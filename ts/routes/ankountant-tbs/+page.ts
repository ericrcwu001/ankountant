// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getNote } from "@generated/backend";

import type { PageLoad } from "./$types";
import { buildTbsModel } from "./lib";

export const load = (async ({ url }) => {
    // The TBS note to play is passed as ?note=<noteId>. The e2e fixture seeds a
    // FAR bank and navigates here with a concrete id.
    const noteIdParam = url.searchParams.get("note");
    const noteId = noteIdParam ? BigInt(noteIdParam) : 0n;
    const note = await getNote({ nid: noteId });
    const model = buildTbsModel(note.fields);
    return { noteId, model };
}) satisfies PageLoad;
