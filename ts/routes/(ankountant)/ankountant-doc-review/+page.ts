// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getNote, searchNotes } from "@generated/backend";

import { buildTbsModel, sectionSearchOrder, tbsSearch } from "../ankountant-tbs/lib";
import type { PageLoad } from "./$types";

export const load = (async ({ url }) => {
    const noteIdParam = url.searchParams.get("note");
    let noteId = noteIdParam ? BigInt(noteIdParam) : 0n;
    if (noteId === 0n) {
        for (const section of sectionSearchOrder(url.searchParams.get("section"))) {
            const found = await searchNotes({ search: tbsSearch("doc_review", section) });
            if (found.ids.length > 0) {
                noteId = found.ids[0];
                break;
            }
        }
    }
    if (noteId === 0n) {
        return { noteId: 0n, model: null, fields: [] as string[], tags: [] as string[] };
    }
    const note = await getNote({ nid: noteId });
    const model = buildTbsModel(note.fields, note.tags);
    return { noteId, model, fields: note.fields, tags: note.tags };
}) satisfies PageLoad;
