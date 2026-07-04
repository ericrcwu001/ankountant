// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

public import Foundation

/// Pure, render-free readiness→topography model + formatters for the summit Home.
///
/// The single hard invariant (Constraint 1) lives here as a scalar comparison, so
/// it is unit-testable without any UI: a section is `.above` the pass line iff its
/// projected CPA point estimate is >= 75. Rendering engines (Swift Charts here)
/// consume `pointEstimate` / `bandLow` / `bandHigh` directly on a pinned 0...99
/// domain; classification is never read back from pixels.

/// Where a section sits relative to the CPA pass line. `.unproven` is gated on
/// `ReadinessBand.abstain` — NEVER on height, because an abstaining band carries
/// `pointEstimate == 0` and would otherwise masquerade as a real score of 0.
public enum PassStanding: String, Sendable, Equatable {
    case unproven
    case below
    case above
}

/// The CPA scaled-score axis the summit is drawn on: 0...99, pass at 75
/// (ADR-0005; `cpa_scale_from_accuracy` caps at 99, never 100).
public enum TopoScale {
    public static let domainMax: Double = 99
    public static let passScore: Double = 75

    /// Normalize a CPA score to 0...1 (clamped) for hand-drawn position meters.
    /// (The Charts range uses the raw value on a pinned domain instead.)
    public static func height(forScore score: Double) -> Double {
        let clamped = min(max(score, 0), domainMax)
        return clamped / domainMax
    }

    /// The pass line's normalized position (0...1).
    public static var passHeight: Double { height(forScore: passScore) }
}

/// Authoritative above/below classifier. Gate on `abstain` FIRST.
public func passStanding(_ band: ReadinessBand) -> PassStanding {
    let validatedBand = checkedReadinessBand(band)
    guard !validatedBand.abstain else { return .unproven }
    return validatedBand.pointEstimate >= TopoScale.passScore ? .above : .below
}

/// One section's readiness for the summit range + list. Reuses the existing
/// `ReadinessSummary` (no parallel snapshot type). `summary == nil` means the
/// per-section load failed → treated as unproven.
public struct SectionReadiness: Sendable, Equatable, Identifiable {
    public let section: CPASection
    public let summary: ReadinessSummary?

    public init(section: CPASection, summary: ReadinessSummary?) {
        self.section = section
        self.summary = summary
    }

    public var id: CPASection { section }
    public var band: ReadinessBand? { summary?.band }
    public var standing: PassStanding { band.map(passStanding) ?? .unproven }

    /// CPA point for plotting; nil when abstaining (render as an unproven ghost at
    /// the base, never a height).
    public var heightPoint: Double? {
        let validatedBand = band.map(checkedReadinessBand)
        guard let validatedBand, !validatedBand.abstain else { return nil }
        return validatedBand.pointEstimate
    }
}

// MARK: - Shared formatters (moved out of HomeView so Home + SectionDetail agree)

/// Gap at/above this fraction is flagged (mirrors the desktop dashboard + Rust).
public let topicGapWarningThreshold = 0.25
public let readinessMinimumSealedAttempts = 20
public let readinessMinimumCoverage = 0.60

public enum ReadinessValidationError: Error, Equatable, LocalizedError {
    case missingAbstainReason
    case invalidCoverage
    case insufficientCoverage
    case nonFiniteScaleValue(String)
    case outOfRangeScaleValue(String)
    case invalidBand
    case pointOutsideBand
    case missingConfidence
    case missingEvidenceReasons
    case missingGeneratedAt

    public var errorDescription: String? {
        switch self {
        case .missingAbstainReason:
            "Readiness abstained without a reason."
        case .invalidCoverage:
            "Readiness coverage must be between 0 and 1."
        case .insufficientCoverage:
            "Readiness coverage must be at least \(formatPercent(readinessMinimumCoverage)) for an emitted range."
        case let .nonFiniteScaleValue(label):
            "Readiness \(label) must be a finite number."
        case let .outOfRangeScaleValue(label):
            "Readiness \(label) must be between 0 and \(Int(TopoScale.domainMax))."
        case .invalidBand:
            "Readiness band must have a low value below the high value."
        case .pointOutsideBand:
            "Readiness point estimate must be inside the reported band."
        case .missingConfidence:
            "Readiness confidence is required for an emitted range."
        case .missingEvidenceReasons:
            "Readiness evidence reasons are required for an emitted range."
        case .missingGeneratedAt:
            "Readiness generated timestamp is required for an emitted range."
        }
    }
}

