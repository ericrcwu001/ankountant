<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";

    import { sectionName } from "../ankountant-home/summit";
    import {
        buildReadinessEvidence,
        buildReadinessView,
        buildTopicRows,
        formatUpdated,
        prettySetId,
    } from "./lib";

    export let readiness: GetReadinessResponse;
    export let examDate = "";
    export let section = "FAR";

    $: rows = buildTopicRows(readiness.topics);
    $: view = buildReadinessView(readiness.readiness);
    $: evidence = buildReadinessEvidence(view, rows);
    $: updated = formatUpdated(view.generatedAt);
    $: examLabel = examDate
        ? `Exam-day projection (${examDate})`
        : "Exam-day projection";
</script>

<div class="ankountant-dashboard" data-testid="dashboard">
    <header class="page-head">
        <p class="eyebrow">{sectionName(section)}</p>
        <h1>Readiness</h1>
    </header>

    <!-- Readiness honesty moment: the exam-day projection (or an explicit
         abstain when the evidence is too thin). The score is the display hero. -->
    <section class="card readiness" data-testid="readiness">
        <h2 class="card-label">{examLabel}</h2>
        {#if view.abstain}
            <div class="abstain" data-testid="abstain">
                <span class="abstain-icon" role="img" aria-label="Insufficient data">
                    &#9636;
                </span>
                <div class="abstain-text">
                    <p class="abstain-title">Not enough data yet</p>
                    <p class="abstain-reason">{view.reason}.</p>
                    <!-- Coverage is shown even while abstaining (one of the seven
                         required fields), so the give-up state is legible. -->
                    <p class="coverage" data-testid="coverage">
                        {view.coveragePct}% of exam topics covered
                    </p>
                </div>
            </div>
        {:else}
            <p class="band" data-testid="readiness-band">
                <span class="range tabular hero">{view.bandLabel}</span>
                <span class="point tabular" data-testid="point-estimate">
                    point {view.pointLabel}
                </span>
                <span class="confidence" data-testid="confidence">
                    {view.confidence} confidence
                </span>
            </p>
            <!-- Graded/faded Wilson band on the CPA 0–99 scale, with a pass tick
                 at 75 — never a crisp point (uncertainty honesty, C12). -->
            <div
                class="band-track"
                role="img"
                aria-label="Projected CPA band {view.bandLabel}, pass line 75"
            >
                <div
                    class="band-fill"
                    style="left:{view.trackLeftPct}%; width:{view.trackWidthPct}%"
                ></div>
                <div class="pass-tick" style="left:{view.trackPassPct}%"></div>
            </div>
            <div class="meta" data-testid="readiness-meta">
                <span data-testid="coverage">{view.coveragePct}% of exam covered</span>
                {#if updated}<span data-testid="updated">{updated}</span>{/if}
            </div>
            {#if view.reasons.length}
                <ul class="reasons" data-testid="reasons">
                    {#each view.reasons as reason}
                        <li>{reason}</li>
                    {/each}
                </ul>
            {/if}
            <p class="band-help">
                Rough projection on the CPA 0–99 scale (pass 75); the band is the
                confidence range, not an official AICPA score.
            </p>
        {/if}
        <div class="evidence-panel" data-testid="readiness-evidence">
            <div class="evidence-block">
                <h3>Evidence behind this range</h3>
                <ul>
                    {#each evidence.evidenceLines as line}
                        <li>{line}</li>
                    {/each}
                </ul>
            </div>
            <div class="evidence-block">
                <h3>Last updated</h3>
                <p>{evidence.updatedAtLine}</p>
            </div>
            <div class="evidence-block">
                <h3>Still missing</h3>
                <ul>
                    {#each evidence.missingData as line}
                        <li>{line}</li>
                    {/each}
                </ul>
            </div>
            <div class="evidence-block action">
                <h3>Next best study action</h3>
                <p>{evidence.nextAction}</p>
            </div>
            <div class="evidence-block">
                <h3>Past prediction accuracy</h3>
                <p>{evidence.calibrationStatus}</p>
                <p class="give-up-rule">{evidence.giveUpRule}</p>
            </div>
        </div>
    </section>

    <!-- Per-topic Memory vs Performance on a shared 0–100 scale. -->
    <section class="topics">
        <h2 class="section-label">Topic breakdown</h2>
        <div class="card table-card">
            <table class="scores" data-testid="score-table">
                <thead>
                    <tr>
                        <th>Topic</th>
                        <th>Memory</th>
                        <th>Performance</th>
                        <th>Gap</th>
                    </tr>
                </thead>
                <tbody>
                    {#each rows as row (row.setId)}
                        <tr
                            class="topic-row"
                            class:gap-warning={row.gapWarning}
                            data-testid="topic-row"
                            data-set-id={row.setId}
                        >
                            <td class="set-id">{prettySetId(row.setId)}</td>
                            <td class="memory num" data-testid="memory">
                                {#if row.memoryPct === null}
                                    <span class="insufficient">insufficient</span>
                                {:else}
                                    <span class="pct">{row.memoryPct}%</span>
                                    {#if row.memoryRange}
                                        <span
                                            class="range-sub"
                                            data-testid="memory-range"
                                        >
                                            {row.memoryRange}
                                        </span>
                                    {/if}
                                    <span class="meter" aria-hidden="true">
                                        <span
                                            class="meter-fill"
                                            style="width:{row.memoryPct}%"
                                        ></span>
                                    </span>
                                {/if}
                            </td>
                            <td class="performance num" data-testid="performance">
                                <span class="pct">{row.performancePct}%</span>
                                {#if row.performanceRange}
                                    <span
                                        class="range-sub"
                                        data-testid="performance-range"
                                    >
                                        {row.performanceRange}
                                    </span>
                                {/if}
                                <span class="meter" aria-hidden="true">
                                    <span
                                        class="meter-fill"
                                        style="width:{row.performancePct}%"
                                    ></span>
                                </span>
                            </td>
                            <td class="gap num" data-testid="gap">
                                {#if row.gapWarning}
                                    <span
                                        class="gap-flag"
                                        role="img"
                                        aria-label="Large gap"
                                    >
                                        &#9650;
                                    </span>
                                {/if}{row.gapPct}%
                            </td>
                        </tr>
                    {/each}
                </tbody>
            </table>
        </div>
    </section>
</div>

<style lang="scss">
    .ankountant-dashboard {
        max-width: 48rem;
        margin: 0 auto;
        padding: var(--space-xl) var(--space-lg) var(--space-xxl);
        font-size: var(--font-size);
        color: var(--fg);
    }

    .page-head {
        margin-bottom: var(--space-lg);

        .eyebrow {
            margin: 0 0 var(--space-xxs);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }

        h1 {
            // Section heading — the score below is the display hero, not this.
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            letter-spacing: var(--type-section-heading-tracking);
            line-height: var(--type-section-heading-line);
            margin: 0;
        }
    }

    // Shared card surface (Ledger §3: borders-first, tinted-ink elevation).
    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        // Theme-aware Ledger elevation (dark mode gets a real shadow, not the
        // near-invisible light-ink one).
        box-shadow: var(--elevation-e1);
    }

    .card-label {
        margin: 0;
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .section-label {
        margin: 0 0 var(--space-sm);
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .readiness {
        padding: var(--space-xl);
        margin-bottom: var(--space-xl);
    }

    // Display hero (the score / projection) — the largest thing on the page.
    .hero {
        font-size: var(--type-display-hero-size);
        font-weight: var(--type-display-hero-weight);
        letter-spacing: var(--type-display-hero-tracking);
        line-height: var(--type-display-hero-line);
    }

    .band {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: var(--space-sm) var(--space-md);
        margin: var(--space-sm) 0 0;
    }

    .band .range {
        color: var(--accent);
    }

    .band .point {
        font-size: 14px;
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums lining-nums;
    }

    .band .confidence {
        font-size: 14px;
        color: var(--fg-subtle);
    }

    // Wilson band positioned on the 0–99 CPA scale, with a pass tick at 75.
    .band-track {
        position: relative;
        height: 10px;
        margin: var(--space-md) 0 var(--space-sm);
        border-radius: var(--border-radius);
        background: var(--canvas);
    }

    .band-fill {
        position: absolute;
        top: 0;
        height: 100%;
        min-width: 2px;
        border-radius: var(--border-radius);
        // Faded navy Wilson band — soft edges, never a crisp point.
        background: linear-gradient(
            90deg,
            transparent 0%,
            var(--accent) 30%,
            var(--accent) 70%,
            transparent 100%
        );
        opacity: 0.75;
    }

    // The pass line (scaled 75) as a reference tick across the track.
    .pass-tick {
        position: absolute;
        top: -3px;
        width: 2px;
        height: 16px;
        margin-left: -1px;
        background: var(--fg-subtle);
        opacity: 0.7;
    }

    .meta {
        display: flex;
        flex-wrap: wrap;
        gap: var(--space-sm) var(--space-lg);
        font-size: 13px;
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums lining-nums;
    }

    // Factual drivers (restated numbers, not claimed causes).
    .reasons {
        margin: var(--space-sm) 0 0;
        padding-left: 1.1em;
        font-size: 13px;
        color: var(--fg-subtle);

        li {
            margin: 2px 0;
        }
    }

    .coverage {
        margin: var(--space-xs) 0 0;
        font-size: 13px;
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums lining-nums;
    }

    .band-help {
        margin: var(--space-sm) 0 0;
        font-size: 13px;
        color: var(--fg-faint);
    }

    .evidence-panel {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--space-lg);
        margin-top: var(--space-lg);
        padding-top: var(--space-lg);
        border-top: 1px solid var(--border-subtle);
    }

    .evidence-block {
        min-width: 0;

        h3 {
            margin: 0 0 var(--space-xs);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }

        ul {
            margin: 0;
            padding-left: 1.1em;
        }

        li,
        p {
            margin: 2px 0;
            font-size: 13px;
            line-height: 1.45;
            color: var(--fg-subtle);
        }
    }

    .evidence-block.action p {
        color: var(--fg);
        font-weight: 600;
    }

    .give-up-rule {
        padding-top: var(--space-xs);
        color: var(--fg-faint) !important;
    }

    // First-class abstain: neutral + hatch + icon + label, visually unlike a
    // low score (Ledger §5, C12). Hatch uses --border so it stays visible in
    // dark mode (C3).
    .abstain {
        display: flex;
        align-items: flex-start;
        gap: var(--space-md);
        margin-top: var(--space-md);
        padding: var(--space-md);
        border: 1px dashed var(--border-strong);
        border-radius: var(--border-radius);
        background: repeating-linear-gradient(
            45deg,
            transparent,
            transparent 7px,
            var(--border) 7px,
            var(--border) 8px
        );
    }

    .abstain-icon {
        font-size: 20px;
        line-height: 1.2;
        color: var(--fg-subtle);
    }

    .abstain-text {
        display: flex;
        flex-direction: column;
        gap: 2px;
    }

    .abstain-title {
        margin: 0;
        font-weight: 600;
        color: var(--fg);
    }

    .abstain-reason {
        margin: 0;
        color: var(--fg-subtle);
    }

    // Topic table: hairline row dividers only (no full grid), tabular numerics.
    .table-card {
        overflow: hidden;
    }

    table.scores {
        width: 100%;
        border-collapse: collapse;

        th,
        td {
            padding: var(--space-md) var(--space-lg);
            text-align: left;
            vertical-align: top;
        }

        thead th {
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
            border-bottom: 1px solid var(--border);
        }

        tbody tr + tr td {
            border-top: 1px solid var(--border-subtle);
        }

        // Numeric columns: neutral ink + tabular figures, right-aligned so the
        // digits line up like a ledger (Ledger §2, C10).
        .num,
        th:not(:first-child) {
            text-align: right;
            font-variant-numeric: tabular-nums lining-nums;
        }

        .set-id {
            font-weight: 500;
            text-transform: capitalize;
            padding-top: calc(var(--space-md) + 1px);
        }
    }

    // Position-on-a-common-scale meter for Memory / Performance (§5: position
    // beats gauges). Neutral fill — scores are not painted semantic hues.
    .meter {
        display: block;
        height: 4px;
        margin-top: 6px;
        border-radius: var(--border-radius);
        background: var(--canvas);
        overflow: hidden;
    }

    .meter-fill {
        display: block;
        height: 100%;
        min-width: 0;
        background: var(--fg-faint);
    }

    // The Wilson confidence range under a topic's point score.
    .range-sub {
        display: block;
        margin-top: 2px;
        font-size: 11px;
        color: var(--fg-faint);
        font-variant-numeric: tabular-nums lining-nums;
    }

    .topic-row.gap-warning {
        // Danger-tint row + defined --fg-error text (fixes the undefined
        // --fg-error → #c00 fallback and the saturated flag-1 red row).
        background: var(--gap-warning-bg);

        .gap {
            font-weight: 600;
            color: var(--fg-error);
        }
    }

    .gap-flag {
        margin-inline-end: var(--space-xxs);
    }

    .insufficient {
        color: var(--fg-faint);
    }

    @media (max-width: 720px) {
        .evidence-panel {
            grid-template-columns: 1fr;
            gap: var(--space-md);
        }
    }
</style>
