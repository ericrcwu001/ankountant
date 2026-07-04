// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { buildChoiceSubmission, confusionQueuePhase, noThreeConsecutiveSameSet, selectedConfusionSection } from "./lib";

test("buildChoiceSubmission wraps the treatment in {choice}", () => {
    expect(JSON.parse(buildChoiceSubmission("Finance lease"))).toEqual({
        choice: "Finance lease",
    });
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
