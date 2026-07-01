public import SwiftUI

/// Ledger type scale from `design-tokens.json` → `typography.scale` (iOS
/// column). Sizes are Dynamic-Type-aware: each role is backed by a relative
/// `Font.TextStyle` so custom point sizes still scale with the user's preferred
/// content size. Negative tracking is applied to display sizes only.
public enum AnkountantFont: Sendable {
    case displayHero       // 34pt semibold, -0.34 tracking
    case sectionHeading    // 24pt semibold, -0.36 tracking
    case cardTitle         // 20pt semibold, -0.20 tracking
    case body              // 17pt regular, no tracking
    case bodyEmphasis      // 17pt semibold, no tracking
    case callout           // 15pt regular, no tracking
    case caption           // 13pt medium, no tracking
    case captionBold       // 13pt semibold, no tracking
    case micro             // 12pt semibold, +0.24 tracking (uppercase labels)
    case mono              // 15pt, ledger / JE cells

    /// The base (unscaled) point size — the token's iOS value.
    var size: CGFloat {
        switch self {
        case .displayHero:    34
        case .sectionHeading: 24
        case .cardTitle:      20
        case .body:           17
        case .bodyEmphasis:   17
        case .callout:        15
        case .caption:        13
        case .captionBold:    13
        case .micro:          12
        case .mono:           15
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayHero:    .semibold
        case .sectionHeading: .semibold
        case .cardTitle:      .semibold
        case .body:           .regular
        case .bodyEmphasis:   .semibold
        case .callout:        .regular
        case .caption:        .medium
        case .captionBold:    .semibold
        case .micro:          .semibold
        case .mono:           .regular
        }
    }

    /// The `TextStyle` each role scales relative to, so custom sizes still
    /// honor Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .displayHero:    .largeTitle
        case .sectionHeading: .title
        case .cardTitle:      .title3
        case .body:           .body
        case .bodyEmphasis:   .body
        case .callout:        .callout
        case .caption:        .footnote
        case .captionBold:    .footnote
        case .micro:          .caption
        case .mono:           .callout
        }
    }

    /// Tracking, applied to display sizes only. Body/caption use 0 tracking
    /// (per token: negative tracking on display sizes only).
    var tracking: CGFloat {
        switch self {
        case .displayHero:    -0.34   // -0.01em @ 34pt
        case .sectionHeading: -0.36   // -0.015em @ 24pt
        case .cardTitle:      -0.20   // -0.01em @ 20pt
        case .micro:           0.24   // +0.02em @ 12pt (uppercase functional labels)
        default:               0
        }
    }

    /// The design family — mono roles use a monospaced system face.
    var design: Font.Design {
        self == .mono ? .monospaced : .default
    }
}

public extension View {
    /// Apply a Ledger type role. The point size scales with Dynamic Type and
    /// tracking is applied on display roles only.
    func ankountantFont(_ style: AnkountantFont) -> some View {
        modifier(AnkountantFontModifier(style: style))
    }

    /// Data-cell alignment for JE / score columns: monospaced digits so numbers
    /// line up in tables and ledgers.
    func dataCell(_ style: AnkountantFont = .mono) -> some View {
        modifier(AnkountantFontModifier(style: style, numeric: true))
    }
}

/// A Dynamic-Type-aware font modifier. Uses `@ScaledMetric(relativeTo:)` to
/// scale the token's fixed point size against the matching text style.
private struct AnkountantFontModifier: ViewModifier {
    let style: AnkountantFont
    var numeric: Bool = false

    @ScaledMetric private var scaledSize: CGFloat
    private let tracking: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let numericVariant: Bool

    init(style: AnkountantFont, numeric: Bool = false) {
        self.style = style
        self._scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        self.tracking = style.tracking
        self.weight = style.weight
        self.design = style.design
        self.numericVariant = numeric || style == .mono
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .tracking(tracking)
    }

    private var font: Font {
        let base = Font.system(size: scaledSize, weight: weight, design: design)
        return numericVariant ? base.monospacedDigit() : base
    }
}
