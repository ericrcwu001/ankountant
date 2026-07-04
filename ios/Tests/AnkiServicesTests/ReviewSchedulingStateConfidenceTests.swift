import AnkiKit
import AnkiProto
import AnkiServices
import Foundation
import Testing

@Suite("Review scheduling confidence")
struct ReviewSchedulingStateConfidenceTests {
    @Test
    func recordingConfidenceCopiesCurrentCustomDataIntoNextStates() throws {
        let updated = try states(currentCustomData: #"{"existing":7}"#)
            .recordingConfidence("Confident")

        #expect(try customData(updated.current)["cf"] == nil)

        for token in [updated.again, updated.hard, updated.good, updated.easy] {
            let data = try customData(token)
            #expect(data["existing"] as? Int == 7)
            #expect(data["cf"] as? String == "Confident")
        }
    }

    @Test
    func recordingConfidenceIgnoresMissingOrBlankConfidence() throws {
        let original = try states(currentCustomData: #"{"existing":7}"#)
        let withoutConfidence = try original.recordingConfidence(nil)
        let withBlankConfidence = try original.recordingConfidence("  ")

        #expect(try customData(withoutConfidence.again).isEmpty)
        #expect(try customData(withBlankConfidence.good).isEmpty)
    }

    @Test
    func recordingConfidenceRejectsMalformedCurrentCustomData() throws {
        #expect(throws: ReviewSchedulingStateConfidenceError.self) {
            try states(currentCustomData: "not json").recordingConfidence("Guess")
        }

        #expect(throws: ReviewSchedulingStateConfidenceError.nonObjectCustomData) {
            try states(currentCustomData: "[]").recordingConfidence("Guess")
        }
    }

    private func states(currentCustomData: String = "") throws -> ReviewSchedulingStates {
        try ReviewSchedulingStates(
            current: token(customData: currentCustomData),
            again: token(),
            hard: token(),
            good: token(),
            easy: token()
        )
    }

    private func token(customData: String = "") throws -> SchedulingStateToken {
        var state = Anki_Scheduler_SchedulingState()
        state.customData = customData
        return SchedulingStateToken(try state.serializedData())
    }

    private func customData(_ token: SchedulingStateToken) throws -> [String: Any] {
        let state = try Anki_Scheduler_SchedulingState(serializedBytes: token.bytes)
        guard !state.customData.isEmpty else { return [:] }
        return try #require(JSONSerialization.jsonObject(with: Data(state.customData.utf8)) as? [String: Any])
    }
}
