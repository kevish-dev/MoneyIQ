import SwiftUI
import Charts
import MoneyIQCore

/// The Insights hero card: a big current-period total over a smooth trend
/// line, with a calendar-icon toggle between a trailing 6-month view and a
/// trailing 5-year view, and a scrubbable speech-bubble tooltip on the line
/// itself — matches the design reference's balance-card pattern (dark
/// red-to-orange gradient, "+X% this period" pill, white tooltip bubble with
/// a black percent badge and a pointer tail).
struct SpendTrendCard: View {
    enum Granularity: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case yearly = "Yearly"
        var id: String { rawValue }
    }

    let monthlyTotals: [InsightsEngine.MonthlyTotal]
    let yearlyTotals: [InsightsEngine.YearlyTotal]
    let currencyCode: String
    /// The month currently browsed elsewhere on the Insights screen (via
    /// the month navigator) — drives which point is permanently highlighted
    /// and which header total/pill show, so this card stays in sync with
    /// the rest of the page instead of always just showing "the latest."
    let selectedMonth: Date
    let selectedMonthTotal: Decimal
    let selectedMonthPercentChange: Double?
    let selectedYearTotal: Decimal
    let selectedYearPercentChange: Double?
    /// Called when the user drags/taps a specific month's point while in
    /// Monthly mode, so the rest of the page (category breakdown, top
    /// merchants, ...) can jump to that month too.
    let onSelectMonth: (Date) -> Void

    @State private var granularity: Granularity = .monthly
    @State private var scrubIndex: Int?

    private var calendar: Calendar { .current }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let total: Decimal
    }

    private var points: [Point] {
        switch granularity {
        case .monthly: monthlyTotals.map { Point(date: $0.monthStart, total: $0.total) }
        case .yearly: yearlyTotals.map { Point(date: $0.yearStart, total: $0.total) }
        }
    }

    /// The index matching `selectedMonth` (or its year), if it falls within
    /// the currently displayed trailing window — nil when the user has
    /// navigated further back than the chart shows, in which case nothing
    /// is permanently highlighted until they scrub.
    private var settledIndex: Int? {
        points.firstIndex { point in
            granularity == .monthly
                ? calendar.isDate(point.date, equalTo: selectedMonth, toGranularity: .month)
                : calendar.isDate(point.date, equalTo: selectedMonth, toGranularity: .year)
        }
    }

    private var highlightedIndex: Int? { scrubIndex ?? settledIndex }

    private var headerTotal: Decimal {
        granularity == .monthly ? selectedMonthTotal : selectedYearTotal
    }

    private var headerPercentChange: Double? {
        granularity == .monthly ? selectedMonthPercentChange : selectedYearPercentChange
    }

    private var hasAnySpend: Bool { points.contains { $0.total > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(headerTotal, format: .currency(code: currencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            if !hasAnySpend {
                Text("No spending yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(height: 150)
            } else {
                chart
                    .frame(height: 160)
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradientVertical, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.3), radius: 16, y: 10)
        .animation(.easeInOut(duration: 0.3), value: headerTotal)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: granularity)
    }

    private var header: some View {
        HStack {
            if let headerPercentChange {
                Label(
                    headerPercentChange.formatted(.percent.precision(.fractionLength(1))) + " this \(granularity == .monthly ? "month" : "year")",
                    systemImage: headerPercentChange >= 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.white.opacity(0.12)), in: .capsule)
                .foregroundStyle(.white)
            }
            Spacer()
            Menu {
                Picker("Range", selection: $granularity) {
                    ForEach(Granularity.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .glassEffect(.regular.tint(.white.opacity(0.12)), in: .circle)
            }
        }
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Period", point.date),
                y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
            )
            .foregroundStyle(
                LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Period", point.date),
                y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
            )
            .foregroundStyle(.white)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)

            if let highlightedIndex, points.indices.contains(highlightedIndex), points[highlightedIndex].id == point.id {
                PointMark(
                    x: .value("Period", point.date),
                    y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
                )
                .foregroundStyle(.white)
                .symbolSize(90)

                RuleMark(x: .value("Period", point.date))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(granularity == .monthly ? date.formatted(.dateTime.month(.abbreviated)) : date.formatted(.dateTime.year()))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // `.simultaneousGesture` so this chart's drag doesn't
                    // steal the enclosing ScrollView's vertical pan — same
                    // reasoning as `InteractiveSpendChart`.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                if granularity == .monthly, let scrubIndex, points.indices.contains(scrubIndex) {
                                    onSelectMonth(points[scrubIndex].date)
                                }
                                withAnimation(.easeOut(duration: 0.2)) { scrubIndex = nil }
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateSelection(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            withAnimation(.easeOut(duration: 0.2)) { scrubIndex = nil }
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            Group {
                if let scrubIndex, points.indices.contains(scrubIndex) {
                    SpendTrendTooltip(
                        amount: points[scrubIndex].total,
                        currencyCode: currencyCode,
                        percentChange: percentChange(at: scrubIndex),
                        periodLabel: periodLabel(for: points[scrubIndex].date)
                    )
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0.3), value: scrubIndex)
        }
    }

    private func periodLabel(for date: Date) -> String {
        granularity == .monthly ? date.formatted(.dateTime.month(.wide).year()) : date.formatted(.dateTime.year())
    }

    private func percentChange(at index: Int) -> Double? {
        guard index > 0, points.indices.contains(index - 1) else { return nil }
        let previous = points[index - 1].total
        let current = points[index].total
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !points.isEmpty else { return }
        let origin = geometry[proxy.plotAreaFrame].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        guard let closest = points.indices.min(by: {
            abs(points[$0].date.timeIntervalSince(date)) < abs(points[$1].date.timeIntervalSince(date))
        }) else { return }
        if scrubIndex != closest {
            scrubIndex = closest
        }
    }
}

/// The white speech-bubble tooltip shown while scrubbing the trend line —
/// amount + a black "vs. previous period" percent badge, a period label,
/// and a small pointer tail.
private struct SpendTrendTooltip: View {
    let amount: Decimal
    let currencyCode: String
    let percentChange: Double?
    let periodLabel: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(amount, format: .currency(code: currencyCode))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                    if let percentChange {
                        Label(
                            percentChange.formatted(.percent.precision(.fractionLength(1))),
                            systemImage: percentChange >= 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black, in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
                Text(periodLabel)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            TooltipTriangle()
                .fill(.white)
                .frame(width: 14, height: 8)
        }
    }
}

private struct TooltipTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
