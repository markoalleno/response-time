import WidgetKit
import SwiftUI
import AppIntents
import SQLite3

// MARK: - Widget Entry

struct ResponseTimeEntry: TimelineEntry {
    let date: Date
    let medianResponseTime: TimeInterval
    let goalProgress: Double
    let platformBreakdown: [(Platform, TimeInterval)]
    let timeRange: WidgetTimeRange
    let showPlatforms: Bool
    var grade: String = "--"
    var pendingCount: Int = 0
}

// MARK: - Configuration Intent

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Response Time"
    static let description: IntentDescription = IntentDescription("View your response time metrics")
    
    @Parameter(title: "Time Range", default: .week)
    var timeRange: WidgetTimeRange
    
    @Parameter(title: "Show Platforms", default: true)
    var showPlatforms: Bool
}

enum WidgetTimeRange: String, AppEnum {
    case today = "today"
    case week = "week"
    case month = "month"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Time Range")
    }
    
    static var caseDisplayRepresentations: [WidgetTimeRange: DisplayRepresentation] {
        [
            .today: DisplayRepresentation(title: "Today"),
            .week: DisplayRepresentation(title: "This Week"),
            .month: DisplayRepresentation(title: "This Month")
        ]
    }
}

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    typealias Entry = ResponseTimeEntry
    typealias Intent = ConfigurationAppIntent
    
    func placeholder(in context: Context) -> ResponseTimeEntry {
        ResponseTimeEntry(
            date: Date(),
            medianResponseTime: 2700, // 45 minutes
            goalProgress: 0.78,
            platformBreakdown: [
                (.gmail, 3600),
                (.slack, 900)
            ],
            timeRange: .week,
            showPlatforms: true
        )
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> ResponseTimeEntry {
        // Return current metrics for snapshot
        await loadMetrics(configuration: configuration)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<ResponseTimeEntry> {
        let entry = await loadMetrics(configuration: configuration)
        
        // Update every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func loadMetrics(configuration: ConfigurationAppIntent) async -> ResponseTimeEntry {
        // Try to read real iMessage stats
        let days: Int
        switch configuration.timeRange {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        }
        
        if let stats = readIMessageStats(days: days) {
            return ResponseTimeEntry(
                date: Date(),
                medianResponseTime: stats.median,
                goalProgress: stats.goalProgress,
                platformBreakdown: [(.imessage, stats.median)],
                timeRange: configuration.timeRange,
                showPlatforms: configuration.showPlatforms,
                grade: stats.grade,
                pendingCount: stats.pendingCount
            )
        }
        
        // Fallback: no data
        return ResponseTimeEntry(
            date: Date(),
            medianResponseTime: 0,
            goalProgress: 0,
            platformBreakdown: [],
            timeRange: configuration.timeRange,
            showPlatforms: configuration.showPlatforms
        )
    }
    
    private struct QuickStats {
        let median: TimeInterval
        let goalProgress: Double
        let grade: String
        let pendingCount: Int
    }
    
    private func readIMessageStats(days: Int) -> QuickStats? {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db").path
        
        guard FileManager.default.isReadableFile(atPath: dbPath) else { return nil }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database = db else { return nil }
        defer { sqlite3_close(database) }
        
        let coreDataEpoch: TimeInterval = 978307200
        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let coreDataNanos = Int64((sinceDate.timeIntervalSince1970 - coreDataEpoch) * 1_000_000_000)
        
        // Get messages grouped by handle, compute response times
        let query = """
            SELECT m.handle_id, m.date, m.is_from_me
            FROM message m
            WHERE m.date > \(coreDataNanos)
              AND m.item_type = 0
              AND m.handle_id > 0
            ORDER BY m.handle_id, m.date ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        var messagesByHandle: [Int64: [(date: Date, isFromMe: Bool)]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let handleId = sqlite3_column_int64(stmt, 0)
            let dateNanos = sqlite3_column_int64(stmt, 1)
            let isFromMe = sqlite3_column_int(stmt, 2) == 1
            let date = Date(timeIntervalSince1970: coreDataEpoch + Double(dateNanos) / 1_000_000_000)
            messagesByHandle[handleId, default: []].append((date, isFromMe))
        }
        
        var responseTimes: [TimeInterval] = []
        for (_, messages) in messagesByHandle {
            var lastInbound: Date?
            for msg in messages {
                if !msg.isFromMe {
                    lastInbound = msg.date
                } else if let inbound = lastInbound {
                    let latency = msg.date.timeIntervalSince(inbound)
                    if latency > 0 && latency < 7 * 86400 {
                        responseTimes.append(latency)
                    }
                    lastInbound = nil
                }
            }
        }
        
        guard !responseTimes.isEmpty else { return nil }
        
        let sorted = responseTimes.sorted()
        let median = sorted[sorted.count / 2]
        let target: TimeInterval = 3600
        let withinTarget = sorted.filter { $0 <= target }.count
        let goalProgress = Double(withinTarget) / Double(sorted.count)
        
        // Compute grade
        let speedRatio = min(median / target, 10)
        let speed = max(0, Int(100 * (1 - speedRatio / 10)))
        let grade = speed >= 90 ? "A+" : speed >= 80 ? "A" : speed >= 70 ? "B" : speed >= 60 ? "C" : speed >= 50 ? "D" : "F"
        
        // Count pending (rough: check last message per handle)
        var pendingCount = 0
        for (_, messages) in messagesByHandle {
            if let last = messages.last, !last.isFromMe {
                pendingCount += 1
            }
        }
        
        return QuickStats(median: median, goalProgress: goalProgress, grade: grade, pendingCount: pendingCount)
    }
}

// MARK: - Widget Views

struct ResponseTimeWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    var entry: Provider.Entry
    
    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .systemLarge:
            largeWidget
        default:
            smallWidget
        }
    }
    
    // MARK: - Small Widget
    
    private var smallWidget: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if entry.grade != "--" {
                    Text(entry.grade)
                        .font(.caption.bold())
                        .foregroundColor(gradeColor)
                }
            }
            
            Text(formatDuration(entry.medianResponseTime))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
            
            Text("Median")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if entry.pendingCount > 0 {
                Text("\(entry.pendingCount) pending")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            Spacer()
            
            // Goal progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * entry.goalProgress)
                }
            }
            .frame(height: 4)
            
            Text("\(Int(entry.goalProgress * 100))% on target")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Medium Widget
    
    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Main metric
            VStack(spacing: 4) {
                Text(formatDuration(entry.medianResponseTime))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Median")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.3))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor)
                            .frame(width: geo.size.width * entry.goalProgress)
                    }
                }
                .frame(height: 6)
                .frame(width: 100)
            }
            
            Divider()
            
            // Platform breakdown
            if entry.showPlatforms {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.platformBreakdown, id: \.0) { platform, latency in
                        HStack {
                            Image(systemName: platform.icon)
                                .foregroundColor(platform.color)
                                .frame(width: 16)
                            Text(platform.displayName)
                                .font(.caption)
                            Spacer()
                            Text(formatDuration(latency))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Large Widget
    
    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("Response Time")
                    .font(.headline)
                Spacer()
                Text(entry.timeRange.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Main metric
            HStack(alignment: .firstTextBaseline) {
                Text(formatDuration(entry.medianResponseTime))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("median")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Progress
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: geo.size.width * entry.goalProgress)
                    }
                }
                .frame(height: 8)
                
                Text("\(Int(entry.goalProgress * 100))% of responses within target")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Platform breakdown
            if entry.showPlatforms {
                Text("By Platform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(entry.platformBreakdown, id: \.0) { platform, latency in
                    HStack {
                        Image(systemName: platform.icon)
                            .foregroundColor(platform.color)
                            .frame(width: 20)
                        Text(platform.displayName)
                        Spacer()
                        Text(formatDuration(latency))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Footer
            HStack {
                Text("Updated \(entry.date, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var progressColor: Color {
        if entry.goalProgress >= 0.8 { return .green }
        if entry.goalProgress >= 0.6 { return .yellow }
        return .red
    }
    
    private var gradeColor: Color {
        switch entry.grade {
        case "A+", "A": return .green
        case "B": return .yellow
        case "C": return .orange
        default: return .red
        }
    }
}

// MARK: - Widget Definition

@main
struct ResponseTimeWidget: Widget {
    let kind: String = "ResponseTimeWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: Provider()
        ) { entry in
            ResponseTimeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Response Time")
        .description("Track your communication response times at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Helper Functions

private func formatDuration(_ seconds: TimeInterval) -> String {
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
        return "\(hours)h \(minutes)m"
    } else {
        let days = Int(seconds / 86400)
        return "\(days)d"
    }
}

// MARK: - Platform (duplicated for widget target)

enum Platform: String, CaseIterable, Identifiable {
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

// MARK: - Previews

#Preview(as: .systemSmall) {
    ResponseTimeWidget()
} timeline: {
    ResponseTimeEntry(
        date: Date(),
        medianResponseTime: 2700,
        goalProgress: 0.78,
        platformBreakdown: [(.gmail, 3600), (.slack, 900)],
        timeRange: .week,
        showPlatforms: true
    )
}

#Preview(as: .systemMedium) {
    ResponseTimeWidget()
} timeline: {
    ResponseTimeEntry(
        date: Date(),
        medianResponseTime: 2700,
        goalProgress: 0.78,
        platformBreakdown: [(.gmail, 3600), (.slack, 900)],
        timeRange: .week,
        showPlatforms: true
    )
}

#Preview(as: .systemLarge) {
    ResponseTimeWidget()
} timeline: {
    ResponseTimeEntry(
        date: Date(),
        medianResponseTime: 2700,
        goalProgress: 0.78,
        platformBreakdown: [(.gmail, 3600), (.slack, 900)],
        timeRange: .week,
        showPlatforms: true
    )
}
