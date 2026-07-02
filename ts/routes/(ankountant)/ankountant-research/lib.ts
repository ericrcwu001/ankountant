// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Pure helpers for the research surface: client-side, offline search over the
// ! bundled per-section corpus (T2 / OQ-3). DOM-free for `just test-ts`.

import type { CorpusEntry } from "./corpus";
import { CORPUS } from "./corpus";

export type { CorpusEntry } from "./corpus";

/** The bundled corpus passages for a section (empty for an unseeded section). */
export function corpusForSection(section: string): CorpusEntry[] {
    return CORPUS[section] ?? [];
}

/**
 * Substring/keyword search over `citation + title + body` (T2 AC1). Empty query
 * returns everything (the corpus is small + scoped), so the pane reads as a
 * browsable reference, not a blank box.
 */
export function searchCorpus(entries: CorpusEntry[], query: string): CorpusEntry[] {
    const q = query.trim().toLowerCase();
    if (!q) {
        return entries;
    }
    const terms = q.split(/\s+/);
    return entries.filter((e) => {
        const hay = `${e.citation} ${e.title} ${e.body} ${(e.tags ?? []).join(" ")}`.toLowerCase();
        return terms.every((t) => hay.includes(t));
    });
}
