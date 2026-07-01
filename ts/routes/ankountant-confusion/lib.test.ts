// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { buildChoiceSubmission, noThreeConsecutiveSameSet } from "./lib";

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
