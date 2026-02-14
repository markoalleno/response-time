import SwiftUI
import SwiftData
import Foundation

// MARK: - Source Account

@Model
final class SourceAccount {
    @Attribute(.unique) var id: UUID
    var platform: Platform
    var displayName: String
    var email: String?
    var isEnabled: Bool
    var syncCheckpoint: Date?
    var deltaLink: String? // For incremental sync (Microsoft Graph)
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Sync settings
    var syncSentItems: Bool = true
    var syncInbox: Bool = true
    var excludedFolders: [String] = []
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Conversation.sourceAccount)
    var conversations: [Conversation] = []
    
    init(
        id: UUID = UUID(),
        platform: Platform,
        displayName: String,
        email: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.email = email
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var totalConversations: Int { conversations.count }
    var totalMessages: Int { conversations.reduce(0) { $0 + $1.messageEvents.count } }
    
    var isStale: Bool {
        guard let checkpoint = syncCheckpoint else { return true }
        return Date().timeIntervalSince(checkpoint) > 3600 // 1 hour
    }
}

// MARK: - Conversation

@Model
final class Conversation {
    @Attribute(.unique) var id: String // Platform-specific ID (thread ID, conversation ID)
    var sourceAccount: SourceAccount?
    var subject: String?
    var isArchived: Bool
    var isExcluded: Bool
    var excludeReason: String?
    var lastActivityAt: Date
    var createdAt: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \MessageEvent.conversation)
    var messageEvents: [MessageEvent] = []
    
    @Relationship(deleteRule: .nullify, inverse: \Participant.conversations)
    var participants: [Participant] = []
    
    init(
        id: String,
        sourceAccount: SourceAccount? = nil,
        subject: String? = nil,
        isArchived: Bool = false,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.sourceAccount = sourceAccount
        self.subject = subject
        self.isArchived = isArchived
        self.isExcluded = isExcluded
        self.lastActivityAt = Date()
        self.createdAt = Date()
    }
    
    var inboundCount: Int { messageEvents.filter { $0.direction == .inbound }.count }
    var outboundCount: Int { messageEvents.filter { $0.direction == .outbound }.count }
    
    var sortedEvents: [MessageEvent] {
        messageEvents.sorted { $0.timestamp < $1.timestamp }
    }
    
    var otherParticipants: [Participant] {
        participants.filter { !$0.isMe }
    }
}

// MARK: - Participant

@Model
final class Participant {
    @Attribute(.unique) var id: UUID
    var email: String
    var displayName: String?
    var isMe: Bool
    var firstSeenAt: Date
    var isExcluded: Bool = false
    var excludeReason: String?
    
    // Relationships
    @Relationship(deleteRule: .nullify)
    var conversations: [Conversation] = []
    
    init(
        id: UUID = UUID(),
        email: String,
        displayName: String? = nil,
        isMe: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isMe = isMe
        self.firstSeenAt = Date()
    }
    
    var label: String { displayName ?? email }
    
    var initials: String {
        let name = displayName ?? email
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

// MARK: - Message Event

@Model
final class MessageEvent {
    @Attribute(.unique) var id: String // Platform-specific message ID
    var conversation: Conversation?
    var timestamp: Date
    var direction: MessageDirection
    var participantEmail: String
    var headersHash: Data? // Privacy-preserving identifier
    var isExcluded: Bool
    var excludeReason: String?
    
    // Threading headers (for matching)
    var messageIdHeader: String?
    var inReplyToHeader: String?
    var referencesHeader: String?
    
    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \ResponseWindow.inboundEvent)
    var responseWindow: ResponseWindow?
    
    init(
        id: String,
        conversation: Conversation? = nil,
        timestamp: Date,
        direction: MessageDirection,
        participantEmail: String,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.conversation = conversation
        self.timestamp = timestamp
        self.direction = direction
        self.participantEmail = participantEmail
        self.isExcluded = isExcluded
    }
}

// MARK: - Response Window

@Model
final class ResponseWindow {
    @Attribute(.unique) var id: UUID
    var inboundEvent: MessageEvent?
    var outboundEvent: MessageEvent?
    var latencySeconds: TimeInterval
    var confidence: Float // 0.0-1.0
    var matchingMethod: ThreadingMethod
    var isValidForAnalytics: Bool
    var computedAt: Date
    
    // Metadata for filtering
    var isWorkingHours: Bool = true
    var dayOfWeek: Int = 1 // 1-7 (Sunday-Saturday)
    var hourOfDay: Int = 12 // 0-23
    
    init(
        id: UUID = UUID(),
        inboundEvent: MessageEvent? = nil,
        outboundEvent: MessageEvent? = nil,
        latencySeconds: TimeInterval,
        confidence: Float = 1.0,
        matchingMethod: ThreadingMethod
    ) {
        self.id = id
        self.inboundEvent = inboundEvent
        self.outboundEvent = outboundEvent
        self.latencySeconds = latencySeconds
        self.confidence = confidence
        self.matchingMethod = matchingMethod
        self.isValidForAnalytics = confidence >= 0.7
        self.computedAt = Date()
        
        // Compute time metadata
        if let timestamp = inboundEvent?.timestamp {
            let calendar = Calendar.current
            self.dayOfWeek = calendar.component(.weekday, from: timestamp)
            self.hourOfDay = calendar.component(.hour, from: timestamp)
        }
    }
    
