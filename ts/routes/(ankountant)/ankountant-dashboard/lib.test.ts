// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { Readiness, TopicScore } from "@generated/anki/scheduler_pb";
import { expect, test } from "vitest";

import {
    buildReadinessEvidence,
    buildReadinessView,
    buildTopicRows,
    CPA_MAX_SCORE,
    formatUpdated,
    formatUpdatedLine,
    fractionToPct,
    isGapWarning,
} from "./lib";

test("gap-warning fires at the 0.25 threshold (A56)", () => {
    expect(isGapWarning(0.24)).toBe(false);
    expect(isGapWarning(0.25)).toBe(true);
    expect(isGapWarning(0.9 - 0.65)).toBe(true);
});

test("topic rows carry memory/performance/gap + gapWarning (A54/A56)", () => {
    const rows = buildTopicRows([
        new TopicScore({
            setId: "capex_vs_expense",
            memory: 0.9,
            performance: 0.65,
            gap: 0.25,
            memoryInsufficient: false,
        }),
    ]);
    expect(rows[0].memoryPct).toBe(90);
    expect(rows[0].performancePct).toBe(65);
    expect(rows[0].gapPct).toBe(25);
    expect(rows[0].gapWarning).toBe(true);
});

test("insufficient memory renders no number", () => {
    const rows = buildTopicRows([
        new TopicScore({ setId: "s", memory: 0, performance: 0.5, gap: 0, memoryInsufficient: true }),
    ]);
    expect(rows[0].memoryPct).toBe(null);
});

test("topic rows carry memory/performance confidence ranges (#3)", () => {
    const rows = buildTopicRows([
        new TopicScore({
            setId: "leases",
            memory: 0.72,
            performance: 0.6,
            gap: 0.12,
            memoryInsufficient: false,
            memoryLow: 0.64,
            memoryHigh: 0.8,
            performanceLow: 0.5,
            performanceHigh: 0.7,
        }),
    ]);
    expect(rows[0].memoryRange).toBe("64–80%");
    expect(rows[0].performanceRange).toBe("50–70%");
});

test("abstain view surfaces the reason + coverage and NO number (A55)", () => {
    const view = buildReadinessView(
        new Readiness({ abstain: true, reason: "insufficient volume", coverage: 0.4 }),
    );
    expect(view.abstain).toBe(true);
    expect(view.reason).toBe("insufficient volume");
    expect(view.bandLabel).toBe("");
    expect(view.coveragePct).toBe(40);
});

test("missing readiness data is named without inventing a volume diagnosis", () => {
    const view = buildReadinessView(undefined);
    expect(view.abstain).toBe(true);
    expect(view.reason).toBe("no readiness data");
    expect(view.bandLabel).toBe("");
});

test("sufficient view is a CPA band with internal midpoint and coverage (A54)", () => {
    const view = buildReadinessView(
        new Readiness({
            abstain: false,
            bandLow: 62,
            bandHigh: 78,
            pointEstimate: 70,
            confidence: "High",
            coverage: 0.75,
            generatedAt: 1_704_067_200n,
            reasons: ["Coverage: 75% of topics; 40 sealed attempts"],
        }),
    );
    expect(view.abstain).toBe(false);
    expect(view.bandLow).toBeLessThan(view.bandHigh);
    // CPA scaled-score band (0-99), not a percentage.
    expect(view.bandLabel).toBe("62–78");
    expect(view.pointEstimate).toBeGreaterThan(view.bandLow);
    expect(view.pointEstimate).toBeLessThan(view.bandHigh);
    expect(view.trackLeftPct).toBeCloseTo((62 / CPA_MAX_SCORE) * 100);
    expect(view.trackWidthPct).toBeCloseTo((16 / CPA_MAX_SCORE) * 100);
    expect(view.coveragePct).toBe(75);
    expect(view.confidence).toBe("High");
    expect(view.reasons.length).toBeGreaterThan(0);
});

