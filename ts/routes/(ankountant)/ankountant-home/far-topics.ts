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

const TOP_ROW_COUNT = 5;
const UNPROVEN_HEIGHT = 0;
const BACK_ROW_X = [0.12, 0.32, 0.52, 0.72, 0.9];
const FRONT_ROW_X = [0.045, 0.175, 0.305, 0.435, 0.565, 0.695, 0.825, 0.955];

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
    const topRow = index < TOP_ROW_COUNT;
    const tier = topRow ? "back" : "front";
    const rowIndex = topRow ? index : index - TOP_ROW_COUNT;
    const rowCount = topRow ? Math.min(TOP_ROW_COUNT, total) : total - TOP_ROW_COUNT;
    return {
        cx: rowX(rowIndex, rowCount, tier),
        height: topicHeight(score, tier),
        tier,
    };
}

function rowX(index: number, count: number, tier: "front" | "back"): number {
    if (tier === "back" && count === BACK_ROW_X.length) {
        return BACK_ROW_X[index];
    }
    if (tier === "front" && count === FRONT_ROW_X.length) {
        return FRONT_ROW_X[index];
    }
    if (count <= 1) {
        return 0.5;
    }
    const min = tier === "back" ? 0.1 : 0.045;
    const max = tier === "back" ? 0.9 : 0.955;
    return min + ((max - min) * index) / (count - 1);
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
