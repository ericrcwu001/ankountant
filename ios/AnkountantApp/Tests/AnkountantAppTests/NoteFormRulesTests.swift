import Testing
import AnkiKit
@testable import AnkountantApp

@Suite("Note form rules")
struct NoteFormRulesTests {
    @Test func addRequiresLoadedDeckNotetypeAndRealFieldContent() {
        let decks = [DeckInfo(id: 1, name: "Default")]

        #expect(!NoteFormRules.canAddNote(
            isSaving: false,
            decks: decks,
            selectedDeckId: 1,
            selectedNotetypeId: 10,
            fieldValues: ["   "],
            loadErrorMessage: nil
        ))

        #expect(NoteFormRules.canAddNote(
            isSaving: false,
            decks: decks,
            selectedDeckId: 1,
            selectedNotetypeId: 10,
            fieldValues: ["Revenue recognition"],
            loadErrorMessage: nil
        ))
    }

    @Test func addBlocksWhenLoadFailedOrSelectedDeckDisappeared() {
        let decks = [DeckInfo(id: 1, name: "Default")]

        #expect(!NoteFormRules.canAddNote(
            isSaving: false,
            decks: decks,
            selectedDeckId: 1,
            selectedNotetypeId: 10,
            fieldValues: ["Front"],
            loadErrorMessage: "Failed to load note form"
        ))

        #expect(!NoteFormRules.canAddNote(
            isSaving: false,
            decks: decks,
            selectedDeckId: 2,
            selectedNotetypeId: 10,
            fieldValues: ["Front"],
            loadErrorMessage: nil
        ))
    }

    @Test func draftFieldValuesFollowActualNotetypeFieldOrder() {
        let draft = AddNoteDraft(fieldValues: [
            "Back": "Answer",
            "Front": "Question",
            "Unused": "Dropped",
        ])

        #expect(NoteFormRules.fieldValues(for: ["Front", "Back", "Extra"], draft: draft) == [
            "Question",
            "Answer",
            "",
        ])
    }

    @Test func splitFieldsPadsMissingEditorFields() {
        #expect(NoteFormRules.splitFields("Question\u{1f}Answer", minimumCount: 3) == [
            "Question",
            "Answer",
            "",
        ])
    }

    @Test func editSaveBlocksWhileLoadingOrAfterLoadError() {
        #expect(!NoteFormRules.canSaveEditedNote(
            isSaving: false,
            fieldNames: [],
            fieldValues: [],
            loadErrorMessage: nil
        ))

        #expect(!NoteFormRules.canSaveEditedNote(
            isSaving: false,
            fieldNames: ["Front"],
            fieldValues: ["Question"],
            loadErrorMessage: "Failed to load note fields"
        ))

        #expect(NoteFormRules.canSaveEditedNote(
            isSaving: false,
            fieldNames: ["Front"],
            fieldValues: ["Question"],
            loadErrorMessage: nil
        ))
    }

    @Test func normalizedTagsCollapseWhitespace() {
        #expect(NoteFormRules.normalizedTags(from: "  tax   audit\nfar ") == ["tax", "audit", "far"])
        #expect(NoteFormRules.spacedTags(from: " tax audit ") == " tax audit ")
        #expect(NoteFormRules.spacedTags(from: "   ") == "")
    }
}
