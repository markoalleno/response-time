import Foundation
import SwiftData

// MARK: - Sync Coordinator

@Observable
@MainActor
class SyncCoordinator {
    static let shared = SyncCoordinator()
    
    // State
    var isSyncing = false
    var syncProgress: Double = 0
    var currentPlatform: Platform?
    var lastSyncDate: Date?
    var lastError: SyncError?
    
    // Connectors
    private let gmailConnector = GmailConnector()
    private let microsoftConnector = MicrosoftConnector()
    private let slackConnector = SlackConnector()
    private let imessageService = iMessageConnector()
    
    enum SyncError: LocalizedError, Sendable {
        case noAccounts
        case authExpired(Platform)
        case networkError(String)
        case rateLimited(Platform, TimeInterval)
        case partialFailure(String)
        case permissionDenied(Platform)
        
        var errorDescription: String? {
            switch self {
            case .noAccounts: return "No accounts connected"
            case .authExpired(let p): return "\(p.displayName) authentication expired"
            case .networkError(let msg): return "Network error: \(msg)"
            case .rateLimited(let p, let t): return "\(p.displayName) rate limited. Retry in \(Int(t))s"
            case .partialFailure(let msg): return "Partial sync failure: \(msg)"
            case .permissionDenied(let p): return "\(p.displayName) permission denied. Check System Preferences."
            }
        }
    }
    
    // MARK: - Sync All
    
    func syncAll(modelContext: ModelContext) async throws {
        let accountsDescriptor = FetchDescriptor<SourceAccount>(
            predicate: #Predicate { $0.isEnabled }
        )
        let accounts = try modelContext.fetch(accountsDescriptor)
        
        guard !accounts.isEmpty else {
            throw SyncError.noAccounts
        }
        
        isSyncing = true
        syncProgress = 0
        lastError = nil
        defer {
            isSyncing = false
            currentPlatform = nil
        }
        
        let step = 1.0 / Double(accounts.count)
        var errors: [String] = []
        
        for (index, account) in accounts.enumerated() {
            currentPlatform = account.platform
            
            do {
                try await syncAccount(account, modelContext: modelContext)
            } catch {
                errors.append("\(account.platform.displayName): \(error.localizedDescription)")
                account.lastSyncError = error.localizedDescription
            }
            
            syncProgress = Double(index + 1) * step
        }
        
        lastSyncDate = Date()
        
        if !errors.isEmpty {
            lastError = .partialFailure(errors.joined(separator: "; "))
        }
    }
    
    // MARK: - Sync Single Account
    
    func syncAccount(_ account: SourceAccount, modelContext: ModelContext) async throws {
        switch account.platform {
        case .gmail:
            try await syncGmail(account, modelContext: modelContext)
        case .outlook:
            try await syncOutlook(account, modelContext: modelContext)
        case .slack:
            try await syncSlack(account, modelContext: modelContext)
        case .imessage:
            try await syncIMessage(account, modelContext: modelContext)
        }
        
        account.syncCheckpoint = Date()
        account.lastSyncError = nil
        account.updatedAt = Date()
        
        try modelContext.save()
    }
    
    // MARK: - Platform-specific Sync
    
    private func syncGmail(_ account: SourceAccount, modelContext: ModelContext) async throws {
        let checkpoint = account.syncCheckpoint
        let email = account.email
        
        let result = try await gmailConnector.sync(
            checkpoint: checkpoint,
            email: email,
            maxResults: 500
        )
        
        await MainActor.run {
            processGmailEvents(
                result.messageEvents,
                account: account,
                modelContext: modelContext
            )
            
            computeResponseWindows(for: account, modelContext: modelContext)
        }
    }
    
    private func syncOutlook(_ account: SourceAccount, modelContext: ModelContext) async throws {
        let checkpoint = account.syncCheckpoint
        let deltaLink = account.deltaLink
        let email = account.email
        
        let result = try await microsoftConnector.sync(
            checkpoint: checkpoint,
            deltaLink: deltaLink,
            email: email
        )
        
        await MainActor.run {
            account.deltaLink = result.deltaLink
            
            processMicrosoftEvents(
                result.messageEvents,
                account: account,
                modelContext: modelContext
            )
            
            computeResponseWindows(for: account, modelContext: modelContext)
        }
    }
    
    private func syncSlack(_ account: SourceAccount, modelContext: ModelContext) async throws {
        let checkpoint = account.syncCheckpoint
        
        let result = try await slackConnector.sync(
            since: checkpoint
        )
        
        await MainActor.run {
            processSlackEvents(
                result.messageEvents,
                account: account,
                modelContext: modelContext
            )
            
            computeResponseWindows(for: account, modelContext: modelContext)
        }
    }
    
    private func syncIMessage(_ account: SourceAccount, modelContext: ModelContext) async throws {
        let checkpoint = account.syncCheckpoint
        
        do {
            let result = try await imessageService.sync(since: checkpoint, limit: 5000)
            
            await MainActor.run {
                processIMessageEvents(
                    result.messageEvents,
                    account: account,
                    modelContext: modelContext
                )
                
                computeResponseWindows(for: account, modelContext: modelContext)
            }
        } catch let error as iMessageError {
            switch error {
            case .databaseNotFound, .databaseOpenFailed, .permissionDenied:
                throw SyncError.permissionDenied(.imessage)
            case .queryFailed(let msg):
                throw SyncError.networkError(msg)
            case .noData:
                // Not an error, just no data
                break
            }
        }
    }
    
