// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Pure, DOM-free view-model helpers for the Ankountant Home hero (the
// ! days-until-exam countdown). Kept free of Svelte so they are unit-testable
// ! under `just test-ts`.

/**
 * Whole days from local "today" to an ISO-8601 (YYYY-MM-DD) exam date; negative
 * when the date is in the past, `null` when the string is empty/invalid. Mirrors
 * the Rust `days_to_exam` (local calendar days) so both clients agree.
 */
export function daysUntil(iso: string, today: Date = new Date()): number | null {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
    if (!match) {
        return null;
    }
    const [, y, m, d] = match;
    const exam = new Date(Number(y), Number(m) - 1, Number(d));
    if (
        Number.isNaN(exam.getTime())
        || exam.getMonth() !== Number(m) - 1
        || exam.getDate() !== Number(d)
    ) {
        return null;
    }
    const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    return Math.round((exam.getTime() - startOfToday.getTime()) / 86_400_000);
}

/** The hero countdown widget's view-model. */
export interface CountdownView {
    /** Whether a valid exam date is set. */
    hasDate: boolean;
    /** Days until the exam (negative if past); null when no valid date. */
    days: number | null;
    /** Big neutral-ink numeral for the hero ("—" when unset). */
    numeral: string;
    /** Caption under the numeral. */
    caption: string;
}

export function buildCountdown(iso: string, today: Date = new Date()): CountdownView {
    const days = daysUntil(iso, today);
    if (days === null) {
        return { hasDate: false, days: null, numeral: "—", caption: "Set your exam date" };
    }
    if (days > 0) {
        return {
            hasDate: true,
            days,
            numeral: String(days),
            caption: days === 1 ? "day until exam" : "days until exam",
        };
    }
    if (days === 0) {
        return { hasDate: true, days, numeral: "0", caption: "Exam day — good luck" };
    }
    const past = Math.abs(days);
    return {
        hasDate: true,
        days,
        numeral: String(past),
        caption: past === 1 ? "day since exam" : "days since exam",
    };
}

// ! Phase-aware primary CTA. The "single dial is days-to-exam" (brainlift SPOV
// ! 1): effortful discrimination far from the exam, consolidation in the final
// ! stretch — with a beginner override so rank beginners get a blocked recall
// ! intro first (SPOV 3 boundary / worked-example effect).

/**
 * Final-stretch window (days). Sits below the backend's 60-day ramp horizon
 * (rslib `RAMP_HORIZON_DAYS`, where desired retention starts climbing toward
 * its peak); tunable.
 */
export const CONSOLIDATION_WINDOW_DAYS = 14;

export type Phase = "foundation" | "discrimination" | "consolidation";

/**
 * Pick the study phase from days-to-exam plus whether the student has any
 * memory base yet. No base → foundation (blocked recall), regardless of date;
 * inside the final stretch → consolidation; otherwise the core primitive,
 * discrimination (confusion set).
 */
export function choosePhase(
    { days, memoryReady }: { days: number | null; memoryReady: boolean },
): Phase {
    if (!memoryReady) {
        return "foundation";
    }
    if (days !== null && days >= 0 && days <= CONSOLIDATION_WINDOW_DAYS) {
        return "consolidation";
    }
    return "discrimination";
}

/** View-model for the phase-aware primary button (dynamic label + subtitle). */
export interface PhaseCta {
    phase: Phase;
    label: string;
    subtitle: string;
    /** Which study surface the button opens. */
    target: "recall" | "confusion";
}

export function buildPhaseCta(phase: Phase): PhaseCta {
    switch (phase) {
        case "foundation":
            return {
                phase,
                label: "Build foundation",
                subtitle: "Blocked recall — learn the material first",
                target: "recall",
            };
        case "consolidation":
            return {
                phase,
                label: "Consolidate",
                subtitle: "Lock in recall to peak on exam day",
                target: "recall",
            };
        default:
            return {
                phase,
                label: "Discrimination drill",
                subtitle: "Interleaved which-treatment practice",
                target: "confusion",
            };
    }
}
