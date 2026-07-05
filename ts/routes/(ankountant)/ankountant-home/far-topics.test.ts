// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { type GetReadinessResponse, TopicScore } from "@generated/anki/scheduler_pb";
import { expect, test } from "vitest";

import { buildFarTopics, buildSectionTopics, needsAttention, topicRowCounts, topStrongTopics } from "./far-topics";
import { heightForTopicScore } from "./topo";

const rounded = (value: number): number => Number(value.toFixed(3));

const topic = (setId: string, performance: number): TopicScore => {
    const low = Math.max(0, performance - 0.08);
    const high = Math.min(1, performance + 0.08);
    return ({
        setId,
        memory: performance,
        performance,
        gap: 0,
        memoryInsufficient: false,
        memoryLow: low,
        memoryHigh: high,
        performanceLow: low,
        performanceHigh: high,
    }) as unknown as TopicScore;
};

test("FAR topic mountains are ranked by preparedness, row-major", () => {
    const readiness = {
        topics: [
            topic("operating_vs_finance_lease", 0.67),
            topic("revrec_step_selection", 0.91),
            topic("capitalize_vs_expense", 0.84),
            topic("inventory_valuation", 0.75),
            topic("trading_afs_htm", 0.98),
            topic("tax_timing", 0.62),
            topic("debt_extinguishment", 0.71),
            topic("intangibles_impairment", 0.89),
            topic("cash_receivables", 0.53),
            topic("financial_statements", 0.77),
            topic("conceptual_framework", 0.69),
            topic("pensions_equity", 0.58),
            topic("government_nfp", 0.81),
        ],
    } as unknown as GetReadinessResponse;

    const topics = buildFarTopics(readiness);
    const expectedScores = [
        98,
        91,
        89,
        84,
        81,
        77,
        75,
        71,
        69,
        67,
        62,
        58,
        53,
    ];

    expect(topics.map((t) => t.performance)).toEqual(expectedScores);
    expect(topics.slice(0, 6).map((t) => t.tier)).toEqual([
        "back",
        "back",
        "back",
        "back",
        "back",
        "back",
    ]);
    expect(topics.slice(6).every((t) => t.tier === "front")).toBe(true);
    expect(topics.slice(0, 6).map((t) => rounded(t.cx))).toEqual([
        0.1,
        0.26,
        0.42,
        0.58,
        0.74,
        0.9,
    ]);
    expect(topics.slice(6).map((t) => rounded(t.cx))).toEqual([
        0.064,
        0.209,
        0.355,
        0.5,
        0.645,
        0.791,
        0.936,
    ]);
    expect(topics.map((t) => t.height)).toEqual(
        topics.map((topic) => heightForTopicScore(topic.performance ?? 0, topic.tier)),
    );
});

test("topic mountain rows are split from the total category count", () => {
    expect(topicRowCounts(0)).toEqual({ back: 0, front: 0 });
    expect(topicRowCounts(1)).toEqual({ back: 1, front: 0 });
    expect(topicRowCounts(2)).toEqual({ back: 1, front: 1 });
    expect(topicRowCounts(13)).toEqual({ back: 6, front: 7 });
    expect(() => topicRowCounts(1.5)).toThrow(/Invalid topic count/);
});

test("non-FAR sections use emitted topics without FAR placeholders", () => {
    const readiness = {
        topics: [
            topic("aud_evidence_sufficiency", 0.72),
            topic("aud_request_relevance", 0.81),
        ],
    } as unknown as GetReadinessResponse;

    const topics = buildSectionTopics(readiness, "AUD");

    expect(topics.map((t) => t.setId)).toEqual([
        "aud_request_relevance",
        "aud_evidence_sufficiency",
    ]);
    expect(topics.map((t) => t.label)).toEqual([
        "Request relevance",
        "Evidence sufficiency",
    ]);
    expect(topics.map((t) => t.tier)).toEqual(["back", "front"]);
    expect(topics.map((t) => rounded(t.cx))).toEqual([0.38, 0.62]);
    expect(topics.every((t) => !t.setId.includes("lease"))).toBe(true);
});

test("thin performance leaves Home topics unproven", () => {
    const readiness = {
        topics: [
            new TopicScore({
                setId: "trading_afs_htm",
                memory: 0.8,
                performance: 0,
                gap: 0.8,
                memoryInsufficient: false,
                memoryLow: 0.7,
                memoryHigh: 0.9,
                performanceLow: 0,
                performanceHigh: 0,
            }),
        ],
    } as unknown as GetReadinessResponse;

    const topic = buildFarTopics(readiness).find((t) => t.setId === "trading_afs_htm");

    expect(topic?.performance).toBe(null);
    expect(topic?.gap).toBe(null);
    expect(topic?.height).toBe(0);
    expect(topic?.unproven).toBe(true);
    expect(topStrongTopics(buildFarTopics(readiness))).toEqual([]);
    expect(needsAttention(buildFarTopics(readiness))).toEqual([]);
});

test("nonzero Home performance without a confidence band is rejected", () => {
    const readiness = {
        topics: [
            new TopicScore({
                setId: "trading_afs_htm",
                memory: 0.8,
                performance: 0.7,
                gap: 0.1,
                memoryInsufficient: false,
                memoryLow: 0.7,
                memoryHigh: 0.9,
                performanceLow: 0,
                performanceHigh: 0,
            }),
        ],
    } as unknown as GetReadinessResponse;

    expect(() => buildFarTopics(readiness)).toThrow(/without a confidence band/);
});

test("Home topics reject memory without a confidence band", () => {
    const readiness = {
        topics: [
            new TopicScore({
                setId: "trading_afs_htm",
                memory: 0.8,
                performance: 0,
                gap: 0,
                memoryInsufficient: false,
                memoryLow: 0,
                memoryHigh: 0,
                performanceLow: 0,
                performanceHigh: 0,
            }),
        ],
    } as unknown as GetReadinessResponse;

    expect(() => buildFarTopics(readiness)).toThrow(/memory requires a non-empty confidence band/);
});
