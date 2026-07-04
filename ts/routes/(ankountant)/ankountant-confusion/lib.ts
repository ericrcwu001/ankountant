// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B2/B3 (F012/F013) — pure helpers for the confusion-set review mode. The
// ! queue itself is built server-side (A3, `BuildConfusionQueue`) and is already
// ! label-stripped; these helpers only shape the discrimination submission and
// ! verify the interleave invariant for tests. DOM-free for `just test-ts`.

import { TBS_FIELD } from "../ankountant-tbs/lib";

/** Shape submission_json for a which-treatment (discrimination) choice (B2). */
export function buildChoiceSubmission(choice: string): string {
    return JSON.stringify({ choice });
}

export function stripConfusionSlug(prompt: string): string {
    return prompt.replace(/\s*\([a-z0-9_]+\s+q\d+\)\s*$/i, "").trimEnd();
}

export interface ConfusionRevealModel {
    correctText: string;
    source: string;
    schemaTag: string;
    setId: string;
}

interface ConfusionRevealStep {
    id?: unknown;
    answer_key?: unknown;
}

function parseJsonArray(fieldName: string, raw: string | undefined): unknown[] {
    if (raw === undefined || raw.trim() === "") {
        throw new Error(`${fieldName} is missing.`);
    }
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
        throw new Error(`${fieldName} must be an array.`);
    }
    return parsed;
}

function jsonObject(raw: unknown, fieldName: string): Record<string, unknown> {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
        throw new Error(`${fieldName} must be an object.`);
    }
    return raw as Record<string, unknown>;
}

export function buildConfusionRevealModel(
    fields: string[],
    setId: string,
): ConfusionRevealModel {
    const tbsType = fields[TBS_FIELD.tbsType];
    if (tbsType !== "mcq") {
        throw new Error(`Unsupported confusion tbs_type: ${tbsType ?? ""}`);
    }
    const steps = parseJsonArray("steps_json", fields[TBS_FIELD.stepsJson]);
    const choice = steps
        .map((step, index) => jsonObject(step, `steps_json[${index}]`) as ConfusionRevealStep)
        .find((step) => step.id === "choice");
    if (choice === undefined) {
        throw new Error("steps_json is missing the choice step.");
    }
    if (typeof choice.answer_key !== "string" || choice.answer_key.trim() === "") {
        throw new Error("choice answer_key must be a non-empty string.");
    }
    return {
        correctText: choice.answer_key,
        source: fields[TBS_FIELD.sourcePassage] ?? "",
        schemaTag: fields[TBS_FIELD.schemaTag] ?? "",
        setId,
    };
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

export type ConfusionQueuePhase = "empty" | "active" | "finished";

export const CONFUSION_SECTION_CHOICES = ["ALL", "FAR", "AUD", "REG", "BAR", "ISC", "TCP"] as const;

export type ConfusionSectionChoice = (typeof CONFUSION_SECTION_CHOICES)[number];

export function selectedConfusionSection(raw: string | null): ConfusionSectionChoice {
    if (raw === null) {
        return "ALL";
    }
    const section = raw.trim().toUpperCase();
    if ((CONFUSION_SECTION_CHOICES as readonly string[]).includes(section)) {
        return section as ConfusionSectionChoice;
    }
    throw new Error(`Unknown CPA section: ${section}`);
}

export function confusionQueuePhase(index: number, itemCount: number): ConfusionQueuePhase {
    if (!Number.isInteger(index) || index < 0) {
        throw new Error("Confusion queue index must be a non-negative integer.");
    }
    if (!Number.isInteger(itemCount) || itemCount < 0) {
        throw new Error("Confusion queue length must be a non-negative integer.");
    }
    if (itemCount === 0) {
        return "empty";
    }
    return index >= itemCount ? "finished" : "active";
}
