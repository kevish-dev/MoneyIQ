import Foundation
import Testing
@testable import MoneyIQCore

@MainActor
struct WidgetSnapshotTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_764_900_000) // Dec 5, 2025

    @Test func summarizesCurrentMonthAndToday() {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        let food = ExpenseCategory(name: "Food", systemIconName: "fork.knife")
        let travel = ExpenseCategory(name: "Travel", systemIconName: "car")
        let transactions = [
            ExpenseTransaction(amount: 75, date: today.addingTimeInterval(3600), category: food),
            ExpenseTransaction(amount: 25, date: yesterday, category: food),
            ExpenseTransaction(amount: 40, date: today, category: travel),
            ExpenseTransaction(amount: 500, date: previousMonth, category: travel)
        ]
        let budget = Budget(monthlyCapAmount: 1_000, currencyCode: "INR")

        let snapshot = WidgetSnapshotBuilder.make(
            currencyCode: "INR", budget: budget, transactions: transactions,
            now: now, calendar: calendar
        )

        #expect(snapshot.monthSpent == 140)
        #expect(snapshot.todaySpent == 115)
        #expect(snapshot.remaining == 860)
        #expect(abs(snapshot.fractionUsed - 0.14) < 0.0001)
        #expect(abs(snapshot.percentUsed - 14) < 0.0001)
        #expect(snapshot.topCategoryName == "Food")
        #expect(snapshot.topCategoryAmount == 100)
    }

    @Test func noBudgetStillShowsSpending() {
        let snapshot = WidgetSnapshotBuilder.make(
            currencyCode: "INR", budget: nil,
            transactions: [ExpenseTransaction(amount: 42, date: now)],
            now: now, calendar: calendar
        )

        #expect(snapshot.monthSpent == 42)
        #expect(snapshot.monthlyCap == nil)
        #expect(snapshot.remaining == nil)
        #expect(snapshot.dailyAllowance(at: now, calendar: calendar) == nil)
    }

    @Test func overBudgetKeepsActualPercentage() {
        let snapshot = WidgetSnapshotBuilder.make(
            currencyCode: "INR", budget: Budget(monthlyCapAmount: 100, currencyCode: "INR"),
            transactions: [ExpenseTransaction(amount: 145, date: now)],
            now: now, calendar: calendar
        )

        #expect(snapshot.remaining == -45)
        #expect(snapshot.percentUsed == 145)
        #expect(snapshot.fractionUsed == 1)
    }

    @Test func newDayDoesNotReuseYesterdaysSpend() {
        let snapshot = WidgetSnapshotBuilder.make(
            currencyCode: "INR", budget: nil,
            transactions: [ExpenseTransaction(amount: 42, date: now)],
            now: now, calendar: calendar
        )
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        #expect(snapshot.spendingToday(at: tomorrow, calendar: calendar) == 0)
        #expect(snapshot.isCurrentMonth(at: tomorrow, calendar: calendar))
    }

    @Test func oldMonthIsMarkedStale() {
        let snapshot = WidgetSnapshotBuilder.make(
            currencyCode: "INR", budget: nil, transactions: [],
            now: now, calendar: calendar
        )
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now)!
        #expect(!snapshot.isCurrentMonth(at: nextMonth, calendar: calendar))
    }
}
