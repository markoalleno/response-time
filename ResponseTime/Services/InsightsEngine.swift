import Foundation
import SwiftData

/// Statistical analysis engine for generating smart insights
@MainActor
class InsightsEngine {
    static let shared = InsightsEngine()
    
    private init() {}
    
    // MARK: - Insight Types
    
    struct Insight: Identifiable, Hashable {
        let id = UUID()
        let type: InsightType
        let icon: String
        let color: String // Color name
        let title: String
        let description: String
        let actionable: String?
        let confidence: Double // 0-1
        let dataPoints: Int
        
        enum InsightType: String {
            case trend
            case pattern
            case anomaly
            case comparison
            case recommendation
            case achievement
            case warning
        }
    }
    
    // MARK: - Generate Insights
    
    func generateInsights(
        from windows: [ResponseWindow],
        timeRange: TimeRange,
        minimumSampleSize: Int = 5
    ) -> [Insight] {
        let valid = windows.filter(\.isValidForAnalytics)
        guard valid.count >= minimumSampleSize else {
            return [Insight(
                type: .recommendation,
                icon: "info.circle.fill",
                color: "blue",
                title: "Getting Started",
                description: "Sync your messages to see personalized insights about your response patterns.",
                actionable: nil,
                confidence: 1.0,
                dataPoints: 0
            )]
        }
        
        var insights: [Insight] = []
        
        // Trend analysis
        insights.append(contentsOf: analyzeTrend(windows: valid, timeRange: timeRange))
        
        // Day-of-week patterns
        insights.append(contentsOf: analyzeDayOfWeekPatterns(windows: valid))
        
        // Time-of-day patterns
        insights.append(contentsOf: analyzeTimeOfDayPatterns(windows: valid))
        
        // Working hours vs off-hours
        insights.append(contentsOf: analyzeWorkingHoursPattern(windows: valid))
        
        // Response speed tier
        insights.append(contentsOf: analyzeSpeedTier(windows: valid))
        
        // Consistency analysis
        insights.append(contentsOf: analyzeConsistency(windows: valid))
        
        // Anomaly detection
        insights.append(contentsOf: detectAnomalies(windows: valid))
        
        // Contact-level insights
        insights.append(contentsOf: analyzeContactPatterns(windows: valid))
        
        // Predictive insights
        insights.append(contentsOf: generatePredictions(windows: valid, timeRange: timeRange))
        
        // Sort by confidence and take top insights
        return insights
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { $0 }
    }
    
    // MARK: - Trend Analysis
    
    /// Linear regression to detect improving/declining trends
    private func analyzeTrend(windows: [ResponseWindow], timeRange: TimeRange) -> [Insight] {
        let dailyData = computeDailyData(windows: windows)
        guard dailyData.count >= 5 else { return [] }
        
        // Linear regression: y = mx + b
        let n = Double(dailyData.count)
        let x = Array(0..<dailyData.count).map { Double($0) }
        let y = dailyData.map { $0.median }
        
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        // Slope indicates trend direction
        let medianLatency = dailyData.map(\.median).sorted()[dailyData.count / 2]
        let relativeChange = (slope * n) / max(medianLatency, 1)
        
        // R-squared for confidence
        let yMean = sumY / n
        let ssTotal = y.map { pow($0 - yMean, 2) }.reduce(0, +)
        let yPred = x.map { slope * $0 + intercept }
        let ssRes = zip(y, yPred).map { pow($0 - $1, 2) }.reduce(0, +)
        let rSquared = 1 - (ssRes / max(ssTotal, 0.001))
        
        var insights: [Insight] = []
        
        if abs(relativeChange) > 0.1 && rSquared > 0.3 {
            if relativeChange < -0.15 {
                // Strong improving trend
                let improvement = Int(abs(relativeChange) * 100)
                insights.append(Insight(
                    type: .trend,
                    icon: "chart.line.downtrend.xyaxis",
                    color: "green",
                    title: "Response Times Improving!",
                    description: "Your response time has decreased approximately \(improvement)% over the past \(timeRange.displayName).",
                    actionable: "Keep up the momentum by maintaining your current habits.",
                    confidence: rSquared,
                    dataPoints: dailyData.count
                ))
            } else if relativeChange > 0.15 {
                // Declining trend
                let decline = Int(relativeChange * 100)
                insights.append(Insight(
                    type: .warning,
                    icon: "chart.line.uptrend.xyaxis",
                    color: "orange",
                    title: "Response Times Increasing",
                    description: "Your response time has increased approximately \(decline)% over the past \(timeRange.displayName).",
                    actionable: "Consider reviewing your message handling habits or setting tighter goals.",
                    confidence: rSquared,
                    dataPoints: dailyData.count
                ))
            }
        } else if rSquared > 0.6 {
            // Strong correlation but small change = stability
            insights.append(Insight(
                type: .achievement,
                icon: "equal.circle.fill",
                color: "blue",
                title: "Consistent Response Times",
                description: "Your response times have remained stable over the past \(timeRange.displayName).",
                actionable: nil,
                confidence: rSquared,
                dataPoints: dailyData.count
            ))
        }
        
        return insights
    }
    
