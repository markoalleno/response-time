import SwiftUI
import SwiftData

// MARK: - Response Analyzer

@Observable
@MainActor
class ResponseAnalyzer {
    static let shared = ResponseAnalyzer()
    
    private var modelContext: ModelContext?
    
    // Settings
    var matchingWindowDays: Int = 7
    var confidenceThreshold: Float = 0.7
    var workingHoursStart: Int = 9
    var workingHoursEnd: Int = 17
    var excludeWeekends: Bool = true
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Compute Response Windows
    
    /// Analyzes a conversation to find response pairs
    func computeResponseWindows(for conversation: Conversation) -> [ResponseWindow] {
        let events = conversation.messageEvents.sorted { $0.timestamp < $1.timestamp }
        var windows: [ResponseWindow] = []
        
        // Find inbound events
        let inboundEvents = events.filter { $0.direction == .inbound && !$0.isExcluded }
        
        for inbound in inboundEvents {
            // Look for next outbound within matching window
            let windowEnd = Calendar.current.date(
                byAdding: .day,
                value: matchingWindowDays,
                to: inbound.timestamp
            )!
            
            let nextOutbound = events.first { event in
                event.direction == .outbound &&
                event.timestamp > inbound.timestamp &&
                event.timestamp <= windowEnd &&
                !event.isExcluded
            }
            
            if let outbound = nextOutbound {
                let latency = outbound.timestamp.timeIntervalSince(inbound.timestamp)
                let confidence = computeConfidence(inbound: inbound, outbound: outbound)
                let method = determineMatchingMethod(inbound: inbound, outbound: outbound)
                
                let window = ResponseWindow(
                    inboundEvent: inbound,
                    outboundEvent: outbound,
                    latencySeconds: latency,
                    confidence: confidence,
                    matchingMethod: method
                )
                
                windows.append(window)
            }
        }
        
        return windows
    }
    
    private func computeConfidence(inbound: MessageEvent, outbound: MessageEvent) -> Float {
        // Use shared confidence calculation
        let latency = outbound.timestamp.timeIntervalSince(inbound.timestamp)
        return computeResponseConfidence(latencySeconds: latency)
    }
    
    private func determineMatchingMethod(inbound: MessageEvent, outbound: MessageEvent) -> ThreadingMethod {
        // In a real implementation, we'd check:
        // - Message-ID / In-Reply-To headers
        // - Thread ID (for Gmail)
        // - References header
        // - Subject matching
        
        // Default to time window matching
        return .timeWindow
    }
    
    // MARK: - Aggregate Metrics
    
    func computeMetrics(
        for windows: [ResponseWindow],
        platform: Platform? = nil,
        timeRange: TimeRange
    ) -> ResponseMetrics {
        // Filter windows
        var filtered = windows.filter { $0.isValidForAnalytics }
        
        if let platform = platform {
            filtered = filtered.filter { window in
                window.inboundEvent?.conversation?.sourceAccount?.platform == platform
            }
        }
        
        // Filter by time range
        let startDate = timeRange.startDate
        filtered = filtered.filter { ($0.inboundEvent?.timestamp ?? Date.distantPast) >= startDate }
        
        guard !filtered.isEmpty else {
            return emptyMetrics(platform: platform, timeRange: timeRange)
        }
        
        // Sort latencies for percentile calculations
        let latencies = filtered.map(\.latencySeconds).sorted()
        
        let count = latencies.count
        let median = latencies[count / 2]
        let mean = latencies.reduce(0, +) / Double(count)
        let p90 = latencies[Int(Double(count) * 0.9)]
        let p95 = latencies[Int(Double(count) * 0.95)]
        
        // Compute working hours breakdown
        let (workingMedian, nonWorkingMedian) = computeWorkingHoursBreakdown(windows: filtered)
        
        // Compute trend
        let previousPeriodMedian = computePreviousPeriodMedian(
            windows: windows,
            platform: platform,
            currentRange: timeRange
        )
        
        var trendPercentage: Double?
        if let previous = previousPeriodMedian, previous > 0 {
            trendPercentage = ((median - previous) / previous) * 100
        }
        
        return ResponseMetrics(
            platform: platform,
            timeRange: timeRange,
            sampleCount: count,
            medianLatency: median,
            meanLatency: mean,
            p90Latency: p90,
            p95Latency: p95,
            minLatency: latencies.first ?? 0,
            maxLatency: latencies.last ?? 0,
            workingHoursMedian: workingMedian,
            nonWorkingHoursMedian: nonWorkingMedian,
            previousPeriodMedian: previousPeriodMedian,
            trendPercentage: trendPercentage
        )
    }
    
    private func emptyMetrics(platform: Platform?, timeRange: TimeRange) -> ResponseMetrics {
        ResponseMetrics(
            platform: platform,
            timeRange: timeRange,
            sampleCount: 0,
            medianLatency: 0,
            meanLatency: 0,
            p90Latency: 0,
            p95Latency: 0,
            minLatency: 0,
            maxLatency: 0,
            workingHoursMedian: nil,
            nonWorkingHoursMedian: nil,
            previousPeriodMedian: nil,
            trendPercentage: nil
        )
    }
    
