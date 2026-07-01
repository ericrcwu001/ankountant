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

test("abstain view surfaces the reason and NO number (A55)", () => {
    const view = buildReadinessView(
        new Readiness({ abstain: true, reason: "insufficient volume" }),
    );
    expect(view.abstain).toBe(true);
    expect(view.reason).toBe("insufficient volume");
    expect(view.bandLabel).toBe("");
});

test("sufficient view is a band, never a point (A54)", () => {
    const view = buildReadinessView(
        new Readiness({ abstain: false, bandLow: 62, bandHigh: 78, confidence: "High" }),
    );
    expect(view.abstain).toBe(false);
    expect(view.bandLow).toBeLessThan(view.bandHigh);
    expect(view.bandLabel).toBe("62%–78%");
    expect(view.confidence).toBe("High");
});

test("fractionToPct rounds", () => {
    expect(fractionToPct(0.666)).toBe(67);
});
