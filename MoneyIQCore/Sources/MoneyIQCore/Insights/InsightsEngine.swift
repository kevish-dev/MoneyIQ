import Foundation

/// Pure, testable spending-analysis logic (Phase 4 of the PRD). Everything
/// here operates on plain arrays of already-fetched transactions rather than
/// a `ModelContext`, so it's cheap to unit test without SwiftData.
public enum InsightsEngine {
    public struct MonthlyTotal: Identifiable, Sendable {
        public let id = UUID()
        public let monthStart: Date
        public let total: Decimal
    }

    public struct CategoryTotal: Identifiable, Sendable {
        public let id = UUID()
        public let categoryName: String
        public let total: Decimal
    }

    /// A category's spend plus its share (0...1) of the period's total —
    /// what drives the bubble chart's per-bubble size/fill.
    public struct CategoryShare: Identifiable, Sendable {
        public let id = UUID()
        public let categoryName: String
        public let systemIconName: String
        public let total: Decimal
        public let fraction: Double
    }

    /// A single day's total spend — the bucket granularity for the
    /// interactive spend-over-time chart.
    public struct DailySpend: Identifiable, Sendable {
        public let id = UUID()
        public let day: Date
        public let total: Decimal
    }

    public struct Anomaly {
        public let transaction: ExpenseTransaction
        public let categoryAverage: Decimal
        public let multiplier: Decimal
    }

    public struct SubscriptionCandidate: Identifiable, Sendable {
        public let id = UUID()
        public let merchantName: String
        public let averageAmount: Decimal
        public let occurrences: Int
        public let lastDate: Date
        public let expectedNextDate: Date
    }

    public struct CashFlowForecast: Sendable {
        public let monthlyIncome: Decimal
        public let spentSoFarThisMonth: Decimal
        public let upcomingBillsTotal: Decimal
        public let projectedEndOfMonthBalance: Decimal
    }

    // MARK: - Spending trends

