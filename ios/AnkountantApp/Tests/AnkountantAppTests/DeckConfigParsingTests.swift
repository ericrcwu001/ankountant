import Testing
@testable import AnkountantApp

@Suite("Deck config parsing")
struct DeckConfigParsingTests {
    @Test func stepsAcceptMinutesHoursDaysAndBareMinutes() throws {
        #expect(try parseDeckConfigSteps("1m 2h, 3d 4") == [1, 120, 4320, 4].map(Float.init))
    }

    @Test func stepsRejectMalformedTokens() {
        #expect(throws: DeckConfigParseError.invalidStep("10x")) {
            try parseDeckConfigSteps("1m 10x")
        }
    }

    @Test func weightsAcceptWhitespaceAndCommas() throws {
        #expect(try parseDeckConfigWeights("0.1, 2 3.5\n4") == [Float(0.1), 2, 3.5, 4])
    }

    @Test func weightsRejectMalformedTokens() {
        #expect(throws: DeckConfigParseError.invalidWeight("bad")) {
            try parseDeckConfigWeights("0.1 bad 0.3")
        }
    }
}
