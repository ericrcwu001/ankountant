import SwiftUI
import AnkiKit
import AnkountantTheme

/// B1 confidence gate — the pre-reveal commitment (mirrors the desktop
/// ts/lib/components/ConfidenceGate.svelte). Three discrete, equal-weight levels
/// (Guess / Unsure / Confident) with no default selection. Commit is once-only:
/// after the first pick the other levels disable and the choice is marked with
/// brand chrome plus a selected trait — never colour alone.
struct ConfidenceGateView: View {
    @Binding var committed: ConfidenceLevel?
    var onCommit: (ConfidenceLevel) -> Void = { _ in }

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("How confident are you? (pick before revealing)")
                .ankountantFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: AnkountantSpacing.sm) {
                ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                    levelButton(level)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Confidence")
        }
    }

    private func levelButton(_ level: ConfidenceLevel) -> some View {
        let selected = committed == level
        return Button {
            choose(level)
        } label: {
            Text(level.rawValue)
                .ankountantFont(selected ? .bodyEmphasis : .body)
                .foregroundStyle(selected ? palette.accent : palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                        .fill(selected ? palette.accent.opacity(0.12) : palette.surfaceInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                        .stroke(selected ? palette.accent : palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(committed != nil && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ level: ConfidenceLevel) {
        guard committed == nil else { return }
        committed = level
        onCommit(level)
    }
}