    var formattedLatency: String {
        formatDuration(latencySeconds)
    }
    
    var latencyMinutes: Double {
        latencySeconds / 60
    }
    
    var latencyHours: Double {
        latencySeconds / 3600
    }
}

// MARK: - Response Goal

@Model
final class ResponseGoal {
    @Attribute(.unique) var id: UUID
    var platform: Platform?
    var targetLatencySeconds: TimeInterval
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Additional settings
    var workingHoursOnly: Bool = false
    var notifyWhenExceeded: Bool = false
    
    init(
        id: UUID = UUID(),
        platform: Platform? = nil,
        targetLatencySeconds: TimeInterval = 3600, // 1 hour default
        isEnabled: Bool = true
    ) {
        self.id = id
        self.platform = platform
        self.targetLatencySeconds = targetLatencySeconds
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var formattedTarget: String {
        formatDuration(targetLatencySeconds)
    }
    
    var targetMinutes: Int {
        Int(targetLatencySeconds / 60)
    }
}

// MARK: - User Preferences

@Model
final class UserPreferences {
    @Attribute(.unique) var id: UUID
    
    // Working hours
    var workingHoursStart: Int = 9 // 9 AM
    var workingHoursEnd: Int = 17 // 5 PM
    var workingDays: [Int] = [2, 3, 4, 5, 6] // Monday-Friday (1=Sun, 7=Sat)
    var timezone: String = TimeZone.current.identifier
    
    // Analytics settings
    var matchingWindowDays: Int = 7
    var confidenceThreshold: Double = 0.7
    var excludeAutoReplies: Bool = true
    var excludeMailingLists: Bool = true
    var excludeCalendarInvites: Bool = true
    
    // Sync settings
    var syncInBackground: Bool = false
    var syncIntervalMinutes: Int = 30
    var syncOnLaunch: Bool = true
    
    // UI settings
    var showMenuBarIcon: Bool = true
    var defaultTimeRange: String = "week"
    
    init(id: UUID = UUID()) {
        self.id = id
    }
    
    func isWorkingHour(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        
        return workingDays.contains(weekday) &&
               hour >= workingHoursStart &&
               hour < workingHoursEnd
    }
}

// MARK: - Analytics Models (Non-persistent)

struct ResponseMetrics: Sendable {
    let platform: Platform?
    let timeRange: TimeRange
    let sampleCount: Int
    
    // Core metrics
    let medianLatency: TimeInterval
    let meanLatency: TimeInterval
    let p90Latency: TimeInterval
    let p95Latency: TimeInterval
    let minLatency: TimeInterval
    let maxLatency: TimeInterval
    
    // Breakdown
    let workingHoursMedian: TimeInterval?
    let nonWorkingHoursMedian: TimeInterval?
    
    // Trend
    let previousPeriodMedian: TimeInterval?
    let trendPercentage: Double?
    
    var formattedMedian: String { formatDuration(medianLatency) }
    var formattedMean: String { formatDuration(meanLatency) }
    var formattedP90: String { formatDuration(p90Latency) }
    
    var trendDirection: TrendDirection {
        guard let trend = trendPercentage else { return .flat }
        if trend < -5 { return .improving }
        if trend > 5 { return .declining }
        return .flat
    }
    
    enum TrendDirection: Sendable {
        case improving, flat, declining
        
        var icon: String {
            switch self {
            case .improving: return "arrow.down.right"
            case .flat: return "minus"
            case .declining: return "arrow.up.right"
            }
        }
        
        var color: Color {
            switch self {
            case .improving: return .green
            case .flat: return .secondary
            case .declining: return .red
            }
        }
    }
}

struct DailyMetrics: Identifiable, Sendable {
    let id: UUID = UUID()
    let date: Date
    let medianLatency: TimeInterval
    let messageCount: Int
    let responseCount: Int
}

struct HourlyMetrics: Identifiable, Sendable {
    let id: Int // 0-23
    let hour: Int
    let medianLatency: TimeInterval
    let responseCount: Int
}

struct PlatformMetrics: Identifiable, Sendable {
    let id: String
    let platform: Platform
    let medianLatency: TimeInterval
    let sampleCount: Int
    let goalProgress: Double?
}

// MARK: - Helpers

func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds))s"
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    } else if seconds < 86400 {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    } else {
        let days = Int(seconds / 86400)
        let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        if hours == 0 {
            return "\(days)d"
        }
        return "\(days)d \(hours)h"
    }
}

func formatDurationShort(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds))s"
    } else if seconds < 3600 {
        return "\(Int(seconds / 60))m"
    } else if seconds < 86400 {
        return "\(Int(seconds / 3600))h"
    } else {
        return "\(Int(seconds / 86400))d"
    }
}
