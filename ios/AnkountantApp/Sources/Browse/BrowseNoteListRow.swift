import SwiftUI
import AnkiKit

struct BrowseNoteListRow: View {
    let note: NoteRecord
    let notetypeName: String?
    @Binding var selectionState: BrowseSelectionState
    let onRowAppear: (NoteRecord) -> Void
    let onRefresh: () -> Void

    var body: some View {
        if selectionState.isSelectMode {
            Button {
                selectionState.toggle(note.id)
            } label: {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    NoteRowView(note: note, notetypeName: notetypeName)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint(isSelected ? "Double-tap to deselect this note." : "Double-tap to select this note.")
            .onAppear {
                onRowAppear(note)
            }
        } else {
            HStack {
                NavigationLink(value: note) {
                    NoteRowView(note: note, notetypeName: notetypeName)
                        .onAppear {
                            onRowAppear(note)
                        }
                }
                NoteContextMenuButton(noteId: note.id, onSuccess: onRefresh)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) {
                selectionState.enterSelectMode(preselect: note.id)
            }
        }
    }

    private var isSelected: Bool {
        selectionState.contains(note.id)
    }

    private var accessibilityLabel: String {
        if let subtitle = composeNoteSubtitle(notetypeName: notetypeName, tags: note.tags) {
            return "\(note.sfld), \(subtitle)"
        }
        return note.sfld
    }
}
