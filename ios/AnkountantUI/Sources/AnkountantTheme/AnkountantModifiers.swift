public import SwiftUI

// MARK: - Elevation shadow (theme-aware, replaces the old hardcoded drop)

public extension View {
    /// Legacy convenience: apply the card-level (e2) elevation using the
    /// environment palette + scheme. Prefer `ankountantElevation(_:palette:scheme:)`
    /// for explicit control.
    func ankountantShadow() -> some View {
        modifier(AnkountantDefaultShadowModifier())
    }
}

private struct AnkountantDefaultShadowModifier: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.ankountantElevation(.e2, palette: palette, scheme: scheme)
    }
}

// MARK: - Card Modifier

public struct AnkountantCardModifier: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var elevated: Bool = false

    public init(elevated: Bool = false) {
        self.elevated = elevated
    }

    public func body(content: Content) -> some View {
        content
            .padding(AnkountantSpacing.lg)
            .background(
                elevated ? palette.surfaceElevated : palette.surface,
                in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(elevated ? palette.border : palette.borderSubtle, lineWidth: 1)
            )
            .modifier(ConditionalElevation(enabled: elevated, palette: palette, scheme: scheme))
    }
}

private struct ConditionalElevation: ViewModifier {
    let enabled: Bool
    let palette: Palette
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        if enabled {
            content.ankountantElevation(.e2, palette: palette, scheme: scheme)
        } else {
            content
        }
    }
}

public extension View {
    func ankountantCard(elevated: Bool = false) -> some View {
        modifier(AnkountantCardModifier(elevated: elevated))
    }
}

// MARK: - Section Background

public extension View {
    func ankountantSectionBackground() -> some View {
        modifier(AnkountantSectionBackgroundModifier())
    }

    func ankountantTabBarClearance(_ height: CGFloat = AnkountantSpacing.xxxl) -> some View {
        safeAreaPadding(.bottom, height)
    }
}

private struct AnkountantSectionBackgroundModifier: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.background(palette.background)
    }
}

// MARK: - Button Styles (8px rounded-rect controls; pills reserved for chips)

public struct AnkountantPrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ankountantFont(.bodyEmphasis)
            .foregroundStyle(palette.onAccent)
            .padding(.vertical, AnkountantSpacing.sm)
            .padding(.horizontal, 20)
            .background(
                palette.accentFill,
                in: RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

public struct AnkountantSecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ankountantFont(.bodyEmphasis)
            .foregroundStyle(palette.accent)
            .padding(.vertical, AnkountantSpacing.sm)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .stroke(palette.accent, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Status Tone

public enum AnkountantStatusTone: Sendable {
    case accent
    case positive
    case warning
    case danger
    case info
    case neutral

    public func foregroundColor(_ palette: Palette) -> Color {
        switch self {
        case .accent:   return palette.accent
        case .positive: return palette.positive
        case .warning:  return palette.warning
        case .danger:   return palette.danger
        case .info:     return palette.info
        case .neutral:  return palette.textSecondary
        }
    }

    public func backgroundColor(_ palette: Palette) -> Color {
        switch self {
        case .accent:   return palette.accent.opacity(0.12)
        case .positive: return palette.positive.opacity(0.14)
        case .warning:  return palette.warning.opacity(0.16)
        case .danger:   return palette.danger.opacity(0.14)
        case .info:     return palette.info.opacity(0.14)
        case .neutral:  return palette.surface
        }
    }

    public func borderColor(_ palette: Palette) -> Color {
        switch self {
        case .neutral: return palette.border
        default:       return foregroundColor(palette).opacity(0.28)
        }
    }

    public func toolbarForegroundColor(_ palette: Palette) -> Color {
        switch self {
        case .neutral: return palette.textPrimary
        default:       return foregroundColor(palette)
        }
    }
}

// MARK: - Status Message (centered Label + caption, used for empty states)

public struct AnkountantStatusMessageView: View {
    @Environment(\.palette) private var palette
    let title: String
    let message: String
    let systemImage: String
    let tone: AnkountantStatusTone

    public init(title: String, message: String, systemImage: String, tone: AnkountantStatusTone) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: AnkountantSpacing.md) {
            Label(title, systemImage: systemImage)
                .ankountantFont(.bodyEmphasis)
                .foregroundStyle(tone.foregroundColor(palette))

            Text(message)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, AnkountantSpacing.lg)
    }
}

// MARK: - Toolbar / Capsule / Status modifiers

public extension View {
    func ankountantToolbarIconButton(size: CGFloat = 32) -> some View {
        modifier(AnkountantToolbarIconButtonModifier(size: size))
    }

    func ankountantToolbarTextButton(tone: AnkountantStatusTone = .accent) -> some View {
        modifier(AnkountantToolbarTextButtonModifier(tone: tone))
    }

    func ankountantCapsuleControl(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 6) -> some View {
        modifier(AnkountantCapsuleControlModifier(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding))
    }

    func ankountantStatusBadge(_ tone: AnkountantStatusTone, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 4) -> some View {
        modifier(AnkountantStatusBadgeModifier(tone: tone, horizontalPadding: horizontalPadding, verticalPadding: verticalPadding))
    }

    func ankountantStatusPanel(_ tone: AnkountantStatusTone, elevated: Bool = false) -> some View {
        modifier(AnkountantStatusPanelModifier(tone: tone, elevated: elevated))
    }

    func ankountantSegmentedPicker() -> some View {
        pickerStyle(.segmented)
    }

    func ankountantStatusText(_ tone: AnkountantStatusTone, font: AnkountantFont = .captionBold) -> some View {
        modifier(AnkountantStatusTextModifier(tone: tone, font: font))
    }
}

private struct AnkountantToolbarIconButtonModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let size: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .foregroundStyle(palette.textPrimary)
            .background(palette.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous))
    }
}

private struct AnkountantToolbarTextButtonModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let tone: AnkountantStatusTone
    func body(content: Content) -> some View {
        content
            .tint(tone.toolbarForegroundColor(palette))
            .foregroundStyle(tone.toolbarForegroundColor(palette))
    }
}

private struct AnkountantCapsuleControlModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(palette.surfaceElevated)
            .overlay(
                Capsule().stroke(palette.border, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct AnkountantStatusBadgeModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let tone: AnkountantStatusTone
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    func body(content: Content) -> some View {
        content
            .ankountantFont(.captionBold)
            .foregroundStyle(tone.foregroundColor(palette))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.backgroundColor(palette))
            .overlay(
                Capsule().stroke(tone.borderColor(palette), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct AnkountantStatusPanelModifier: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    let tone: AnkountantStatusTone
    let elevated: Bool
    func body(content: Content) -> some View {
        content
            .padding(AnkountantSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                    .fill(palette.surfaceElevated)
            )
            .background(
                RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                    .fill(tone.backgroundColor(palette))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                    .stroke(tone.borderColor(palette), lineWidth: 1)
            )
            .modifier(ConditionalElevation(enabled: elevated, palette: palette, scheme: scheme))
    }
}

private struct AnkountantStatusTextModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let tone: AnkountantStatusTone
    let font: AnkountantFont
    func body(content: Content) -> some View {
        content
            .ankountantFont(font)
            .foregroundStyle(tone.foregroundColor(palette))
    }
}