    // MARK: - Day-of-Week Patterns
    
    private func analyzeDayOfWeekPatterns(windows: [ResponseWindow]) -> [Insight] {
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let dayShort = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        var dayData: [Int: [TimeInterval]] = [:]
        for window in windows {
            let day = window.dayOfWeek
            dayData[day, default: []].append(window.latencySeconds)
        }
        
        // Find best and worst days with sufficient data
        var bestDay = 1, worstDay = 1
        var bestMedian: TimeInterval = .infinity
        var worstMedian: TimeInterval = 0
        
        for day in 1...7 {
            guard let latencies = dayData[day], latencies.count >= 3 else { continue }
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            if median < bestMedian { bestMedian = median; bestDay = day }
            if median > worstMedian { worstMedian = median; worstDay = day }
        }
        
        guard bestDay != worstDay, bestMedian < .infinity else { return [] }
        
        let ratio = worstMedian / max(bestMedian, 1)
        
        if ratio > 2.0 {
            // Significant difference
            return [Insight(
                type: .pattern,
                icon: "calendar.badge.clock",
                color: "green",
                title: "You respond \(String(format: "%.1f", ratio))x faster on \(dayNames[bestDay])s",
                description: "Median \(formatDuration(bestMedian)) on \(dayShort[bestDay]) vs \(formatDuration(worstMedian)) on \(dayShort[worstDay]).",
                actionable: "Consider batching messages for \(dayShort[worstDay]) to improve consistency.",
                confidence: 0.85,
                dataPoints: (dayData[bestDay]?.count ?? 0) + (dayData[worstDay]?.count ?? 0)
            )]
        } else if ratio > 1.5 {
            return [Insight(
                type: .pattern,
                icon: "calendar",
                color: "blue",
                title: "\(dayNames[bestDay])s are your fastest day",
                description: "Median \(formatDuration(bestMedian)) on \(dayShort[bestDay]) compared to \(formatDuration(worstMedian)) on \(dayShort[worstDay]).",
                actionable: nil,
                confidence: 0.75,
                dataPoints: (dayData[bestDay]?.count ?? 0) + (dayData[worstDay]?.count ?? 0)
            )]
        }
        
        return []
    }
    
    // MARK: - Time-of-Day Patterns
    
    private func analyzeTimeOfDayPatterns(windows: [ResponseWindow]) -> [Insight] {
        var hourData: [Int: [TimeInterval]] = [:]
        for window in windows {
            let hour = window.hourOfDay
            hourData[hour, default: []].append(window.latencySeconds)
        }
        
        // Find peak hour (fastest responses) with sufficient data
        var peakHour = 0
        var peakMedian: TimeInterval = .infinity
        
        for hour in 0..<24 {
            guard let latencies = hourData[hour], latencies.count >= 3 else { continue }
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            if median < peakMedian {
                peakMedian = median
                peakHour = hour
            }
        }
        
        guard peakMedian < .infinity else { return [] }
        
        let hourStr = formatHour(peakHour)
        let avgMedian = windows.map(\.latencySeconds).sorted()[windows.count / 2]
        let ratio = avgMedian / max(peakMedian, 1)
        
        if ratio > 1.8 {
            return [Insight(
                type: .pattern,
                icon: "clock.badge.checkmark.fill",
                color: "blue",
                title: "Peak Response Hour: \(hourStr)",
                description: "Messages around \(hourStr) get your fastest replies — median \(formatDuration(peakMedian)) vs overall \(formatDuration(avgMedian)).",
                actionable: "Consider scheduling important communications during this window.",
                confidence: 0.8,
                dataPoints: hourData[peakHour]?.count ?? 0
            )]
        }
        
        return []
    }
    
    // MARK: - Working Hours Analysis
    
