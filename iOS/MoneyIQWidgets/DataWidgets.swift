import SwiftUI
import WidgetKit
import MoneyIQCore

private enum MoneyWidgetStyle {
    static let green = Color(red: 0.08, green: 0.43, blue: 0.34)
    static let cream = Color(red: 0.96, green: 0.97, blue: 0.94)
    static let paleOrange = Color(red: 1, green: 0.96, blue: 0.91)

    static func money(_ value: Decimal, _ code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}

struct BudgetShortcutWidget: Widget {
    let kind = "com.moneyiq.budget-shortcut"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { entry in
            MonthlyBudgetView(entry: entry)
        }
        .configurationDisplayName("Monthly Spending")
        .description("See this month's spending and budget progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct MonthlyBudgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinanceEntry

    private var snapshot: WidgetSnapshot? { entry.currentSnapshot }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default: inline
            }
        }
        .containerBackground(family == .systemSmall || family == .systemMedium ? MoneyWidgetStyle.cream : .clear, for: .widget)
        .widgetURL(WidgetRoute.budget.url)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(MoneyWidgetStyle.green)
                Spacer()
                if let snapshot, snapshot.monthlyCap != nil {
                    Text("\(Int(snapshot.percentUsed.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MoneyWidgetStyle.green)
                        .privacySensitive()
                }
            }
            Spacer(minLength: 8)
            Text("THIS MONTH")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            if let snapshot {
                Text(MoneyWidgetStyle.money(snapshot.monthSpent, snapshot.currencyCode))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LaunchStyle.ink)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .privacySensitive()
                if let cap = snapshot.monthlyCap {
                    ProgressView(value: snapshot.fractionUsed)
                        .tint((snapshot.remaining ?? 0) < 0 ? LaunchStyle.accent : MoneyWidgetStyle.green)
                        .padding(.top, 9)
                    Text("of \(MoneyWidgetStyle.money(cap, snapshot.currencyCode)) budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 4)
                        .privacySensitive()
                } else {
                    Text("Set a monthly budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 7)
                }
            } else {
                Text("Open MoneyIQ to refresh")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LaunchStyle.ink)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 17) {
            VStack(alignment: .leading, spacing: 5) {
                Label("MONTHLY SPENDING", systemImage: "chart.pie.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(MoneyWidgetStyle.green)
                Spacer(minLength: 1)
                if let snapshot {
                    Text(MoneyWidgetStyle.money(snapshot.monthSpent, snapshot.currencyCode))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                    if let cap = snapshot.monthlyCap {
                        ProgressView(value: snapshot.fractionUsed)
                            .tint((snapshot.remaining ?? 0) < 0 ? LaunchStyle.accent : MoneyWidgetStyle.green)
                        Text("\(Int(snapshot.percentUsed.rounded()))% of \(MoneyWidgetStyle.money(cap, snapshot.currencyCode))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .privacySensitive()
                    } else {
                        Text("No budget set")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Open MoneyIQ to refresh")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if let snapshot, let remaining = snapshot.remaining {
                    Text(remaining < 0 ? "OVER BUDGET" : "LEFT THIS MONTH")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(MoneyWidgetStyle.money(abs(remaining), snapshot.currencyCode))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(remaining < 0 ? LaunchStyle.accent : MoneyWidgetStyle.green)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                } else if let snapshot {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(MoneyWidgetStyle.money(snapshot.spendingToday(at: entry.date), snapshot.currencyCode))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MoneyWidgetStyle.green)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    quickAction("plus", .addExpense, "Log expense")
                    quickAction("doc.on.clipboard", .pasteExpense, "Paste expense")
                    quickAction("photo", .screenshotExpense, "Add screenshot")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickAction(_ symbol: String, _ route: WidgetRoute, _ label: String) -> some View {
        Link(destination: route.url) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MoneyWidgetStyle.green)
                .frame(width: 32, height: 32)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(label)
    }

    private var circular: some View {
        Group {
            if let snapshot, snapshot.monthlyCap != nil {
                Gauge(value: snapshot.fractionUsed) {
                    Image(systemName: "chart.pie.fill")
                } currentValueLabel: {
                    Text("\(Int(snapshot.percentUsed.rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .privacySensitive()
            } else if let snapshot {
                VStack(spacing: 1) {
                    Image(systemName: "chart.pie.fill")
                    Text(MoneyWidgetStyle.money(snapshot.monthSpent, snapshot.currencyCode))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .privacySensitive()
                }
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MONTHLY SPENDING")
                .font(.caption2.weight(.bold))
            if let snapshot {
                Text(MoneyWidgetStyle.money(snapshot.monthSpent, snapshot.currencyCode))
                    .font(.headline)
                    .privacySensitive()
                if let cap = snapshot.monthlyCap {
                    ProgressView(value: snapshot.fractionUsed)
                    Text("of \(MoneyWidgetStyle.money(cap, snapshot.currencyCode))")
                        .font(.caption2)
                        .privacySensitive()
                }
            } else {
                Text("Open to refresh")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            if let snapshot {
                Text("Month: \(MoneyWidgetStyle.money(snapshot.monthSpent, snapshot.currencyCode))")
                    .privacySensitive()
            } else {
                Text("Monthly spending: refresh")
            }
        }
    }
}

struct TodaySpendingWidget: Widget {
    let kind = "com.moneyiq.today-spending"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { entry in
            TodaySpendingView(entry: entry)
        }
        .configurationDisplayName("Today's Spending")
        .description("Track today's expense total and quickly add another.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TodaySpendingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinanceEntry

    private var snapshot: WidgetSnapshot? { entry.currentSnapshot }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 23))
                        .foregroundStyle(LaunchStyle.orange)
                    Spacer(minLength: 5)
                    Text("SPENT TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    if let snapshot {
                        Text(MoneyWidgetStyle.money(snapshot.spendingToday(at: entry.date), snapshot.currencyCode))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(LaunchStyle.ink)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .privacySensitive()
                        if let allowance = snapshot.dailyAllowance(at: entry.date) {
                            Text("\(MoneyWidgetStyle.money(allowance, snapshot.currencyCode)) daily pace")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.top, 5)
                                .privacySensitive()
                        }
                    } else {
                        Text("Open to refresh")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                    Text(snapshot.map { MoneyWidgetStyle.money($0.spendingToday(at: entry.date), $0.currencyCode) } ?? "—")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .privacySensitive()
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("SPENT TODAY", systemImage: "sun.max.fill")
                        .font(.caption2.weight(.bold))
                    Text(snapshot.map { MoneyWidgetStyle.money($0.spendingToday(at: entry.date), $0.currencyCode) } ?? "Open to refresh")
                        .font(.headline)
                        .privacySensitive()
                    if let snapshot, let allowance = snapshot.dailyAllowance(at: entry.date) {
                        Text("\(MoneyWidgetStyle.money(allowance, snapshot.currencyCode)) daily pace")
                            .font(.caption2)
                            .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Text(snapshot.map { "Today: \(MoneyWidgetStyle.money($0.spendingToday(at: entry.date), $0.currencyCode))" } ?? "Today's spending: refresh")
                    .privacySensitive()
            }
        }
        .containerBackground(family == .systemSmall ? MoneyWidgetStyle.paleOrange : .clear, for: .widget)
        .widgetURL(WidgetRoute.addExpense.url)
    }
}

struct InsightsShortcutWidget: Widget {
    let kind = "com.moneyiq.insights-shortcut"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { entry in
            TopCategoryView(entry: entry)
        }
        .configurationDisplayName("Top Spending Category")
        .description("See which category accounts for the most spending this month.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

private struct TopCategoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinanceEntry

    private var snapshot: WidgetSnapshot? { entry.currentSnapshot }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(MoneyWidgetStyle.green)
                    Spacer(minLength: 5)
                    Text("TOP CATEGORY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(snapshot?.topCategoryName ?? (snapshot == nil ? "Open to refresh" : snapshot?.monthSpent == 0 ? "No expenses yet" : "No category yet"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let snapshot, snapshot.topCategoryName != nil {
                        Text(MoneyWidgetStyle.money(snapshot.topCategoryAmount, snapshot.currencyCode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MoneyWidgetStyle.green)
                            .padding(.top, 4)
                            .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("TOP THIS MONTH", systemImage: "chart.bar.xaxis")
                        .font(.caption2.weight(.bold))
                    Text(snapshot?.topCategoryName ?? (snapshot == nil ? "Open to refresh" : snapshot?.monthSpent == 0 ? "No expenses yet" : "No category yet"))
                        .font(.headline)
                        .lineLimit(1)
                    if let snapshot, snapshot.topCategoryName != nil {
                        Text(MoneyWidgetStyle.money(snapshot.topCategoryAmount, snapshot.currencyCode))
                            .font(.caption)
                            .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                if let snapshot, let category = snapshot.topCategoryName {
                    Text("Top: \(category) \(MoneyWidgetStyle.money(snapshot.topCategoryAmount, snapshot.currencyCode))")
                        .privacySensitive()
                } else if snapshot != nil {
                    Text("Top category: none yet")
                } else {
                    Text("Top category: refresh")
                }
            }
        }
        .containerBackground(family == .systemSmall ? MoneyWidgetStyle.cream : .clear, for: .widget)
        .widgetURL(WidgetRoute.insights.url)
    }
}
