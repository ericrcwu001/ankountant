<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";
    import { setExamDate } from "@generated/backend";

    import { goto } from "$app/navigation";
    import { bridgeCommand } from "@tslib/bridgecommand";

    import {
        buildReadinessEvidence,
        buildReadinessView,
        buildTopicRows,
        CPA_MAX_SCORE,
        GAP_WARNING_THRESHOLD,
    } from "../ankountant-dashboard/lib";
    import {
        buildFarTopics,
        needsAttention,
        topStrongTopics,
        type FarTopic,
    } from "./far-topics";
    import { buildCountdown, buildPhaseCta, choosePhase } from "./lib";
    import SummitTopographic from "./SummitTopographic.svelte";

    export let readiness: GetReadinessResponse | undefined = undefined;
    export let section = "FAR";
    export let examDate = "";
    export let sections: Record<string, GetReadinessResponse | undefined> = {};

    let date = examDate;
    let saveState: "idle" | "saving" | "saved" | "error" = "idle";
    let savedDate = examDate;
    let savingDate = "";
    let saveError = "";

    const R = 46;
    const C = 2 * Math.PI * R;
    const SWEEP = 0.75;
    const TOPO_W = 1000;
    const TOPO_H = 680;
    let hoveredTopicKey: string | null = null;
    let tipLeft = 0;
    let tipTop = 0;

    $: countdown = buildCountdown(date);
    $: sectionCount = Object.keys(sections).length;
    $: days = countdown.numeral.split("");
    $: view = buildReadinessView(readiness?.readiness);
    $: topicRows = buildTopicRows(readiness?.topics ?? []);
    $: evidence = buildReadinessEvidence(view, topicRows);
    $: farTopics = buildFarTopics(readiness);
    $: strongTopics = topStrongTopics(farTopics);
    $: attentionTopics = needsAttention(farTopics);
    $: provenCount = farTopics.filter((topic) => !topic.unproven).length;
    $: gapCount = farTopics.filter(
        (topic) => (topic.gap ?? 0) >= GAP_WARNING_THRESHOLD * 100,
    ).length;
    $: gaugeScore = view.abstain ? null : view.pointEstimate;
    $: gaugeFill = C * SWEEP * ((gaugeScore ?? 0) / CPA_MAX_SCORE);
    $: hoveredTopic = hoveredTopicKey
        ? farTopics.find((topic) => topic.key === hoveredTopicKey)
        : undefined;
    $: memoryReady = (readiness?.topics ?? []).some(
        (topic) => !topic.memoryInsufficient,
    );
    $: phase = choosePhase({ days: countdown.days, memoryReady });
    $: cta = buildPhaseCta(phase);

    async function onDateChange(): Promise<void> {
        const nextDate = date;
        if (nextDate === savedDate || nextDate === savingDate) {
            return;
        }
        saveState = "saving";
        savingDate = nextDate;
        saveError = "";
        try {
            await setExamDate({ section, date: nextDate });
            savedDate = nextDate;
            saveState = "saved";
        } catch (error) {
            saveState = "error";
            saveError = error instanceof Error ? error.message : String(error);
        } finally {
            if (savingDate === nextDate) {
                savingDate = "";
            }
        }
    }

    function nav(href: string): void {
        goto(href);
    }

    function runCta(): void {
        if (cta.target === "confusion") {
            nav("/ankountant-confusion");
        } else {
            bridgeCommand("ankountant:review");
        }
    }

    function clampTip(value: number, min: number, max: number): number {
        return Math.max(min, Math.min(max, value));
    }

    function showTopicTip(
        event: CustomEvent<{ key: string; x: number; y: number }>,
    ): void {
        hoveredTopicKey = event.detail.key;
        tipLeft = clampTip((event.detail.x / TOPO_W) * 100, 11, 91);
        tipTop = clampTip(((event.detail.y - 8) / TOPO_H) * 100, 20, 78);
    }

    function hideTopicTip(): void {
        hoveredTopicKey = null;
    }

    function topicValue(value: number | null): string {
        return value === null ? "—" : String(value);
    }

    function topicPercent(value: number | null): string {
        return value === null ? "insufficient" : `${value}%`;
    }

    function topicAria(topic: FarTopic): string {
        if (topic.unproven) {
            return `${topic.label}, not enough data yet`;
        }
        return `${topic.label}, memory ${topicPercent(topic.memory)}, performance ${topicPercent(topic.performance)}, gap ${topicPercent(topic.gap)}`;
    }
