import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Widget Entry

struct ResponseTimeEntry: TimelineEntry {
    let date: Date
    let medianResponseTime: TimeInterval
    let goalProgress: Double
    let platformBreakdown: [(Platform, TimeInterval)]
    let configuration: ConfigurationAppIntent
}

// MARK: - Configuration Intent

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Response Time"
    static var description: IntentDescription = "View your response time metrics"
    
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
        "Time Range"
    }
    
    static var caseDisplayRepresentations: [WidgetTimeRange: DisplayRepresentation] {
        [
            .today: "Today",
            .week: "This Week",
            .month: "This Month"
        ]
    }
}

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ResponseTimeEntry {
        ResponseTimeEntry(
            date: Date(),
            medianResponseTime: 2700, // 45 minutes
            goalProgress: 0.78,
            platformBreakdown: [
                (.gmail, 3600),
                (.slack, 900)
            ],
            configuration: ConfigurationAppIntent()
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
        // In production, this would read from shared SwiftData container
        // For now, return sample data
        
        return ResponseTimeEntry(
            date: Date(),
            medianResponseTime: Double.random(in: 1800...5400),
            goalProgress: Double.random(in: 0.6...0.95),
            platformBreakdown: [
                (.gmail, Double.random(in: 2400...4800)),
                (.slack, Double.random(in: 600...1800))
            ],
            configuration: configuration
        )
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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Text(formatDuration(entry.medianResponseTime))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
            
            Text("Median")
                .font(.caption2)
                .foregroundColor(.secondary)
            
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
            if entry.configuration.showPlatforms {
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
                Text(entry.configuration.timeRange.rawValue.capitalized)
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
            if entry.configuration.showPlatforms {
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
        configuration: ConfigurationAppIntent()
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
        configuration: ConfigurationAppIntent()
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
        configuration: ConfigurationAppIntent()
    )
}
