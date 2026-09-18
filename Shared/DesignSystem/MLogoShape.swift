import SwiftUI

/// The connecting "V" stroke between the M's two legs, as its own filled
/// ribbon shape (not just an outline) so it can carry its own Liquid Glass
/// surface, separate from the leg capsules.
private struct MMidVShape: Shape {
    func path(in rect: CGRect) -> Path {
        var line = Path()
        line.move(to: CGPoint(x: rect.minX, y: rect.minY))
        line.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        line.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return line.strokedPath(
            StrokeStyle(lineWidth: rect.width * 0.30, lineCap: .round, lineJoin: .round)
        )
    }
}

/// The full MoneyIQ "M" mark, built from three separate Liquid Glass
/// surfaces — a left leg, a right leg, and a connecting "V" — grouped in one
/// `GlassEffectContainer` so they optically merge at the seams, the way
/// distinct panes of glass do, instead of looking like one flat stroke.
struct MLogoView: View {
    var size: CGFloat = 160

    var body: some View {
        GlassEffectContainer {
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let legWidth = w * 0.24
                let legHeight = h * 0.94

                ZStack {
                    Capsule()
                        .fill(.clear)
                        .frame(width: legWidth, height: legHeight)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                        .position(x: legWidth / 2 + w * 0.02, y: h / 2)

                    Capsule()
                        .fill(.clear)
                        .frame(width: legWidth, height: legHeight)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                        .position(x: w - legWidth / 2 - w * 0.02, y: h / 2)

                    Color.clear
                        .frame(width: w, height: h * 0.86)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.85)).interactive(), in: MMidVShape())
                        .position(x: w / 2, y: h * 0.47)
                }
            }
        }
        .frame(width: size, height: size * 0.68)
        .shadow(color: .accentColor.opacity(0.25), radius: 24, x: 0, y: 16)
    }
}

#Preview {
    MLogoView()
        .padding(60)
        .background(Color(white: 0.95))
}
