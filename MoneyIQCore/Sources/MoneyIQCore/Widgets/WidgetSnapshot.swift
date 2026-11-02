import Foundation

/// Only aggregate figures cross into the widget extension. Transactions,
/// merchant names, and account details stay in the app's SwiftData store.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var refreshedAt: Date
    public let monthStart: Date
    public let dayStart: Date
    public let currencyCode: String
    public let monthSpent: Decimal
    public let todaySpent: Decimal
    public let monthlyCap: Decimal?
    public let topCategoryName: String?
    public let topCategoryAmount: Decimal

    public init(
        refreshedAt: Date,
        monthStart: Date,
        dayStart: Date,
        currencyCode: String,
        monthSpent: Decimal,
        todaySpent: Decimal,
        monthlyCap: Decimal?,
        topCategoryName: String?,
        topCategoryAmount: Decimal
    ) {
        self.refreshedAt = refreshedAt
        self.monthStart = monthStart
        self.dayStart = dayStart
        self.currencyCode = currencyCode
        self.monthSpent = monthSpent
        self.todaySpent = todaySpent
        self.monthlyCap = monthlyCap
        self.topCategoryName = topCategoryName
        self.topCategoryAmount = topCategoryAmount
    }

    public var remaining: Decimal? { monthlyCap.map { $0 - monthSpent } }

    public var percentUsed: Double {
        guard let monthlyCap, monthlyCap > 0 else { return 0 }
        return max(NSDecimalNumber(decimal: monthSpent / monthlyCap).doubleValue * 100, 0)
    }

    public var fractionUsed: Double { min(percentUsed / 100, 1) }

    public func isCurrentMonth(at date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(monthStart, equalTo: date, toGranularity: .month)
    }

    public func spendingToday(at date: Date, calendar: Calendar = .current) -> Decimal {
        calendar.isDate(dayStart, inSameDayAs: date) ? todaySpent : 0
    }

    public func dailyAllowance(at date: Date, calendar: Calendar = .current) -> Decimal? {
        remaining.map { BudgetEngine.dailyPace(remaining: $0, asOf: date, calendar: calendar).recommendedDailySpend }
    }
}

public enum WidgetSnapshotBuilder {
    public static func make(
        currencyCode: String,
        budget: Budget?,
        transactions: [ExpenseTransaction],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let monthStart = calendar.startOfMonth(for: now)
        let dayStart = calendar.startOfDay(for: now)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let monthTransactions = transactions.filter { $0.date >= monthStart && $0.date < nextMonth }
        let monthSpent = monthTransactions.reduce(Decimal(0)) { $0 + $1.amount }
        let todaySpent = monthTransactions
            .filter { $0.date >= dayStart && $0.date < nextDay }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let categoryTotals = Dictionary(grouping: monthTransactions.compactMap { transaction -> (String, Decimal)? in
            guard let category = transaction.category else { return nil }
            return (category.name, transaction.amount)
        }, by: { $0.0 }).mapValues { items in items.reduce(Decimal(0)) { $0 + $1.1 } }
        let topCategory = categoryTotals.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.first
        let effectiveCap = budget.map {
            BudgetEngine.monthProgress(for: $0, transactions: transactions, date: now, calendar: calendar).effectiveCap
        }

        return WidgetSnapshot(
            refreshedAt: now,
            monthStart: monthStart,
            dayStart: dayStart,
            currencyCode: currencyCode,
            monthSpent: monthSpent,
            todaySpent: todaySpent,
            monthlyCap: effectiveCap,
            topCategoryName: topCategory?.key,
            topCategoryAmount: topCategory?.value ?? 0
        )
    }
}
