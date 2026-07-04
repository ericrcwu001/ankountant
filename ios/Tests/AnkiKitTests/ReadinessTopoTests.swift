// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Testing
@testable import AnkiKit

/// Pure-logic tests for the summit Home: the ≥75 invariant (Constraint 1), the
/// abstain gate, the near-pass display clamp, the section enum, and the shared
/// formatters. No UI / simulator needed.
@Suite("Readiness topography")
struct ReadinessTopoTests {
    private func band(
        abstain: Bool = false,
        low: Double = 0,
        high: Double = 0,
        point: Double = 0,
        confidence: String = "Med"
    ) -> ReadinessBand {
        ReadinessBand(
            abstain: abstain,
            reason: abstain ? "insufficient volume" : "",
            bandLow: low,
            bandHigh: high,
            pointEstimate: point,
            confidence: confidence
        )
    }

    // MARK: Constraint 1 — ≥75 above, <75 below

    @Test func classifiesAboveBelowByPoint() {
        #expect(passStanding(band(low: 78, high: 90, point: 84)) == .above)
        #expect(passStanding(band(low: 52, high: 70, point: 61)) == .below)
        #expect(passStanding(band(low: 70, high: 80, point: 75)) == .above) // inclusive pass
        #expect(passStanding(band(low: 70, high: 80, point: 74.99)) == .below)
    }

    @Test func abstainIsUnprovenEvenWithZeroPoint() {
        // The trap: an abstaining band carries pointEstimate == 0.
        #expect(passStanding(band(abstain: true, point: 0)) == .unproven)
    }

    // MARK: TopoScale

    @Test func heightIsMonotonicAndClamped() {
        #expect(TopoScale.height(forScore: 0) == 0)
        #expect(TopoScale.height(forScore: 99) == 1)
        #expect(TopoScale.height(forScore: -10) == 0)
        #expect(TopoScale.height(forScore: 200) == 1)
        #expect(TopoScale.height(forScore: 84) > TopoScale.height(forScore: 61))
        #expect(TopoScale.passHeight == TopoScale.height(forScore: 75))
    }

    @Test func invariantHoldsAcrossDomain() {
        // Exhaustive: normalized height ordering must agree with the classifier.
        for s in stride(from: 0.0, through: 99.0, by: 1) {
            let above = s >= TopoScale.passScore
            let higher = TopoScale.height(forScore: s) >= TopoScale.passHeight
            #expect(above == higher)
        }
    }

    // MARK: Near-pass display clamp

    @Test func nearPassScoreNeverShowsMisleading75() {
        #expect(passDisplayScore(74.6, standing: .below) == 74) // rounds to 75, clamped to 74
        #expect(passDisplayScore(75.4, standing: .above) == 75)
        #expect(passDisplayScore(90, standing: .above) == 90)
        #expect(passDisplayScore(60, standing: .below) == 60)
        #expect(passDisplayScore(0, standing: .unproven) == 0)
    }

    // MARK: CPASection

    @Test func homeOrderAndCodes() {
        #expect(CPASection.homeOrder == [.far, .aud, .reg, .tcp, .isc])
        #expect(CPASection.far.code == "FAR")
        #expect(CPASection.tcp.displayName == "Tax Compliance and Planning")
        #expect(CPASection(code: "AUD") == .aud)
        #expect(CPASection(code: "XX") == nil)
        #expect(CPASection.allCases.count == 6) // includes BAR for backend parity
        #expect(!CPASection.homeOrder.contains(.bar))
    }

    // MARK: Formatters

    @Test func formatters() {
        #expect(scoreWithRange(0.62, low: 0.54, high: 0.70) == "62% (54–70%)")
        #expect(scoreWithRange(0.62, low: 0.62, high: 0.62) == "62%")
        #expect(scoreWithRange(nil, low: 0, high: 0) == "insufficient")
        #expect(formatPercent(0.6) == "60%")
        #expect(readinessBandLabel(band(low: 60, high: 84)) == "60–84")
    }

