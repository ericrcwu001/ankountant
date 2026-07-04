// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Pure, DOM-free view-model helpers for the Home "summit" — the topographic
// ! range of CPA sections. Mirrors the iOS `AnkiKit/ReadinessTopo.swift`: peak
// ! height = a section's readiness point on the CPA 0-99 scale, pass line at 75,
// ! and "unproven" gated on `abstain` (never on height). Kept Svelte-free so it
// ! is unit-testable under `just test-ts`.

import type { GetReadinessResponse, Readiness } from "@generated/anki/scheduler_pb";

import { buildReadinessView, CPA_MAX_SCORE, CPA_PASS_SCORE } from "../ankountant-dashboard/lib";

/** A CPA exam section shown as a summit peak. */
export interface CpaSection {
    code: string;
    name: string;
}

/**
 * The five summit sections, FAR first. BAR (the discipline the candidate did
 * not pick) is intentionally excluded from the Home range.
 */
export const SUMMIT_SECTIONS: CpaSection[] = [
    { code: "FAR", name: "Financial Accounting and Reporting" },
    { code: "AUD", name: "Auditing and Attestation" },
    { code: "REG", name: "Regulation" },
    { code: "TCP", name: "Tax Compliance and Planning" },
    { code: "ISC", name: "Information Systems and Controls" },
];

export const DEFAULT_SUMMIT_SECTION = "FAR";

export function sectionName(raw: string): string {
    const code = raw.trim().toUpperCase();
    const section = SUMMIT_SECTIONS.find((s) => s.code === code);
    if (!section) {
        throw new Error(`Unknown CPA section: ${code}`);
    }
    return section.name;
}

export function selectedSummitSection(raw: string | null): string {
    const section = (raw ?? DEFAULT_SUMMIT_SECTION).trim().toUpperCase();
    if (!SUMMIT_SECTIONS.some((s) => s.code === section)) {
        throw new Error(`Unknown CPA section: ${section}`);
    }
    return section;
}

export type PassStanding = "unproven" | "below" | "above";

/** Normalized 0..1 height on the CPA 0..99 axis (clamped). */
export function heightForScore(score: number): number {
    const clamped = Math.min(Math.max(score, 0), CPA_MAX_SCORE);
    return clamped / CPA_MAX_SCORE;
}

/** The pass line's normalized position (0..1). */
export const PASS_HEIGHT = heightForScore(CPA_PASS_SCORE);

/**
 * Score (0..99) → a top-down y within [top, top + plotHeight] (99 at the top, 0
 * at the base). Mirrors iOS `TopoScale.y`; kept pure so the ≥75 geometry
 * invariant is directly unit-testable without rendering.
 */
export function yForScore(score: number, top: number, plotHeight: number): number {
    return top + plotHeight * (1 - heightForScore(score));
}

/**
 * Above/below the pass line. Gated on `abstain` — NEVER on height, because an
 * abstaining band carries `pointEstimate` 0 and would masquerade as a real 0.
 */
export function passStanding(readiness: Readiness | undefined): PassStanding {
    if (!readiness || readiness.abstain) {
        return "unproven";
    }
    return readiness.pointEstimate >= CPA_PASS_SCORE ? "above" : "below";
}

/** One section's peak on the summit range. */
export interface SectionPeak {
    code: string;
    name: string;
    standing: PassStanding;
    /** CPA point (0..99), null when unproven. */
    point: number | null;
    /** Wilson band endpoints on the CPA scale (0..99), null when unproven. */
    bandLow: number | null;
    bandHigh: number | null;
    /** Confidence label ("Med"/"High"); empty when unproven. */
    confidence: string;
}

export function buildSectionPeak(
    section: CpaSection,
    readiness: Readiness | undefined,
): SectionPeak {
    const view = buildReadinessView(readiness);
    if (view.abstain) {
        return {
            code: section.code,
            name: section.name,
            standing: "unproven",
            point: null,
            bandLow: null,
            bandHigh: null,
            confidence: "",
        };
    }
    return {
        code: section.code,
        name: section.name,
        standing: view.pointEstimate >= CPA_PASS_SCORE ? "above" : "below",
        point: view.pointEstimate,
        bandLow: view.bandLow,
        bandHigh: view.bandHigh,
        confidence: view.confidence,
    };
}

/** Build peaks for all summit sections from a `code -> response` map. */
export function buildSummit(
    byCode: Record<string, GetReadinessResponse | undefined>,
): SectionPeak[] {
    return SUMMIT_SECTIONS.map((s) => buildSectionPeak(s, byCode[s.code]?.readiness));
}
