import SwiftUI
import SwiftData
import Charts

struct WeeklyDigestView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ResponseWindow.computedAt, order: .reverse)
    private var allWindows: [ResponseWindow]
    
    @Query private var goals: [ResponseGoal]
    @Query private var accounts: [SourceAccount]
    
    @State private var weekOffset: Int = 0
    
    private var calendar: Calendar { Calendar.current }
    
    private var weekStart: Date {
        let now = Date()
        let shifted = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now)!
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: shifted))!
    }
    
    private var weekEnd: Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart)!
    }
    
    private var weekWindows: [ResponseWindow] {
        allWindows.filter { w in
            guard let t = w.inboundEvent?.timestamp else { return false }
            return t >= weekStart && t < weekEnd && w.isValidForAnalytics
        }
    }
    
    private var previousWeekWindows: [ResponseWindow] {
        let prevStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        return allWindows.filter { w in
            guard let t = w.inboundEvent?.timestamp else { return false }
            return t >= prevStart && t < weekStart && w.isValidForAnalytics
        }
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Week navigation
                weekNavigator
                
                if weekWindows.isEmpty {
                    emptyWeek
                } else {
                    // Week score
                    weekScoreCard
                    
                    // Summary hero
                    summaryHero
                    
                    // Daily breakdown chart
                    dailyBreakdownCard
                    
                    // Stats grid
                    statsGrid
                    
                    // Top contacts this week
                    topContactsCard
                    
                    // Highlights
                    highlightsCard
                    
                    // Goal streaks
                    if !goals.isEmpty {
                        goalStreaksCard
                    }
                    
                    // Day-by-day breakdown
                    dayByDayCard
                }
            }
            .padding(24)
        }
        .background(backgroundColor)
    }
    
    // MARK: - Week Navigator
    
    private var weekNavigator: some View {
        HStack {
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Weekly Digest")
                    .font(.title2.bold())
                Text(weekRangeLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button { weekOffset = max(0, weekOffset - 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
        }
    }
    
    private var weekRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }
    
    // MARK: - Week Score Card
    
    private var weekScoreCard: some View {
        let score = ResponseScore.compute(from: weekWindows)
        let prevScore = ResponseScore.compute(from: previousWeekWindows)
        let change = score.overall - prevScore.overall
        
        return HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(score.grade)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(gradeColor(score.gradeColor))
                Text("Week Score")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ScoreBar(label: "Speed", value: score.speedScore, color: .blue)
                ScoreBar(label: "Consistency", value: score.consistencyScore, color: .purple)
                ScoreBar(label: "Coverage", value: score.coverageScore, color: .green)
            }
            
            if prevScore.overall > 0 {
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: change > 0 ? "arrow.up" : change < 0 ? "arrow.down" : "minus")
                        Text("\(abs(change))")
                    }
                    .font(.title2.bold())
                    .foregroundColor(change > 0 ? .green : change < 0 ? .red : .secondary)
                    Text("vs last week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func gradeColor(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }
    
    // MARK: - Summary Hero
    
    private var summaryHero: some View {
        let latencies = weekWindows.map(\.latencySeconds).sorted()
        let median = latencies[latencies.count / 2]
        let prevLatencies = previousWeekWindows.map(\.latencySeconds).sorted()
        let prevMedian = prevLatencies.isEmpty ? nil : prevLatencies[prevLatencies.count / 2]
        let change: Double? = prevMedian.map { ((median - $0) / max($0, 1)) * 100 }
        
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatDuration(median))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                
                if let change = change {
                    HStack(spacing: 2) {
                        Image(systemName: change < 0 ? "arrow.down.right" : change > 0 ? "arrow.up.right" : "minus")
                        Text("\(abs(Int(change)))%")
                    }
                    .font(.title3)
                    .foregroundColor(change < -5 ? .green : change > 5 ? .red : .secondary)
                }
            }
            
            Text("Median response time")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 24) {
                VStack {
                    Text("\(weekWindows.count)")
                        .font(.title3.bold())
                    Text("responses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(formatDuration(latencies.first ?? 0))
                        .font(.title3.bold())
                        .foregroundColor(.green)
                    Text("fastest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(formatDuration(latencies.last ?? 0))
                        .font(.title3.bold())
                        .foregroundColor(.orange)
                    Text("slowest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    // MARK: - Daily Breakdown Chart
    
    private var dailyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Response Times")
                .font(.headline)
            
            let dailyData = computeDailyData()
            if dailyData.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(dailyData, id: \.day) { item in
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Minutes", item.median / 60)
                        )
                        .foregroundStyle(barColor(for: item.median))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if item.count > 0 {
                                Text(formatDurationShort(item.median))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartYAxisLabel("Minutes")
                .frame(height: 200)
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func barColor(for median: TimeInterval) -> Color {
        if median < 1800 { return .green }
        if median < 3600 { return .blue }
        if median < 7200 { return .yellow }
        return .orange
    }
    
    private func computeDailyData() -> [(day: String, median: TimeInterval, count: Int)] {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            let windows = weekWindows.filter {
                guard let t = $0.inboundEvent?.timestamp else { return false }
                return t >= day && t < dayEnd
            }
            let latencies = windows.map(\.latencySeconds).sorted()
            let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
            let weekday = calendar.component(.weekday, from: day) - 1
            return (day: dayNames[weekday], median: median, count: windows.count)
        }
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        let latencies = weekWindows.map(\.latencySeconds).sorted()
        let mean = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let p90 = latencies.isEmpty ? 0 : latencies[Int(Double(latencies.count) * 0.9)]
        let workHrs = weekWindows.filter(\.isWorkingHours)
        let workMedian = workHrs.isEmpty ? nil : workHrs.map(\.latencySeconds).sorted()[workHrs.count / 2]
        
        return LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            StatCard(title: "Mean", value: formatDuration(mean), icon: "function", color: .blue)
            StatCard(title: "90th %ile", value: formatDuration(p90), icon: "chart.bar.fill", color: .purple)
            StatCard(title: "Work Hours", value: workMedian.map { formatDuration($0) } ?? "--", icon: "briefcase.fill", color: .teal)
            StatCard(title: "Responses", value: "\(weekWindows.count)", icon: "arrow.right.arrow.left", color: .green)
        }
    }
    
    // MARK: - Top Contacts
    
    private var topContactsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Contacts This Week")
                .font(.headline)
            
            let contactData = computeContactBreakdown()
            if contactData.isEmpty {
                Text("No contact data").foregroundColor(.secondary)
            } else {
                ForEach(contactData.prefix(5), id: \.email) { contact in
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Text(String(contact.email.prefix(1)).uppercased())
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(contact.email)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(contact.count) responses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(formatDuration(contact.median))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(contact.median < 3600 ? .green : .orange)
                    }
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func computeContactBreakdown() -> [(email: String, count: Int, median: TimeInterval)] {
        var byContact: [String: [TimeInterval]] = [:]
        for w in weekWindows {
            let email = w.inboundEvent?.participantEmail ?? "unknown"
            byContact[email, default: []].append(w.latencySeconds)
        }
        return byContact.map { (email, latencies) in
            let sorted = latencies.sorted()
            return (email: email, count: latencies.count, median: sorted[sorted.count / 2])
        }.sorted { $0.count > $1.count }
    }
    
    // MARK: - Goal Streaks
    
    private var goalStreaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goal Streaks")
                .font(.headline)
            
            ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                GoalStreakRow(goal: goal)
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    struct GoalStreakRow: View {
        let goal: ResponseGoal
        
        var body: some View {
            HStack {
                let icon = goal.platform?.icon ?? "target"
                let color = goal.platform?.color ?? Color.accentColor
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(goal.platform?.displayName ?? "All Platforms") < \(goal.formattedTarget)")
                        .font(.subheadline)
                    Text("Current: \(goal.currentStreak) days · Best: \(goal.longestStreak) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if goal.currentStreak >= 3 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(goal.currentStreak)")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    // MARK: - Highlights
    
    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Highlights")
                .font(.headline)
            
            let latencies = weekWindows.map(\.latencySeconds).sorted()
            let highlights = computeHighlights(latencies: latencies)
            
            ForEach(highlights, id: \.text) { highlight in
                HStack(spacing: 10) {
                    Text(highlight.emoji)
                        .font(.title3)
                    Text(highlight.text)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private struct Highlight: Hashable {
        let emoji: String
        let text: String
    }
    
    private func computeHighlights(latencies: [TimeInterval]) -> [Highlight] {
        var highlights: [Highlight] = []
        
        // Fastest response
        if let fastest = latencies.first {
            highlights.append(Highlight(emoji: "⚡", text: "Fastest response: \(formatDuration(fastest))"))
        }
        
        // Total responses
        highlights.append(Highlight(emoji: "📊", text: "\(weekWindows.count) responses tracked"))
        
        // % under 30 min
        let under30 = latencies.filter { $0 < 1800 }.count
        let pct = latencies.isEmpty ? 0 : Int(Double(under30) / Double(latencies.count) * 100)
        highlights.append(Highlight(emoji: "🏃", text: "\(pct)% of responses under 30 minutes"))
        
        // Busiest day
        let dailyData = computeDailyData()
        if let busiest = dailyData.max(by: { $0.count < $1.count }), busiest.count > 0 {
            highlights.append(Highlight(emoji: "📅", text: "Busiest day: \(busiest.day) (\(busiest.count) responses)"))
        }
        
        // Peak hour
        var hourCounts: [Int: Int] = [:]
        for w in weekWindows {
            guard let t = w.inboundEvent?.timestamp else { continue }
            let h = calendar.component(.hour, from: t)
            hourCounts[h, default: 0] += 1
        }
        if let peakHour = hourCounts.max(by: { $0.value < $1.value }) {
            let hStr = peakHour.key == 0 ? "12 AM" : peakHour.key < 12 ? "\(peakHour.key) AM" : peakHour.key == 12 ? "12 PM" : "\(peakHour.key - 12) PM"
            highlights.append(Highlight(emoji: "🕐", text: "Most active hour: \(hStr) (\(peakHour.value) responses)"))
        }
        
        // Comparison to previous week
        let prevLatencies = previousWeekWindows.map(\.latencySeconds).sorted()
        if !prevLatencies.isEmpty && !latencies.isEmpty {
            let thisMedian = latencies[latencies.count / 2]
            let prevMedian = prevLatencies[prevLatencies.count / 2]
            if thisMedian < prevMedian {
                let improvement = Int(((prevMedian - thisMedian) / prevMedian) * 100)
                highlights.append(Highlight(emoji: "📈", text: "Improved \(improvement)% vs last week"))
            }
        }
        
        return highlights
    }
    
    // MARK: - Day by Day
    
    private var dayByDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day by Day")
                .font(.headline)
            
            let dailyData = computeDailyData()
            ForEach(dailyData.filter { $0.count > 0 }, id: \.day) { item in
                HStack {
                    Text(item.day)
                        .font(.subheadline.bold())
                        .frame(width: 40, alignment: .leading)
                    
                    GeometryReader { geo in
                        let maxMedian = dailyData.map(\.median).max() ?? 1
                        let width = maxMedian > 0 ? geo.size.width * (item.median / maxMedian) : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: item.median))
                            .frame(width: max(width, 4), height: 20)
                    }
                    .frame(height: 20)
                    
                    Text(formatDuration(item.median))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    // MARK: - Empty State
    
    private var emptyWeek: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No responses this week")
                .font(.headline)
            Text("Check a different week or sync your messages")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
}

#Preview {
    WeeklyDigestView()
        .environment(AppState())
        .modelContainer(for: ResponseWindow.self)
}
