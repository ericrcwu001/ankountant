import Foundation
import Testing
@testable import AnkiKit

// The pinned lease worked-example from rslib/src/ankountant/seed.rs
// (add_sealed_je_tbs). Carries answer_key + weight for four lines; the client
// must strip the answer_key and expose only id/label/weight.
private let anchorSteps = """
[{"id":"l1","answer_key":{"account":"ROU Asset","side":"dr","amount":10000},"weight":0.25},{"id":"l2","answer_key":{"account":"Lease Liability","side":"cr","amount":10000},"weight":0.25},{"id":"l3","answer_key":{"account":"Interest Expense","side":"dr","amount":500},"weight":0.25},{"id":"l4","answer_key":{"account":"Cash","side":"cr","amount":500},"weight":0.25}]
"""

// A research citation step as stored in the note (mirrors seed.rs
// section_item_steps): `accepted` lands in `answer_key`, plus the client-only
// extras kind/label/corpus_refs/granularity. The render model must strip the
// key and keep only the safe extras.
private let researchSteps = """
[{"id":"citation","kind":"citation","answer_key":["ASC 842-20-25-1","842-20-25-1","ASC 842-20-25"],"weight":1.0,"label":"Governing citation","corpus_refs":["asc-842-20-25-1"],"granularity":"paragraph"}]
"""

// A doc-review blank step as stored in the note. `answer_key` is the correct
// OPTION id and must never survive parsing; `options` are label-stripped.
private let docReviewSteps = """
[{"kind":"blank","id":"s1","label":"Callout 1","answer_key":"o3","correct_option":"o3","original_text":"Accounts receivable summarized by date of most recent purchase.","options":[{"id":"o1","kind":"keep","text":"Retain the original text."},{"id":"o2","kind":"delete","text":"Delete the text."},{"id":"o3","kind":"replace","text":"Accounts receivable aged by date due."}]}]
"""

// A doc-review exhibits array: a primary document (role:"document", body with a
// `<blank>` marker) plus a supporting table exhibit.
private let docReviewExhibits = """
[{"id":"doc","kind":"document","role":"document","title":"Audit Request List (Draft)","body":"1. <blank step=\\"s1\\">Accounts receivable summarized by date of most recent purchase.</blank>"},{"id":"ex1","kind":"table","title":"Trial balance","columns":["Item","Amount"],"rows":[["A","100"]]}]
"""

private struct JSONParseFailure: Error {}

private func parseObject(_ json: String) throws -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw JSONParseFailure()
    }
    return object
}

private func expectTbsParseError<T>(_ expected: String, _ body: () throws -> T) {
    do {
        _ = try body()
        Issue.record("Expected TbsParseError containing \(expected)")
    } catch let error as TbsParseError {
        #expect(error.localizedDescription.contains(expected))
    } catch {
        Issue.record("Expected TbsParseError containing \(expected), got \(error)")
    }
}

private func expectTbsSubmissionError<T>(_ expected: String, _ body: () throws -> T) {
    do {
        _ = try body()
        Issue.record("Expected TbsSubmissionError containing \(expected)")
    } catch let error as TbsSubmissionError {
        #expect(error.localizedDescription.contains(expected))
    } catch {
        Issue.record("Expected TbsSubmissionError containing \(expected), got \(error)")
    }
}

@Test func parseStepsOnAnchorJournalEntry() throws {
    let steps = try parseSteps(anchorSteps)

    #expect(steps.count == 4)
    #expect(steps.map(\.id) == ["l1", "l2", "l3", "l4"])
    #expect(steps.allSatisfy { $0.weight == 0.25 })
    // Labels default to the id when absent (the anchor has no label field).
    #expect(steps.map(\.label) == ["l1", "l2", "l3", "l4"])

    // The answer_key must not survive parsing, so grading stays
    // server-authoritative. RenderStep carries the render-only fields
    // (id/label/weight/kind/options/originalText/corpusRefs/placeholder) but
    // nothing named like an answer/correct key.
    let mirrored = Mirror(reflecting: steps[0]).children.compactMap(\.label)
    #expect(mirrored.contains("id"))
    #expect(mirrored.contains("label"))
    #expect(mirrored.contains("weight"))
    #expect(!mirrored.contains { $0.lowercased().contains("answer") })
    #expect(!mirrored.contains { $0.lowercased().contains("correct") })
}

