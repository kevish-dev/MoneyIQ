import SwiftUI

/// Central color/gradient tokens for MoneyIQ's orange/red brand identity —
/// the single source of truth the redesign introduced so every tab (Home,
/// Split, Insights, Goals, Net Worth, Settings) pulls from the same
/// palette instead of ad hoc `.blue`/`.orange` one-offs. Matches
/// `Assets.xcassets/AccentColor` (which drives `.accentColor`/`.tint(.accentColor)`
/// automatically) plus the darker gradient stops used for hero cards that
/// need an explicit `Color`/`LinearGradient` value.
enum AppTheme {
    /// The trailing (right-side) toolbar slot — `.topBarTrailing` is
    /// iOS-only, so this picks the closest macOS equivalent instead of
    /// failing to compile there. Used for the top-right profile icon.
    static var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// Bright orange accent — same value as Assets.xcassets/AccentColor.
    /// Kept as an explicit token too, for call sites that need a `Color`
    /// before the view's environment resolves `.accentColor` (e.g. gradient
    /// stops, chart marks).
    static let accent = Color(red: 1.0, green: 0.478, blue: 0.161)
    static let accentSecondary = Color(red: 1.0, green: 0.616, blue: 0.294)

    /// Deep red/ember stops for the dark hero-card gradient (image 4's
    /// balance/chart card background).
    static let deepRed = Color(red: 0.40, green: 0.05, blue: 0.05)
    static let emberRed = Color(red: 0.70, green: 0.14, blue: 0.05)

    /// The dark red-to-orange gradient behind hero cards.
    static let heroGradient = LinearGradient(
        colors: [deepRed, emberRed, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradientVertical = LinearGradient(
        colors: [deepRed, emberRed, accent],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardCornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 16

    /// A subtle translucent pill background used for badges/chips sitting
    /// on top of a hero gradient (e.g. the "+2.46% this month" pill).
    static let pillBackgroundOnHero = Color.white.opacity(0.18)

    /// Shared spacing scale — introduced so every screen's card padding,
    /// row insets, and section gaps come from the same handful of values
    /// instead of scattered one-off numbers (8, 12, 14, 16, 18, 20... all
    /// meaning slightly different things depending on which view you're
    /// reading). Pick the closest token rather than reaching for a literal.
    enum Spacing {
        /// Tight gaps: badge/pill internal padding, icon-to-text spacing.
        static let xs: CGFloat = 4
        /// Row vertical insets (list rows, entry rows).
        static let small: CGFloat = 8
        /// Default inline spacing between stacked elements within a card.
        static let medium: CGFloat = 12
        /// Outer padding for hero cards and top-level sections.
        static let large: CGFloat = 20
        /// Gap between major sections on a scrollable screen.
        static let xl: CGFloat = 24
    }
}

extension View {
    /// Minimal, consistent top gap and inter-section spacing for
    /// `List`-based content screens (Home, Goals, Net Worth, Split, and
    /// their push destinations) — inline title so the heading sits right
    /// under the status bar with no large-title gap, `.plain` style and
    /// `.compact` section spacing so sections start immediately below it
    /// instead of the system's default (fairly large) grouped-list insets.
    func compactListLayout() -> some View {
        self
            .listStyle(.plain)
            #if os(iOS)
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    /// Same top-gap/title treatment as `compactListLayout()`, for
    /// `Form`-based input screens — keeps the native grouped form style
    /// (so pickers/toggles/text fields still look like a settings form)
    /// but still tightens section spacing and the top gap for consistency.
    func compactFormLayout() -> some View {
        self
            #if os(iOS)
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}