    /// Total spend per calendar month, oldest first, for the trailing
    /// `monthCount` months (including the current month).
    public static func monthlyTotals(
        transactions: [ExpenseTransaction],
        monthCount: Int = 6,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [MonthlyTotal] {
        guard let earliestStart = calendar.date(byAdding: .month, value: -(monthCount - 1), to: calendar.startOfMonth(for: now)) else {
            return []
        }

        var buckets: [Date: Decimal] = [:]
        var cursor = earliestStart
        for _ in 0..<monthCount {
            buckets[cursor] = 0
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        for transaction in transactions {
            let monthStart = calendar.startOfMonth(for: transaction.date)
            guard monthStart >= earliestStart else { continue }
            buckets[monthStart, default: 0] += transaction.amount
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { MonthlyTotal(monthStart: $0.key, total: $0.value) }
    }

    /// Category breakdown for a single month (defaults to the current one).
    public static func categoryBreakdown(
        transactions: [ExpenseTransaction],
        forMonthContaining date: Date = .now,
        calendar: Calendar = .current
    ) -> [CategoryTotal] {
        let monthStart = calendar.startOfMonth(for: date)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        var totals: [String: Decimal] = [:]
        for transaction in transactions where transaction.date >= monthStart && transaction.date < monthEnd {
            let name = transaction.category?.name ?? "Uncategorized"
            totals[name, default: 0] += transaction.amount
        }

        return totals
            .map { CategoryTotal(categoryName: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    /// Each category's percentage share of total spend for a single month
    /// (defaults to the current one) — the data the category bubble chart
    /// renders, one bubble per category, sized/filled by `fraction`.
    public static func categoryShares(
        transactions: [ExpenseTransaction],
        forMonthContaining date: Date = .now,
        calendar: Calendar = .current
    ) -> [CategoryShare] {
        let monthStart = calendar.startOfMonth(for: date)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        struct Bucket { var total: Decimal = 0; var icon: String = "questionmark.circle" }
        var buckets: [String: Bucket] = [:]
        for transaction in transactions where transaction.date >= monthStart && transaction.date < monthEnd {
            let name = transaction.category?.name ?? "Uncategorized"
            var bucket = buckets[name] ?? Bucket()
            bucket.total += transaction.amount
            if let icon = transaction.category?.systemIconName {
                bucket.icon = icon
            }
            buckets[name] = bucket
        }

        let grandTotal = buckets.values.reduce(Decimal(0)) { $0 + $1.total }
        guard grandTotal > 0 else { return [] }

        return buckets
            .map { name, bucket in
                CategoryShare(
                    categoryName: name,
                    systemIconName: bucket.icon,
                    total: bucket.total,
                    fraction: NSDecimalNumber(decimal: bucket.total / grandTotal).doubleValue
                )
            }
            .sorted { $0.total > $1.total }
    }

    /// Total spend per calendar day from the start of the current month
    /// through today — the bucket granularity for the interactive
    /// spend-over-time chart.
    public static func dailySpendThisMonth(
        transactions: [ExpenseTransaction],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailySpend] {
        let monthStart = calendar.startOfMonth(for: now)
        let today = calendar.startOfDay(for: now)
        guard today >= monthStart else { return [] }

        var buckets: [Date: Decimal] = [:]
        var cursor = monthStart
        while cursor <= today {
            buckets[cursor] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            guard day >= monthStart && day <= today else { continue }
            buckets[day, default: 0] += transaction.amount
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { DailySpend(day: $0.key, total: $0.value) }
    }

    // MARK: - Anomaly detection

    /// Flags transactions notably larger than the average for their own
    /// category — a simple, explainable baseline rather than a black-box
    /// model, per the "explainable insights" spirit of the PRD.
    public static func anomalies(
        in transactions: [ExpenseTransaction],
        thresholdMultiplier: Decimal = 2.0,
        minimumSampleSize: Int = 3
    ) -> [Anomaly] {
        let byCategory = Dictionary(grouping: transactions) { $0.category?.id }

        var results: [Anomaly] = []
        for (_, categoryTransactions) in byCategory {
            guard categoryTransactions.count >= minimumSampleSize else { continue }
            let total = categoryTransactions.reduce(Decimal(0)) { $0 + $1.amount }
            let average = total / Decimal(categoryTransactions.count)
            guard average > 0 else { continue }

            for transaction in categoryTransactions where transaction.amount > average * thresholdMultiplier {
                results.append(Anomaly(
                    transaction: transaction,
                    categoryAverage: average,
                    multiplier: transaction.amount / average
                ))
            }
        }
        return results.sorted { $0.transaction.date > $1.transaction.date }
    }

    // MARK: - Recurring subscription detection

    /// Groups transactions by merchant and flags ones that repeat roughly
    /// monthly at a roughly stable amount — Phase 4's "recurring subscription
    /// detection," built on Phase 3's merchant auto-categorization.
    public static func recurringSubscriptions(
        in transactions: [ExpenseTransaction],
        minimumOccurrences: Int = 2,
        dayIntervalRange: ClosedRange<Int> = 24...36,
        amountToleranceFraction: Decimal = 0.15,
        calendar: Calendar = .current
    ) -> [SubscriptionCandidate] {
        let named = transactions.filter { ($0.merchantName?.isEmpty == false) }
        let byMerchant = Dictionary(grouping: named) { MerchantCategoryMapping.normalize($0.merchantName!) }

        var candidates: [SubscriptionCandidate] = []
        for (_, group) in byMerchant {
            guard group.count >= minimumOccurrences else { continue }
            let sorted = group.sorted { $0.date < $1.date }

            var recurringPairs = 0
            for i in 1..<sorted.count {
                let dayGap = calendar.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
                let amountA = sorted[i - 1].amount
                let amountB = sorted[i].amount
                let amountDiff = abs(amountA - amountB)
                let amountOK = amountA == 0 ? amountB == 0 : (amountDiff / amountA) <= amountToleranceFraction

                if dayIntervalRange.contains(dayGap), amountOK {
                    recurringPairs += 1
                }
            }

            guard recurringPairs >= 1 else { continue }

            let total = sorted.reduce(Decimal(0)) { $0 + $1.amount }
            let average = total / Decimal(sorted.count)
            let last = sorted.last!
            let expectedNext = calendar.date(byAdding: .day, value: 30, to: last.date) ?? last.date

            candidates.append(SubscriptionCandidate(
                merchantName: last.merchantName ?? "Unknown",
                averageAmount: average,
                occurrences: sorted.count,
                lastDate: last.date,
                expectedNextDate: expectedNext
            ))
        }
        return candidates.sorted { $0.expectedNextDate < $1.expectedNextDate }
    }

    // MARK: - Cash flow forecast

    /// A simple projection: income minus what's already been spent this
    /// month minus bill-like transactions from last month not yet repeated
    /// this month (a proxy for "upcoming bills" until Phase 3's bill
    /// detection has enough history to schedule them precisely).
    public static func cashFlowForecast(
        transactions: [ExpenseTransaction],
        monthlyIncome: Decimal,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> CashFlowForecast {
        let monthStart = calendar.startOfMonth(for: now)
        let spentThisMonth = transactions
            .filter { $0.date >= monthStart }
            .reduce(Decimal(0)) { $0 + $1.amount }

        guard let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else {
            return CashFlowForecast(
                monthlyIncome: monthlyIncome,
                spentSoFarThisMonth: spentThisMonth,
                upcomingBillsTotal: 0,
                projectedEndOfMonthBalance: monthlyIncome - spentThisMonth
            )
        }

        let lastMonthBills = transactions.filter {
            $0.isBillLike && $0.date >= lastMonthStart && $0.date < monthStart
        }
        let thisMonthBillMerchants = Set(
            transactions
                .filter { $0.isBillLike && $0.date >= monthStart }
                .compactMap { $0.merchantName.map(MerchantCategoryMapping.normalize) }
        )
        let notYetRepeated = lastMonthBills.filter {
            guard let merchant = $0.merchantName else { return true }
            return !thisMonthBillMerchants.contains(MerchantCategoryMapping.normalize(merchant))
        }
        let upcomingBillsTotal = notYetRepeated.reduce(Decimal(0)) { $0 + $1.amount }

        return CashFlowForecast(
            monthlyIncome: monthlyIncome,
            spentSoFarThisMonth: spentThisMonth,
            upcomingBillsTotal: upcomingBillsTotal,
            projectedEndOfMonthBalance: monthlyIncome - spentThisMonth - upcomingBillsTotal
        )
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
