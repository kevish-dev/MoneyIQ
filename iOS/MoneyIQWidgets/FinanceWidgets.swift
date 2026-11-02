import SwiftUI
import WidgetKit
import MoneyIQCore

/// Action-only widgets route into the app to review or log an expense.
private struct LaunchEntry: TimelineEntry {
    let date: Date
}

private struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry(date: .now)], policy: .never))
    }
}

struct FinanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var currentSnapshot: WidgetSnapshot? {
        guard let snapshot, snapshot.isCurrentMonth(at: date) else { return nil }
        return snapshot
    }
}

struct FinanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinanceEntry {
        let now = Date.now
        return FinanceEntry(date: now, snapshot: WidgetSnapshot(
            refreshedAt: now,
            monthStart: Calendar.current.startOfMonth(for: now),
            dayStart: Calendar.current.startOfDay(for: now),
            currencyCode: "INR",
            monthSpent: 12_400,
            todaySpent: 480,
            monthlyCap: 30_000,
            topCategoryName: "Food",
            topCategoryAmount: 4_200
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : FinanceEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceEntry>) -> Void) {
        let now = Date.now
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
        let snapshot = WidgetSnapshotStore.load()
        completion(Timeline(entries: [
            FinanceEntry(date: now, snapshot: snapshot),
            FinanceEntry(date: nextDay, snapshot: snapshot)
        ], policy: .after(nextDay.addingTimeInterval(60))))
    }
}

enum LaunchStyle {
    static let accent = Color(red: 0.70, green: 0.14, blue: 0.05)
    static let orange = Color(red: 0.88, green: 0.39, blue: 0.08)
    static let ink = Color(red: 0.18, green: 0.17, blue: 0.21)
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.95)
}

struct ScreenshotExpenseWidget: Widget {
    let kind = "com.moneyiq.screenshot-expense"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LaunchProvider()) { _ in ScreenshotExpenseView() }
            .configurationDisplayName("Expense from Screenshot")
            .description("Choose a payment screenshot to read on your device and review.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ScreenshotExpenseView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LaunchStyle.orange)
                        .frame(width: 40, height: 40)
                        .background(LaunchStyle.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 8)
                    Text("Add from screenshot")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                        .lineLimit(2)
                    Text("Pick a payment image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "photo.on.rectangle").font(.title2)
                    Text("SHOT").font(.system(size: 9, weight: .bold))
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle").font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add screenshot").font(.headline)
                        Text("Choose payment image").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Label("Add screenshot", systemImage: "photo.on.rectangle")
            }
        }
        .containerBackground(family == .systemSmall ? Color(red: 1, green: 0.96, blue: 0.92) : .clear, for: .widget)
        .widgetURL(WidgetRoute.screenshotExpense.url)
        .accessibilityLabel("Add an expense from a screenshot in MoneyIQ")
    }
}

struct PasteExpenseWidget: Widget {
    let kind = "com.moneyiq.paste-expense"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LaunchProvider()) { _ in PasteExpenseView() }
            .configurationDisplayName("Paste Expense")
            .description("Copy a payment receipt, then tap to import it for review.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct PasteExpenseView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LaunchStyle.accent)
                        .frame(width: 40, height: 40)
                        .background(LaunchStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 8)
                    Text("Paste an expense")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                        .lineLimit(2)
                    Text("Copy a receipt first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "doc.on.clipboard.fill").font(.title2)
                    Text("PASTE").font(.system(size: 9, weight: .bold))
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Paste expense").font(.headline)
                        Text("Import copied receipt").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Label("Paste expense", systemImage: "doc.on.clipboard.fill")
            }
        }
        .containerBackground(family == .systemSmall ? LaunchStyle.paper : .clear, for: .widget)
        .widgetURL(WidgetRoute.pasteExpense.url)
        .accessibilityLabel("Paste a copied expense in MoneyIQ")
    }
}

struct QuickLogWidget: Widget {
    let kind = "com.moneyiq.quick-log"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LaunchProvider()) { _ in QuickLogView() }
            .configurationDisplayName("Log an Expense")
            .description("Open expense entry from your Home or Lock Screen.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct QuickLogView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 8)
                    Text("Log an expense")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text("Tap to add")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                    Text("LOG").font(.system(size: 9, weight: .bold))
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Log expense").font(.headline)
                        Text("Open entry form").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Label("Log expense", systemImage: "plus.circle.fill")
            }
        }
        .containerBackground(family == .systemSmall ? LaunchStyle.accent : .clear, for: .widget)
        .widgetURL(WidgetRoute.addExpense.url)
        .accessibilityLabel("Log an expense in MoneyIQ")
    }
}

struct MoneyIQHubWidget: Widget {
    let kind = "com.moneyiq.quick-actions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { entry in MoneyIQHubView(entry: entry) }
            .configurationDisplayName("Today + Quick Actions")
            .description("See today's total and paste, scan, or log an expense.")
            .supportedFamilies([.systemMedium])
    }
}

private struct MoneyIQHubView: View {
    let entry: FinanceEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SPENT TODAY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(LaunchStyle.accent)
                Spacer(minLength: 4)
                if let snapshot = entry.currentSnapshot {
                    Text(snapshot.spendingToday(at: entry.date), format: .currency(code: snapshot.currencyCode).precision(.fractionLength(0)))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .privacySensitive()
                    Text("\(snapshot.monthSpent.formatted(.currency(code: snapshot.currencyCode).precision(.fractionLength(0)))) this month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .privacySensitive()
                } else {
                    Text("Add an\nexpense.")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(LaunchStyle.ink)
                    Text("Open MoneyIQ to sync totals")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                action("Paste expense", symbol: "doc.on.clipboard.fill", route: .pasteExpense)
                action("Screenshot", symbol: "photo.on.rectangle", route: .screenshotExpense)
                action("Log manually", symbol: "plus.circle.fill", route: .addExpense)
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(LaunchStyle.paper, for: .widget)
        .widgetURL(WidgetRoute.budget.url)
    }

    private func action(_ title: String, symbol: String, route: WidgetRoute) -> some View {
        Link(destination: route.url) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(LaunchStyle.accent)
                    .frame(width: 17)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LaunchStyle.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Open \(title) in MoneyIQ")
    }
}

