import SwiftUI
import SwiftData
#if os(iOS)
import UniformTypeIdentifiers
#else
import AppKit
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("workingHoursStart") private var workingHoursStart = 9
    @AppStorage("workingHoursEnd") private var workingHoursEnd = 17
    @AppStorage("excludeWeekends") private var excludeWeekends = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("syncInBackground") private var syncInBackground = false
    @AppStorage("syncIntervalMinutes") private var syncIntervalMinutes = 30
    @AppStorage("matchingWindowDays") private var matchingWindowDays = 7
    @AppStorage("confidenceThreshold") private var confidenceThreshold = 0.7
    
    // Notification settings
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("thresholdNotificationsEnabled") private var thresholdNotificationsEnabled = true
    @AppStorage("thresholdMinutes") private var thresholdMinutes = 60
    @AppStorage("dailySummaryEnabled") private var dailySummaryEnabled = true
    @AppStorage("dailySummaryHour") private var dailySummaryHour = 21
    @AppStorage("quietHoursEnabled") private var quietHoursEnabled = false
    @AppStorage("quietHoursStart") private var quietHoursStart = 22
    @AppStorage("quietHoursEnd") private var quietHoursEnd = 8
    
    #if os(iOS)
    @State private var showingExporter = false
    #endif
    
    var body: some View {
        #if os(macOS)
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            platformsSettings
                .tabItem {
                    Label("Platforms", systemImage: "square.stack.3d.up")
                }
            
            notificationSettings
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
            
            analyticsSettings
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
            
            privacySettings
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
            
            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 500)
        #else
        List {
            Section("App Behavior") {
                Toggle("Sync in Background", isOn: $syncInBackground)
                
                if syncInBackground {
                    Picker("Sync Interval", selection: $syncIntervalMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }
            }
            
            Section {
                Picker("Start of Day", selection: $workingHoursStart) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Picker("End of Day", selection: $workingHoursEnd) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Toggle("Exclude Weekends", isOn: $excludeWeekends)
            } header: {
                Text("Working Hours")
            } footer: {
                Text("Working hours are used to calculate separate metrics for on vs off hours.")
            }
            
            Section {
                Picker("Matching Window", selection: $matchingWindowDays) {
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                
                VStack(alignment: .leading) {
                    Text("Confidence: \(Int(confidenceThreshold * 100))%")
                    Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.05)
                }
            } header: {
                Text("Response Matching")
            } footer: {
                Text("Higher confidence thresholds require stronger thread matching.")
            }
            
            Section {
                privacyInfo
            } header: {
                Text("Privacy")
            }
            
            Section {
                Button("Export All Data (CSV)") {
                    showingExporter = true
                }
                
                Button("Delete All Data", role: .destructive) {
                    // Would delete all data
                }
            } header: {
                Text("Your Data")
            }
            
            Section {
                iOSAboutContent
            } header: {
                Text("About")
            }
        }
        .sheet(isPresented: $showingExporter) {
            ExportDataView()
        }
        #endif
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(from: DateComponents(hour: hour))!
        return formatter.string(from: date)
    }
    
    // MARK: - macOS Settings
    
    #if os(macOS)
    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
                Toggle("Sync in Background", isOn: $syncInBackground)
                
                if syncInBackground {
                    Picker("Sync Interval", selection: $syncIntervalMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }
            } header: {
                Text("App Behavior")
            }
            
            Section {
                Picker("Start of Day", selection: $workingHoursStart) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Picker("End of Day", selection: $workingHoursEnd) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Toggle("Exclude Weekends from Working Hours", isOn: $excludeWeekends)
            } header: {
                Text("Working Hours")
            } footer: {
                Text("Working hours are used to calculate separate metrics for on vs off hours.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private var notificationSettings: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        Task {
                            if enabled {
                                _ = try? await NotificationService.shared.requestAuthorization()
                            }
                        }
                    }
            } header: {
                Text("Notifications")
            }
            
            if notificationsEnabled {
                Section {
                    Toggle("Alert When Threshold Exceeded", isOn: $thresholdNotificationsEnabled)
                    
                    if thresholdNotificationsEnabled {
                        Picker("Threshold", selection: $thresholdMinutes) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("4 hours").tag(240)
                        }
                    }
                } header: {
                    Text("Threshold Alerts")
                } footer: {
                    Text("Get notified when a response exceeds the threshold.")
                }
                
                Section {
                    Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                    
                    if quietHoursEnabled {
                        Picker("Start", selection: $quietHoursStart) {
                            ForEach(0..<24) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        
                        Picker("End", selection: $quietHoursEnd) {
                            ForEach(0..<24) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                    }
                } header: {
                    Text("Quiet Hours")
                } footer: {
                    Text("No notifications during quiet hours. Pending responses will still be tracked.")
                }
                
                Section {
                    Toggle("Daily Summary", isOn: $dailySummaryEnabled)
                    
                    if dailySummaryEnabled {
                        Picker("Summary Time", selection: $dailySummaryHour) {
                            ForEach(6..<23) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .onChange(of: dailySummaryHour) { _, hour in
                            Task {
                                try? await NotificationService.shared.scheduleDailySummary(at: hour, minute: 0)
                            }
                        }
                    }
                } header: {
                    Text("Daily Summary")
                } footer: {
                    Text("Receive a daily summary of your response time statistics.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    @State private var showingResetConfirm = false
    @State private var showingDeleteConfirm = false
    
    private var analyticsSettings: some View {
        Form {
            Section {
                Picker("Matching Window", selection: $matchingWindowDays) {
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                
                VStack(alignment: .leading) {
                    Text("Confidence Threshold: \(Int(confidenceThreshold * 100))%")
                    Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.05)
                }
            } header: {
                Text("Response Matching")
            } footer: {
                Text("Matching window determines how long after receiving a message we'll look for your response. Higher confidence thresholds require stronger thread matching.")
            }
            
            Section {
                Button("Reset Analytics") {
                    showingResetConfirm = true
                }
                .foregroundColor(.red)
                .confirmationDialog("Reset all analytics?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        resetAnalytics()
                    }
                } message: {
                    Text("This will delete all computed response windows. Your synced messages will be preserved and analytics can be recomputed.")
                }
            } header: {
                Text("Data Management")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func resetAnalytics() {
        let descriptor = FetchDescriptor<ResponseWindow>()
        if let windows = try? modelContext.fetch(descriptor) {
            for window in windows {
                modelContext.delete(window)
            }
            try? modelContext.save()
        }
    }
    
    private func deleteAllData() {
        // Delete in dependency order
        for type in [DismissedPending.self, ResponseWindow.self, MessageEvent.self, Conversation.self, Participant.self, SourceAccount.self, ResponseGoal.self] as [any PersistentModel.Type] {
            deleteAll(type, from: modelContext)
        }
        try? modelContext.save()
        
        // Reset user defaults
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
    
    private func deleteAll<T: PersistentModel>(_ type: T.Type, from context: ModelContext) {
        let descriptor = FetchDescriptor<T>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
        }
    }
    
    private var privacySettings: some View {
        Form {
            Section {
                privacyInfo
            } header: {
                Text("Privacy Guarantees")
            }
            
            Section {
                Button("Export as CSV") {
                    exportData(format: .csv)
                }
                
                Button("Export as JSON") {
                    exportData(format: .json)
                }
                
                Button("Export Summary Report") {
                    exportSummaryReport()
                }
                
                Button("Delete All Data") {
                    showingDeleteConfirm = true
                }
                .foregroundColor(.red)
                .confirmationDialog("Delete all data?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete Everything", role: .destructive) {
                        deleteAllData()
                    }
                } message: {
                    Text("This will permanently delete all your response time data, accounts, and goals. This cannot be undone.")
                }
            } header: {
                Text("Your Data")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func exportData(format: ExportService.ExportFormat = .csv) {
        let descriptor = FetchDescriptor<ResponseWindow>(
            sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
        )
        let windows = (try? modelContext.fetch(descriptor)) ?? []
        let result = ExportService.shared.exportResponseData(windows: windows, format: format)
        ExportService.shared.saveExport(result)
    }
    
    private func exportSummaryReport() {
        let windowsDescriptor = FetchDescriptor<ResponseWindow>(
            sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
        )
        let goalsDescriptor = FetchDescriptor<ResponseGoal>()
        
        let windows = (try? modelContext.fetch(windowsDescriptor)) ?? []
        let goals = (try? modelContext.fetch(goalsDescriptor)) ?? []
        
        let analyzer = ResponseAnalyzer.shared
        let metrics = analyzer.computeMetrics(for: windows, platform: nil, timeRange: .month)
        let dailyData = analyzer.computeDailyMetrics(windows: windows, platform: nil, timeRange: .month)
        
        let result = ExportService.shared.exportSummaryReport(
            metrics: metrics,
            dailyData: dailyData,
            goals: goals
        )
        ExportService.shared.saveExport(result)
    }
    
    @Query(sort: \ResponseWindow.computedAt, order: .reverse)
    private var allWindows: [ResponseWindow]
    
    private var aboutView: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 4) {
                Text("Response Time")
                    .font(.title.bold())
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("Version \(version) (\(build))")
                    .foregroundColor(.secondary)
            }
            
            Text("Privacy-first response time analytics.\nAll data stays on your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Quick stats summary
            VStack(spacing: 8) {
                let valid = allWindows.filter(\.isValidForAnalytics)
                HStack(spacing: 24) {
                    VStack {
                        Text("\(valid.count)")
                            .font(.title2.bold())
                        Text("Responses tracked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !valid.isEmpty {
                        let latencies = valid.map(\.latencySeconds).sorted()
                        VStack {
                            Text(formatDuration(latencies[latencies.count / 2]))
                                .font(.title2.bold())
                            Text("Overall median")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/markoalleno/response-time")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/markoalleno/response-time/issues")!)
            }
            
            Spacer()
            
            Text("© 2025 Mark Allen. Built with Swift & SwiftUI.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
    }
    
    private var platformsSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // iMessage Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("iMessage")
                                    .font(.headline)
                                Text("Read local Messages database")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            iMessageStatusBadge
                        }
                        
                        Divider()
                        
                        if !hasFullDiskAccess {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Full Disk Access Required")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                Text("Response Time needs Full Disk Access to read your Messages database. Your messages stay on your device — we only read timestamps.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button("Open System Settings") {
                                    openFullDiskAccessSettings()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Label("Connected — reading from Messages database", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        }
                    }
                    .padding(8)
                }
                
                // Gmail Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Gmail")
                                    .font(.headline)
                                Text("Connect via OAuth")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                }
                
                // Telegram Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Telegram")
                                    .font(.headline)
                                Text("Import from data export")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                }
                
                Spacer()
            }
            .padding(20)
        }
    }
    
    @ViewBuilder
    private var iMessageStatusBadge: some View {
        if hasFullDiskAccess {
            Text("Connected")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)
        } else {
            Text("Setup Required")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(4)
        }
    }
    
    private var hasFullDiskAccess: Bool {
        let testPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        return FileManager.default.isReadableFile(atPath: testPath)
    }
    
    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
    
    // MARK: - Shared Views
    
    private var privacyInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local Processing Only", systemImage: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("All data is processed and stored on your device")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Label("No Message Content", systemImage: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("We only access timestamps and participant metadata")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Label("No Cloud Analytics", systemImage: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("No data is sent to external servers")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    #if os(iOS)
    private var iOSAboutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Response Time")
                        .font(.headline)
                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Privacy-first response time analytics for your communications.")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
            Link("Support", destination: URL(string: "mailto:support@example.com")!)
            
            Text("© 2025 Mark Allen")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    #endif
}

// MARK: - Export Data View (iOS)

#if os(iOS)
struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Export Your Data")
                    .font(.title2.bold())
                
                Text("Export all your response time data as a CSV file that you can open in Excel, Numbers, or any spreadsheet app.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                Button {
                    isExporting = true
                    // Generate and share CSV
                    let csv = "date,platform,from,response_time_minutes\n"
                    let data = Data(csv.utf8)
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("response-time-export.csv")
                    try? data.write(to: tempURL)
                    
                    // Share sheet would go here
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
#endif

#Preview {
    SettingsView()
        .environment(AppState())
}
