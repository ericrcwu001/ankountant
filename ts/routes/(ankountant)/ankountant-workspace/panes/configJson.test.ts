// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { decodeConfigJson, encodeConfigJson, errorMessage, isMissingConfigJson } from "./configJson";

test("isMissingConfigJson recognises optional absent config keys", () => {
    expect(
        isMissingConfigJson(
            new Error("500: Your collection is corrupt. No such value: 'savedFilters'"),
            "savedFilters",
        ),
    ).toBe(true);
    expect(
        isMissingConfigJson(
            new Error("500: Your collection is corrupt. No such value: 'other'"),
            "savedFilters",
        ),
    ).toBe(false);
});

test("decodeConfigJson fails loudly on corrupt saved preferences", () => {
    expect(decodeConfigJson("x", new TextEncoder().encode("[\"a\"]"))).toEqual(["a"]);
    expect(() => decodeConfigJson("x", new TextEncoder().encode("{"))).toThrow(
        /Saved preference "x" contains invalid JSON/,
    );
});

test("encodeConfigJson rejects values that are not JSON preferences", () => {
    expect(new TextDecoder().decode(encodeConfigJson("x", ["a"]))).toBe("[\"a\"]");
    expect(() => encodeConfigJson("x", undefined)).toThrow(
        /Could not encode saved preference "x"/,
    );
});

test("errorMessage handles non-Error throw values", () => {
    expect(errorMessage("failed")).toBe("failed");
});
