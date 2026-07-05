// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { GetReadinessResponse, TopicScore } from "@generated/anki/scheduler_pb";

import { hasTopicPerformanceEvidence, validateTopicScoreEvidence } from "../topic-evidence";
import { topicLabel } from "../topic-labels";
import { heightForTopicScore, type TopoTopic } from "./topo";

export interface FarTopic extends TopoTopic {
    setId: string;
    memory: number | null;
    performance: number | null;
    gap: number | null;
    memoryRange: string;
    performanceRange: string;
    unproven: boolean;
}

interface FarTopicSpec {
    key: string;
    setId: string;
    label: string;
}

export interface TopicStat {
    label: string;
    value: number;
    warn?: boolean;
}

const FAR_TOPIC_SPECS: FarTopicSpec[] = [
    {
        key: "leases",
        setId: "operating_vs_finance_lease",
        label: "Leases",
    },
    {
        key: "revenue",
        setId: "revrec_step_selection",
        label: "Revenue",
    },
    {
        key: "ppe",
        setId: "capitalize_vs_expense",
        label: "PP&E",
    },
    {
        key: "inventory",
        setId: "inventory_valuation",
        label: "Inventory",
    },
    {
        key: "investments",
        setId: "trading_afs_htm",
        label: "Investments",
    },
    {
        key: "taxes",
        setId: "tax_timing",
        label: "Taxes",
    },
    {
        key: "debt",
        setId: "debt_extinguishment",
        label: "Debt",
    },
    {
        key: "intangibles",
        setId: "intangibles_impairment",
        label: "Intangibles",
    },
    {
        key: "cash",
        setId: "cash_receivables",
        label: "Cash & Receivables",
    },
    {
        key: "statements",
        setId: "financial_statements",
        label: "Statements",
    },
    {
        key: "conceptual",
        setId: "conceptual_framework",
        label: "Conceptual",
    },
    {
        key: "pensions",
        setId: "pensions_equity",
        label: "Pensions & Equity",
    },
    {
        key: "govnfp",
        setId: "government_nfp",
        label: "Gov & NFP",
    },
];

const UNPROVEN_HEIGHT = 0;

export function buildFarTopics(
    readiness: GetReadinessResponse | undefined,
): FarTopic[] {
    return buildSectionTopics(readiness, "FAR");
}

export function buildSectionTopics(
    readiness: GetReadinessResponse | undefined,
    section: string,
): FarTopic[] {
    const specs = topicSpecs(section);
    const bySetId = new Map(
        (readiness?.topics ?? []).map((topic) => [topic.setId, topic]),
    );
    const used = new Set(specs.map((spec) => spec.setId));
    const known = specs.map((spec) => buildFarTopic(spec, bySetId));
    const unknown = (readiness?.topics ?? [])
        .filter((topic) => !used.has(topic.setId))
        .map((topic) => buildUnknownTopic(topic));
    return placeTopicsByPreparedness([...known, ...unknown]);
}

export function topStrongTopics(topics: FarTopic[]): TopicStat[] {
    return provenTopics(topics)
        .slice()
        .sort((a, b) => (b.performance ?? 0) - (a.performance ?? 0))
        .slice(0, 3)
        .map((topic) => ({ label: topic.label, value: topic.performance ?? 0 }));
}

export function needsAttention(topics: FarTopic[]): TopicStat[] {
    return provenTopics(topics)
        .slice()
        .sort((a, b) => (b.gap ?? 0) - (a.gap ?? 0))
        .slice(0, 3)
        .map((topic) => ({
            label: topic.label,
            value: topic.gap ?? 0,
            warn: (topic.gap ?? 0) >= 25,
        }));
}

function buildFarTopic(spec: FarTopicSpec, bySetId: Map<string, TopicScore>): FarTopic {
    return buildTopic({
        key: spec.key,
        setId: spec.setId,
        label: spec.label,
        topic: bySetId.get(spec.setId),
    });
}

function buildUnknownTopic(topic: TopicScore): FarTopic {
    return buildTopic({
        key: `topic-${topic.setId}`,
        setId: topic.setId,
        label: prettyTopic(topic.setId),
        topic,
    });
}