@Test func parseStepsDefaultsWeightToOneOverN() throws {
    let steps = try parseSteps(#"[{"id":"a"},{"id":"b"},{"id":"c"}]"#)

    #expect(steps.count == 3)
    for step in steps {
        #expect(abs(step.weight - 1.0 / 3.0) < 1e-9)
    }
}

@Test func parseStepsFailsForMissingMalformedOrEmptyJson() {
    expectTbsParseError("steps_json is missing.") { try parseSteps(nil) }
    expectTbsParseError("steps_json is missing.") { try parseSteps("") }
    expectTbsParseError("steps_json must contain at least one step.") { try parseSteps("[]") }
    expectTbsParseError("Invalid steps_json:") { try parseSteps("not json") }
    expectTbsParseError("steps_json must be an array.") { try parseSteps("{\"id\":\"x\"}") }
    expectTbsParseError("Invalid steps_json[0]: must be an object") { try parseSteps("[1]") }
    expectTbsParseError("Invalid steps_json[0].id: missing step id") {
        try parseSteps(#"[{"answer_key":1}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].id: missing step id") {
        try parseSteps(#"[{"id":" ","answer_key":1}]"#)
    }
    expectTbsParseError("Invalid steps_json: duplicate step id: s1") {
        try parseSteps(#"[{"id":"s1"},{"id":"s1"}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].weight: must be a nonnegative finite number") {
        try parseSteps(#"[{"id":"a","weight":-0.1},{"id":"b","weight":1.1}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].weight: must be a nonnegative finite number") {
        try parseSteps(#"[{"id":"a","weight":null},{"id":"b"}]"#)
    }
    expectTbsParseError("Invalid steps_json: weights must sum to 1.0") {
        try parseSteps(#"[{"id":"a","weight":0.8},{"id":"b","weight":0.8}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options: must be an array") {
        try parseSteps(#"[{"id":"s1","options":"bad"}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options: must be an array") {
        try parseSteps(#"[{"id":"s1","kind":"blank"}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options: must contain at least one option") {
        try parseSteps(#"[{"id":"s1","kind":"blank","options":[]}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options[0]: must be an object") {
        try parseSteps(#"[{"id":"s1","options":[1]}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options[0].id: missing option id") {
        try parseSteps(#"[{"id":"s1","options":[{"text":"x"}]}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options[0].text: missing option text") {
        try parseSteps(#"[{"id":"s1","options":[{"id":"o1","text":""}]}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].options[0].kind: unknown option kind: maybe") {
        try parseSteps(#"[{"id":"s1","options":[{"id":"o1","text":"x","kind":"maybe"}]}]"#)
    }
    expectTbsParseError("Invalid steps_json[0].corpus_refs: must be an array") {
        try parseSteps(#"[{"id":"s1","corpus_refs":"asc"}]"#)
    }
}

@Test func parseExhibitsFailsForMissingOrMalformedJson() throws {
    #expect(try parseExhibits("[]").isEmpty)
    expectTbsParseError("exhibits_json is missing.") { try parseExhibits(nil) }
    expectTbsParseError("exhibits_json is missing.") { try parseExhibits("") }
    expectTbsParseError("Invalid exhibits_json:") { try parseExhibits("not json") }
    expectTbsParseError("exhibits_json must be an array.") { try parseExhibits("{\"id\":\"x\"}") }
    expectTbsParseError("Invalid exhibits_json[0]: must be an object") { try parseExhibits("[1]") }
    expectTbsParseError("Invalid exhibits_json[0].columns: must be an array") {
        try parseExhibits(#"[{"columns":"Item"}]"#)
    }
    expectTbsParseError("Invalid exhibits_json[0].rows[0]: must be an array") {
        try parseExhibits(#"[{"rows":[1]}]"#)
    }
    expectTbsParseError("Invalid exhibits_json[0].kind: unknown exhibit kind: chart") {
        try parseExhibits(#"[{"kind":"chart"}]"#)
    }
    #expect(try parseExhibits(#"[{"title":"T"}]"#).first?.kind == "text")
}

@Test func buildTbsModelParsesJournalEntry() throws {
    let model = try buildTbsModel(fields: [
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

@Test func tbsSearchFiltersByRenderableSimulationShape() {
    let search = tbsSearch(shape: .journalEntry, section: "FAR")

    #expect(search.contains("\"note:Ankountant TBS\""))
    #expect(search.contains("\"tbs_type:journal_entry\""))
    #expect(search.contains("deck:Ankountant::Sealed::FAR::*"))
}

@Test func buildTbsRevealModelFormatsJournalEntryKeys() throws {
    let reveal = try buildTbsRevealModel(
        fields: [
            "journal_entry",
            "Record the entry",
            "[]",
            anchorSteps,
            "ds::lease::finance",
            "ASC 842-20-35",
        ],
        tags: ["sec::FAR"]
    )

    #expect(reveal.section == "FAR")
    #expect(reveal.schemaTag == "ds::lease::finance")
    #expect(reveal.source == "ASC 842-20-35")
    #expect(reveal.steps[0].label == "l1")
    #expect(reveal.steps[0].correctText == "DR ROU Asset 10000")
}

@Test func buildTbsRevealModelResolvesDocReviewOptionText() throws {
    let reveal = try buildTbsRevealModel(
        fields: [
            "doc_review",
            "Review the document",
            docReviewExhibits,
            docReviewSteps,
            "ds::audit::evidence",
            "PCAOB AS 1105",
        ],
        tags: ["sec::AUD"]
    )

    #expect(reveal.section == "AUD")
    #expect(reveal.steps[0].label == "Callout 1")
    #expect(reveal.steps[0].correctText == "Accounts receivable aged by date due.")
}

@Test func buildTbsRevealModelJoinsResearchAcceptedCitations() throws {
    let reveal = try buildTbsRevealModel(
        fields: [
            "research",
            "Find support",
            "[]",
            researchSteps,
            "ds::lease::finance",
            "ASC 842-20-25-1",
        ],
        tags: ["sec::FAR"]
    )

    #expect(reveal.steps[0].label == "Governing citation")
    #expect(reveal.steps[0].correctText == "ASC 842-20-25-1 / 842-20-25-1 / ASC 842-20-25")
}

@Test func buildTbsModelRejectsUnknownShape() throws {
    expectTbsParseError("Unsupported tbs_type: totally_unknown") {
        try buildTbsModel(fields: ["totally_unknown", "p", "[]", anchorSteps])
    }
    #expect(try buildTbsModel(fields: ["numeric", "p", "[]", anchorSteps]).shape == .numeric)
}

@Test func buildTbsModelRejectsShortFields() {
    expectTbsParseError("Unsupported tbs_type: ") {
        try buildTbsModel(fields: [])
    }
    expectTbsParseError("Invalid prompt: missing prompt") {
        try buildTbsModel(fields: ["numeric", "", "[]", anchorSteps])
    }
    expectTbsParseError("Invalid prompt: missing prompt") {
        try buildTbsModel(fields: ["numeric", " ", "[]", anchorSteps])
    }
    expectTbsParseError("exhibits_json is missing.") {
        try buildTbsModel(fields: ["numeric", "p"])
    }
    expectTbsParseError("steps_json is missing.") {
        try buildTbsModel(fields: ["numeric", "p", "[]"])
    }
}

@Test func buildJeSubmissionShapesAmounts() throws {
    let json = try buildJeSubmission([
        JeLineInput(id: "l1", account: "ROU Asset", side: "dr", amount: " 10000.50 "),
        JeLineInput(id: "l2", account: "Cash", side: "cr", amount: ""),
    ])
    let steps = try #require(try parseObject(json)["steps"] as? [[String: Any]])
    #expect(steps.count == 2)

    let first = try #require(steps[0]["value"] as? [String: Any])
    #expect(steps[0]["id"] as? String == "l1")
    #expect(first["account"] as? String == "ROU Asset")
    #expect(first["side"] as? String == "dr")
    // A provided amount is a JSON number, never a string.
    #expect(first["amount"] as? Double == 10000.5)
    #expect(first["amount"] as? String == nil)

    let second = try #require(steps[1]["value"] as? [String: Any])
    #expect(second["account"] as? String == "Cash")
    #expect(second["side"] as? String == "cr")
    // An empty amount is the empty string, never a number.
    #expect(second["amount"] as? String == "")
    #expect(second["amount"] as? Double == nil)
}

@Test func buildJeSubmissionRejectsMalformedAmounts() {
    expectTbsSubmissionError("Amount for Line 1 must be a decimal number.") {
        try buildJeSubmission([
            JeLineInput(id: "l1", account: "ROU Asset", side: "dr", amount: "1,000"),
        ])
    }
}

@Test func buildNumericSubmissionShapesValues() throws {
    let json = try buildNumericSubmission([
        NumericCellInput(id: "c1", value: "-42.5"),
        NumericCellInput(id: "c2", value: "   "),
        NumericCellInput(id: "c3", value: ".25"),
    ])
    let steps = try #require(try parseObject(json)["steps"] as? [[String: Any]])
    #expect(steps.count == 3)

    #expect(steps[0]["id"] as? String == "c1")
    #expect(steps[0]["value"] as? Double == -42.5)
    #expect(steps[0]["value"] as? String == nil)

    #expect(steps[1]["id"] as? String == "c2")
    #expect(steps[1]["value"] as? String == "")
    #expect(steps[1]["value"] as? Double == nil)

    #expect(steps[2]["id"] as? String == "c3")
    #expect(steps[2]["value"] as? Double == 0.25)
}

@Test func buildNumericSubmissionRejectsMalformedValues() {
    expectTbsSubmissionError("Value for Cell 1 must be a decimal number.") {
        try buildNumericSubmission([NumericCellInput(id: "c1", label: "Cell 1", value: "NaN")])
    }
}

@Test func buildChoiceSubmissionWrapsChoice() throws {
    let choice = try parseObject(buildChoiceSubmission("Capitalize"))["choice"] as? String
    #expect(choice == "Capitalize")
}

@Test func buildConfusionRevealModelExposesCorrectTreatment() throws {
    let reveal = try buildConfusionRevealModel(
        fields: [
            "mcq",
            "Which treatment applies?",
            "[]",
            #"[{"id":"choice","answer_key":"Capitalize","weight":1}]"#,
            "ds::fixed_assets::capitalize",
            "ASC 360-10-30",
        ],
        setId: "capitalize_vs_expense"
    )

    #expect(reveal.correctText == "Capitalize")
    #expect(reveal.source == "ASC 360-10-30")
    #expect(reveal.schemaTag == "ds::fixed_assets::capitalize")
    #expect(reveal.setId == "capitalize_vs_expense")
}

@Test func buildConfusionRevealModelRejectsNonConfusionNotes() {
    expectTbsParseError("Unsupported tbs_type: numeric") {
        try buildConfusionRevealModel(fields: ["numeric", "", "[]", "[]"], setId: "set")
    }
}

@Test func buildConfusionRevealModelRejectsMalformedChoiceKeys() {
    expectTbsParseError("Invalid choice.answer_key: must be a non-empty string") {
        try buildConfusionRevealModel(
            fields: ["mcq", "", "[]", #"[{"id":"choice","answer_key":""}]"#],
            setId: "set"
        )
    }
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

// MARK: - Research shape

@Test func parseStepsResearchKeepsSafeExtrasStripsKey() throws {
    let steps = try parseSteps(researchSteps)

    #expect(steps.count == 1)
    let step = steps[0]
    #expect(step.id == "citation")
    #expect(step.kind == "citation")
    #expect(step.corpusRefs == ["asc-842-20-25-1"])
    #expect(step.weight == 1.0)
    #expect(step.options.isEmpty)

    // Neither the accepted-citation answer_key nor a correct_option may survive.
    let labels = Mirror(reflecting: step).children.compactMap(\.label)
    #expect(!labels.contains { $0.lowercased().contains("answer") })
    #expect(!labels.contains { $0.lowercased().contains("accept") })
    #expect(!labels.contains { $0.lowercased().contains("correct") })
}

@Test func buildResearchSubmissionTrimsCitation() throws {
    let citation = try parseObject(buildResearchSubmission("  ASC 842-20-25-1  "))["citation"] as? String
    #expect(citation == "ASC 842-20-25-1")
}

// MARK: - Doc-review shape

@Test func parseStepsDocReviewParsesLabelStrippedOptions() throws {
    let steps = try parseSteps(docReviewSteps)

    #expect(steps.count == 1)
    let blank = steps[0]
    #expect(blank.kind == "blank")
    #expect(blank.originalText == "Accounts receivable summarized by date of most recent purchase.")
    #expect(blank.options.map(\.id) == ["o1", "o2", "o3"])
    #expect(blank.options.map(\.kind) == ["keep", "delete", "replace"])
    #expect(blank.options.first?.text == "Retain the original text.")

    // An option is purely {id, text, kind} — nothing marks which one is correct.
    let optionLabels = Mirror(reflecting: blank.options[0]).children.compactMap(\.label).sorted()
    #expect(optionLabels == ["id", "kind", "text"])

    // The blank's answer_key / correct_option are stripped from the step too.
    let stepLabels = Mirror(reflecting: blank).children.compactMap(\.label)
    #expect(!stepLabels.contains { $0.lowercased().contains("answer") })
    #expect(!stepLabels.contains { $0.lowercased().contains("correct") })
}

@Test func parseExhibitsParsesTypedKindRoleAndTable() throws {
    let exhibits = try parseExhibits(docReviewExhibits)

    #expect(exhibits.count == 2)
    let document = exhibits.first { $0.role == "document" }
    #expect(document?.exhibitId == "doc")
    #expect(document?.kind == "document")
    #expect(document?.body.contains("<blank step=\"s1\">") == true)

    let table = exhibits.first { $0.kind == "table" }
    #expect(table?.columns == ["Item", "Amount"])
    #expect(table?.rows == [["A", "100"]])
}

@Test func buildStepsSubmissionShapesStringValues() throws {
    let json = try buildStepsSubmission([(id: "s1", value: " o2 "), (id: "s2", value: "o3")])
    let steps = try #require(try parseObject(json)["steps"] as? [[String: Any]])

    #expect(steps.count == 2)
    #expect(steps[0]["id"] as? String == "s1")
    #expect(steps[0]["value"] as? String == "o2")
    #expect(steps[0]["value"] as? Double == nil)
    #expect(steps[1]["id"] as? String == "s2")
    #expect(steps[1]["value"] as? String == "o3")
}

@Test func docReviewSubmissionRequiresEveryBlankSelection() throws {
    #expect(docReviewBlanksComplete([DocReviewBlankInput(id: "s1", selection: "o2")]))
    #expect(!docReviewBlanksComplete([DocReviewBlankInput(id: "s1")]))
    #expect(!docReviewBlanksComplete([]))
    do {
        _ = try buildStepsSubmission([(id: "s1", value: "")])
        Issue.record("Expected missing step selection error.")
    } catch let error as TbsSubmissionError {
        #expect(error == .missingStepSelection)
    }
}

@Test func segmentDocumentSplitsTextAndBlanks() {
    let body = "Recognize revenue <blank step=\"s1\">at signing</blank> today."
    let segments = segmentDocument(body)

    #expect(segments.count == 3)
    guard case let .text(_, first) = segments[0] else {
        Issue.record("expected leading text segment")
        return
    }
    #expect(first == "Recognize revenue ")
    guard case let .blank(_, blankId, original) = segments[1] else {
        Issue.record("expected a blank segment")
        return
    }
    #expect(blankId == "s1")
    #expect(original == "at signing")
    guard case let .text(_, last) = segments[2] else {
        Issue.record("expected trailing text segment")
        return
    }
    #expect(last == " today.")
}

@Test func segmentDocumentHandlesEmptyAndPlain() {
    #expect(segmentDocument(nil).isEmpty)
    #expect(segmentDocument("").isEmpty)
    let plain = segmentDocument("plain text with no markers")
    #expect(plain.count == 1)
    guard case let .text(_, text) = plain[0] else {
        Issue.record("expected a single text segment")
        return
    }
    #expect(text == "plain text with no markers")
}

// MARK: - Section + model routing

@Test func buildTbsModelRoutesResearchAndSection() throws {
    let model = try buildTbsModel(
        fields: ["research", "Cite the standard", "[]", researchSteps],
        tags: ["ds::foo", "sec::REG"]
    )
    #expect(model.shape == .research)
    #expect(model.section == "REG")
    #expect(model.document == nil)
    #expect(model.steps.first?.kind == "citation")
}

@Test func buildTbsModelRoutesDocReviewWithDocumentAndSection() throws {
    let model = try buildTbsModel(
        fields: ["doc_review", "Review the list", docReviewExhibits, docReviewSteps],
        tags: ["sec::AUD"]
    )
    #expect(model.shape == .docReview)
    #expect(model.section == "AUD")
    #expect(model.document?.contains("<blank step=\"s1\">") == true)
    // The primary document is excluded from the exhibits pane; the table stays.
    #expect(!paneExhibits(model).contains { $0.role == "document" })
    #expect(paneExhibits(model).contains { $0.kind == "table" })
}

@Test func buildTbsModelRejectsMalformedDocReviewDocument() {
    expectTbsParseError("Invalid doc_review.document: missing document exhibit") {
        try buildTbsModel(
            fields: [
                "doc_review",
                "Review the list",
                #"[{"title":"Supporting exhibit","body":"facts"}]"#,
                docReviewSteps,
            ]
        )
    }
    expectTbsParseError("Invalid doc_review.document: no blank markers") {
        try buildTbsModel(
            fields: [
                "doc_review",
                "Review the list",
                #"[{"id":"doc","kind":"document","role":"document","title":"Doc","body":"plain text"}]"#,
                docReviewSteps,
            ]
        )
    }
    expectTbsParseError("Invalid doc_review.document: blank missing has no step") {
        try buildTbsModel(
            fields: [
                "doc_review",
                "Review the list",
                #"[{"id":"doc","kind":"document","role":"document","title":"Doc","body":"<blank step=\"missing\">x</blank>"}]"#,
                docReviewSteps,
            ]
        )
    }
}

@Test func sectionFromTagsResolvesKnownAndFallsBackToFAR() throws {
    #expect(try sectionFromTags(["sec::AUD"]) == "AUD")
    #expect(try sectionFromTags(["ds::x", "sec::BAR"]) == "BAR")
    #expect(try sectionFromTags(["sec:: reg "]) == "REG")
    #expect(try sectionFromTags([]) == "FAR")
    expectTbsParseError("Unknown CPA section tag: sec::ZZZ") {
        try sectionFromTags(["sec::ZZZ"])
    }
    #expect(try buildTbsModel(fields: ["numeric", "p", "[]", anchorSteps]).section == "FAR")
}

// MARK: - Bundled literature corpus (client-side research search)

@Test func searchCorpusFiltersByAndedTerms() {
    let entries = [
        CorpusEntry(id: "a", citation: "ASC 842-20-25-1", title: "Leases", body: "right-of-use asset", tags: ["lease"]),
        CorpusEntry(id: "b", citation: "IRC §162(a)", title: "Business expenses", body: "ordinary and necessary", verbatim: true, tags: ["deduction"]),
    ]
    #expect(searchCorpus(entries, query: "").count == 2)              // empty → all
    #expect(searchCorpus(entries, query: "lease").map(\.id) == ["a"]) // tag/body hit
    #expect(searchCorpus(entries, query: "ordinary necessary").map(\.id) == ["b"]) // AND
    #expect(searchCorpus(entries, query: "nonexistent").isEmpty)
}

@Test func loadLiteratureCorpusDecodesBundledResource() throws {
    let corpus = try loadLiteratureCorpus()

    #expect(!corpus.isEmpty)
    // FAR ships ASC paraphrase (cite-only); REG ships verbatim IRC text.
    #expect(try corpusForSection(corpus, "FAR").contains { $0.citation == "ASC 842-20-25-1" && !$0.verbatim })
    #expect(try corpusForSection(corpus, " reg ").contains { $0.verbatim })
    // The ASC deep link is mapped from the JSON `deep_link` snake_case key.
    let asc = try corpusForSection(corpus, "FAR").first { $0.citation == "ASC 842-20-25-1" }
    #expect(asc?.deepLink?.contains("asc.fasb.org") == true)
    #expect(throws: LiteratureCorpusError.unknownSection("NOPE")) {
        try corpusForSection(corpus, "NOPE")
    }
}

@Test func corpusEntryRejectsMalformedOptionalMetadata() {
    let json = #"{"id":"x","citation":"C","title":"T","body":"B","verbatim":"yes"}"#
    do {
        _ = try JSONDecoder().decode(CorpusEntry.self, from: Data(json.utf8))
        Issue.record("Expected malformed corpus entry metadata to throw")
    } catch {
        #expect(!error.localizedDescription.isEmpty)
    }
}
