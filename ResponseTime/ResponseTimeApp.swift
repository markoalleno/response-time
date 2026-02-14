import SwiftUI
import SwiftData
#if os(macOS)
import UserNotifications
#endif

@main
struct ResponseTimeApp: App {
    @State private var appState = AppState()
    #if os(macOS)
    @State private var menuBarManager = MenuBarManager.shared
    #endif
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SourceAccount.self,
            Conversation.self,
            MessageEvent.self,
            ResponseWindow.self,
            ResponseGoal.self,
            Participant.self,
            UserPreferences.self
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
    
    init() {
        #if os(macOS)
        // Setup notification categories
        Task { @MainActor in
            NotificationService.shared.setupNotificationCategories()
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await setupNotifications()
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1000, height: 700)
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
        
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        #endif
    }
    
    private func setupNotifications() async {
        #if os(macOS)
        do {
            let granted = try await NotificationService.shared.requestAuthorization()
            if granted {
                // Schedule daily summary notification at user's preferred time
                let hour = UserDefaults.standard.integer(forKey: "dailySummaryHour")
                try await NotificationService.shared.scheduleDailySummary(at: hour == 0 ? 21 : hour, minute: 0)
            }
        } catch {
            print("Failed to setup notifications: \(error)")
        }
        #endif
    }
}

// MARK: - Menu Bar Label

#if os(macOS)
struct MenuBarLabel: View {
    @State private var menuBarManager = MenuBarManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
            
            if let latency = menuBarManager.currentStats.overallMedianLatency {
                Text(formatMenuBarTime(latency))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .task {
            menuBarManager.start()
        }
    }
    
    private func formatMenuBarTime(_ seconds: TimeInterval) -> String {
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
            return "\(hours)h\(minutes)m"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d"
        }
    }
}
#endif

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
    
    // Notification settings
    var notificationSettings = NotificationSettings()
    
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

enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum TimeRange: String, CaseIterable, Identifiable, Sendable {
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

enum MessageDirection: String, Codable, Sendable {
    case inbound = "inbound"
    case outbound = "outbound"
}

enum ThreadingMethod: String, Codable, Sendable {
    case messageId = "message_id"
    case threadId = "thread_id"
    case references = "references"
    case subjectMatch = "subject_match"
    case timeWindow = "time_window"
}