public func validatedReadinessBand(_ band: ReadinessBand) throws -> ReadinessBand {
    try validateCoverage(band.coverage)
    let reason = band.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let confidence = band.confidence.trimmingCharacters(in: .whitespacesAndNewlines)
    let reasons = band.reasons.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    if band.abstain {
        guard !reason.isEmpty else { throw ReadinessValidationError.missingAbstainReason }
        return ReadinessBand(
            abstain: true,
            reason: reason,
            bandLow: band.bandLow,
            bandHigh: band.bandHigh,
            pointEstimate: band.pointEstimate,
            confidence: confidence,
            coverage: band.coverage,
            generatedAt: band.generatedAt,
            reasons: reasons
        )
    }

    guard band.coverage >= readinessMinimumCoverage else {
        throw ReadinessValidationError.insufficientCoverage
    }
    try validateScaleValue("band low", band.bandLow)
    try validateScaleValue("band high", band.bandHigh)
    try validateScaleValue("point estimate", band.pointEstimate)
    guard band.bandLow < band.bandHigh else { throw ReadinessValidationError.invalidBand }
    guard band.pointEstimate >= band.bandLow && band.pointEstimate <= band.bandHigh else {
        throw ReadinessValidationError.pointOutsideBand
    }
    guard !confidence.isEmpty else { throw ReadinessValidationError.missingConfidence }
    guard !reasons.isEmpty && !reasons.contains(where: \.isEmpty) else {
        throw ReadinessValidationError.missingEvidenceReasons
    }
    guard band.generatedAt > 0 else { throw ReadinessValidationError.missingGeneratedAt }

    return ReadinessBand(
        abstain: false,
        reason: reason,
        bandLow: band.bandLow,
        bandHigh: band.bandHigh,
        pointEstimate: band.pointEstimate,
        confidence: confidence,
        coverage: band.coverage,
        generatedAt: band.generatedAt,
        reasons: reasons
    )
}

func checkedReadinessBand(_ band: ReadinessBand) -> ReadinessBand {
    do {
        return try validatedReadinessBand(band)
    } catch {
        preconditionFailure(error.localizedDescription)
    }
}

private func validateCoverage(_ coverage: Double) throws {
    guard coverage.isFinite && coverage >= 0 && coverage <= 1 else {
        throw ReadinessValidationError.invalidCoverage
    }
}

private func validateScaleValue(_ label: String, _ value: Double) throws {
    guard value.isFinite else { throw ReadinessValidationError.nonFiniteScaleValue(label) }
    guard value >= 0 && value <= TopoScale.domainMax else {
        throw ReadinessValidationError.outOfRangeScaleValue(label)
    }
}

public struct ReadinessEvidence: Sendable, Equatable {
    public let evidenceLines: [String]
    public let updatedAtLine: String
    public let missingData: [String]
    public let calibrationStatus: String
    public let nextAction: String
    public let giveUpRule: String

    public init(
        evidenceLines: [String],
        updatedAtLine: String,
        missingData: [String],
        calibrationStatus: String,
        nextAction: String,
        giveUpRule: String
    ) {
        self.evidenceLines = evidenceLines
        self.updatedAtLine = updatedAtLine
        self.missingData = missingData
        self.calibrationStatus = calibrationStatus
        self.nextAction = nextAction
        self.giveUpRule = giveUpRule
    }
}

/// A point score plus its Wilson range ("62% (54–70%)"), or "insufficient" when
/// the metric has no reliable value (nil).
public func scoreWithRange(_ value: Double?, low: Double, high: Double) -> String {
    guard let value else { return "insufficient" }
    let lo = Int((low * 100).rounded())
    let hi = Int((high * 100).rounded())
    let point = Int((value * 100).rounded())
    return hi > lo ? "\(point)% (\(lo)–\(hi)%)" : "\(point)%"
}

/// A 0..1 fraction as an integer percent string ("62%").
public func formatPercent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

/// The CPA scaled-score band label ("60–84"); the score, not a percentage.
public func readinessBandLabel(_ band: ReadinessBand) -> String {
    let validatedBand = checkedReadinessBand(band)
    return "\(Int(validatedBand.bandLow.rounded()))–\(Int(validatedBand.bandHigh.rounded()))"
}

