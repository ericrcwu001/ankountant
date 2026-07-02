// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { Readiness, TopicScore } from "@generated/anki/scheduler_pb";
import { expect, test } from "vitest";

import { buildReadinessView, buildTopicRows, fractionToPct, isGapWarning } from "./lib";

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

test("sufficient view is a CPA band + point + coverage, never a bare point (A54)", () => {
    const view = buildReadinessView(
        new Readiness({
            abstain: false,
            bandLow: 62,
            bandHigh: 78,
            pointEstimate: 70,
            confidence: "High",
            coverage: 0.75,
            reasons: ["Coverage: 75% of topics; 40 sealed attempts"],
        }),
    );
    expect(view.abstain).toBe(false);
    expect(view.bandLow).toBeLessThan(view.bandHigh);
    // CPA scaled-score band (0-99), not a percentage.
    expect(view.bandLabel).toBe("62–78");
    expect(view.pointLabel).toBe("70");
    expect(view.pointEstimate).toBeGreaterThan(view.bandLow);
    expect(view.pointEstimate).toBeLessThan(view.bandHigh);
    expect(view.coveragePct).toBe(75);
    expect(view.confidence).toBe("High");
    expect(view.reasons.length).toBeGreaterThan(0);
});

test("fractionToPct rounds", () => {
    expect(fractionToPct(0.666)).toBe(67);
});
