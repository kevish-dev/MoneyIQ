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
    /// `body` lets the caller pass real, computed spending data (see
    /// `InsightsEngine`) instead of generic boilerplate — since a local
    /// notification's content is fixed at schedule time, callers should
    /// reschedule this periodically (e.g. whenever the app foregrounds) to
    /// keep it fresh.
    public func scheduleWeeklySummary(weekday: Int, time: DateComponents, body: String? = nil) {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])

        let content = UNMutableNotificationContent()
        content.title = "Your weekly summary is ready"
        content.body = body ?? "See how last week's spending stacked up against your budget."
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

    // MARK: - Custom payment reminders (Phase 7)

    private func reminderIdentifier(_ reminder: ReminderItem) -> String {
        "com.moneyiq.notifications.reminder.\(reminder.id.uuidString)"
    }

    /// Schedules (or, if disabled, cancels) a custom reminder. `time` is
    /// read for whichever components its frequency actually uses — day+time
    /// for `.once`/`.monthly`, weekday+time for `.weekly`, just time for
    /// `.daily` — everything else in the stored `Date` is ignored.
    public func scheduleReminder(_ reminder: ReminderItem, currencyCode: String, calendar: Calendar = .current) {
        let id = reminderIdentifier(reminder)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard reminder.isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let amount = reminder.amount {
            content.body = "Payment of \(amount.formatted(.currency(code: currencyCode))) due"
        } else {
            content.body = "Payment reminder"
        }
        content.sound = .default

        let trigger: UNCalendarNotificationTrigger
        switch reminder.frequency {
        case .once:
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.time)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        case .daily:
            let comps = calendar.dateComponents([.hour, .minute], from: reminder.time)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        case .weekly:
            let comps = calendar.dateComponents([.weekday, .hour, .minute], from: reminder.time)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        case .monthly:
            let comps = calendar.dateComponents([.day, .hour, .minute], from: reminder.time)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        }

        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancelReminder(_ reminder: ReminderItem) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(reminder)])
    }
}
