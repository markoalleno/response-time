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
        case comparison = "Compare"
        case weekly = "Weekly"
        case heatmap = "Heatmap"
        case hourly = "Hourly"
        case distribution = "Distribution"
        case byPlatform = "By Platform"
        case byContact = "By Contact"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .trend: return "chart.line.uptrend.xyaxis"
            case .comparison: return "arrow.left.arrow.right"
            case .weekly: return "calendar"
            case .heatmap: return "square.grid.3x3.fill"
            case .hourly: return "clock"
            case .distribution: return "chart.bar.fill"
            case .byPlatform: return "chart.pie.fill"
            case .byContact: return "person.3.fill"
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
        case .comparison:
            comparisonChart
        case .weekly:
            weeklyPatternChart
        case .heatmap:
            heatmapChart
        case .hourly:
            hourlyChart
        case .distribution:
            distributionChart
        case .byPlatform:
            platformChart
        case .byContact:
            contactChart
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
    
    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Period vs Previous")
                .font(.headline)
            
            let current = realDailyData
            let previous = previousDailyData
            
            if current.isEmpty && previous.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(current) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Minutes", point.medianLatency / 60),
                            series: .value("Period", "Current")
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    ForEach(previous) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Minutes", point.medianLatency / 60),
                            series: .value("Period", "Previous")
                        )
                        .foregroundStyle(Color.secondary)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    }
                }
                .chartYAxisLabel("Minutes")
                .chartForegroundStyleScale([
                    "Current": Color.accentColor,
                    "Previous": Color.secondary
                ])
                
                // Summary
                let curMedian = current.isEmpty ? nil : current.map(\.medianLatency).sorted()[current.count / 2]
                let prevMedian = previous.isEmpty ? nil : previous.map(\.medianLatency).sorted()[previous.count / 2]
                
                if let cur = curMedian, let prev = prevMedian {
                    let change = ((cur - prev) / max(prev, 1)) * 100
                    HStack {
                        Image(systemName: change < 0 ? "arrow.down.right" : "arrow.up.right")
                            .foregroundColor(change < 0 ? .green : .red)
                        Text(change < 0 ? "Improved \(Int(abs(change)))% from previous period" : "Increased \(Int(change))% from previous period")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var previousDailyData: [DailyMetrics] {
        let analyzer = ResponseAnalyzer.shared
        let range = appState.selectedTimeRange
        let currentStart = range.startDate
        let duration = Date().timeIntervalSince(currentStart)
        let previousStart = currentStart.addingTimeInterval(-duration)
        
        // Filter windows to previous period and shift dates forward
        let previousWindows = responseWindows.filter { w in
            guard let t = w.inboundEvent?.timestamp else { return false }
            return t >= previousStart && t < currentStart && w.isValidForAnalytics
        }
        
        // Compute daily metrics but shift dates forward by `duration`
        let raw = analyzer.computeDailyMetrics(windows: previousWindows, platform: appState.selectedPlatform, timeRange: .year)
        return raw.map { DailyMetrics(date: $0.date.addingTimeInterval(duration), medianLatency: $0.medianLatency, messageCount: $0.messageCount, responseCount: $0.responseCount) }
    }
    
    private var weeklyPatternChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Day of Week")
                .font(.headline)
            
            let data = WeeklyPatternChart.generateWeeklyPattern(from: responseWindows.filter(\.isValidForAnalytics))
            if data.allSatisfy({ $0.count == 0 }) {
                emptyChartState
            } else {
                Chart {
                    ForEach(data.filter { $0.count > 0 }, id: \.day) { item in
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Minutes", item.median / 60)
                        )
                        .foregroundStyle(
                            (item.day == "Sun" || item.day == "Sat") ? Color.orange : Color.accentColor
                        )
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartYAxisLabel("Minutes")
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        Text("Weekday").font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Weekend").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var heatmapChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Day & Hour")
                .font(.headline)
            
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("<30m").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                    Text("30m-1h").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(.yellow).frame(width: 8, height: 8)
                    Text("1-2h").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("2-4h").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(">4h").font(.caption2).foregroundColor(.secondary)
                }
            }
            
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
        let matching = responseWindows.filter { window in
            window.dayOfWeek == (day + 1) && window.hourOfDay == hour && window.isValidForAnalytics
        }
        
        guard !matching.isEmpty else {
            return Color.secondary.opacity(0.08)
        }
        
        let latencies = matching.map(\.latencySeconds)
        let median = latencies.sorted()[latencies.count / 2]
        let count = matching.count
        
        // Intensity based on sample count (more data = more opaque)
        let intensity = min(Double(count) / 5.0, 1.0) * 0.3 + 0.4
        
        // Color based on median: green = fast, red = slow
        if median < 900 {        // < 15 min
            return Color.green.opacity(intensity)
        } else if median < 1800 { // < 30 min
            return Color.green.opacity(intensity * 0.7)
        } else if median < 3600 { // < 1 hour
            return Color.blue.opacity(intensity * 0.7)
        } else if median < 7200 { // < 2 hours
            return Color.yellow.opacity(intensity)
        } else if median < 14400 { // < 4 hours
            return Color.orange.opacity(intensity)
        } else {
            return Color.red.opacity(intensity)
        }
    }
    
    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Hour of Day")
                .font(.headline)
            
            let hourlyData = ResponseAnalyzer.shared.computeHourlyMetrics(windows: responseWindows.filter(\.isValidForAnalytics))
            let hasData = hourlyData.contains { $0.responseCount > 0 }
            
            if !hasData {
                emptyChartState
            } else {
                Chart {
                    ForEach(hourlyData.filter { $0.responseCount > 0 }) { point in
                        BarMark(
                            x: .value("Hour", "\(point.hour):00"),
                            y: .value("Minutes", point.medianLatency / 60)
                        )
                        .foregroundStyle(hourColor(point.medianLatency))
                        .cornerRadius(3)
                    }
                }
                .chartYAxisLabel("Minutes")
                
                // Working hours indicator
                let start = UserDefaults.standard.integer(forKey: "workingHoursStart")
                let end = UserDefaults.standard.integer(forKey: "workingHoursEnd")
                Text("Working hours: \(formatHour12(start == 0 ? 9 : start)) – \(formatHour12(end == 0 ? 17 : end))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func hourColor(_ seconds: TimeInterval) -> Color {
        if seconds < 1800 { return .green }
        if seconds < 3600 { return .blue }
        if seconds < 7200 { return .yellow }
        return .orange
    }
    
    private func formatHour12(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
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
    
    private var contactChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response Time by Contact")
                .font(.headline)
            
            let contactData = computeContactData()
            if contactData.isEmpty {
                emptyChartState
            } else {
                Chart {
                    ForEach(contactData, id: \.name) { item in
                        BarMark(
                            x: .value("Response Time", item.median / 60),
                            y: .value("Contact", item.name)
                        )
                        .foregroundStyle(item.median < 1800 ? Color.green : item.median < 3600 ? Color.blue : Color.orange)
                        .annotation(position: .trailing) {
                            Text(formatDuration(item.median))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartXAxisLabel("Median (minutes)")
                .frame(minHeight: CGFloat(contactData.count) * 35)
            }
        }
    }
    
    private func computeContactData() -> [(name: String, median: TimeInterval, count: Int)] {
        let validWindows = responseWindows.filter(\.isValidForAnalytics)
        
        // Group by participant email
        var byContact: [String: [TimeInterval]] = [:]
        for window in validWindows {
            guard let email = window.inboundEvent?.participantEmail else { continue }
            byContact[email, default: []].append(window.latencySeconds)
        }
        
        return byContact.map { (email, latencies) in
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            let name = email.contains("@") ? email : formatPhoneNumber(email)
            return (name: name, median: median, count: latencies.count)
        }
        .sorted { $0.median < $1.median }
        .prefix(15) // Top 15
        .map { $0 }
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.count == 11 && digits.hasPrefix("1") {
            let area = digits.dropFirst().prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        }
        return phone
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
    
    private struct InsightData {
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
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let dayShort = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        // Best day insight
        var bestDay = 1, worstDay = 1
        var bestDayMedian: TimeInterval = .infinity
        var worstDayMedian: TimeInterval = 0
        for day in 1...7 {
            let dayWindows = valid.filter { $0.dayOfWeek == day }
            guard !dayWindows.isEmpty else { continue }
            let latencies = dayWindows.map(\.latencySeconds).sorted()
            let median = latencies[latencies.count / 2]
            if median < bestDayMedian { bestDayMedian = median; bestDay = day }
            if median > worstDayMedian { worstDayMedian = median; worstDay = day }
        }
        if bestDay != worstDay && bestDayMedian < .infinity {
            insights.append(InsightData(
                icon: "calendar.badge.clock",
                color: .green,
                title: "You respond faster on \(dayNames[bestDay])s",
                description: "Median \(formatDuration(bestDayMedian)) on \(dayShort[bestDay]) vs \(formatDuration(worstDayMedian)) on \(dayShort[worstDay])"
            ))
        }
        
        // Best hour insight
        var bestHour = 0
        var bestHourMedian: TimeInterval = .infinity
        for hour in 0..<24 {
            let hourWindows = valid.filter { $0.hourOfDay == hour }
            guard hourWindows.count >= 2 else { continue }
            let latencies = hourWindows.map(\.latencySeconds).sorted()
            let median = latencies[latencies.count / 2]
            if median < bestHourMedian { bestHourMedian = median; bestHour = hour }
        }
        if bestHourMedian < .infinity {
            let hourStr = bestHour == 0 ? "12 AM" : bestHour < 12 ? "\(bestHour) AM" : bestHour == 12 ? "12 PM" : "\(bestHour - 12) PM"
            insights.append(InsightData(
                icon: "clock.fill",
                color: .blue,
                title: "Peak Hour: \(hourStr)",
                description: "Messages received around \(hourStr) get your fastest replies — median \(formatDuration(bestHourMedian))"
            ))
        }
        
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
            } else if ratio < 0.8 {
                insights.append(InsightData(
                    icon: "sun.max.fill",
                    color: .orange,
                    title: "Faster Off-Hours",
                    description: "You actually respond faster outside work hours — \(formatDuration(offMedian)) vs \(formatDuration(workMedian)) during work"
                ))
            }
        }
        
        // Speed tier insight
        let latencies = valid.map(\.latencySeconds).sorted()
        let median = latencies[latencies.count / 2]
        let under30min = valid.filter { $0.latencySeconds < 1800 }.count
        let under30pct = Double(under30min) / Double(valid.count) * 100
        if under30pct > 50 {
            insights.append(InsightData(
                icon: "bolt.fill",
                color: .yellow,
                title: "Speed Demon",
                description: "\(Int(under30pct))% of your responses are under 30 minutes. You're a fast responder!"
            ))
        } else if median > 14400 {
            insights.append(InsightData(
                icon: "tortoise.fill",
                color: .orange,
                title: "Taking Your Time",
                description: "Your median response is \(formatDuration(median)). Consider setting tighter goals."
            ))
        }
        
        // Improving/declining trend
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
        let thisWeek = valid.filter { ($0.inboundEvent?.timestamp ?? .distantPast) >= oneWeekAgo }
        let lastWeek = valid.filter {
            let t = $0.inboundEvent?.timestamp ?? .distantPast
            return t >= twoWeeksAgo && t < oneWeekAgo
        }
        if thisWeek.count >= 3 && lastWeek.count >= 3 {
            let thisMedian = thisWeek.map(\.latencySeconds).sorted()[thisWeek.count / 2]
            let lastMedian = lastWeek.map(\.latencySeconds).sorted()[lastWeek.count / 2]
            let change = ((thisMedian - lastMedian) / max(lastMedian, 1)) * 100
            if change < -15 {
                insights.append(InsightData(
                    icon: "arrow.down.right",
                    color: .green,
                    title: "Improving! 📈",
                    description: "Your response time dropped \(Int(abs(change)))% this week (\(formatDuration(thisMedian)) vs \(formatDuration(lastMedian)) last week)"
                ))
            } else if change > 15 {
                insights.append(InsightData(
                    icon: "arrow.up.right",
                    color: .red,
                    title: "Slowing Down",
                    description: "Response time increased \(Int(change))% this week (\(formatDuration(thisMedian)) vs \(formatDuration(lastMedian)) last week)"
                ))
            }
        }
        
        // Consistency insight
        if latencies.count >= 5 {
            let q1 = latencies[latencies.count / 4]
            let q3 = latencies[3 * latencies.count / 4]
            let iqr = q3 - q1
            if iqr < median * 0.5 {
                insights.append(InsightData(
                    icon: "metronome.fill",
                    color: .teal,
                    title: "Consistent Responder",
                    description: "Your response times are tightly clustered. Most fall between \(formatDuration(q1)) and \(formatDuration(q3))."
                ))
            } else if iqr > median * 2 {
                insights.append(InsightData(
                    icon: "waveform.path",
                    color: .orange,
                    title: "Variable Response Times",
                    description: "Your responses range widely — from \(formatDuration(q1)) to \(formatDuration(q3)). Consider identifying what causes delays."
                ))
            }
        }
        
        // Tracking summary (always last)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

#Preview {
    AnalyticsView()
        .environment(AppState())
        .modelContainer(for: ResponseWindow.self)
}
