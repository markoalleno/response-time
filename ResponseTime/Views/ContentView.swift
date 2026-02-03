import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [SourceAccount]
    
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case platforms = "Platforms"
        case analytics = "Analytics"
        case goals = "Goals"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .platforms: return "square.stack.3d.up"
            case .analytics: return "chart.xyaxis.line"
            case .goals: return "target"
            }
        }
    }
    
    var body: some View {
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
            if accounts.isEmpty {
                appState.isOnboarding = true
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
    
    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(Tab.allCases) { tab in
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
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .platforms:
            PlatformsView()
        case .analytics:
            AnalyticsView()
        case .goals:
            GoalsView()
        }
    }
    
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
        .help(appState.lastSyncDate.map { "Last sync: \(formatRelativeTime($0))" } ?? "Sync now")
    }
    
    private func performSync() async {
        appState.isSyncing = true
        defer { appState.isSyncing = false }
        
        // Simulated sync for now
        try? await Task.sleep(for: .seconds(2))
        appState.lastSyncDate = Date()
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
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // Response time card
                    responseTimeCard
                    
                    // Trend card
                    trendCard
                    
                    // Platform breakdown
                    platformBreakdownCard
                    
                    // Goals progress
                    goalsCard
                }
                
                // Recent activity
                recentActivitySection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadMetrics()
        }
        .onChange(of: appState.selectedTimeRange) { _, _ in
            Task { await loadMetrics() }
        }
    }
    
    private var metricsHeader: some View {
        VStack(spacing: 8) {
            Text("Response Time")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let metrics = metrics {
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
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
        .frame(maxWidth: 400)
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
                        HStack {
                            Image(systemName: account.platform.icon)
                                .foregroundColor(account.platform.color)
                                .frame(width: 20)
                            Text(account.platform.displayName)
                            Spacer()
                            Text("--")
                                .foregroundColor(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
    
    private var goalsCard: some View {
        DashboardCard(title: "Goals", icon: "target") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Target")
                    Spacer()
                    Text("1h")
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * 0.75)
                    }
                }
                .frame(height: 8)
                
                Text("75% of responses within target")
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
                if recentResponses.isEmpty {
                    Text("Demo Data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            if recentResponses.isEmpty {
                // Show demo responses
                ForEach(DemoDataGenerator.generateDemoRecentResponses()) { response in
                    HStack {
                        Image(systemName: response.platform.icon)
                            .foregroundColor(response.platform.color)
                        
                        VStack(alignment: .leading) {
                            Text(response.sender)
                                .lineLimit(1)
                            Text(response.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(response.formattedLatency)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(response.latencySeconds < 3600 ? .green : .orange)
                    }
                    .padding(.vertical, 8)
                    
                    Divider()
                }
                
                Text("Connect a platform to see your real data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
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
        .background(Color(nsColor: .controlBackgroundColor))
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
            // Show demo data to showcase the UI
            await MainActor.run {
                metrics = DemoDataGenerator.generateDemoMetrics(timeRange: appState.selectedTimeRange)
                dailyData = DemoDataGenerator.generateDemoDailyMetrics(timeRange: appState.selectedTimeRange)
            }
        }
    }
}

// MARK: - Dashboard Card

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
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
        .background(Color(nsColor: .controlBackgroundColor))
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
        // Placeholder chart - would use Swift Charts in production
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