test("emitted readiness requires a valid range, confidence, coverage, and evidence", () => {
    const valid = {
        abstain: false,
        bandLow: 62,
        bandHigh: 78,
        pointEstimate: 70,
        confidence: "High",
        coverage: 0.75,
        generatedAt: 1_704_067_200n,
        reasons: ["Coverage: 75% of topics; 40 sealed attempts"],
    };
    expect(() => buildReadinessView(new Readiness({ ...valid, bandHigh: 62 }))).toThrow(
        /low value below the high value/,
    );
    expect(() => buildReadinessView(new Readiness({ ...valid, pointEstimate: 90 }))).toThrow(
        /inside the reported band/,
    );
    expect(() => buildReadinessView(new Readiness({ ...valid, confidence: "" }))).toThrow(/confidence is required/);
    expect(() => buildReadinessView(new Readiness({ ...valid, reasons: [] }))).toThrow(/evidence reasons are required/);
    expect(() => buildReadinessView(new Readiness({ ...valid, generatedAt: 0n }))).toThrow(/generated timestamp/);
    expect(() => buildReadinessView(new Readiness({ ...valid, coverage: 1.1 }))).toThrow(
        /coverage must be between 0 and 1/,
    );
    expect(() => buildReadinessView(new Readiness({ ...valid, coverage: 0.4 }))).toThrow(
        /coverage must be at least 60%/,
    );
    expect(() => buildReadinessView(new Readiness({ ...valid, coverage: 0.596 }))).toThrow(
        /coverage must be at least 60%/,
    );
});

test("abstaining readiness requires an explicit reason", () => {
    expect(() => buildReadinessView(new Readiness({ abstain: true, reason: "", coverage: 0.4 }))).toThrow(
        /without a reason/,
    );
});

test("evidence view names missing data and the give-up rule", () => {
    const view = buildReadinessView(
        new Readiness({ abstain: true, reason: "insufficient volume", coverage: 0.4 }),
    );
    const rows = buildTopicRows([
        new TopicScore({
            setId: "tax_timing",
            memory: 0,
            performance: 0.42,
            gap: 0,
            memoryInsufficient: true,
        }),
    ]);
    const evidence = buildReadinessEvidence(view, rows);
    expect(evidence.giveUpRule).toContain("20 sealed attempts");
    expect(evidence.missingData.join(" ")).toContain("60% of topics");
    expect(evidence.missingData.join(" ")).toContain("tax timing");
    expect(evidence.calibrationStatus).toContain("No past score-verification history");
    expect(evidence.updatedAtLine).toContain("time unavailable");
});

test("evidence view chooses the largest memory-performance gap as next action", () => {
    const view = buildReadinessView(
        new Readiness({
            abstain: false,
            bandLow: 74,
            bandHigh: 85,
            pointEstimate: 80,
            confidence: "High",
            coverage: 1,
            generatedAt: 1_704_067_200n,
            reasons: ["Coverage: 100% of topics; 188 sealed attempts"],
        }),
    );
    const rows = buildTopicRows([
        new TopicScore({
            setId: "leases",
            memory: 0.9,
            performance: 0.52,
            gap: 0.38,
            memoryInsufficient: false,
        }),
        new TopicScore({
            setId: "tax_timing",
            memory: 0.7,
            performance: 0.51,
            gap: 0.19,
            memoryInsufficient: false,
        }),
    ]);
    const evidence = buildReadinessEvidence(view, rows);
    expect(evidence.nextAction).toContain("leases");
    expect(evidence.nextAction).toContain("memory is 90%");
    expect(evidence.missingData[0]).toContain("No hard blockers");
    expect(evidence.updatedAtLine).toMatch(/^Last updated /);
    expect(evidence.updatedAtLine).not.toContain("unavailable");
});

test("evidence view does not invent a memory value for thin-memory gaps", () => {
    const view = buildReadinessView(
        new Readiness({
            abstain: false,
            bandLow: 74,
            bandHigh: 85,
            pointEstimate: 80,
            confidence: "High",
            coverage: 1,
            generatedAt: 1_704_067_200n,
            reasons: ["Coverage: 100% of topics; 188 sealed attempts"],
        }),
    );
    const rows = buildTopicRows([
        new TopicScore({
            setId: "tax_timing",
            memory: 0,
            performance: 0.42,
            gap: 0.38,
            memoryInsufficient: true,
        }),
    ]);
    const evidence = buildReadinessEvidence(view, rows);
    expect(evidence.nextAction).toContain("sealed exam-style practice");
    expect(evidence.nextAction).not.toContain("memory is 0%");
});

test("fractionToPct rounds", () => {
    expect(fractionToPct(0.666)).toBe(67);
});

test("updated labels require positive generated timestamps", () => {
    expect(formatUpdated(0)).toBe("");
    expect(formatUpdated(-1)).toBe("");
    expect(formatUpdated(Number.NaN)).toBe("");
    expect(formatUpdated(Number.POSITIVE_INFINITY)).toBe("");
    expect(formatUpdatedLine(0)).toContain("time unavailable");
    expect(formatUpdatedLine(-1)).toContain("time unavailable");
    expect(formatUpdatedLine(Number.NaN)).toContain("time unavailable");
    expect(formatUpdatedLine(Number.POSITIVE_INFINITY)).toContain("time unavailable");
    expect(formatUpdatedLine(1_704_067_200)).toMatch(/^Last updated /);
});
