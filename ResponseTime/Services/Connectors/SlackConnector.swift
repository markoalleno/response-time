import Foundation
import SwiftData

// MARK: - Slack Connector

actor SlackConnector {
    private let baseURL = "https://slack.com/api"
    
    // Rate limiting - Tier 2 (20+ requests per minute)
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0 // 1 request per second to be safe
    
    struct SlackSyncResult: Sendable {
        let messageEvents: [MessageEventData]
        let checkpoint: Date
    }
    
    struct MessageEventData: Sendable {
        let id: String
        let channelId: String
        let channelType: ChannelType
        let timestamp: Date
        let direction: MessageDirection
        let userId: String
        let threadTs: String?
    }
    
    enum ChannelType: String, Sendable {
        case dm = "dm"
        case mpim = "mpim" // Multi-person DM
        case channel = "channel"
    }
    
    // MARK: - Sync
    
    func sync(
        since: Date?
    ) async throws -> SlackSyncResult {
        let tokens = await getTokens()
        guard let tokens = tokens else {
            throw ConnectorError.notAuthenticated
        }
        
        var accessToken = tokens.accessToken
        if tokens.isExpired {
            let newTokens = try await refreshTokens()
            accessToken = newTokens.accessToken
        }
        
        // Get user's ID
        let userId = try await getCurrentUserId(accessToken: accessToken)
        
        // Get all DM and MPIM channels
        let channels = try await getConversations(accessToken: accessToken)
        
        // Fetch messages from each channel
        var allEvents: [MessageEventData] = []
        
        for channel in channels {
            let events = try await getChannelHistory(
                channelId: channel.id,
                channelType: channel.type,
                accessToken: accessToken,
                since: since,
                currentUserId: userId
            )
            allEvents.append(contentsOf: events)
        }
        
        return SlackSyncResult(
            messageEvents: allEvents,
            checkpoint: Date()
        )
    }
    
    // MARK: - API Calls
    
    private func getCurrentUserId(accessToken: String) async throws -> String {
        await rateLimit()
        
        var request = URLRequest(url: URL(string: "\(baseURL)/auth.test")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let ok = json?["ok"] as? Bool, ok,
              let userId = json?["user_id"] as? String else {
            throw ConnectorError.invalidResponse
        }
        
        return userId
    }
    
    private func getConversations(accessToken: String) async throws -> [(id: String, type: ChannelType)] {
        await rateLimit()
        
        var urlComponents = URLComponents(string: "\(baseURL)/conversations.list")!
        urlComponents.queryItems = [
            URLQueryItem(name: "types", value: "im,mpim"),
            URLQueryItem(name: "limit", value: "200")
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let ok = json?["ok"] as? Bool, ok,
              let channels = json?["channels"] as? [[String: Any]] else {
            if let error = json?["error"] as? String {
                if error == "ratelimited" {
                    throw ConnectorError.rateLimited(retryAfter: 60)
                }
            }
            return []
        }
        
        return channels.compactMap { channel in
            guard let id = channel["id"] as? String else { return nil }
            let isIm = channel["is_im"] as? Bool ?? false
            let isMpim = channel["is_mpim"] as? Bool ?? false
            
            let type: ChannelType
            if isIm {
                type = .dm
            } else if isMpim {
                type = .mpim
            } else {
                type = .channel
            }
            
            return (id: id, type: type)
        }
    }
    
    private func getChannelHistory(
        channelId: String,
        channelType: ChannelType,
        accessToken: String,
        since: Date?,
        currentUserId: String
    ) async throws -> [MessageEventData] {
        await rateLimit()
        
        var urlComponents = URLComponents(string: "\(baseURL)/conversations.history")!
        var queryItems = [
            URLQueryItem(name: "channel", value: channelId),
            URLQueryItem(name: "limit", value: "100")
        ]
        
        if let since = since {
            queryItems.append(URLQueryItem(name: "oldest", value: String(since.timeIntervalSince1970)))
        }
        
        urlComponents.queryItems = queryItems
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let ok = json?["ok"] as? Bool, ok,
              let messages = json?["messages"] as? [[String: Any]] else {
            return []
        }
        
        return messages.compactMap { msg -> MessageEventData? in
            guard let ts = msg["ts"] as? String,
                  let userId = msg["user"] as? String else {
                return nil
            }
            
            // Skip bot messages
            if msg["bot_id"] != nil { return nil }
            
            // Parse timestamp (Slack uses seconds.microseconds format)
            guard let timestamp = Double(ts).map({ Date(timeIntervalSince1970: $0) }) else {
                return nil
            }
            
            // Determine direction
            let direction: MessageDirection = userId == currentUserId ? .outbound : .inbound
            
            return MessageEventData(
                id: ts,
                channelId: channelId,
                channelType: channelType,
                timestamp: timestamp,
                direction: direction,
                userId: userId,
                threadTs: msg["thread_ts"] as? String
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
        OAuthService.shared.getStoredTokens(for: .slack)
    }
    
    @MainActor
    private func refreshTokens() async throws -> OAuthTokens {
        try await OAuthService.shared.refreshTokens(for: .slack)
    }
}
