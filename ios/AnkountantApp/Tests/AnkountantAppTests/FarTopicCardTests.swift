import Testing
import AnkiKit
@testable import AnkountantApp

@Suite("FAR topic cards")
struct FarTopicCardTests {
    @Test func unprovenTopicsStayOnBaseline() throws {
        let cards = FarTopicCard.build(from: ReadinessSummary(
            band: ReadinessBand(abstain: true, reason: "insufficient volume", bandLow: 0, bandHigh: 0, confidence: ""),
            topics: [
                TopicScoreModel(
                    setId: "operating_vs_finance_lease",
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
        ))

        let leases = try #require(cards.first { $0.setId == "operating_vs_finance_lease" })
        #expect(leases.height == 0)
        #expect(leases.performance == nil)
        #expect(leases.performanceLabel == "—")
        #expect(leases.isUnproven)
    }

    @Test func provenTopicsUseSealedPerformanceAsPeakHeight() throws {
        let cards = FarTopicCard.build(from: ReadinessSummary(
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
            topics: [
                TopicScoreModel(
                    setId: "operating_vs_finance_lease",
                    memory: 0.8,
                    performance: 0.52,
                    gap: 0.28,
                    memoryInsufficient: false,
                    memoryLow: 0.7,
                    memoryHigh: 0.9,
                    performanceLow: 0.42,
                    performanceHigh: 0.62
                ),
            ]
        ))

        let leases = try #require(cards.first { $0.setId == "operating_vs_finance_lease" })
        #expect(leases.height == 0.52)
        #expect(leases.performance == 52)
        #expect(leases.performanceLabel == "52%")
        #expect(!leases.isUnproven)
        #expect(leases.accessibilityLabel == "Leases, sealed performance 52%")
    }
}