function buildTopic(input: {
    key: string;
    setId: string;
    label: string;
    topic: TopicScore | undefined;
}): FarTopic {
    const topic = input.topic;
    if (topic !== undefined) {
        validateTopicScoreEvidence(topic);
    }
    const hasMemory = topic !== undefined && !topic.memoryInsufficient;
    const hasPerformance = topic !== undefined && hasTopicPerformanceEvidence(topic);
    const performance = hasPerformance ? pct(topic.performance) : null;
    const memory = hasMemory ? pct(topic.memory) : null;
    let gap: number | null = null;
    if (topic !== undefined && memory !== null && performance !== null) {
        gap = pct(topic.gap);
    }
    const memoryRange = hasMemory ? rangeLabel(topic.memoryLow, topic.memoryHigh) : "";
    const performanceRange = hasPerformance
        ? rangeLabel(topic.performanceLow, topic.performanceHigh)
        : "";

    return {
        key: input.key,
        setId: input.setId,
        label: input.label,
        score: performance,
        memory,
        performance,
        gap,
        memoryRange,
        performanceRange,
        unproven: performance === null,
        cx: 0,
        height: UNPROVEN_HEIGHT,
        tier: "front",
    };
}

function placeTopicsByPreparedness(topics: FarTopic[]): FarTopic[] {
    return topics
        .map((topic, index) => ({ topic, index }))
        .sort((a, b) => {
            const byScore = preparednessScore(b.topic) - preparednessScore(a.topic);
            return byScore === 0 ? a.index - b.index : byScore;
        })
        .map(({ topic }, index, sorted) => ({
            ...topic,
            ...topicGeometry(index, sorted.length, topic.score),
        }));
}

function topicGeometry(
    index: number,
    total: number,
    score: number | null,
): Pick<FarTopic, "cx" | "height" | "tier"> {
    const rowCounts = topicRowCounts(total);
    const topRow = index < rowCounts.back;
    const tier = topRow ? "back" : "front";
    const rowIndex = topRow ? index : index - rowCounts.back;
    const rowCount = topRow ? rowCounts.back : rowCounts.front;
    return {
        cx: rowX(rowIndex, rowCount, tier, total),
        height: topicHeight(score, tier),
        tier,
    };
}

export function topicRowCounts(total: number): { back: number; front: number } {
    if (!Number.isInteger(total) || total < 0) {
        throw new Error(`Invalid topic count: ${total}`);
    }
    if (total === 0) {
        return { back: 0, front: 0 };
    }
    if (total === 1) {
        return { back: 1, front: 0 };
    }

    const back = Math.floor(total / 2);
    return { back, front: total - back };
}

function rowX(
    index: number,
    count: number,
    tier: "front" | "back",
    total: number,
): number {
    if (count < 1) {
        throw new Error(`Invalid row count: ${count}`);
    }
    if (count <= 1) {
        if (total === 1) {
            return 0.5;
        }
        return tier === "back" ? 0.38 : 0.62;
    }

    const min = rowPadding(count, tier);
    const max = 1 - min;
    return min + ((max - min) * index) / (count - 1);
}

function rowPadding(count: number, tier: "front" | "back"): number {
    const roomy = tier === "back" ? 0.22 : 0.16;
    const dense = tier === "back" ? 0.1 : 0.045;
    const denseCount = tier === "back" ? 6 : 8;
    const crowd = clamp((count - 2) / (denseCount - 2), 0, 1);
    return roomy + (dense - roomy) * crowd;
}

function clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
}

function topicHeight(score: number | null, tier: "front" | "back"): number {
    if (score === null) {
        return UNPROVEN_HEIGHT;
    }
    return heightForTopicScore(score, tier);
}

function preparednessScore(topic: FarTopic): number {
    return topic.score ?? -1;
}

function provenTopics(topics: FarTopic[]): FarTopic[] {
    return topics.filter((topic) => !topic.unproven);
}

function topicSpecs(section: string): FarTopicSpec[] {
    return section === "FAR" ? FAR_TOPIC_SPECS : [];
}

function pct(value: number): number {
    return Math.round(value * 100);
}

function rangeLabel(low: number, high: number): string {
    const lo = pct(low);
    const hi = pct(high);
    return hi > lo ? `${lo}–${hi}%` : "";
}

function prettyTopic(setId: string): string {
    return topicLabel(setId);
}
