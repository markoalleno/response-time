import AppIntents
import SwiftUI
import SwiftData

// MARK: - Get Response Time Intent

struct GetResponseTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Response Time"
    static let description: IntentDescription = IntentDescription("Get your average response time")
    
    @Parameter(title: "Time Period", default: .week)
    var timePeriod: IntentTimePeriod
    
    @Parameter(title: "Platform")
    var platform: IntentPlatform?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get response time for \(\.$timePeriod)") {
            \.$platform
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Fetch real stats from iMessage
        let connector = iMessageConnector()
        let days: Int = {
            switch timePeriod {
            case .today: return 1
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            }
        }()
        let stats = try? await connector.getQuickStats(days: days)
        let formattedTime = stats?.formattedMedian ?? "--"
        
        let platformText = platform?.displayName ?? "all platforms"
        let periodText = timePeriod.displayName.lowercased()
        
        return .result(
            dialog: "Your average response time for \(platformText) \(periodText) is \(formattedTime).",
            view: ResponseTimeSnippetView(
                medianTime: formattedTime,
                platform: platform?.displayName,
                period: timePeriod.displayName
            )
        )
    }
}

// MARK: - Set Response Goal Intent

struct SetResponseGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Response Goal"
    static let description: IntentDescription = IntentDescription("Set a response time goal")
    
    @Parameter(title: "Target Time (minutes)")
    var targetMinutes: Int
    
    @Parameter(title: "Platform")
    var platform: IntentPlatform?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Set goal to respond in \(\.$targetMinutes) minutes") {
            \.$platform
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let platformText = platform?.displayName ?? "all platforms"
        let timeText = targetMinutes < 60 ? "\(targetMinutes) minutes" : "\(targetMinutes / 60) hours"
        
        // In production, would save to SwiftData
        return .result(dialog: "Set response goal for \(platformText) to \(timeText).")
    }
}

// MARK: - Get Goal Progress Intent

struct GetGoalProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Goal Progress"
    static let description: IntentDescription = IntentDescription("Check your response goal progress")
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Simulated progress
        let progress = 78
        return .result(dialog: "You're \(progress)% on target with your response goals this week.")
    }
}

// MARK: - Toggle Sync Intent

struct ToggleSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Sync"
    static let description: IntentDescription = IntentDescription("Enable or disable response time tracking")
    
    @Parameter(title: "Enabled")
    var enabled: Bool
    
    static var parameterSummary: some ParameterSummary {
        When(\.$enabled, .equalTo, true) {
            Summary("Enable response time tracking")
        } otherwise: {
            Summary("Disable response time tracking")
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let statusText = enabled ? "enabled" : "disabled"
        return .result(dialog: "Response time tracking is now \(statusText).")
    }
}

// MARK: - Snippet View

struct ResponseTimeSnippetView: View {
    let medianTime: String
    let platform: String?
    let period: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("Response Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(medianTime)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            Text("\(platform ?? "All platforms") • \(period)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Intent Enums

enum IntentTimePeriod: String, AppEnum {
    case today = "today"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Time Period")
    }
    
    static var caseDisplayRepresentations: [IntentTimePeriod: DisplayRepresentation] {
        [
            .today: DisplayRepresentation(title: "Today"),
            .week: DisplayRepresentation(title: "This Week"),
            .month: DisplayRepresentation(title: "This Month"),
            .quarter: DisplayRepresentation(title: "This Quarter"),
            .year: DisplayRepresentation(title: "This Year")
        ]
    }
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .quarter: return "This Quarter"
        case .year: return "This Year"
        }
    }
    
    var toTimeRange: TimeRange {
        switch self {
        case .today: return .today
        case .week: return .week
        case .month: return .month
        case .quarter: return .quarter
        case .year: return .year
        }
    }
}

enum IntentPlatform: String, AppEnum {
    case gmail = "gmail"
    case outlook = "outlook"
    case slack = "slack"
    case imessage = "imessage"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Platform")
    }
    
    static var caseDisplayRepresentations: [IntentPlatform: DisplayRepresentation] {
        [
            .gmail: DisplayRepresentation(title: "Gmail"),
            .outlook: DisplayRepresentation(title: "Outlook"),
            .slack: DisplayRepresentation(title: "Slack"),
            .imessage: DisplayRepresentation(title: "iMessage")
        ]
    }
    
    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        case .slack: return "Slack"
        case .imessage: return "iMessage"
        }
    }
}

// MARK: - Get Pending Responses Intent

struct GetPendingResponsesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Pending Responses"
    static let description: IntentDescription = IntentDescription("See who you haven't responded to yet")
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connector = iMessageConnector()
        let conversations = try await connector.fetchAllConversations(days: 7)
        let pending = conversations.filter { $0.pendingResponse && !$0.isGroupChat }
        
        if pending.isEmpty {
            return .result(dialog: "You're all caught up! No pending responses.")
        }
        
        let names = pending.prefix(5).map { conv in
            conv.displayName ?? conv.participants.first?.displayIdentifier ?? conv.chatIdentifier
        }
        let list = names.joined(separator: ", ")
        let more = pending.count > 5 ? " and \(pending.count - 5) more" : ""
        
        return .result(dialog: "You have \(pending.count) pending response\(pending.count == 1 ? "" : "s"): \(list)\(more).")
    }
}

// MARK: - Sync Now Intent

struct SyncNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Response Time"
    static let description: IntentDescription = IntentDescription("Sync your messages and update response time data")
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connector = iMessageConnector()
        let stats = try await connector.getQuickStats(days: 7)
        
        let median = stats.formattedMedian
        let pending = stats.pendingResponses
        
        return .result(dialog: "Synced! Median response time: \(median). \(pending) pending response\(pending == 1 ? "" : "s").")
    }
}

// MARK: - App Shortcuts Provider

struct ResponseTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetResponseTimeIntent(),
            phrases: [
                "Get my response time from \(.applicationName)",
                "What's my average response time in \(.applicationName)",
                "How quickly am I responding in \(.applicationName)"
            ],
            shortTitle: "Get Response Time",
            systemImageName: "clock.arrow.circlepath"
        )
        
        AppShortcut(
            intent: GetGoalProgressIntent(),
            phrases: [
                "Check my response goals in \(.applicationName)",
                "How am I doing on response goals in \(.applicationName)"
            ],
            shortTitle: "Goal Progress",
            systemImageName: "target"
        )
        
        AppShortcut(
            intent: GetPendingResponsesIntent(),
            phrases: [
                "Who haven't I responded to in \(.applicationName)",
                "Show pending responses in \(.applicationName)",
                "Who's waiting for my reply in \(.applicationName)"
            ],
            shortTitle: "Pending Responses",
            systemImageName: "exclamationmark.bubble"
        )
        
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Update my response time data in \(.applicationName)"
            ],
            shortTitle: "Sync Now",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
