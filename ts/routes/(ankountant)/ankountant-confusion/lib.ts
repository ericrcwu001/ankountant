// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B2/B3 (F012/F013) — pure helpers for the confusion-set review mode. The
// ! queue itself is built server-side (A3, `BuildConfusionQueue`) and is already
// ! label-stripped; these helpers only shape the discrimination submission and
// ! verify the interleave invariant for tests. DOM-free for `just test-ts`.

/** Shape submission_json for a which-treatment (discrimination) choice (B2). */
export function buildChoiceSubmission(choice: string): string {
    return JSON.stringify({ choice });
}

/**
 * Assert the interleave invariant used by B3-D1 / A47: no 3 consecutive items
 * share the same treatment-set. Exposed for unit testing the client's handling
 * of the server queue.
 */
export function noThreeConsecutiveSameSet(setIds: string[]): boolean {
    for (let i = 2; i < setIds.length; i++) {
        if (setIds[i] === setIds[i - 1] && setIds[i] === setIds[i - 2]) {
            return false;
        }
    }
    return true;
}
