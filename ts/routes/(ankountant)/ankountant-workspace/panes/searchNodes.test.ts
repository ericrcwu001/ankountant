// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    addedInDays,
    cardStateNode,
    combineFromEvent,
    deckNode,
    dueOnDay,
    flagNode,
    group,
    joinerFor,
    negate,
    notetypeNode,
    parsableText,
    ratedNode,
    SearchNode_CardState,
    SearchNode_Flag,
    SearchNode_Group_Joiner,
    SearchNode_Rating,
    tagNode,
} from "./searchNodes";

test("leaf factories produce the matching oneof case", () => {
    expect(deckNode("FAR::Sealed")).toEqual({
        filter: { case: "deck", value: "FAR::Sealed" },
    });
    expect(tagNode("ds::lease")).toEqual({ filter: { case: "tag", value: "ds::lease" } });
    expect(notetypeNode("Ankountant TBS")).toEqual({
        filter: { case: "note", value: "Ankountant TBS" },
    });
    expect(parsableText("deck:current")).toEqual({
        filter: { case: "parsableText", value: "deck:current" },
    });
});

test("enum-valued factories carry the enum value", () => {
    expect(cardStateNode(SearchNode_CardState.SUSPENDED)).toEqual({
        filter: { case: "cardState", value: SearchNode_CardState.SUSPENDED },
    });
    expect(flagNode(SearchNode_Flag.RED)).toEqual({
        filter: { case: "flag", value: SearchNode_Flag.RED },
    });
});

test("today factories map to the right numeric filters", () => {
    expect(dueOnDay(0)).toEqual({ filter: { case: "dueOnDay", value: 0 } });
    expect(addedInDays(1)).toEqual({ filter: { case: "addedInDays", value: 1 } });
    expect(ratedNode(1, SearchNode_Rating.AGAIN)).toEqual({
        filter: { case: "rated", value: { days: 1, rating: SearchNode_Rating.AGAIN } },
    });
});

test("negate wraps a node without mutating it", () => {
    const inner = deckNode("Default");
    const wrapped = negate(inner);
    expect(wrapped).toEqual({ filter: { case: "negated", value: inner } });
    // original untouched
    expect(inner).toEqual({ filter: { case: "deck", value: "Default" } });
});

test("group nests children under a joiner", () => {
    const g = group([tagNode("a"), tagNode("b")], SearchNode_Group_Joiner.OR);
    expect(g.filter.case).toBe("group");
    if (g.filter.case === "group") {
        expect(g.filter.value.joiner).toBe(SearchNode_Group_Joiner.OR);
        expect(g.filter.value.nodes).toHaveLength(2);
    }
});

test("combineFromEvent resolves modifiers with Alt/Ctrl/Shift precedence", () => {
    expect(combineFromEvent({})).toBe("replace");
    expect(combineFromEvent({ shiftKey: true })).toBe("or");
    expect(combineFromEvent({ ctrlKey: true })).toBe("and");
    expect(combineFromEvent({ metaKey: true })).toBe("and");
    expect(combineFromEvent({ altKey: true })).toBe("negate");
    // Alt wins over the rest.
    expect(combineFromEvent({ altKey: true, ctrlKey: true, shiftKey: true })).toBe(
        "negate",
    );
    // Ctrl wins over Shift.
    expect(combineFromEvent({ ctrlKey: true, shiftKey: true })).toBe("and");
});

test("joinerFor maps and/or to the proto joiner", () => {
    expect(joinerFor("and")).toBe(SearchNode_Group_Joiner.AND);
    expect(joinerFor("or")).toBe(SearchNode_Group_Joiner.OR);
});
