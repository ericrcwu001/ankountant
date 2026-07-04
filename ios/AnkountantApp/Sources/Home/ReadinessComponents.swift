// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit

/// Shared readiness UI, extracted from HomeView so the FAR hero and every
/// SectionDetail render identical semantics. Constraint 2 (per-topic Memory /
/// Performance with Wilson ranges) lives in `TopicBreakdownList`.

/// The abstain-aware CPA readiness band (0–99, pass 75). Navy is spent here — the
/// one sanctioned "readiness band" value color.
struct ReadinessBandView: View {
    let band: ReadinessBand
    var topics: [TopicScoreModel] = []
    @Environment(\.palette) private var palette

    var body: some View {
        if band.abstain {
            VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
                AbstainView(reason: band.reason, coverage: band.coverage)
                ReadinessEvidencePanel(evidence: readinessEvidence(band: band, topics: topics))
            }
        } else {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AnkountantSpacing.sm) {
                    Text(readinessBandLabel(band))
                        .ankountantFont(.sectionHeading)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                    Text("\(band.confidence) confidence")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                ReadinessBandTrack(band: band)
                Text("\(formatPercent(band.coverage)) of exam covered · CPA 0–99, pass 75 (exam-day projection)")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                ForEach(band.reasons.prefix(3), id: \.self) { reason in
                    Text("• \(reason)")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("Rough exam-day projection on the CPA 0–99 scale (pass 75); the band is the confidence range, not an official AICPA score.")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textTertiary)
                ReadinessEvidencePanel(evidence: readinessEvidence(band: band, topics: topics))
            }
        }
    }
}

/// Faded-navy Wilson band on the 0–99 track with a neutral pass tick at 75.
private struct ReadinessBandTrack: View {
    let band: ReadinessBand
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = TopoScale.height(forScore: band.bandLow) * w
            let hi = TopoScale.height(forScore: band.bandHigh) * w
            let passX = TopoScale.passHeight * w
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceInset)
                Capsule()
                    .fill(palette.accent.opacity(0.6))
                    .frame(width: max(2, hi - lo))
                    .offset(x: lo)
                Rectangle()
                    .fill(palette.textSecondary)
                    .frame(width: 2)
                    .offset(x: passX - 1)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// First-class abstain state (dashed square icon + label + optional coverage).
struct AbstainView: View {
    let reason: String
    var coverage: Double?
    @Environment(\.palette) private var palette

    init(reason: String, coverage: Double? = nil) {
        self.reason = reason
        self.coverage = coverage
    }

    var body: some View {
        HStack(alignment: .top, spacing: AnkountantSpacing.sm) {
            Image(systemName: "square.dashed")
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                Text("Not enough data yet")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text(reason.isEmpty ? "Keep studying to project a score." : "\(reason).")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                if let coverage {
                    Text("\(formatPercent(coverage)) of exam topics covered")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// Per-confusion-set Memory / Performance breakdown (Constraint 2).
struct TopicBreakdownList: View {
    let summary: ReadinessSummary
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("Topic breakdown")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            if summary.topics.isEmpty {
                Text("No topics defined for this section yet.")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                if summary.band.abstain {
                    Text("Per-topic signal — the overall projection stays withheld until there's enough data.")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(Array(summary.topics.enumerated()), id: \.element.id) { index, topic in
                    if index > 0 {
                        Rectangle().fill(palette.borderSubtle).frame(height: 1)
                    }
                    TopicScoreRow(topic: topic)
                }
            }
        }
    }
}

struct ReadinessEvidencePanel: View {
    let evidence: ReadinessEvidence
    var compact = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? AnkountantSpacing.sm : AnkountantSpacing.md) {
            evidenceSection(
                title: "Evidence behind this range",
                systemImage: "checklist",
                lines: evidence.evidenceLines
            )
            evidenceSection(
                title: "Last updated",
                systemImage: "clock",
                lines: [evidence.updatedAtLine]
            )
            evidenceSection(
                title: "Still missing",
                systemImage: "tray",
                lines: evidence.missingData
            )
            evidenceSection(
                title: "Next best study action",
                systemImage: "arrow.forward.circle",
                lines: [evidence.nextAction],
                emphasized: true
            )
            evidenceSection(
                title: "Past prediction accuracy",
                systemImage: "chart.xyaxis.line",
                lines: [evidence.calibrationStatus, evidence.giveUpRule]
            )
        }
        .padding(.top, compact ? 0 : AnkountantSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    private func evidenceSection(
        title: String,
        systemImage: String,
        lines: [String],
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Label(title, systemImage: systemImage)
                .ankountantFont(.micro)
                .textCase(.uppercase)
                .foregroundStyle(palette.textSecondary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .ankountantFont(emphasized ? .bodyEmphasis : .caption)
                    .foregroundStyle(emphasized ? palette.textPrimary : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One confusion set: Memory + Performance as neutral position meters with their
/// Wilson range, plus the gap (warning icon+label when large).
struct TopicScoreRow: View {
    let topic: TopicScoreModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.displayName)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !topic.gapAvailable {
                    Text("Gap insufficient")
                        .ankountantFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                } else if topic.gapWarning {
                    Label("Gap \(formatPercent(topic.gap))", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .ankountantStatusBadge(.warning)
                } else {
                    Text("Gap \(formatPercent(topic.gap))")
                        .ankountantFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
            metric("Memory", insufficient: topic.memoryInsufficient,
                   value: topic.memory, low: topic.memoryLow, high: topic.memoryHigh)
            metric("Performance", insufficient: topic.performanceInsufficient,
                   value: topic.performance, low: topic.performanceLow, high: topic.performanceHigh)
        }
        .padding(.vertical, AnkountantSpacing.xs)
    }

    @ViewBuilder
    private func metric(_ label: String, insufficient: Bool, value: Double, low: Double, high: Double) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(scoreWithRange(insufficient ? nil : value, low: low, high: high))
                    .ankountantFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(insufficient ? palette.textTertiary : palette.textPrimary)
            }
            PositionMeter(fraction: insufficient ? nil : value)
        }
    }
}

/// Neutral position-on-a-common-scale meter (position beats gauges; scores are
/// never painted in semantic hues).
private struct PositionMeter: View {
    let fraction: Double?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceInset)
                if let fraction {
                    Capsule()
                        .fill(palette.textTertiary)
                        .frame(width: max(2, min(max(fraction, 0), 1) * geo.size.width))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