</script>

<div class="dash" data-testid="home">
    <aside class="rail">
        <div class="rail-card">
            <div class="rail-label">
                <svg
                    viewBox="0 0 24 24"
                    class="mini"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                    stroke-linecap="round"
                >
                    <rect x="3.5" y="4.5" width="17" height="16" rx="2.5" />
                    <path d="M3.5 9h17M8 3v3M16 3v3" />
                </svg>
                EXAM COUNTDOWN
            </div>
            <div class="countdown" data-testid="countdown">
                <span class="countdown-readable tabular" data-testid="countdown-days">
                    {countdown.numeral}
                </span>
                <div class="flip">
                    <span class="flip-value" aria-hidden="true">
                        {#each days as digit, index (`${index}-${digit}`)}
                            <span class="flip-card">
                                <span class="flip-digit tabular">{digit}</span>
                            </span>
                        {/each}
                    </span>
                </div>
                <div class="flip-unit">{countdown.caption}</div>
            </div>
            <label class="date-field" for="exam-date">
                <span>Exam date</span>
                <input
                    id="exam-date"
                    type="date"
                    bind:value={date}
                    on:input={onDateChange}
                    on:change={onDateChange}
                    disabled={saveState === "saving"}
                    data-testid="exam-date-input"
                />
            </label>
            <div
                class="save-state"
                data-state={saveState}
                data-testid="save-state"
                aria-live="polite"
            >
                {#if saveState === "saving"}Saving{:else if saveState === "saved"}Saved{:else if saveState === "error"}Save
                    failed{/if}
            </div>
            {#if saveError}
                <div class="save-error" role="alert">{saveError}</div>
            {/if}

            <hr class="rail-div" />

            <div class="rail-label">
                READINESS
                <svg
                    viewBox="0 0 24 24"
                    class="mini info"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                >
                    <circle cx="12" cy="12" r="9" />
                    <path d="M12 11v5" stroke-linecap="round" />
                    <circle cx="12" cy="7.8" r="0.4" fill="currentColor" />
                </svg>
            </div>
            <div class="gauge" data-testid="readiness">
                <svg
                    viewBox="0 0 120 108"
                    class="gauge-svg"
                    role="img"
                    aria-label={view.abstain
                        ? `Readiness withheld, ${view.reason}`
                        : `Readiness ${view.pointLabel} out of 99`}
                >
                    <g transform="rotate(135 60 58)">
                        <circle
                            cx="60"
                            cy="58"
                            r={R}
                            fill="none"
                            stroke="var(--border-subtle)"
                            stroke-width="9"
                            stroke-linecap="round"
                            stroke-dasharray="{C * SWEEP} {C}"
                        />
                        <circle
                            cx="60"
                            cy="58"
                            r={R}
                            fill="none"
                            stroke="var(--accent)"
                            stroke-width="9"
                            stroke-linecap="round"
                            stroke-dasharray="{gaugeFill} {C}"
                        />
                    </g>
                    <text class="gauge-num tabular" x="60" y="60" text-anchor="middle">
                        {view.abstain ? "—" : view.pointLabel}
                    </text>
                    <text class="gauge-den tabular" x="60" y="78" text-anchor="middle">
                        /99
                    </text>
                </svg>
                <div class="gauge-status">
                    {view.abstain
                        ? "Not enough data yet"
                        : `${view.confidence} confidence`}
                </div>
                <div class="gauge-note">
                    {#if view.abstain}
                        {view.reason} · {view.coveragePct}% covered
                    {:else}
                        {view.bandLabel} range · {view.coveragePct}% covered
                    {/if}
                </div>
                <div class="readiness-brief" data-testid="readiness-brief">
                    <div class="brief-row next">
                        <span>Next</span>
                        <p>{evidence.nextAction}</p>
                    </div>
                    <div class="brief-row">
                        <span>Missing</span>
                        <p>{evidence.missingData[0]}</p>
                    </div>
                    <button
                        type="button"
                        class="brief-link"
                        on:click={() => nav(`/ankountant-dashboard?section=${section}`)}
                    >
                        See readiness evidence
                    </button>
                </div>
            </div>

            <hr class="rail-div" />

            <div class="rail-label">TOP STRONG TOPICS</div>
            <ul class="stat-list">
                {#each strongTopics as topic (topic.label)}
                    <li>
                        <span class="stat-name">{topic.label}</span>
                        <span class="stat-val tabular">{topic.value}</span>
                    </li>
                {/each}
            </ul>

            <div class="rail-label attn">NEEDS ATTENTION</div>
            <ul class="stat-list">
                {#each attentionTopics as topic (topic.label)}
                    <li>
                        <span class="stat-name">{topic.label}</span>
                        <span class="stat-val tabular" class:warn={topic.warn}>
                            {topic.value}
                        </span>
                    </li>
                {/each}
            </ul>

            <button
                type="button"
                class="study-plan"
                data-testid="start-review"
                data-phase={cta.phase}
                on:click={runCta}
            >
                <span>
                    <strong>{cta.label}</strong>
                    <small>{cta.subtitle}</small>
                </span>
                <svg
                    viewBox="0 0 24 24"
                    class="mini"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                >
                    <path d="M9 6l6 6-6 6" />
                </svg>
            </button>
        </div>
    </aside>

    <section class="mastery">
        <header class="mastery-head">
            <div class="mastery-title">
                <p>{section} TOPIC MASTERY</p>
                <h1>Each peak is a topic. Climb higher. Master more.</h1>
            </div>
            <div class="controls">
                <button type="button" class="seg-solo active">All Topics</button>
                <div class="seg-group">
                    <button type="button">3M</button>
                    <button type="button">1M</button>
                    <button type="button">1W</button>
                </div>
                <button type="button" class="icon-btn" aria-label="Filter">
                    <svg
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.8"
                        stroke-linecap="round"
                    >
                        <path d="M4 6h11M4 12h7M4 18h13" />
                        <circle cx="18" cy="6" r="2.2" />
                        <circle cx="14" cy="12" r="2.2" />
                        <circle cx="20" cy="18" r="2.2" />
                    </svg>
                </button>
            </div>
        </header>

        <div class="map-wrap">
            {#if hoveredTopic}
                <div class="topo-tip" style={`left:${tipLeft}%; top:${tipTop}%`}>
                    <div class="tt-title">{hoveredTopic.label}</div>
                    <div class="tt-row">
                        <span>Memory</span>
                        <span class="tt-val tabular">
                            {topicPercent(hoveredTopic.memory)}
                        </span>
                    </div>
                    <div class="tt-row">
                        <span>Performance</span>
                        <span class="tt-val tabular">
                            {topicPercent(hoveredTopic.performance)}
                        </span>
                    </div>
                    <hr class="tt-div" />
                    <div class="tt-row">
                        <span>Gap</span>
                        <span class="tt-val tabular">
                            {topicPercent(hoveredTopic.gap)}
                        </span>
                    </div>
                    <span class="tt-tail"></span>
                </div>
            {/if}

            <SummitTopographic
                topics={farTopics}
                on:flagenter={showTopicTip}
                on:flagleave={hideTopicTip}
            />

            <div class="topic-strip" aria-label="FAR topics">
                {#each farTopics as topic (topic.key)}
                    <button
                        type="button"
                        class:unproven={topic.unproven}
                        aria-label={topicAria(topic)}
                        on:click={() => nav(`/ankountant-dashboard?section=${section}`)}
                    >
                        <span>{topic.label}</span>
                        <strong class="tabular">{topicValue(topic.performance)}</strong>
                    </button>
                {/each}
            </div>

            <div class="legend">
                <span class="leg-item">
                    <svg viewBox="0 0 16 16" class="leg-flag">
                        <path d="M4 2v12" stroke="#1f3a5f" stroke-width="1.6" />
                        <path d="M4 2.5l7 2.5-7 2.5z" fill="#1f3a5f" />
                    </svg>
                    At or Above Pass Line (>= 75)
                </span>
                <span class="leg-item">
                    <svg viewBox="0 0 16 16" class="leg-flag">
                        <path d="M4 2v12" stroke="#e08a2e" stroke-width="1.6" />
                        <path d="M4 2.5l7 2.5-7 2.5z" fill="#e08a2e" />
                    </svg>
                    Below Pass Line (&lt; 75)
                </span>
                <span class="leg-item">
                    <span class="leg-dot"></span>
                    Your Current Mastery
                </span>
            </div>
        </div>

        <footer class="mastery-foot">
            <span class="foot-left">
                <svg
                    viewBox="0 0 24 24"
                    class="mini"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.7"
                >
                    <circle cx="12" cy="12" r="9" />
                    <path
                        d="M15 9l-2.5 5.5L7 17l2.5-5.5z"
                        fill="currentColor"
                        stroke="none"
                    />
                </svg>
                {provenCount} proven topics · {gapCount} gap{gapCount === 1 ? "" : "s"} to
                close · {sectionCount} sections loaded
            </span>
            <span class="foot-right">
                Mastery is a blend of memory and performance.
                <svg
                    viewBox="0 0 24 24"
                    class="mini"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                >
                    <circle cx="12" cy="12" r="9" />
                    <path d="M12 11v5" stroke-linecap="round" />
                    <circle cx="12" cy="7.8" r="0.4" fill="currentColor" />
                </svg>
            </span>
        </footer>
    </section>
</div>

<style lang="scss">
    .dash {
        --accent: #0e3a66;
        --fg: #0f2744;
        --fg-subtle: #51657e;
        --fg-faint: #7e8da1;
        --canvas: #f2f6fb;
        --canvas-elevated: rgba(255, 255, 255, 0.9);
        --canvas-inset: rgba(248, 250, 253, 0.96);
        --canvas-overlay: rgba(255, 255, 255, 0.94);
        --border: #c8d5e5;
        --border-subtle: #d8e2ef;
        --border-strong: #9fb1c8;

        display: grid;
        grid-template-columns: minmax(250px, 300px) minmax(0, 1fr);
        gap: var(--space-xl);
        box-sizing: border-box;
        height: 100vh;
        min-height: 100vh;
        overflow: hidden;
        padding: var(--space-xl);
        background: radial-gradient(
            120% 80% at 70% 0%,
            #eef4fb 0%,
            #eef0f4 55%,
            #eef0f4 100%
        );
        color: var(--fg);
    }

    .rail-card,
    .mastery {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        box-shadow: var(--elevation-e1);
    }

    .rail-card {
        padding: var(--space-xl);
    }

    .rail-label {
        display: flex;
        align-items: center;
        gap: 7px;
        font-size: 11.5px;
        font-weight: 700;
        letter-spacing: 0.09em;
        text-transform: uppercase;
        color: var(--fg-subtle);
        margin-bottom: var(--space-md);

        &.attn {
            margin-top: var(--space-lg);
        }
    }

    .mini {
        width: 15px;
        height: 15px;
        flex: none;
    }

    .info {
        width: 13px;
        height: 13px;
        color: var(--fg-faint);
    }

    .flip {
        display: flex;
        gap: 7px;
    }

    .countdown-readable {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
        white-space: nowrap;
    }

    .flip-value {
        display: flex;
        gap: 7px;
    }

    .flip-card {
        position: relative;
        display: grid;
        place-items: center;
        min-width: 62px;
        height: 90px;
        padding: 0 10px;
        border-radius: 12px;
        background: linear-gradient(180deg, #fdfdfe 0%, #eef1f6 100%);
        border: 1px solid var(--border-subtle);
        box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.6);

        &::after {
            content: "";
            position: absolute;
            left: 6px;
            right: 6px;
            top: 50%;
            height: 1px;
            background: var(--border-subtle);
        }
    }

    .flip-digit {
        font-size: 64px;
        font-weight: 600;
        line-height: 1;
        letter-spacing: 0;
        color: var(--accent);
    }

    .flip-unit {
        margin-top: var(--space-sm);
        font-size: 12px;
        font-weight: 600;
        color: var(--fg-subtle);
    }

    .date-field {
        display: grid;
        gap: var(--space-xs);
        margin-top: var(--space-md);
        font-size: 12px;
        font-weight: 600;
        color: var(--fg-subtle);

        input {
            width: 100%;
            min-height: 38px;
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border);
            border-radius: var(--border-radius);
            padding: 0 var(--space-sm);
            font: inherit;

            &:disabled {
                color: var(--fg-faint);
                cursor: progress;
            }
        }
    }

    .save-state {
        min-height: 17px;
        margin-top: var(--space-xs);
        font-size: 12px;
        font-weight: 600;
        color: var(--fg-faint);

        &[data-state="error"] {
            color: var(--fg-error);
        }
    }

    .save-error {
        margin-top: var(--space-xxs);
        font-size: 11px;
        line-height: 1.35;
        color: var(--fg-error);
        overflow-wrap: anywhere;
    }

    .rail-div {
        border: 0;
        border-top: 1px solid var(--border-subtle);
        margin: var(--space-lg) 0;
    }

    .gauge {
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
    }

    .gauge-svg {
        width: 150px;
        height: 135px;
    }

    .gauge-num {
        font-size: 36px;
        font-weight: 600;
        letter-spacing: 0;
        fill: var(--accent);
    }

    .gauge-den {
        font-size: 13px;
        font-weight: 600;
        fill: var(--fg-subtle);
    }

    .gauge-status {
        margin-top: 2px;
        font-size: 15px;
        font-weight: 600;
        color: var(--accent);
    }

    .gauge-note {
        font-size: 13px;
        color: var(--fg-subtle);
    }

    .readiness-brief {
        display: grid;
        gap: var(--space-sm);
        width: 100%;
        margin-top: var(--space-md);
        padding-top: var(--space-md);
        border-top: 1px solid var(--border-subtle);
        text-align: left;
    }

    .brief-row {
        display: grid;
        gap: 2px;

        span {
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: var(--fg-faint);
        }

        p {
            margin: 0;
            font-size: 12.5px;
            line-height: 1.4;
            color: var(--fg-subtle);
        }

        &.next p {
            font-weight: 600;
            color: var(--fg);
        }
    }

    .brief-link {
        justify-self: start;
        padding: 0;
        font-size: 12.5px;
        font-weight: 700;
        color: var(--accent);
        background: transparent;
        border: 0;
        cursor: pointer;

        &:hover {
            text-decoration: underline;
        }

        &:focus-visible {
            outline: 2px solid #7ea6d6;
            outline-offset: 3px;
        }
    }

    .stat-list {
        list-style: none;
        margin: 0;
        padding: 0;

        li {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--space-md);
            padding: 5px 0;
            font-size: 14.5px;
        }
    }

    .stat-name {
        min-width: 0;
        color: var(--fg);
    }

    .stat-val {
        font-weight: 700;
        color: var(--accent);

        &.warn {
            color: #8a5a12;
        }
    }

    .study-plan {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-sm);
        width: 100%;
        margin-top: var(--space-lg);
        padding: 11px;
        font-size: 14px;
        color: var(--fg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border);
        border-radius: 10px;
        text-align: left;

        span {
            display: grid;
            gap: 2px;
        }

        strong,
        small {
            line-height: 1.2;
        }

        small {
            color: var(--fg-subtle);
        }

        &:hover {
            background: var(--canvas);
        }
    }

    .mastery {
        display: flex;
        flex-direction: column;
        min-width: 0;
        padding: var(--space-xl) var(--space-xl) var(--space-lg);
        overflow: hidden;
        background: transparent;
        border-color: transparent;
        box-shadow: none;
    }

    .mastery-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: var(--space-lg);
        position: relative;
        z-index: 2;
    }

    .mastery-title {
        p {
            margin: 0;
            font-size: 15px;
            font-weight: 800;
            letter-spacing: 0;
            color: var(--fg);
        }

        h1 {
            margin: 4px 0 0;
            font-size: 14px;
            font-weight: 500;
            letter-spacing: 0;
            color: var(--fg-subtle);
        }
    }

    .controls {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        flex: none;
    }

    .seg-solo,
    .seg-group button,
    .icon-btn {
        min-height: 36px;
        border-radius: 9px;
    }

    .seg-solo {
        padding: 8px 14px;
        font-size: 13px;
        font-weight: 600;
        color: #fff;
        background: var(--accent);
        border: 1px solid var(--accent);
    }

    .seg-group {
        display: flex;
        border: 1px solid var(--border);
        border-radius: 9px;
        overflow: hidden;

        button {
            padding: 8px 14px;
            font-size: 13px;
            font-weight: 500;
            color: var(--fg-subtle);
            background: var(--canvas-elevated);
            border: 0;
            border-right: 1px solid var(--border-subtle);

            &:last-child {
                border-right: 0;
            }

            &:hover {
                background: var(--canvas);
            }
        }
    }

    .icon-btn {
        display: grid;
        place-items: center;
        width: 36px;
        color: var(--fg-subtle);
        background: var(--canvas-elevated);
        border: 1px solid var(--border);

        svg {
            width: 18px;
            height: 18px;
        }

        &:hover {
            background: var(--canvas);
        }
    }

    .map-wrap {
        position: relative;
        flex: 1;
        min-height: 620px;
        margin-top: var(--space-md);
    }

    .topo-tip {
        position: absolute;
        z-index: 5;
        width: 190px;
        padding: var(--space-md) var(--space-lg);
        background: var(--canvas-overlay);
        border: 1px solid var(--border-subtle);
        border-radius: 14px;
        box-shadow: var(--elevation-e2);
        pointer-events: none;
        transform: translate(-50%, -108%);
    }

    .tt-title {
        font-size: 17px;
        font-weight: 700;
        color: var(--fg);
        margin-bottom: var(--space-sm);
    }

    .tt-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-sm);
        padding: 3px 0;
        font-size: 13.5px;
        color: var(--fg-subtle);
    }

    .tt-val {
        font-weight: 700;
        color: var(--accent);
    }

    .tt-div {
        border: 0;
        border-top: 1px dashed var(--border);
        margin: var(--space-sm) 0;
    }

    .tt-tail {
        position: absolute;
        left: 50%;
        bottom: -8px;
        width: 16px;
        height: 16px;
        background: var(--canvas-overlay);
        border-right: 1px solid var(--border-subtle);
        border-bottom: 1px solid var(--border-subtle);
        transform: translateX(-50%) rotate(45deg);
    }

    .topic-strip {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 58px;
        z-index: 4;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
        gap: 6px;
        pointer-events: none;
        opacity: 0;
    }

    .topic-strip button {
        min-height: 1px;
        pointer-events: auto;
    }

    .legend {
        position: absolute;
        left: 50%;
        bottom: 22px;
        z-index: 6;
        transform: translateX(-50%);
        display: flex;
        align-items: center;
        gap: var(--space-lg);
        padding: 10px var(--space-lg);
        background: var(--canvas-overlay);
        border: 1px solid var(--border-subtle);
        border-radius: 999px;
        box-shadow: var(--elevation-e2);
        white-space: nowrap;
    }

    .leg-item {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        font-size: 12.5px;
        color: var(--fg-subtle);
    }

    .leg-flag {
        width: 15px;
        height: 15px;
    }

    .leg-dot {
        width: 9px;
        height: 9px;
        border-radius: 999px;
        border: 2px solid var(--fg-faint);
        background: var(--canvas-elevated);
    }

    .mastery-foot {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-lg);
        margin-top: var(--space-md);
        padding-top: var(--space-md);
        font-size: 12.5px;
        color: var(--fg-faint);
    }

    .foot-left,
    .foot-right {
        display: inline-flex;
        align-items: center;
        gap: 7px;
    }

    @media (max-width: 1100px) {
        .dash {
            grid-template-columns: 1fr;
            height: auto;
            overflow: visible;
        }

        .rail-card {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: var(--space-lg);
        }

        .rail-div,
        .study-plan {
            grid-column: 1 / -1;
        }
    }

    @media (max-width: 760px) {
        .dash {
            padding: var(--space-md);
        }

        .rail-card {
            display: block;
        }

        .mastery-head,
        .mastery-foot {
            flex-direction: column;
            align-items: stretch;
        }

        .controls,
        .legend {
            display: none;
        }

        .map-wrap {
            min-height: 500px;
        }
    }
</style>
