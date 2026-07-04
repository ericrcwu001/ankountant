import SwiftUI
import AnkountantTheme
import Charts
import AnkiProto

struct AddedChart: View {
    let added: Anki_Stats_GraphsResponse.Added
    let period: StatsPeriod

    private struct Model {
        var bars: [(day: Int, count: Int)] = []
        var total = 0
        var uniqueDays = 0
        var avgPerDay: Double { uniqueDays == 0 ? 0 : Double(total) / Double(uniqueDays) }
    }

    private func buildModel() -> Model {
        let maxDay = period.days
        var raw: [(day: Int, count: Int)] = []
        var total = 0
        for (dayOffset, count) in added.added {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay, count > 0 else { continue }
            raw.append((day: day, count: Int(count)))
            total += Int(count)
        }
        var model = Model()
        model.total = total
        model.uniqueDays = raw.count
        model.bars = StatsSeriesBinning.binned(raw)
        return model
    }

    var body: some View {
        let model = buildModel()
        VStack(alignment: .leading, spacing: 8) {
            Text("Cards Added").ankountantFont(.bodyEmphasis)

            if model.bars.isEmpty {
                StatsEmptyChartView(title: "No cards added", systemImage: "plus.rectangle")
            } else {
                Chart(model.bars, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(.cyan.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
            }

            HStack(spacing: 16) {
                footerItem("Total", value: "\(model.total)")
                footerItem("Avg/day", value: String(format: "%.1f", model.avgPerDay))
            }
            .font(.caption2)
        }
        .ankountantCard()
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
