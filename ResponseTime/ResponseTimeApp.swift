import SwiftUI
import SwiftData

@main
struct ResponseTimeApp: App {
    @State private var appState = AppState()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SourceAccount.self,
            Conversation.self,
            MessageEvent.self,
            ResponseWindow.self,
            ResponseGoal.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1000, height: 700)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
        
        MenuBarExtra("Response Time", systemImage: "clock.arrow.circlepath") {
            MenuBarView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App State

@Observable
@MainActor
class AppState {
    var selectedPlatform: Platform?
    var selectedTimeRange: TimeRange = .week
    var isOnboarding: Bool = false
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var error: AppError?
    
    // Analytics cache
    var cachedMetrics: ResponseMetrics?
    var metricsLastUpdated: Date?
    
    enum AppError: LocalizedError {
        case syncFailed(String)
        case authFailed(Platform)
        case networkError
        
        var errorDescription: String? {
            switch self {
            case .syncFailed(let msg): return "Sync failed: \(msg)"
            case .authFailed(let platform): return "Authentication failed for \(platform.displayName)"
            case .networkError: return "Network connection error"
            }
        }
    }
}

// MARK: - Enums

enum Platform: String, Codable, CaseIterable, Identifiable {
    case gmail = "gmail"
    case outlook = "outlook"
    case slack = "slack"
    case imessage = "imessage"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        case .slack: return "Slack"
        case .imessage: return "iMessage"
        }
    }
    
    var icon: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .outlook: return "envelope.badge.fill"
        case .slack: return "number.square.fill"
        case .imessage: return "message.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .gmail: return .red
        case .outlook: return .blue
        case .slack: return .purple
        case .imessage: return .green
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "today"
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .quarter: return "This Quarter"
        case .year: return "This Year"
        }
    }
    
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now)!
        case .quarter:
            return calendar.date(byAdding: .month, value: -3, to: now)!
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now)!
        }
    }
}

enum MessageDirection: String, Codable {
    case inbound = "inbound"
    case outbound = "outbound"
}

enum ThreadingMethod: String, Codable {
    case messageId = "message_id"
    case threadId = "thread_id"
    case references = "references"
    case subjectMatch = "subject_match"
    case timeWindow = "time_window"
}
