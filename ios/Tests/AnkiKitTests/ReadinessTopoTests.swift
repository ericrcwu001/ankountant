// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Testing
@testable import AnkiKit

/// Pure-logic tests for the summit Home: the ≥75 invariant (Constraint 1), the
/// abstain gate, the section enum, and the shared formatters. No UI / simulator
/// needed.
@Suite("Readiness topography")
struct ReadinessTopoTests {
    private func band(
        abstain: Bool = false,
        low: Double = 0,
        high: Double = 0,
        point: Double = 0,
        confidence: String = "Med",
        coverage: Double = 1,
        generatedAt: Int64 = 1_704_067_200,
        reasons: [String]? = nil
    ) -> ReadinessBand {
        ReadinessBand(
            abstain: abstain,
            reason: abstain ? "insufficient volume" : "",
            bandLow: low,
            bandHigh: high,
            pointEstimate: point,
            confidence: confidence,
            coverage: coverage,
            generatedAt: generatedAt,
            reasons: abstain ? [] : (reasons ?? ["Coverage: 100% of topics; 188 sealed attempts"])
        )
    }

    private func expectValidationError(_ expected: ReadinessValidationError, _ band: ReadinessBand) {
        do {
            _ = try validatedReadinessBand(band)
            Issue.record("Expected readiness validation error \(expected).")
        } catch let error as ReadinessValidationError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected readiness validation error \(error).")
        }
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

    // MARK: CPASection

    @Test func homeOrderAndCodes() {
        #expect(CPASection.homeOrder == [.far, .aud, .reg, .tcp, .isc])
        #expect(CPASection.far.code == "FAR")
        #expect(CPASection.tcp.displayName == "Tax Compliance and Planning")
        #expect(CPASection(code: "AUD") == .aud)
        #expect(CPASection(code: "XX") == nil)
        #expect(CPASection.allCases == [.aud, .far, .reg, .bar, .isc, .tcp])
        #expect(CPASection.practiceOrder == CPASection.allCases)
        #expect(!CPASection.homeOrder.contains(.bar))
        #expect(CPASection.practiceOrder.contains(.bar))
    }

    // MARK: Formatters

    @Test func formatters() {
        #expect(scoreWithRange(0.62, low: 0.54, high: 0.70) == "62% (54–70%)")
        #expect(scoreWithRange(0.62, low: 0.62, high: 0.62) == "62%")
        #expect(scoreWithRange(nil, low: 0, high: 0) == "insufficient")
        #expect(formatPercent(0.6) == "60%")
        #expect(readinessBandLabel(band(low: 60, high: 84, point: 72)) == "60–84")
    }

    @Test func readinessValidationRequiresValidBandsAndEvidence() throws {
        let valid = try validatedReadinessBand(
            band(
                low: 62,
                high: 78,
                point: 70,
                confidence: " High ",
                reasons: [" Coverage: 75% of topics; 40 sealed attempts "]
            )
        )
        #expect(valid.confidence == "High")
        #expect(valid.reasons == ["Coverage: 75% of topics; 40 sealed attempts"])
        expectValidationError(.invalidBand, band(low: 62, high: 62, point: 62))
        expectValidationError(.pointOutsideBand, band(low: 62, high: 78, point: 90))
        expectValidationError(.missingConfidence, band(low: 62, high: 78, point: 70, confidence: ""))
        expectValidationError(.missingEvidenceReasons, band(low: 62, high: 78, point: 70, reasons: []))
        expectValidationError(.missingGeneratedAt, band(low: 62, high: 78, point: 70, generatedAt: 0))
        expectValidationError(.invalidCoverage, band(low: 62, high: 78, point: 70, coverage: 1.1))
        expectValidationError(.insufficientCoverage, band(low: 62, high: 78, point: 70, coverage: 0.4))
        expectValidationError(
            .missingAbstainReason,
            ReadinessBand(abstain: true, reason: "", bandLow: 0, bandHigh: 0, confidence: "")
        )
    }

