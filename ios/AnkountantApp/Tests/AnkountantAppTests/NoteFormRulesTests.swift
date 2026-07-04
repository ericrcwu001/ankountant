import Testing
import AnkiKit
import CoreGraphics
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

@Suite("Image occlusion parser")
struct ImageOcclusionParserTests {
    @Test func textValuesCanContainKeyLikeSubstrings() {
        let masks = parseMasks(
            from: "{{c1::image-occlusion:text:left=0.1:top=0.2:text=scale=not a key:scale=1:fs=0.055}}"
        )

        #expect(masks == [
            .text(
                left: 0.1,
                top: 0.2,
                text: "scale=not a key",
                scale: 1,
                fontSize: 0.055,
                extras: ["_ankountant_ordinal": "1"]
            )
        ])
    }

    @Test func validPolygonCoordinatesAreParsed() {
        let masks = parseMasks(
            from: "{{c2::image-occlusion:polygon:points=0,0 0.5,0.25 1,1:fill=#ffcc00}}"
        )

        #expect(masks == [
            .polygon(
                points: [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 0.5, y: 0.25),
                    CGPoint(x: 1, y: 1),
                ],
                extras: ["_ankountant_ordinal": "2", "fill": "#ffcc00"]
            )
        ])
    }

    @Test func malformedPolygonCoordinatesAreRejected() {
        let masks = parseMasks(
            from: "{{c1::image-occlusion:polygon:points=0,0 0.5,oops 1,1 0,1}}"
        )

        #expect(masks.isEmpty)
    }
}

@MainActor
@Suite("Rich note field editor")
struct RichNoteFieldEditorTests {
    @Test func normalizesInlineMathJaxToAnkiSyntax() {
        #expect(
            RichNoteFieldEditor.normalizedStoredHTML(#"<anki-mathjax>x<br />y</anki-mathjax>"#)
                == "\\(x\ny\\)"
        )
    }

    @Test func normalizesBlockMathJaxToAnkiSyntax() {
        #expect(
            RichNoteFieldEditor.normalizedStoredHTML(#"<anki-mathjax block="true"><br />x<br /></anki-mathjax>"#)
                == "\\[x\\]"
        )
    }
}
