// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

export function deleteSelectionMenuLabel(selectedCount: number, notesMode: boolean): string {
    if (selectedCount <= 0) {
        return "Delete notes";
    }
    if (notesMode) {
        return selectedCount === 1 ? "Delete note" : `Delete ${selectedCount} notes`;
    }
    return selectedCount === 1 ? "Delete card's note" : "Delete selected notes";
}

export function deleteNotesConfirmation(noteCount: number): string {
    if (noteCount <= 0) {
        throw new Error("Delete confirmation requires at least one note.");
    }
    return `Delete ${noteCount} note${noteCount === 1 ? "" : "s"}? You can undo this.`;
}
