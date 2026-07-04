import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies

struct BrowseNoteDestinationView: View {
    let note: NoteRecord
    let onSave: () -> Void

    @Dependency(\.noteClient) private var noteClient
    @State private var resolvedNote: NoteRecord?
    @State private var loadErrorMessage: String?

    var body: some View {
        Group {
            if let resolvedNote {
                NoteEditingDestinationView(note: resolvedNote, onSave: onSave)
            } else if let loadErrorMessage {
                ContentUnavailableView(
                    "Could Not Load Note",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: note.id) {
            await loadNote()
        }
    }

    @MainActor
    private func loadNote() async {
        loadErrorMessage = nil

        guard note.sfld == "Loading..." else {
            resolvedNote = note
            return
        }

        do {
            guard let fullNote = try noteClient.fetch(note.id) else {
                resolvedNote = nil
                loadErrorMessage = "The selected note could not be found."
                return
            }
            resolvedNote = fullNote
        } catch {
            resolvedNote = nil
            loadErrorMessage = "Failed to load note: \(error.localizedDescription)"
        }
    }
}
