// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

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
    guard !band.abstain else { return .unproven }
    return band.pointEstimate >= TopoScale.passScore ? .above : .below
}

/// Near-pass display rule: classify on the raw point, but clamp the *displayed*
/// integer so it never crosses the line versus the true standing — a below-pass
/// score never renders as an unqualified "75" beside the pass line.
public func passDisplayScore(_ point: Double, standing: PassStanding) -> Int {
    let rounded = Int(point.rounded())
    let pass = Int(TopoScale.passScore)
    switch standing {
    case .above: return max(rounded, pass)       // >= 75
    case .below: return min(rounded, pass - 1)   // <= 74
    case .unproven: return rounded
    }
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
        guard let band, !band.abstain else { return nil }
        return band.pointEstimate
    }
}

// MARK: - Shared formatters (moved out of HomeView so Home + SectionDetail agree)

/// Gap at/above this fraction is flagged (mirrors the desktop dashboard + Rust).
public let topicGapWarningThreshold = 0.25

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
    "\(Int(band.bandLow.rounded()))–\(Int(band.bandHigh.rounded()))"
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

    var gapWarning: Bool { gap >= topicGapWarningThreshold }
}

public extension ReadinessSummary {
    /// Count of topics whose memory→performance gap is flag-worthy.
    var gapsToCloseCount: Int {
        topics.filter { $0.gap >= topicGapWarningThreshold }.count
    }
}
