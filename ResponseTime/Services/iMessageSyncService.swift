import Foundation
import SwiftData

/// Service to sync iMessage data to SwiftData models
@MainActor
final class iMessageSyncService {
    static let shared = iMessageSyncService()
    
    private let connector = iMessageConnector()
    
    private init() {}
    
    // MARK: - Sync to SwiftData
    
    func syncToSwiftData(modelContext: ModelContext) async throws {
        // Get or create the iMessage source account
        let sourceAccount = try getOrCreateSourceAccount(modelContext: modelContext)
        
        // Fetch raw messages from chat.db via the connector
        let syncResult = try await connector.sync(since: sourceAccount.syncCheckpoint, limit: 10000)
        
        guard !syncResult.messageEvents.isEmpty else {
            sourceAccount.syncCheckpoint = Date()
            sourceAccount.updatedAt = Date()
            try modelContext.save()
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
                modelContext: modelContext
            )
            conversation.subject = participantId
            
            // Get or create participant
            let participant = try getOrCreateParticipant(
                identifier: participantId,
                modelContext: modelContext
            )
            if !conversation.participants.contains(where: { $0.email == participant.email }) {
                conversation.participants.append(participant)
            }
            
            // Create MessageEvents (skip duplicates)
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
            for eventData in sortedEvents {
                let eventId = eventData.id
                let existingDescriptor = FetchDescriptor<MessageEvent>(
                    predicate: #Predicate { $0.id == eventId }
                )
                if let _ = try? modelContext.fetch(existingDescriptor).first {
                    continue  // Already exists
                }
                
                let messageEvent = MessageEvent(
                    id: eventData.id,
                    conversation: conversation,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.participantId
                )
                modelContext.insert(messageEvent)
            }
            
            // Update last activity
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        // Compute response windows for all iMessage conversations
        try computeResponseWindows(for: sourceAccount, modelContext: modelContext)
        
        // Update checkpoint
        sourceAccount.syncCheckpoint = Date()
        sourceAccount.updatedAt = Date()
        
        try modelContext.save()
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
                    
                    // Skip if this inbound already has a response window
                    if inbound.responseWindow != nil {
                        lastInbound = nil
                        continue
                    }
                    
                    // Compute confidence
                    var confidence: Float = 1.0
                    let hours = latency / 3600
                    if hours > 72 { confidence = 0.4 }
                    else if hours > 48 { confidence = 0.6 }
                    else if hours > 24 { confidence = 0.8 }
                    
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