    @Test func topicExtensions() {
        let warn = TopicScoreModel(
            setId: "capitalize_vs_expense",
            memory: 0.8,
            performance: 0.5,
            gap: 0.30,
            memoryInsufficient: false,
            performanceLow: 0.4,
            performanceHigh: 0.6
        )
        #expect(warn.gapWarning)
        #expect(warn.displayName == "Capitalize Vs Expense")
        let ok = TopicScoreModel(
            setId: "x",
            memory: 0.8,
            performance: 0.7,
            gap: 0.10,
            memoryInsufficient: false,
            performanceLow: 0.6,
            performanceHigh: 0.8
        )
        #expect(!ok.gapWarning)
        let noPerf = TopicScoreModel(setId: "x", memory: 0.8, performance: 0, gap: 0, memoryInsufficient: false, performanceLow: 0, performanceHigh: 0)
        #expect(noPerf.performanceInsufficient)
        #expect(!noPerf.gapWarning)
    }

    @Test func gapsToCloseCount() {
        let summary = ReadinessSummary(band: band(), topics: [
            TopicScoreModel(setId: "a", memory: 0.9, performance: 0.5, gap: 0.40, memoryInsufficient: false, performanceLow: 0.4, performanceHigh: 0.6),
            TopicScoreModel(setId: "b", memory: 0.6, performance: 0.5, gap: 0.10, memoryInsufficient: false, performanceLow: 0.4, performanceHigh: 0.6),
            TopicScoreModel(setId: "c", memory: 0.9, performance: 0.6, gap: 0.30, memoryInsufficient: false, performanceLow: 0.5, performanceHigh: 0.7),
            TopicScoreModel(setId: "d", memory: 0.9, performance: 0, gap: 0.90, memoryInsufficient: false, performanceLow: 0, performanceHigh: 0),
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
                TopicScoreModel(setId: "tax_timing", memory: 0, performance: 0.42, gap: 0, memoryInsufficient: true, performanceLow: 0.32, performanceHigh: 0.52),
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
                TopicScoreModel(setId: "leases", memory: 0.9, performance: 0.52, gap: 0.38, memoryInsufficient: false, performanceLow: 0.42, performanceHigh: 0.62),
                TopicScoreModel(setId: "tax_timing", memory: 0.7, performance: 0.51, gap: 0.19, memoryInsufficient: false, performanceLow: 0.41, performanceHigh: 0.61),
            ]
        )
        #expect(evidence.nextAction.contains("Leases"))
        #expect(evidence.nextAction.contains("memory is 90%"))
        #expect(evidence.missingData.first?.contains("No hard blockers") == true)
    }

