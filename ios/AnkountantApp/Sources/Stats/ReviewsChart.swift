import SwiftUI
import AnkountantTheme
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let period: StatsPeriod

    private typealias Reviews = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews

    private static let types: [(name: String, keyPath: KeyPath<Reviews, UInt32>)] = [
        ("Learn", \.learn),
        ("Relearn", \.relearn),
        ("Young", \.young),
        ("Mature", \.mature),
        ("Filtered", \.filtered),
    ]

    private struct Series: Identifiable {
        let id: String
        let day: Int
        let type: String
        let count: Int
    }

    private struct Model {
        var series: [Series] = []
        var total = 0
        var uniqueDays = 0
        var avgPerDay: Double { uniqueDays == 0 ? 0 : Double(total) / Double(uniqueDays) }
    }

    /// Aggregates the raw per-day review counts once per render. Days are binned
    /// into a bounded number of buckets so long time frames ("All Time") don't
    /// emit thousands of marks and freeze the main thread during layout.
    private func buildModel() -> Model {
        let maxDay = period.days
        var validDays: [(day: Int, rev: Reviews)] = []
        var minDay = 0
        var total = 0
        for (dayOffset, rev) in reviews.count {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            let dayTotal = Int(rev.learn) + Int(rev.relearn) + Int(rev.young)
                + Int(rev.mature) + Int(rev.filtered)
            guard dayTotal > 0 else { continue }
            validDays.append((day, rev))
            minDay = min(minDay, day)
            total += dayTotal
        }

        var model = Model()
        model.total = total
        model.uniqueDays = validDays.count
        guard !validDays.isEmpty else { return model }

        let size = StatsSeriesBinning.bucketSize(forSpanDays: (0 - minDay) + 1)
        var buckets: [Int: [Int]] = [:]
        for (day, rev) in validDays {
            let key = StatsSeriesBinning.bucketKey(day: day, size: size)
            var sums = buckets[key] ?? Array(repeating: 0, count: Self.types.count)
            for (index, type) in Self.types.enumerated() {
                sums[index] += Int(rev[keyPath: type.keyPath])
            }
            buckets[key] = sums
        }

        var series: [Series] = []
        for (bucketDay, sums) in buckets {
            for (index, type) in Self.types.enumerated() where sums[index] > 0 {
                series.append(
                    Series(id: "\(type.name)@\(bucketDay)", day: bucketDay, type: type.name, count: sums[index])
                )
            }
        }
        model.series = series.sorted { $0.day < $1.day }
        return model
    }

    var body: some View {
        let model = buildModel()
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews").ankountantFont(.bodyEmphasis)

            if model.series.isEmpty {
                StatsEmptyChartView(title: "No review data", systemImage: "chart.bar")
            } else {
                Chart(model.series) { entry in
                    BarMark(
                        x: .value("Day", entry.day),
                        y: .value("Count", entry.count)
                    )
                    .foregroundStyle(by: .value("Type", entry.type))
                }
                .chartForegroundStyleScale([
                    "Learn": Color.blue,
                    "Relearn": Color.orange,
                    "Young": Color.green,
                    "Mature": Color.purple,
                    "Filtered": Color.gray,
                ])
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