    private func computeWorkingHoursBreakdown(windows: [ResponseWindow]) -> (working: TimeInterval?, nonWorking: TimeInterval?) {
        let calendar = Calendar.current
        
        var workingLatencies: [TimeInterval] = []
        var nonWorkingLatencies: [TimeInterval] = []
        
        for window in windows {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            
            let hour = calendar.component(.hour, from: timestamp)
            let weekday = calendar.component(.weekday, from: timestamp)
            let isWeekend = weekday == 1 || weekday == 7
            
            let isWorkingHours = hour >= workingHoursStart &&
                                 hour < workingHoursEnd &&
                                 (!excludeWeekends || !isWeekend)
            
            if isWorkingHours {
                workingLatencies.append(window.latencySeconds)
            } else {
                nonWorkingLatencies.append(window.latencySeconds)
            }
        }
        
        let workingMedian = workingLatencies.isEmpty ? nil : workingLatencies.sorted()[workingLatencies.count / 2]
        let nonWorkingMedian = nonWorkingLatencies.isEmpty ? nil : nonWorkingLatencies.sorted()[nonWorkingLatencies.count / 2]
        
        return (workingMedian, nonWorkingMedian)
    }
    
    private func computePreviousPeriodMedian(
        windows: [ResponseWindow],
        platform: Platform?,
        currentRange: TimeRange
    ) -> TimeInterval? {
        let calendar = Calendar.current
        let now = Date()
        
        // Determine previous period based on current range
        let (previousStart, previousEnd): (Date, Date) = {
            switch currentRange {
            case .today:
                let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
                return (yesterday, calendar.startOfDay(for: now))
            case .week:
                let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!
                let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                return (twoWeeksAgo, oneWeekAgo)
            case .month:
                let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
                let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
                return (twoMonthsAgo, oneMonthAgo)
            case .quarter:
                let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
                let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
                return (sixMonthsAgo, threeMonthsAgo)
            case .year:
                let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: now)!
                let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
                return (twoYearsAgo, oneYearAgo)
            }
        }()
        
        var filtered = windows.filter { window in
            guard let timestamp = window.inboundEvent?.timestamp else { return false }
            return timestamp >= previousStart && timestamp < previousEnd && window.isValidForAnalytics
        }
        
        if let platform = platform {
            filtered = filtered.filter { $0.inboundEvent?.conversation?.sourceAccount?.platform == platform }
        }
        
        guard !filtered.isEmpty else { return nil }
        
        let latencies = filtered.map(\.latencySeconds).sorted()
        return latencies[latencies.count / 2]
    }
    
    // MARK: - Daily/Hourly Breakdown
    
    func computeDailyMetrics(
        windows: [ResponseWindow],
        platform: Platform? = nil,
        timeRange: TimeRange
    ) -> [DailyMetrics] {
        let calendar = Calendar.current
        var filtered = windows.filter { $0.isValidForAnalytics }
        
        if let platform = platform {
            filtered = filtered.filter { $0.inboundEvent?.conversation?.sourceAccount?.platform == platform }
        }
        
        let startDate = timeRange.startDate
        filtered = filtered.filter { ($0.inboundEvent?.timestamp ?? Date.distantPast) >= startDate }
        
        // Group by day
        var dailyGroups: [Date: [ResponseWindow]] = [:]
        for window in filtered {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            let day = calendar.startOfDay(for: timestamp)
            dailyGroups[day, default: []].append(window)
        }
        
        return dailyGroups.map { date, dayWindows in
            let latencies = dayWindows.map(\.latencySeconds).sorted()
            let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
            
            return DailyMetrics(
                date: date,
                medianLatency: median,
                messageCount: dayWindows.count * 2, // Rough estimate
                responseCount: dayWindows.count
            )
        }.sorted { $0.date < $1.date }
    }
    
    func computeHourlyMetrics(windows: [ResponseWindow]) -> [HourlyMetrics] {
        let calendar = Calendar.current
        
        var hourlyGroups: [Int: [ResponseWindow]] = [:]
        for window in windows.filter(\.isValidForAnalytics) {
            guard let timestamp = window.inboundEvent?.timestamp else { continue }
            let hour = calendar.component(.hour, from: timestamp)
            hourlyGroups[hour, default: []].append(window)
        }
        
        return (0..<24).map { hour in
            let hourWindows = hourlyGroups[hour] ?? []
            let latencies = hourWindows.map(\.latencySeconds).sorted()
            let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
            
            return HourlyMetrics(
                id: hour,
                hour: hour,
                medianLatency: median,
                responseCount: hourWindows.count
            )
        }
    }
}

// MARK: - Sync Manager

@Observable
@MainActor
class SyncManager {
    static let shared = SyncManager()
    
    var isSyncing = false
    var lastSyncDate: Date?
    var syncProgress: Double = 0
    var currentPlatform: Platform?
    var error: SyncError?
    
    enum SyncError: LocalizedError {
        case noAccounts
        case authExpired(Platform)
        case networkError
        case rateLimited(retryAfter: TimeInterval)
        
