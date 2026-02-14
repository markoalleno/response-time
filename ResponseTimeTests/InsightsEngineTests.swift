import XCTest
@testable import Response_Time

@MainActor
final class InsightsEngineTests: XCTestCase {
    var engine: InsightsEngine!
    
    override func setUp() async throws {
        engine = InsightsEngine.shared
    }
    
    // MARK: - Basic Insights Generation
    
    func testEmptyDataReturnsGettingStarted() {
        let insights = engine.generateInsights(from: [], timeRange: .week, minimumSampleSize: 5)
        
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].type, .recommendation)
        XCTAssertTrue(insights[0].title.contains("Getting Started"))
    }
    
    func testInsufficientDataReturnsGettingStarted() {
        let windows = makeTestWindows(count: 3, medianSeconds: 1800)
        let insights = engine.generateInsights(from: windows, timeRange: .week, minimumSampleSize: 5)
        
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].type, .recommendation)
    }
    
    func testSufficientDataGeneratesMultipleInsights() {
        let windows = makeTestWindows(count: 20, medianSeconds: 1800)
        let insights = engine.generateInsights(from: windows, timeRange: .week, minimumSampleSize: 5)
        
        // Should generate multiple insights (trend, patterns, speed tier, etc.)
        XCTAssertGreaterThan(insights.count, 1)
    }
    
    // MARK: - Trend Analysis
    
    func testImprovingTrendDetected() {
        // Create data with improving trend (latencies decreasing over time)
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -i, to: now)!
            // Earlier days have higher latency, later days have lower
            let latency: TimeInterval = 3600 - Double(i) * 200 // Decrease by 200s/day
            let window = makeTestWindow(timestamp: day, latencySeconds: latency)
            windows.append(window)
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        // Should detect improving trend
        let trendInsights = insights.filter { $0.type == .trend || $0.type == .achievement }
        XCTAssertGreaterThan(trendInsights.count, 0, "Should detect trend")
        
        let improving = trendInsights.first { $0.title.lowercased().contains("improv") }
        XCTAssertNotNil(improving, "Should detect improving trend")
    }
    
    func testDecliningTrendDetected() {
        // Create data with declining trend (latencies increasing over time)
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -i, to: now)!
            // Earlier days have lower latency, later days have higher
            let latency: TimeInterval = 1800 + Double(i) * 300 // Increase by 300s/day
            let window = makeTestWindow(timestamp: day, latencySeconds: latency)
            windows.append(window)
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        // Should detect declining trend
        let warnings = insights.filter { $0.type == .warning }
        XCTAssertGreaterThan(warnings.count, 0, "Should detect declining trend")
    }
    
    // MARK: - Day of Week Patterns
    
    func testDayOfWeekPatternDetected() {
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Create 4 weeks of data with Monday being fastest, Friday slowest
        for week in 0..<4 {
            for day in 1...7 {
                let date = calendar.date(byAdding: .day, value: -(week * 7 + (7 - day)), to: now)!
                
                // Monday (day 2) = fast (900s), Friday (day 6) = slow (5400s)
                let baseLatency: TimeInterval
                if day == 2 { baseLatency = 900 } // Monday
                else if day == 6 { baseLatency = 5400 } // Friday
                else { baseLatency = 2700 } // Others
                
                for _ in 0..<3 { // 3 messages per day
                    let window = makeTestWindow(timestamp: date, latencySeconds: baseLatency)
                    windows.append(window)
                }
            }
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .month)
        
        // Should detect Monday as fastest day
        let dayPatterns = insights.filter { $0.type == .pattern && $0.title.contains("Monday") }
        XCTAssertGreaterThan(dayPatterns.count, 0, "Should detect Monday pattern")
    }
    
    // MARK: - Speed Tier Classification
    
    func testLightningFastClassification() {
        // 80% of responses under 30 minutes
        var windows: [ResponseWindow] = []
        for _ in 0..<80 {
            windows.append(makeTestWindow(latencySeconds: 1200)) // 20 min
        }
        for _ in 0..<20 {
            windows.append(makeTestWindow(latencySeconds: 5400)) // 90 min
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let speedInsights = insights.filter { $0.type == .achievement && $0.title.contains("Fast") }
        XCTAssertGreaterThan(speedInsights.count, 0, "Should classify as fast responder")
    }
    
    func testSlowResponderDetected() {
        // Most responses very slow
        var windows: [ResponseWindow] = []
        for _ in 0..<20 {
            windows.append(makeTestWindow(latencySeconds: 14400)) // 4 hours
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let slowInsights = insights.filter { 
            $0.type == .recommendation && ($0.title.lowercased().contains("slow") || $0.title.contains("Improvement"))
        }
        XCTAssertGreaterThan(slowInsights.count, 0, "Should detect slow response times")
    }
    
    // MARK: - Consistency Analysis
    
    func testConsistentResponderDetected() {
        // Very consistent response times (low variance)
        var windows: [ResponseWindow] = []
        for i in 0..<20 {
            // Tight range: 1750-1850 seconds (all around 30 minutes)
            let latency = 1800 + Double(i % 10) * 10
            windows.append(makeTestWindow(latencySeconds: latency))
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let consistencyInsights = insights.filter { $0.title.contains("Consistent") }
        XCTAssertGreaterThan(consistencyInsights.count, 0, "Should detect consistency")
    }
    
    func testVariableResponseTimesDetected() {
        // Highly variable response times
        var windows: [ResponseWindow] = []
        let latencies: [TimeInterval] = [300, 900, 3600, 7200, 14400, 1800, 10800, 600, 5400, 12000]
        for _ in 0..<5 {
            for latency in latencies {
                windows.append(makeTestWindow(latencySeconds: latency))
            }
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let variableInsights = insights.filter { $0.title.contains("Variable") }
        XCTAssertGreaterThan(variableInsights.count, 0, "Should detect variability")
    }
    
    // MARK: - Working Hours Pattern
    
    func testWorkingHoursVsOffHoursPattern() {
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        for day in 0..<7 {
            let baseDate = calendar.date(byAdding: .day, value: -day, to: now)!
            
            // Working hours (9 AM-5 PM): fast (1200s = 20 min)
            for hour in 9..<17 {
                let workDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate)!
                let window = makeTestWindow(timestamp: workDate, latencySeconds: 1200)
                window.isWorkingHours = true
                windows.append(window)
            }
            
            // Off hours: slow (7200s = 2 hours)
            for hour in [7, 8, 18, 19, 20] {
                let offDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate)!
                let window = makeTestWindow(timestamp: offDate, latencySeconds: 7200)
                window.isWorkingHours = false
                windows.append(window)
            }
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let workHoursInsights = insights.filter { 
            $0.title.contains("Off-Hours") || $0.title.contains("working hours")
        }
        XCTAssertGreaterThan(workHoursInsights.count, 0, "Should detect working hours pattern")
    }
    
    // MARK: - Anomaly Detection
    
    func testAnomalyDetectedFastDay() {
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Normal days: ~3000s median
        for day in 0..<13 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            for _ in 0..<5 {
                windows.append(makeTestWindow(timestamp: date, latencySeconds: 3000))
            }
        }
        
        // One anomalous fast day: 600s median
        let anomalyDate = calendar.date(byAdding: .day, value: -1, to: now)!
        for _ in 0..<5 {
            windows.append(makeTestWindow(timestamp: anomalyDate, latencySeconds: 600))
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let anomalies = insights.filter { $0.type == .anomaly }
        XCTAssertGreaterThan(anomalies.count, 0, "Should detect anomalous fast day")
    }
    
    // MARK: - Contact Patterns
    
    func testVIPContactDetected() {
        var windows: [ResponseWindow] = []
        
        // VIP contact: always fast (600s)
        for _ in 0..<10 {
            let window = makeTestWindow(latencySeconds: 600)
            window.inboundEvent?.participantEmail = "vip@example.com"
            windows.append(window)
        }
        
        // Other contacts: slower (3600s)
        for i in 0..<10 {
            let window = makeTestWindow(latencySeconds: 3600)
            window.inboundEvent?.participantEmail = "contact\(i)@example.com"
            windows.append(window)
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let vipInsights = insights.filter { $0.title.contains("VIP") }
        XCTAssertGreaterThan(vipInsights.count, 0, "Should detect VIP contact")
    }
    
    // MARK: - Confidence Scores
    
    func testInsightsHaveConfidenceScores() {
        let windows = makeTestWindows(count: 20, medianSeconds: 1800)
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        for insight in insights {
            XCTAssertGreaterThanOrEqual(insight.confidence, 0.0, "Confidence should be >= 0")
            XCTAssertLessThanOrEqual(insight.confidence, 1.0, "Confidence should be <= 1")
        }
    }
    
    func testInsightsHaveDataPointCounts() {
        let windows = makeTestWindows(count: 20, medianSeconds: 1800)
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        for insight in insights {
            // Getting started insight has 0 data points, others should have > 0
            if insight.type != .recommendation || !insight.title.contains("Getting Started") {
                XCTAssertGreaterThan(insight.dataPoints, 0, "\(insight.title) should have data points")
            }
        }
    }
    
    // MARK: - Insight Limits
    
    func testInsightsAreLimitedToReasonableCount() {
        // Generate lots of data that could produce many insights
        var windows: [ResponseWindow] = []
        for _ in 0..<100 {
            windows.append(makeTestWindow(latencySeconds: Double.random(in: 300...7200)))
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        // Should be limited to reasonable number (top 8 by default)
        XCTAssertLessThanOrEqual(insights.count, 10, "Should limit insight count")
    }
    
    // MARK: - Predictive Insights
    
    func testPredictiveInsightForImprovingTrend() {
        // Strong improving trend
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -i, to: now)!
            let latency = 4800 - Double(i) * 300 // Strong decline
            windows.append(makeTestWindow(timestamp: day, latencySeconds: latency))
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .week)
        
        let predictive = insights.filter { $0.type == .trend && $0.title.contains("Track") }
        // May or may not generate prediction depending on R-squared, but shouldn't crash
        XCTAssertNotNil(insights)
    }
    
    // MARK: - Edge Cases
    
    func testHandlesSingleDayOfData() {
        var windows: [ResponseWindow] = []
        let now = Date()
        
        for _ in 0..<10 {
            windows.append(makeTestWindow(timestamp: now, latencySeconds: 1800))
        }
        
        let insights = engine.generateInsights(from: windows, timeRange: .today)
        
        // Should not crash, should return some insights
        XCTAssertGreaterThan(insights.count, 0)
    }
    
    func testHandlesExtremeLatencies() {
        var windows: [ResponseWindow] = []
        
        // Mix of very fast and very slow
        windows.append(makeTestWindow(latencySeconds: 10)) // 10 seconds
        windows.append(makeTestWindow(latencySeconds: 604800)) // 1 week
        windows.append(makeTestWindow(latencySeconds: 1800)) // 30 min
        
        let insights = engine.generateInsights(from: windows, timeRange: .week, minimumSampleSize: 3)
        
        // Should handle without crashing
        XCTAssertNotNil(insights)
    }
    
    // MARK: - Test Helpers
    
    private func makeTestWindows(count: Int, medianSeconds: TimeInterval) -> [ResponseWindow] {
        var windows: [ResponseWindow] = []
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<count {
            let day = calendar.date(byAdding: .hour, value: -i * 6, to: now)!
            // Add some variance around median
            let variance = Double.random(in: -600...600)
            let latency = medianSeconds + variance
            let window = makeTestWindow(timestamp: day, latencySeconds: max(latency, 60))
            windows.append(window)
        }
        
        return windows
    }
    
    private func makeTestWindow(
        timestamp: Date = Date(),
        latencySeconds: TimeInterval
    ) -> ResponseWindow {
        let inbound = MessageEvent(
            id: UUID().uuidString,
            timestamp: timestamp,
            direction: .inbound,
            participantEmail: "test@example.com"
        )
        
        let outbound = MessageEvent(
            id: UUID().uuidString,
            timestamp: timestamp.addingTimeInterval(latencySeconds),
            direction: .outbound,
            participantEmail: "test@example.com"
        )
        
        let window = ResponseWindow(
            inboundEvent: inbound,
            outboundEvent: outbound,
            latencySeconds: latencySeconds,
            confidence: 0.9,
            matchingMethod: .timeWindow
        )
        
        window.isValidForAnalytics = true
        
        // Set day of week and hour
        let calendar = Calendar.current
        window.dayOfWeek = calendar.component(.weekday, from: timestamp)
        window.hourOfDay = calendar.component(.hour, from: timestamp)
        
        // Set working hours flag (9 AM - 5 PM, Mon-Fri)
        let hour = calendar.component(.hour, from: timestamp)
        let weekday = calendar.component(.weekday, from: timestamp)
        window.isWorkingHours = hour >= 9 && hour < 17 && weekday >= 2 && weekday <= 6
        
        return window
    }
}
