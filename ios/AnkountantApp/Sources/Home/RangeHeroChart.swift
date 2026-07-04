// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import Charts
import AnkountantTheme
import AnkiKit

/// The summit "range": each CPA section as a faded-navy Wilson band on a pinned
/// 0–99 CPA scale with a dashed pass line at 75. Above/below is read from the
/// point's position relative to the labeled line, reinforced by a neutral
/// triangle glyph + tabular score (never a semantic hue on the mountain).
/// Abstaining sections are simply absent from the plot (no faked height); the
/// section list below spells out their "Not enough data yet" state and owns
/// navigation + VoiceOver, so the chart is decorative.
struct RangeHeroChart: View {
    let sections: [SectionReadiness]
    @Environment(\.palette) private var palette

    private var codes: [String] { CPASection.homeOrder.map(\.code) }

    private struct Peak: Identifiable {
        let id: String
        let code: String
        let low: Double
        let high: Double
        let point: Double
        let standing: PassStanding
    }

    private var peaks: [Peak] {
        sections.compactMap { s in
            guard let band = s.band, !band.abstain else { return nil }
            return Peak(
                id: s.section.code,
                code: s.section.code,
                low: band.bandLow,
                high: band.bandHigh,
                point: band.pointEstimate,
                standing: s.standing
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            HStack {
                Text("Your range")
                    .ankountantFont(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("CPA 0–99")
                    .ankountantFont(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textSecondary)
            }
            chart
            Text("Bars show projected CPA ranges. Arrows mark whether the midpoint is above or below pass 75.")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Pass", TopoScale.passScore))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(palette.textSecondary)
                .annotation(position: .top, alignment: .trailing) {
                    Text("Pass 75")
                        .ankountantFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                }

            ForEach(peaks) { peak in
                BarMark(
                    x: .value("Section", peak.code),
                    yStart: .value("Low", peak.low),
                    yEnd: .value("High", peak.high),
                    width: .ratio(0.5)
                )
                .foregroundStyle(palette.accent.opacity(0.18))
                .cornerRadius(3)

                PointMark(
                    x: .value("Section", peak.code),
                    y: .value("Projected", peak.point)
                )
                .symbolSize(0)
                .annotation(position: .overlay) {
                    VStack(spacing: 1) {
                        Image(systemName: peak.standing == .above ? "arrowtriangle.up" : "arrowtriangle.down")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .chartYScale(domain: 0...TopoScale.domainMax)
        .chartXScale(domain: codes)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 99]) { value in
                AxisGridLine().foregroundStyle(palette.borderSubtle)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .ankountantFont(.micro)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let code = value.as(String.self) {
                        Text(code)
                            .ankountantFont(.micro)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness range across CPA sections. Use the section list below for details.")
    }
}
