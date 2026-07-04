import Testing
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
}
