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

test("errorMessage strips backend html from workspace pane failures", () => {
    const html403 = `403: <!doctype html>
        <html lang=en>
        <title>403 Forbidden</title>
        <h1>Forbidden</h1>
        <p>You don&#39;t have the permission to access the requested resource.</p>`;

    const message = errorMessage(new Error(html403));

    expect(message).toBe("403 Forbidden. This workspace surface could not be loaded.");
    expect(message).not.toContain("<html");
    expect(message).not.toContain("doctype");
    expect(message).not.toContain("don&#39;t");
});
