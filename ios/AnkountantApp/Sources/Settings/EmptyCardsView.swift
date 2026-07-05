import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies
import Foundation

struct EmptyCardsView: View {
    @Dependency(\.cardRenderingService) var cardRenderingService
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.noteClient) var noteClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var isLoading = true
    @State private var report: String = ""
    @State private var noteEntries: [NoteEntry] = []
    @State private var isDeletingAll = false
    @State private var showDeleteConfirm = false
    @State private var loadErrorMessage: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var editingNote: NoteRecord?

    struct NoteEntry: Identifiable, Sendable {
        let id: Int64
        let cardIds: [Int64]
        let totalCards: Int
        let emptyCards: Int
        let deckName: String
        let willDeleteNote: Bool
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.background)
            } else {
                resultsList
            }
        }
        .navigationTitle("Empty Cards")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete empty cards?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAllEmpty() }
            }
        } message: {
            let count = noteEntries.reduce(0) { $0 + $1.cardIds.count }
            Text("Delete \(count) empty cards? This cannot be undone.")
        }
        .alert("Done", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Empty cards deleted.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task { await loadEmptyCards() }
        .sheet(item: regularEditingNoteBinding) { note in
            NoteEditingDestinationView(note: note, embedInNavigationStack: true) {
                Task { await loadEmptyCards() }
            }
        }
        .fullScreenCover(item: imageOcclusionEditingNoteBinding) { note in
            NoteEditingDestinationView(note: note, embedInNavigationStack: true) {
                Task { await loadEmptyCards() }
            }
        }
    }

    private var imageOcclusionEditingNoteBinding: Binding<NoteRecord?> {
        Binding(
            get: {
                guard let editingNote, editingNote.isImageOcclusionNote else { return nil }
                return editingNote
            },
            set: { newValue in
                if let newValue {
                    editingNote = newValue
                } else if editingNote?.isImageOcclusionNote == true {
                    editingNote = nil
                }
            }
        )
    }

    private var regularEditingNoteBinding: Binding<NoteRecord?> {
        Binding(
            get: {
                guard let editingNote, !editingNote.isImageOcclusionNote else { return nil }
                return editingNote
            },
            set: { newValue in
                if let newValue {
                    editingNote = newValue
                } else if editingNote?.isImageOcclusionNote != true {
                    editingNote = nil
                }
            }
        )
    }

    private var resultsList: some View {
        List {
            if let loadErrorMessage {
                Section {
                    ContentUnavailableView {
                        Label("Could Not Load Empty Cards", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadErrorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await loadEmptyCards() }
                        }
                    }
                    .listRowBackground(palette.surfaceElevated)
                }
            } else if noteEntries.isEmpty {
                Section {
                    Label("No empty cards found", systemImage: "checkmark.circle")
                        .ankountantStatusText(.positive)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(palette.surfaceElevated)
                }
            } else {
                Section {
                    let totalEmpty = noteEntries.reduce(0) { $0 + $1.cardIds.count }
                    Label(
                        "Found \(totalEmpty) notes with empty cards",
                        systemImage: "rectangle.stack.badge.minus"
                    )
                    .ankountantStatusText(.warning)
                    .listRowBackground(palette.surfaceElevated)

                    if !report.isEmpty {
                        DisclosureGroup("Report") {
                            Text(report)
                                .ankountantFont(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .listRowBackground(palette.surfaceElevated)
                    }
                }

                Section("Affected notes") {
                    ForEach(noteEntries) { entry in
                        Button {
                            Task { await openNoteEditor(noteId: entry.id) }
                        } label: {
                            HStack(alignment: .top, spacing: AnkountantSpacing.sm) {
                                VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                                    Text("Note id: \(entry.id)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(palette.textPrimary)
                                    Text("\(entry.emptyCards) of \(entry.totalCards) cards empty")
                                        .ankountantFont(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                    Text("Deck: \(entry.deckName)")
                                        .ankountantFont(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                    if entry.willDeleteNote {
                                        Text("Will also delete the note (all cards empty)")
                                            .ankountantStatusText(.danger, font: .caption)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(palette.surfaceElevated)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeletingAll {
                            HStack {
                                Text("Delete All Empty Cards")
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Label("Delete All Empty Cards", systemImage: "trash")
                        }
                    }
                    .disabled(isDeletingAll)
                    .listRowBackground(palette.surfaceElevated)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    private func loadEmptyCards() async {
        isLoading = true
        loadErrorMessage = nil
        errorMessage = nil
        let cardRenderingServiceCapture = cardRenderingService
        let capturedCardClient = cardClient
        let capturedDeckClient = deckClient
        defer { isLoading = false }

        do {
            let (loadedReport, loadedEntries) = try await Task.detached(priority: .userInitiated) {
                let emptyReport: EmptyCardsReport = try cardRenderingServiceCapture.getEmptyCardsReport()
                let deckById = try capturedDeckClient.fetchAll().reduce(into: [Int64: String]()) { partial, deck in
                    partial[deck.id] = deck.name
                }

                let entries = try emptyReport.notes.map { note in
                    let cards = try capturedCardClient.fetchByNote(note.noteID)
                    guard cards.count >= note.cardIDs.count, let firstCard = cards.first else {
                        throw emptyCardsLoadError("Card metadata changed while loading note \(note.noteID).")
                    }
                    guard let deckName = deckById[firstCard.did] else {
                        throw emptyCardsLoadError("Deck metadata is missing for note \(note.noteID).")
                    }
                    return NoteEntry(
                        id: note.noteID,
                        cardIds: note.cardIDs,
                        totalCards: cards.count,
                        emptyCards: note.cardIDs.count,
                        deckName: deckName,
                        willDeleteNote: note.willDeleteNote
                    )
                }
                return (emptyReport.report, entries)
            }.value
            report = loadedReport
            noteEntries = loadedEntries
        } catch {
            noteEntries = []
            loadErrorMessage = "Failed to load empty cards: \(error.localizedDescription)"
        }
    }

    private func deleteAllEmpty() async {
        isDeletingAll = true
        defer { isDeletingAll = false }

        let allCardIds = noteEntries.flatMap { $0.cardIds }
        let cardClientCapture = cardClient
        do {
            try await Task.detached {
                try cardClientCapture.removeCards(allCardIds)
            }.value
            showSuccess = true
        } catch {
            errorMessage = "Failed to delete empty cards: \(error.localizedDescription)"
            showError = true
        }
    }

    private func openNoteEditor(noteId: Int64) async {
        do {
            let fetchNote = noteClient.fetch
            let note = try await Task.detached(priority: .userInitiated) {
                try fetchNote(noteId)
            }.value
            guard let note else {
                errorMessage = "The selected note no longer exists."
                showError = true
                return
            }
            editingNote = note
        } catch {
            errorMessage = "Failed to load note: \(error.localizedDescription)"
            showError = true
        }
    }
}

private func emptyCardsLoadError(_ message: String) -> NSError {
    NSError(domain: "EmptyCardsView", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
