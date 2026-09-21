import Testing
import Foundation
@testable import MoneyIQCore

@MainActor
struct BudgetEngineTests {
    private let calendar = Calendar.current

    private func monthStart(monthsAgo: Int, from now: Date) -> Date {
        calendar.startOfMonth(for: calendar.date(byAdding: .month, value: -monthsAgo, to: now)!)
    }

    @Test func withoutRolloverCapStaysFixed() {
        let now = Date()
        let budget = Budget(monthlyCapAmount: 1000, currencyCode: "USD", rolloverEnabled: false, effectiveFrom: monthStart(monthsAgo: 3, from: now))
        let progress = BudgetEngine.monthProgress(for: budget, transactions: [], date: now)
        #expect(progress.effectiveCap == 1000)
        #expect(progress.rolloverFromLastMonth == 0)
    }

    @Test func rolloverAddsLastMonthsUnspentAmount() {
        let now = Date()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let budget = Budget(monthlyCapAmount: 1000, currencyCode: "USD", rolloverEnabled: true, effectiveFrom: monthStart(monthsAgo: 3, from: now))
        let lastMonthSpend = ExpenseTransaction(amount: 600, date: lastMonth)

        let progress = BudgetEngine.monthProgress(for: budget, transactions: [lastMonthSpend], date: now)
        #expect(progress.rolloverFromLastMonth == 400)
        #expect(progress.effectiveCap == 1400)
    }

    @Test func overspendingDoesNotCarryForwardAsDebt() {
        let now = Date()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let budget = Budget(monthlyCapAmount: 1000, currencyCode: "USD", rolloverEnabled: true, effectiveFrom: monthStart(monthsAgo: 3, from: now))
        let lastMonthSpend = ExpenseTransaction(amount: 1500, date: lastMonth)

        let progress = BudgetEngine.monthProgress(for: budget, transactions: [lastMonthSpend], date: now)
        #expect(progress.rolloverFromLastMonth == 0)
        #expect(progress.effectiveCap == 1000)
    }

    @Test func rolloverIgnoredBeforeBudgetWasEffective() {
        let now = Date()
        // Budget only started existing this month — no "last month" to roll over from.
        let budget = Budget(monthlyCapAmount: 1000, currencyCode: "USD", rolloverEnabled: true, effectiveFrom: now)
        let progress = BudgetEngine.monthProgress(for: budget, transactions: [], date: now)
        #expect(progress.rolloverFromLastMonth == 0)
        #expect(progress.effectiveCap == 1000)
    }

    @Test func totalSpentOnlyCountsTransactionsInThatMonth() {
        let now = Date()
        let thisMonth = ExpenseTransaction(amount: 100, date: now)
        let lastMonth = ExpenseTransaction(amount: 999, date: calendar.date(byAdding: .month, value: -1, to: now)!)
        let spent = BudgetEngine.totalSpent(transactions: [thisMonth, lastMonth], inMonthContaining: now)
        #expect(spent == 100)
    }

    @Test func dailyPaceDividesRemainingByDaysLeftIncludingToday() {
        let date = calendar.date(from: DateComponents(year: 2024, month: 6, day: 25))! // 6 days left: 25-30
        let pace = BudgetEngine.dailyPace(remaining: 600, asOf: date, calendar: calendar)
        #expect(pace.daysRemaining == 6)
        #expect(pace.recommendedDailySpend == 100)
    }

    @Test func dailyPaceClampsNegativeRemainingToZero() {
        let date = calendar.date(from: DateComponents(year: 2024, month: 6, day: 25))!
        let pace = BudgetEngine.dailyPace(remaining: -50, asOf: date, calendar: calendar)
        #expect(pace.recommendedDailySpend == 0)
    }
}

@MainActor
struct SavingsGoalTests {
    @Test func progressFractionIsClampedToTarget() {
        let goal = SavingsGoal(name: "Trip", targetAmount: 1000, targetDate: .now, savedAmount: 1200)
        #expect(goal.progressFraction == 1.0)
        #expect(goal.isComplete == true)
        #expect(goal.remainingAmount == 0)
    }

    @Test func progressFractionReflectsPartialSavings() {
        let goal = SavingsGoal(name: "Trip", targetAmount: 1000, targetDate: .now, savedAmount: 250)
        #expect(goal.progressFraction == 0.25)
        #expect(goal.remainingAmount == 750)
    }

    @Test func suggestedMonthlyContributionDividesRemainingByMonthsLeft() {
        let calendar = Calendar.current
        let now = Date()
        let sixMonthsOut = calendar.date(byAdding: .month, value: 6, to: now)!
        let goal = SavingsGoal(name: "Trip", targetAmount: 6000, targetDate: sixMonthsOut, savedAmount: 0)
        #expect(goal.suggestedMonthlyContribution(calendar: calendar, now: now) == 1000)
    }
}
