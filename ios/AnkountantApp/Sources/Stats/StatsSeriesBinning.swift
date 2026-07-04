import Foundation

/// Aggregates day-offset time series into a bounded number of buckets so charts
/// stay responsive for long time frames.
///
/// The reviews / added / future-due charts plot one mark per day. Over a long
/// span (e.g. the "All Time" range, which can cover years) that becomes
/// thousands of marks, and Swift Charts layout on the main thread freezes the
/// app when switching time frames. Binning caps the mark count: short ranges
/// (≤ `maxBuckets` days) are untouched (1 day per bucket), while longer ranges
/// collapse into wider buckets (weeks, then months, …).
enum StatsSeriesBinning {
    /// Upper bound on the number of buckets any time-series chart should plot.
    /// Beyond ~100 marks Swift Charts layout cost grows sharply.
    static let maxBuckets = 90

    /// Bucket width, in days, needed to cover `spanDays` within `maxBuckets`.
    static func bucketSize(forSpanDays spanDays: Int) -> Int {
        guard spanDays > maxBuckets else { return 1 }
        return Int((Double(spanDays) / Double(maxBuckets)).rounded(.up))
    }

    /// Floor-aligns `day` onto a bucket boundary (correct for negative offsets),
    /// keeping day 0 as its own bucket edge.
    static func bucketKey(day: Int, size: Int) -> Int {
        guard size > 1 else { return day }
        return Int((Double(day) / Double(size)).rounded(.down)) * size
    }

    /// Bins `(day, count)` pairs into `(day, count)` buckets, summing counts that
    /// fall in the same bucket. Bucket size is derived from the data's own span.
    /// Result is sorted by day ascending.
    static func binned(_ points: [(day: Int, count: Int)]) -> [(day: Int, count: Int)] {
        guard let minDay = points.map(\.day).min(),
              let maxDay = points.map(\.day).max()
        else { return [] }

        let size = bucketSize(forSpanDays: maxDay - minDay + 1)
        guard size > 1 else { return points.sorted { $0.day < $1.day } }

        var totals: [Int: Int] = [:]
        for point in points {
            totals[bucketKey(day: point.day, size: size), default: 0] += point.count
        }
        return totals
            .map { (day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
