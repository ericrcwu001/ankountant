// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

function isTextEntryTarget(target: EventTarget | null): boolean {
    if (typeof HTMLElement === "undefined" || !(target instanceof HTMLElement)) {
        return false;
    }
    const tagName = target.tagName;
    if (tagName === "INPUT" || tagName === "TEXTAREA" || tagName === "SELECT") {
        return true;
    }
    const editable = target.closest("[contenteditable]");
    return editable instanceof HTMLElement
        && editable.getAttribute("contenteditable")?.toLowerCase() !== "false";
}

export function confidenceShortcutIndex(
    event: Pick<KeyboardEvent, "key" | "target">,
    committed: unknown,
): number | null {
    if (committed !== null || isTextEntryTarget(event.target)) {
        return null;
    }
    const index = ["1", "2", "3"].indexOf(event.key);
    return index >= 0 ? index : null;
}
