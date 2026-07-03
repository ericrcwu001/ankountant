// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit

/// One section row under the summit range: code + name, above/below-pass standing
/// (position + neutral glyph + text — never color alone), and the projected score
/// (or a dash when unproven). Wrapped by a `NavigationLink(value: CPASection)` in
/// HomeView, so tapping drills into the section detail.
struct SectionReadinessRow: View {
    let section: SectionReadiness
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AnkountantSpacing.md) {
            Text(section.section.code)
                .ankountantFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                Text(section.section.displayName)
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textPrimary)
                standingLine
            }

            Spacer(minLength: AnkountantSpacing.sm)
            readout

            Image(systemName: "chevron.right")
                .ankountantFont(.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var standingLine: some View {
        switch section.standing {
        case .above:
            Label("Above pass line", systemImage: "arrowtriangle.up")
                .labelStyle(.titleAndIcon)
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
        case .below:
            Label("Below pass line", systemImage: "arrowtriangle.down")
                .labelStyle(.titleAndIcon)
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
        case .unproven:
            Text("Not enough data yet")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let band = section.band, !band.abstain {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(passDisplayScore(band.pointEstimate, standing: section.standing))")
                    .ankountantFont(.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("proj")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        } else {
            Text("—")
                .ankountantFont(.cardTitle)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var accessibilityText: String {
        let name = section.section.displayName
        if let band = section.band, !band.abstain {
            let score = passDisplayScore(band.pointEstimate, standing: section.standing)
            let where_ = section.standing == .above ? "above" : "below"
            return "\(name), projected \(score), \(where_) the pass line of 75. \(band.confidence) confidence."
        }
        return "\(name), not enough data yet."
    }
}
