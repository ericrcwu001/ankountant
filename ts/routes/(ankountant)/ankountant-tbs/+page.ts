// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getNote } from "@generated/backend";

import type { PageLoad } from "./$types";
import { buildTbsModel } from "./lib";

// The TBS tab hosts all four shapes behind a chooser (see TbsTab.svelte). A
// concrete task can be deep-linked as ?note=<noteId> (the e2e does this); the
// chooser then opens on that note's shape. Without an id we hand the chooser an
// empty model and it loads the default (journal-entry) shape on mount.
export const load = (async ({ url }) => {
    const noteIdParam = url.searchParams.get("note");
    const noteId = noteIdParam ? BigInt(noteIdParam) : 0n;
    if (noteId === 0n) {
        return { noteId: 0n, model: null, fields: [] as string[], tags: [] as string[] };
    }
    const note = await getNote({ nid: noteId });
    const model = buildTbsModel(note.fields, note.tags);
    return { noteId, model, fields: note.fields, tags: note.tags };
}) satisfies PageLoad;
