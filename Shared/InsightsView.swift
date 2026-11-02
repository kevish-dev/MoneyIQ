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
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]

    /// The month currently being viewed — defaults to the current month,
    /// but every section below re-derives from this instead of `.now`, so
    /// navigating to a past month re-slices the whole screen for it.
    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: .now)

    private var calendar: Calendar { .current }

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    private var isCurrentMonth: Bool {
        calendar.startOfMonth(for: selectedMonth) == calendar.startOfMonth(for: .now)
    }

    private var canGoToNextMonth: Bool { !isCurrentMonth }

    private var monthlyTotals: [InsightsEngine.MonthlyTotal] {
        InsightsEngine.monthlyTotals(transactions: transactions)
    }

    private var yearlyTotals: [InsightsEngine.YearlyTotal] {
        InsightsEngine.yearlyTotals(transactions: transactions)
    }

    private var yearChange: InsightsEngine.YearOverYearChange {
        InsightsEngine.yearOverYearChange(transactions: transactions, forYearContaining: selectedMonth)
    }

    private var categoryShares: [InsightsEngine.CategoryShare] {
        InsightsEngine.categoryShares(transactions: transactions, forMonthContaining: selectedMonth)
    }

    private var monthTotalSpend: Decimal {
        categoryShares.reduce(Decimal(0)) { $0 + $1.total }
    }

    private var monthChange: InsightsEngine.MonthOverMonthChange {
        InsightsEngine.monthOverMonthChange(transactions: transactions, forMonthContaining: selectedMonth)
    }

    private var topMerchants: [InsightsEngine.MerchantTotal] {
        InsightsEngine.topMerchants(transactions: transactions, forMonthContaining: selectedMonth)
    }

    /// Anomalies use ALL transactions for the per-category average (better
    /// statistics from more history), but only the ones that actually fall
    /// in the viewed month are shown.
    private var anomalies: [InsightsEngine.Anomaly] {
        let monthStart = calendar.startOfMonth(for: selectedMonth)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return InsightsEngine.anomalies(in: transactions)
            .filter { $0.transaction.date >= monthStart && $0.transaction.date < monthEnd }
    }

    /// "Next expected" only makes sense looking forward, so this only shows
    /// while viewing the current month.
    private var subscriptions: [InsightsEngine.SubscriptionCandidate] {
        guard isCurrentMonth else { return [] }
        return InsightsEngine.recurringSubscriptions(in: transactions)
    }

    private var forecast: InsightsEngine.CashFlowForecast {
        InsightsEngine.cashFlowForecast(
            transactions: transactions,
            monthlyIncome: authManager.currentAccount?.monthlyIncome ?? 0
        )
    }

    private var insightFacts: [String] {
        var facts = [
            "Period: \(selectedMonth.formatted(.dateTime.month(.wide).year()))",
            "Currency: \(currencyCode)",
            "Total spent in period: \(monthTotalSpend.formatted(.currency(code: currencyCode)))",
            "Previous month total: \(monthChange.previousTotal.formatted(.currency(code: currencyCode)))",
            "Transactions in period: \(transactions.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }.count)"
        ]
        if let change = monthChange.percentChange {
            facts.append("Change from previous month: \(change.formatted(.percent.precision(.fractionLength(1))))")
        }
        facts += categoryShares.prefix(6).map { "Category \($0.categoryName): \($0.total.formatted(.currency(code: currencyCode))), \($0.fraction.formatted(.percent.precision(.fractionLength(0)))) of spend" }
        facts += topMerchants.prefix(4).map { "Merchant \($0.merchantName): \($0.total.formatted(.currency(code: currencyCode))) in \($0.occurrences) transactions" }
        facts += anomalies.prefix(3).map { "Unusual transaction \($0.transaction.merchantName ?? "Unknown merchant"): \($0.transaction.amount.formatted(.currency(code: currencyCode)))" }
        if isCurrentMonth {
            facts.append("Monthly income: \(forecast.monthlyIncome.formatted(.currency(code: currencyCode)))")
            facts.append("Upcoming recurring bills estimate: \(forecast.upcomingBillsTotal.formatted(.currency(code: currencyCode)))")
            if forecast.monthlyIncome > 0 {
                facts.append("Projected end-of-month balance: \(forecast.projectedEndOfMonthBalance.formatted(.currency(code: currencyCode)))")
            }
            if let budget = budgets.first {
                let progress = BudgetEngine.monthProgress(for: budget, transactions: transactions)
                facts.append("Monthly budget: \(budget.monthlyCapAmount.formatted(.currency(code: currencyCode))); remaining: \(progress.remaining.formatted(.currency(code: currencyCode)))")
            }
        }
        return facts
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    monthNavigator
                    if transactions.isEmpty {
                        emptyState
                    } else {
                        editorialHeader
                        spendTrendCard
                        LocalIntelligenceCard(
                            title: "Ask your spending",
                            subtitle: "A private explanation of the numbers on this page",
                            facts: insightFacts,
                            suggestions: ["What changed this month?", "Where can I look more closely?", "Summarize my spending"]
                        )
                        if isCurrentMonth {
                            cashFlowCard
                        } else {
                            monthSummaryCard
                        }
                        categoryBubbleSection
                        if !topMerchants.isEmpty { topMerchantsSection }
                        if !anomalies.isEmpty { anomalySection }
                        if !subscriptions.isEmpty { subscriptionSection }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.large)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
        }
    }

    // MARK: - Month navigation

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR MONEY, IN FOCUS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(AppTheme.accent)
            Text("See the story behind the spend.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("Explore a month, spot patterns, then ask a better question.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
            Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }

            Spacer()

            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)

            Spacer()

            Button {
                guard canGoToNextMonth else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
            Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundStyle(canGoToNextMonth ? AppTheme.accent : Color.secondary.opacity(0.3))
            }
            .disabled(!canGoToNextMonth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func forecastStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.subheadline.weight(.semibold))
        }
    }

    /// Shown instead of `cashFlowCard` for a past month, where a forward
    /// "projected balance" doesn't make sense — a simple recap instead.
    private var monthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Month Summary")
                .font(.headline)
            HStack {
                forecastStat("Total spent", monthChange.currentTotal)
                Spacer()
                if let percent = monthChange.percentChange {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("vs. previous month").font(.caption).foregroundStyle(.secondary)
                        Label(
                            percent.formatted(.percent.precision(.fractionLength(1))),
                            systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(percent >= 0 ? .red : .green)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Dark red-to-orange hero card: current-period total over a smooth
    /// trend line, toggleable between a trailing 6-month and 5-year view,
    /// with a scrubbable tooltip bubble — matches the design reference's
    /// balance-card pattern.
    private var spendTrendCard: some View {
        SpendTrendCard(
            monthlyTotals: monthlyTotals,
            yearlyTotals: yearlyTotals,
            currencyCode: currencyCode,
            selectedMonth: selectedMonth,
            selectedMonthTotal: monthTotalSpend,
            selectedMonthPercentChange: monthChange.percentChange,
            selectedYearTotal: yearChange.currentTotal,
            selectedYearPercentChange: yearChange.percentChange,
            onSelectMonth: { date in
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = calendar.startOfMonth(for: date)
                }
            }
        )
    }

    /// The category bubble chart, plus a compact "top categories" stat row
    /// beneath it — the design reference's expense-breakdown screen
    /// (image 3), reskinned in the app's orange palette.
    private var categoryBubbleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Category")
                .font(.headline)
            if categoryShares.isEmpty {
                Text("No spending that month.")
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
                                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var topMerchantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Merchants")
                .font(.headline)
            ForEach(topMerchants) { merchant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(merchant.merchantName).font(.subheadline.weight(.medium))
                        Text("\(merchant.occurrences) transaction\(merchant.occurrences == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(merchant.total, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
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
                .glassEffect(.regular.tint(.red.opacity(0.10)), in: .rect(cornerRadius: 12))
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
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
    }
}

private let multiplierFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 1
    return formatter
}()
