import SwiftUI
import AnkiKit
import AnkountantTheme

struct ConfidenceGateView: View {
    @Binding var committed: ConfidenceLevel?
    var onCommit: (ConfidenceLevel) -> Void = { _ in }

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("How confident are you? (pick before revealing)")
                .ankountantFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)

            VStack(spacing: AnkountantSpacing.sm) {
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
            HStack(spacing: AnkountantSpacing.md) {
                Image(systemName: icon(for: level))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? palette.onAccent : palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        selected ? palette.accent : palette.accent.opacity(0.1),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.rawValue)
                        .ankountantFont(.bodyEmphasis)
                    Text(subtitle(for: level))
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .foregroundStyle(selected ? palette.accent : palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AnkountantSpacing.md)
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

    private func icon(for level: ConfidenceLevel) -> String {
        switch level {
        case .guess: "questionmark"
        case .unsure: "face.dashed"
        case .confident: "checkmark"
        }
    }

    private func subtitle(for level: ConfidenceLevel) -> String {
        switch level {
        case .guess: "I'm guessing"
        case .unsure: "I'm not certain"
        case .confident: "I'm pretty sure"
        }
    }
}
