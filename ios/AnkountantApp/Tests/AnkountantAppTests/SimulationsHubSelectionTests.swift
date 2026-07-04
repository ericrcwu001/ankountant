import Testing
import Foundation
import AnkiKit
@testable import AnkountantApp

@Suite("Simulation hub selection")
struct SimulationsHubSelectionTests {
    private let order: [TbsShape] = [.journalEntry, .numeric, .research, .docReview]

    @Test func keepsCurrentShapeWhenStillAvailable() {
        let tasks = [
            TbsTaskSummary(noteId: 1, shape: .journalEntry, prompt: "Journal"),
            TbsTaskSummary(noteId: 2, shape: .research, prompt: "Research"),
        ]

        #expect(simulationShapeAfterLoad(current: .research, tasks: tasks, order: order) == .research)
    }

    @Test func movesToFirstAvailableShapeWhenCurrentIsEmpty() {
        let tasks = [
            TbsTaskSummary(noteId: 1, shape: .numeric, prompt: "Numeric"),
            TbsTaskSummary(noteId: 2, shape: .research, prompt: "Research"),
        ]

        #expect(simulationShapeAfterLoad(current: .docReview, tasks: tasks, order: order) == .numeric)
    }

    @Test func keepsCurrentShapeWhenNoTasksExist() {
        #expect(simulationShapeAfterLoad(current: .docReview, tasks: [], order: order) == .docReview)
    }

    @Test func availableConfusionSectionsKeepsOnlySectionsWithItems() {
        let counts: [CPASection: Int] = [
            .aud: 0,
            .far: 12,
            .reg: 1,
            .bar: 0,
        ]

        #expect(availableConfusionSections(counts, order: CPASection.practiceOrder) == [.far, .reg])
    }

    @Test func confusionCountLabelPluralizes() {
        #expect(confusionCountLabel(0) == "0 items")
        #expect(confusionCountLabel(1) == "1 item")
        #expect(confusionCountLabel(2) == "2 items")
    }

    @Test func tbsShapeLabelsKeepSegmentLabelsShortAndMenuLabelsComplete() {
        #expect(tbsShapeDisplayLabel(.docReview) == "Document review")
        #expect(tbsShapeSegmentLabel(.docReview) == "Review")
        #expect(tbsShapeMenuLabel(.docReview, taskCount: 2) == "Document review · 2 simulations")
        #expect(tbsShapeMenuLabel(.numeric, taskCount: 1) == "Numeric · 1 simulation")
    }

    @Test func tbsTaskCountFiltersByShape() {
        let tasks = [
            TbsTaskSummary(noteId: 1, shape: .journalEntry, prompt: "Journal"),
            TbsTaskSummary(noteId: 2, shape: .numeric, prompt: "Numeric"),
            TbsTaskSummary(noteId: 3, shape: .numeric, prompt: "Another numeric"),
        ]

        #expect(tbsTaskCount(for: .journalEntry, in: tasks) == 1)
        #expect(tbsTaskCount(for: .numeric, in: tasks) == 2)
        #expect(tbsTaskCount(for: .research, in: tasks) == 0)
    }

    @Test func confusionCompletionReadinessLinkTargetsKnownSection() {
        #expect(confusionReadinessSection(after: .aud) == .aud)
        #expect(confusionReadinessButtonLabel(for: .aud) == "View AUD readiness")
    }

    @Test func allSectionConfusionCompletionUsesFarReadinessAnchor() {
        #expect(confusionReadinessSection(after: nil) == .far)
        #expect(confusionReadinessButtonLabel(for: nil) == "View FAR readiness")
    }

    @Test func hubHasContentWhenEitherTbsOrConfusionExists() {
        let task = TbsTaskSummary(noteId: 1, shape: .journalEntry, prompt: "Journal")

        #expect(simulationsHubHasContent(tasks: [task], allConfusionCount: 0))
        #expect(simulationsHubHasContent(tasks: [], allConfusionCount: 1))
        #expect(!simulationsHubHasContent(tasks: [], allConfusionCount: 0))
    }