public func readinessEvidence(band: ReadinessBand, topics: [TopicScoreModel]) -> ReadinessEvidence {
    let validatedBand = checkedReadinessBand(band)
    var missingData: [String] = []
    if validatedBand.abstain && validatedBand.reason.localizedCaseInsensitiveContains("volume") {
        missingData.append("Need at least \(readinessMinimumSealedAttempts) sealed attempts before a readiness range can be shown.")
    }
    if validatedBand.coverage < readinessMinimumCoverage {
        missingData.append("Need sealed evidence across \(formatPercent(readinessMinimumCoverage)) of topics; current coverage is \(formatPercent(validatedBand.coverage)).")
    }

    let thinMemory = topics.filter(\.memoryInsufficient).prefix(3).map(\.displayName)
    if !thinMemory.isEmpty {
        missingData.append("Memory is still thin for \(thinMemory.joined(separator: ", ")).")
    }
    let missingPerformance = topics.filter(\.performanceInsufficient).prefix(3).map(\.displayName)
    if !missingPerformance.isEmpty {
        missingData.append("Performance has no sealed evidence for \(missingPerformance.joined(separator: ", ")).")
    }
    if missingData.isEmpty {
        missingData.append("No hard blockers for the current range; more sealed attempts will narrow uncertainty.")
    }

    return ReadinessEvidence(
        evidenceLines: validatedBand.reasons.isEmpty ? [validatedBand.reason] : validatedBand.reasons,
        updatedAtLine: readinessGeneratedAtLine(validatedBand.generatedAt),
        missingData: missingData,
        calibrationStatus: "No past score-verification history is available yet; treat this as an uncalibrated projection until held-out outcomes are logged.",
        nextAction: bestNextReadinessAction(band: validatedBand, topics: topics),
        giveUpRule: "No readiness range until there are at least \(readinessMinimumSealedAttempts) sealed attempts and \(formatPercent(readinessMinimumCoverage)) topic coverage."
    )
}

public func readinessGeneratedAtLine(_ generatedAt: Int64) -> String {
    guard generatedAt > 0 else {
        return "Last updated time unavailable; refresh readiness after more graded evidence is logged."
    }
    let date = Date(timeIntervalSince1970: TimeInterval(generatedAt))
    return "Last updated \(date.formatted(date: .abbreviated, time: .shortened))."
}

private func bestNextReadinessAction(band: ReadinessBand, topics: [TopicScoreModel]) -> String {
    guard !topics.isEmpty else {
        return "Load a CPA bank or demo profile, then start sealed practice."
    }
    if band.abstain && band.reason.localizedCaseInsensitiveContains("volume") {
        return "Complete sealed exam-style attempts until at least \(readinessMinimumSealedAttempts) are logged; readiness is withheld for insufficient volume."
    }
    if band.coverage < readinessMinimumCoverage {
        return "Add sealed exam-style attempts in uncovered topics before trusting the readiness range."
    }
    if let gap = topics
        .filter(\.gapWarning)
        .max(by: { $0.gap < $1.gap }) {
        return "Run a confusion-set drill for \(gap.displayName); memory is \(formatPercent(gap.memory)) and performance is \(formatPercent(gap.performance))."
    }
    if let missingPerformance = topics.first(where: \.performanceInsufficient) {
        return "Do sealed exam-style practice for \(missingPerformance.displayName); performance has no sealed evidence yet."
    }
    if let weakest = topics.filter({ !$0.performanceInsufficient }).min(by: { $0.performance < $1.performance }) {
        return "Do sealed exam-style practice for \(weakest.displayName); current performance is \(formatPercent(weakest.performance))."
    }
    preconditionFailure("Readiness topics require at least one performance value.")
}

public extension TopicScoreModel {
    /// "capitalize_vs_expense" → "Capitalize Vs Expense".
    var displayName: String {
        setId.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Performance has no reliable value until the sealed bank is sampled — the
    /// backend signals it with a zero-width band (both endpoints 0).
    var performanceInsufficient: Bool {
        performanceLow == 0 && performanceHigh == 0
    }

    var gapAvailable: Bool { !memoryInsufficient && !performanceInsufficient }
    var gapWarning: Bool { gapAvailable && gap >= topicGapWarningThreshold }
}

public extension ReadinessSummary {
    /// Count of topics whose memory→performance gap is flag-worthy.
    var gapsToCloseCount: Int {
        topics.count(where: \.gapWarning)
    }
}
