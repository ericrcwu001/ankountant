// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit

struct ReadinessScoreStrip: View {
    let scores: [ReadinessScoreSummary]
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            heading
            scoreTiles
        }
        .padding(AnkountantSpacing.md)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var heading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                title
                subtitle
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: AnkountantSpacing.sm)
                subtitle
            }
        }
    }

    private var title: some View {
        Label("Score signals", systemImage: "chart.bar.xaxis")
            .labelStyle(.titleAndIcon)
            .ankountantFont(.micro)
            .textCase(.uppercase)
            .foregroundStyle(palette.textSecondary)
    }

    private var subtitle: some View {
        Text("Confidence ranges")
            .ankountantFont(.micro)
            .foregroundStyle(palette.textTertiary)
    }

    @ViewBuilder
    private var scoreTiles: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
                scoreTileRows
            }
        } else {
            LazyVGrid(columns: scoreColumns, alignment: .leading, spacing: AnkountantSpacing.sm) {
                scoreTileRows
            }
        }
    }

    private var scoreTileRows: some View {
        ForEach(scores) { score in
            ReadinessScoreTile(score: score)
        }
    }

    private var scoreColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: AnkountantSpacing.sm, alignment: .top)]
    }
}