    @Test func revealResultStateUsesBackendResult() {
        let step = StepReveal(id: "line-1", label: "Line 1", correctText: "Dr Cash 100")

        #expect(simulationRevealResultState(
            for: step,
            results: [PerformanceStepResult(id: "line-1", correct: true, weight: 1)]
        ) == .correct)
        #expect(simulationRevealResultState(
            for: step,
            results: [PerformanceStepResult(id: "line-1", correct: false, weight: 1)]
        ) == .incorrect)
    }

    @Test func revealResultStateKeepsMissingRowsUngraded() {
        let step = StepReveal(id: "line-2", label: "Line 2", correctText: "Cr Cash 100")

        #expect(simulationRevealResultState(
            for: step,
            results: [PerformanceStepResult(id: "line-1", correct: false, weight: 1)]
        ) == .ungraded)
    }

    @Test func journalEntryAccountsIncludeSeededAndCommonChoices() {
        #expect(Set(journalEntryAccounts).count == journalEntryAccounts.count)
        #expect(journalEntryAccounts.contains("Cash"))
        #expect(journalEntryAccounts.contains("Lease Liability"))
        #expect(journalEntryAccounts.contains("Interest Expense"))
        #expect(journalEntryAccounts.contains("COGS"))
    }

    @Test func paneExhibitsKeepTypedTablesButSkipDocReviewDocument() {
        let table = Exhibit(
            id: 0,
            title: "Schedule",
            body: "",
            kind: "table",
            columns: ["Item", "Amount"],
            rows: [["Revenue", "100"]]
        )
        let document = Exhibit(id: 1, title: "Document", body: "Body", role: "document")
        let model = TbsModel(
            shape: .numeric,
            prompt: "Compute it.",
            exhibits: [table, document],
            steps: []
        )

        #expect(paneExhibits(model) == [table])
        #expect(paneExhibits(model).first?.rows == [["Revenue", "100"]])
    }

    @Test func defaultStepLabelMakesSeededIdsLearnerReadable() {
        #expect(defaultStepLabel("l1") == "Line 1")
        #expect(defaultStepLabel("c2") == "Cell 2")
        #expect(defaultStepLabel("b3") == "Blank 3")
        #expect(defaultStepLabel("citation") == "citation")
    }

    @Test func parseStepsFallsBackToFriendlyLabelsForSeededIds() throws {
        let steps = try parseSteps("""
        [
          {"id":"l1","answer_key":1},
          {"id":"c2","answer_key":2},
          {"id":"named","label":"Explicit","answer_key":3}
        ]
        """)

        #expect(steps.map(\.label) == ["Line 1", "Cell 2", "Explicit"])
    }

    @Test func jeNumericSimulationTitlesMatchExamSurfaces() {
        #expect(jeNumericSimulationTitle(for: .journalEntry) == "Journal entry simulation")
        #expect(jeNumericSimulationTitle(for: .numeric) == "Numeric simulation")
    }

    @Test func journalEntryNoEntrySubmitsBlankValuesWithoutParsingAmount() throws {
        let json = try buildJeSubmission([
            JeLineInput(id: "l1", account: "Cash", side: "dr", amount: "not-a-number", noEntry: true),
        ])
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        let value = try #require(steps.first?["value"] as? [String: Any])

        #expect(value["account"] as? String == "")
        #expect(value["side"] as? String == "")
        #expect(value["amount"] as? String == "")
    }

    @Test func journalEntryAmountStillFailsFastWhenLineIsNotNoEntry() {
        #expect(throws: TbsSubmissionError.invalidDecimal(field: "Amount for Line 1")) {
            try buildJeSubmission([
                JeLineInput(id: "l1", label: "Line 1", account: "Cash", side: "dr", amount: "not-a-number"),
            ])
        }
    }

    @Test func spareJournalEntryLinesAreStableAndBlank() {
        let lines = spareJournalEntryLines()

        #expect(lines.map(\.id) == ["spare-1", "spare-2"])
        #expect(lines.allSatisfy { $0.account.isEmpty })
        #expect(lines.allSatisfy { $0.side.isEmpty })
        #expect(lines.allSatisfy { $0.amount.isEmpty })
        #expect(lines.allSatisfy { !$0.noEntry })
    }
}
