#if os(macOS)
import Foundation
import SwiftUI
import Combine

// MARK: - Menu Bar Manager

@Observable
@MainActor
final class MenuBarManager {
    static let shared = MenuBarManager()
    
    // Current stats
    var currentStats: MenuBarStats = .empty
    var isLoading: Bool = false
    var lastError: String?
    var lastUpdate: Date?
    
    // Update timer
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 60 // Update every minute
    
    // Connectors
    private let imessageService = iMessageConnector()
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start() {
        // Initial fetch
        Task {
            await refreshStats()
        }
        
        // Schedule periodic updates
        scheduleUpdates()
    }
    
    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func scheduleUpdates() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStats()
            }
        }
    }
    
    // MARK: - Data Fetching
    
    func refreshStats() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        do {
            // Get iMessage stats
            let iMessageStats = try await imessageService.getQuickStats(days: 7)
            
            // Build combined stats
            var platforms: [PlatformStat] = []
            
            if let median = iMessageStats.medianLatency {
                platforms.append(PlatformStat(
                    platform: .imessage,
                    medianLatency: median,
                    responseCount: iMessageStats.responseCount,
                    pendingCount: iMessageStats.pendingResponses
                ))
            }
            
            let overallMedian: TimeInterval?
            if !platforms.isEmpty {
                // Weighted average by response count
                let totalResponses = platforms.reduce(0) { $0 + $1.responseCount }
                if totalResponses > 0 {
                    overallMedian = platforms.reduce(0.0) { $0 + $1.medianLatency * Double($1.responseCount) } / Double(totalResponses)
                } else {
                    overallMedian = platforms.map(\.medianLatency).reduce(0, +) / Double(platforms.count)
                }
            } else {
                overallMedian = nil
            }
            
            let totalPending = platforms.reduce(0) { $0 + $1.pendingCount }
            let totalResponses = platforms.reduce(0) { $0 + $1.responseCount }
            
            // Compute trend vs previous week
            var trend: Double? = nil
            if let currentMedian = overallMedian {
                let prevStats = try? await imessageService.getQuickStats(days: 14)
                if let prevMedian = prevStats?.medianLatency, prevMedian > 0 {
                    trend = ((currentMedian - prevMedian) / prevMedian) * 100
                }
            }
            
            currentStats = MenuBarStats(
                overallMedianLatency: overallMedian,
                totalResponses: totalResponses,
                totalPending: totalPending,
                platforms: platforms,
                trendPercentage: trend
            )
            lastUpdate = Date()
            
            // Update dock badge with pending count
            if totalPending > 0 {
                NSApp.dockTile.badgeLabel = "\(totalPending)"
            } else {
                NSApp.dockTile.badgeLabel = nil
            }
            
        } catch {
            if let iMsgError = error as? iMessageError {
                switch iMsgError {
                case .databaseNotFound:
                    lastError = "iMessage database not found"
                case .permissionDenied:
                    lastError = "Grant Full Disk Access in System Settings → Privacy & Security"
                default:
                    lastError = iMsgError.localizedDescription
                }
            } else {
                lastError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Formatting
    
    var formattedTitle: String {
        guard let latency = currentStats.overallMedianLatency else {
            return "⏱"
        }
        return formatLatencyForMenuBar(latency)
    }
}

// MARK: - Menu Bar Stats

struct MenuBarStats: Sendable {
    let overallMedianLatency: TimeInterval?
    let totalResponses: Int
    let totalPending: Int
    let platforms: [PlatformStat]
    var trendPercentage: Double?
    
    static let empty = MenuBarStats(
        overallMedianLatency: nil,
        totalResponses: 0,
        totalPending: 0,
        platforms: [],
        trendPercentage: nil
    )
    
    var formattedOverall: String {
        guard let latency = overallMedianLatency else { return "--" }
        return formatLatencyForMenuBar(latency)
    }
    
    var statusColor: Color {
        guard let latency = overallMedianLatency else { return .secondary }
        // Green < 30 min, yellow < 2 hours, red > 2 hours
        if latency < 1800 {
            return .green
        } else if latency < 7200 {
            return .yellow
        } else {
            return .red
        }
    }
}

struct PlatformStat: Identifiable, Sendable {
    let id = UUID()
    let platform: Platform
    let medianLatency: TimeInterval
    let responseCount: Int
    let pendingCount: Int
    
    var formattedLatency: String {
        formatLatencyForMenuBar(medianLatency)
    }
}

// MARK: - Formatting Helper

private func formatLatencyForMenuBar(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds))s"
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m\(secs)s"
    } else if seconds < 86400 {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        if minutes == 0 {
            return "\(hours)h"
        }
        if secs == 0 || hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(hours)h\(minutes)m\(secs)s"
    } else {
        let days = Int(seconds / 86400)
        let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        if hours == 0 {
            return "\(days)d"
        }
        return "\(days)d\(hours)h"
    }
}
#endif
