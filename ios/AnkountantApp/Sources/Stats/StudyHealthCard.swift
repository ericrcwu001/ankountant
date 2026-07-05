import SwiftUI
import AnkountantTheme
import AnkiProto

struct StudyHealthCard: View {
    let graphs: Anki_Stats_GraphsResponse
    @Environment(\.palette) private var palette

    private var counts: Anki_Stats_GraphsResponse.CardCounts.Counts {
        graphs.cardCounts.excludingInactive
    }

    private var activeCards: UInt32 {
        counts.newCards + counts.learn + counts.relearn + counts.young + counts.mature
    }

    private var learningCards: UInt32 {
        counts.learn + counts.relearn
    }

    private var matureFraction: Double? {
        guard activeCards > 0 else { return nil }
        return Double(counts.mature) / Double(activeCards)
    }

    private var monthRetentionFraction: Double? {
        let retention = graphs.trueRetention.month
        let passed = retention.youngPassed + retention.maturePassed
        let total = passed + retention.youngFailed + retention.matureFailed
        guard total > 0 else { return nil }
        return Double(passed) / Double(total)
    }

    private var fragileCards: UInt32 {
        graphs.retrievability.retrievability.reduce(UInt32.zero) { partial, entry in
            entry.key < 70 ? partial + entry.value : partial
        }
    }

    private var retrievabilityCards: UInt32 {
        graphs.retrievability.retrievability.values.reduce(0, +)
    }

    private var fragileFraction: Double? {
        guard retrievabilityCards > 0 else { return nil }
        return Double(fragileCards) / Double(retrievabilityCards)
    }

    private var backlogCards: UInt32 {
        graphs.futureDue.futureDue.reduce(UInt32.zero) { partial, entry in
            entry.key < 0 ? partial + entry.value : partial
        }
    }

    private var healthSummary: String {
        if backlogCards > 0 {
            return "\(formatNumber(backlogCards)) overdue cards should come before new material."
        }
        guard let monthRetentionFraction else {
            return "Review history will turn these signals into guidance."
        }
        if monthRetentionFraction >= 0.9 {
            return "Recall is stable; keep the current study load."
        }
        if monthRetentionFraction >= 0.8 {
            return "Recall is workable; watch new-card pressure."
        }
        return "Recall is slipping; clear reviews before adding more."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text("Study Health")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text(healthSummary)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                healthRow(
                    icon: "target",
                    title: "Recall",
                    value: monthRetentionFraction.map(formatPercent) ?? "--",
                    detail: "Month retention",
                    tone: retentionTone
                )
                Divider()
                healthRow(
                    icon: "exclamationmark.triangle",
                    title: "Risk",
                    value: retrievabilityCards > 0 ? formatNumber(fragileCards) : "--",
                    detail: fragileDetail,
                    tone: fragileTone
                )
                Divider()
                healthRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Learning queue",
                    value: formatNumber(learningCards),
                    detail: "Learning and relearning cards",
                    tone: learningTone
                )
                Divider()
                healthRow(
                    icon: "checkmark.seal",
                    title: "Mature mix",
                    value: matureFraction.map(formatPercent) ?? "--",
                    detail: "Active cards with long spacing",
                    tone: matureTone
                )
            }
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            }
        }
        .ankountantCard()
    }

    private var fragileDetail: String {
        guard let fragileFraction else {
            return "Review more cards to estimate recall risk"
        }
        return "\(formatPercent(fragileFraction)) below 70% predicted recall"
    }

    private var retentionTone: AnkountantStatusTone {
        guard let monthRetentionFraction else { return .neutral }
        if monthRetentionFraction >= 0.9 { return .positive }
        if monthRetentionFraction >= 0.8 { return .warning }
        return .danger
    }

    private var fragileTone: AnkountantStatusTone {
        guard let fragileFraction else { return .neutral }
        if fragileFraction <= 0.1 { return .positive }
        if fragileFraction <= 0.25 { return .warning }
        return .danger
    }

    private var learningTone: AnkountantStatusTone {
        if learningCards == 0 { return .positive }
        if learningCards <= graphs.futureDue.dailyLoad { return .warning }
        return .danger
    }

    private var matureTone: AnkountantStatusTone {
        guard let matureFraction else { return .neutral }
        if matureFraction >= 0.5 { return .positive }
        if matureFraction >= 0.25 { return .warning }
        return .neutral
    }

    private func healthRow(
        icon: String,
        title: String,
        value: String,
        detail: String,
        tone: AnkountantStatusTone
    ) -> some View {
        HStack(spacing: AnkountantSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.foregroundColor(palette))
                .frame(width: 34, height: 34)
                .background(tone.backgroundColor(palette), in: RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                Text(title)
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            Text(value)
                .ankountantFont(.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(tone.foregroundColor(palette))
        }
        .padding(.horizontal, AnkountantSpacing.md)
        .padding(.vertical, AnkountantSpacing.sm)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatNumber(_ value: UInt32) -> String {
        value.formatted(.number)
    }
}
