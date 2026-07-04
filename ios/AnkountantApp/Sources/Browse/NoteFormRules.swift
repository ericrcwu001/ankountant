import Foundation
import AnkiKit

enum NoteFormRules {
    static func canAddNote(
        isSaving: Bool,
        decks: [DeckInfo],
        selectedDeckId: Int64,
        selectedNotetypeId: Int64,
        fieldValues: [String],
        loadErrorMessage: String?
    ) -> Bool {
        !isSaving
            && loadErrorMessage == nil
            && decks.contains { $0.id == selectedDeckId }
            && selectedNotetypeId != 0
            && hasEnteredField(fieldValues)
    }

    static func addNoteRequirementMessage(
        isSaving: Bool,
        decks: [DeckInfo],
        selectedDeckId: Int64,
        selectedNotetypeId: Int64,
        fieldValues: [String],
        loadErrorMessage: String?
    ) -> String? {
        if isSaving || loadErrorMessage != nil {
            return nil
        }
        guard !decks.isEmpty, selectedNotetypeId != 0, !fieldValues.isEmpty else {
            return "Note form is still loading."
        }
        guard decks.contains(where: { $0.id == selectedDeckId }) else {
            return "Choose a deck before adding."
        }
        guard hasEnteredField(fieldValues) else {
            return "Enter at least one field before adding."
        }
        return nil
    }

    static func canSaveEditedNote(
        isSaving: Bool,
        fieldNames: [String],
        fieldValues: [String],
        loadErrorMessage: String?
    ) -> Bool {
        !isSaving
            && loadErrorMessage == nil
            && !fieldNames.isEmpty
            && fieldValues.count >= fieldNames.count
    }

    static func editNoteRequirementMessage(
        isSaving: Bool,
        fieldNames: [String],
        fieldValues: [String],
        loadErrorMessage: String?
    ) -> String? {
        if isSaving || loadErrorMessage != nil {
            return nil
        }
        guard !fieldNames.isEmpty, fieldValues.count >= fieldNames.count else {
            return "Note fields are still loading."
        }
        return nil
    }

    static func fieldValues(for fieldNames: [String], draft: AddNoteDraft?) -> [String] {
        fieldNames.map { name in
            draft?.fieldValues[name] ?? ""
        }
    }

    static func splitFields(_ fields: String, minimumCount: Int) -> [String] {
        var values = fields
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)

        while values.count < minimumCount {
            values.append("")
        }

        return values
    }

    static func normalizedTags(from tags: String) -> [String] {
        tags.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func spacedTags(from tags: String) -> String {
        let normalized = normalizedTags(from: tags)
        guard !normalized.isEmpty else { return "" }
        return " \(normalized.joined(separator: " ")) "
    }

    private static func hasEnteredField(_ fieldValues: [String]) -> Bool {
        fieldValues.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
