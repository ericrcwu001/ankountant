// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B5 (F015) — pure view-model helpers for the three-score readiness
// ! dashboard. Kept free of Svelte/DOM so they are unit-testable under
// ! `just test-ts` and reused by the Playwright-gated dashboard page.

import type { Readiness, TopicScore } from "@generated/anki/scheduler_pb";

/** A gap >= this threshold is flagged (contract A56 / B5-D3). */
export const GAP_WARNING_THRESHOLD = 0.25;

/** View row for a single topic in the dashboard table. */
export interface TopicRow {
    setId: string;
    /** 0..100, or null when memory is insufficient. */
    memoryPct: number | null;
    performancePct: number;
    gap: number;
    gapPct: number;
    /** True when the gap crosses GAP_WARNING_THRESHOLD (B5-D3). */
    gapWarning: boolean;
}

/** Format a 0..1 fraction as an integer percentage string. */
export function fractionToPct(fraction: number): number {
    return Math.round(fraction * 100);
}

/** True when the "feels ready, isn't" gap should be visually flagged. */
export function isGapWarning(gap: number): boolean {
    return gap >= GAP_WARNING_THRESHOLD;
}

/** Build the per-topic dashboard rows from the GetReadiness topics. */
export function buildTopicRows(topics: TopicScore[]): TopicRow[] {
    return topics.map((t) => ({
        setId: t.setId,
        memoryPct: t.memoryInsufficient ? null : fractionToPct(t.memory),
        performancePct: fractionToPct(t.performance),
        gap: t.gap,
        gapPct: fractionToPct(t.gap),
        gapWarning: isGapWarning(t.gap),
    }));
}

/**
 * The exam-day readiness readout. When abstaining we surface the reason and
 * NO number (B5-D2 / A55); otherwise a low–high band + confidence, never a
 * single point (B5-D1 / A54).
 */
export interface ReadinessView {
    abstain: boolean;
    reason: string;
    bandLow: number;
    bandHigh: number;
    confidence: string;
    /** Human band string, only meaningful when !abstain. */
    bandLabel: string;
}

export function buildReadinessView(readiness: Readiness | undefined): ReadinessView {
    if (!readiness || readiness.abstain) {
        return {
            abstain: true,
            reason: readiness?.reason ?? "insufficient volume",
            bandLow: 0,
            bandHigh: 0,
            confidence: "",
            bandLabel: "",
        };
    }
    const low = Math.round(readiness.bandLow);
    const high = Math.round(readiness.bandHigh);
    return {
        abstain: false,
        reason: "",
        bandLow: low,
        bandHigh: high,
        confidence: readiness.confidence,
        bandLabel: `${low}%–${high}%`,
    };
}
