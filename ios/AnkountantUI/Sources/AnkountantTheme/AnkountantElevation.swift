public import SwiftUI

/// Elevation scale from `design-tokens.json` → `elevation`. Borders-first;
/// shadows are tinted to the theme-aware `palette.shadow` ink. SwiftUI shadows
/// are single-layer, so each level models the dominant layer of the token's
/// two-layer web recipe. Opacity is baked into the shadow color, so pass a
/// fully-opaque `palette.shadow` and let the level apply its own alpha.
public enum AnkountantElevation: Sendable {
    case e0
    case e1
    case e2
    case e3

    /// Shadow parameters for the light scheme (ink #0E0F13). Opacities from
    /// the dominant layer of `elevation.light`.
    var light: ShadowSpec {
        switch self {
        case .e0: return .none
        case .e1: return ShadowSpec(opacity: 0.06, radius: 3, x: 0, y: 1)
        case .e2: return ShadowSpec(opacity: 0.09, radius: 10, x: 0, y: 4)
        case .e3: return ShadowSpec(opacity: 0.16, radius: 40, x: 0, y: 16)
        }
    }

    /// Shadow parameters for the dark scheme (pure black). Opacities from
    /// `elevation.dark`.
    var dark: ShadowSpec {
        switch self {
        case .e0: return .none
        case .e1: return ShadowSpec(opacity: 0.40, radius: 2, x: 0, y: 1)
        case .e2: return ShadowSpec(opacity: 0.50, radius: 16, x: 0, y: 6)
        case .e3: return ShadowSpec(opacity: 0.60, radius: 48, x: 0, y: 20)
        }
    }

    struct ShadowSpec: Sendable {
        var opacity: Double
        var radius: CGFloat
        var x: CGFloat
        var y: CGFloat
        static let none = ShadowSpec(opacity: 0, radius: 0, x: 0, y: 0)
    }
}

public extension View {
    /// Apply a theme-aware elevation shadow. The shadow color is derived from
    /// the palette's `shadow` ink and the scheme selects the light/dark recipe.
    func ankountantElevation(
        _ level: AnkountantElevation,
        palette: Palette,
        scheme: ColorScheme
    ) -> some View {
        let spec = scheme == .dark ? level.dark : level.light
        return shadow(
            color: palette.shadow.opacity(spec.opacity),
            radius: spec.radius,
            x: spec.x,
            y: spec.y
        )
    }
}
