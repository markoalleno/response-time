import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var responseWindows: [ResponseWindow]
    @Query private var accounts: [SourceAccount]
    
    @State private var selectedChart: ChartType = .trend
    @State private var hoveredPoint: DailyMetrics?
    
    enum ChartType: String, CaseIterable, Identifiable {
        case trend = "Trend"
        case heatmap = "Heatmap"
        case distribution = "Distribution"
        case byPlatform = "By Platform"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .trend: return "chart.line.uptrend.xyaxis"
            case .heatmap: return "square.grid.3x3.fill"
            case .distribution: return "chart.bar.fill"
            case .byPlatform: return "chart.pie.fill"
            }
        }
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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header with chart selector
                #if os(macOS)
                HStack {
                    Text("Analytics")
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    Picker("Chart", selection: $selectedChart) {
                        ForEach(ChartType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 400)
                }
                #else
                VStack(spacing: 12) {
                    Picker("Chart", selection: $selectedChart) {
                        ForEach(ChartType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                #endif
                
                // Time range
                timeRangePicker
                
                // Main chart
                chartContent
                    .frame(height: chartHeight)
                    .padding()
                    .background(cardBackgroundColor)
                    .cornerRadius(12)
                
                // Stats grid
                statsGrid
                
                // Insights
                insightsSection
            }
            .padding(viewPadding)
        }
        .background(backgroundColor)
    }
    
    private var viewPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 16
        #endif
    }
    
    private var chartHeight: CGFloat {
        #if os(macOS)
        return 400
        #else
        return 300
        #endif
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
    
    @ViewBuilder
    private var chartContent: some View {
        switch selectedChart {
        case .trend:
            trendChart
        case .heatmap:
            heatmapChart
        case .distribution:
            distributionChart
        case .byPlatform:
            platformChart
        }
    }
    
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time Trend")
                .font(.headline)
            
            let dailyData = realDailyData
            if dailyData.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(dailyData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Response Time", point.medianLatency / 60)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Response Time", point.medianLatency / 60)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxisLabel("Minutes")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
            }
        }
    }
    
    private var heatmapChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Day & Hour")
                .font(.headline)
            
            Text("Darker colors indicate faster response times")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if responseWindows.isEmpty {
                emptyChartState
            } else {
                // 7x24 grid for day of week x hour
                let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 2) {
                        // Hour labels
                        HStack(spacing: 2) {
                            Text("")
                                .frame(width: 40)
                            ForEach(0..<24) { hour in
                                Text("\(hour)")
                                    .font(.system(size: 8))
                                    .frame(width: 14)
                            }
                        }
                        
                        ForEach(0..<7, id: \.self) { day in
                            HStack(spacing: 2) {
                                Text(days[day])
                                    .font(.caption2)
                                    .frame(width: 40, alignment: .leading)
                                
                                ForEach(0..<24, id: \.self) { hour in
                                    Rectangle()
                                        .fill(heatmapColor(day: day, hour: hour))
                                        .frame(width: 14, height: 14)
                                        .cornerRadius(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func heatmapColor(day: Int, hour: Int) -> Color {
        // Use real data from response windows
        let matching = responseWindows.filter { window in
            window.dayOfWeek == (day + 1) && window.hourOfDay == hour && window.isValidForAnalytics
        }
        
        guard !matching.isEmpty else {
            return Color.secondary.opacity(0.1)
        }
        
        let latencies = matching.map(\.latencySeconds)
        let median = latencies.sorted()[latencies.count / 2]
        
        // Color based on median: green = fast, red = slow
        if median < 1800 {       // < 30 min
            return Color.green.opacity(0.7)
        } else if median < 3600 { // < 1 hour
            return Color.green.opacity(0.4)
        } else if median < 7200 { // < 2 hours
            return Color.yellow.opacity(0.5)
        } else if median < 14400 { // < 4 hours
            return Color.orange.opacity(0.5)
        } else {
            return Color.red.opacity(0.5)
        }
    }
    
    private var distributionChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time Distribution")
                .font(.headline)
            
            if responseWindows.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(distributionData, id: \.bucket) { item in
                        BarMark(
                            x: .value("Time", item.bucket),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(item.color)
                    }
                }
                .chartXAxisLabel("Response Time")
                .chartYAxisLabel("Count")
            }
        }
    }
    
    private var distributionData: [(bucket: String, count: Int, color: Color)] {
        ResponseDistributionChart.generateDistribution(from: responseWindows.filter(\.isValidForAnalytics))
    }
    
    private var platformChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Platform")
                .font(.headline)
            
            if accounts.isEmpty {
                emptyChartState
            } else {
                let platformData = computePlatformData()
                if platformData.isEmpty {
                    emptyChartState
                } else {
                    Chart {
                        ForEach(platformData, id: \.platform) { item in
                            BarMark(
                                x: .value("Response Time", item.median / 60),
                                y: .value("Platform", item.platform.displayName)
                            )
                            .foregroundStyle(item.platform.color)
                            .annotation(position: .trailing) {
                                Text(formatDuration(item.median))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .chartXAxisLabel("Median (minutes)")
                }
            }
        }
    }
    
    private func computePlatformData() -> [(platform: Platform, median: TimeInterval)] {
        let validWindows = responseWindows.filter(\.isValidForAnalytics)
        var result: [(platform: Platform, median: TimeInterval)] = []
        
        for account in accounts {
            let platformWindows = validWindows.filter {
                $0.inboundEvent?.conversation?.sourceAccount?.platform == account.platform
            }
            guard !platformWindows.isEmpty else { continue }
            let latencies = platformWindows.map(\.latencySeconds).sorted()
            let median = latencies[latencies.count / 2]
            result.append((platform: account.platform, median: median))
        }
        
        return result
    }
    
    private var statsGrid: some View {
        #if os(macOS)
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            statCards
        }
        #else
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCards
        }
        #endif
    }
    
    @ViewBuilder
    private var statCards: some View {
        let valid = responseWindows.filter(\.isValidForAnalytics)
        let latencies = valid.map(\.latencySeconds).sorted()
        StatCard(title: "Fastest", value: latencies.first.map { formatDuration($0) } ?? "--", icon: "bolt.fill", color: .green)
        StatCard(title: "Slowest", value: latencies.last.map { formatDuration($0) } ?? "--", icon: "tortoise.fill", color: .orange)
        StatCard(title: "Total Responses", value: "\(valid.count)", icon: "arrow.right.arrow.left", color: .blue)
        StatCard(title: "Platforms", value: "\(accounts.count)", icon: "square.stack.3d.up", color: .purple)
    }
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(computeInsights(), id: \.title) { insight in
                    InsightCard(
                        icon: insight.icon,
                        color: insight.color,
                        title: insight.title,
                        description: insight.description
                    )
                }
            }
        }
    }
    
    private struct InsightData: Sendable {
        let icon: String
        let color: Color
        let title: String
        let description: String
    }
    
    private func computeInsights() -> [InsightData] {
        let valid = responseWindows.filter(\.isValidForAnalytics)
        guard !valid.isEmpty else {
            return [InsightData(
                icon: "info.circle.fill",
                color: .blue,
                title: "Getting Started",
                description: "Sync your messages to see personalized insights about your response patterns."
            )]
        }
        
        var insights: [InsightData] = []
        
        // Best day/hour insight
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var bestDay = 1
        var bestDayMedian: TimeInterval = .infinity
        for day in 1...7 {
            let dayWindows = valid.filter { $0.dayOfWeek == day }
            guard !dayWindows.isEmpty else { continue }
            let latencies = dayWindows.map(\.latencySeconds).sorted()
            let median = latencies[latencies.count / 2]
            if median < bestDayMedian {
                bestDayMedian = median
                bestDay = day
            }
        }
        insights.append(InsightData(
            icon: "lightbulb.fill",
            color: .yellow,
            title: "Fastest Day",
            description: "Your fastest responses are on \(dayNames[bestDay])s — median \(formatDuration(bestDayMedian))"
        ))
        
        // Working vs non-working hours
        let workingWindows = valid.filter(\.isWorkingHours)
        let offWindows = valid.filter { !$0.isWorkingHours }
        if !workingWindows.isEmpty && !offWindows.isEmpty {
            let workMedian = workingWindows.map(\.latencySeconds).sorted()[workingWindows.count / 2]
            let offMedian = offWindows.map(\.latencySeconds).sorted()[offWindows.count / 2]
            let ratio = offMedian / max(workMedian, 1)
            if ratio > 1.5 {
                insights.append(InsightData(
                    icon: "moon.fill",
                    color: .purple,
                    title: "Off-Hours Slower",
                    description: "You respond \(String(format: "%.1f", ratio))x slower outside working hours (\(formatDuration(offMedian)) vs \(formatDuration(workMedian)))"
                ))
            }
        }
        
        // Total tracked
        insights.append(InsightData(
            icon: "chart.bar.fill",
            color: .blue,
            title: "Tracking Summary",
            description: "\(valid.count) response\(valid.count == 1 ? "" : "s") tracked across \(accounts.count) platform\(accounts.count == 1 ? "" : "s")"
        ))
        
        return insights
    }
    
    private var emptyChartState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No data to display")
                .foregroundColor(.secondary)
            Text("Connect a platform and sync to see analytics")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var realDailyData: [DailyMetrics] {
        let analyzer = ResponseAnalyzer.shared
        return analyzer.computeDailyMetrics(
            windows: responseWindows.map { $0 },
            platform: appState.selectedPlatform,
            timeRange: appState.selectedTimeRange
        )
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3.bold())
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
}

#Preview {
    AnalyticsView()
        .environment(AppState())
        .modelContainer(for: ResponseWindow.self)
}
