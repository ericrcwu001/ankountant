import SwiftUI
import AnkiKit
import AnkountantTheme

struct LearningFeedbackPanel: View {
    let state: LearningFeedbackPanelState

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Label("Learning feedback", systemImage: "sparkles")
                .ankountantFont(.micro)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            switch state {
            case .loading:
                LearningFeedbackLoadingView()
            case let .content(feedback, sources):
                LearningFeedbackContentView(feedback: feedback, sources: sources)
            case let .error(message):
                LearningFeedbackErrorView(message: message)
            }
        }
        .padding(AnkountantSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct LearningFeedbackLoadingView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: AnkountantSpacing.md) {
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel("Generating learning feedback")
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text("Generating grounded feedback")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text("Using the revealed answer and cited sources for this attempt.")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LearningFeedbackContentView: View {
    let feedback: LearningFeedback
    let sources: [LearningFeedbackSource]

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            if !feedback.title.isEmpty {
                Text(feedback.title)
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LearningFeedbackSectionView(title: "Why this was wrong", systemImage: "xmark.circle", text: feedback.whyWrong)
            LearningFeedbackSectionView(title: "Correct approach", systemImage: "checkmark.circle", text: feedback.correctApproach)
            LearningFeedbackSectionView(title: "Remember", systemImage: "pin", text: feedback.remember)

            if !feedback.sourceIds.isEmpty {
                VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                    Label("Cited sources", systemImage: "quote.bubble")
                        .ankountantFont(.captionBold)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(feedback.sourceIds, id: \.self) { sourceId in
                        Text(sourceLabel(for: sourceId))
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Cited source \(sourceLabel(for: sourceId))")
                    }
                }
            }
        }
    }

    private func sourceLabel(for sourceId: String) -> String {
        guard let source = sources.first(where: { $0.id == sourceId }) else {
            return sourceId
        }
        return "\(source.title) · \(source.id)"
    }
}

private struct LearningFeedbackSectionView: View {
    let title: String
    let systemImage: String
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Label(title, systemImage: systemImage)
                    .ankountantFont(.captionBold)
                    .foregroundStyle(palette.textPrimary)
                Text(text)
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct LearningFeedbackErrorView: View {
    let message: String

    var body: some View {
        AnkountantStatusMessageView(
            title: "Feedback unavailable",
            message: message,
            systemImage: "exclamationmark.triangle",
            tone: .warning
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AnkountantSpacing.sm)
        .ankountantStatusPanel(.warning)
    }
}
