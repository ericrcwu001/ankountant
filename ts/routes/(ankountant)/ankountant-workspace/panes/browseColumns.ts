// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Column metadata helpers shared by the Browse table + its header/column
// ! menus. The default sets and config keys mirror pylib/anki/browser.py so the
// ! web table persists the same `activeCols` / `activeNoteCols` the Qt browser
// ! reads. Pure (no RPC) so it can be reasoned about + reused in both modes.

import type { BrowserColumns_Column } from "@generated/anki/search_pb";
import { BrowserColumns_Sorting } from "@generated/anki/search_pb";

/** Default visible columns in cards mode (Anki's built-in default). */
export const DEFAULT_CARD_COLUMNS = ["noteFld", "template", "cardDue", "deck"];

/** Default visible columns in notes mode. */
export const DEFAULT_NOTE_COLUMNS = ["noteFld", "note", "template", "noteTags"];

/** col config key holding the active column set, per mode. */
export function activeColsKey(notesMode: boolean): string {
    return notesMode ? "activeNoteCols" : "activeCols";
}

/** col config key holding the sort column, per mode. */
export function sortTypeKey(notesMode: boolean): string {
    return notesMode ? "noteSortType" : "sortType";
}

/** col config key holding the sort direction, per mode. */
export function sortBackwardsKey(notesMode: boolean): string {
    return notesMode ? "browserNoteSortBackwards" : "sortBackwards";
}

export function defaultColumns(notesMode: boolean): string[] {
    return notesMode ? DEFAULT_NOTE_COLUMNS : DEFAULT_CARD_COLUMNS;
}

/** The label to show for a column in the current mode. */
export function labelFor(col: BrowserColumns_Column, notesMode: boolean): string {
    return notesMode ? col.notesModeLabel : col.cardsModeLabel;
}

/** The tooltip to show for a column in the current mode. */
export function tooltipFor(col: BrowserColumns_Column, notesMode: boolean): string {
    return notesMode ? col.notesModeTooltip : col.cardsModeTooltip;
}

/** A column is sortable in a mode when its per-mode sorting isn't NONE. */
export function isSortable(col: BrowserColumns_Column, notesMode: boolean): boolean {
    const sorting = notesMode ? col.sortingNotes : col.sortingCards;
    return sorting !== BrowserColumns_Sorting.NONE;
}

/**
 * The natural first-click direction for a column: numeric/date columns read
 * best newest-first (descending), text columns A→Z (ascending). Encoded by the
 * backend as the column's default `Sorting`.
 */
export function defaultReverse(col: BrowserColumns_Column, notesMode: boolean): boolean {
    const sorting = notesMode ? col.sortingNotes : col.sortingCards;
    return sorting === BrowserColumns_Sorting.DESCENDING;
}
