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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header with chart selector
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
                
                // Time range
                timeRangePicker
                
                // Main chart
                chartContent
                    .frame(height: 400)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                
                // Stats grid
                statsGrid
                
                // Insights
                insightsSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            
            if responseWindows.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(sampleDailyData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Response Time", point.medianLatency / 60) // Convert to minutes
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
                    
                    ForEach(0..<7) { day in
                        HStack(spacing: 2) {
                            Text(days[day])
                                .font(.caption2)
                                .frame(width: 40, alignment: .leading)
                            
                            ForEach(0..<24) { hour in
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
    
    private func heatmapColor(day: Int, hour: Int) -> Color {
        // Simulated data - working hours (9-17) on weekdays are faster
        let isWorkingHour = hour >= 9 && hour <= 17
        let isWeekday = day >= 1 && day <= 5
        
        if isWeekday && isWorkingHour {
            return Color.green.opacity(Double.random(in: 0.6...0.9))
        } else if isWeekday {
            return Color.yellow.opacity(Double.random(in: 0.4...0.6))
        } else {
            return Color.orange.opacity(Double.random(in: 0.3...0.5))
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
                        .foregroundStyle(item.bucket == "<1h" ? Color.green : 
                                        item.bucket == "1-2h" ? Color.blue :
                                        item.bucket == "2-4h" ? Color.yellow :
                                        item.bucket == "4-8h" ? Color.orange : Color.red)
                    }
                }
                .chartXAxisLabel("Response Time")
                .chartYAxisLabel("Count")
            }
        }
    }
    
    private var distributionData: [(bucket: String, count: Int)] {
        // Sample distribution
        [
            (bucket: "<1h", count: 45),
            (bucket: "1-2h", count: 28),
            (bucket: "2-4h", count: 15),
            (bucket: "4-8h", count: 8),
            (bucket: ">8h", count: 4)
        ]
    }
    
    private var platformChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Platform")
                .font(.headline)
            
            if accounts.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(accounts) { account in
                        BarMark(
                            x: .value("Response Time", Double.random(in: 30...120)),
                            y: .value("Platform", account.platform.displayName)
                        )
                        .foregroundStyle(account.platform.color)
                    }
                }
                .chartXAxisLabel("Median (minutes)")
            }
        }
    }
    
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(title: "Fastest", value: "12m", icon: "bolt.fill", color: .green)
            StatCard(title: "Slowest", value: "4h 32m", icon: "tortoise.fill", color: .orange)
            StatCard(title: "Total Responses", value: "\(responseWindows.count)", icon: "arrow.right.arrow.left", color: .blue)
            StatCard(title: "Platforms", value: "\(accounts.count)", icon: "square.stack.3d.up", color: .purple)
        }
    }
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)
            
            VStack(spacing: 12) {
                InsightCard(
                    icon: "lightbulb.fill",
                    color: .yellow,
                    title: "Best Response Time",
                    description: "Your fastest responses are on Tuesdays between 10am-12pm"
                )
                
                InsightCard(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    title: "Attention Needed",
                    description: "Weekend response times have increased by 45% this month"
                )
                
                InsightCard(
                    icon: "trophy.fill",
                    color: .green,
                    title: "Goal Progress",
                    description: "You've met your 1-hour email response goal 78% of the time"
                )
            }
        }
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
    
    private var sampleDailyData: [DailyMetrics] {
        let calendar = Calendar.current
        return (0..<14).map { daysAgo in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!,
                medianLatency: Double.random(in: 1800...7200), // 30min - 2h
                messageCount: Int.random(in: 10...50),
                responseCount: Int.random(in: 5...30)
            )
        }.reversed()
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    AnalyticsView()
        .environment(AppState())
        .modelContainer(for: ResponseWindow.self)
}
