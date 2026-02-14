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
            UserPreferences.self
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
}
