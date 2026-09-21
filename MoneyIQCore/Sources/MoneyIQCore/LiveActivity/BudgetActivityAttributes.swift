import Foundation

/// What a Live Activity surface (Lock Screen or Dynamic Island) shows —
/// chosen independently per surface in Settings → Live Activity. Declared
/// outside the `#if os(iOS)` guard below (unlike the rest of this file)
/// since `AppSettingsStore`, which persists the choice, compiles on macOS
/// too even though the Activity itself never runs there.
public enum LiveActivityContentKind: String, Codable, CaseIterable, Sendable {
    case budgetProgress
    case savingsGoalProgress
    case dailyPace

    public var displayName: String {
        switch self {
        case .budgetProgress: "Budget Progress"
        case .savingsGoalProgress: "Savings Goal Progress"
        case .dailyPace: "Daily Spend Pace"
        }
    }

    public var systemIconName: String {
        switch self {
        case .budgetProgress: "creditcard.fill"
        case .savingsGoalProgress: "target"
        case .dailyPace: "gauge.with.needle.fill"
        }
    }
}

// Live Activities (ActivityKit) are iOS/iPadOS/watchOS-only — unavailable on
// macOS entirely, independent of any paid-account restriction. MoneyIQ is a
// universal iOS+macOS package, so this whole file compiles out on macOS.
#if os(iOS)
import ActivityKit

/// Shared between the main app (which starts/updates the activity) and the
/// widget extension (which renders it) — this is why it lives in the shared
/// package rather than either target.
public struct BudgetActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        // Budget progress payload — always populated, since it's also the
        // fallback/default content kind.
        public var spent: Decimal
        public var cap: Decimal
        public var currencyCode: String

        /// Independently toggleable per surface (Settings → Live Activity) —
        /// one running Activity backs both, but the widget extension checks
        /// these to decide what, if anything, to render on each.
        public var showOnLockScreen: Bool
        public var showOnDynamicIsland: Bool
        /// Which content type each surface renders when it's shown at all.
        public var lockScreenKind: LiveActivityContentKind
        public var dynamicIslandKind: LiveActivityContentKind

        // Savings goal progress payload — the nearest incomplete goal, if
        // any exists; `goalName == nil` means there's nothing to show.
        public var goalName: String?
        public var goalSaved: Decimal
        public var goalTarget: Decimal

        // Daily spend pace payload.
        public var recommendedDailySpend: Decimal
        public var daysRemainingInMonth: Int

        public init(
            spent: Decimal,
            cap: Decimal,
            currencyCode: String,
            showOnLockScreen: Bool = true,
            showOnDynamicIsland: Bool = true,
            lockScreenKind: LiveActivityContentKind = .budgetProgress,
            dynamicIslandKind: LiveActivityContentKind = .budgetProgress,
            goalName: String? = nil,
            goalSaved: Decimal = 0,
            goalTarget: Decimal = 0,
            recommendedDailySpend: Decimal = 0,
            daysRemainingInMonth: Int = 0
        ) {
            self.spent = spent
            self.cap = cap
            self.currencyCode = currencyCode
            self.showOnLockScreen = showOnLockScreen
            self.showOnDynamicIsland = showOnDynamicIsland
            self.lockScreenKind = lockScreenKind
            self.dynamicIslandKind = dynamicIslandKind
            self.goalName = goalName
            self.goalSaved = goalSaved
            self.goalTarget = goalTarget
            self.recommendedDailySpend = recommendedDailySpend
            self.daysRemainingInMonth = daysRemainingInMonth
        }

        public var remaining: Decimal { cap - spent }
        public var fractionUsed: Double {
            guard cap > 0 else { return 0 }
            return min(max(NSDecimalNumber(decimal: spent / cap).doubleValue, 0), 1)
        }

        public var goalProgressFraction: Double {
            guard goalTarget > 0 else { return 0 }
            return min(max(NSDecimalNumber(decimal: goalSaved / goalTarget).doubleValue, 0), 1)
        }
    }

    public init() {}
}
#endif
