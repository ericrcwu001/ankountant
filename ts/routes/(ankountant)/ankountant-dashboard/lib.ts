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
export const READINESS_MIN_SEALED_ATTEMPTS = 20;
export const READINESS_MIN_COVERAGE_PCT = 60;

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

export interface ReadinessEvidence {
    evidenceLines: string[];
    updatedAtLine: string;
    missingData: string[];
    calibrationStatus: string;
    nextAction: string;
    giveUpRule: string;
}

/** Format a 0..1 fraction as an integer percentage string. */
export function fractionToPct(fraction: number): number {
    return Math.round(fraction * 100);
}

/** True when the "feels ready, isn't" gap should be visually flagged. */
export function isGapWarning(gap: number): boolean {
    return gap >= GAP_WARNING_THRESHOLD;
}

export function prettySetId(setId: string): string {
    return setId.replace(/_/g, " ");
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
    /** Left/width/pass marker as 0..100 percentages for the band track. */
    trackLeftPct: number;
    trackWidthPct: number;
    trackPassPct: number;
}

export function buildReadinessView(readiness: Readiness | undefined): ReadinessView {
    const coveragePct = readiness ? coveragePercent(readiness.coverage) : 0;
    if (!readiness || readiness.abstain) {
        if (readiness && !readiness.reason.trim()) {
            throw new Error("Readiness abstained without a reason.");
        }
        return {
            abstain: true,
            reason: readiness?.reason ?? "no readiness data",
            bandLow: 0,
            bandHigh: 0,
            pointEstimate: 0,
            confidence: "",
            coveragePct,
            reasons: readiness?.reasons ?? [],
            generatedAt: readiness ? Number(readiness.generatedAt) : 0,
            bandLabel: "",
            trackLeftPct: 0,
            trackWidthPct: 0,
            trackPassPct: (CPA_PASS_SCORE / CPA_MAX_SCORE) * 100,
        };
    }
    validateEmittedReadiness(readiness);
    const low = Math.round(readiness.bandLow);
    const high = Math.round(readiness.bandHigh);
    const point = Math.round(readiness.pointEstimate);
    const reasons = (readiness.reasons ?? []).map((reason) => reason.trim());
    return {
        abstain: false,
        reason: "",
        bandLow: low,
        bandHigh: high,
        pointEstimate: point,
        confidence: readiness.confidence.trim(),
        coveragePct,
        reasons,
        generatedAt: Number(readiness.generatedAt),
        bandLabel: `${low}–${high}`,
        trackLeftPct: (low / CPA_MAX_SCORE) * 100,
        trackWidthPct: (Math.max(high - low, 0) / CPA_MAX_SCORE) * 100,
        trackPassPct: (CPA_PASS_SCORE / CPA_MAX_SCORE) * 100,
    };
}

export function buildReadinessEvidence(
    view: ReadinessView,
    rows: TopicRow[],
): ReadinessEvidence {
    if (!view.abstain && !view.reasons.length) {
        throw new Error("Readiness evidence requires reasons for the emitted range.");
    }
    const missingData: string[] = [];
    if (view.abstain && view.reason.toLowerCase().includes("volume")) {
        missingData.push(
            `Need at least ${READINESS_MIN_SEALED_ATTEMPTS} sealed attempts before a readiness range can be shown.`,
        );
    }
    if (view.coveragePct < READINESS_MIN_COVERAGE_PCT) {
        missingData.push(
            `Need sealed evidence across ${READINESS_MIN_COVERAGE_PCT}% of topics; current coverage is ${view.coveragePct}%.`,
        );
    }

    const thinMemory = rows.filter((row) => row.memoryPct === null).slice(0, 3);
    if (thinMemory.length) {
        missingData.push(
            `Memory is still thin for ${thinMemory.map((row) => prettySetId(row.setId)).join(", ")}.`,
        );
    }
    if (!missingData.length) {
        missingData.push("No hard blockers for the current range; more sealed attempts will narrow uncertainty.");
    }

    const evidenceLines = view.reasons.length
        ? view.reasons
        : [view.reason];

    return {
        evidenceLines,
        updatedAtLine: formatUpdatedLine(view.generatedAt),
        missingData,
        calibrationStatus:
            "No past score-verification history is available yet; treat this as an uncalibrated projection until held-out outcomes are logged.",
        nextAction: bestNextAction(view, rows),
        giveUpRule:
            `No readiness range until there are at least ${READINESS_MIN_SEALED_ATTEMPTS} sealed attempts and ${READINESS_MIN_COVERAGE_PCT}% topic coverage.`,
    };
}

