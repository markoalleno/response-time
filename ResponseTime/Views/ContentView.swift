import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [SourceAccount]
    
    @State private var selectedTab: Tab = .dashboard
    
    private let autoSyncTimer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()
    
    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case analytics = "Analytics"
        case digest = "Weekly Digest"
        case goals = "Goals"
        case contacts = "Contacts"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .analytics: return "chart.xyaxis.line"
            case .digest: return "calendar.badge.clock"
            case .goals: return "target"
            case .contacts: return "person.2"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }
    
    // MARK: - macOS Layout
    
    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationTitle(selectedTab.rawValue)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                syncButton
                
                if appState.error != nil {
                    Button {
                        appState.error = nil
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                    .help(appState.error?.localizedDescription ?? "Error")
                }
            }
        }
        .onAppear {
            // Only show onboarding once
            let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if !hasCompleted {
                appState.isOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
        .onReceive(autoSyncTimer) { _ in
            if !appState.isSyncing && UserDefaults.standard.bool(forKey: "syncInBackground") {
                Task { await performSync() }
            }
        }
        .alert("Sync Error", isPresented: Binding(
            get: { appState.error != nil },
            set: { if !$0 { appState.error = nil } }
        )) {
            Button("OK") { appState.error = nil }
            if let error = appState.error, error.localizedDescription.contains("Permission") || error.localizedDescription.contains("Full Disk Access") {
                #if os(macOS)
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                    appState.error = nil
                }
                #endif
            }
        } message: {
            if let error = appState.error {
                Text(error.localizedDescription)
            }
        }
        .task {
            // Auto-create iMessage source account if none exists and we have access
            if accounts.isEmpty {
                let testPath = NSHomeDirectory() + "/Library/Messages/chat.db"
                if FileManager.default.isReadableFile(atPath: testPath) {
                    let account = SourceAccount(platform: .imessage, displayName: "iMessage", isEnabled: true)
                    modelContext.insert(account)
                    try? modelContext.save()
                }
            }
            
            // Apply user settings to analyzer
            let analyzer = ResponseAnalyzer.shared
            analyzer.matchingWindowDays = UserDefaults.standard.integer(forKey: "matchingWindowDays")
            if analyzer.matchingWindowDays == 0 { analyzer.matchingWindowDays = 7 }
            analyzer.confidenceThreshold = Float(UserDefaults.standard.double(forKey: "confidenceThreshold"))
            if analyzer.confidenceThreshold == 0 { analyzer.confidenceThreshold = 0.7 }
            analyzer.workingHoursStart = UserDefaults.standard.integer(forKey: "workingHoursStart")
            if analyzer.workingHoursStart == 0 { analyzer.workingHoursStart = 9 }
            analyzer.workingHoursEnd = UserDefaults.standard.integer(forKey: "workingHoursEnd")
            if analyzer.workingHoursEnd == 0 { analyzer.workingHoursEnd = 17 }
            analyzer.excludeWeekends = UserDefaults.standard.bool(forKey: "excludeWeekends")
            
            // Defer auto-sync slightly to allow UI to render first
            // Only sync if user has enabled sync on launch AND data is stale
            if UserDefaults.standard.bool(forKey: "syncOnLaunch") {
                let lastSync = appState.lastSyncDate
                let isStale = lastSync == nil || Date().timeIntervalSince(lastSync!) > 1800 // 30 min
                
                if isStale {
                    // Run sync in lower-priority background task so it doesn't block this .task
                    Task(priority: .background) {
                        // Delay 500ms to let first frame render
                        try? await Task.sleep(for: .milliseconds(500))
                        await performSync()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isOnboarding },
            set: { appState.isOnboarding = $0 }
        )) {
            OnboardingView()
                .environment(appState)
        }
        .background {
            KeyboardShortcutView(selectedTab: $selectedTab)
        }
    }
    
    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(Tab.allCases.filter { $0 != .settings }) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            }
            
            if !accounts.isEmpty {
                Section("Connected") {
                    ForEach(accounts) { account in
                        HStack(spacing: 8) {
                            Image(systemName: account.platform.icon)
                                .foregroundColor(account.platform.color)
                            Text(account.displayName)
                                .lineLimit(1)
                            Spacer()
                            if account.isEnabled {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
            
            Section {
                NavigationLink(value: Tab.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
    #endif
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
                    .navigationTitle("Dashboard")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            syncButton
                        }
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            .tag(Tab.dashboard)
            
            NavigationStack {
                AnalyticsView()
                    .navigationTitle("Analytics")
            }
            .tabItem {
                Label("Analytics", systemImage: "chart.xyaxis.line")
            }
            .tag(Tab.analytics)
            
            NavigationStack {
                WeeklyDigestView()
                    .navigationTitle("Weekly")
            }
            .tabItem {
                Label("Weekly", systemImage: "calendar.badge.clock")
            }
            .tag(Tab.digest)
            
            NavigationStack {
                GoalsView()
                    .navigationTitle("Goals")
            }
            .tabItem {
                Label("Goals", systemImage: "target")
            }
            .tag(Tab.goals)
            
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(Tab.settings)
        }
        .onAppear {
            // Only show onboarding once
            let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if !hasCompleted {
                appState.isOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isOnboarding },
            set: { appState.isOnboarding = $0 }
        )) {
            OnboardingView()
                .environment(appState)
        }
    }
    #endif
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .analytics:
            AnalyticsView()
        case .digest:
            WeeklyDigestView()
        case .goals:
            GoalsView()
        case .contacts:
            ContactsView()
        case .settings:
            SettingsView()
        }
    }
    
    // MARK: - Sync Button
    
    private var syncButton: some View {
        Button {
            Task {
                await performSync()
            }
        } label: {
            if appState.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Syncing messages")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .accessibilityLabel("Sync messages")
            }
        }
        .disabled(appState.isSyncing)
        .accessibilityHint(appState.lastSyncDate.map { "Last synced \(formatRelativeTime($0))" } ?? "Sync your messages now")
        #if os(macOS)
        .help(appState.lastSyncDate.map { "Last sync: \(formatRelativeTime($0))" } ?? "Sync now")
        .keyboardShortcut("r", modifiers: .command)
        #endif
    }
    
    private func performSync() async {
        // Check permissions first
        let testPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        guard FileManager.default.isReadableFile(atPath: testPath) else {
            await MainActor.run {
                appState.error = .syncFailed("Full Disk Access required. Please grant permission in System Settings.")
            }
            return
        }
        
        appState.isSyncing = true
        defer { appState.isSyncing = false }
        
        do {
            // Clean up expired snoozes
            let expiredDescriptor = FetchDescriptor<DismissedPending>()
            if let all = try? modelContext.fetch(expiredDescriptor) {
                for d in all where !d.isActive {
                    modelContext.delete(d)
                }
            }
            
            // Sync iMessage data to SwiftData (creates MessageEvents + ResponseWindows)
            try await iMessageSyncService.shared.syncToSwiftData(modelContext: modelContext)
            await MainActor.run {
                appState.lastSyncDate = Date()
                appState.error = nil  // Clear any previous errors
            }
            
            // Check for threshold notifications
            // Metrics reload handled by DashboardView
        } catch {
            let errorMessage: String
            if error.localizedDescription.contains("permission") || error.localizedDescription.contains("access") {
                errorMessage = "Permission denied. Please grant Full Disk Access in System Settings."
            } else if error.localizedDescription.contains("database") || error.localizedDescription.contains("SQLite") {
                errorMessage = "Unable to read Messages database. Make sure Messages is not running."
            } else {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
            await MainActor.run {
                appState.error = .syncFailed(errorMessage)
            }
        }
    }
    
    private func checkThresholdNotifications() async {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled"),
              UserDefaults.standard.bool(forKey: "thresholdNotificationsEnabled") else { return }
        
        // Respect quiet hours
        if UserDefaults.standard.bool(forKey: "quietHoursEnabled") {
            let hour = Calendar.current.component(.hour, from: Date())
            let start = UserDefaults.standard.integer(forKey: "quietHoursStart")
            let end = UserDefaults.standard.integer(forKey: "quietHoursEnd")
            let isQuiet = start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
            if isQuiet { return }
        }
        
        let thresholdMinutes = UserDefaults.standard.integer(forKey: "thresholdMinutes")
        let threshold = TimeInterval(max(thresholdMinutes, 60) * 60)
        
        // Find pending conversations that exceed threshold
        let connector = iMessageConnector()
        guard let conversations = try? await connector.fetchAllConversations(days: 7) else { return }
        
        for conv in conversations where conv.pendingResponse && !conv.isGroupChat {
            guard let lastDate = conv.lastMessageDate else { continue }
            let waitTime = Date().timeIntervalSince(lastDate)
            
            if waitTime > threshold {
                let name = conv.participants.first?.displayIdentifier ?? conv.chatIdentifier
                try? await NotificationService.shared.notifyThresholdExceeded(
                    participant: name,
                    currentLatency: waitTime,
                    threshold: threshold
                )
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [SourceAccount]
    @Query private var dismissedPending: [DismissedPending]
    
    // Don't load all windows at startup — fetch on demand
    @State private var recentResponses: [ResponseWindow] = []
    @State private var metrics: ResponseMetrics?
    @State private var dailyData: [DailyMetrics] = []
    @State private var pendingContacts: [(name: String, identifier: String, waitingSince: Date)] = []
    @State private var isLoadingData = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Hero metrics
                metricsHeader
                
                // Time range selector
                timeRangePicker
                
                // Loading indicator
                if isLoadingData {
                    ProgressView("Loading analytics...")
                        .padding()
                }
                
                // Main dashboard grid
                #if os(macOS)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    responseScoreCard
                    responseTimeCard
                    trendCard
                    workingHoursCard
                    platformBreakdownCard
                    goalsCard
                }
                #else
                LazyVStack(spacing: 16) {
                    responseScoreCard
                    responseTimeCard
                    trendCard
                    workingHoursCard
                    platformBreakdownCard
                    goalsCard
                }
                #endif
                
                // Percentile + Velocity row
                if recentResponses.count >= 5 {
                    #if os(macOS)
                    HStack(spacing: 16) {
                        percentileCard
                        velocityCard
                    }
                    #else
                    percentileCard
                    velocityCard
                    #endif
                }
                
                // Recent responses
                recentResponsesList
                
                // Pending responses (actionable)
                pendingResponsesSection
                
                // Recent activity
                recentActivitySection
                
                // Last sync footer
                if let lastSync = appState.lastSyncDate {
                    HStack {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Last synced \(lastSync, style: .relative)")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(horizontalPadding)
            .padding(.vertical, 24)
        }
        .background(backgroundColor)
        .task {
            await loadMetrics()
        }
        .onChange(of: appState.selectedTimeRange) { _, _ in
            Task { await loadMetrics() }
        }
    }
    
    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 16
        #endif
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    @State private var permissionStatus: PermissionStatus = .unknown
    
    enum PermissionStatus {
        case unknown, granted, denied
    }
    
    private var metricsHeader: some View {
        VStack(spacing: 8) {
            if permissionStatus == .denied {
                // Permission banner
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text("Full Disk Access Required")
                        .font(.headline)
                    Text("Response Time needs permission to read your Messages database. Only timestamps are read — never message content.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    #if os(macOS)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open System Settings to grant Full Disk Access")
                    #endif
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Permission required: Full Disk Access")
            }
            
            Text("Response Time")
                .font(.headline)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            if let metrics = metrics, metrics.sampleCount > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metrics.formattedMedian)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .accessibilityLabel("Median response time: \(metrics.formattedMedian)")
                    
                    if let trend = metrics.trendPercentage {
                        HStack(spacing: 2) {
                            Image(systemName: metrics.trendDirection.icon)
                                .accessibilityHidden(true)
                            Text("\(abs(Int(trend)))%")
                        }
                        .font(.subheadline)
                        .foregroundColor(metrics.trendDirection.color)
                        .accessibilityLabel("Trend: \(trend < 0 ? "improving" : "declining") by \(abs(Int(trend)))%")
                    }
                }
                .accessibilityElement(children: .combine)
                
                Text("Median \(appState.selectedTimeRange.displayName.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                HStack(spacing: 16) {
                    Text("\(metrics.sampleCount) responses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastResponse = recentResponses.first {
                        Text("Last: \(lastResponse.computedAt, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Text(appState.isSyncing ? "Syncing..." : "No data yet — tap sync to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .task {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        let testPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        permissionStatus = FileManager.default.isReadableFile(atPath: testPath) ? .granted : .denied
    }
    
    private var timeRangePicker: some View {
        Picker("Time Range", selection: Binding(
            get: { appState.selectedTimeRange },
            set: { appState.selectedTimeRange = $0 }
        )) {
            ForEach(TimeRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        #if os(macOS)
        .frame(maxWidth: 400)
        #endif
        .accessibilityLabel("Select time range for analytics")
        .accessibilityValue(appState.selectedTimeRange.displayName)
    }
    
    private var responseScoreCard: some View {
        DashboardCard(title: "Response Score", icon: "star.fill") {
            let score = ResponseScore.compute(from: recentResponses)
            if score.overall == 0 {
                emptyState
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(score.grade)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(score.gradeColor))
                        Text("\(score.overall)/100")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 6) {
                        ScoreBar(label: "Speed", value: score.speedScore, color: .blue)
                            .help("How quickly you respond relative to your 1-hour target")
                        ScoreBar(label: "Consistency", value: score.consistencyScore, color: .purple)
                            .help("How consistent your response times are (low variance = high score)")
                        ScoreBar(label: "Coverage", value: score.coverageScore, color: .green)
                            .help("Percentage of responses within your target time")
                    }
                }
            }
        }
    }
    
    private func scoreColor(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }
    
    private var responseTimeCard: some View {
        DashboardCard(title: "Response Breakdown", icon: "clock.fill") {
            if let metrics = metrics {
                VStack(alignment: .leading, spacing: 12) {
                    MetricRow(label: "Median", value: metrics.formattedMedian)
                    MetricRow(label: "Mean", value: metrics.formattedMean)
                    MetricRow(label: "90th Percentile", value: metrics.formattedP90)
                    MetricRow(label: "Samples", value: "\(metrics.sampleCount)")
                }
            } else {
                emptyState
            }
        }
    }
    
    private var trendCard: some View {
        DashboardCard(title: "Trend", icon: "chart.line.uptrend.xyaxis") {
            if !dailyData.isEmpty {
                TrendChart(data: dailyData)
                    .frame(height: 150)
            } else {
                emptyState
            }
        }
    }
    
    private var workingHoursCard: some View {
        DashboardCard(title: "Work vs Off-Hours", icon: "briefcase.fill") {
            let valid = recentResponses.filter(\.isValidForAnalytics)
            let workHrs = valid.filter(\.isWorkingHours)
            let offHrs = valid.filter { !$0.isWorkingHours }
            
            if workHrs.isEmpty && offHrs.isEmpty {
                emptyState
            } else {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                        if !workHrs.isEmpty {
                            let latencies = workHrs.map(\.latencySeconds).sorted()
                            Text(formatDuration(latencies[latencies.count / 2]))
                                .font(.title3.bold())
                        } else {
                            Text("--")
                                .font(.title3.bold())
                                .foregroundColor(.secondary)
                        }
                        Text("Work hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(workHrs.count) responses")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .frame(height: 50)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.purple)
                        if !offHrs.isEmpty {
                            let latencies = offHrs.map(\.latencySeconds).sorted()
                            Text(formatDuration(latencies[latencies.count / 2]))
                                .font(.title3.bold())
                        } else {
                            Text("--")
                                .font(.title3.bold())
                                .foregroundColor(.secondary)
                        }
                        Text("Off hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(offHrs.count) responses")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var platformBreakdownCard: some View {
        DashboardCard(title: "By Platform", icon: "square.stack.3d.up.fill") {
            if accounts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(accounts) { account in
                        let platformWindows = recentResponses.filter {
                            $0.inboundEvent?.conversation?.sourceAccount?.platform == account.platform && $0.isValidForAnalytics
                        }
                        let latencies = platformWindows.map(\.latencySeconds).sorted()
                        let median = latencies.isEmpty ? nil : latencies[latencies.count / 2]
                        
                        HStack {
                            Image(systemName: account.platform.icon)
                                .foregroundColor(account.platform.color)
                                .frame(width: 20)
                            Text(account.platform.displayName)
                            Spacer()
                            Text(median.map { formatDuration($0) } ?? "--")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(median.map { $0 < 3600 ? .green : .orange } ?? .secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
    
    private var goalsCard: some View {
        DashboardCard(title: "Goals", icon: "target") {
            let valid = recentResponses.filter(\.isValidForAnalytics)
            let defaultTarget: TimeInterval = 3600 // 1 hour
            let withinTarget = valid.filter { $0.latencySeconds <= defaultTarget }
            let progress = valid.isEmpty ? 0.0 : Double(withinTarget.count) / Double(valid.count)
            
            HStack(spacing: 16) {
                GoalProgressRing(progress: progress, target: formatDuration(defaultTarget), lineWidth: 8)
                    .frame(width: 70, height: 70)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text(formatDuration(defaultTarget))
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progress >= 0.8 ? Color.green : progress >= 0.6 ? Color.yellow : Color.red)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                    
                    Text(valid.isEmpty ? "No data yet" : "\(Int(progress * 100))% within target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var recentResponsesList: some View {
        DashboardCard(title: "Recent Responses", icon: "clock.arrow.circlepath") {
            let recent = recentResponses.prefix(5)
            if recent.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, window in
                        HStack {
                            let email = window.inboundEvent?.participantEmail ?? "Unknown"
                            Text(email)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(formatDuration(window.latencySeconds))
                                .font(.caption.monospaced())
                                .foregroundColor(responseColor(for: window.latencySeconds))
                            
                            if let t = window.inboundEvent?.timestamp {
                                Text(t, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func responseColor(for latency: TimeInterval) -> Color {
        if latency < 900 { return .green }       // < 15 min
        if latency < 1800 { return .blue }       // < 30 min
        if latency < 3600 { return .orange }     // < 1 hr
        return .red
    }
    
    private var percentileCard: some View {
        let valid = recentResponses.filter(\.isValidForAnalytics)
        let latencies = valid.map(\.latencySeconds).sorted()
        let p50 = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        let p90 = latencies.isEmpty ? 0 : latencies[min(Int(Double(latencies.count) * 0.9), latencies.count - 1)]
        let p10 = latencies.isEmpty ? 0 : latencies[max(Int(Double(latencies.count) * 0.1), 0)]
        
        return HStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.title2)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Percentiles")
                    .font(.subheadline.bold())
                HStack(spacing: 12) {
                    VStack {
                        Text(formatDurationShort(p10))
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        Text("10th")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text(formatDurationShort(p50))
                            .font(.caption.bold())
                        Text("50th")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text(formatDurationShort(p90))
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("90th")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var velocityCard: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        
        let thisWeek = recentResponses.filter {
            ($0.inboundEvent?.timestamp ?? .distantPast) >= weekAgo
        }.count
        let lastWeek = recentResponses.filter {
            let t = $0.inboundEvent?.timestamp ?? .distantPast
            return t >= twoWeeksAgo && t < weekAgo
        }.count
        
        let dailyAvg = Double(thisWeek) / 7
        let change = lastWeek > 0 ? Int(((Double(thisWeek) - Double(lastWeek)) / Double(lastWeek)) * 100) : 0
        
        return HStack(spacing: 16) {
            Image(systemName: "speedometer")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Response Velocity")
                    .font(.subheadline.bold())
                Text("\(String(format: "%.1f", dailyAvg)) responses/day this week")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if lastWeek > 0 {
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "minus")
                    Text("\(abs(change))%")
                }
                .font(.subheadline)
                .foregroundColor(change > 10 ? .green : change < -10 ? .orange : .secondary)
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var activePendingContacts: [(name: String, identifier: String, waitingSince: Date)] {
        let dismissedIds = Set(
            dismissedPending
                .filter(\.isActive)
                .map(\.contactIdentifier)
        )
        return pendingContacts.filter { !dismissedIds.contains($0.identifier) }
    }
    
    private var pendingResponsesSection: some View {
        Group {
            if !activePendingContacts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .foregroundColor(.orange)
                        Text("Pending Responses")
                            .font(.headline)
                        Spacer()
                        Text("\(activePendingContacts.count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                        
                        Button {
                            // Archive all pending
                            for pending in activePendingContacts {
                                let dismissed = DismissedPending(contactIdentifier: pending.identifier, action: .archived)
                                modelContext.insert(dismissed)
                            }
                            try? modelContext.save()
                        } label: {
                            Text("Archive All")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        
                        let archivedCount = dismissedPending.filter(\.isActive).count
                        if archivedCount > 0 {
                            Button {
                                for d in dismissedPending { modelContext.delete(d) }
                                try? modelContext.save()
                            } label: {
                                Text("Show \(archivedCount) hidden")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    ForEach(activePendingContacts.prefix(8), id: \.identifier) { pending in
                        PendingResponseRow(
                            pending: pending,
                            onArchive: { archivePending(pending.identifier) },
                            onSnooze: { snoozePending(pending.identifier, hours: $0) }
                        )
                    }
                }
                .padding()
                .background(cardBackgroundColor)
                .cornerRadius(12)
            }
        }
    }
    
    private func archivePending(_ identifier: String) {
        let dismissed = DismissedPending(contactIdentifier: identifier, action: .archived)
        modelContext.insert(dismissed)
        try? modelContext.save()
    }
    
    private func cleanExpiredDismissals() {
        let expired = dismissedPending.filter { !$0.isActive }
        for d in expired { modelContext.delete(d) }
        if !expired.isEmpty { try? modelContext.save() }
    }
    
    private func snoozePending(_ identifier: String, hours: Int) {
        let until = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
        let dismissed = DismissedPending(contactIdentifier: identifier, action: .snoozed, snoozeUntil: until)
        modelContext.insert(dismissed)
        try? modelContext.save()
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Responses")
                    .font(.headline)
                Spacer()
            }
            
            if recentResponses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No responses yet")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Sync iMessage to see your response data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(recentResponses.prefix(5)) { response in
                    HStack {
                        if let event = response.inboundEvent,
                           let platform = event.conversation?.sourceAccount?.platform {
                            Image(systemName: platform.icon)
                                .foregroundColor(platform.color)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(response.inboundEvent?.conversation?.subject ?? response.inboundEvent?.participantEmail ?? "Unknown")
                                .lineLimit(1)
                            Text(response.computedAt, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(response.formattedLatency)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(response.latencySeconds < 3600 ? .green : .orange)
                    }
                    .padding(.vertical, 8)
                    
                    if response.id != recentResponses.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: permissionStatus == .denied ? "lock.shield" : "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if permissionStatus == .denied {
                Text("Permission Required")
                    .font(.headline)
                Text("Grant Full Disk Access to track your response times")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                #if os(macOS)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                #endif
            } else if appState.isSyncing {
                Text("Syncing Messages...")
                    .font(.headline)
                ProgressView()
                    .controlSize(.large)
                Text("This may take a moment on first sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No data yet")
                    .font(.headline)
                Text("Tap the sync button (⌘R) above to analyze your Messages")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }
    
    private func loadMetrics() async {
        isLoadingData = true
        defer { isLoadingData = false }
        
        // Fetch response windows — filter by validity and time range
        // Note: Can't use relationship traversal in predicates, so fetch all valid and filter in-memory
        let windowsDescriptor = FetchDescriptor<ResponseWindow>(
            predicate: #Predicate { window in
                window.isValidForAnalytics
            },
            sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
        )
        
        guard let allWindows = try? modelContext.fetch(windowsDescriptor) else {
            await MainActor.run {
                recentResponses = []
                metrics = nil
                dailyData = []
            }
            await loadPendingResponses()
            return
        }
        
        // Filter by time range in-memory (can't do in predicate due to optional chaining)
        let startDate = appState.selectedTimeRange.startDate
        let windows = allWindows.filter { window in
            guard let timestamp = window.inboundEvent?.timestamp else { return false }
            return timestamp >= startDate
        }
        
        await MainActor.run {
            recentResponses = windows
        }
        
        if !windows.isEmpty {
            // Compute real metrics from response windows
            let analyzer = ResponseAnalyzer.shared
            let realMetrics = analyzer.computeMetrics(
                for: windows,
                platform: appState.selectedPlatform,
                timeRange: appState.selectedTimeRange
            )
            await MainActor.run {
                metrics = realMetrics
                dailyData = analyzer.computeDailyMetrics(
                    windows: windows,
                    platform: appState.selectedPlatform,
                    timeRange: appState.selectedTimeRange
                )
            }
        } else {
            // No data — show empty state
            await MainActor.run {
                metrics = nil
                dailyData = []
            }
        }
        
        // Load pending responses
        await loadPendingResponses()
    }
    
    private func loadPendingResponses() async {
        let connector = iMessageConnector()
        do {
            let conversations = try await connector.fetchAllConversations(days: 7)
            let pending = conversations
                .filter { $0.pendingResponse && !$0.isGroupChat }
                .compactMap { conv -> (name: String, identifier: String, waitingSince: Date)? in
                    guard let lastDate = conv.lastMessageDate else { return nil }
                    let name = conv.displayName ?? conv.participants.first?.displayIdentifier ?? conv.chatIdentifier
                    return (name: name, identifier: conv.chatIdentifier, waitingSince: lastDate)
                }
                .sorted { $0.waitingSince < $1.waitingSince } // oldest first
            
            // Resolve names
            let resolver = ContactResolver.shared
            _ = await resolver.requestAccessAndLoad()
            
            var resolved: [(name: String, identifier: String, waitingSince: Date)] = []
            for p in pending {
                if let realName = await resolver.resolve(p.name) {
                    resolved.append((name: realName, identifier: p.identifier, waitingSince: p.waitingSince))
                } else {
                    resolved.append(p)
                }
            }
            
            await MainActor.run {
                pendingContacts = resolved
            }
        } catch {
            // Silently fail — pending is supplementary
        }
    }
}

// MARK: - Dashboard Card

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Trend Chart

import Charts

struct TrendChart: View {
    let data: [DailyMetrics]
    
    var body: some View {
        if data.isEmpty {
            Text("No data")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", point.medianLatency / 60)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", point.medianLatency / 60)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartYAxisLabel("min")
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
        }
    }
}

// MARK: - Score Bar

struct ScoreBar: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * Double(value) / 100)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) score: \(value) out of 100")
    }
}

// MARK: - Keyboard Shortcuts

struct KeyboardShortcutView: View {
    @Binding var selectedTab: ContentView.Tab
    
    var body: some View {
        Group {
            Button("") { selectedTab = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { selectedTab = .analytics }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { selectedTab = .digest }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { selectedTab = .goals }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { selectedTab = .contacts }
                .keyboardShortcut("5", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

// MARK: - Pending Response Row

struct PendingResponseRow: View {
    let pending: (name: String, identifier: String, waitingSince: Date)
    let onArchive: () -> Void
    let onSnooze: (Int) -> Void
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(pending.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("Waiting \(pending.waitingSince, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            let wait = Date().timeIntervalSince(pending.waitingSince)
            Text(formatDuration(wait))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(wait > 3600 ? .red : wait > 1800 ? .orange : .yellow)
                .accessibilityLabel("Waiting for \(formatDuration(wait))")
            
            #if os(macOS)
            Button {
                // Open Messages to this contact
                let identifier = pending.identifier
                if let url = URL(string: "imessage://\(identifier)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Reply in Messages")
            .frame(width: 24)
            #endif
            
            Menu {
                #if os(macOS)
                Button {
                    let identifier = pending.identifier
                    if let url = URL(string: "imessage://\(identifier)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Reply in Messages", systemImage: "arrowshape.turn.up.right")
                }
                Divider()
                #endif
                Button { onSnooze(1) } label: {
                    Label("Snooze 1 hour", systemImage: "clock")
                }
                Button { onSnooze(4) } label: {
                    Label("Snooze 4 hours", systemImage: "clock")
                }
                Button { onSnooze(24) } label: {
                    Label("Snooze until tomorrow", systemImage: "moon")
                }
                Divider()
                Button { onArchive() } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .frame(width: 24)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: [SourceAccount.self, ResponseWindow.self])
}
