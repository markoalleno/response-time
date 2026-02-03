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
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    
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
}

// MARK: - Conversation

@Model
final class Conversation {
    @Attribute(.unique) var id: String // Platform-specific ID
    var sourceAccount: SourceAccount?
    var subject: String?
    var isArchived: Bool
    var isExcluded: Bool
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
}

// MARK: - Participant

@Model
final class Participant {
    @Attribute(.unique) var id: UUID
    var email: String
    var displayName: String?
    var isMe: Bool
    var firstSeenAt: Date
    
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
    }
    
    var formattedLatency: String {
        formatDuration(latencySeconds)
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
}

// MARK: - Analytics Models

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
    
    enum TrendDirection {
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
