import SwiftUI

/// A circular icon badge — the leading "icon in a tinted circle" element
/// used throughout transaction/account/goal rows, matching the design
/// reference's row style (image 2's transaction list). One shared component
/// so every list row across tabs looks consistent.
struct IconBubble: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var diameter: CGFloat = 40

    var body: some View {
        Circle()
            .fill(tint.opacity(0.15))
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: diameter * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}
