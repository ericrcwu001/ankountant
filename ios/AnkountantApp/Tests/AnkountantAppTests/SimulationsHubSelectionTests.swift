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
}