        var errorDescription: String? {
            switch self {
            case .noAccounts: return "No accounts connected"
            case .authExpired(let p): return "\(p.displayName) authentication expired"
            case .networkError: return "Network connection error"
            case .rateLimited(let t): return "Rate limited. Retry in \(Int(t))s"
            }
        }
    }
    
    func syncAll(accounts: [SourceAccount], modelContext: ModelContext) async throws {
        guard !accounts.isEmpty else {
            throw SyncError.noAccounts
        }
        
        isSyncing = true
        syncProgress = 0
        defer {
            isSyncing = false
            currentPlatform = nil
        }
        
        let step = 1.0 / Double(accounts.count)
        
        for (index, account) in accounts.enumerated() {
            guard account.isEnabled else { continue }
            
            currentPlatform = account.platform
            
            do {
                try await syncAccount(account, modelContext: modelContext)
            } catch {
                account.lastSyncError = error.localizedDescription
                // Continue with other accounts
            }
            
            syncProgress = Double(index + 1) * step
        }
        
        // Update goal streaks
        updateGoalStreaks(modelContext: modelContext)
        
        lastSyncDate = Date()
    }
    
    private func updateGoalStreaks(modelContext: ModelContext) {
        let goalFetch = FetchDescriptor<ResponseGoal>()
        guard let goals = try? modelContext.fetch(goalFetch), !goals.isEmpty else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let windowFetch = FetchDescriptor<ResponseWindow>()
        guard let allWindows = try? modelContext.fetch(windowFetch) else { return }
        let valid = allWindows.filter(\.isValidForAnalytics)
        
        for goal in goals where goal.isEnabled {
            // Check if today met the goal
            let todayWindows = valid.filter {
                guard let t = $0.inboundEvent?.timestamp else { return false }
                if let platform = goal.platform {
                    guard $0.inboundEvent?.conversation?.sourceAccount?.platform == platform else { return false }
                }
                return calendar.isDate(t, inSameDayAs: today)
            }
            
            let todayMet: Bool
            if todayWindows.isEmpty {
                todayMet = false // No data = no streak
            } else {
                let latencies = todayWindows.map(\.latencySeconds).sorted()
                let median = latencies[latencies.count / 2]
                todayMet = median <= goal.targetLatencySeconds
            }
            
            if todayMet {
                if let lastDate = goal.lastStreakDate, calendar.isDate(lastDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                    // Consecutive day
                    goal.currentStreak += 1
                } else if let lastDate = goal.lastStreakDate, calendar.isDate(lastDate, inSameDayAs: today) {
                    // Already updated today
                } else {
                    // New streak
                    goal.currentStreak = 1
                }
                goal.lastStreakDate = today
                
                if goal.currentStreak > goal.longestStreak {
                    goal.longestStreak = goal.currentStreak
                    // Notify new record
                    let goalName = goal.platform?.displayName ?? "All Platforms"
                    let streak = goal.currentStreak
                    Task { @MainActor in
                        try? await NotificationService.shared.notifyStreakRecord(
                            goalName: goalName,
                            streakDays: streak
                        )
                    }
                }
            } else if let lastDate = goal.lastStreakDate, !calendar.isDate(lastDate, inSameDayAs: today) && !calendar.isDate(lastDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                // Streak broken
                goal.currentStreak = 0
            }
        }
    }
    
    private func syncAccount(_ account: SourceAccount, modelContext: ModelContext) async throws {
        // Get stored tokens
        guard let tokens = OAuthService.shared.getStoredTokens(for: account.platform) else {
            throw SyncError.authExpired(account.platform)
        }
        
        // Refresh if expired
        var accessToken = tokens.accessToken
        if tokens.isExpired {
            let newTokens = try await OAuthService.shared.refreshTokens(for: account.platform)
            accessToken = newTokens.accessToken
        }
        
        // Fetch messages based on platform
        switch account.platform {
        case .gmail:
            try await syncGmail(account: account, accessToken: accessToken, modelContext: modelContext)
        case .outlook:
            try await syncOutlook(account: account, accessToken: accessToken, modelContext: modelContext)
        case .slack:
            try await syncSlack(account: account, accessToken: accessToken, modelContext: modelContext)
        case .imessage:
            // iMessage syncs differently (local database)
            try await syncIMessage(account: account, modelContext: modelContext)
        }
        
        account.syncCheckpoint = Date()
        account.lastSyncError = nil
    }
    
    private func syncGmail(account: SourceAccount, accessToken: String, modelContext: ModelContext) async throws {
        // Placeholder - would call Gmail API
        try await Task.sleep(for: .seconds(1))
    }
    
    private func syncOutlook(account: SourceAccount, accessToken: String, modelContext: ModelContext) async throws {
        // Placeholder - would call Graph API
        try await Task.sleep(for: .seconds(1))
    }
    
    private func syncSlack(account: SourceAccount, accessToken: String, modelContext: ModelContext) async throws {
        // Placeholder - would call Slack API
        try await Task.sleep(for: .seconds(1))
    }
    
    private func syncIMessage(account: SourceAccount, modelContext: ModelContext) async throws {
        // Placeholder - would read local chat.db
        try await Task.sleep(for: .seconds(1))
    }
}
