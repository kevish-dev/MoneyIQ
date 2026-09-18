import Foundation
import UserNotifications
import Observation

public enum NotificationPermissionState: Sendable {
    case notDetermined
    case denied
    case authorized
}

private enum NotificationID {
    static let dailyReminder = "com.moneyiq.notifications.dailyReminder"
    static let weeklySummary = "com.moneyiq.notifications.weeklySummary"
}

/// Schedules the two Phase 1/2 local notifications called out in the PRD —
/// a daily logging reminder and a weekly spending summary. Both are
/// entirely local (`UNUserNotificationCenter`), no APNs/push entitlement
/// needed.
@MainActor
@Observable
public final class NotificationScheduler {
    public private(set) var permissionState: NotificationPermissionState = .notDetermined

    private let center = UNUserNotificationCenter.current()

    public init() {
        Task { await refreshPermissionState() }
    }

    public func refreshPermissionState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permissionState = .authorized
        case .denied:
            permissionState = .denied
        case .notDetermined:
            permissionState = .notDetermined
        @unknown default:
            permissionState = .notDetermined
        }
    }

    /// Requests permission if needed. Returns whether notifications ended up
    /// authorized, so the caller can revert a toggle if the user declines.
    public func requestPermissionIfNeeded() async -> Bool {
        if permissionState == .authorized { return true }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermissionState()
            return granted
        } catch {
            await refreshPermissionState()
            return false
        }
    }

    public func scheduleDailyReminder(at time: DateComponents) {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyReminder])

        let content = UNMutableNotificationContent()
        content.title = "Log today's spending"
        content.body = "Add any transactions from today so your budget stays accurate."
        content.sound = .default

        var trigger = DateComponents()
        trigger.hour = time.hour
        trigger.minute = time.minute

        let request = UNNotificationRequest(
            identifier: NotificationID.dailyReminder,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )
        center.add(request)
    }

    public func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyReminder])
    }

    /// `weekday` is 1 = Sunday ... 7 = Saturday, matching `Calendar.Component.weekday`.
    public func scheduleWeeklySummary(weekday: Int, time: DateComponents) {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])

        let content = UNMutableNotificationContent()
        content.title = "Your weekly summary is ready"
        content.body = "See how last week's spending stacked up against your budget."
        content.sound = .default

        var trigger = DateComponents()
        trigger.weekday = weekday
        trigger.hour = time.hour
        trigger.minute = time.minute

        let request = UNNotificationRequest(
            identifier: NotificationID.weeklySummary,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )
        center.add(request)
    }

    public func cancelWeeklySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])
    }
}
