import Foundation

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
        public var spent: Decimal
        public var cap: Decimal
        public var currencyCode: String

        public init(spent: Decimal, cap: Decimal, currencyCode: String) {
            self.spent = spent
            self.cap = cap
            self.currencyCode = currencyCode
        }

        public var remaining: Decimal { cap - spent }
        public var fractionUsed: Double {
            guard cap > 0 else { return 0 }
            return min(max(NSDecimalNumber(decimal: spent / cap).doubleValue, 0), 1)
        }
    }

    public init() {}
}
#endif
