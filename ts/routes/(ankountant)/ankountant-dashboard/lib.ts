// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B5 (F015) — pure view-model helpers for the three-score readiness
// ! dashboard. Kept free of Svelte/DOM so they are unit-testable under
// ! `just test-ts` and reused by the Playwright-gated dashboard page.

import type { Readiness, TopicScore } from "@generated/anki/scheduler_pb";

/** A gap >= this threshold is flagged (contract A56 / B5-D3). */
export const GAP_WARNING_THRESHOLD = 0.25;

/** CPA scaled-score pass line (0-99 scale); mirrors Rust CPA_PASS_SCORE. */
export const CPA_PASS_SCORE = 75;
/** Top of the reported CPA scale; mirrors Rust CPA_MAX_SCORE. */
export const CPA_MAX_SCORE = 99;

/** View row for a single topic in the dashboard table. */
export interface TopicRow {
    setId: string;
    /** 0..100, or null when memory is insufficient. */
    memoryPct: number | null;
    performancePct: number;
    /** Confidence-range labels ("64–80%"), null when there is no band. */
    memoryRange: string | null;
    performanceRange: string | null;
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

/**
 * A confidence range label from two 0..1 fractions ("64–80%"), or null when the
 * band is empty/degenerate (no evidence) so the UI shows only the point.
 */
export function rangeLabel(low: number, high: number): string | null {
    const lo = fractionToPct(low);
    const hi = fractionToPct(high);
    if (hi <= lo) {
        return null;
    }
    return `${lo}–${hi}%`;
}

/** Build the per-topic dashboard rows from the GetReadiness topics. */
export function buildTopicRows(topics: TopicScore[]): TopicRow[] {
    return topics.map((t) => ({
        setId: t.setId,
        memoryPct: t.memoryInsufficient ? null : fractionToPct(t.memory),
        performancePct: fractionToPct(t.performance),
        memoryRange: t.memoryInsufficient ? null : rangeLabel(t.memoryLow, t.memoryHigh),
        performanceRange: rangeLabel(t.performanceLow, t.performanceHigh),
        gap: t.gap,
        gapPct: fractionToPct(t.gap),
        gapWarning: isGapWarning(t.gap),
    }));
}

/**
 * The exam-day readiness readout. When abstaining we surface the reason and
 * NO number (B5-D2 / A55); otherwise a low–high band on the CPA scaled-score
 * scale (0-99, pass 75) with a point estimate, confidence, exam coverage, the
 * factual drivers, and a last-updated time — never a bare single point
 * (B5-D1 / A54). The band is a heuristic projection (ADR 0005), not an official
 * AICPA score.
 */
export interface ReadinessView {
    abstain: boolean;
    reason: string;
    /** CPA 0-99 band + centre. */
    bandLow: number;
    bandHigh: number;
    pointEstimate: number;
    confidence: string;
    /** Percent of the exam's topics with sealed evidence so far. */
    coveragePct: number;
    /** Factual drivers behind the score (restated numbers, not causes). */
    reasons: string[];
    /** Unix seconds the score was computed (0 when unknown). */
    generatedAt: number;
    /** Human band string ("62–78"), only meaningful when !abstain. */
    bandLabel: string;
    /** Point-estimate string ("70"), only meaningful when !abstain. */
    pointLabel: string;
    /** Left/width/pass marker as 0..100 percentages for the band track. */
    trackLeftPct: number;
    trackWidthPct: number;
    trackPassPct: number;
}

export function buildReadinessView(readiness: Readiness | undefined): ReadinessView {
    const coveragePct = readiness ? fractionToPct(readiness.coverage) : 0;
    if (!readiness || readiness.abstain) {
        return {
            abstain: true,
            reason: readiness?.reason ?? "insufficient volume",
            bandLow: 0,
            bandHigh: 0,
            pointEstimate: 0,
            confidence: "",
            coveragePct,
            reasons: readiness?.reasons ?? [],
            generatedAt: readiness ? Number(readiness.generatedAt) : 0,
            bandLabel: "",
            pointLabel: "",
            trackLeftPct: 0,
            trackWidthPct: 0,
            trackPassPct: (CPA_PASS_SCORE / CPA_MAX_SCORE) * 100,
        };
    }
    const low = Math.round(readiness.bandLow);
    const high = Math.round(readiness.bandHigh);
    const point = Math.round(readiness.pointEstimate);
    return {
        abstain: false,
        reason: "",
        bandLow: low,
        bandHigh: high,
        pointEstimate: point,
        confidence: readiness.confidence,
        coveragePct,
        reasons: readiness.reasons ?? [],
        generatedAt: Number(readiness.generatedAt),
        bandLabel: `${low}–${high}`,
        pointLabel: `${point}`,
        trackLeftPct: (low / CPA_MAX_SCORE) * 100,
        trackWidthPct: (Math.max(high - low, 0) / CPA_MAX_SCORE) * 100,
        trackPassPct: (CPA_PASS_SCORE / CPA_MAX_SCORE) * 100,
    };
}

/** Short "Updated 3:04 PM" style label from Unix seconds (empty when unknown). */
export function formatUpdated(generatedAt: number): string {
    if (!generatedAt) {
        return "";
    }
    const d = new Date(generatedAt * 1000);
    return `Updated ${d.toLocaleString()}`;
}
