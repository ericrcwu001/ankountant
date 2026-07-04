// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit

struct ReadinessScoreStrip: View {
    let scores: [ReadinessScoreSummary]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("Score signals", systemImage: "chart.bar.xaxis")
                    .labelStyle(.titleAndIcon)
                    .ankountantFont(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: AnkountantSpacing.sm)
                Text("Point + range")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: AnkountantSpacing.sm) {
                ForEach(scores) { score in
                    ReadinessScoreTile(score: score)
                }
            }
        }
        .padding(AnkountantSpacing.md)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
