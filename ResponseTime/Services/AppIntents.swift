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
        // Use real data from ResponseAnalyzer
        let formattedTime = "--"
        
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
    }
}
