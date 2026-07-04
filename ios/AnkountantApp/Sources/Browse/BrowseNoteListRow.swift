import SwiftUI
import AnkiKit

struct BrowseNoteListRow: View {
    let note: NoteRecord
    let notetypeName: String?
    @Binding var selectionState: BrowseSelectionState
    let onRowAppear: (NoteRecord) -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            if selectionState.isSelectMode {
                Image(systemName: selectionState.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectionState.contains(note.id) ? Color.accentColor : Color.secondary)
                NoteRowView(note: note, notetypeName: notetypeName)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionState.toggle(note.id)
                    }
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
    }
}