    private func analyzeWorkingHoursPattern(windows: [ResponseWindow]) -> [Insight] {
        let workWindows = windows.filter(\.isWorkingHours)
        let offWindows = windows.filter { !$0.isWorkingHours }
        
        guard workWindows.count >= 3, offWindows.count >= 3 else { return [] }
        
        let workLatencies = workWindows.map(\.latencySeconds).sorted()
        let offLatencies = offWindows.map(\.latencySeconds).sorted()
        
        let workMedian = workLatencies[workLatencies.count / 2]
        let offMedian = offLatencies[offLatencies.count / 2]
        
        let ratio = offMedian / max(workMedian, 1)
        
        if ratio > 2.0 {
            return [Insight(
                type: .pattern,
                icon: "moon.fill",
                color: "purple",
                title: "Off-Hours Significantly Slower",
                description: "You respond \(String(format: "%.1f", ratio))x slower outside working hours (\(formatDuration(offMedian)) vs \(formatDuration(workMedian))).",
                actionable: "This is healthy work-life balance. Keep maintaining boundaries!",
                confidence: 0.8,
                dataPoints: workWindows.count + offWindows.count
            )]
        } else if ratio < 0.7 {
            return [Insight(
                type: .pattern,
                icon: "moon.stars.fill",
                color: "orange",
                title: "Faster Responses Off-Hours",
                description: "You actually respond faster outside working hours — \(formatDuration(offMedian)) vs \(formatDuration(workMedian)) during work.",
                actionable: "Consider setting boundaries to protect off-hours time.",
                confidence: 0.75,
                dataPoints: workWindows.count + offWindows.count
            )]
        }
        
        return []
    }
    
    // MARK: - Speed Tier Analysis
    
    private func analyzeSpeedTier(windows: [ResponseWindow]) -> [Insight] {
        let latencies = windows.map(\.latencySeconds).sorted()
        let median = latencies[latencies.count / 2]
        
        let under30min = windows.filter { $0.latencySeconds < 1800 }.count
        let under1hr = windows.filter { $0.latencySeconds < 3600 }.count
        let under4hr = windows.filter { $0.latencySeconds < 14400 }.count
        
        let pct30 = Double(under30min) / Double(windows.count) * 100
        let pct1hr = Double(under1hr) / Double(windows.count) * 100
        let pct4hr = Double(under4hr) / Double(windows.count) * 100
        
        if pct30 > 70 {
            return [Insight(
                type: .achievement,
                icon: "bolt.fill",
                color: "yellow",
                title: "Lightning Fast Responder",
                description: "\(Int(pct30))% of your responses are under 30 minutes. You're in the top tier!",
                actionable: nil,
                confidence: 0.9,
                dataPoints: windows.count
            )]
        } else if pct30 > 50 {
            return [Insight(
                type: .achievement,
                icon: "hare.fill",
                color: "green",
                title: "Fast Responder",
                description: "\(Int(pct30))% of your responses are under 30 minutes. Great responsiveness!",
                actionable: nil,
                confidence: 0.85,
                dataPoints: windows.count
            )]
        } else if pct1hr < 30 {
            return [Insight(
                type: .recommendation,
                icon: "tortoise.fill",
                color: "orange",
                title: "Room for Improvement",
                description: "Only \(Int(pct1hr))% of responses under 1 hour. Median is \(formatDuration(median)).",
                actionable: "Set a goal to respond within 2 hours for new messages.",
                confidence: 0.8,
                dataPoints: windows.count
            )]
        }
        
        return []
    }
    
    // MARK: - Consistency Analysis
    
