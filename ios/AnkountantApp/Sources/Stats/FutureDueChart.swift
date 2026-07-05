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
        var tomorrow = 0
        var avgPerDay = 0.0
    }

    private func buildModel() -> Model {
        let maxDay = period.days
        var raw: [(day: Int, count: Int)] = []
        var total = 0
        var tomorrow = 0
        var positiveSum = 0
        var maxOffset = 1
        var hasPositive = false
        for (dayOffset, count) in futureDue.futureDue {
            let day = Int(dayOffset)
            if !includeBacklog && day < 0 { continue }
            guard day < maxDay else { continue }
            let value = Int(count)
            raw.append((day: day, count: value))
            total += value
            if day == 1 { tomorrow += value }
            if day >= 0 {
                hasPositive = true
                positiveSum += value
                maxOffset = max(maxOffset, day)
            }
        }
        var model = Model()
        model.total = total
        model.tomorrow = tomorrow
        model.avgPerDay = hasPositive ? Double(positiveSum) / Double(max(maxOffset, 1)) : 0
        model.bars = StatsSeriesBinning.binned(raw)
        return model
    }

    var body: some View {
        let model = buildModel()
        VStack(alignment: .leading, spacing: 8) {
            Text("Future Due").ankountantFont(.bodyEmphasis)

            if model.bars.isEmpty {
                StatsEmptyChartView(
                    title: "No cards due",
                    systemImage: "calendar",
                    description: "Add or review cards to create a future due schedule."
                )
            } else {
                Chart(model.bars, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(item.day < 0 ? Color.red.gradient : Color.blue.gradient)
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
                    .font(.caption)
            }

            HStack(spacing: 16) {
                footerItem("Total", value: "\(model.total)")
                footerItem("Avg/day", value: String(format: "%.1f", model.avgPerDay))
                footerItem("Tomorrow", value: "\(model.tomorrow)")
                footerItem("Daily Load", value: "\(futureDue.dailyLoad)")
            }
        }
        .ankountantCard()
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: AnkountantSpacing.xxs) {
            Text(value).ankountantFont(.captionBold).monospacedDigit()
            Text(label).ankountantFont(.micro).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