    @Test func topicExtensions() {
        let warn = TopicScoreModel(setId: "capitalize_vs_expense", memory: 0.8, performance: 0.5, gap: 0.30, memoryInsufficient: false)
        #expect(warn.gapWarning)
        #expect(warn.displayName == "Capitalize Vs Expense")
        let ok = TopicScoreModel(setId: "x", memory: 0.8, performance: 0.7, gap: 0.10, memoryInsufficient: false)
        #expect(!ok.gapWarning)
        let noPerf = TopicScoreModel(setId: "x", memory: 0.8, performance: 0, gap: 0, memoryInsufficient: false, performanceLow: 0, performanceHigh: 0)
        #expect(noPerf.performanceInsufficient)
    }

    @Test func gapsToCloseCount() {
        let summary = ReadinessSummary(band: band(), topics: [
            TopicScoreModel(setId: "a", memory: 0.9, performance: 0.5, gap: 0.40, memoryInsufficient: false),
            TopicScoreModel(setId: "b", memory: 0.6, performance: 0.5, gap: 0.10, memoryInsufficient: false),
            TopicScoreModel(setId: "c", memory: 0.9, performance: 0.6, gap: 0.30, memoryInsufficient: false),
        ])
        #expect(summary.gapsToCloseCount == 2)
    }

    @Test func readinessEvidenceNamesMissingDataAndGiveUpRule() {
        let band = ReadinessBand(
            abstain: true,
            reason: "insufficient volume",
            bandLow: 0,
            bandHigh: 0,
            confidence: "",
            coverage: 0.4
        )
        let evidence = readinessEvidence(
            band: band,
            topics: [
                TopicScoreModel(setId: "tax_timing", memory: 0, performance: 0.42, gap: 0, memoryInsufficient: true),
            ]
        )
        #expect(evidence.giveUpRule.contains("20 sealed attempts"))
        #expect(evidence.missingData.joined(separator: " ").contains("60% of topics"))
        #expect(evidence.missingData.joined(separator: " ").contains("Tax Timing"))
        #expect(evidence.calibrationStatus.contains("No past score-verification history"))
    }

    @Test func readinessEvidenceChoosesLargestGapAction() {
        let band = ReadinessBand(
            abstain: false,
            reason: "",
            bandLow: 74,
            bandHigh: 85,
            pointEstimate: 80,
            confidence: "High",
            coverage: 1,
            reasons: ["Coverage: 100% of topics; 188 sealed attempts"]
        )
        let evidence = readinessEvidence(
            band: band,
            topics: [
                TopicScoreModel(setId: "leases", memory: 0.9, performance: 0.52, gap: 0.38, memoryInsufficient: false),
                TopicScoreModel(setId: "tax_timing", memory: 0.7, performance: 0.51, gap: 0.19, memoryInsufficient: false),
            ]
        )
        #expect(evidence.nextAction.contains("Leases"))
        #expect(evidence.nextAction.contains("memory is 90%"))
        #expect(evidence.missingData.first?.contains("No hard blockers") == true)
    }

    @Test func readinessEvidenceDoesNotInventMemoryValueForThinMemoryGaps() {
        let band = ReadinessBand(
            abstain: false,
            reason: "",
            bandLow: 74,
            bandHigh: 85,
            pointEstimate: 80,
            confidence: "High",
            coverage: 1,
            reasons: ["Coverage: 100% of topics; 188 sealed attempts"]
        )
        let evidence = readinessEvidence(
            band: band,
            topics: [
                TopicScoreModel(setId: "tax_timing", memory: 0, performance: 0.42, gap: 0.38, memoryInsufficient: true),
            ]
        )
        #expect(evidence.nextAction.contains("sealed exam-style practice"))
        #expect(!evidence.nextAction.contains("memory is 0%"))
    }
}
