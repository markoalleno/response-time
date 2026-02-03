import SwiftUI
import SwiftData

// MARK: - Demo Data Generator

/// Generates realistic-looking demo data for the app
/// Used to showcase functionality before real accounts are connected
@MainActor
class DemoDataGenerator {
    
    /// Check if demo data should be shown (no real accounts exist)
    static func shouldShowDemoData(modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SourceAccount>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count == 0
    }
    
    /// Generate demo metrics for display
    static func generateDemoMetrics(timeRange: TimeRange) -> ResponseMetrics {
        // Base metrics that look realistic
        let baseMedian: TimeInterval = switch timeRange {
        case .today: Double.random(in: 1800...3600)      // 30min - 1h
        case .week: Double.random(in: 2400...4200)       // 40min - 1h10m
        case .month: Double.random(in: 2700...4800)      // 45min - 1h20m
        case .quarter: Double.random(in: 3000...5400)    // 50min - 1h30m
        case .year: Double.random(in: 3300...6000)       // 55min - 1h40m
        }
        
        // Add some variance
        let median = baseMedian
        let mean = median * Double.random(in: 1.1...1.3)
        let p90 = median * Double.random(in: 1.8...2.5)
        let p95 = p90 * Double.random(in: 1.1...1.3)
        
        // Sample count based on time range
        let sampleCount: Int = switch timeRange {
        case .today: Int.random(in: 8...25)
        case .week: Int.random(in: 50...150)
        case .month: Int.random(in: 200...500)
        case .quarter: Int.random(in: 500...1200)
        case .year: Int.random(in: 1500...4000)
        }
        
        // Trend (slightly positive on average - people tend to improve)
        let trendPercentage = Double.random(in: -15...10)
        let previousMedian = median / (1 + trendPercentage / 100)
        
        return ResponseMetrics(
            platform: nil,
            timeRange: timeRange,
            sampleCount: sampleCount,
            medianLatency: median,
            meanLatency: mean,
            p90Latency: p90,
            p95Latency: p95,
            minLatency: Double.random(in: 60...300),       // 1-5 min fastest
            maxLatency: Double.random(in: 28800...86400),  // 8-24h slowest
            workingHoursMedian: median * 0.7,              // 30% faster during work
            nonWorkingHoursMedian: median * 1.4,           // 40% slower off-hours
            previousPeriodMedian: previousMedian,
            trendPercentage: trendPercentage
        )
    }
    
    /// Generate demo daily metrics for trend chart
    static func generateDemoDailyMetrics(timeRange: TimeRange) -> [DailyMetrics] {
        let calendar = Calendar.current
        let now = Date()
        
        let days: Int = switch timeRange {
        case .today: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        }
        
        // Generate with a slight downward trend (improvement)
        let baseLatency: TimeInterval = 3600 // 1 hour base
        
        return (0..<min(days, 30)).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            
            // Slight improvement over time (newer = faster)
            let trendFactor = 1.0 + (Double(daysAgo) / Double(days) * 0.15)
            
            // Add daily variance
            let variance = Double.random(in: 0.7...1.3)
            
            // Weekend effect (slower on weekends)
            let weekday = calendar.component(.weekday, from: date)
            let weekendFactor = (weekday == 1 || weekday == 7) ? 1.3 : 1.0
            
            let latency = baseLatency * trendFactor * variance * weekendFactor
            
            return DailyMetrics(
                date: date,
                medianLatency: latency,
                messageCount: Int.random(in: 15...60),
                responseCount: Int.random(in: 8...35)
            )
        }.reversed()
    }
    
    /// Generate demo platform metrics
    static func generateDemoPlatformMetrics() -> [(Platform, TimeInterval)] {
        [
            (.gmail, Double.random(in: 2400...4800)),      // 40min - 1h20m
            (.slack, Double.random(in: 600...1800)),       // 10min - 30min (faster)
            (.outlook, Double.random(in: 2700...5400)),    // 45min - 1h30m
            (.imessage, Double.random(in: 300...900))      // 5min - 15min (fastest)
        ]
    }
    
    /// Generate demo distribution data
    static func generateDemoDistribution() -> [(bucket: String, count: Int)] {
        // Realistic distribution - most responses are quick
        let total = Double.random(in: 80...150)
        return [
            (bucket: "<1h", count: Int(total * 0.45)),
            (bucket: "1-2h", count: Int(total * 0.25)),
            (bucket: "2-4h", count: Int(total * 0.15)),
            (bucket: "4-8h", count: Int(total * 0.10)),
            (bucket: ">8h", count: Int(total * 0.05))
        ]
    }
    
    /// Generate demo recent responses
    static func generateDemoRecentResponses() -> [DemoResponse] {
        let platforms: [Platform] = [.gmail, .slack, .gmail, .outlook, .imessage]
        let senders = [
            "sarah@company.com",
            "team-updates",
            "john.smith@client.org",
            "support@service.com",
            "boss@company.com"
        ]
        
        return (0..<5).map { i in
            DemoResponse(
                id: UUID(),
                platform: platforms[i],
                sender: senders[i],
                latencySeconds: [
                    Double.random(in: 300...1800),
                    Double.random(in: 60...600),
                    Double.random(in: 1800...3600),
                    Double.random(in: 600...2400),
                    Double.random(in: 120...900)
                ][i],
                timestamp: Date().addingTimeInterval(-Double(i * 3600 + Int.random(in: 0...3600)))
            )
        }
    }
}

// MARK: - Demo Response Model

struct DemoResponse: Identifiable {
    let id: UUID
    let platform: Platform
    let sender: String
    let latencySeconds: TimeInterval
    let timestamp: Date
    
    var formattedLatency: String {
        formatDuration(latencySeconds)
    }
}

// MARK: - Demo Insights

struct DemoInsight: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    static let samples: [DemoInsight] = [
        DemoInsight(
            icon: "bolt.fill",
            color: .green,
            title: "Quick Responder",
            description: "You respond to Slack DMs 3x faster than email. Consider nudging important contacts there."
        ),
        DemoInsight(
            icon: "moon.stars.fill",
            color: .purple,
            title: "Night Owl Alert",
            description: "Your response times spike after 6 PM. Setting expectations could reduce stress."
        ),
        DemoInsight(
            icon: "chart.line.uptrend.xyaxis",
            color: .blue,
            title: "Improving Trend",
            description: "Your median response time improved 12% this month. Keep it up!"
        ),
        DemoInsight(
            icon: "calendar.badge.clock",
            color: .orange,
            title: "Tuesday Champion",
            description: "You're fastest on Tuesdays (avg 32 min). Mondays are your slowest (avg 1h 15m)."
        ),
        DemoInsight(
            icon: "person.2.fill",
            color: .cyan,
            title: "VIP Detection",
            description: "You prioritize responses to sarah@company.com — avg 8 min vs 52 min overall."
        )
    ]
}
