// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { TopicScore } from "@generated/anki/scheduler_pb";

const TOPIC_GAP_EPSILON = 1e-9;

export function hasTopicPerformanceEvidence(topic: TopicScore): boolean {
    const hasConfidenceBand = topic.performanceLow !== 0 || topic.performanceHigh !== 0;
    if (!hasConfidenceBand && topic.performance !== 0) {
        throw new Error("Topic performance cannot be non-zero without a confidence band.");
    }
    return hasConfidenceBand;
}

export function validateTopicScoreEvidence(topic: TopicScore): void {
    if (!topic.setId.trim()) {
        throw new Error("Topic score requires a set id.");
    }
    if (topic.memoryInsufficient) {
        assertMissingTopicEvidence("memory", topic.memory, topic.memoryLow, topic.memoryHigh);
    } else {
        assertTopicEvidenceRange("memory", topic.memory, topic.memoryLow, topic.memoryHigh);
    }
    const hasPerformanceEvidence = hasTopicPerformanceEvidence(topic);
    if (hasPerformanceEvidence) {
        assertTopicEvidenceRange("performance", topic.performance, topic.performanceLow, topic.performanceHigh);
    }
    if (!topic.memoryInsufficient && hasPerformanceEvidence) {
        assertGap(topic.gap, topic.memory, topic.performance);
    }
}

function assertMissingTopicEvidence(metric: string, value: number, low: number, high: number): void {
    if (value !== 0 || low !== 0 || high !== 0) {
        throw new Error(`Topic ${metric} cannot be marked insufficient with evidence values.`);
    }
}

function assertTopicEvidenceRange(metric: string, value: number, low: number, high: number): void {
    assertFraction(`topic ${metric}`, value);
    assertFraction(`topic ${metric} low`, low);
    assertFraction(`topic ${metric} high`, high);
    if (low >= high) {
        throw new Error(`Topic ${metric} requires a non-empty confidence band.`);
    }
    if (value < low || value > high) {
        throw new Error(`Topic ${metric} point must be inside its confidence band.`);
    }
}

function assertFraction(label: string, value: number): void {
    if (!Number.isFinite(value)) {
        throw new Error(`${label} must be a finite number.`);
    }
    if (value < 0 || value > 1) {
        throw new Error(`${label} must be between 0 and 1.`);
    }
}

function assertGap(value: number, memory: number, performance: number): void {
    if (!Number.isFinite(value)) {
        throw new Error("topic gap must be a finite number.");
    }
    if (value < -1 || value > 1) {
        throw new Error("topic gap must be between -1 and 1.");
    }
    if (Math.abs(value - (memory - performance)) > TOPIC_GAP_EPSILON) {
        throw new Error("topic gap must equal memory minus performance.");
    }
}
