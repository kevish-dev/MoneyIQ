import SwiftUI
import Charts
import MoneyIQCore

/// A spend-over-time line/area chart with a scrubbable tooltip — one shared
/// component for both platforms, per the design reference (image 4's
/// tooltip-on-line-chart pattern):
///
/// - iOS/iPadOS: drag a finger along the chart (`DragGesture` inside
///   `.chartOverlay`) to scrub the tooltip to the nearest data point.
/// - macOS: real pointer hover (`.onContinuousHover`) shows the same
///   tooltip as the pointer moves — a no-op on iPhone (no pointer), so both
///   handlers can live in the same view with no `#if os()` branching for
///   the interaction logic itself.
struct InteractiveSpendChart: View {
    let data: [InsightsEngine.DailySpend]
    let currencyCode: String

    @State private var selectedIndex: Int?

    private var selectedPoint: InsightsEngine.DailySpend? {
        guard let selectedIndex, data.indices.contains(selectedIndex) else { return nil }
        return data[selectedIndex]
    }

    var body: some View {
        Chart(data) { point in
            AreaMark(
                x: .value("Day", point.day),
                y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", point.day),
                y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
            )
            .foregroundStyle(.white)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)

            if let selectedPoint, point.id == selectedPoint.id {
                PointMark(
                    x: .value("Day", point.day),
                    y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
                )
                .foregroundStyle(.white)
                .symbolSize(80)

                RuleMark(x: .value("Day", point.day))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // `.simultaneousGesture` instead of `.gesture` on
                    // purpose: this chart sits inside a ScrollView
                    // (InsightsView's hero card), and a plain `.gesture`
                    // with `minimumDistance: 0` claims every touch the
                    // instant it starts, including ones the user meant as a
                    // vertical scroll — that made the whole page feel stuck
                    // right above/below the chart. `simultaneousGesture`
                    // lets the ScrollView's own pan recognizer keep
                    // competing for the touch instead of being preempted.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) { selectedIndex = nil }
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateSelection(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            withAnimation(.easeOut(duration: 0.2)) { selectedIndex = nil }
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            // The spring animation is scoped to just this overlay (the
            // tooltip), not the whole `Chart` — it used to be a trailing
            // `.animation(value: selectedIndex)` on the Chart itself, which
            // implicitly animated every mark (line, area, axes) on each
            // selection change, not just the tooltip fade/scale. That
            // showed up as the chart's marks visibly jittering/resettling
            // on every scrub tick instead of a clean tooltip transition.
            Group {
                if let selectedPoint {
                    tooltip(for: selectedPoint)
                        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0.3), value: selectedIndex)
        }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !data.isEmpty else { return }
        let origin = geometry[proxy.plotAreaFrame].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        guard let closest = data.indices.min(by: {
            abs(data[$0].day.timeIntervalSince(date)) < abs(data[$1].day.timeIntervalSince(date))
        }) else { return }
        if selectedIndex != closest {
            selectedIndex = closest
        }
    }

    private func tooltip(for point: InsightsEngine.DailySpend) -> some View {
        VStack(spacing: 2) {
            Text(point.total, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.bold))
            Text(point.day, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.black)
        .shadow(radius: 6, y: 3)
    }
}
