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
        debugLog("🔄 [SYNC] Starting iMessage sync...")
        
        // Pre-load contact names on main actor before background work
        debugLog("👤 [SYNC] Requesting contact access...")
        _ = await ContactResolver.shared.requestAccessAndLoad()
        debugLog("👤 [SYNC] Contact access complete")
        
        // Fetch raw messages from chat.db (this is I/O, fine off main)
        // We need the checkpoint from the existing account, fetch it in background context
        debugLog("💾 [SYNC] Creating background ModelContext...")
        let backgroundContext = ModelContext(container)
        backgroundContext.autosaveEnabled = false
        debugLog("💾 [SYNC] Background context created")
        
        // Get or create the iMessage source account
        let sourceAccount = try getOrCreateSourceAccount(modelContext: backgroundContext)
        debugLog("📱 [SYNC] Source account checkpoint: \(sourceAccount.syncCheckpoint ?? Date.distantPast)")
        
        debugLog("🔌 [SYNC] Calling connector.sync()...")
        let syncResult: iMessageConnector.iMessageSyncResult
        do {
            syncResult = try await connector.sync(since: sourceAccount.syncCheckpoint, limit: 10000)
            debugLog("📊 [SYNC] Fetched \(syncResult.messageEvents.count) raw message events from chat.db")
        } catch {
            debugLog("❌ [SYNC] Connector.sync() failed: \(error)")
            throw error
        }
        
        guard !syncResult.messageEvents.isEmpty else {
            debugLog("⚠️ [SYNC] No messages found, updating checkpoint and returning")
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
        debugLog("👥 [SYNC] Grouped into \(handleGroups.count) conversations")
        
        var totalEventsCreated = 0
        var totalEventsSkipped = 0
        
        // Process each handle group
        for (participantId, events) in handleGroups {
            debugLog("💬 [SYNC] Processing conversation with \(participantId): \(events.count) messages")
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
            var inboundCount = 0
            var outboundCount = 0
            
            // Batch fetch existing events for this conversation (optimization)
            let eventIds = Set(sortedEvents.map(\.id))
            let existingDescriptor = FetchDescriptor<MessageEvent>()
            let allExistingEvents = (try? backgroundContext.fetch(existingDescriptor)) ?? []
            let existingIds = Set(allExistingEvents.filter { eventIds.contains($0.id) }.map(\.id))
            
            for eventData in sortedEvents {
                // Check against pre-fetched set (much faster than individual DB queries)
                if existingIds.contains(eventData.id) {
                    totalEventsSkipped += 1
                    continue
                }
                
                let messageEvent = MessageEvent(
                    id: eventData.id,
                    conversation: conversation,
                    timestamp: eventData.timestamp,
                    direction: eventData.direction,
                    participantEmail: eventData.participantId
                )
                backgroundContext.insert(messageEvent)
                totalEventsCreated += 1
                
                if eventData.direction == .inbound {
                    inboundCount += 1
                } else {
                    outboundCount += 1
                }
            }
            
            debugLog("   📥 Inbound: \(inboundCount), 📤 Outbound: \(outboundCount)")
            
            // Update last activity
            if let lastEvent = sortedEvents.last {
                conversation.lastActivityAt = lastEvent.timestamp
            }
        }
        
        debugLog("✅ [SYNC] Created \(totalEventsCreated) new MessageEvents (skipped \(totalEventsSkipped) duplicates)")
        
        // Compute response windows for all iMessage conversations
        debugLog("🧮 [SYNC] Computing response windows...")
        try computeResponseWindows(for: sourceAccount, modelContext: backgroundContext)
        
        // Update checkpoint
        sourceAccount.syncCheckpoint = Date()
        sourceAccount.updatedAt = Date()
        
        // Single save at the end — main context auto-merges
        debugLog("💾 [SYNC] Saving background context...")
        try backgroundContext.save()
        debugLog("✅ [SYNC] Sync complete! Context saved successfully.")
    }
    
    // MARK: - Compute Response Windows
    
    private func computeResponseWindows(for account: SourceAccount, modelContext: ModelContext) throws {
        var totalWindows = 0
        var totalConversationsProcessed = 0
        var totalConversationsSkipped = 0
        
        debugLog("   📋 [COMPUTE] Account has \(account.conversations.count) conversations")
        
        for conversation in account.conversations {
            guard !conversation.isExcluded else {
                totalConversationsSkipped += 1
                continue
            }
            
            let events = conversation.messageEvents.sorted { $0.timestamp < $1.timestamp }
            guard events.count >= 2 else {
                debugLog("   ⏭️  Skipping conversation \(conversation.subject ?? "unknown"): only \(events.count) events")
                continue
            }
            
            totalConversationsProcessed += 1
            debugLog("   🔍 [COMPUTE] Processing \(conversation.subject ?? "unknown"): \(events.count) events")
            
            // Find inbound→outbound pairs
            var lastInbound: MessageEvent?
            var windowsForConversation = 0
            
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
                    windowsForConversation += 1
                    totalWindows += 1
                    lastInbound = nil
                }
            }
            
            if windowsForConversation > 0 {
                debugLog("      ✨ Created \(windowsForConversation) response windows")
            }
        }
        
        debugLog("📈 [COMPUTE] Total: \(totalWindows) response windows created across \(totalConversationsProcessed) conversations (skipped \(totalConversationsSkipped))")
    }
    
    // MARK: - Helpers
    
    private func getOrCreateSourceAccount(modelContext: ModelContext) throws -> SourceAccount {
        debugLog("📂 [SYNC] Getting or creating source account...")
        
        // Fetch all source accounts without predicate (workaround for background context hang)
        debugLog("📂 [SYNC] Fetching all source accounts...")
        let descriptor = FetchDescriptor<SourceAccount>()
        let allAccounts = try modelContext.fetch(descriptor)
        debugLog("📂 [SYNC] Fetched \(allAccounts.count) source accounts")
        
        // Filter for iMessage account manually
        if let existing = allAccounts.first(where: { $0.platform == .imessage }) {
            debugLog("📂 [SYNC] Found existing iMessage account")
            return existing
        }
        
        debugLog("📂 [SYNC] Creating new iMessage source account...")
        let account = SourceAccount(
            platform: .imessage,
            displayName: "iMessage",
            isEnabled: true
        )
        modelContext.insert(account)
        debugLog("📂 [SYNC] Source account created")
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
