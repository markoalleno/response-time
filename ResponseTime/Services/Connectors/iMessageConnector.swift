import Foundation
import SQLite3

// MARK: - iMessage Connector

actor iMessageConnector {
    
    // Core Data epoch: 2001-01-01 00:00:00 UTC
    static let coreDataEpoch: TimeInterval = 978307200
    
    private var dbPath: String {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path
        #else
        "" // iMessage not available on iOS
        #endif
    }
    
    // MARK: - Database Connection
    
    private func openDatabase() throws -> OpaquePointer {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        
        if result != SQLITE_OK {
            let errorCode = result
            sqlite3_close(db)
            
            // SQLITE_CANTOPEN (14) usually means permission denied or file not found
            if errorCode == SQLITE_CANTOPEN {
                // Check if file exists at all
                if FileManager.default.fileExists(atPath: dbPath) {
                    // File exists but can't open = permission issue
                    throw iMessageError.permissionDenied
                } else {
                    throw iMessageError.databaseNotFound
                }
            }
            throw iMessageError.databaseOpenFailed
        }
        
        guard let database = db else {
            throw iMessageError.databaseOpenFailed
        }
        
        // Verify we can actually read by doing a quick query
        var stmt: OpaquePointer?
        let testQuery = "SELECT 1 FROM message LIMIT 1"
        if sqlite3_prepare_v2(database, testQuery, -1, &stmt, nil) != SQLITE_OK {
            sqlite3_close(database)
            throw iMessageError.permissionDenied
        }
        sqlite3_finalize(stmt)
        
        return database
    }
    
    // MARK: - Conversation Data
    
    struct ConversationData: Sendable, Identifiable {
        let id: String // chat ROWID as string
        let chatIdentifier: String
        let displayName: String?
        let isGroupChat: Bool
        let participantCount: Int
        let participants: [ParticipantData]
        let messageCount: Int
        let lastMessageDate: Date?
        
        // Response time stats
        var medianResponseTime: TimeInterval?
        var meanResponseTime: TimeInterval?
        var fastestResponse: TimeInterval?
        var slowestResponse: TimeInterval?
        var responseCount: Int = 0
        var pendingResponse: Bool = false
    }
    
    struct ParticipantData: Sendable, Identifiable, Hashable {
        let id: String // handle ROWID as string
        let identifier: String // phone number or email
        let service: String // iMessage or SMS
        
        var displayIdentifier: String {
            // Clean up the identifier for display
            if identifier.hasPrefix("+") {
                return formatPhoneNumber(identifier)
            }
            return identifier
        }
        
        private func formatPhoneNumber(_ phone: String) -> String {
            let digits = phone.filter { $0.isNumber }
            guard digits.count == 11, digits.hasPrefix("1") else {
                return phone
            }
            let area = digits.dropFirst().prefix(3)
            let prefix = digits.dropFirst(4).prefix(3)
            let line = digits.dropFirst(7)
            return "(\(area)) \(prefix)-\(line)"
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: ParticipantData, rhs: ParticipantData) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct ResponseTimeEntry: Sendable {
        let inboundTimestamp: Date
        let outboundTimestamp: Date
        let latencySeconds: TimeInterval
        let participant: String
    }
    
    // MARK: - Fetch All Conversations
    
    func fetchAllConversations(days: Int = 30) async throws -> [ConversationData] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        
        // Get all chats with participant counts and recent activity
        let query = """
            SELECT 
                c.ROWID as chat_id,
                c.chat_identifier,
                c.display_name,
                COUNT(DISTINCT chj.handle_id) as participant_count,
                MAX(m.date) as last_message_date,
                COUNT(m.ROWID) as message_count
            FROM chat c
            LEFT JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
            LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
            LEFT JOIN message m ON cmj.message_id = m.ROWID
            WHERE m.date > \(coreDataNanos) OR m.date IS NULL
            GROUP BY c.ROWID
            HAVING message_count > 0
            ORDER BY last_message_date DESC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var conversations: [ConversationData] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let chatId = sqlite3_column_int64(statement, 0)
            
            guard let identifierRaw = sqlite3_column_text(statement, 1) else { continue }
            let identifier = String(cString: identifierRaw)
            
            let displayNameRaw = sqlite3_column_text(statement, 2)
            let displayName = displayNameRaw.map { String(cString: $0) }
            
            let participantCount = Int(sqlite3_column_int(statement, 3))
            let lastDateNanos = sqlite3_column_int64(statement, 4)
            let messageCount = Int(sqlite3_column_int(statement, 5))
            
            let lastDate = lastDateNanos > 0 
                ? Date(timeIntervalSince1970: Self.coreDataEpoch + Double(lastDateNanos) / 1_000_000_000)
                : nil
            
            // Group chat if: has display name OR has multiple participants OR identifier contains "chat"
            let isGroup = (displayName != nil && !displayName!.isEmpty) || 
                         participantCount > 1 || 
                         identifier.hasPrefix("chat")
            
            // Get participants for this chat
            let participants = try await fetchParticipants(for: Int(chatId), db: db)
            
            // Calculate response times for this conversation
            let responseStats = try await calculateConversationResponseTimes(
                chatId: Int(chatId),
                days: days,
                db: db
            )
            
            var conversation = ConversationData(
                id: String(chatId),
                chatIdentifier: identifier,
                displayName: displayName,
                isGroupChat: isGroup,
                participantCount: max(participantCount, participants.count),
                participants: participants,
                messageCount: messageCount,
                lastMessageDate: lastDate
            )
            
            conversation.medianResponseTime = responseStats.median
            conversation.meanResponseTime = responseStats.mean
            conversation.fastestResponse = responseStats.fastest
            conversation.slowestResponse = responseStats.slowest
            conversation.responseCount = responseStats.count
            conversation.pendingResponse = responseStats.hasPending
            
            conversations.append(conversation)
        }
        
        return conversations
    }
    
    // MARK: - Fetch Participants
    
    private func fetchParticipants(for chatId: Int, db: OpaquePointer) async throws -> [ParticipantData] {
        let query = """
            SELECT h.ROWID, h."id", h.service
            FROM handle h
            JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            WHERE chj.chat_id = \(chatId)
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var participants: [ParticipantData] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let handleId = sqlite3_column_int64(statement, 0)
            
            guard let identifierRaw = sqlite3_column_text(statement, 1) else { continue }
            let identifier = String(cString: identifierRaw)
            
            let serviceRaw = sqlite3_column_text(statement, 2)
            let service = serviceRaw.map { String(cString: $0) } ?? "iMessage"
            
            participants.append(ParticipantData(
                id: String(handleId),
                identifier: identifier,
                service: service
            ))
        }
        
        return participants
    }
    
    // MARK: - Calculate Response Times
    
    struct ResponseStats: Sendable {
        var median: TimeInterval?
        var mean: TimeInterval?
        var fastest: TimeInterval?
        var slowest: TimeInterval?
        var count: Int = 0
        var hasPending: Bool = false
    }
    
    private func calculateConversationResponseTimes(chatId: Int, days: Int, db: OpaquePointer) async throws -> ResponseStats {
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        
        // Get messages for this chat ordered by date
        let query = """
            SELECT m.date, m.is_from_me
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            WHERE cmj.chat_id = \(chatId)
              AND m.date > \(coreDataNanos)
              AND m.item_type = 0
            ORDER BY m.date ASC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var messages: [(date: Date, isFromMe: Bool)] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let dateNanos = sqlite3_column_int64(statement, 0)
            let isFromMe = sqlite3_column_int(statement, 1) == 1
            
            let date = Date(timeIntervalSince1970: Self.coreDataEpoch + Double(dateNanos) / 1_000_000_000)
            messages.append((date, isFromMe))
        }
        
        // Calculate response times
        var responseTimes: [TimeInterval] = []
        var lastInbound: Date?
        var hasPending = false
        
        for msg in messages {
            if !msg.isFromMe {
                // Inbound message
                lastInbound = msg.date
            } else if let inbound = lastInbound {
                // Outbound response
                let latency = msg.date.timeIntervalSince(inbound)
                // Only count reasonable response times (< 7 days, > 0)
                if latency > 0 && latency < 7 * 24 * 3600 {
                    responseTimes.append(latency)
                }
                lastInbound = nil
            }
        }
        
        // Check if last message was inbound (pending response)
        if let last = messages.last, !last.isFromMe {
            hasPending = true
        }
        
        guard !responseTimes.isEmpty else {
            return ResponseStats(hasPending: hasPending)
        }
        
        let sorted = responseTimes.sorted()
        let median = sorted[sorted.count / 2]
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let fastest = sorted.first
        let slowest = sorted.last
        
        return ResponseStats(
            median: median,
            mean: mean,
            fastest: fastest,
            slowest: slowest,
            count: responseTimes.count,
            hasPending: hasPending
        )
    }
    
    // MARK: - Get Contact Stats
    
    struct ContactStats: Sendable, Identifiable {
        let id: String
        let identifier: String
        let displayName: String?
        let service: String
        let conversationCount: Int
        let totalMessages: Int
        let medianResponseTime: TimeInterval?
        let meanResponseTime: TimeInterval?
        let responseCount: Int
        let pendingCount: Int
        let lastMessageDate: Date?
    }
    
    func fetchContactStats(days: Int = 30) async throws -> [ContactStats] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        
        // Get all unique handles with stats
        let query = """
            SELECT 
                h.ROWID as handle_id,
                h."id" as identifier,
                h.service,
                COUNT(DISTINCT cmj.chat_id) as conversation_count,
                COUNT(m.ROWID) as message_count,
                MAX(m.date) as last_date
            FROM handle h
            JOIN message m ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            WHERE m.date > \(coreDataNanos)
            GROUP BY h.ROWID
            ORDER BY last_date DESC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var contacts: [ContactStats] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let handleId = sqlite3_column_int64(statement, 0)
            
            guard let identifierRaw = sqlite3_column_text(statement, 1) else { continue }
            let identifier = String(cString: identifierRaw)
            
            let serviceRaw = sqlite3_column_text(statement, 2)
            let service = serviceRaw.map { String(cString: $0) } ?? "iMessage"
            
            let conversationCount = Int(sqlite3_column_int(statement, 3))
            let messageCount = Int(sqlite3_column_int(statement, 4))
            let lastDateNanos = sqlite3_column_int64(statement, 5)
            
            let lastDate = lastDateNanos > 0
                ? Date(timeIntervalSince1970: Self.coreDataEpoch + Double(lastDateNanos) / 1_000_000_000)
                : nil
            
            // Get response time stats for this handle
            let responseStats = try await calculateHandleResponseTimes(
                handleId: Int(handleId),
                days: days,
                db: db
            )
            
            contacts.append(ContactStats(
                id: String(handleId),
                identifier: identifier,
                displayName: nil, // Would need AddressBook for this
                service: service,
                conversationCount: conversationCount,
                totalMessages: messageCount,
                medianResponseTime: responseStats.median,
                meanResponseTime: responseStats.mean,
                responseCount: responseStats.count,
                pendingCount: responseStats.hasPending ? 1 : 0,
                lastMessageDate: lastDate
            ))
        }
        
        return contacts
    }
    
    private func calculateHandleResponseTimes(handleId: Int, days: Int, db: OpaquePointer) async throws -> ResponseStats {
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        
        // Get messages with this handle, ordered by date
        let query = """
            SELECT m.date, m.is_from_me
            FROM message m
            WHERE m.handle_id = \(handleId)
              AND m.date > \(coreDataNanos)
              AND m.item_type = 0
            ORDER BY m.date ASC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var messages: [(date: Date, isFromMe: Bool)] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let dateNanos = sqlite3_column_int64(statement, 0)
            let isFromMe = sqlite3_column_int(statement, 1) == 1
            
            let date = Date(timeIntervalSince1970: Self.coreDataEpoch + Double(dateNanos) / 1_000_000_000)
            messages.append((date, isFromMe))
        }
        
        // Calculate response times
        var responseTimes: [TimeInterval] = []
        var lastInbound: Date?
        var hasPending = false
        
        for msg in messages {
            if !msg.isFromMe {
                lastInbound = msg.date
            } else if let inbound = lastInbound {
                let latency = msg.date.timeIntervalSince(inbound)
                if latency > 0 && latency < 7 * 24 * 3600 {
                    responseTimes.append(latency)
                }
                lastInbound = nil
            }
        }
        
        if let last = messages.last, !last.isFromMe {
            hasPending = true
        }
        
        guard !responseTimes.isEmpty else {
            return ResponseStats(hasPending: hasPending)
        }
        
        let sorted = responseTimes.sorted()
        return ResponseStats(
            median: sorted[sorted.count / 2],
            mean: sorted.reduce(0, +) / Double(sorted.count),
            fastest: sorted.first,
            slowest: sorted.last,
            count: sorted.count,
            hasPending: hasPending
        )
    }
    
    // MARK: - Legacy Compatibility
    
    struct iMessageSyncResult: Sendable {
        let messageEvents: [MessageEventData]
        let checkpoint: Date
    }
    
    struct MessageEventData: Sendable {
        let id: String
        let handleId: String
        let timestamp: Date
        let direction: MessageDirection
        let participantId: String
        let threadOriginatorGuid: String?
    }
    
    // MARK: - Sync (Legacy)
    
    func sync(since checkpoint: Date? = nil, limit: Int = 5000) async throws -> iMessageSyncResult {
        debugLog("🔌 [CONNECTOR] Opening database at \(dbPath)...")
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        
        var query = """
            SELECT 
                m.guid,
                m.handle_id,
                m.date,
                m.is_from_me,
                h."id" AS participant_id,
                m.thread_originator_guid
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.item_type = 0
        """
        
        if let since = checkpoint {
            let coreDataNanos = Int64((since.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
            query += " AND m.date > \(coreDataNanos)"
            debugLog("🔌 [CONNECTOR] Fetching messages since \(since)")
        } else {
            debugLog("🔌 [CONNECTOR] Fetching ALL messages (no checkpoint)")
        }
        
        query += " ORDER BY m.date DESC LIMIT \(limit)"
        debugLog("🔌 [CONNECTOR] Query limit: \(limit)")
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var events: [MessageEventData] = []
        var inboundCount = 0
        var outboundCount = 0
        var unknownParticipantCount = 0
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let guidRaw = sqlite3_column_text(statement, 0) else { continue }
            let guid = String(cString: guidRaw)
            
            let handleId = sqlite3_column_int64(statement, 1)
            let dateNanos = sqlite3_column_int64(statement, 2)
            let isFromMe = sqlite3_column_int(statement, 3) == 1
            
            let participantRaw = sqlite3_column_text(statement, 4)
            let participant = participantRaw.map { String(cString: $0) } ?? "unknown"
            
            if participant == "unknown" {
                unknownParticipantCount += 1
            }
            
            let threadOriginatorRaw = sqlite3_column_text(statement, 5)
            let threadOriginator = threadOriginatorRaw.map { String(cString: $0) }
            
            let timestamp = Date(timeIntervalSince1970: Self.coreDataEpoch + Double(dateNanos) / 1_000_000_000)
            
            let direction: MessageDirection = isFromMe ? .outbound : .inbound
            if direction == .inbound {
                inboundCount += 1
            } else {
                outboundCount += 1
            }
            
            let event = MessageEventData(
                id: guid,
                handleId: String(handleId),
                timestamp: timestamp,
                direction: direction,
                participantId: participant,
                threadOriginatorGuid: threadOriginator
            )
            events.append(event)
        }
        
        debugLog("🔌 [CONNECTOR] Fetched \(events.count) events: 📥 \(inboundCount) inbound, 📤 \(outboundCount) outbound")
        if unknownParticipantCount > 0 {
            debugLog("⚠️  [CONNECTOR] \(unknownParticipantCount) messages with unknown participant (group chats?)")
        }
        
        return iMessageSyncResult(
            messageEvents: events,
            checkpoint: Date()
        )
    }
    
    // MARK: - Get Recent Response Times
    
    func getRecentResponseTimes(days: Int = 7) async throws -> [ResponseTimeData] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        
        let query = """
            SELECT 
                m.guid,
                m.handle_id,
                h."id" AS participant_id,
                m.date,
                m.is_from_me,
                m.thread_originator_guid
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.date > \(coreDataNanos)
              AND m.item_type = 0
              AND h."id" IS NOT NULL
            ORDER BY m.handle_id, m.date ASC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        var messagesByHandle: [String: [(id: String, date: Date, isFromMe: Bool)]] = [:]
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let guidRaw = sqlite3_column_text(statement, 0),
                  let participantRaw = sqlite3_column_text(statement, 2) else { continue }
            
            let guid = String(cString: guidRaw)
            let participant = String(cString: participantRaw)
            let dateNanos = sqlite3_column_int64(statement, 3)
            let isFromMe = sqlite3_column_int(statement, 4) == 1
            
            let timestamp = Date(timeIntervalSince1970: Self.coreDataEpoch + Double(dateNanos) / 1_000_000_000)
            
            messagesByHandle[participant, default: []].append((id: guid, date: timestamp, isFromMe: isFromMe))
        }
        
        var responseTimes: [ResponseTimeData] = []
        
        for (participant, messages) in messagesByHandle {
            var lastInbound: Date?
            
            for msg in messages {
                if !msg.isFromMe {
                    lastInbound = msg.date
                } else if let inbound = lastInbound {
                    let latency = msg.date.timeIntervalSince(inbound)
                    
                    if latency > 0 && latency < 7 * 24 * 3600 {
                        responseTimes.append(ResponseTimeData(
                            participant: participant,
                            inboundTime: inbound,
                            outboundTime: msg.date,
                            latencySeconds: latency
                        ))
                    }
                    lastInbound = nil
                }
            }
        }
        
        return responseTimes
    }
    
    /// Gets aggregated stats for the menu bar
    func getQuickStats(days: Int = 7) async throws -> iMessageQuickStats {
        let responseTimes = try await getRecentResponseTimes(days: days)
        
        guard !responseTimes.isEmpty else {
            return iMessageQuickStats(
                medianLatency: nil,
                meanLatency: nil,
                responseCount: 0,
                pendingResponses: 0
            )
        }
        
        let latencies = responseTimes.map(\.latencySeconds).sorted()
        let median = latencies[latencies.count / 2]
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        
        let pending = try await countPendingResponses()
        
        return iMessageQuickStats(
            medianLatency: median,
            meanLatency: mean,
            responseCount: responseTimes.count,
            pendingResponses: pending
        )
    }
    
    /// Counts messages received but not yet replied to
    private func countPendingResponses() async throws -> Int {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        
        let query = """
            WITH ranked AS (
                SELECT 
                    m.handle_id,
                    m.is_from_me,
                    m.date,
                    ROW_NUMBER() OVER (PARTITION BY m.handle_id ORDER BY m.date DESC) as rn
                FROM message m
                WHERE m.item_type = 0
                  AND m.handle_id > 0
            )
            SELECT COUNT(*) FROM ranked
            WHERE rn = 1 AND is_from_me = 0
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw iMessageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
    
    // MARK: - Summary Stats
    
    struct OverallStats: Sendable {
        let totalConversations: Int
        let groupChats: Int
        let directMessages: Int
        let totalContacts: Int
        let totalResponses: Int
        let pendingResponses: Int
        let medianResponseTime: TimeInterval?
        let meanResponseTime: TimeInterval?
        let fastestResponse: TimeInterval?
        let slowestResponse: TimeInterval?
        
        static let empty = OverallStats(
            totalConversations: 0,
            groupChats: 0,
            directMessages: 0,
            totalContacts: 0,
            totalResponses: 0,
            pendingResponses: 0,
            medianResponseTime: nil,
            meanResponseTime: nil,
            fastestResponse: nil,
            slowestResponse: nil
        )
    }
    
    func getOverallStats(days: Int = 30) async throws -> OverallStats {
        let conversations = try await fetchAllConversations(days: days)
        
        let groupChats = conversations.filter { $0.isGroupChat }.count
        let directMessages = conversations.count - groupChats
        
        let allResponseTimes = conversations.compactMap { $0.medianResponseTime }
        let totalResponses = conversations.reduce(0) { $0 + $1.responseCount }
        let pendingResponses = conversations.filter { $0.pendingResponse }.count
        
        let contacts = try await fetchContactStats(days: days)
        
        guard !allResponseTimes.isEmpty else {
            return OverallStats(
                totalConversations: conversations.count,
                groupChats: groupChats,
                directMessages: directMessages,
                totalContacts: contacts.count,
                totalResponses: totalResponses,
                pendingResponses: pendingResponses,
                medianResponseTime: nil,
                meanResponseTime: nil,
                fastestResponse: nil,
                slowestResponse: nil
            )
        }
        
        let sorted = allResponseTimes.sorted()
        
        return OverallStats(
            totalConversations: conversations.count,
            groupChats: groupChats,
            directMessages: directMessages,
            totalContacts: contacts.count,
            totalResponses: totalResponses,
            pendingResponses: pendingResponses,
            medianResponseTime: sorted[sorted.count / 2],
            meanResponseTime: sorted.reduce(0, +) / Double(sorted.count),
            fastestResponse: sorted.first,
            slowestResponse: sorted.last
        )
    }
}

// MARK: - Data Types

struct ResponseTimeData: Sendable {
    let participant: String
    let inboundTime: Date
    let outboundTime: Date
    let latencySeconds: TimeInterval
}

struct iMessageQuickStats: Sendable {
    let medianLatency: TimeInterval?
    let meanLatency: TimeInterval?
    let responseCount: Int
    let pendingResponses: Int
    
    var formattedMedian: String {
        guard let latency = medianLatency else { return "--" }
        return formatDurationCompact(latency)
    }
    
    var formattedMean: String {
        guard let latency = meanLatency else { return "--" }
        return formatDurationCompact(latency)
    }
}

// MARK: - Errors

enum iMessageError: LocalizedError {
    case databaseNotFound
    case databaseOpenFailed
    case permissionDenied
    case queryFailed(String)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "iMessage database not found at ~/Library/Messages/chat.db"
        case .databaseOpenFailed:
            return "Failed to open iMessage database"
        case .permissionDenied:
            return "Permission denied. Grant Full Disk Access to Response Time in System Settings > Privacy & Security > Full Disk Access"
        case .queryFailed(let msg):
            return "Database query failed: \(msg)"
        case .noData:
            return "No iMessage data found"
        }
    }
}

// MARK: - Formatting Helper

private func formatDurationCompact(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds))s"
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return secs > 0 ? "\(minutes)m\(secs)s" : "\(minutes)m"
    } else if seconds < 86400 {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h\(minutes)m"
    } else {
        let days = Int(seconds / 86400)
        let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        if hours == 0 {
            return "\(days)d"
        }
        return "\(days)d\(hours)h"
    }
}
