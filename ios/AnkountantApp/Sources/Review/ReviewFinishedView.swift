import SwiftUI
import AnkountantTheme

struct ReviewFinishedView: View {
    let summary: ReviewCompletionSummary
    let onDone: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if summary.hasReviews {
                completedView
            } else {
                caughtUpView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caughtUpView: some View {
        ContentUnavailableView {
            Label(summary.title, systemImage: summary.systemImage)
        } description: {
            Text(summary.message)
        } actions: {
            Button("Done", action: onDone)
                .buttonStyle(AnkountantPrimaryButtonStyle())
        }
    }

    private var completedView: some View {
        VStack(spacing: AnkountantSpacing.lg) {
            Spacer()
            Image(systemName: summary.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(summary.title)
                .ankountantFont(.sectionHeading)
                .foregroundStyle(palette.textPrimary)
            Text(summary.message)
                .ankountantFont(.body)
                .foregroundStyle(palette.textSecondary)
            if let accuracyText = summary.accuracyText {
                Text(accuracyText)
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(AnkountantPrimaryButtonStyle())
                .padding()
        }
    }
}
