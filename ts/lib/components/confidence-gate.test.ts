// @vitest-environment jsdom
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { confidenceShortcutIndex } from "./confidence-gate";

function keyEvent(key: string, target: EventTarget): Pick<KeyboardEvent, "key" | "target"> {
    return { key, target };
}

test("confidence shortcuts are ignored while typing", () => {
    const input = document.createElement("input");
    const textarea = document.createElement("textarea");
    const select = document.createElement("select");
    const editable = document.createElement("div");
    const editableChild = document.createElement("span");
    editable.setAttribute("contenteditable", "true");
    editable.appendChild(editableChild);

    for (const target of [input, textarea, select, editable, editableChild]) {
        expect(confidenceShortcutIndex(keyEvent("1", target), null)).toBeNull();
    }
});

test("confidence shortcuts work outside typing targets", () => {
    const button = document.createElement("button");

    expect(confidenceShortcutIndex(keyEvent("1", button), null)).toBe(0);
    expect(confidenceShortcutIndex(keyEvent("2", button), null)).toBe(1);
    expect(confidenceShortcutIndex(keyEvent("3", button), null)).toBe(2);
    expect(confidenceShortcutIndex(keyEvent("4", button), null)).toBeNull();
    expect(confidenceShortcutIndex(keyEvent("1", button), "Guess")).toBeNull();
});
