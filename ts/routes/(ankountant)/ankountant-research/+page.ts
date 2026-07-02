// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getNote, searchNotes } from "@generated/backend";

import { buildTbsModel } from "../ankountant-tbs/lib";
import type { PageLoad } from "./$types";

// Section-agnostic (ADR 0008): filter by BOTH tbs_type (a note field) AND
// section (the sealed-deck prefix), defaulting to FAR. A concrete item can be
// deep-linked as ?note=<id>, or a section chosen with ?section=<AUD|FAR|...>.
export const load = (async ({ url }) => {
    const section = url.searchParams.get("section") ?? "FAR";
    const search = `"note:Ankountant TBS" "tbs_type:research" deck:Ankountant::Sealed::${section}::*`;
    const noteIdParam = url.searchParams.get("note");
    let noteId = noteIdParam ? BigInt(noteIdParam) : 0n;
    if (noteId === 0n) {
        const found = await searchNotes({ search });
        if (found.ids.length > 0) {
            noteId = found.ids[0];
        }
    }
    if (noteId === 0n) {
        return { noteId: 0n, model: null, fields: [] as string[], tags: [] as string[] };
    }
    const note = await getNote({ nid: noteId });
    const model = buildTbsModel(note.fields, note.tags);
    return { noteId, model, fields: note.fields, tags: note.tags };
}) satisfies PageLoad;
