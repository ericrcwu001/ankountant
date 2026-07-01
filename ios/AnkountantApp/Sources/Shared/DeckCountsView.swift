import SwiftUI
import AnkiKit
import AnkountantTheme

struct DeckCountsView: View {
    @Environment(\.palette) private var palette
    let counts: DeckCounts

    var body: some View {
        HStack(spacing: 8) {
            if counts.newCount > 0 {
                countBadge(counts.newCount, color: palette.stateNew)
            }
            if counts.learnCount > 0 {
                countBadge(counts.learnCount, color: palette.stateLearn)
            }
            if counts.reviewCount > 0 {
                countBadge(counts.reviewCount, color: palette.stateReview)
            }
            if counts.total == 0 {
                Text("\u{2713}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .monospacedDigit()
    }
}
