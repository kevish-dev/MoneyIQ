import SwiftUI
import SwiftData
import Charts
import MoneyIQCore

struct InsightsView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

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

    private var categoryShares: [InsightsEngine.CategoryShare] {
        InsightsEngine.categoryShares(transactions: transactions)
    }

    private var dailySpend: [InsightsEngine.DailySpend] {
        InsightsEngine.dailySpendThisMonth(transactions: transactions)
    }

    private var monthTotalSpend: Decimal {
        categoryBreakdown.reduce(Decimal(0)) { $0 + $1.total }
    }

    /// Percent change vs. the prior month, for the hero card's pill —
    /// derived from the existing `monthlyTotals` bucketing rather than a
    /// new engine function, since the two already-adjacent months it needs
    /// are already in that array.
    private var monthOverMonthChange: Double? {
        guard monthlyTotals.count >= 2 else { return nil }
        let current = monthlyTotals[monthlyTotals.count - 1].total
        let previous = monthlyTotals[monthlyTotals.count - 2].total
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    if transactions.isEmpty {
                        emptyState
                    } else {
                        spendChartHeroCard
                        cashFlowCard
                        categoryBubbleSection
                        if !anomalies.isEmpty { anomalySection }
                        if !subscriptions.isEmpty { subscriptionSection }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.large)
            }
            .navigationTitle("Insights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
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
        .padding(AppTheme.Spacing.large)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func forecastStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.subheadline.weight(.semibold))
        }
    }

    /// Dark orange/red hero card with the current month's total spend and
    /// the interactive scrub/hover line chart — matches the design
    /// reference's balance-card-plus-chart pattern (image 4).
    private var spendChartHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spent This Month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if let change = monthOverMonthChange {
                    Label(
                        change.formatted(.percent.precision(.fractionLength(1))),
                        systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.pillBackgroundOnHero, in: Capsule())
                    .foregroundStyle(.white)
                }
            }

            Text(monthTotalSpend, format: .currency(code: currencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if dailySpend.isEmpty {
                Text("No spending yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(height: 140)
            } else {
                InteractiveSpendChart(data: dailySpend, currencyCode: currencyCode)
                    .frame(height: 160)
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.3), radius: 16, y: 10)
    }

    /// The category bubble chart, plus a compact "top categories" stat row
    /// beneath it — the design reference's expense-breakdown screen
    /// (image 3), reskinned in the app's orange palette.
    private var categoryBubbleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This Month by Category")
                .font(.headline)
            if categoryShares.isEmpty {
                Text("No spending yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                CategoryBubbleChart(shares: categoryShares)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Expenses").font(.headline)
                        Spacer()
                    }
                    Text(monthTotalSpend, format: .currency(code: currencyCode))
                        .font(.title2.bold())

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(categoryShares.prefix(4)) { share in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(share.categoryName)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: share.systemIconName)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    Text(share.total, format: .currency(code: currencyCode))
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(12)
                                .frame(width: 140, alignment: .leading)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unusual Spending", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
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
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
