// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// Ankountant B1: a pre-reveal confidence gate for the normal card reviewer.
// The reviewer's card and its "Show Answer" button live in separate webviews,
// so the reveal is gated on the Python side (reviewer.py). This module renders
// the confidence control in the card webview, mirrors the committed level into
// card.custom_data (the scalar the A2 backend reads), and then asks Python to
// reveal. It fails open: if `ankountant_gate_ready` is never signalled (e.g. a
// JS error here), Python does not block the reveal, so study can't soft-lock.

import { bridgeCommand } from "@tslib/bridgecommand";

const LEVELS = ["Guess", "Unsure", "Confident"] as const;
type ConfidenceLevel = (typeof LEVELS)[number];
const GATE_ID = "ankountant-confidence-gate";

let committing = false;

/** Remove the gate bar and its key handler (safe to call repeatedly). */
export function clearAnkountantConfidenceGate(): void {
    document.getElementById(GATE_ID)?.remove();
    document.removeEventListener("keydown", onKey, true);
}

async function commit(level: ConfidenceLevel): Promise<void> {
    if (committing) {
        return;
    }
    committing = true;

    // Best-effort: mirror the pre-reveal confidence into the next states'
    // custom_data. Never let a failure here block the reveal.
    try {
        const anki = (globalThis as { anki?: Record<string, unknown> }).anki;
        const mutate = anki?.["mutateNextCardStates"] as
            | ((
                key: string,
                transform: (
                    states: unknown,
                    customData: Record<string, Record<string, unknown>>,
                ) => Promise<void>,
            ) => Promise<void>)
            | undefined;
        if (mutate) {
            await mutate("ankountantConfidence", async (_states, customData) => {
                for (const rating of ["again", "hard", "good", "easy"]) {
                    if (customData[rating]) {
                        customData[rating]["confidence"] = level;
                    }
                }
            });
        }
    } catch (error) {
        console.log("ankountant: failed to persist confidence", error);
    }

    clearAnkountantConfidenceGate();
    bridgeCommand(`ankountant_ans:${level}`);
}

function onKey(event: KeyboardEvent): void {
    // Never steal digit keys while the user is typing a type-in answer.
    const active = document.activeElement;
    if (
        active instanceof HTMLInputElement
        || active instanceof HTMLTextAreaElement
    ) {
        return;
    }
    const index = ["1", "2", "3"].indexOf(event.key);
    if (index >= 0) {
        event.preventDefault();
        event.stopPropagation();
        void commit(LEVELS[index]);
    }
}

/** Render the confidence gate on the question side and arm Python's block. */
export function setupAnkountantConfidenceGate(): void {
    clearAnkountantConfidenceGate();
    committing = false;

    const bar = document.createElement("div");
    bar.id = GATE_ID;
    bar.setAttribute("data-testid", "confidence-gate");
    bar.style.cssText = "position:fixed;top:0;left:0;right:0;z-index:2147483647;"
        + "display:flex;gap:.5em;align-items:center;justify-content:center;"
        + "padding:.4em;background:var(--canvas,#fff);"
        + "border-bottom:1px solid var(--border,#ccc);font-size:small;";

    const label = document.createElement("span");
    label.textContent = "Rate your confidence before revealing:";
    bar.appendChild(label);

    LEVELS.forEach((level, i) => {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = `${level} (${i + 1})`;
        button.setAttribute("data-testid", `confidence-${level.toLowerCase()}`);
        button.addEventListener("click", () => void commit(level));
        bar.appendChild(button);
    });

    document.body.appendChild(bar);
    document.addEventListener("keydown", onKey, true);

    // Tell Python the gate is active so premature reveals are blocked. If this
    // never fires, Python fails open and the reveal works as normal.
    bridgeCommand("ankountant_gate_ready");
}
