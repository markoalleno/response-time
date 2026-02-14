import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [SourceAccount]
    
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case analytics = "Analytics"
        case goals = "Goals"
        case contacts = "Contacts"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .analytics: return "chart.xyaxis.line"
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
        .task {
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
            
            // Auto-sync iMessage on launch
            await performSync()
        }
        .sheet(isPresented: Binding(
            get: { appState.isOnboarding },
            set: { appState.isOnboarding = $0 }
        )) {
            OnboardingView()
                .environment(appState)
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
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(appState.isSyncing)
        #if os(macOS)
        .help(appState.lastSyncDate.map { "Last sync: \(formatRelativeTime($0))" } ?? "Sync now")
        #endif
    }
    
    private func performSync() async {
        appState.isSyncing = true
        defer { appState.isSyncing = false }
        
        do {
            // Sync iMessage data to SwiftData (creates MessageEvents + ResponseWindows)
            try await iMessageSyncService.shared.syncToSwiftData(modelContext: modelContext)
            appState.lastSyncDate = Date()
        } catch {
            appState.error = .syncFailed(error.localizedDescription)
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
    @Query(sort: \ResponseWindow.computedAt, order: .reverse)
    private var recentResponses: [ResponseWindow]
    
    @State private var metrics: ResponseMetrics?
    @State private var dailyData: [DailyMetrics] = []
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Hero metrics
                metricsHeader
                
                // Time range selector
                timeRangePicker
                
                // Main dashboard grid
                #if os(macOS)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    responseTimeCard
                    trendCard
                    platformBreakdownCard
                    goalsCard
                }
                #else
                LazyVStack(spacing: 16) {
                    responseTimeCard
                    trendCard
                    platformBreakdownCard
                    goalsCard
                }
                #endif
                
                // Recent activity
                recentActivitySection
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
                    #endif
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            Text("Response Time")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let metrics = metrics, metrics.sampleCount > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metrics.formattedMedian)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    
                    if let trend = metrics.trendPercentage {
                        HStack(spacing: 2) {
                            Image(systemName: metrics.trendDirection.icon)
                            Text("\(abs(Int(trend)))%")
                        }
                        .font(.subheadline)
                        .foregroundColor(metrics.trendDirection.color)
                    }
                }
                
                Text("Median \(appState.selectedTimeRange.displayName.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
            
            VStack(alignment: .leading, spacing: 12) {
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
                
                Text(valid.isEmpty ? "No data yet" : "\(Int(progress * 100))% of responses within target")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
                            Text(response.inboundEvent?.participantEmail ?? "Unknown")
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
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private func loadMetrics() async {
        // Check if we have real data or should show demo
        let hasRealData = !recentResponses.isEmpty
        
        if hasRealData {
            // Compute real metrics from response windows
            let analyzer = ResponseAnalyzer.shared
            let realMetrics = analyzer.computeMetrics(
                for: recentResponses.map { $0 },
                platform: appState.selectedPlatform,
                timeRange: appState.selectedTimeRange
            )
            await MainActor.run {
                metrics = realMetrics
                dailyData = analyzer.computeDailyMetrics(
                    windows: recentResponses.map { $0 },
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
    }
}

// MARK: - Trend Chart

struct TrendChart: View {
    let data: [DailyMetrics]
    
    var body: some View {
        // Simple line chart visualization
        GeometryReader { geo in
            Path { path in
                guard !data.isEmpty else { return }
                
                let maxLatency = data.map(\.medianLatency).max() ?? 1
                let stepX = geo.size.width / CGFloat(max(data.count - 1, 1))
                
                for (index, point) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geo.size.height - (CGFloat(point.medianLatency / maxLatency) * geo.size.height)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: [SourceAccount.self, ResponseWindow.self])
}
