import Foundation
import SwiftData

/// Sophisticated scoring system for response time performance
/// Combines multiple factors into a single 0-100 score with letter grade
@MainActor
class ResponseScoreEngine {
    static let shared = ResponseScoreEngine()
    
    private init() {}
    
    // MARK: - Response Score
    
    struct ResponseScore {
        let overall: Int // 0-100
        let grade: String // A+ to F
        let gradeColor: String // Color name
        
        // Component scores (0-100 each)
        let speedScore: Int
        let consistencyScore: Int
        let coverageScore: Int
        let trendScore: Int
        let improvementScore: Int
        
        // Supporting data
        let totalResponses: Int
        let medianLatency: TimeInterval
        let p90Latency: TimeInterval
        let coefficientOfVariation: Double
        let trendSlope: Double?
        
        // Insights
        let strengths: [String]
        let weaknesses: [String]
    }
    
    // MARK: - Compute Score
    
    /// Compute comprehensive response score from windows
    func computeScore(
        from windows: [ResponseWindow],
        timeRange: TimeRange = .week,
        previousPeriodWindows: [ResponseWindow] = []
    ) -> ResponseScore {
        let valid = windows.filter(\.isValidForAnalytics)
        
        guard !valid.isEmpty else {
            return emptyScore()
        }
        
        let latencies = valid.map(\.latencySeconds).sorted()
        let median = latencies[latencies.count / 2]
        let p90 = latencies[Int(Double(latencies.count) * 0.9)]
        
        // Component scores
        let speedScore = computeSpeedScore(latencies: latencies)
        let consistencyScore = computeConsistencyScore(latencies: latencies)
        let coverageScore = computeCoverageScore(windowCount: valid.count, timeRange: timeRange)
        let trendScore = computeTrendScore(windows: valid)
        let improvementScore = computeImprovementScore(current: valid, previous: previousPeriodWindows)
        
        // Weighted overall score
        // Speed: 40%, Consistency: 25%, Coverage: 15%, Trend: 10%, Improvement: 10%
        let overall = Int(
            Double(speedScore) * 0.40 +
            Double(consistencyScore) * 0.25 +
            Double(coverageScore) * 0.15 +
            Double(trendScore) * 0.10 +
            Double(improvementScore) * 0.10
        )
        
        let grade = gradeFromScore(overall)
        let gradeColor = colorFromGrade(grade)
        
        // Coefficient of variation for analysis
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(latencies.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / max(mean, 1)
        
        // Trend slope (if enough data)
        let trendSlope = computeTrendSlope(windows: valid)
        
        // Analyze strengths and weaknesses
        let strengths = identifyStrengths(
            speedScore: speedScore,
            consistencyScore: consistencyScore,
            coverageScore: coverageScore,
            trendScore: trendScore,
            improvementScore: improvementScore
        )
        
        let weaknesses = identifyWeaknesses(
            speedScore: speedScore,
            consistencyScore: consistencyScore,
            coverageScore: coverageScore,
            trendScore: trendScore,
            improvementScore: improvementScore,
            median: median
        )
        
        return ResponseScore(
            overall: overall,
            grade: grade,
            gradeColor: gradeColor,
            speedScore: speedScore,
            consistencyScore: consistencyScore,
            coverageScore: coverageScore,
            trendScore: trendScore,
            improvementScore: improvementScore,
            totalResponses: valid.count,
            medianLatency: median,
            p90Latency: p90,
            coefficientOfVariation: cv,
            trendSlope: trendSlope,
            strengths: strengths,
            weaknesses: weaknesses
        )
    }
    
    // MARK: - Component Scores
    
    /// Speed score: How fast you respond (0-100)
    /// Based on median and p90 latency
    private func computeSpeedScore(latencies: [TimeInterval]) -> Int {
        let median = latencies[latencies.count / 2]
        let p90 = latencies[Int(Double(latencies.count) * 0.9)]
        
        // Targets: 30min (ideal), 1hr (good), 2hr (ok), 4hr (poor)
        let medianScore = scoreFromLatency(median, targets: [1800: 100, 3600: 80, 7200: 60, 14400: 40])
        let p90Score = scoreFromLatency(p90, targets: [3600: 100, 7200: 80, 14400: 60, 28800: 40])
        
        // Weighted: 70% median, 30% p90
        return Int(Double(medianScore) * 0.7 + Double(p90Score) * 0.3)
    }
    
    /// Consistency score: How consistent your response times are (0-100)
    /// Based on coefficient of variation
    private func computeConsistencyScore(latencies: [TimeInterval]) -> Int {
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(latencies.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / max(mean, 1)
        
        // Low CV = high consistency
        // cv < 0.3: excellent (95+)
        // cv < 0.5: good (80+)
        // cv < 1.0: fair (60+)
        // cv < 1.5: poor (40+)
        if cv < 0.3 {
            return 95 + Int((0.3 - cv) / 0.3 * 5)
        } else if cv < 0.5 {
            return 80 + Int((0.5 - cv) / 0.2 * 15)
        } else if cv < 1.0 {
            return 60 + Int((1.0 - cv) / 0.5 * 20)
        } else if cv < 1.5 {
            return 40 + Int((1.5 - cv) / 0.5 * 20)
        } else {
            return max(0, 40 - Int((cv - 1.5) * 10))
        }
    }
    
    /// Coverage score: How many responses you have tracked (0-100)
    /// More data = higher confidence in score
    private func computeCoverageScore(windowCount: Int, timeRange: TimeRange) -> Int {
        // Expected responses per time range
        let expected: Int
        switch timeRange {
        case .today: expected = 5
        case .week: expected = 30
        case .month: expected = 100
        case .quarter: expected = 300
        case .year: expected = 1000
        }
        
        let ratio = Double(windowCount) / Double(expected)
        
        if ratio >= 1.0 {
            return 100
        } else if ratio >= 0.7 {
            return 85 + Int((ratio - 0.7) / 0.3 * 15)
        } else if ratio >= 0.4 {
            return 70 + Int((ratio - 0.4) / 0.3 * 15)
        } else if ratio >= 0.2 {
            return 50 + Int((ratio - 0.2) / 0.2 * 20)
        } else {
            return Int(ratio / 0.2 * 50)
        }
    }
    
    /// Trend score: Whether response times are improving or declining (0-100)
    /// Based on linear regression slope
    private func computeTrendScore(windows: [ResponseWindow]) -> Int {
        guard windows.count >= 5 else { return 70 } // Neutral if insufficient data
        
        guard let slope = computeTrendSlope(windows: windows) else {
            return 70 // Neutral
        }
        
        // Negative slope = improving (scores > 70)
        // Positive slope = declining (scores < 70)
        // slope in seconds/day
        
        if slope < -300 {
            // Strong improvement: -5 min/day or more
            return min(100, 85 + Int(abs(slope) / 300 * 15))
        } else if slope < -100 {
            // Moderate improvement
            return 75 + Int(abs(slope) / 100 * 10)
        } else if slope > 300 {
            // Strong decline
            return max(0, 55 - Int(slope / 300 * 15))
        } else if slope > 100 {
            // Moderate decline
            return 65 - Int(slope / 100 * 10)
        } else {
            // Stable (slight variation is normal)
            return 70
        }
    }
    
    /// Improvement score: Comparison to previous period (0-100)
    private func computeImprovementScore(current: [ResponseWindow], previous: [ResponseWindow]) -> Int {
        guard !previous.isEmpty, !current.isEmpty else { return 70 } // Neutral if no comparison
        
        let currentMedian = current.map(\.latencySeconds).sorted()[current.count / 2]
        let previousMedian = previous.map(\.latencySeconds).sorted()[previous.count / 2]
        
        let change = ((currentMedian - previousMedian) / max(previousMedian, 1)) * 100
        
        // Negative change = improvement
        if change < -20 {
            return 100
        } else if change < -10 {
            return 90 + Int(abs(change + 10) / 10 * 10)
        } else if change < -5 {
            return 80 + Int(abs(change + 5) / 5 * 10)
        } else if change > 20 {
            return 40
        } else if change > 10 {
            return 50 + Int((20 - change) / 10 * 10)
        } else if change > 5 {
            return 60 + Int((10 - change) / 5 * 10)
        } else {
            // -5% to +5%: stable is good
            return 70 + Int((5 - abs(change)) / 5 * 10)
        }
    }
    
    // MARK: - Helpers
    
    private func scoreFromLatency(_ latency: TimeInterval, targets: [TimeInterval: Int]) -> Int {
        let sorted = targets.sorted { $0.key < $1.key }
        
        // Find the bracket
        for (threshold, score) in sorted {
            if latency <= threshold {
                return score
            }
        }
        
        // Worse than all targets
        let worstTarget = sorted.last!
        let excess = latency - worstTarget.key
        let penalty = Int(excess / 3600) * 5 // -5 points per hour beyond worst
        return max(0, worstTarget.value - penalty)
    }
    
    private func computeTrendSlope(windows: [ResponseWindow]) -> Double? {
        guard windows.count >= 5 else { return nil }
        
        // Group by day
        let calendar = Calendar.current
        var dailyData: [Date: [TimeInterval]] = [:]
        
        for window in windows {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            let day = calendar.startOfDay(for: timestamp)
            dailyData[day, default: []].append(window.latencySeconds)
        }
        
        guard dailyData.count >= 3 else { return nil }
        
        // Compute daily medians and linear regression
        let sorted = dailyData.sorted { $0.key < $1.key }
        let n = Double(sorted.count)
        let x = Array(0..<sorted.count).map { Double($0) }
        let y = sorted.map { day, latencies in
            latencies.sorted()[latencies.count / 2]
        }
        
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        
        return slope // seconds per day
    }
    
    private func gradeFromScore(_ score: Int) -> String {
        switch score {
        case 97...100: return "A+"
        case 93..<97: return "A"
        case 90..<93: return "A-"
        case 87..<90: return "B+"
        case 83..<87: return "B"
        case 80..<83: return "B-"
        case 77..<80: return "C+"
        case 73..<77: return "C"
        case 70..<73: return "C-"
        case 67..<70: return "D+"
        case 63..<67: return "D"
        case 60..<63: return "D-"
        default: return "F"
        }
    }
    
    private func colorFromGrade(_ grade: String) -> String {
        if grade.hasPrefix("A") { return "green" }
        if grade.hasPrefix("B") { return "blue" }
        if grade.hasPrefix("C") { return "yellow" }
        if grade.hasPrefix("D") { return "orange" }
        return "red"
    }
    
    private func identifyStrengths(
        speedScore: Int,
        consistencyScore: Int,
        coverageScore: Int,
        trendScore: Int,
        improvementScore: Int
    ) -> [String] {
        var strengths: [String] = []
        
        if speedScore >= 85 {
            strengths.append("Lightning-fast responses")
        }
        if consistencyScore >= 85 {
            strengths.append("Highly consistent timing")
        }
        if trendScore >= 80 {
            strengths.append("Strong improvement trend")
        }
        if improvementScore >= 85 {
            strengths.append("Significant progress vs previous period")
        }
        
        return strengths
    }
    
    private func identifyWeaknesses(
        speedScore: Int,
        consistencyScore: Int,
        coverageScore: Int,
        trendScore: Int,
        improvementScore: Int,
        median: TimeInterval
    ) -> [String] {
        var weaknesses: [String] = []
        
        if speedScore < 60 {
            weaknesses.append("Response times could be faster")
        }
        if consistencyScore < 60 {
            weaknesses.append("High variability in response times")
        }
        if coverageScore < 60 {
            weaknesses.append("Limited data for full analysis")
        }
        if trendScore < 60 {
            weaknesses.append("Response times are increasing")
        }
        if median > 7200 {
            weaknesses.append("Median response exceeds 2 hours")
        }
        
        return weaknesses
    }
    
    private func emptyScore() -> ResponseScore {
        ResponseScore(
            overall: 0,
            grade: "--",
            gradeColor: "secondary",
            speedScore: 0,
            consistencyScore: 0,
            coverageScore: 0,
            trendScore: 0,
            improvementScore: 0,
            totalResponses: 0,
            medianLatency: 0,
            p90Latency: 0,
            coefficientOfVariation: 0,
            trendSlope: nil,
            strengths: [],
            weaknesses: []
        )
    }
}
