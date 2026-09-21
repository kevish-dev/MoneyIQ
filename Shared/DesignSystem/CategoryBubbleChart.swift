import SwiftUI
import MoneyIQCore

/// A single circular "bubble" progress ring — diameter and ring fill are
/// both driven by a category's percentage share of total spend, matching
/// the bubble-chart pattern from the design reference (image 3/4): a
/// bigger bubble and a fuller ring both mean a bigger share.
struct CategoryBubble: View {
    let share: InsightsEngine.CategoryShare
    var diameter: CGFloat

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.heroGradient)

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)

            Circle()
                .trim(from: 0, to: appeared ? share.fraction : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Image(systemName: share.systemIconName)
                    .font(.system(size: diameter * 0.17, weight: .medium))
                    .foregroundStyle(.white)
                Text(share.categoryName)
                    .font(.system(size: diameter * 0.1, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(share.fraction, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: diameter * 0.13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(diameter * 0.16)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: AppTheme.emberRed.opacity(0.35), radius: 10, y: 6)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.35).delay(.random(in: 0...0.15))) {
                appeared = true
            }
        }
    }
}

/// A wrapping "flow" layout that packs views of varying size left-to-right,
/// top-to-bottom — used for the bubble grid since bubble diameters vary by
/// share and won't fit a fixed-column `LazyVGrid` cleanly.
struct FlowLayout: Layout {
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The category bubble chart — sizes each bubble's diameter within
/// `[minDiameter, maxDiameter]` proportionally to its share of total spend,
/// then packs them in a loose wrapping grid.
struct CategoryBubbleChart: View {
    let shares: [InsightsEngine.CategoryShare]

    private let minDiameter: CGFloat = 92
    private let maxDiameter: CGFloat = 168

    private func diameter(for share: InsightsEngine.CategoryShare) -> CGFloat {
        guard let maxFraction = shares.map(\.fraction).max(), maxFraction > 0 else { return minDiameter }
        let t = share.fraction / maxFraction
        return minDiameter + (maxDiameter - minDiameter) * CGFloat(t)
    }

    var body: some View {
        FlowLayout(spacing: 14) {
            ForEach(shares) { share in
                CategoryBubble(share: share, diameter: diameter(for: share))
            }
        }
    }
}
