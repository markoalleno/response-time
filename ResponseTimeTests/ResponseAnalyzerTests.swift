import XCTest
import SwiftData
@testable import Response_Time

@MainActor
final class ResponseAnalyzerTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var analyzer: ResponseAnalyzer!
    
    override func setUp() async throws {
        let schema = Schema([
            SourceAccount.self,
            Conversation.self,
            MessageEvent.self,
            ResponseWindow.self,
            ResponseGoal.self,
            Participant.self,
            UserPreferences.self,
            DismissedPending.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
        analyzer = ResponseAnalyzer.shared
        analyzer.configure(modelContext: modelContext)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }
    
    // MARK: - Response Window Computation
    
    func testComputeResponseWindowsFindsCorrectPairs() throws {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        
        let conversation = Conversation(id: "test_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        let now = Date()
        let inbound = MessageEvent(
            id: "msg1",
            conversation: conversation,
            timestamp: now.addingTimeInterval(-3600), // 1 hour ago
            direction: .inbound,
            participantEmail: "test@example.com"
        )
        let outbound = MessageEvent(
            id: "msg2",
            conversation: conversation,
            timestamp: now.addingTimeInterval(-1800), // 30 min ago
            direction: .outbound,
            participantEmail: "me@example.com"
        )
        modelContext.insert(inbound)
        modelContext.insert(outbound)
        
        let windows = analyzer.computeResponseWindows(for: conversation)
        
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first!.latencySeconds, 1800, accuracy: 1) // 30 minutes
        XCTAssertEqual(windows.first?.matchingMethod, .timeWindow)
    }
    
    func testComputeResponseWindowsSkipsExcluded() throws {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        
        let conversation = Conversation(id: "test_conv2", sourceAccount: account)
        modelContext.insert(conversation)
        
        let now = Date()
        let inbound = MessageEvent(
            id: "msg3",
            conversation: conversation,
            timestamp: now.addingTimeInterval(-3600),
            direction: .inbound,
            participantEmail: "test@example.com",
            isExcluded: true
        )
        let outbound = MessageEvent(
            id: "msg4",
            conversation: conversation,
            timestamp: now.addingTimeInterval(-1800),
            direction: .outbound,
            participantEmail: "me@example.com"
        )
        modelContext.insert(inbound)
        modelContext.insert(outbound)
        
        let windows = analyzer.computeResponseWindows(for: conversation)
        XCTAssertEqual(windows.count, 0)
    }
    
    func testComputeResponseWindowsConfidenceDecays() throws {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        
        let conversation = Conversation(id: "test_conv3", sourceAccount: account)
        modelContext.insert(conversation)
        
        let now = Date()
        // Inbound 3 days ago, response now
        let inbound = MessageEvent(
            id: "msg5",
            conversation: conversation,
            timestamp: now.addingTimeInterval(-3 * 86400),
            direction: .inbound,
            participantEmail: "test@example.com"
        )
        let outbound = MessageEvent(
            id: "msg6",
            conversation: conversation,
            timestamp: now,
            direction: .outbound,
            participantEmail: "me@example.com"
        )
        modelContext.insert(inbound)
        modelContext.insert(outbound)
        
        let windows = analyzer.computeResponseWindows(for: conversation)
        XCTAssertEqual(windows.count, 1)
        XCTAssertLessThan(windows.first!.confidence, 1.0) // Should have reduced confidence
    }
    
    // MARK: - Metrics Computation
    
    func testComputeMetricsCalculatesCorrectly() throws {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        let conversation = Conversation(id: "metrics_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        // Create response windows with known latencies and proper inbound events
        let latencies: [TimeInterval] = [600, 1200, 1800, 3600, 7200]
        var windows: [ResponseWindow] = []
        
        for (i, latency) in latencies.enumerated() {
            let inbound = MessageEvent(
                id: "metrics_in_\(i)",
                conversation: conversation,
                timestamp: Date().addingTimeInterval(-Double(i + 1) * 86400), // stagger by day
                direction: .inbound,
                participantEmail: "test@example.com"
            )
            modelContext.insert(inbound)
            
            let window = ResponseWindow(
                inboundEvent: inbound,
                latencySeconds: latency,
                confidence: 1.0,
                matchingMethod: .timeWindow
            )
            windows.append(window)
        }
        
        let metrics = analyzer.computeMetrics(
            for: windows,
            platform: nil,
            timeRange: .year
        )
        
        XCTAssertEqual(metrics.sampleCount, 5)
        XCTAssertEqual(metrics.medianLatency, 1800)
        XCTAssertEqual(metrics.minLatency, 600)
        XCTAssertEqual(metrics.maxLatency, 7200)
    }
    
    func testEmptyMetrics() {
        let metrics = analyzer.computeMetrics(for: [], platform: nil, timeRange: .week)
        XCTAssertEqual(metrics.sampleCount, 0)
        XCTAssertEqual(metrics.medianLatency, 0)
    }
    
    // MARK: - Format Duration
    
    func testFormatDurationSeconds() {
        XCTAssertEqual(formatDuration(30), "30s")
    }
    
    func testFormatDurationMinutes() {
        XCTAssertEqual(formatDuration(300), "5m")
    }
    
    func testFormatDurationHours() {
        XCTAssertEqual(formatDuration(3600), "1h")
        XCTAssertEqual(formatDuration(5400), "1h 30m")
    }
    
    func testFormatDurationDays() {
        XCTAssertEqual(formatDuration(86400), "1d")
        XCTAssertEqual(formatDuration(90000), "1d 1h")
    }
    
    // MARK: - DismissedPending Model
    
    func testDismissedPendingArchiveIsAlwaysActive() {
        let dismissed = DismissedPending(contactIdentifier: "+1234", action: .archived)
        modelContext.insert(dismissed)
        XCTAssertTrue(dismissed.isActive)
    }
    
    func testDismissedPendingSnoozeFutureIsActive() {
        let until = Date().addingTimeInterval(3600)
        let dismissed = DismissedPending(contactIdentifier: "+1234", action: .snoozed, snoozeUntil: until)
        modelContext.insert(dismissed)
        XCTAssertTrue(dismissed.isActive)
    }
    
    func testDismissedPendingSnoozePastIsInactive() {
        let until = Date().addingTimeInterval(-3600)
        let dismissed = DismissedPending(contactIdentifier: "+1234", action: .snoozed, snoozeUntil: until)
        modelContext.insert(dismissed)
        XCTAssertFalse(dismissed.isActive)
    }
    
    // MARK: - ResponseGoal Streaks
    
    func testResponseGoalStreakFields() {
        let goal = ResponseGoal(platform: .imessage, targetLatencySeconds: 3600)
        modelContext.insert(goal)
        XCTAssertEqual(goal.currentStreak, 0)
        XCTAssertEqual(goal.longestStreak, 0)
        XCTAssertNil(goal.lastStreakDate)
    }
    
    // MARK: - Daily Metrics
    
    func testComputeDailyMetrics() {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        let conversation = Conversation(id: "daily_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        let today = Calendar.current.startOfDay(for: Date())
        var windows: [ResponseWindow] = []
        
        for i in 0..<3 {
            let inbound = MessageEvent(
                id: "daily_in_\(i)",
                conversation: conversation,
                timestamp: today.addingTimeInterval(Double(i) * 3600),
                direction: .inbound,
                participantEmail: "test@example.com"
            )
            modelContext.insert(inbound)
            
            let w = ResponseWindow(
                inboundEvent: inbound,
                latencySeconds: Double(i + 1) * 600,
                confidence: 1.0,
                matchingMethod: .timeWindow
            )
            windows.append(w)
        }
        
        let daily = analyzer.computeDailyMetrics(windows: windows, platform: nil, timeRange: .week)
        XCTAssertFalse(daily.isEmpty)
        XCTAssertEqual(daily.first?.responseCount, 3)
    }
    
    // MARK: - Hourly Metrics
    
    func testComputeHourlyMetrics() {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        let conversation = Conversation(id: "hourly_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        let inbound = MessageEvent(
            id: "hourly_in",
            conversation: conversation,
            timestamp: Date(),
            direction: .inbound,
            participantEmail: "test@example.com"
        )
        modelContext.insert(inbound)
        
        let w = ResponseWindow(
            inboundEvent: inbound,
            latencySeconds: 1800,
            confidence: 1.0,
            matchingMethod: .timeWindow
        )
        
        let hourly = analyzer.computeHourlyMetrics(windows: [w])
        XCTAssertEqual(hourly.count, 24)
        let currentHour = Calendar.current.component(.hour, from: Date())
        XCTAssertEqual(hourly[currentHour].responseCount, 1)
    }
    
    // MARK: - Format Duration Short
    
    func testFormatDurationShort() {
        XCTAssertEqual(formatDurationShort(30), "30s")
        XCTAssertEqual(formatDurationShort(300), "5m")
        XCTAssertEqual(formatDurationShort(3600), "1h")
        XCTAssertEqual(formatDurationShort(86400), "1d")
    }
    
    // MARK: - Platform Enum
    
    func testPlatformProperties() {
        XCTAssertEqual(Platform.gmail.displayName, "Gmail")
        XCTAssertEqual(Platform.imessage.displayName, "iMessage")
        XCTAssertFalse(Platform.gmail.icon.isEmpty)
    }
    
    // MARK: - TimeRange
    
    func testTimeRangeStartDates() {
        let now = Date()
        for range in TimeRange.allCases {
            XCTAssertLessThan(range.startDate, now)
        }
    }
    
    // MARK: - Export Service
    
    func testExportCSV() {
        let account = SourceAccount(platform: .imessage, displayName: "Test")
        modelContext.insert(account)
        let conversation = Conversation(id: "export_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        let inbound = MessageEvent(
            id: "export_in",
            conversation: conversation,
            timestamp: Date().addingTimeInterval(-3600),
            direction: .inbound,
            participantEmail: "test@test.com"
        )
        modelContext.insert(inbound)
        
        let window = ResponseWindow(
            inboundEvent: inbound,
            latencySeconds: 1800,
            confidence: 0.9,
            matchingMethod: .timeWindow
        )
        
        let result = ExportService.shared.exportResponseData(windows: [window], format: .csv)
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertTrue(result.filename.hasSuffix(".csv"))
        XCTAssertEqual(result.mimeType, "text/csv")
        
        let csv = String(data: result.data, encoding: .utf8)!
        XCTAssertTrue(csv.contains("date,time,platform"))
        XCTAssertTrue(csv.contains("test@test.com"))
    }
    
    func testExportJSON() {
        let account = SourceAccount(platform: .gmail, displayName: "Gmail")
        modelContext.insert(account)
        let conversation = Conversation(id: "json_conv", sourceAccount: account)
        modelContext.insert(conversation)
        
        let inbound = MessageEvent(
            id: "json_in",
            conversation: conversation,
            timestamp: Date(),
            direction: .inbound,
            participantEmail: "user@gmail.com"
        )
        modelContext.insert(inbound)
        
        let window = ResponseWindow(
            inboundEvent: inbound,
            latencySeconds: 3600,
            confidence: 1.0,
            matchingMethod: .threadId
        )
        
        let result = ExportService.shared.exportResponseData(windows: [window], format: .json)
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertTrue(result.filename.hasSuffix(".json"))
        
        let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["total_records"] as? Int, 1)
    }
    
    func testExportSummaryReport() {
        let metrics = ResponseMetrics(
            platform: nil,
            timeRange: .week,
            sampleCount: 10,
            medianLatency: 1800,
            meanLatency: 2400,
            p90Latency: 5400,
            p95Latency: 7200,
            minLatency: 300,
            maxLatency: 10800,
            workingHoursMedian: 1200,
            nonWorkingHoursMedian: 3600,
            previousPeriodMedian: 2100,
            trendPercentage: -14.3
        )
        
        let result = ExportService.shared.exportSummaryReport(metrics: metrics, dailyData: [], goals: [])
        let markdown = String(data: result.data, encoding: .utf8)!
        XCTAssertTrue(markdown.contains("Response Time Summary Report"))
        XCTAssertTrue(markdown.contains("30m"))
        XCTAssertTrue(result.filename.hasSuffix(".md"))
    }
    
    // MARK: - ResponseWindow Properties
    
    func testResponseWindowFormattedLatency() {
        let window = ResponseWindow(latencySeconds: 5400, matchingMethod: .timeWindow)
        XCTAssertEqual(window.formattedLatency, "1h 30m")
        XCTAssertEqual(window.latencyMinutes, 90)
        XCTAssertEqual(window.latencyHours, 1.5)
    }
    
    // MARK: - ResponseGoal Properties
    
    func testResponseGoalFormattedTarget() {
        let goal = ResponseGoal(targetLatencySeconds: 3600)
        XCTAssertEqual(goal.formattedTarget, "1h")
        XCTAssertEqual(goal.targetMinutes, 60)
    }
    
    // MARK: - Conversation Properties
    
    func testConversationCounts() {
        let conv = Conversation(id: "count_conv")
        modelContext.insert(conv)
        
        let in1 = MessageEvent(id: "c_in1", conversation: conv, timestamp: Date(), direction: .inbound, participantEmail: "a@b.com")
        let out1 = MessageEvent(id: "c_out1", conversation: conv, timestamp: Date(), direction: .outbound, participantEmail: "me@b.com")
        modelContext.insert(in1)
        modelContext.insert(out1)
        
        XCTAssertEqual(conv.inboundCount, 1)
        XCTAssertEqual(conv.outboundCount, 1)
    }
    
    // MARK: - Participant
    
    func testParticipantInitials() {
        let p = Participant(email: "john@test.com", displayName: "John Doe")
        XCTAssertEqual(p.initials, "JD")
        XCTAssertEqual(p.label, "John Doe")
        
        let p2 = Participant(email: "hello@world.com")
        XCTAssertEqual(p2.label, "hello@world.com")
    }
}
