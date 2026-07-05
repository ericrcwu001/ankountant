import SwiftUI
import AnkountantTheme
import AnkiClients
import Dependencies
import UIKit

@MainActor
struct CardContextMenu: View {
    let cardId: Int64
    let noteId: Int64?
    var onSuccess: (() -> Void)?
    var onActionSuccess: ((_ shouldAdvance: Bool) -> Void)?
    var onRequestSetDueDate: ((_ cardId: Int64) -> Void)?

    @Dependency(\.cardClient) var cardClient
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.tagClient) var tagClient

    @Environment(\.palette) private var palette

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var isMarkedNote = false
    @State private var currentFlag: UInt32 = 0
    @State private var canUndo = false
    @State private var isUndoing = false

    init(
        cardId: Int64,
        noteId: Int64? = nil,
        onSuccess: (() -> Void)? = nil,
        onActionSuccess: ((_ shouldAdvance: Bool) -> Void)? = nil,
        onRequestSetDueDate: ((_ cardId: Int64) -> Void)? = nil
    ) {
        self.cardId = cardId
        self.noteId = noteId
        self.onSuccess = onSuccess
        self.onActionSuccess = onActionSuccess
        self.onRequestSetDueDate = onRequestSetDueDate
    }

    var body: some View {
        Menu {
            Button {
                Task { await performSuspend() }
            } label: {
                Label("Suspend", systemImage: "pause.circle")
            }

            Button {
                Task { await performBury() }
            } label: {
                Label("Bury until tomorrow", systemImage: "books.vertical")
            }

            Button {
                Task { await performResetToNew() }
            } label: {
                Label("Forget", systemImage: "arrow.counterclockwise")
            }

            if let onRequestSetDueDate {
                Button {
                    onRequestSetDueDate(cardId)
                } label: {
                    Label("Set due date", systemImage: "calendar.badge.clock")
                }
            }

            if noteId != nil {
                Menu {
                    Button {
                        Task { await performToggleMarkedNote() }
                    } label: {
                        Label(
                            isMarkedNote ? "Unmark note" : "Mark note",
                            systemImage: isMarkedNote ? "star.slash" : "star"
                        )
                    }

                    Button {
                        Task { await performSuspendNote() }
                    } label: {
                        Label("Suspend note", systemImage: "pause.circle.fill")
                    }

                    Button {
                        Task { await performBuryNote() }
                    } label: {
                        Label("Bury note", systemImage: "books.vertical.fill")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                } label: {
                    Label("Note actions", systemImage: "note.text")
                }
            }

            Menu {
                // Listed in reverse so iOS bottom-anchored menus display 1→7 top–to–bottom
                flagButton(0)
                flagButton(7)
                flagButton(6)
                flagButton(5)
                flagButton(4)
                flagButton(3)
                flagButton(2)
                flagButton(1)
            } label: {
                Label {
                    Text("Flag")
                } icon: {
                    Image(systemName: currentFlag == 0 ? "flag.slash.fill" : "flag.fill")
                        .foregroundStyle(flagColor(for: currentFlag))
                }
            }

            Button {
                Task { await performUndo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo || isUndoing)
        } label: {
            Label("Card actions", systemImage: "ellipsis.circle")
                .ankountantFont(.bodyEmphasis)
                .labelStyle(.iconOnly)
        }
        .alert("Action failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await performDeleteNote() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the note and all its cards. The action cannot be undone.")
        }
        .task(id: cardId) {
            await loadMarkedState()
            await loadCurrentFlag()
            await refreshUndoAvailability()
        }
    }

    private func performSuspend() async {
        await performCardAction(
            action: cardClient.suspend,
            errorPrefix: "Suspend failed",
            shouldAdvance: true
        )
    }

    private func performBury() async {
        await performCardAction(
            action: cardClient.bury,
            errorPrefix: "Bury failed",
            shouldAdvance: true
        )
    }

    private func performSuspendNote() async {
        await performNoteAction(
            action: cardClient.suspend,
            errorMessage: { err in "Suspend note failed: \(err)" }
        )
    }

    private func performBuryNote() async {
        await performNoteAction(
            action: cardClient.bury,
            errorMessage: { err in "Bury note failed: \(err)" }
        )
    }

    private func performResetToNew() async {
        await performCardAction(
            action: cardClient.resetToNew,
            errorPrefix: "Forget failed",
            shouldAdvance: true
        )
    }

    private func performDeleteNote() async {
        guard let noteId else { return }
        let deleteNote = noteClient.delete
        do {
            try await Task.detached(priority: .userInitiated) {
                try deleteNote(noteId)
            }.value
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = "Delete note failed: \(error.localizedDescription)"
            showError = true
        }
    }

    private func performToggleMarkedNote() async {
        guard let noteId else { return }
        let addTagToNotes = tagClient.addTagToNotes
        let removeTagFromNotes = tagClient.removeTagFromNotes
        let shouldRemove = isMarkedNote
        do {
            if shouldRemove {
                try await Task.detached(priority: .userInitiated) {
                    try removeTagFromNotes(markedTag, [noteId])
                }.value
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try addTagToNotes(markedTag, [noteId])
                }.value
            }
            isMarkedNote.toggle()
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = "Mark note failed: \(error.localizedDescription)"
            showError = true
        }
    }

    private func performCardAction(
        action: @escaping @Sendable (_ cardId: Int64) throws -> Void,
        errorPrefix: String,
        shouldAdvance: Bool
    ) async {
        do {
            try await Task.detached(priority: .userInitiated) {
                try action(cardId)
            }.value
            onSuccess?()
            onActionSuccess?(shouldAdvance)
        } catch {
            errorMessage = "\(errorPrefix): \(error.localizedDescription)"
            showError = true
        }
    }

    private func performNoteAction(
        action: @escaping @Sendable (_ cardId: Int64) throws -> Void,
        errorMessage buildMessage: (String) -> String
    ) async {
        guard let noteId else { return }
        let fetchByNote = cardClient.fetchByNote
        do {
            try await Task.detached(priority: .userInitiated) {
                let cards = try fetchByNote(noteId)
                guard !cards.isEmpty else {
                    throw NSError(
                        domain: "CardContextMenu",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "No cards found for this note.",
                        ]
                    )
                }
                for card in cards {
                    try action(card.id)
                }
            }.value
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = buildMessage(error.localizedDescription)
            showError = true
        }
    }

    private func performFlag(_ value: UInt32) async {
        let flag = cardClient.flag
        do {
            try await Task.detached(priority: .userInitiated) {
                try flag(cardId, value)
            }.value
            currentFlag = value
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = "Flag failed: \(error.localizedDescription)"
            showError = true
        }
    }

    private func performUndo() async {
        guard !isUndoing, canUndo else { return }
        isUndoing = true
        defer { isUndoing = false }
        let undoLast = cardClient.undoLast
        do {
            try await Task.detached(priority: .userInitiated) {
                try undoLast()
            }.value
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
            showError = true
            await refreshUndoAvailability()
        }
    }

    private func refreshUndoAvailability() async {
        let hasUndoableAction = cardClient.hasUndoableAction
        do {
            canUndo = try await Task.detached(priority: .userInitiated) {
                try hasUndoableAction()
            }.value
        } catch {
            canUndo = false
            errorMessage = "Could not load undo state: \(error.localizedDescription)"
            showError = true
        }
    }

    private func flagButton(_ value: UInt32) -> some View {
        let tint = flagColor(for: value)
        return Button {
            Task { await performFlag(value) }
        } label: {
            Label {
                Text(flagDisplayName(for: value))
                    .foregroundStyle(tint)
            } icon: {
                flagMenuIcon(for: value)
            }
        }
    }

    private func flagDisplayName(for value: UInt32) -> String {
        switch value & 0b111 {
        case 1: return "Red"
        case 2: return "Orange"
        case 3: return "Green"
        case 4: return "Blue"
        case 5: return "Pink"
        case 6: return "Cyan"
        case 7: return "Purple"
        default: return "None"
        }
    }

    private func flagMenuIcon(for value: UInt32) -> Image {
        let symbolName = value == 0 ? "flag.slash.fill" : "flag.fill"
        let tint = UIColor(flagColor(for: value))
        if let image = UIImage(systemName: symbolName)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        return Image(systemName: symbolName)
    }

    private func loadMarkedState() async {
        guard let noteId else {
            isMarkedNote = false
            return
        }

        let fetchNote = noteClient.fetch
        do {
            let note = try await Task.detached(priority: .userInitiated) {
                try fetchNote(noteId)
            }.value
            isMarkedNote = note.map {
                $0.tags
                    .split(separator: " ")
                    .contains { $0.caseInsensitiveCompare(markedTag) == .orderedSame }
            } ?? false
        } catch {
            isMarkedNote = false
            errorMessage = "Could not load note mark state: \(error.localizedDescription)"
            showError = true
        }
    }

    private func loadCurrentFlag() async {
        let getCardFlags = cardClient.getCardFlags
        do {
            currentFlag = try await Task.detached(priority: .userInitiated) {
                try getCardFlags(cardId)
            }.value
        } catch {
            currentFlag = 0
            errorMessage = "Could not load card flag: \(error.localizedDescription)"
            showError = true
        }
    }

    private func flagColor(for value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }
}

private let markedTag = "marked"

#Preview {
    VStack(spacing: 20) {
        Text("Tap the menu button below")
            .ankountantFont(.bodyEmphasis)

        Spacer()

        HStack {
            Text("Card Menu:")
            CardContextMenu(
                cardId: 12345,
                onSuccess: { print("Action succeeded") }
            )
        }

        Spacer()
    }
    .padding()
}
