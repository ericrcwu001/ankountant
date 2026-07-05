import SwiftUI
import AnkountantTheme
import AnkiProto

struct ProgressOverviewCard: View {
    let graphs: Anki_Stats_GraphsResponse
    @Environment(\.palette) private var palette

    private var counts: Anki_Stats_GraphsResponse.CardCounts.Counts {
        graphs.cardCounts.excludingInactive
    }

    private var activeCards: UInt32 {
        counts.newCards + counts.learn + counts.relearn + counts.young + counts.mature
    }

    private var masteredFraction: Double {
        guard activeCards > 0 else { return 0 }
        return Double(counts.mature) / Double(activeCards)
    }

    private var retentionFraction: Double? {
        let retention = graphs.trueRetention.month
        let passed = retention.youngPassed + retention.maturePassed
        let total = passed + retention.youngFailed + retention.matureFailed
        guard total > 0 else { return nil }
        return Double(passed) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.lg) {
            HStack(alignment: .center, spacing: AnkountantSpacing.lg) {
                ProgressRing(fraction: masteredFraction)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                    Text("Progress")
                        .ankountantFont(.displayHero)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(Int((masteredFraction * 100).rounded()))% mastered")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(formatNumber(activeCards)) active cards")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ProgressOverviewRow(
                    icon: "checkmark.seal",
                    title: "Cards mastered",
                    value: formatNumber(counts.mature)
                )
                Divider()
                ProgressOverviewRow(
                    icon: "target",
                    title: "Month retention",
                    value: retentionFraction.map(formatPercent) ?? "--"
                )
                Divider()
                ProgressOverviewRow(
                    icon: "clock.arrow.circlepath",
                    title: "Reviewed today",
                    value: formatNumber(graphs.today.answerCount)
                )
                Divider()
                ProgressOverviewRow(
                    icon: "calendar",
                    title: "Daily load",
                    value: formatNumber(graphs.futureDue.dailyLoad)
                )
            }
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            }
        }
        .padding(AnkountantSpacing.lg)
        .background(
            LinearGradient(
                colors: [palette.surfaceElevated, palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        }
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatNumber(_ value: UInt32) -> String {
        value.formatted(.number)
    }
}
