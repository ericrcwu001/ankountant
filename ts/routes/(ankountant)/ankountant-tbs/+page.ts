// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getNote, searchNotes } from "@generated/backend";

import type { PageLoad } from "./$types";
import { buildTbsModel } from "./lib";

const SECTION = "FAR";
// Mirrors rslib TBS_NOTETYPE + the sealed-bank deck layout (confusion.rs).
const FIRST_TBS_SEARCH = `"note:Ankountant TBS" deck:Ankountant::Sealed::${SECTION}::*`;

export const load = (async ({ url }) => {
    // A concrete task can be deep-linked as ?note=<noteId> (the e2e does this).
    // Opened from the Ankountant menu there is no id, so we fall back to the
    // first available sealed TBS note in the section. If none exist (no FAR seed
    // loaded yet) we render an empty state rather than fetching note 0.
    const noteIdParam = url.searchParams.get("note");
    let noteId = noteIdParam ? BigInt(noteIdParam) : 0n;
    if (noteId === 0n) {
        const found = await searchNotes({ search: FIRST_TBS_SEARCH });
        if (found.ids.length > 0) {
            noteId = found.ids[0];
        }
    }
    if (noteId === 0n) {
        return { noteId: 0n, model: null };
    }
    const note = await getNote({ nid: noteId });
    const model = buildTbsModel(note.fields, note.tags);
    return { noteId, model };
}) satisfies PageLoad;
