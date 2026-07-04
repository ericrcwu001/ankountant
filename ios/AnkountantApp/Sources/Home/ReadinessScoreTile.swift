// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit

struct ReadinessScoreTile: View {
    let score: ReadinessScoreSummary
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Text(score.label.uppercased())
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(score.valueText)
                .ankountantFont(.cardTitle)
                .monospacedDigit()
                .foregroundStyle(score.available ? palette.textPrimary : palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(score.rangeText)
                .ankountantFont(.caption)
                .monospacedDigit()
                .foregroundStyle(score.available ? palette.textSecondary : palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            meter
            Text(score.detailText)
                .ankountantFont(.micro)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .padding(AnkountantSpacing.sm)
        .background(palette.surfaceInset, in: RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.borderSubtle)
                if let fraction = score.fraction {
                    Capsule()
                        .fill(palette.accent.opacity(0.7))
                        .frame(width: max(2, min(max(fraction, 0), 1) * geo.size.width))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if score.available {
            return "\(score.label), \(score.valueText), range \(score.rangeText), \(score.detailText)"
        }
        return "\(score.label), not available, \(score.rangeText), \(score.detailText)"
    }
}
