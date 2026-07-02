import Foundation
import Testing
@testable import AnkiKit

// The pinned lease worked-example from rslib/src/ankountant/seed.rs
// (add_sealed_je_tbs). Carries answer_key + weight for four lines; the client
// must strip the answer_key and expose only id/label/weight.
private let anchorSteps = """
[{"id":"l1","answer_key":{"account":"ROU Asset","side":"dr","amount":10000},"weight":0.25},{"id":"l2","answer_key":{"account":"Lease Liability","side":"cr","amount":10000},"weight":0.25},{"id":"l3","answer_key":{"account":"Interest Expense","side":"dr","amount":500},"weight":0.25},{"id":"l4","answer_key":{"account":"Cash","side":"cr","amount":500},"weight":0.25}]
"""

private struct JSONParseFailure: Error {}

private func parseObject(_ json: String) throws -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw JSONParseFailure()
    }
    return object
}

@Test func parseStepsOnAnchorJournalEntry() {
    let steps = parseSteps(anchorSteps)

    #expect(steps.count == 4)
    #expect(steps.map(\.id) == ["l1", "l2", "l3", "l4"])
    #expect(steps.allSatisfy { $0.weight == 0.25 })
    // Labels default to the id when absent (the anchor has no label field).
    #expect(steps.map(\.label) == ["l1", "l2", "l3", "l4"])

    // The answer_key must not survive parsing: RenderStep can only carry
    // id/label/weight, so grading stays server-authoritative.
    let mirrored = Mirror(reflecting: steps[0]).children.compactMap(\.label)
    #expect(mirrored == ["id", "label", "weight"])
}

@Test func parseStepsDefaultsWeightToOneOverN() {
    let steps = parseSteps(#"[{"id":"a"},{"id":"b"},{"id":"c"}]"#)

    #expect(steps.count == 3)
    for step in steps {
        #expect(abs(step.weight - 1.0 / 3.0) < 1e-9)
    }
}

@Test func parseStepsReturnsEmptyForNonArrayOrEmpty() {
    #expect(parseSteps(nil).isEmpty)
    #expect(parseSteps("").isEmpty)
    #expect(parseSteps("[]").isEmpty)
    #expect(parseSteps("not json").isEmpty)
    #expect(parseSteps("{\"id\":\"x\"}").isEmpty)
}

@Test func buildTbsModelParsesJournalEntry() {
    let model = buildTbsModel(fields: [
        "journal_entry",
        "Record the entry",
        #"[{"title":"T","body":"B"}]"#,
        anchorSteps,
    ])

    #expect(model.shape == .journalEntry)
    #expect(model.prompt == "Record the entry")
    #expect(model.exhibits.count == 1)
    #expect(model.exhibits.first?.title == "T")
    #expect(model.exhibits.first?.body == "B")
    #expect(model.steps.count == 4)
}

@Test func buildTbsModelShapeFallback() {
    #expect(buildTbsModel(fields: ["totally_unknown", "p", "[]", "[]"]).shape == .journalEntry)
    #expect(buildTbsModel(fields: ["numeric", "p", "[]", "[]"]).shape == .numeric)
}

@Test func buildTbsModelToleratesShortFields() {
    let model = buildTbsModel(fields: [])

    #expect(model.shape == .journalEntry)
    #expect(model.prompt == "")
    #expect(model.exhibits.isEmpty)
    #expect(model.steps.isEmpty)
}

@Test func buildJeSubmissionShapesAmounts() throws {
    let json = buildJeSubmission([
        JeLineInput(id: "l1", account: "ROU Asset", side: "dr", amount: "10000"),
        JeLineInput(id: "l2", account: "Cash", side: "cr", amount: ""),
    ])
    let steps = try #require(try parseObject(json)["steps"] as? [[String: Any]])
    #expect(steps.count == 2)

    let first = try #require(steps[0]["value"] as? [String: Any])
    #expect(steps[0]["id"] as? String == "l1")
    #expect(first["account"] as? String == "ROU Asset")
    #expect(first["side"] as? String == "dr")
    // A provided amount is a JSON number, never a string.
    #expect(first["amount"] as? Double == 10000)
    #expect(first["amount"] as? String == nil)

    let second = try #require(steps[1]["value"] as? [String: Any])
    #expect(second["account"] as? String == "Cash")
    #expect(second["side"] as? String == "cr")
    // An empty amount is the empty string, never a number.
    #expect(second["amount"] as? String == "")
    #expect(second["amount"] as? Double == nil)
}

@Test func buildNumericSubmissionShapesValues() throws {
    let json = buildNumericSubmission([
        NumericCellInput(id: "c1", value: "42"),
        NumericCellInput(id: "c2", value: ""),
    ])
    let steps = try #require(try parseObject(json)["steps"] as? [[String: Any]])
    #expect(steps.count == 2)

    #expect(steps[0]["id"] as? String == "c1")
    #expect(steps[0]["value"] as? Double == 42)
    #expect(steps[0]["value"] as? String == nil)

    #expect(steps[1]["id"] as? String == "c2")
    #expect(steps[1]["value"] as? String == "")
    #expect(steps[1]["value"] as? Double == nil)
}

@Test func buildChoiceSubmissionWrapsChoice() throws {
    let choice = try parseObject(buildChoiceSubmission("Capitalize"))["choice"] as? String
    #expect(choice == "Capitalize")
}

@Test func stripConfusionSlugRemovesTrailingDevSlug() {
    #expect(
        stripConfusionSlug("Which treatment applies? (capitalize_vs_expense q0)")
            == "Which treatment applies?"
    )
}

@Test func stripConfusionSlugLeavesPlainPromptUnchanged() {
    let plain = "Which treatment applies?"
    #expect(stripConfusionSlug(plain) == plain)
}
