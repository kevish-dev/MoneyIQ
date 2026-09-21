import Foundation
import Observation

/// Lightweight user-preference store backed by UserDefaults — no SwiftData
/// needed for simple toggles/times that aren't shared data.
@MainActor
@Observable
public final class AppSettingsStore {
    private enum Key {
        static let appLockEnabled = "com.moneyiq.settings.appLockEnabled"
        static let dailyReminderEnabled = "com.moneyiq.settings.dailyReminderEnabled"
        static let dailyReminderMinutesSinceMidnight = "com.moneyiq.settings.dailyReminderMinutes"
        static let weeklySummaryEnabled = "com.moneyiq.settings.weeklySummaryEnabled"
        static let weeklySummaryWeekday = "com.moneyiq.settings.weeklySummaryWeekday"
        static let weeklySummaryMinutesSinceMidnight = "com.moneyiq.settings.weeklySummaryMinutes"
        static let budgetLockScreenEnabled = "com.moneyiq.settings.budgetLockScreenEnabled"
        static let budgetDynamicIslandEnabled = "com.moneyiq.settings.budgetDynamicIslandEnabled"
    }

    private let defaults: UserDefaults

    public var isAppLockEnabled: Bool {
        didSet { defaults.set(isAppLockEnabled, forKey: Key.appLockEnabled) }
    }

    public var isDailyReminderEnabled: Bool {
        didSet { defaults.set(isDailyReminderEnabled, forKey: Key.dailyReminderEnabled) }
    }

    /// Time-of-day only (date component is irrelevant); stored as minutes
    /// since midnight so it survives across days without drifting.
    public var dailyReminderTime: DateComponents {
        didSet {
            let minutes = (dailyReminderTime.hour ?? 20) * 60 + (dailyReminderTime.minute ?? 0)
            defaults.set(minutes, forKey: Key.dailyReminderMinutesSinceMidnight)
        }
    }

    public var isWeeklySummaryEnabled: Bool {
        didSet { defaults.set(isWeeklySummaryEnabled, forKey: Key.weeklySummaryEnabled) }
    }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.Component.weekday`.
    public var weeklySummaryWeekday: Int {
        didSet { defaults.set(weeklySummaryWeekday, forKey: Key.weeklySummaryWeekday) }
    }

    public var weeklySummaryTime: DateComponents {
        didSet {
            let minutes = (weeklySummaryTime.hour ?? 9) * 60 + (weeklySummaryTime.minute ?? 0)
            defaults.set(minutes, forKey: Key.weeklySummaryMinutesSinceMidnight)
        }
    }

    /// Off by default — showing budget status on the Lock Screen is opt-in,
    /// not automatic just because a budget exists. Independent from the
    /// Dynamic Island toggle below: one Live Activity backs both surfaces,
    /// but each can be shown/hidden on its own (see
    /// `BudgetActivityAttributes.ContentState`'s `showOnLockScreen`/
    /// `showOnDynamicIsland`, which the widget extension reads to decide
    /// what to render on each surface).
    public var isBudgetLockScreenEnabled: Bool {
        didSet { defaults.set(isBudgetLockScreenEnabled, forKey: Key.budgetLockScreenEnabled) }
    }

    /// Off by default — see `isBudgetLockScreenEnabled`.
    public var isBudgetDynamicIslandEnabled: Bool {
        didSet { defaults.set(isBudgetDynamicIslandEnabled, forKey: Key.budgetDynamicIslandEnabled) }
    }

    /// Whether the Live Activity should be running at all — true if either
    /// surface wants it. The activity itself is one instance shared by both
    /// surfaces; per-surface content visibility is a separate concern.
    public var isBudgetLiveActivityEnabled: Bool {
        isBudgetLockScreenEnabled || isBudgetDynamicIslandEnabled
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isAppLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
        self.isDailyReminderEnabled = defaults.bool(forKey: Key.dailyReminderEnabled)
        self.isWeeklySummaryEnabled = defaults.bool(forKey: Key.weeklySummaryEnabled)
        self.isBudgetLockScreenEnabled = defaults.bool(forKey: Key.budgetLockScreenEnabled)
        self.isBudgetDynamicIslandEnabled = defaults.bool(forKey: Key.budgetDynamicIslandEnabled)

        let dailyMinutes = defaults.object(forKey: Key.dailyReminderMinutesSinceMidnight) as? Int ?? (20 * 60)
        self.dailyReminderTime = DateComponents(hour: dailyMinutes / 60, minute: dailyMinutes % 60)

        self.weeklySummaryWeekday = defaults.object(forKey: Key.weeklySummaryWeekday) as? Int ?? 2 // Monday

        let weeklyMinutes = defaults.object(forKey: Key.weeklySummaryMinutesSinceMidnight) as? Int ?? (9 * 60)
        self.weeklySummaryTime = DateComponents(hour: weeklyMinutes / 60, minute: weeklyMinutes % 60)
    }
}
