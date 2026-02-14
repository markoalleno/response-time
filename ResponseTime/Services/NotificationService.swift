import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

// MARK: - Notification Service

@MainActor
final class NotificationService: Sendable {
    static let shared = NotificationService()
    
    // Notification identifiers
    private enum NotificationID {
        static let thresholdExceeded = "response_time_threshold"
        static let dailySummary = "response_time_daily_summary"
        static let reminder = "response_time_reminder"
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        
        do {
            let granted = try await center.requestAuthorization(options: options)
            return granted
        } catch {
            throw NotificationError.authorizationFailed(error)
        }
    }
    
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Quiet Hours Check
    
    func isInQuietHours() -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        // Default quiet hours: 10 PM to 7 AM
        return hour >= 22 || hour < 7
    }
    
    // MARK: - Threshold Notifications
    
    /// Sends a notification when response time exceeds threshold
    func notifyThresholdExceeded(
        participant: String,
        currentLatency: TimeInterval,
        threshold: TimeInterval
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Response Time Alert"
        content.body = "Your response to \(participant) has exceeded \(formatDuration(threshold)). Current wait: \(formatDuration(currentLatency))"
        content.sound = .default
        content.categoryIdentifier = NotificationID.thresholdExceeded
        
        // Use a unique identifier based on participant
        let identifier = "\(NotificationID.thresholdExceeded)_\(participant.hashValue)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Daily Summary
    
    /// Schedules a daily summary notification
    func scheduleDailySummary(at hour: Int = 21, minute: Int = 0) async throws {
        let content = UNMutableNotificationContent()
        content.title = "📊 Daily Response Time Summary"
        content.body = "Tap to view your response time statistics for today."
        content.sound = .default
        content.categoryIdentifier = NotificationID.dailySummary
        
        // Schedule for the specified time each day
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: NotificationID.dailySummary,
            content: content,
            trigger: trigger
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    /// Sends immediate daily summary with stats
    func sendDailySummary(
        medianLatency: TimeInterval,
        responseCount: Int,
        pendingCount: Int,
        improvement: Double? = nil
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "📊 Daily Response Time Summary"
        
        var body = "Today: \(formatDuration(medianLatency)) median, \(responseCount) responses"
        if pendingCount > 0 {
            body += "\n⚠️ \(pendingCount) pending response\(pendingCount == 1 ? "" : "s")"
        }
        if let trend = improvement {
            if trend < 0 {
                body += "\n📈 \(Int(abs(trend)))% faster than yesterday!"
            } else if trend > 0 {
                body += "\n📉 \(Int(trend))% slower than yesterday"
            }
        }
        
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationID.dailySummary
        
        let request = UNNotificationRequest(
            identifier: "\(NotificationID.dailySummary)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Pending Response Reminder
    
    /// Reminds about pending responses
    func sendPendingReminder(count: Int, oldestWait: TimeInterval?) async throws {
        guard count > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "💬 Pending Responses"
        
        var body = "You have \(count) conversation\(count == 1 ? "" : "s") awaiting a response."
        if let oldest = oldestWait {
            body += "\nOldest: \(formatDuration(oldest)) waiting"
        }
        
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationID.reminder
        
        let request = UNNotificationRequest(
            identifier: NotificationID.reminder,
            content: content,
            trigger: nil
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Weekly Summary Notification
    
    func sendWeeklySummary(
        medianLatency: TimeInterval,
        responseCount: Int,
        grade: String,
        streakDays: Int,
        improvement: Double? = nil
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "📅 Weekly Response Time Summary"
        
        var body = "Grade: \(grade) · \(responseCount) responses · Median: \(formatDuration(medianLatency))"
        if streakDays > 0 {
            body += "\n🔥 \(streakDays) day streak"
        }
        if let trend = improvement {
            if trend < 0 {
                body += "\n📈 \(Int(abs(trend)))% faster than last week!"
            } else if trend > 0 {
                body += "\n📉 \(Int(trend))% slower than last week"
            }
        }
        
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "weekly_summary_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Streak Notifications
    
    func notifyStreakRecord(goalName: String, streakDays: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "🔥 New Streak Record!"
        content.body = "\(goalName): \(streakDays) day streak — your new personal best!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "streak_record_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Management
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func cancelDailySummary() {
        cancelNotification(identifier: NotificationID.dailySummary)
    }
    
    // MARK: - Notification Actions
    
    func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: [.destructive]
        )
        
        let thresholdCategory = UNNotificationCategory(
            identifier: NotificationID.thresholdExceeded,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let summaryCategory = UNNotificationCategory(
            identifier: NotificationID.dailySummary,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let reminderCategory = UNNotificationCategory(
            identifier: NotificationID.reminder,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            thresholdCategory,
            summaryCategory,
            reminderCategory
        ])
    }
}

// MARK: - Errors

enum NotificationError: LocalizedError {
    case authorizationFailed(Error)
    case schedulingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let error):
            return "Notification authorization failed: \(error.localizedDescription)"
        case .schedulingFailed(let error):
            return "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}

// MARK: - Settings

struct NotificationSettings: Codable, Sendable {
    var isEnabled: Bool = true
    var thresholdNotificationsEnabled: Bool = true
    var thresholdMinutes: Int = 60 // Default: 1 hour
    var dailySummaryEnabled: Bool = true
    var dailySummaryHour: Int = 21 // 9 PM
    var dailySummaryMinute: Int = 0
    var pendingReminderEnabled: Bool = true
    var pendingReminderIntervalHours: Int = 4
    
    var thresholdSeconds: TimeInterval {
        TimeInterval(thresholdMinutes * 60)
    }
}