    // MARK: - Process Gmail Events
    
    private func processGmailEvents(
        _ events: [GmailConnector.MessageEventData],
        account: SourceAccount,
        modelContext: ModelContext
    ) {
        var threadGroups: [String: [GmailConnector.MessageEventData]] = [:]
        for event in events {
            threadGroups[event.threadId, default: []].append(event)
        }
        
        for (threadId, threadEvents) in threadGroups {
            let conversation = findOrCreateConversation(
                id: threadId,
                subject: threadEvents.first?.subject,
                account: account,
                modelContext: modelContext
            )
            
            let sortedEvents = threadEvents.sorted { $0.timestamp < $1.timestamp }
            
            for eventData in sortedEvents {
                let event = findOrCreateMessageEvent(
                    id: eventData.id,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.from,
                    conversation: conversation,
                    modelContext: modelContext
                )
                
                event.messageIdHeader = eventData.id
                event.inReplyToHeader = eventData.inReplyTo
                event.referencesHeader = eventData.references
            }
            
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Process Microsoft Events
    
    private func processMicrosoftEvents(
        _ events: [MicrosoftConnector.MessageEventData],
        account: SourceAccount,
        modelContext: ModelContext
    ) {
        var conversationGroups: [String: [MicrosoftConnector.MessageEventData]] = [:]
        for event in events {
            conversationGroups[event.conversationId, default: []].append(event)
        }
        
        for (conversationId, convEvents) in conversationGroups {
            let conversation = findOrCreateConversation(
                id: conversationId,
                subject: convEvents.first?.subject,
                account: account,
                modelContext: modelContext
            )
            
            let sortedEvents = convEvents.sorted { $0.timestamp < $1.timestamp }
            
            for eventData in sortedEvents {
                _ = findOrCreateMessageEvent(
                    id: eventData.id,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.from,
                    conversation: conversation,
                    modelContext: modelContext
                )
            }
            
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Process Slack Events
    
    private func processSlackEvents(
        _ events: [SlackConnector.MessageEventData],
        account: SourceAccount,
        modelContext: ModelContext
    ) {
        var channelGroups: [String: [SlackConnector.MessageEventData]] = [:]
        for event in events {
            channelGroups[event.channelId, default: []].append(event)
        }
        
        for (channelId, channelEvents) in channelGroups {
            let conversation = findOrCreateConversation(
                id: channelId,
                subject: nil,
                account: account,
                modelContext: modelContext
            )
            
            let sortedEvents = channelEvents.sorted { $0.timestamp < $1.timestamp }
            
            for eventData in sortedEvents {
                _ = findOrCreateMessageEvent(
                    id: eventData.id,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.userId,
                    conversation: conversation,
                    modelContext: modelContext
                )
            }
            
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Process iMessage Events
    
    private func processIMessageEvents(
        _ events: [iMessageConnector.MessageEventData],
        account: SourceAccount,
        modelContext: ModelContext
    ) {
        // Group messages by handle (conversation)
        var handleGroups: [String: [iMessageConnector.MessageEventData]] = [:]
        for event in events {
            handleGroups[event.handleId, default: []].append(event)
        }
        
        for (handleId, handleEvents) in handleGroups {
            let conversation = findOrCreateConversation(
                id: "imessage_\(handleId)",
                subject: handleEvents.first?.participantId,
                account: account,
                modelContext: modelContext
            )
            
            let sortedEvents = handleEvents.sorted { $0.timestamp < $1.timestamp }
            
            for eventData in sortedEvents {
                _ = findOrCreateMessageEvent(
                    id: eventData.id,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.participantId,
                    conversation: conversation,
                    modelContext: modelContext
                )
            }
            
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Helpers
    
    private func findOrCreateConversation(
        id: String,
        subject: String?,
        account: SourceAccount,
        modelContext: ModelContext
    ) -> Conversation {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        
        let conversation = Conversation(
            id: id,
            sourceAccount: account,
            subject: subject
        )
        modelContext.insert(conversation)
        return conversation
    }
    
    private func findOrCreateMessageEvent(
        id: String,
        timestamp: Date,
        direction: MessageDirection,
        participantEmail: String,
        conversation: Conversation,
        modelContext: ModelContext
    ) -> MessageEvent {
        let descriptor = FetchDescriptor<MessageEvent>(
            predicate: #Predicate { $0.id == id }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        
        let event = MessageEvent(
            id: id,
            conversation: conversation,
            timestamp: timestamp,
            direction: direction,
            participantEmail: participantEmail
        )
        modelContext.insert(event)
        return event
    }
    
    // MARK: - Compute Response Windows
    
    private func computeResponseWindows(
        for account: SourceAccount,
        modelContext: ModelContext
    ) {
        let analyzer = ResponseAnalyzer.shared
        
        for conversation in account.conversations {
            guard !conversation.isExcluded else { continue }
            
            let windows = analyzer.computeResponseWindows(for: conversation)
            
            for window in windows {
                modelContext.insert(window)
            }
        }
        
        try? modelContext.save()
    }
}

// MARK: - Background Sync Support

extension SyncCoordinator {
    func scheduleBackgroundSync(interval: TimeInterval) {
        // This would integrate with BGTaskScheduler on iOS
        // and SMAppService on macOS for background refresh
    }
    
    func cancelBackgroundSync() {
        // Cancel scheduled background tasks
    }
}
