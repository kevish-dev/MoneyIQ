import SwiftUI

enum SplitDesign {
    static let ink = AppTheme.ink
    static let muted = AppTheme.muted
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.067, blue: 0.078, alpha: 1)
        : UIColor(red: 0.985, green: 0.978, blue: 0.967, alpha: 1) })
    static let card = AppTheme.surface
    static let receive = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.43, green: 0.84, blue: 0.68, alpha: 1)
        : UIColor(red: 0.10, green: 0.46, blue: 0.36, alpha: 1) })
    static let pay = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.55, blue: 0.42, alpha: 1)
        : UIColor(red: 0.72, green: 0.25, blue: 0.17, alpha: 1) })

    static func money(_ amount: Decimal, code: String) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }

    static func balanceDescription(_ net: Decimal, name: String) -> String {
        if net > 0 { return "\(name) owes you" }
        if net < 0 { return "You owe \(name)" }
        return "All settled up"
    }
}

struct SplitAvatar: View {
    let name: String
    let colorHex: String
    var size: CGFloat = 48

    private var tint: Color { Color(hex: colorHex) }

    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.33, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

struct SplitSheetHeader: View {
    let eyebrow: String
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 48, height: 48)
                .background(AppTheme.emberRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                .padding(.bottom, 7)
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accentText)
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(SplitDesign.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SplitDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SplitPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(AppTheme.emberRed, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.42)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
