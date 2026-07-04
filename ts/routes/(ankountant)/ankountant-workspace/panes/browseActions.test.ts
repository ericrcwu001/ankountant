// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { deleteNotesConfirmation, deleteSelectionMenuLabel } from "./browseActions";

test("delete menu label distinguishes selected cards from selected notes", () => {
    expect(deleteSelectionMenuLabel(1, true)).toBe("Delete note");
    expect(deleteSelectionMenuLabel(3, true)).toBe("Delete 3 notes");
    expect(deleteSelectionMenuLabel(1, false)).toBe("Delete card's note");
    expect(deleteSelectionMenuLabel(3, false)).toBe("Delete selected notes");
});

test("delete confirmation uses resolved unique note count", () => {
    expect(deleteNotesConfirmation(1)).toBe("Delete 1 note? You can undo this.");
    expect(deleteNotesConfirmation(2)).toBe("Delete 2 notes? You can undo this.");
    expect(() => deleteNotesConfirmation(0)).toThrow(/at least one note/);
});
