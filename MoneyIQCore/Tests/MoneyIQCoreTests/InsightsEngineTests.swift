import Testing
import Foundation
@testable import MoneyIQCore

@MainActor
struct InsightsEngineTests {
    private func makeTransaction(amount: Decimal, daysAgo: Int, merchant: String? = nil, isBillLike: Bool = false, category: ExpenseCategory? = nil, now: Date) -> ExpenseTransaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return ExpenseTransaction(amount: amount, date: date, merchantName: merchant, isBillLike: isBillLike, category: category)
    }

    @Test func monthlyTotalsBucketsCorrectlyAcrossMonths() {
        let now = Date()
        let calendar = Calendar.current
        let thisMonthTx = makeTransaction(amount: 100, daysAgo: 1, now: now)
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let lastMonthTx = ExpenseTransaction(amount: 50, date: lastMonthDate)

        let totals = InsightsEngine.monthlyTotals(transactions: [thisMonthTx, lastMonthTx], monthCount: 3, now: now)
        #expect(totals.count == 3)
        #expect(totals.last!.total == 100)
        #expect(totals[totals.count - 2].total == 50)
    }

    @Test func categoryBreakdownSumsPerCategoryForCurrentMonth() {
        let now = Date()
        let food = ExpenseCategory(name: "Food")
        let travel = ExpenseCategory(name: "Travel")
        let transactions = [
            makeTransaction(amount: 150, daysAgo: 1, category: food, now: now),
            makeTransaction(amount: 100, daysAgo: 2, category: food, now: now),
            makeTransaction(amount: 300, daysAgo: 3, category: travel, now: now)
        ]
        let breakdown = InsightsEngine.categoryBreakdown(transactions: transactions, forMonthContaining: now)
        #expect(breakdown.first?.categoryName == "Travel")
        #expect(breakdown.first?.total == 300)
        #expect(breakdown.last?.total == 250) // Food total = 150 + 100
    }

    @Test func anomaliesFlagTransactionsFarAboveCategoryAverage() {
        let now = Date()
        let food = ExpenseCategory(name: "Food")
        let normal = [
            makeTransaction(amount: 100, daysAgo: 1, category: food, now: now),
            makeTransaction(amount: 110, daysAgo: 2, category: food, now: now),
            makeTransaction(amount: 90, daysAgo: 3, category: food, now: now)
        ]
        let spike = makeTransaction(amount: 1000, daysAgo: 4, category: food, now: now)

        let anomalies = InsightsEngine.anomalies(in: normal + [spike])
        #expect(anomalies.count == 1)
        #expect(anomalies.first?.transaction.amount == 1000)
    }

    @Test func anomaliesIgnoreCategoriesWithTooFewSamples() {
        let now = Date()
        let food = ExpenseCategory(name: "Food")
        let transactions = [
            makeTransaction(amount: 100, daysAgo: 1, category: food, now: now),
            makeTransaction(amount: 1000, daysAgo: 2, category: food, now: now)
        ]
        #expect(InsightsEngine.anomalies(in: transactions).isEmpty)
    }

    @Test func detectsRecurringMonthlySubscription() {
        let now = Date()
        let transactions = [
            makeTransaction(amount: 199, daysAgo: 60, merchant: "Netflix", now: now),
            makeTransaction(amount: 199, daysAgo: 30, merchant: "Netflix", now: now),
            makeTransaction(amount: 199, daysAgo: 1, merchant: "Netflix", now: now)
        ]
        let subs = InsightsEngine.recurringSubscriptions(in: transactions)
        #expect(subs.count == 1)
        #expect(subs.first?.merchantName == "Netflix")
        #expect(subs.first?.occurrences == 3)
    }

    @Test func doesNotFlagOneOffPurchasesAsSubscriptions() {
        let now = Date()
        let transactions = [
            makeTransaction(amount: 450, daysAgo: 10, merchant: "Swiggy", now: now),
            makeTransaction(amount: 620, daysAgo: 3, merchant: "Swiggy", now: now)
        ]
        #expect(InsightsEngine.recurringSubscriptions(in: transactions).isEmpty)
    }

    @Test func cashFlowForecastSubtractsSpendAndUpcomingBills() {
        let now = Date()
        let calendar = Calendar.current
        let lastMonthBill = ExpenseTransaction(
            amount: 500,
            date: calendar.date(byAdding: .day, value: -35, to: now)!,
            merchantName: "Electricity Board",
            isBillLike: true
        )
        let thisMonthSpend = makeTransaction(amount: 200, daysAgo: 1, now: now)

        let forecast = InsightsEngine.cashFlowForecast(
            transactions: [lastMonthBill, thisMonthSpend],
            monthlyIncome: 5000,
            now: now
        )
        #expect(forecast.spentSoFarThisMonth == 200)
        #expect(forecast.upcomingBillsTotal == 500)
        let expectedBalance: Decimal = 4300
        #expect(forecast.projectedEndOfMonthBalance == expectedBalance)
    }
}
