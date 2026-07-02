// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Loads a note into the shared `ts/editor/NoteEditor` from a `Notetype` +
// ! `Note`. The web-native Add/Browse surfaces drive the editor from TS (there
// ! is no Python `aqt.editor.Editor` behind it), so the per-field metadata the
// ! editor needs — names, fonts, descriptions, plain-text/collapsed defaults —
// ! has to be pushed in explicitly. Missing this is why a bare setFields() mount
// ! throws on `fonts[index]`; both panes now go through here.

import type { Note } from "@generated/anki/notes_pb";
import type { Notetype } from "@generated/anki/notetypes_pb";
import { Notetype_Config_Kind } from "@generated/anki/notetypes_pb";

/** The subset of NoteEditor's imperative API the panes drive. */
export interface EditorHandle {
    setNoteId(id: number): void;
    setFields(fields: [string, string][]): void;
    setFonts(fonts: [string, number, boolean][]): void;
    setDescriptions(descriptions: string[]): void;
    setPlainTexts(plainTexts: boolean[]): void;
    setCollapsed(collapsed: boolean[]): void;
    setClozeFields(clozeFields: boolean[]): void;
    setTags(tags: string[]): void;
    triggerChanges(): void;
    focusField(index: number | null): void;
}

const DEFAULT_FONT = "Arial";
const DEFAULT_FONT_SIZE = 20;

/**
 * Push a note's content + its notetype's per-field presentation into the editor.
 * Pass `focus: true` to move the caret into the first field (Add flow); Browse
 * leaves focus alone so row navigation isn't hijacked.
 */
export function loadNoteIntoEditor(
    editor: EditorHandle,
    notetype: Notetype,
    note: Note,
    options: { focus?: boolean } = {},
): void {
    const fields = notetype.fields;
    const isCloze = notetype.config?.kind === Notetype_Config_Kind.CLOZE;

    editor.setNoteId(Number(note.id));
    editor.setFields(
        fields.map((f, i) => [f.name, note.fields[i] ?? ""] as [string, string]),
    );
    editor.setFonts(
        fields.map(
            (f) =>
                [
                    f.config?.fontName || DEFAULT_FONT,
                    f.config?.fontSize || DEFAULT_FONT_SIZE,
                    f.config?.rtl ?? false,
                ] as [string, number, boolean],
        ),
    );
    editor.setDescriptions(fields.map((f) => f.config?.description ?? ""));
    editor.setPlainTexts(fields.map((f) => f.config?.plainText ?? false));
    editor.setCollapsed(fields.map((f) => f.config?.collapsed ?? false));
    editor.setClozeFields(fields.map(() => isCloze));
    editor.setTags(note.tags);
    editor.triggerChanges();

    if (options.focus) {
        editor.focusField(0);
    }
}
