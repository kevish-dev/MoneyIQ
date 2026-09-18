import Foundation

/// Pure budget-cap math (Phase 5's rollover). Kept separate from
/// `InsightsEngine` since it reasons about a single `Budget`, not aggregate
/// spending analysis.
public enum BudgetEngine {
    public struct MonthProgress: Sendable {
        public let effectiveCap: Decimal
        public let spent: Decimal
        public let rolloverFromLastMonth: Decimal

        public var remaining: Decimal { effectiveCap - spent }
        public var fractionUsed: Double {
            guard effectiveCap > 0 else { return 0 }
            return min(max(NSDecimalNumber(decimal: spent / effectiveCap).doubleValue, 0), 1)
        }
    }

    public static func totalSpent(
        transactions: [ExpenseTransaction],
        inMonthContaining date: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        let monthStart = calendar.startOfMonth(for: date)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }
        return transactions
            .filter { $0.date >= monthStart && $0.date < monthEnd }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// The cap that actually applies to `date`'s month: the base cap, plus
    /// last month's unused amount if rollover is on and last month came in
    /// under budget. Overspending never carries forward as a debt — only
    /// unused amounts roll over, matching how most budgeting apps do it.
    /// Only looks one month back (not a compounding chain), so a long
    /// history of underspending doesn't silently inflate the cap forever.
    public static func monthProgress(
        for budget: Budget,
        transactions: [ExpenseTransaction],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> MonthProgress {
        let monthStart = calendar.startOfMonth(for: date)
        let spent = totalSpent(transactions: transactions, inMonthContaining: monthStart, calendar: calendar)

        guard budget.rolloverEnabled,
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart),
              lastMonthStart >= calendar.startOfMonth(for: budget.effectiveFrom) else {
            return MonthProgress(effectiveCap: budget.monthlyCapAmount, spent: spent, rolloverFromLastMonth: 0)
        }

        let lastMonthSpent = totalSpent(transactions: transactions, inMonthContaining: lastMonthStart, calendar: calendar)
        let rollover = max(0, budget.monthlyCapAmount - lastMonthSpent)

        return MonthProgress(
            effectiveCap: budget.monthlyCapAmount + rollover,
            spent: spent,
            rolloverFromLastMonth: rollover
        )
    }
}
