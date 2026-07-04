import Testing
import AnkiKit

@Suite("Readiness score summary")
struct ReadinessScoreSummaryTests {
    @Test func homeScoreSummariesExposeThreeSignalsWithRanges() {
        let summary = ReadinessSummary(
            band: ReadinessBand(
                abstain: false,
                reason: "",
                bandLow: 74,
                bandHigh: 85,
                pointEstimate: 80,
                confidence: "High",
                coverage: 1,
                reasons: ["Coverage: 100% of topics; 188 sealed attempts"]
            ),
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
        #expect(scores.map(\.rangeText) == ["60–80%", "50–70%", "74–85"])
        #expect(scores.allSatisfy { $0.available })
    }

    @Test func homeScoreSummariesWithholdReadinessWithoutHidingMemorySignal() {
        let summary = ReadinessSummary(
            band: ReadinessBand(
                abstain: true,
                reason: "insufficient volume",
                bandLow: 0,
                bandHigh: 0,
                confidence: ""
            ),
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
        #expect(scores[1].rangeText == "insufficient")
        #expect(!scores[1].available)
        #expect(scores[2].rangeText == "withheld")
        #expect(!scores[2].available)
    }

    @Test func readinessEvidenceIncludesLastUpdatedLine() {
        let evidence = readinessEvidence(
            band: ReadinessBand(
                abstain: false,
                reason: "",
                bandLow: 74,
                bandHigh: 85,
                pointEstimate: 80,
                confidence: "High",
                coverage: 1,
                generatedAt: 1_704_067_200,
                reasons: ["Coverage: 100% of topics; 188 sealed attempts"]
            ),
            topics: []
        )

        #expect(evidence.updatedAtLine.hasPrefix("Last updated "))
        #expect(!evidence.updatedAtLine.contains("unavailable"))
    }

    @Test func readinessEvidenceReportsMissingGeneratedTime() {
        let evidence = readinessEvidence(
            band: ReadinessBand(
                abstain: true,
                reason: "insufficient volume",
                bandLow: 0,
                bandHigh: 0,
                confidence: "",
                generatedAt: 0
            ),
            topics: []
        )

        #expect(evidence.updatedAtLine == "Last updated time unavailable; refresh readiness after more graded evidence is logged.")
    }
}
