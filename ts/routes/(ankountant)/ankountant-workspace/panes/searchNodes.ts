// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Pure builders for browser `SearchNode`s + the click-modifier semantics the
// ! sidebar uses to combine a clicked node with the current search. Mirrors the
// ! Qt sidebar (qt/aqt/browser/sidebar/tree.py): plain replaces, Ctrl ANDs,
// ! Shift ORs, Alt negates. The nodes are `PlainMessage` shapes so they can be
// ! handed straight to `buildSearchString` / `joinSearchNodes`; kept DOM- and
// ! RPC-free so they unit-test under `just test-ts`.

import type { PlainMessage } from "@bufbuild/protobuf";

import type { SearchNode } from "@generated/anki/search_pb";
import {
    SearchNode_CardState,
    SearchNode_Flag,
    SearchNode_Group_Joiner,
    SearchNode_Rating,
} from "@generated/anki/search_pb";

/** A `SearchNode` in its plain (RPC-ready) form. */
export type Node = PlainMessage<SearchNode>;

/** How a clicked sidebar node combines with the existing search. */
export type SearchCombine = "replace" | "and" | "or" | "negate";

export function parsableText(text: string): Node {
    return { filter: { case: "parsableText", value: text } };
}

export function literalText(text: string): Node {
    return { filter: { case: "literalText", value: text } };
}

export function deckNode(fullName: string): Node {
    return { filter: { case: "deck", value: fullName } };
}

export function tagNode(fullName: string): Node {
    return { filter: { case: "tag", value: fullName } };
}

export function notetypeNode(name: string): Node {
    return { filter: { case: "note", value: name } };
}

export function cardStateNode(state: SearchNode_CardState): Node {
    return { filter: { case: "cardState", value: state } };
}

export function flagNode(flag: SearchNode_Flag): Node {
    return { filter: { case: "flag", value: flag } };
}

export function addedInDays(days: number): Node {
    return { filter: { case: "addedInDays", value: days } };
}

export function editedInDays(days: number): Node {
    return { filter: { case: "editedInDays", value: days } };
}

export function introducedInDays(days: number): Node {
    return { filter: { case: "introducedInDays", value: days } };
}

export function dueOnDay(day: number): Node {
    return { filter: { case: "dueOnDay", value: day } };
}

export function ratedNode(days: number, rating: SearchNode_Rating): Node {
    return { filter: { case: "rated", value: { days, rating } } };
}

/** Wrap a node so it matches everything it previously excluded. */
export function negate(node: Node): Node {
    return { filter: { case: "negated", value: node } };
}

export function group(nodes: Node[], joiner: SearchNode_Group_Joiner): Node {
    return { filter: { case: "group", value: { nodes, joiner } } };
}

/**
 * Resolve the click modifiers on a mouse/keyboard event to a combine mode,
 * matching the Qt sidebar. Order matters: Alt (negate) wins, then Ctrl (and),
 * then Shift (or); a plain click replaces.
 */
export function combineFromEvent(
    event: { altKey?: boolean; ctrlKey?: boolean; metaKey?: boolean; shiftKey?: boolean },
): SearchCombine {
    if (event.altKey) {
        return "negate";
    }
    if (event.ctrlKey || event.metaKey) {
        return "and";
    }
    if (event.shiftKey) {
        return "or";
    }
    return "replace";
}

/** The joiner a combine mode maps to when calling `joinSearchNodes`. */
export function joinerFor(combine: "and" | "or"): SearchNode_Group_Joiner {
    return combine === "or" ? SearchNode_Group_Joiner.OR : SearchNode_Group_Joiner.AND;
}

export { SearchNode_CardState, SearchNode_Flag, SearchNode_Group_Joiner, SearchNode_Rating };
