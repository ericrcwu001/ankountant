import SwiftUI
import AnkountantTheme
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let period: StatsPeriod
    @Environment(\.palette) private var palette

    private typealias Reviews = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews

    private static let types: [(name: String, keyPath: KeyPath<Reviews, UInt32>)] = [
        ("Learn", \.learn),
        ("Relearn", \.relearn),
        (StatsCardStateLabels.shortInterval, \.young),
        (StatsCardStateLabels.longInterval, \.mature),
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
        var activeDays = 0
        var spanDays = 1
        var avgPerDay: Double { Double(total) / Double(max(spanDays, 1)) }
    }

    private func buildModel() -> Model {
        let maxDay = period.days
        var validDays: [(day: Int, rev: Reviews)] = []
        var minDay = 0
        var total = 0
        for (dayOffset, rev) in reviews.count {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) < maxDay else { continue }
            let dayTotal = Int(rev.learn) + Int(rev.relearn) + Int(rev.young)
                + Int(rev.mature) + Int(rev.filtered)
            guard dayTotal > 0 else { continue }
            validDays.append((day, rev))
            minDay = min(minDay, day)
            total += dayTotal
        }

        var model = Model()
        model.total = total
        model.activeDays = validDays.count
        model.spanDays = period == .all ? max(1, abs(minDay) + 1) : period.days
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
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text("Review Volume").ankountantFont(.bodyEmphasis)
                Text("Daily work by card stage")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if model.series.isEmpty {
                StatsEmptyChartView(
                    title: "No review data",
                    systemImage: "chart.bar",
                    description: "Review cards in this period to build performance evidence."
                )
            } else {
                Chart(model.series) { entry in
                    BarMark(
                        x: .value("Day", entry.day),
                        y: .value("Count", entry.count)
                    )
                    .foregroundStyle(by: .value("Type", entry.type))
                }
                .chartForegroundStyleScale([
                    "Learn": palette.stateNew,
                    "Relearn": palette.stateLearn,
                    StatsCardStateLabels.shortInterval: palette.stateReview,
                    StatsCardStateLabels.longInterval: palette.accent,
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

            LazyVGrid(columns: footerColumns, alignment: .leading, spacing: AnkountantSpacing.md) {
                footerItem("Reviews", value: "\(model.total)")
                footerItem("Avg/day", value: formatDecimal(model.avgPerDay))
                footerItem("Active days", value: "\(model.activeDays)")
            }
        }
        .ankountantCard()
    }

    private var footerColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: AnkountantSpacing.md)]
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
}
