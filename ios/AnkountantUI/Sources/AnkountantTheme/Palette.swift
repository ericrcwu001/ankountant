public import SwiftUI

/// The Ledger design-system palette. A single navy identity resolved by
/// `ColorScheme` into two concrete palettes (`light` / `dark`). All hex values
/// come from `docs_ankountant/design-tokens.json` and are pinned to the sRGB
/// color space in `Color.hex` for 1:1 parity with the web build.
public struct Palette: Sendable, Equatable {
    // Neutral surfaces
    public let background: Color        // neutral.bg
    public let surface: Color           // neutral.surface
    public let surfaceElevated: Color   // neutral.surfaceElevated
    public let surfaceInset: Color      // neutral.surfaceInset

    // Borders
    public let borderSubtle: Color      // neutral.borderSubtle
    public let border: Color            // neutral.border
    public let borderStrong: Color      // neutral.borderStrong

    // Text
    public let textPrimary: Color       // neutral.fg
    public let textSecondary: Color     // neutral.fgSecondary
    public let textTertiary: Color      // neutral.fgTertiary
    public let textDisabled: Color      // neutral.fgDisabled

    // Brand (chrome only — actions, links, focus, selection)
    public let accent: Color            // brand.accent
    public let accentFill: Color        // brand.fill
    public let accentHover: Color       // brand.hover
    public let link: Color              // brand.accent
    public let onAccent: Color          // white — sits on accentFill (navy passes AA)

    // Semantic states (data/state only; pair with icon + label)
    public let positive: Color          // state.positive (text-safe light / dark)
    public let warning: Color           // state.warning
    public let danger: Color            // state.danger
    public let info: Color              // state.info

    // Card-state hues (map onto the semantic states; used by views + widgets
    // so they stop hardcoding .blue / .orange / .green).
    public let stateNew: Color          // cardState.new  → info
    public let stateLearn: Color        // cardState.learn → danger (was iOS orange)
    public let stateReview: Color       // cardState.review → positive
    public let stateBuried: Color       // cardState.buried → warning

    // Meaning-bearing tokens preserved from the prior system.
    public let customStudyBadge: Color  // suspended yellow — do not repurpose

    // Elevation source: theme-aware shadow ink (see AnkountantElevation).
    public let shadow: Color

    public init(
        background: Color,
        surface: Color,
        surfaceElevated: Color,
        surfaceInset: Color,
        borderSubtle: Color,
        border: Color,
        borderStrong: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        textDisabled: Color,
        accent: Color,
        accentFill: Color,
        accentHover: Color,
        link: Color,
        onAccent: Color,
        positive: Color,
        warning: Color,
        danger: Color,
        info: Color,
        stateNew: Color,
        stateLearn: Color,
        stateReview: Color,
        stateBuried: Color,
        customStudyBadge: Color,
        shadow: Color
    ) {
        self.background = background
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.surfaceInset = surfaceInset
        self.borderSubtle = borderSubtle
        self.border = border
        self.borderStrong = borderStrong
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.textDisabled = textDisabled
        self.accent = accent
        self.accentFill = accentFill
        self.accentHover = accentHover
        self.link = link
        self.onAccent = onAccent
        self.positive = positive
        self.warning = warning
        self.danger = danger
        self.info = info
        self.stateNew = stateNew
        self.stateLearn = stateLearn
        self.stateReview = stateReview
        self.stateBuried = stateBuried
        self.customStudyBadge = customStudyBadge
        self.shadow = shadow
    }

    /// Resolve the concrete palette for a color scheme. There is a single
    /// design identity now, so only the scheme matters.
    public static func resolve(scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Hex helper (file-private, sRGB-pinned for web parity)

private extension Color {
    /// Build a color from a packed 0xRRGGBB value, pinned to the sRGB color
    /// space so iOS matches the web hexes exactly.
    static func hex(_ value: UInt32, opacity: Double = 1.0) -> Color {
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Light

public extension Palette {
    static let light = Palette(
        background: .hex(0xEEF0F4),
        surface: .hex(0xFBFBFC),
        surfaceElevated: .hex(0xFFFFFF),
        surfaceInset: .hex(0xFFFFFF),
        borderSubtle: .hex(0xE6E9EF),
        border: .hex(0xD5DAE3),
        borderStrong: .hex(0xB7BECB),
        textPrimary: .hex(0x0E0F13),
        textSecondary: .hex(0x3C424D),
        textTertiary: .hex(0x616875),
        textDisabled: .hex(0x9AA0AC),
        accent: .hex(0x1F3A5F),
        accentFill: .hex(0x1F3A5F),
        accentHover: .hex(0x172C48),
        link: .hex(0x1F3A5F),
        onAccent: .hex(0xFFFFFF),
        positive: .hex(0x157A42),
        warning: .hex(0x8A5A12),
        danger: .hex(0xB0322F),
        info: .hex(0x2559AE),
        stateNew: .hex(0x2559AE),   // info
        stateLearn: .hex(0xB0322F), // danger (reconciled from iOS orange)
        stateReview: .hex(0x157A42), // positive
        stateBuried: .hex(0x8A5A12), // warning
        customStudyBadge: .hex(0xFF9300),
        // elevation.light tinted to ink #0E0F13
        shadow: .hex(0x0E0F13)
    )
}

// MARK: - Dark

public extension Palette {
    static let dark = Palette(
        background: .hex(0x0F1216),
        surface: .hex(0x171B21),
        surfaceElevated: .hex(0x1F242C),
        surfaceInset: .hex(0x12151A),
        borderSubtle: .hex(0x262C34),
        border: .hex(0x303742),
        borderStrong: .hex(0x414A57),
        textPrimary: .hex(0xECEEF2),
        textSecondary: .hex(0xAEB4BF),
        textTertiary: .hex(0x8A909C),
        textDisabled: .hex(0x5B6270),
        accent: .hex(0x7FA6D4),
        accentFill: .hex(0x274B75),
        accentHover: .hex(0x2F5888),
        link: .hex(0x7FA6D4),
        onAccent: .hex(0xFFFFFF),
        positive: .hex(0x34D07C),
        warning: .hex(0xF5B44E),
        danger: .hex(0xF7625A),
        info: .hex(0x5AA0FF),
        stateNew: .hex(0x5AA0FF),   // info
        stateLearn: .hex(0xF7625A), // danger
        stateReview: .hex(0x34D07C), // positive
        stateBuried: .hex(0xF5B44E), // warning
        customStudyBadge: .hex(0xFF9F0A),
        // elevation.dark relies on pure black drops
        shadow: .hex(0x000000)
    )
}
