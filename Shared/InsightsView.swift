import SwiftUI
import SwiftData
import Charts
import MoneyIQCore

struct InsightsView: View {
    let authManager: AuthManager

    @Query(sort: \ExpenseTransaction.date) private var transactions: [ExpenseTransaction]

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    private var monthlyTotals: [InsightsEngine.MonthlyTotal] {
        InsightsEngine.monthlyTotals(transactions: transactions)
    }

    private var categoryBreakdown: [InsightsEngine.CategoryTotal] {
        InsightsEngine.categoryBreakdown(transactions: transactions)
    }

    private var anomalies: [InsightsEngine.Anomaly] {
        InsightsEngine.anomalies(in: transactions)
    }

    private var subscriptions: [InsightsEngine.SubscriptionCandidate] {
        InsightsEngine.recurringSubscriptions(in: transactions)
    }

    private var forecast: InsightsEngine.CashFlowForecast {
        InsightsEngine.cashFlowForecast(
            transactions: transactions,
            monthlyIncome: authManager.currentAccount?.monthlyIncome ?? 0
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if transactions.isEmpty {
                        emptyState
                    } else {
                        cashFlowCard
                        trendSection
                        categorySection
                        if !anomalies.isEmpty { anomalySection }
                        if !subscriptions.isEmpty { subscriptionSection }
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No insights yet")
                .font(.headline)
            Text("Add a few transactions and trends, anomalies, and forecasts will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var cashFlowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cash Flow Forecast")
                .font(.headline)

            if authManager.currentAccount?.monthlyIncome == nil || authManager.currentAccount?.monthlyIncome == 0 {
                Text("Add your monthly income in Settings for a projected balance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Projected end-of-month balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(forecast.projectedEndOfMonthBalance, format: .currency(code: currencyCode))
                            .font(.title2.bold())
                            .foregroundStyle(forecast.projectedEndOfMonthBalance < 0 ? .red : .primary)
                    }
                    Spacer()
                }
                Divider()
                HStack {
                    forecastStat("Spent so far", forecast.spentSoFarThisMonth)
                    Spacer()
                    forecastStat("Upcoming bills", forecast.upcomingBillsTotal)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func forecastStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.subheadline.weight(.semibold))
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spending Trend")
                .font(.headline)
            Chart(monthlyTotals) { entry in
                BarMark(
                    x: .value("Month", entry.monthStart, unit: .month),
                    y: .value("Total", NSDecimalNumber(decimal: entry.total).doubleValue)
                )
                .foregroundStyle(.tint)
                .cornerRadius(6)
            }
            .frame(height: 180)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Month by Category")
                .font(.headline)
            if categoryBreakdown.isEmpty {
                Text("No spending yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(categoryBreakdown) { entry in
                    SectorMark(
                        angle: .value("Total", NSDecimalNumber(decimal: entry.total).doubleValue),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(by: .value("Category", entry.categoryName))
                    .cornerRadius(4)
                }
                .frame(height: 220)
            }
        }
    }

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unusual Spending", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(anomalies.prefix(5), id: \.transaction.id) { anomaly in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomaly.transaction.merchantName ?? anomaly.transaction.category?.name ?? "Transaction")
                            .font(.subheadline.weight(.medium))
                        Text("\(anomaly.multiplier as NSDecimalNumber, formatter: multiplierFormatter)x your usual \(anomaly.transaction.category?.name ?? "category") spend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(anomaly.transaction.amount, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recurring Subscriptions", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            ForEach(subscriptions) { sub in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.merchantName).font(.subheadline.weight(.medium))
                        Text("Next expected \(sub.expectedNextDate, format: .dateTime.month().day())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(sub.averageAmount, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private let multiplierFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 1
    return formatter
}()
