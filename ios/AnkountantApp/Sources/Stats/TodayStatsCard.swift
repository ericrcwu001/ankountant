import SwiftUI
import AnkountantTheme
import AnkiProto

struct PeriodStatsCard: View {
    let period: StatsPeriod
    let today: Anki_Stats_GraphsResponse.Today
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    @Environment(\.palette) private var palette

    private var periodTitle: String {
        switch period {
        case .day: return "Today"
        case .week: return "Last 7 Days"
        case .month: return "Last Month"
        case .threeMonths: return "Last 3 Months"
        case .year: return "Last Year"
        case .all: return "All Time"
        }
    }

    private struct Aggregated {
        var total: Int = 0
        var timeMillis: UInt64 = 0
        var learn: Int = 0
        var relearn: Int = 0
        var young: Int = 0
        var mature: Int = 0
        var activeDays: Int = 0
        var spanDays: Int = 1
    }

    private var aggregated: Aggregated {
        var agg = Aggregated()
        let limit = period.days
        var earliestDay = 0
        for (dayOffset, rev) in reviews.count {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) < limit else { continue }
            let dayTotal = Int(rev.learn) + Int(rev.relearn) + Int(rev.young) + Int(rev.mature)
            guard dayTotal > 0 else { continue }
            agg.learn += Int(rev.learn)
            agg.relearn += Int(rev.relearn)
            agg.young += Int(rev.young)
            agg.mature += Int(rev.mature)
            agg.activeDays += 1
            earliestDay = min(earliestDay, day)
        }
        for (dayOffset, t) in reviews.time {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) < limit else { continue }
            agg.timeMillis += UInt64(t.learn) + UInt64(t.relearn) + UInt64(t.young) + UInt64(t.mature) + UInt64(t.filtered)
        }
        agg.total = agg.learn + agg.relearn + agg.young + agg.mature
        agg.spanDays = period == .all ? max(1, abs(earliestDay) + 1) : period.days
        return agg
    }

    private var todayAccuracy: String {
        guard today.answerCount > 0 else { return "---" }
        let pct = Int(Double(today.correctCount) / Double(today.answerCount) * 100)
        return "\(pct)%"
    }

    private var todayMatureAccuracy: String {
        guard today.matureCount > 0 else { return "---" }
        let pct = Int(Double(today.matureCorrect) / Double(today.matureCount) * 100)
        return "\(pct)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            HStack {
                Text("Study Activity")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(periodTitle)
                    .ankountantFont(.captionBold)
                    .foregroundStyle(palette.textSecondary)
                    .textCase(.uppercase)
            }

            if period == .day {
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                    statItem(title: "Reviewed", value: "\(today.answerCount)", color: palette.textPrimary)
                    statItem(title: "Study time", value: formatMillis(UInt64(today.answerMillis)), color: palette.textPrimary)
                    statItem(title: "Correct", value: todayAccuracy, color: palette.positive)
                    statItem(title: StatsCardStateLabels.longInterval, value: todayMatureAccuracy, color: palette.accent)
                }
                Divider()
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                    statBadge("New", count: today.learnCount, color: palette.stateNew)
                    statBadge("Relearn", count: today.relearnCount, color: palette.stateLearn)
                    statBadge("Review", count: today.reviewCount, color: palette.stateReview)
                    statBadge("Again", count: today.answerCount - today.correctCount, color: palette.danger)
                }
            } else {
                let agg = aggregated
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                    statItem(title: "Reviewed", value: "\(agg.total)", color: palette.textPrimary)
                    statItem(title: "Study time", value: formatMillis(agg.timeMillis), color: palette.textPrimary)
                    statItem(title: "Avg/day", value: formatDecimal(Double(agg.total) / Double(max(agg.spanDays, 1))), color: palette.accent)
                    statItem(title: "Active days", value: "\(agg.activeDays)", color: palette.textPrimary)
                }
                Divider()
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                    statBadge("New", count: UInt32(agg.learn), color: palette.stateNew)
                    statBadge("Relearn", count: UInt32(agg.relearn), color: palette.stateLearn)
                    statBadge(StatsCardStateLabels.shortInterval, count: UInt32(agg.young), color: palette.stateReview)
                    statBadge(StatsCardStateLabels.longInterval, count: UInt32(agg.mature), color: palette.accent)
                }
            }
        }
        .ankountantCard(elevated: true)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: AnkountantSpacing.md)]
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Text(value).ankountantFont(.sectionHeading).foregroundStyle(color)
            Text(title).ankountantFont(.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statBadge(_ title: String, count: UInt32, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Text("\(count)").ankountantFont(.bodyEmphasis).foregroundStyle(color)
            Text(title).ankountantFont(.micro).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatMillis(_ ms: UInt64) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func formatDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
