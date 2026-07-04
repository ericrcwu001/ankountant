package import Foundation

/// Opaque wrapper for a serialized proto SchedulingState. App code holds these
/// but cannot inspect them; AnkiServices reads/writes the bytes internally.
public struct SchedulingStateToken: Sendable {
    package let bytes: Data
    package init(_ bytes: Data) { self.bytes = bytes }
}

public struct ReviewSchedulingStates: Sendable {
    public let current: SchedulingStateToken
    public let again: SchedulingStateToken
    public let hard: SchedulingStateToken
    public let good: SchedulingStateToken
    public let easy: SchedulingStateToken

    package init(
        current: SchedulingStateToken,
        again: SchedulingStateToken,
        hard: SchedulingStateToken,
        good: SchedulingStateToken,
        easy: SchedulingStateToken
    ) {
        self.current = current
        self.again = again
        self.hard = hard
        self.good = good
        self.easy = easy
    }
}

public struct QueuedReviewCard: Sendable {
    public let card: CardRecord
    public let states: ReviewSchedulingStates
    public let nextIntervals: [Rating: String]

    package init(card: CardRecord, states: ReviewSchedulingStates, nextIntervals: [Rating: String]) {
        self.card = card
        self.states = states
        self.nextIntervals = nextIntervals
    }

    /// Convenience factory for tests and SwiftUI previews.
    public static func preview(cardId: Int64, noteId: Int64, ord: Int32) -> QueuedReviewCard {
        let emptyToken = SchedulingStateToken(Data())
        let states = ReviewSchedulingStates(
            current: emptyToken, again: emptyToken,
            hard: emptyToken, good: emptyToken, easy: emptyToken
        )
        let card = CardRecord(id: cardId, nid: noteId, did: 1, ord: ord, mod: 0)
        return QueuedReviewCard(card: card, states: states, nextIntervals: [:])
    }
}

public struct QueuedCardsResult: Sendable {
    public let cards: [QueuedReviewCard]
    public let newCount: Int
    public let learningCount: Int
    public let reviewCount: Int

    public init(cards: [QueuedReviewCard], newCount: Int, learningCount: Int, reviewCount: Int) {
        self.cards = cards
        self.newCount = newCount
        self.learningCount = learningCount
        self.reviewCount = reviewCount
    }
}

/// A4/A5 — the exam-day readiness band for a section. When `abstain` is true
/// there is too little evidence to project a score (surface `reason`, no
/// number); otherwise `bandLow`..`bandHigh` is the Wilson 95% projection mapped
/// onto the CPA scaled-score scale (0-99, pass 75) via the ADR-0005 transform,
/// with `pointEstimate` the band centre. `coverage` (0..1) and `generatedAt`
/// (unix seconds) are always populated; `reasons` are factual drivers.
public struct ReadinessBand: Sendable, Equatable {
    public let abstain: Bool
    public let reason: String
    public let bandLow: Double
    public let bandHigh: Double
    public let pointEstimate: Double
    public let confidence: String
    public let coverage: Double
    public let generatedAt: Int64
    public let reasons: [String]

    public init(
        abstain: Bool,
        reason: String,
        bandLow: Double,
        bandHigh: Double,
        pointEstimate: Double = 0,
        confidence: String,
        coverage: Double = 0,
        generatedAt: Int64 = 0,
        reasons: [String] = []
    ) {
        self.abstain = abstain
        self.reason = reason
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.pointEstimate = pointEstimate
        self.confidence = confidence
        self.coverage = coverage
        self.generatedAt = generatedAt
        self.reasons = reasons
    }
}

/// A4 — per-topic Memory vs Performance on a shared 0..1 scale, each with a
/// Wilson confidence band (`*Low`..`*High`, also 0..1). `memory` is only
/// meaningful when `memoryInsufficient` is false.
public struct TopicScoreModel: Sendable, Equatable, Identifiable {
    public let setId: String
    public let memory: Double
    public let performance: Double
    public let gap: Double
    public let memoryInsufficient: Bool
    public let memoryLow: Double
    public let memoryHigh: Double
    public let performanceLow: Double
    public let performanceHigh: Double

    public var id: String { setId }

    public init(
        setId: String,
        memory: Double,
        performance: Double,
        gap: Double,
        memoryInsufficient: Bool,
        memoryLow: Double = 0,
        memoryHigh: Double = 0,
        performanceLow: Double = 0,
        performanceHigh: Double = 0
    ) {
        precondition(!setId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Topic score requires a set id.")
        if memoryInsufficient {
            precondition(memory == 0 && memoryLow == 0 && memoryHigh == 0, "Topic memory cannot be marked insufficient with evidence values.")
        } else {
            preconditionTopicEvidenceRange("memory", value: memory, low: memoryLow, high: memoryHigh)
        }
        let hasPerformanceEvidence = performanceLow != 0 || performanceHigh != 0
        precondition(performance == 0 || hasPerformanceEvidence, "Topic performance cannot be non-zero without a confidence band.")
        if hasPerformanceEvidence {
            preconditionTopicEvidenceRange("performance", value: performance, low: performanceLow, high: performanceHigh)
        }
        if !memoryInsufficient && hasPerformanceEvidence {
            preconditionGap(gap)
        }
        self.setId = setId
        self.memory = memory
        self.performance = performance
        self.gap = gap
        self.memoryInsufficient = memoryInsufficient
        self.memoryLow = memoryLow
        self.memoryHigh = memoryHigh
        self.performanceLow = performanceLow
        self.performanceHigh = performanceHigh
    }
}

private func preconditionTopicEvidenceRange(_ metric: String, value: Double, low: Double, high: Double) {
    preconditionFraction("topic \(metric)", value)
    preconditionFraction("topic \(metric) low", low)
    preconditionFraction("topic \(metric) high", high)
    precondition(low < high, "Topic \(metric) requires a non-empty confidence band.")
    precondition(value >= low && value <= high, "Topic \(metric) point must be inside its confidence band.")
}

private func preconditionFraction(_ label: String, _ value: Double) {
    precondition(value.isFinite, "\(label) must be a finite number.")
    precondition(value >= 0 && value <= 1, "\(label) must be between 0 and 1.")
}

private func preconditionGap(_ value: Double) {
    precondition(value.isFinite, "topic gap must be a finite number.")
    precondition(value >= -1 && value <= 1, "topic gap must be between -1 and 1.")
}

/// The full readiness rollup for a section (band + per-topic scores).
public struct ReadinessSummary: Sendable, Equatable {
    public let band: ReadinessBand
    public let topics: [TopicScoreModel]

    public init(band: ReadinessBand, topics: [TopicScoreModel]) {
        self.band = band
        self.topics = topics
    }
}

public struct RenderedCard: Sendable {
    public let frontHTML: String
    public let backHTML: String
    public let cardCSS: String

    public init(frontHTML: String, backHTML: String, cardCSS: String) {
        self.frontHTML = frontHTML
        self.backHTML = backHTML
        self.cardCSS = cardCSS
    }
}

public struct TypedAnswerState: Sendable, Equatable {
    public let placeholder: String
    public let expected: String
    public let combining: Bool
    public let fontName: String
    public let fontSize: Int

    public init(placeholder: String, expected: String, combining: Bool, fontName: String, fontSize: Int) {
        self.placeholder = placeholder
        self.expected = expected
        self.combining = combining
        self.fontName = fontName
        self.fontSize = fontSize
    }
}
