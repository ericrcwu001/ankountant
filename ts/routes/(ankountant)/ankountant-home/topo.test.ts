// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    buildTopoRange,
    heightForTopicScore,
    TOPIC_MAX_SCORE,
    TOPIC_PASS_SCORE,
    type TopoTopic,
    yForTopicScore,
} from "./topo";

test("heightForTopicScore maps topic score percentages onto 0..1", () => {
    expect(heightForTopicScore(0)).toBe(0);
    expect(heightForTopicScore(75)).toBeGreaterThan(0.65);
    expect(heightForTopicScore(75)).toBeLessThan(0.75);
    expect(heightForTopicScore(TOPIC_MAX_SCORE)).toBe(1);
    expect(heightForTopicScore(-4)).toBe(0);
    expect(heightForTopicScore(130)).toBe(1);
    expect(heightForTopicScore(90) - heightForTopicScore(80)).toBeGreaterThan(0.1);
});

test("topic heights use one pass-line scale across both rows", () => {
    expect(heightForTopicScore(0, "front")).toBe(0);
    expect(heightForTopicScore(82, "front")).toBeGreaterThan(heightForTopicScore(60, "front"));
    expect(heightForTopicScore(82, "front")).toBe(heightForTopicScore(82, "back"));
    expect(heightForTopicScore(TOPIC_MAX_SCORE, "front")).toBe(1);
});

test("topo flags and pass line use the topic performance y-axis", () => {
    const topics: TopoTopic[] = [
        {
            key: "back-above",
            label: "Back Above",
            score: 90,
            cx: 0.2,
            height: 0.9,
            tier: "back",
        },
        {
            key: "back-mid",
            label: "Back Mid",
            score: 75,
            cx: 0.5,
            height: 0.75,
            tier: "back",
        },
        {
            key: "front-mid",
            label: "Front Mid",
            score: 75,
            cx: 0.6,
            height: 0.75,
            tier: "front",
        },
        {
            key: "front-lower",
            label: "Front Lower",
            score: 60,
            cx: 0.8,
            height: 0.6,
            tier: "front",
        },
    ];
    const range = buildTopoRange(topics, { width: 1000, height: 680 });
    const plotH = range.height * 0.86;

    expect(range.passY).toBeCloseTo(
        yForTopicScore(TOPIC_PASS_SCORE, range.baseY, plotH, "back"),
    );
    expect(yForTopicScore(0, range.baseY, plotH)).toBe(range.height);
    expect(range.flags.find((f) => f.key === "back-mid")?.y).toBeCloseTo(
        yForTopicScore(75, range.baseY, plotH, "back"),
    );
    expect(range.flags.find((f) => f.key === "back-above")?.y).toBeLessThan(
        yForTopicScore(75, range.baseY, plotH, "back"),
    );
    expect(range.flags.find((f) => f.key === "front-lower")?.y).toBeCloseTo(
        yForTopicScore(60, range.baseY, plotH, "front"),
    );
    expect(range.flags.find((f) => f.key === "front-mid")?.y).toBeCloseTo(
        range.passY,
    );
});