    private func analyzeConsistency(windows: [ResponseWindow]) -> [Insight] {
        let latencies = windows.map(\.latencySeconds).sorted()
        guard latencies.count >= 10 else { return [] }
        
        let median = latencies[latencies.count / 2]
        let q1 = latencies[latencies.count / 4]
        let q3 = latencies[3 * latencies.count / 4]
        let iqr = q3 - q1
        
        // Coefficient of variation
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(latencies.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / max(mean, 1)
        
        if cv < 0.5 {
            return [Insight(
                type: .achievement,
                icon: "metronome.fill",
                color: "teal",
                title: "Highly Consistent Responder",
                description: "Your response times are tightly clustered. Most fall between \(formatDuration(q1)) and \(formatDuration(q3)).",
                actionable: nil,
                confidence: 0.85,
                dataPoints: latencies.count
            )]
        } else if cv > 1.5 {
            return [Insight(
                type: .pattern,
                icon: "waveform.path",
                color: "orange",
                title: "Variable Response Times",
                description: "Your responses range widely — from \(formatDuration(q1)) to \(formatDuration(q3)). High variability detected.",
                actionable: "Identify what causes delays: specific contacts, times, or message types.",
                confidence: 0.8,
                dataPoints: latencies.count
            )]
        }
        
        return []
    }
    
    // MARK: - Anomaly Detection
    
    /// Detect unusually fast or slow periods using IQR method
    private func detectAnomalies(windows: [ResponseWindow]) -> [Insight] {
        let dailyData = computeDailyData(windows: windows)
        guard dailyData.count >= 7 else { return [] }
        
        let medians = dailyData.map(\.median).sorted()
        let q1 = medians[medians.count / 4]
        let q3 = medians[3 * medians.count / 4]
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr
        
        // Find most recent anomaly
        for day in dailyData.reversed() {
            if day.median < lowerBound {
                return [Insight(
                    type: .anomaly,
                    icon: "bolt.badge.automatic.fill",
                    color: "green",
                    title: "Exceptional Performance Detected",
                    description: "On \(formatDate(day.date)), you responded unusually fast (median \(formatDuration(day.median))).",
                    actionable: "What did you do differently? Replicate that pattern!",
                    confidence: 0.75,
                    dataPoints: day.count
                )]
            } else if day.median > upperBound {
                return [Insight(
                    type: .anomaly,
                    icon: "exclamationmark.triangle.fill",
                    color: "red",
                    title: "Unusual Delay Detected",
                    description: "On \(formatDate(day.date)), response times were unusually slow (median \(formatDuration(day.median))).",
                    actionable: "Review what caused the delay to prevent future occurrences.",
                    confidence: 0.7,
                    dataPoints: day.count
                )]
            }
        }
        
        return []
    }
    
    // MARK: - Contact Pattern Analysis
    
    private func analyzeContactPatterns(windows: [ResponseWindow]) -> [Insight] {
        var contactData: [String: [TimeInterval]] = [:]
        for window in windows {
            guard let email = window.inboundEvent?.participantEmail else { continue }
            contactData[email, default: []].append(window.latencySeconds)
        }
        
        // Find VIP (fastest responses) and slowest
        var vip: String?
        var vipMedian: TimeInterval = .infinity
        var slowest: String?
        var slowestMedian: TimeInterval = 0
        
        for (email, latencies) in contactData where latencies.count >= 3 {
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            if median < vipMedian { vipMedian = median; vip = email }
            if median > slowestMedian { slowestMedian = median; slowest = email }
        }
        
        if let vip = vip, vipMedian < 1800 {
            let name = formatContactName(vip)
            return [Insight(
                type: .pattern,
                icon: "star.fill",
                color: "yellow",
                title: "VIP Contact: \(name)",
                description: "You respond fastest to \(name) — median \(formatDuration(vipMedian)).",
                actionable: nil,
                confidence: 0.75,
                dataPoints: contactData[vip]?.count ?? 0
            )]
        }
        
        return []
    }
    
    // MARK: - Predictive Insights
    
    private func generatePredictions(windows: [ResponseWindow], timeRange: TimeRange) -> [Insight] {
        let dailyData = computeDailyData(windows: windows)
        guard dailyData.count >= 7 else { return [] }
        
        // Simple linear projection
        let recentWeek = Array(dailyData.suffix(7))
        let n = Double(recentWeek.count)
        let x = Array(0..<recentWeek.count).map { Double($0) }
        let y = recentWeek.map { $0.median }
        
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        
        // Project 7 days forward
        let projected = slope * 14 + (sumY - slope * sumX) / n
        let current = y.last ?? 0
        
        let change = ((projected - current) / max(current, 1)) * 100
        
        if slope < -100 && change < -20 {
            return [Insight(
                type: .trend,
                icon: "arrow.down.forward.circle.fill",
                color: "green",
                title: "On Track to Improve",
                description: "Based on recent trends, your response time could decrease by \(Int(abs(change)))% next week.",
                actionable: "Maintain your current habits to hit this projection!",
                confidence: 0.6,
                dataPoints: recentWeek.count
            )]
        } else if slope > 100 && change > 20 {
            return [Insight(
                type: .warning,
                icon: "arrow.up.forward.circle.fill",
                color: "orange",
                title: "Trend Warning",
                description: "If current trend continues, response time may increase by \(Int(change))% next week.",
                actionable: "Consider setting stricter goals or reviewing habits.",
                confidence: 0.55,
                dataPoints: recentWeek.count
            )]
        }
        
        return []
    }
    
    // MARK: - Helpers
    
    private struct DailyData {
        let date: Date
        let median: TimeInterval
        let count: Int
    }
    
    private func computeDailyData(windows: [ResponseWindow]) -> [DailyData] {
        let calendar = Calendar.current
        var dailyGroups: [Date: [TimeInterval]] = [:]
        
        for window in windows {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            let day = calendar.startOfDay(for: timestamp)
            dailyGroups[day, default: []].append(window.latencySeconds)
        }
        
        return dailyGroups.map { date, latencies in
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            return DailyData(date: date, median: median, count: latencies.count)
        }.sorted { $0.date < $1.date }
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatContactName(_ email: String) -> String {
        if email.contains("@") {
            return email.components(separatedBy: "@").first ?? email
        }
        return email
    }
}
