public import SwiftUI

/// A `ShapeStyle` that resolves a palette role from the environment, so views
/// can write `.foregroundStyle(.textPrimary)` / `.background(.surface)` instead
/// of threading `@Environment(\.palette)` everywhere (design-system.md §7).
public struct PaletteShapeStyle: ShapeStyle {
    public enum Role: Sendable {
        case background, surface, surfaceElevated, surfaceInset
        case borderSubtle, border, borderStrong
        case textPrimary, textSecondary, textTertiary, textDisabled
        case accent, accentFill, accentHover, link, onAccent
        case positive, warning, danger, info
        case stateNew, stateLearn, stateReview, stateBuried
    }

    let role: Role

    public func resolve(in environment: EnvironmentValues) -> Color {
        let p = environment.palette
        switch role {
        case .background:      return p.background
        case .surface:         return p.surface
        case .surfaceElevated: return p.surfaceElevated
        case .surfaceInset:    return p.surfaceInset
        case .borderSubtle:    return p.borderSubtle
        case .border:          return p.border
        case .borderStrong:    return p.borderStrong
        case .textPrimary:     return p.textPrimary
        case .textSecondary:   return p.textSecondary
        case .textTertiary:    return p.textTertiary
        case .textDisabled:    return p.textDisabled
        case .accent:          return p.accent
        case .accentFill:      return p.accentFill
        case .accentHover:     return p.accentHover
        case .link:            return p.link
        case .onAccent:        return p.onAccent
        case .positive:        return p.positive
        case .warning:         return p.warning
        case .danger:          return p.danger
        case .info:            return p.info
        case .stateNew:        return p.stateNew
        case .stateLearn:      return p.stateLearn
        case .stateReview:     return p.stateReview
        case .stateBuried:     return p.stateBuried
        }
    }
}

public extension ShapeStyle where Self == PaletteShapeStyle {
    static var background: PaletteShapeStyle { .init(role: .background) }
    static var surface: PaletteShapeStyle { .init(role: .surface) }
    static var surfaceElevated: PaletteShapeStyle { .init(role: .surfaceElevated) }
    static var surfaceInset: PaletteShapeStyle { .init(role: .surfaceInset) }
    static var borderSubtle: PaletteShapeStyle { .init(role: .borderSubtle) }
    static var paletteBorder: PaletteShapeStyle { .init(role: .border) }
    static var borderStrong: PaletteShapeStyle { .init(role: .borderStrong) }
    static var textPrimary: PaletteShapeStyle { .init(role: .textPrimary) }
    static var textSecondary: PaletteShapeStyle { .init(role: .textSecondary) }
    static var textTertiary: PaletteShapeStyle { .init(role: .textTertiary) }
    static var textDisabled: PaletteShapeStyle { .init(role: .textDisabled) }
    static var accent: PaletteShapeStyle { .init(role: .accent) }
    static var accentFill: PaletteShapeStyle { .init(role: .accentFill) }
    static var accentHover: PaletteShapeStyle { .init(role: .accentHover) }
    static var link: PaletteShapeStyle { .init(role: .link) }
    static var onAccent: PaletteShapeStyle { .init(role: .onAccent) }
    static var positive: PaletteShapeStyle { .init(role: .positive) }
    static var warning: PaletteShapeStyle { .init(role: .warning) }
    static var danger: PaletteShapeStyle { .init(role: .danger) }
    static var info: PaletteShapeStyle { .init(role: .info) }
    static var stateNew: PaletteShapeStyle { .init(role: .stateNew) }
    static var stateLearn: PaletteShapeStyle { .init(role: .stateLearn) }
    static var stateReview: PaletteShapeStyle { .init(role: .stateReview) }
    static var stateBuried: PaletteShapeStyle { .init(role: .stateBuried) }
}
