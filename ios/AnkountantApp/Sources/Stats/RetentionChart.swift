import SwiftUI
import AnkountantTheme
import AnkiProto

struct RetentionChart: View {
    let trueRetention: Anki_Stats_GraphsResponse.TrueRetentionStats
    @Environment(\.palette) private var palette

    private struct RetentionRow: Identifiable {
        let id: String
        let label: String
        let youngRate: Double?
        let matureRate: Double?
        let total: Int
    }

    private var rows: [RetentionRow] {
        func row(_ label: String, _ r: Anki_Stats_GraphsResponse.TrueRetentionStats.TrueRetention) -> RetentionRow {
            let youngTotal = r.youngPassed + r.youngFailed
            let matureTotal = r.maturePassed + r.matureFailed
            let youngRate = youngTotal > 0 ? Double(r.youngPassed) / Double(youngTotal) : nil
            let matureRate = matureTotal > 0 ? Double(r.maturePassed) / Double(matureTotal) : nil
            return RetentionRow(
                id: label,
                label: label,
                youngRate: youngRate,
                matureRate: matureRate,
                total: Int(youngTotal + matureTotal)
            )
        }
        return [
            row("Today", trueRetention.today),
            row("7 days", trueRetention.week),
            row("1 month", trueRetention.month),
            row("1 year", trueRetention.year),
        ].filter { $0.total > 0 }
    }

    private var monthRate: Double? {
        overallRate(trueRetention.month)
    }

    private var statusText: String {
        guard let monthRate else {
            return "Review cards to measure recall quality."
        }
        if monthRate >= 0.9 {
            return "Recall is stable across recent reviews."
        }
        if monthRate >= 0.8 {
            return "Recall is usable, but new cards should stay controlled."
        }
        return "Recall is slipping; review backlog before adding more."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                    Text("Recall Quality").ankountantFont(.bodyEmphasis)
                    Text(statusText)
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(monthRate.map(formatPercent) ?? "--")
                    .ankountantFont(.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(retentionColor(monthRate))
                    .padding(.horizontal, AnkountantSpacing.sm)
                    .padding(.vertical, AnkountantSpacing.xs)
                    .background(retentionColor(monthRate).opacity(0.12), in: Capsule())
            }

            if rows.isEmpty {
                StatsEmptyChartView(
                    title: "No retention data",
                    systemImage: "target",
                    description: "Review cards to see recall quality.",
                    height: 120
                )
            } else {
                Grid(alignment: .leading, horizontalSpacing: AnkountantSpacing.md, verticalSpacing: AnkountantSpacing.sm) {
                    GridRow {
                        header("Period")
                        header("Reviews")
                        header(StatsCardStateLabels.shortInterval)
                        header(StatsCardStateLabels.longInterval)
                    }
                    Divider()
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .ankountantFont(.caption)
                                .foregroundStyle(palette.textPrimary)
                            Text("\(row.total)")
                                .ankountantFont(.caption)
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                            retentionBadge(row.youngRate)
                            retentionBadge(row.matureRate)
                        }
                    }
                }
            }
        }
        .ankountantCard()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .ankountantFont(.captionBold)
            .foregroundStyle(palette.textSecondary)
    }

    private func retentionBadge(_ rate: Double?) -> some View {
        Text(rate.map(formatPercent) ?? "--")
            .ankountantFont(.captionBold)
            .monospacedDigit()
            .foregroundStyle(retentionColor(rate))
    }

    private func retentionColor(_ rate: Double?) -> Color {
        guard let rate else { return palette.textSecondary }
        if rate >= 0.9 { return palette.positive }
        if rate >= 0.8 { return palette.warning }
        return palette.danger
    }

    private func overallRate(_ r: Anki_Stats_GraphsResponse.TrueRetentionStats.TrueRetention) -> Double? {
        let passed = r.youngPassed + r.maturePassed
        let total = passed + r.youngFailed + r.matureFailed
        guard total > 0 else { return nil }
        return Double(passed) / Double(total)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
