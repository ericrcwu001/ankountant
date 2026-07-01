<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";

    import { buildReadinessView, buildTopicRows } from "./lib";

    export let readiness: GetReadinessResponse;
    export let examDate = "";

    $: rows = buildTopicRows(readiness.topics);
    $: view = buildReadinessView(readiness.readiness);
    $: examLabel = examDate
        ? `Exam-day projection (${examDate})`
        : "Exam-day projection";

    // Pretty-print the snake_case set ids for display without losing the raw id.
    function pretty(setId: string): string {
        return setId.replace(/_/g, " ");
    }
</script>

<div class="ankountant-dashboard" data-testid="dashboard">
    <header class="page-head">
        <p class="eyebrow">FAR section</p>
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
                </div>
            </div>
        {:else}
            <p class="band" data-testid="readiness-band">
                <span class="range tabular hero">{view.bandLabel}</span>
                <span class="confidence" data-testid="confidence">
                    {view.confidence} confidence
                </span>
            </p>
            <!-- Graded/faded Wilson band (navy, fading at the edges) — never a
                 crisp point (uncertainty honesty, C12). -->
            <div class="band-track" aria-hidden="true">
                <div class="band-fill"></div>
            </div>
            <p class="band-help">
                Projected exam-day score; the band is the confidence range.
            </p>
        {/if}
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
                            <td class="set-id">{pretty(row.setId)}</td>
                            <td class="memory num" data-testid="memory">
                                {#if row.memoryPct === null}
                                    <span class="insufficient">insufficient</span>
                                {:else}
                                    <span class="pct">{row.memoryPct}%</span>
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
            font-size: 22px;
            font-weight: 600;
            letter-spacing: -0.015em;
            line-height: 1.2;
            margin: 0;
        }
    }

    // Shared card surface (Ledger §3: borders-first, tinted-ink elevation).
    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow:
            0 1px 2px rgba(14, 15, 19, 0.06),
            0 1px 3px rgba(14, 15, 19, 0.05);
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
        font-size: 44px;
        font-weight: 600;
        letter-spacing: -0.02em;
        line-height: 1;
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

    .band .confidence {
        font-size: 14px;
        color: var(--fg-subtle);
    }

    .band-track {
        height: 8px;
        margin: var(--space-md) 0 var(--space-sm);
        border-radius: var(--border-radius);
        background: var(--canvas);
        overflow: hidden;
    }

    .band-fill {
        height: 100%;
        // Faded navy Wilson band — soft edges, never a crisp point.
        background: linear-gradient(
            90deg,
            transparent 0%,
            var(--accent) 28%,
            var(--accent) 72%,
            transparent 100%
        );
        opacity: 0.6;
    }

    .band-help {
        margin: 0;
        font-size: 13px;
        color: var(--fg-faint);
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
</style>
