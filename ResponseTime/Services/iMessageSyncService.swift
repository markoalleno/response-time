import Foundation
import SwiftData

/// Service to sync iMessage data to SwiftData models
/// Runs sync on a background ModelContext to avoid blocking SwiftUI layout
final class iMessageSyncService: Sendable {
    static let shared = iMessageSyncService()
    
    private let connector = iMessageConnector()
    
    private init() {}
    
    // MARK: - Sync to SwiftData
    
    /// Syncs iMessage data using a background ModelContext.
    /// Call from any actor — this creates its own context from the container.
    func syncToSwiftData(container: ModelContainer) async throws {
        // Pre-load contact names on main actor before background work
        _ = await ContactResolver.shared.requestAccessAndLoad()
        
        // Fetch raw messages from chat.db (this is I/O, fine off main)
        // We need the checkpoint from the existing account, fetch it in background context
        let backgroundContext = ModelContext(container)
        backgroundContext.autosaveEnabled = false
        
        // Get or create the iMessage source account
        let sourceAccount = try getOrCreateSourceAccount(modelContext: backgroundContext)
        
        let syncResult = try await connector.sync(since: sourceAccount.syncCheckpoint, limit: 10000)
        
        guard !syncResult.messageEvents.isEmpty else {
            sourceAccount.syncCheckpoint = Date()
            sourceAccount.updatedAt = Date()
            try backgroundContext.save()
            return
        }
        
        // Group messages by handle (each handle = a conversation)
        var handleGroups: [String: [iMessageConnector.MessageEventData]] = [:]
        for event in syncResult.messageEvents {
            let key = event.participantId  // phone/email of the other person
            handleGroups[key, default: []].append(event)
        }
        
        // Process each handle group
        for (participantId, events) in handleGroups {
            // Get or create conversation
            let conversationId = "imessage_\(participantId)"
            let conversation = try getOrCreateConversation(
                id: conversationId,
                sourceAccount: sourceAccount,
                modelContext: backgroundContext
            )
            // Get or create participant (with resolved name)
            let participant = try getOrCreateParticipant(
                identifier: participantId,
                modelContext: backgroundContext
            )
            // Resolve contact name if not already set
            if participant.displayName == nil {
                if let resolvedName = await ContactResolver.shared.resolve(participantId) {
                    participant.displayName = resolvedName
                }
            }
            if !conversation.participants.contains(where: { $0.email == participant.email }) {
                conversation.participants.append(participant)
            }
            conversation.subject = participant.displayName ?? participantId
            
            // Create MessageEvents (skip duplicates)
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
            for eventData in sortedEvents {
                let eventId = eventData.id
                let existingDescriptor = FetchDescriptor<MessageEvent>(
                    predicate: #Predicate { $0.id == eventId }
                )
                if let _ = try? backgroundContext.fetch(existingDescriptor).first {
                    continue  // Already exists
                }
                
                let messageEvent = MessageEvent(
                    id: eventData.id,
                    conversation: conversation,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.participantId
                )
                backgroundContext.insert(messageEvent)
            }
            
            // Update last activity
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        // Compute response windows for all iMessage conversations
        try computeResponseWindows(for: sourceAccount, modelContext: backgroundContext)
        
        // Update checkpoint
        sourceAccount.syncCheckpoint = Date()
        sourceAccount.updatedAt = Date()
        
        // Single save at the end — main context auto-merges
        try backgroundContext.save()
    }
    
    // MARK: - Compute Response Windows
    
    private func computeResponseWindows(for account: SourceAccount, modelContext: ModelContext) throws {
        for conversation in account.conversations {
            guard !conversation.isExcluded else { continue }
            
            let events = conversation.messageEvents.sorted { $0.timestamp < $1.timestamp }
            guard events.count >= 2 else { continue }
            
            // Find inbound→outbound pairs
            var lastInbound: MessageEvent?
            
            for event in events {
                if event.direction == .inbound && !event.isExcluded {
                    lastInbound = event
                } else if event.direction == .outbound && !event.isExcluded, let inbound = lastInbound {
                    let latency = event.timestamp.timeIntervalSince(inbound.timestamp)
                    
                    // Only count reasonable response times (> 0, < 7 days)
                    guard latency > 0 && latency < 7 * 24 * 3600 else {
                        lastInbound = nil
                        continue
                    }
                    
                    // Skip if this inbound already has a response window (check both relationship and database)
                    if inbound.responseWindow != nil {
                        lastInbound = nil
                        continue
                    }
                    
                    // Double-check database for existing window (prevents duplicates on re-sync)
                    let inboundId = inbound.id
                    let existingWindowCheck = FetchDescriptor<ResponseWindow>(
                        predicate: #Predicate { window in
                            window.inboundEvent?.id == inboundId
                        }
                    )
                    if let existingWindows = try? modelContext.fetch(existingWindowCheck), !existingWindows.isEmpty {
                        lastInbound = nil
                        continue
                    }
                    
                    // Compute confidence using shared helper
                    let confidence = computeResponseConfidence(latencySeconds: latency)
                    
                    let window = ResponseWindow(
                        inboundEvent: inbound,
                        outboundEvent: event,
                        latencySeconds: latency,
                        confidence: confidence,
                        matchingMethod: .timeWindow
                    )
                    
                    // Set working hours metadata
                    let calendar = Calendar.current
                    window.dayOfWeek = calendar.component(.weekday, from: inbound.timestamp)
                    window.hourOfDay = calendar.component(.hour, from: inbound.timestamp)
                    
                    // Check if working hours (9-17, Mon-Fri)
                    let weekday = window.dayOfWeek
                    let hour = window.hourOfDay
                    window.isWorkingHours = (weekday >= 2 && weekday <= 6) && (hour >= 9 && hour < 17)
                    
                    modelContext.insert(window)
                    lastInbound = nil
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getOrCreateSourceAccount(modelContext: ModelContext) throws -> SourceAccount {
        let targetPlatform = Platform.imessage
        let descriptor = FetchDescriptor<SourceAccount>(
            predicate: #Predicate { $0.platform == targetPlatform }
        )
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let account = SourceAccount(
            platform: .imessage,
            displayName: "iMessage",
            isEnabled: true
        )
        modelContext.insert(account)
        return account
    }
    
    private func getOrCreateParticipant(identifier: String, modelContext: ModelContext) throws -> Participant {
        let descriptor = FetchDescriptor<Participant>(
            predicate: #Predicate { $0.email == identifier }
        )
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let participant = Participant(email: identifier, isMe: false)
        modelContext.insert(participant)
        return participant
    }
    
    private func getOrCreateConversation(id: String, sourceAccount: SourceAccount, modelContext: ModelContext) throws -> Conversation {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let conversation = Conversation(id: id, sourceAccount: sourceAccount)
        modelContext.insert(conversation)
        return conversation
    }
}
