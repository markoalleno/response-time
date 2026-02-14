import SwiftUI
import Charts

// MARK: - Response Trend Chart

struct ResponseTrendChart: View {
    let data: [DailyMetrics]
    let goalTarget: TimeInterval?
    
    var body: some View {
        Chart {
            // Area under the line
            ForEach(data) { point in
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
            
            // Main line
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Response Time", point.medianLatency / 60)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            
            // Points
            ForEach(data) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Response Time", point.medianLatency / 60)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(30)
            }
            
            // Goal line
            if let goal = goalTarget {
                RuleMark(y: .value("Goal", goal / 60))
                    .foregroundStyle(.green.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
            }
        }
        .chartYAxisLabel("Minutes")
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayStride)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
    }
    
    private var dayStride: Int {
        if data.count > 14 { return 3 }
        if data.count > 7 { return 2 }
        return 1
    }
}

// MARK: - Distribution Chart

struct ResponseDistributionChart: View {
    let data: [(bucket: String, count: Int, color: Color)]
    
    var body: some View {
        Chart {
            ForEach(data, id: \.bucket) { item in
                BarMark(
                    x: .value("Bucket", item.bucket),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
            }
        }
        .chartYAxisLabel("Responses")
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
    
    static func generateDistribution(from windows: [ResponseWindow]) -> [(bucket: String, count: Int, color: Color)] {
        var buckets: [String: Int] = [
            "<30m": 0,
            "30m-1h": 0,
            "1-2h": 0,
            "2-4h": 0,
            "4-8h": 0,
            ">8h": 0
        ]
        
        for window in windows {
            let minutes = window.latencySeconds / 60
            switch minutes {
            case ..<30: buckets["<30m", default: 0] += 1
            case 30..<60: buckets["30m-1h", default: 0] += 1
            case 60..<120: buckets["1-2h", default: 0] += 1
            case 120..<240: buckets["2-4h", default: 0] += 1
            case 240..<480: buckets["4-8h", default: 0] += 1
            default: buckets[">8h", default: 0] += 1
            }
        }
        
        return [
            ("<30m", buckets["<30m"]!, .green),
            ("30m-1h", buckets["30m-1h"]!, .blue),
            ("1-2h", buckets["1-2h"]!, .yellow),
            ("2-4h", buckets["2-4h"]!, .orange),
            ("4-8h", buckets["4-8h"]!, .red),
            (">8h", buckets[">8h"]!, .purple)
        ]
    }
}

// MARK: - Platform Comparison Chart

struct PlatformComparisonChart: View {
    let data: [(platform: Platform, median: TimeInterval)]
    
    var body: some View {
        Chart {
            ForEach(data, id: \.platform) { item in
                BarMark(
                    x: .value("Median", item.median / 60),
                    y: .value("Platform", item.platform.displayName)
                )
                .foregroundStyle(item.platform.color)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(formatDuration(item.median))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .chartXAxisLabel("Minutes")
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
    }
}

// MARK: - Hour Distribution Chart (Heatmap alternative)

struct HourlyResponseChart: View {
    let data: [HourlyMetrics]
    
    var body: some View {
        Chart {
            ForEach(data) { point in
                BarMark(
                    x: .value("Hour", "\(point.hour):00"),
                    y: .value("Response Time", point.medianLatency / 60)
                )
                .foregroundStyle(colorForLatency(point.medianLatency))
                .cornerRadius(2)
            }
        }
        .chartYAxisLabel("Minutes")
        .chartXAxis {
            AxisMarks(values: .stride(by: 4)) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
    
    private func colorForLatency(_ seconds: TimeInterval) -> Color {
        let minutes = seconds / 60
        switch minutes {
        case ..<30: return .green
        case 30..<60: return .blue
        case 60..<120: return .yellow
        case 120..<240: return .orange
        default: return .red
        }
    }
}

// MARK: - Weekly Pattern Chart

struct WeeklyPatternChart: View {
    let data: [(day: String, median: TimeInterval, count: Int)]
    
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        Chart {
            ForEach(data, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day),
                    y: .value("Response Time", item.median / 60)
                )
                .foregroundStyle(
                    isWeekend(item.day) ? Color.orange : Color.accentColor
                )
                .cornerRadius(4)
            }
        }
        .chartYAxisLabel("Minutes")
    }
    
    private func isWeekend(_ day: String) -> Bool {
        day == "Sun" || day == "Sat"
    }
    
    static func generateWeeklyPattern(from windows: [ResponseWindow]) -> [(day: String, median: TimeInterval, count: Int)] {
        let calendar = Calendar.current
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        var dayData: [Int: [TimeInterval]] = [:]
        
        for window in windows {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            let weekday = calendar.component(.weekday, from: timestamp) - 1
            dayData[weekday, default: []].append(window.latencySeconds)
        }
        
        return (0..<7).map { day in
            let latencies = dayData[day] ?? []
            let sorted = latencies.sorted()
            let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            return (day: days[day], median: median, count: latencies.count)
        }
    }
}

// MARK: - Goal Progress Ring

struct GoalProgressRing: View {
    let progress: Double
    let target: String
    let lineWidth: CGFloat
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            // Center text
            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: lineWidth * 1.5, weight: .bold, design: .rounded))
                Text(target)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var progressColor: Color {
        if progress >= 0.8 { return .green }
        if progress >= 0.6 { return .yellow }
        return .red
    }
}

// MARK: - Mini Sparkline

struct SparklineChart: View {
    let values: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            if !values.isEmpty {
                let maxValue = values.max() ?? 1
                let minValue = values.min() ?? 0
                let range = maxValue - minValue
                
                Path { path in
                    let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
                    
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedY = range > 0 ? (value - minValue) / range : 0.5
                        let y = geo.size.height - (CGFloat(normalizedY) * geo.size.height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1.5)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GoalProgressRing(progress: 0.78, target: "1h target", lineWidth: 10)
            .frame(width: 100, height: 100)
        
        SparklineChart(
            values: [45, 30, 55, 40, 35, 50, 42],
            color: .accentColor
        )
        .frame(height: 30)
    }
    .padding()
}