function coveragePercent(coverage: number): number {
    assertFiniteNumber("coverage", coverage);
    if (coverage < 0 || coverage > 1) {
        throw new Error("Readiness coverage must be between 0 and 1.");
    }
    return fractionToPct(coverage);
}

function validateEmittedReadiness(readiness: Readiness): void {
    const reasons = readiness.reasons ?? [];
    if (readiness.coverage < READINESS_MIN_COVERAGE_PCT / 100) {
        throw new Error(
            `Readiness coverage must be at least ${READINESS_MIN_COVERAGE_PCT}% for an emitted range.`,
        );
    }
    assertScaleValue("band low", readiness.bandLow);
    assertScaleValue("band high", readiness.bandHigh);
    assertScaleValue("point estimate", readiness.pointEstimate);
    if (readiness.bandLow >= readiness.bandHigh) {
        throw new Error("Readiness band must have a low value below the high value.");
    }
    if (
        readiness.pointEstimate < readiness.bandLow
        || readiness.pointEstimate > readiness.bandHigh
    ) {
        throw new Error("Readiness point estimate must be inside the reported band.");
    }
    if (!readiness.confidence.trim()) {
        throw new Error("Readiness confidence is required for an emitted range.");
    }
    if (!reasons.length || reasons.some((reason) => !reason.trim())) {
        throw new Error("Readiness evidence reasons are required for an emitted range.");
    }
    assertGeneratedAt(Number(readiness.generatedAt));
}

function assertGeneratedAt(generatedAt: number): void {
    if (!Number.isFinite(generatedAt) || generatedAt <= 0) {
        throw new Error("Readiness generated timestamp is required for an emitted range.");
    }
}

function assertScaleValue(label: string, value: number): void {
    assertFiniteNumber(label, value);
    if (value < 0 || value > CPA_MAX_SCORE) {
        throw new Error(`Readiness ${label} must be between 0 and ${CPA_MAX_SCORE}.`);
    }
}

function assertFiniteNumber(label: string, value: number): void {
    if (!Number.isFinite(value)) {
        throw new Error(`Readiness ${label} must be a finite number.`);
    }
}

function bestNextAction(view: ReadinessView, rows: TopicRow[]): string {
    if (!rows.length) {
        return "Load a CPA bank or demo profile, then start sealed practice.";
    }
    if (view.coveragePct < READINESS_MIN_COVERAGE_PCT) {
        return "Add sealed exam-style attempts in uncovered topics before trusting the readiness range.";
    }

    const gap = [...rows]
        .filter((row) => row.gapWarning && row.memoryPct !== null)
        .sort((a, b) => b.gap - a.gap)[0];
    if (gap) {
        return `Run a confusion-set drill for ${
            prettySetId(gap.setId)
        }; memory is ${gap.memoryPct}% and performance is ${gap.performancePct}%.`;
    }

    const weakest = [...rows].sort((a, b) => a.performancePct - b.performancePct)[0];
    return `Do sealed exam-style practice for ${
        prettySetId(weakest.setId)
    }; current performance is ${weakest.performancePct}%.`;
}

/** Short "Updated 3:04 PM" style label from Unix seconds (empty when unknown). */
export function formatUpdated(generatedAt: number): string {
    if (!Number.isFinite(generatedAt) || generatedAt <= 0) {
        return "";
    }
    const d = new Date(generatedAt * 1000);
    return `Updated ${d.toLocaleString()}`;
}

export function formatUpdatedLine(generatedAt: number): string {
    if (!Number.isFinite(generatedAt) || generatedAt <= 0) {
        return "Last updated time unavailable; refresh readiness after more graded evidence is logged.";
    }
    const d = new Date(generatedAt * 1000);
    return `Last updated ${d.toLocaleString()}.`;
}
