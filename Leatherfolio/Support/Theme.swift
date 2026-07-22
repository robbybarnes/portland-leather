import SwiftUI

/// Warm editorial design language: cream backgrounds, cognac accents,
/// espresso text, serif display type. Colors resolve from the asset catalog
/// (light/dark variants; WCAG AA verified by ThemeContrastTests).
enum Theme {
    static let background = Color("Cream")
    static let card = Color("Parchment")
    static let textPrimary = Color("Espresso")
    static let textSecondary = Color("Nutmeg")
    static let accent = Color("Cognac")
    static let gain = Color("Gain")
    static let loss = Color("Loss")

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cardCornerRadius: CGFloat = 14
}

extension Font {
    /// Serif display type (New York) for titles and headline moments.
    /// Built on system text styles, so Dynamic Type scaling is preserved.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }
}

/// Card treatment used by grid cells and detail/stat blocks: parchment
/// surface, rounded corners, hairline shadow.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
