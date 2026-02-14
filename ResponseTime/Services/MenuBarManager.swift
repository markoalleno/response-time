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
            
            // TODO: Add Gmail stats when connected
            // let gmailStats = try await gmailConnector.getQuickStats()
            // platforms.append(...)
            
            let overallMedian = platforms.isEmpty ? nil : platforms.map(\.medianLatency).reduce(0, +) / Double(platforms.count)
            let totalPending = platforms.reduce(0) { $0 + $1.pendingCount }
            let totalResponses = platforms.reduce(0) { $0 + $1.responseCount }
            
            currentStats = MenuBarStats(
                overallMedianLatency: overallMedian,
                totalResponses: totalResponses,
                totalPending: totalPending,
                platforms: platforms
            )
            lastUpdate = Date()
            
        } catch {
            lastError = error.localizedDescription
            
            // If it's a database not found error, show a helpful message
            if case iMessageError.databaseNotFound = error {
                lastError = "Grant Full Disk Access to read iMessage data"
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
    
    static let empty = MenuBarStats(
        overallMedianLatency: nil,
        totalResponses: 0,
        totalPending: 0,
        platforms: []
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
