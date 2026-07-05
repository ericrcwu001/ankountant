import SwiftUI
import AnkountantTheme
import Charts
import AnkiProto

struct FutureDueChart: View {
    let futureDue: Anki_Stats_GraphsResponse.FutureDue
    let period: StatsPeriod
    @Environment(\.palette) private var palette
    @State private var includeBacklog = false

    private struct Model {
        var bars: [(day: Int, count: Int)] = []
        var total = 0
        var nextSevenDays = 0
        var backlog = 0
        var tomorrow = 0
        var avgPerDay = 0.0
    }

    private func buildModel() -> Model {
        let maxDay = period.days
        var raw: [(day: Int, count: Int)] = []
        var total = 0
        var nextSevenDays = 0
        var backlog = 0
        var tomorrow = 0
        var positiveSum = 0
        var maxOffset = 1
        var hasPositive = false
        for (dayOffset, count) in futureDue.futureDue {
            let day = Int(dayOffset)
            let value = Int(count)
            if day < 0 {
                backlog += value
                if !includeBacklog { continue }
            }
            guard day < maxDay else { continue }
            raw.append((day: day, count: value))
            total += value
            if day == 1 { tomorrow += value }
            if day >= 0 {
                hasPositive = true
                positiveSum += value
                if day <= 7 { nextSevenDays += value }
                maxOffset = max(maxOffset, day)
            }
        }
        var model = Model()
        model.total = total
        model.nextSevenDays = nextSevenDays
        model.backlog = backlog
        model.tomorrow = tomorrow
        model.avgPerDay = hasPositive ? Double(positiveSum) / Double(max(maxOffset, 1)) : 0
        model.bars = StatsSeriesBinning.binned(raw)
        return model
    }

    var body: some View {
        let model = buildModel()
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text("Due Load").ankountantFont(.bodyEmphasis)
                Text(summaryText(model))
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if model.bars.isEmpty {
                StatsEmptyChartView(
                    title: "No cards due",
                    systemImage: "calendar",
                    description: model.backlog > 0 ? "Turn on backlog to include overdue cards." : "Future workload will appear after reviews are scheduled."
                )
            } else {
                Chart(model.bars, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(item.day < 0 ? palette.danger.gradient : palette.accent.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
            }

            if futureDue.haveBacklog {
                Toggle("Include Backlog", isOn: $includeBacklog)
                    .ankountantFont(.caption)
                    .tint(palette.accent)
            }

            LazyVGrid(columns: footerColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                footerItem("Next 7 days", value: formatNumber(model.nextSevenDays))
                footerItem("Avg/day", value: formatDecimal(model.avgPerDay))
                footerItem("Tomorrow", value: formatNumber(model.tomorrow))
                footerItem("Daily load", value: futureDue.dailyLoad.formatted(.number))
            }
        }
        .ankountantCard()
    }

    private var footerColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 82), spacing: AnkountantSpacing.md)]
    }

    private func summaryText(_ model: Model) -> String {
        if model.backlog > 0 && !includeBacklog {
            return "\(formatNumber(model.backlog)) overdue hidden; \(formatNumber(model.nextSevenDays)) due in the next week."
        }
        if model.backlog > 0 {
            return "\(formatNumber(model.backlog)) overdue, \(formatNumber(model.nextSevenDays)) due in the next week."
        }
        return "\(formatNumber(model.nextSevenDays)) due in the next week."
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Text(value).ankountantFont(.captionBold).monospacedDigit()
            Text(label).ankountantFont(.micro).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func formatNumber(_ value: Int) -> String {
        value.formatted(.number)
    }
}
