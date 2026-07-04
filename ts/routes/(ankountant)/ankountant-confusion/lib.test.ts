// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    buildChoiceSubmission,
    buildConfusionRevealModel,
    confusionQueuePhase,
    noThreeConsecutiveSameSet,
    selectedConfusionSection,
    stripConfusionSlug,
} from "./lib";

test("buildChoiceSubmission wraps the treatment in {choice}", () => {
    expect(JSON.parse(buildChoiceSubmission("Finance lease"))).toEqual({
        choice: "Finance lease",
    });
});

test("buildConfusionRevealModel exposes the post-submit correct treatment", () => {
    const reveal = buildConfusionRevealModel(
        [
            "mcq",
            "Which treatment applies?",
            "[]",
            JSON.stringify([{ id: "choice", answer_key: "Capitalize", weight: 1 }]),
            "ds::fixed_assets::capitalize",
            "ASC 360-10-30",
        ],
        "capitalize_vs_expense",
    );

    expect(reveal).toEqual({
        correctText: "Capitalize",
        source: "ASC 360-10-30",
        schemaTag: "ds::fixed_assets::capitalize",
        schemaLabel: "Capitalize",
        setId: "capitalize_vs_expense",
        topicLabel: "Capitalization vs expense",
    });
});

test("buildConfusionRevealModel rejects non-confusion notes", () => {
    expect(() => buildConfusionRevealModel(["numeric", "", "[]", "[]"], "set")).toThrow(
        /Unsupported confusion tbs_type: numeric/,
    );
});

test("buildConfusionRevealModel rejects malformed choice keys", () => {
    expect(() =>
        buildConfusionRevealModel(
            ["mcq", "", "[]", JSON.stringify([{ id: "choice", answer_key: "" }])],
            "set",
        )
    ).toThrow(/choice answer_key must be a non-empty string/);
});

test("noThreeConsecutiveSameSet detects the interleave invariant (A47)", () => {
    expect(noThreeConsecutiveSameSet(["a", "b", "a", "b"])).toBe(true);
    expect(noThreeConsecutiveSameSet(["a", "a", "b", "a"])).toBe(true);
    expect(noThreeConsecutiveSameSet(["a", "a", "a"])).toBe(false);
    expect(noThreeConsecutiveSameSet(["b", "a", "a", "a", "b"])).toBe(false);
});

test("confusionQueuePhase keeps empty queues distinct from finished queues", () => {
    expect(confusionQueuePhase(0, 0)).toBe("empty");
    expect(confusionQueuePhase(0, 3)).toBe("active");
    expect(confusionQueuePhase(2, 3)).toBe("active");
    expect(confusionQueuePhase(3, 3)).toBe("finished");
    expect(confusionQueuePhase(4, 3)).toBe("finished");
});

test("confusionQueuePhase fails fast on malformed queue state", () => {
    expect(() => confusionQueuePhase(-1, 3)).toThrow(/non-negative integer/);
    expect(() => confusionQueuePhase(0.5, 3)).toThrow(/non-negative integer/);
    expect(() => confusionQueuePhase(0, -1)).toThrow(/non-negative integer/);
    expect(() => confusionQueuePhase(0, 1.5)).toThrow(/non-negative integer/);
});

test("selectedConfusionSection accepts all practice sections and rejects unknown values", () => {
    expect(selectedConfusionSection(null)).toBe("ALL");
    expect(selectedConfusionSection(" all ")).toBe("ALL");
    expect(selectedConfusionSection("bar")).toBe("BAR");
    expect(selectedConfusionSection(" tcp ")).toBe("TCP");
    expect(() => selectedConfusionSection("NOPE")).toThrow(/Unknown CPA section: NOPE/);
});

test("stripConfusionSlug removes trailing dev slugs only", () => {
    expect(stripConfusionSlug("Which treatment applies? (capitalize_vs_expense q0)")).toBe(
        "Which treatment applies?",
    );
    expect(stripConfusionSlug("Which treatment applies?")).toBe("Which treatment applies?");
});
