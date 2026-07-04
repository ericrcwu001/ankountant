// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

public struct ReadinessScoreSummary: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case memory = "Memory"
        case performance = "Performance"
        case readiness = "Readiness"
    }

    public let kind: Kind
    public let valueText: String
    public let rangeText: String
    public let detailText: String
    public let fraction: Double?
    public let available: Bool

    public var id: Kind { kind }
    public var label: String { kind.rawValue }

    public init(
        kind: Kind,
        valueText: String,
        rangeText: String,
        detailText: String,
        fraction: Double?,
        available: Bool
    ) {
        self.kind = kind
        self.valueText = valueText
        self.rangeText = rangeText
        self.detailText = detailText
        self.fraction = fraction
        self.available = available
    }
}

public extension ReadinessScoreSummary {
    static func pendingSummaries(loaded: Bool) -> [ReadinessScoreSummary] {
        Kind.allCases.map {
            ReadinessScoreSummary(
                kind: $0,
                valueText: loaded ? "—" : "...",
                rangeText: loaded ? "insufficient" : "loading",
                detailText: loaded ? "Need more evidence" : "Loading",
                fraction: nil,
                available: false
            )
        }
    }
}

public extension ReadinessSummary {
    var scoreSummaries: [ReadinessScoreSummary] {
        [
            Self.percentSummary(
                kind: .memory,
                topics: topics.filter { !$0.memoryInsufficient },
                value: \.memory,
                low: \.memoryLow,
                high: \.memoryHigh,
                missingDetail: "Need review history",
                availableDetail: "Topic average"
            ),
            Self.percentSummary(
                kind: .performance,
                topics: topics.filter { !$0.performanceInsufficient },
                value: \.performance,
                low: \.performanceLow,
                high: \.performanceHigh,
                missingDetail: "Need sealed attempts",
                availableDetail: "Sealed tasks"
            ),
            readinessSummary,
        ]
    }

    private var readinessSummary: ReadinessScoreSummary {
        let validatedBand = checkedReadinessBand(band)
        guard !validatedBand.abstain else {
            return ReadinessScoreSummary(
                kind: .readiness,
                valueText: "—",
                rangeText: "withheld",
                detailText: validatedBand.reason,
                fraction: nil,
                available: false
            )
        }

        return ReadinessScoreSummary(
            kind: .readiness,
            valueText: "\(Int(validatedBand.pointEstimate.rounded()))",
            rangeText: "\(Int(validatedBand.bandLow.rounded()))–\(Int(validatedBand.bandHigh.rounded()))",
            detailText: "\(validatedBand.confidence) confidence",
            fraction: TopoScale.height(forScore: validatedBand.pointEstimate),
            available: true
        )
    }

    private static func percentSummary(
        kind: ReadinessScoreSummary.Kind,
        topics: [TopicScoreModel],
        value: KeyPath<TopicScoreModel, Double>,
        low: KeyPath<TopicScoreModel, Double>,
        high: KeyPath<TopicScoreModel, Double>,
        missingDetail: String,
        availableDetail: String
    ) -> ReadinessScoreSummary {
        guard let point = average(topics.map { $0[keyPath: value] }),
              let bandLow = average(topics.map { $0[keyPath: low] }),
              let bandHigh = average(topics.map { $0[keyPath: high] }) else {
            return ReadinessScoreSummary(
                kind: kind,
                valueText: "—",
                rangeText: "insufficient",
                detailText: missingDetail,
                fraction: nil,
                available: false
            )
        }

        return ReadinessScoreSummary(
            kind: kind,
            valueText: formatPercent(point),
            rangeText: "\(Int((bandLow * 100).rounded()))–\(Int((bandHigh * 100).rounded()))%",
            detailText: availableDetail,
            fraction: point,
            available: true
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
