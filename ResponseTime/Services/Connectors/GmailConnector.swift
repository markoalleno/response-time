import Foundation
import SwiftData

// MARK: - Gmail Connector

actor GmailConnector {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    
    // Rate limiting
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.1 // 10 requests per second
    
    struct GmailSyncResult: Sendable {
        let messageEvents: [MessageEventData]
        let checkpoint: Date
        let nextPageToken: String?
    }
    
    struct MessageEventData: Sendable {
        let id: String
        let threadId: String
        let timestamp: Date
        let direction: MessageDirection
        let from: String
        let to: [String]
        let subject: String?
        let inReplyTo: String?
        let references: String?
    }
    
    // MARK: - Sync
    
    func sync(
        checkpoint: Date?,
        email: String?,
        maxResults: Int = 500
    ) async throws -> GmailSyncResult {
        let tokens = await getTokens()
        guard let tokens = tokens else {
            throw ConnectorError.notAuthenticated
        }
        
        var accessToken = tokens.accessToken
        if tokens.isExpired {
            let newTokens = try await refreshTokens()
            accessToken = newTokens.accessToken
        }
        
        // Build query for messages
        var query = "in:inbox OR in:sent"
        if let since = checkpoint {
            let timestamp = Int(since.timeIntervalSince1970)
            query += " after:\(timestamp)"
        }
        
        // Fetch message list
        let messages = try await fetchMessageList(
            accessToken: accessToken,
            query: query,
            maxResults: maxResults
        )
        
        // Fetch headers for each message (batched)
        var events: [MessageEventData] = []
        let batches = messages.chunked(into: 50)
        
        for batch in batches {
            let batchEvents = try await fetchMessageHeaders(
                messageIds: batch.map(\.id),
                accessToken: accessToken,
                userEmail: email ?? ""
            )
            events.append(contentsOf: batchEvents)
        }
        
        return GmailSyncResult(
            messageEvents: events,
            checkpoint: Date(),
            nextPageToken: nil
        )
    }
    
    // MARK: - API Calls
    
    private func fetchMessageList(
        accessToken: String,
        query: String,
        maxResults: Int,
        pageToken: String? = nil
    ) async throws -> [(id: String, threadId: String)] {
        await rateLimit()
        
        var urlComponents = URLComponents(string: "\(baseURL)/users/me/messages")!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        urlComponents.queryItems = queryItems
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw ConnectorError.tokenExpired
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ConnectorError.apiError(httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let messages = json?["messages"] as? [[String: Any]] else {
            return []
        }
        
        return messages.compactMap { msg in
            guard let id = msg["id"] as? String,
                  let threadId = msg["threadId"] as? String else { return nil }
            return (id: id, threadId: threadId)
        }
    }
    
    private func fetchMessageHeaders(
        messageIds: [String],
        accessToken: String,
        userEmail: String
    ) async throws -> [MessageEventData] {
        var events: [MessageEventData] = []
        
        for messageId in messageIds {
            await rateLimit()
            
            let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=Message-ID&metadataHeaders=In-Reply-To&metadataHeaders=References")!
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }
                
                if let event = try parseMessageResponse(data: data, userEmail: userEmail) {
                    events.append(event)
                }
            } catch {
                // Skip failed messages
                continue
            }
        }
        
        return events
    }
    
    private func parseMessageResponse(data: Data, userEmail: String) throws -> MessageEventData? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let id = json?["id"] as? String,
              let threadId = json?["threadId"] as? String,
              let internalDate = json?["internalDate"] as? String,
              let timestamp = Double(internalDate).map({ Date(timeIntervalSince1970: $0 / 1000) }),
              let payload = json?["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else {
            return nil
        }
        
        // Parse headers
        var from = ""
        var to: [String] = []
        var subject: String?
        var inReplyTo: String?
        var references: String?
        
        for header in headers {
            guard let name = header["name"] as? String,
                  let value = header["value"] as? String else { continue }
            
            switch name.lowercased() {
            case "from":
                from = extractEmail(from: value)
            case "to":
                to = value.components(separatedBy: ",").map { extractEmail(from: $0) }
            case "subject":
                subject = value
            case "in-reply-to":
                inReplyTo = value
            case "references":
                references = value
            default:
                break
            }
        }
        
        // Determine direction based on whether user sent it
        let isFromUser = from.lowercased().contains(userEmail.lowercased())
        let direction: MessageDirection = isFromUser ? .outbound : .inbound
        
        return MessageEventData(
            id: id,
            threadId: threadId,
            timestamp: timestamp,
            direction: direction,
            from: from,
            to: to,
            subject: subject,
            inReplyTo: inReplyTo,
            references: references
        )
    }
    
    private func extractEmail(from string: String) -> String {
        // Extract email from "Name <email@domain.com>" format
        if let range = string.range(of: "<(.+?)>", options: .regularExpression) {
            return String(string[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        return string.trimmingCharacters(in: .whitespaces)
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
        OAuthService.shared.getStoredTokens(for: .gmail)
    }
    
    @MainActor
    private func refreshTokens() async throws -> OAuthTokens {
        try await OAuthService.shared.refreshTokens(for: .gmail)
    }
}

// MARK: - Connector Error

enum ConnectorError: LocalizedError {
    case notAuthenticated
    case tokenExpired
    case invalidResponse
    case apiError(Int)
    case rateLimited(retryAfter: TimeInterval)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated"
        case .tokenExpired: return "Authentication token expired"
        case .invalidResponse: return "Invalid response from server"
        case .apiError(let code): return "API error: \(code)"
        case .rateLimited(let retry): return "Rate limited. Retry in \(Int(retry))s"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
