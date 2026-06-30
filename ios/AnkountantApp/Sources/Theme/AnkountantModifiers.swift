import SwiftUI
import AnkountantTheme

// MARK: - Shadow

extension View {
    func ankountantShadow() -> some View {
        shadow(color: Color.black.opacity(0.22), radius: 15, x: 3, y: 5)
    }
}

// MARK: - Card Modifier

struct AnkountantCardModifier: ViewModifier {
    @Environment(\.palette) private var palette
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AnkountantSpacing.lg)
            .background(
                elevated ? palette.surfaceElevated : palette.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.border.opacity(elevated ? 0.32 : 0.18), lineWidth: 1)
            )
            .modifier(ConditionalShadow(enabled: elevated))
    }
}

private struct ConditionalShadow: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.ankountantShadow()
        } else {
            content
        }
    }
}

extension View {
    func ankountantCard(elevated: Bool = false) -> some View {
        modifier(AnkountantCardModifier(elevated: elevated))
    }
}

// MARK: - Section Background

extension View {
    func ankountantSectionBackground() -> some View {
        modifier(AnkountantSectionBackgroundModifier())
    }
}

private struct AnkountantSectionBackgroundModifier: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.background(palette.background)
    }
}

// MARK: - Button Styles

struct AnkountantPrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ankountantFont(.body)
            .foregroundStyle(.white)
            .padding(.vertical, AnkountantSpacing.sm)
            .padding(.horizontal, 20)
            .background(palette.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AnkountantSecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ankountantFont(.body)
            .foregroundStyle(palette.accent)
            .padding(.vertical, AnkountantSpacing.sm)
            .padding(.horizontal, 20)
            .background(
                Capsule().stroke(palette.accent, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Status Tone

enum AnkountantStatusTone {
    case accent
    case positive
    case warning
    case danger
    case info
    case neutral

    fileprivate func foregroundColor(_ palette: Palette) -> Color {
        switch self {
        case .accent:   return palette.accent
        case .positive: return palette.positive
        case .warning:  return palette.warning
        case .danger:   return palette.danger
        case .info:     return palette.info
        case .neutral:  return palette.textSecondary
        }
    }

    fileprivate func backgroundColor(_ palette: Palette) -> Color {
        switch self {
        case .accent:   return palette.accent.opacity(0.12)
        case .positive: return palette.positive.opacity(0.14)
        case .warning:  return palette.warning.opacity(0.16)
        case .danger:   return palette.danger.opacity(0.14)
        case .info:     return palette.info.opacity(0.14)
        case .neutral:  return palette.surface
        }
    }

    fileprivate func borderColor(_ palette: Palette) -> Color {
        switch self {
        case .neutral: return palette.border.opacity(0.32)
        default:       return foregroundColor(palette).opacity(0.28)
        }
    }

    fileprivate func toolbarForegroundColor(_ palette: Palette) -> Color {
        switch self {
        case .neutral: return palette.textPrimary
        default:       return foregroundColor(palette)
        }
    }
}

// MARK: - Status Message (centered Label + caption, used for empty states)

struct AnkountantStatusMessageView: View {
    @Environment(\.palette) private var palette
    let title: String
    let message: String
    let systemImage: String
    let tone: AnkountantStatusTone

    var body: some View {
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

extension View {
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.border.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Capsule().stroke(palette.border.opacity(0.28), lineWidth: 1)
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
    let tone: AnkountantStatusTone
    let elevated: Bool
    func body(content: Content) -> some View {
        content
            .padding(AnkountantSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.surfaceElevated)
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone.backgroundColor(palette))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tone.borderColor(palette), lineWidth: 1)
            )
            .modifier(_ConditionalShadow(enabled: elevated))
    }
}

private struct _ConditionalShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.ankountantShadow()
        } else {
            content
        }
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