    @Test func readinessEvidencePrioritizesInsufficientVolumeBeforeGapDrills() {
        let band = ReadinessBand(
            abstain: true,
            reason: "insufficient volume",
            bandLow: 0,
            bandHigh: 0,
            confidence: "",
            coverage: 1
        )
        let evidence = readinessEvidence(
            band: band,
            topics: [
                TopicScoreModel(setId: "leases", memory: 0.9, performance: 0.52, gap: 0.38, memoryInsufficient: false, performanceLow: 0.42, performanceHigh: 0.62),
            ]
        )
        #expect(evidence.nextAction.contains("20"))
        #expect(evidence.nextAction.contains("sealed exam-style attempts"))
        #expect(!evidence.nextAction.contains("confusion-set drill"))
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
                TopicScoreModel(setId: "tax_timing", memory: 0, performance: 0.42, gap: 0.38, memoryInsufficient: true, performanceLow: 0.32, performanceHigh: 0.52),
            ]
        )
        #expect(evidence.nextAction.contains("sealed exam-style practice"))
        #expect(!evidence.nextAction.contains("memory is 0%"))
    }

    @Test func readinessEvidenceDoesNotInventPerformanceValueWithoutSealedEvidence() {
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
                TopicScoreModel(
                    setId: "leases",
                    memory: 0.82,
                    performance: 0,
                    gap: 0.82,
                    memoryInsufficient: false,
                    memoryLow: 0.75,
                    memoryHigh: 0.9,
                    performanceLow: 0,
                    performanceHigh: 0
                ),
            ]
        )
        #expect(evidence.missingData.joined(separator: " ").contains("Performance has no sealed evidence for Leases"))
        #expect(evidence.nextAction.contains("performance has no sealed evidence yet"))
        #expect(!evidence.nextAction.contains("performance is 0%"))
    }

    @Test func scoreSummariesExposeThreeRangeAwareSignals() {
        let summary = ReadinessSummary(
            band: band(low: 74, high: 85, point: 80, confidence: "High"),
            topics: [
                TopicScoreModel(
                    setId: "leases",
                    memory: 0.8,
                    performance: 0.5,
                    gap: 0.3,
                    memoryInsufficient: false,
                    memoryLow: 0.7,
                    memoryHigh: 0.9,
                    performanceLow: 0.4,
                    performanceHigh: 0.6
                ),
                TopicScoreModel(
                    setId: "tax_timing",
                    memory: 0.6,
                    performance: 0.7,
                    gap: 0.1,
                    memoryInsufficient: false,
                    memoryLow: 0.5,
                    memoryHigh: 0.7,
                    performanceLow: 0.6,
                    performanceHigh: 0.8
                ),
            ]
        )

        let scores = summary.scoreSummaries
        #expect(scores.map(\.label) == ["Memory", "Performance", "Readiness"])
        #expect(scores[0].valueText == "70%")
        #expect(scores[0].rangeText == "60–80%")
        #expect(scores[0].detailText == "Topic average")
        #expect(scores[1].valueText == "60%")
        #expect(scores[1].rangeText == "50–70%")
        #expect(scores[1].detailText == "Sealed tasks")
        #expect(scores[2].valueText == "74–85")
        #expect(scores[2].rangeText == "CPA range")
        #expect(scores[2].detailText == "High confidence")
        #expect(scores[2].fraction == nil)
        #expect(scores[2].rangeFraction == TopoScale.height(forScore: 74)...TopoScale.height(forScore: 85))
        #expect(scores.allSatisfy { $0.available })
    }

    @Test func scoreSummariesWithholdReadinessButKeepAvailableSignals() {
        let summary = ReadinessSummary(
            band: band(abstain: true, confidence: ""),
            topics: [
                TopicScoreModel(
                    setId: "leases",
                    memory: 0.8,
                    performance: 0,
                    gap: 0,
                    memoryInsufficient: false,
                    memoryLow: 0.7,
                    memoryHigh: 0.9,
                    performanceLow: 0,
                    performanceHigh: 0
                ),
            ]
        )

        let scores = summary.scoreSummaries
        #expect(scores[0].valueText == "80%")
        #expect(scores[0].rangeText == "70–90%")
        #expect(scores[0].available)
        #expect(scores[1].valueText == "—")
        #expect(scores[1].rangeText == "insufficient")
        #expect(!scores[1].available)
        #expect(scores[2].valueText == "—")
        #expect(scores[2].rangeText == "withheld")
        #expect(scores[2].detailText == "insufficient volume")
        #expect(!scores[2].available)
    }

    @Test func pendingScoreSummariesDifferentiateLoadingAndLoadedEmptyStates() {
        let loading = ReadinessScoreSummary.pendingSummaries(loaded: false)
        let loaded = ReadinessScoreSummary.pendingSummaries(loaded: true)

        #expect(loading.map(\.rangeText) == ["loading", "loading", "loading"])
        #expect(loading.map(\.valueText) == ["...", "...", "..."])
        #expect(loaded.map(\.rangeText) == ["insufficient", "insufficient", "insufficient"])
        #expect(loaded.map(\.valueText) == ["—", "—", "—"])
        #expect(!loading.contains { $0.available })
        #expect(!loaded.contains { $0.available })
    }
}
