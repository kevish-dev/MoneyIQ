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

    private var categoryShares: [InsightsEngine.CategoryShare] {
        InsightsEngine.categoryShares(transactions: transactions, forMonthContaining: selectedMonth)
    }

    private var dailySpend: [InsightsEngine.DailySpend] {
        InsightsEngine.dailySpend(transactions: transactions, forMonthContaining: selectedMonth)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    monthNavigator
                    if transactions.isEmpty {
                        emptyState
                    } else {
                        spendChartHeroCard
                        if isCurrentMonth {
                            cashFlowCard
                        } else {
                            monthSummaryCard
                        }
                        trendSection
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
        }
    }

    // MARK: - Month navigation

    private var monthNavigator: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
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
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canGoToNextMonth ? AppTheme.accent : Color.secondary.opacity(0.3))
            }
            .disabled(!canGoToNextMonth)
        }
        .padding(.top, AppTheme.Spacing.xs)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Dark orange/red hero card with the selected month's total spend and
    /// the interactive scrub/hover line chart — matches the design
    /// reference's balance-card-plus-chart pattern (image 4).
    private var spendChartHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isCurrentMonth ? "Spent This Month" : "Spent That Month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if let percent = monthChange.percentChange {
                    Label(
                        percent.formatted(.percent.precision(.fractionLength(1))),
                        systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right"
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
                Text("No spending that month.")
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

    /// A trailing-6-month bar chart — tap any bar to jump `selectedMonth`
    /// there, so the month-by-month trend and the detailed per-month
    /// sections above stay connected instead of being two separate views.
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("6-Month Trend")
                .font(.headline)
            Chart(monthlyTotals) { bucket in
                BarMark(
                    x: .value("Month", bucket.monthStart, unit: .month),
                    y: .value("Spend", NSDecimalNumber(decimal: bucket.total).doubleValue)
                )
                .foregroundStyle(
                    calendar.isDate(bucket.monthStart, equalTo: selectedMonth, toGranularity: .month)
                        ? AppTheme.accent
                        : AppTheme.accent.opacity(0.35)
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let origin = geometry[proxy.plotAreaFrame].origin
                            guard let date: Date = proxy.value(atX: location.x - origin.x) else { return }
                            guard let closest = monthlyTotals.min(by: {
                                abs($0.monthStart.timeIntervalSince(date)) < abs($1.monthStart.timeIntervalSince(date))
                            }) else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMonth = calendar.startOfMonth(for: closest.monthStart)
                            }
                        }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
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
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
