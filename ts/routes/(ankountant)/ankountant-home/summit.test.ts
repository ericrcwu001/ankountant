// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { Readiness } from "@generated/anki/scheduler_pb";
import { expect, test } from "vitest";

import { CPA_PASS_SCORE } from "../ankountant-dashboard/lib";
import {
    buildSectionPeak,
    DEFAULT_SUMMIT_SECTION,
    heightForScore,
    PASS_HEIGHT,
    passStanding,
    sectionName,
    selectedSummitSection,
    SUMMIT_SECTIONS,
    yForScore,
} from "./summit";

const rd = (o: Partial<Readiness>): Readiness => o as unknown as Readiness;
const provenReadiness = (o: Partial<Readiness>): Readiness =>
    rd({
        abstain: false,
        bandLow: 62,
        bandHigh: 78,
        pointEstimate: 70,
        confidence: "High",
        coverage: 0.75,
        generatedAt: 1_704_067_200n,
        reasons: ["Coverage: 75% of topics; 40 sealed attempts"],
        ...o,
    });

test("heightForScore maps the CPA 0-99 axis to 0..1 and clamps", () => {
    expect(heightForScore(0)).toBe(0);
    expect(heightForScore(99)).toBe(1);
    expect(heightForScore(-10)).toBe(0);
    expect(heightForScore(200)).toBe(1);
    expect(heightForScore(84)).toBeGreaterThan(heightForScore(61));
    expect(PASS_HEIGHT).toBe(heightForScore(CPA_PASS_SCORE));
});

test("yForScore is strictly decreasing; >=75 sits on/above the pass line", () => {
    const TOP = 14;
    const PLOT_H = 180;
    const passY = yForScore(CPA_PASS_SCORE, TOP, PLOT_H);
    expect(yForScore(84, TOP, PLOT_H)).toBeLessThan(passY);
    expect(yForScore(61, TOP, PLOT_H)).toBeGreaterThan(passY);
    // Exhaustive: the geometry never contradicts the scalar classification.
    for (let s = 0; s <= 99; s++) {
        expect(s >= CPA_PASS_SCORE).toBe(yForScore(s, TOP, PLOT_H) <= passY);
    }
});

test("passStanding: >=75 above, <75 below, inclusive at the pass line", () => {
    expect(passStanding(rd({ abstain: false, pointEstimate: 84 }))).toBe("above");
    expect(passStanding(rd({ abstain: false, pointEstimate: 61 }))).toBe("below");
    expect(passStanding(rd({ abstain: false, pointEstimate: 75 }))).toBe("above");
    expect(passStanding(rd({ abstain: false, pointEstimate: 74.99 }))).toBe("below");
});

test("passStanding: abstain (or missing) is unproven even with a zero point", () => {
    // The trap: an abstaining band carries pointEstimate 0.
    expect(passStanding(rd({ abstain: true, pointEstimate: 0 }))).toBe("unproven");
    expect(passStanding(undefined)).toBe("unproven");
});

test("summit sections are the five, FAR first, BAR excluded", () => {
    expect(SUMMIT_SECTIONS.map((s) => s.code)).toEqual(["FAR", "AUD", "REG", "TCP", "ISC"]);
    expect(sectionName("TCP")).toBe("Tax Compliance and Planning");
    expect(sectionName(" tcp ")).toBe("Tax Compliance and Planning");
    expect(() => sectionName("BAR")).toThrow(/Unknown CPA section/);
});

test("selectedSummitSection defaults, normalizes, and rejects unknown sections", () => {
    expect(selectedSummitSection(null)).toBe(DEFAULT_SUMMIT_SECTION);
    expect(selectedSummitSection(" aud ")).toBe("AUD");
    expect(() => selectedSummitSection("BAR")).toThrow(/Unknown CPA section/);
});

test("buildSectionPeak fills proven peaks and blanks unproven ones", () => {
    const proven = buildSectionPeak(
        { code: "FAR", name: "Financial Accounting and Reporting" },
        provenReadiness({ pointEstimate: 61, bandLow: 44, bandHigh: 75, confidence: "Med" }),
    );
    expect(proven).toMatchObject({
        standing: "below",
        point: 61,
        bandLow: 44,
        bandHigh: 75,
        confidence: "Med",
    });

    const unproven = buildSectionPeak(
        { code: "AUD", name: "Auditing and Attestation" },
        rd({ abstain: true, reason: "insufficient volume", pointEstimate: 0, coverage: 0 }),
    );
    expect(unproven).toMatchObject({
        standing: "unproven",
        point: null,
        bandLow: null,
        bandHigh: null,
    });
});

test("buildSectionPeak rejects invalid emitted readiness instead of plotting it", () => {
    expect(() =>
        buildSectionPeak(
            { code: "FAR", name: "Financial Accounting and Reporting" },
            provenReadiness({ pointEstimate: 90, bandLow: 62, bandHigh: 78 }),
        )
    ).toThrow(/inside the reported band/);
});
