import Foundation
import SwiftData

// MARK: - Microsoft Graph Connector

actor MicrosoftConnector {
    private let baseURL = "https://graph.microsoft.com/v1.0"
    
    // Rate limiting
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.05 // 20 requests per second
    
    struct GraphSyncResult: Sendable {
        let messageEvents: [MessageEventData]
        let checkpoint: Date
        let deltaLink: String?
    }
    
    struct MessageEventData: Sendable {
        let id: String
        let conversationId: String
        let timestamp: Date
        let direction: MessageDirection
        let from: String
        let to: [String]
        let subject: String?
        let inReplyTo: String?
    }
    
    // MARK: - Sync
    
    func sync(
        checkpoint: Date?,
        deltaLink: String?,
        email: String?
    ) async throws -> GraphSyncResult {
        let tokens = await getTokens()
        guard let tokens = tokens else {
            throw ConnectorError.notAuthenticated
        }
        
        var accessToken = tokens.accessToken
        if tokens.isExpired {
            let newTokens = try await refreshTokens()
            accessToken = newTokens.accessToken
        }
        
        // Use delta query if we have a delta link
        if let deltaLink = deltaLink {
            return try await fetchDelta(deltaLink: deltaLink, accessToken: accessToken, userEmail: email ?? "")
        }
        
        // Otherwise, do initial sync
        return try await initialSync(accessToken: accessToken, since: checkpoint, userEmail: email ?? "")
    }
    
    // MARK: - Initial Sync
    
    private func initialSync(
        accessToken: String,
        since: Date?,
        userEmail: String
    ) async throws -> GraphSyncResult {
        var allEvents: [MessageEventData] = []
        var nextLink: String? = nil
        var deltaLink: String? = nil
        
        // Build initial URL
        let urlString = "\(baseURL)/me/mailFolders/inbox/messages/delta"
        var urlComponents = URLComponents(string: urlString)!
        
        var queryItems = [
            URLQueryItem(name: "$select", value: "id,conversationId,receivedDateTime,from,toRecipients,subject,internetMessageHeaders"),
            URLQueryItem(name: "$top", value: "100")
        ]
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "$filter", value: "receivedDateTime ge \(formatter.string(from: since))"))
        }
        
        urlComponents.queryItems = queryItems
        
        var currentURL: URL? = urlComponents.url
        
        repeat {
            guard let url = currentURL else { break }
            
            await rateLimit()
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConnectorError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 {
                throw ConnectorError.tokenExpired
            }
            
            if httpResponse.statusCode == 429 {
                let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            }
            
            guard httpResponse.statusCode == 200 else {
                throw ConnectorError.apiError(httpResponse.statusCode)
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let messages = json?["value"] as? [[String: Any]] {
                let events = parseMessages(messages, userEmail: userEmail)
                allEvents.append(contentsOf: events)
            }
            
            nextLink = json?["@odata.nextLink"] as? String
            deltaLink = json?["@odata.deltaLink"] as? String
            
            if let next = nextLink {
                currentURL = URL(string: next)
            } else {
                currentURL = nil
            }
            
        } while currentURL != nil
        
        // Also fetch sent items
        let sentEvents = try await fetchSentItems(accessToken: accessToken, since: since, userEmail: userEmail)
        allEvents.append(contentsOf: sentEvents)
        
        return GraphSyncResult(
            messageEvents: allEvents,
            checkpoint: Date(),
            deltaLink: deltaLink
        )
    }
    
    private func fetchSentItems(
        accessToken: String,
        since: Date?,
        userEmail: String
    ) async throws -> [MessageEventData] {
        var urlComponents = URLComponents(string: "\(baseURL)/me/mailFolders/sentitems/messages")!
        
        var queryItems = [
            URLQueryItem(name: "$select", value: "id,conversationId,sentDateTime,from,toRecipients,subject"),
            URLQueryItem(name: "$top", value: "100"),
            URLQueryItem(name: "$orderby", value: "sentDateTime desc")
        ]
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "$filter", value: "sentDateTime ge \(formatter.string(from: since))"))
        }
        
        urlComponents.queryItems = queryItems
        
        await rateLimit()
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let messages = json?["value"] as? [[String: Any]] else {
            return []
        }
        
        return parseMessages(messages, userEmail: userEmail, forcedDirection: .outbound)
    }
    
    // MARK: - Delta Sync
    
    private func fetchDelta(
        deltaLink: String,
        accessToken: String,
        userEmail: String
    ) async throws -> GraphSyncResult {
        await rateLimit()
        
        var request = URLRequest(url: URL(string: deltaLink)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.invalidResponse
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        var events: [MessageEventData] = []
        if let messages = json?["value"] as? [[String: Any]] {
            events = parseMessages(messages, userEmail: userEmail)
        }
        
        let newDeltaLink = json?["@odata.deltaLink"] as? String
        
        return GraphSyncResult(
            messageEvents: events,
            checkpoint: Date(),
            deltaLink: newDeltaLink
        )
    }
    
    // MARK: - Parsing
    
    private func parseMessages(
        _ messages: [[String: Any]],
        userEmail: String,
        forcedDirection: MessageDirection? = nil
    ) -> [MessageEventData] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return messages.compactMap { msg -> MessageEventData? in
            guard let id = msg["id"] as? String,
                  let conversationId = msg["conversationId"] as? String else {
                return nil
            }
            
            // Parse timestamp
            let dateString = msg["receivedDateTime"] as? String ?? msg["sentDateTime"] as? String ?? ""
            guard let timestamp = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
                return nil
            }
            
            // Parse from
            var from = ""
            if let fromObj = msg["from"] as? [String: Any],
               let emailAddress = fromObj["emailAddress"] as? [String: Any] {
                from = emailAddress["address"] as? String ?? ""
            }
            
            // Parse to
            var to: [String] = []
            if let toRecipients = msg["toRecipients"] as? [[String: Any]] {
                to = toRecipients.compactMap { recipient in
                    (recipient["emailAddress"] as? [String: Any])?["address"] as? String
                }
            }
            
            // Determine direction
            let direction: MessageDirection
            if let forced = forcedDirection {
                direction = forced
            } else {
                direction = from.lowercased() == userEmail.lowercased() ? .outbound : .inbound
            }
            
            return MessageEventData(
                id: id,
                conversationId: conversationId,
                timestamp: timestamp,
                direction: direction,
                from: from,
                to: to,
                subject: msg["subject"] as? String,
                inReplyTo: nil
            )
        }
    }
    
    private func rateLimit() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                try? await Task.sleep(for: .milliseconds(Int((minRequestInterval - elapsed) * 1000)))
            }
        }
        lastRequestTime = Date()
    }
    
    @MainActor
    private func getTokens() -> OAuthTokens? {
        OAuthService.shared.getStoredTokens(for: .outlook)
    }
    
    @MainActor
    private func refreshTokens() async throws -> OAuthTokens {
        try await OAuthService.shared.refreshTokens(for: .outlook)
    }
}
