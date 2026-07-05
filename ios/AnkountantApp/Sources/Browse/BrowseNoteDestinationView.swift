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
                ContentUnavailableView {
                    Label("Could Not Load Note", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadNote() }
                    }
                }
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
        resolvedNote = nil

        guard note.sfld == "Loading..." else {
            resolvedNote = note
            return
        }

        do {
            let fetchNote = noteClient.fetch
            let noteId = note.id
            let fullNote = try await Task.detached(priority: .userInitiated) {
                try fetchNote(noteId)
            }.value
            guard let fullNote else {
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
