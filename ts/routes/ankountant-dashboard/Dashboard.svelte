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
</script>

<div class="ankountant-dashboard" data-testid="dashboard">
    <h1>Readiness — FAR</h1>

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
                    <td class="set-id">{row.setId}</td>
                    <td class="memory" data-testid="memory">
                        {#if row.memoryPct === null}
                            <span class="insufficient">insufficient</span>
                        {:else}
                            {row.memoryPct}%
                        {/if}
                    </td>
                    <td class="performance" data-testid="performance">
                        {row.performancePct}%
                    </td>
                    <td class="gap" data-testid="gap">{row.gapPct}%</td>
                </tr>
            {/each}
        </tbody>
    </table>

    <section class="readiness" data-testid="readiness">
        <h2>{examLabel}</h2>
        {#if view.abstain}
            <p class="abstain" data-testid="abstain">
                Not enough data yet — {view.reason}.
            </p>
        {:else}
            <p class="band" data-testid="readiness-band">
                <span class="range">{view.bandLabel}</span>
                <span class="confidence" data-testid="confidence">
                    ({view.confidence} confidence)
                </span>
            </p>
        {/if}
    </section>
</div>

<style lang="scss">
    .ankountant-dashboard {
        max-width: 40em;
        margin: 1rem auto;
        font-size: var(--font-size);
    }

    table.scores {
        width: 100%;
        border-collapse: collapse;

        th,
        td {
            border: 1px solid var(--border);
            padding: 0.4rem 0.6rem;
            text-align: left;
        }
    }

    .topic-row.gap-warning {
        background: var(--flag-1, #ffdddd);

        .gap {
            font-weight: bold;
            color: var(--fg-error, #c00);
        }
    }

    .insufficient {
        font-style: italic;
        opacity: 0.7;
    }

    .readiness {
        margin-top: 1.5rem;

        .abstain {
            font-style: italic;
        }

        .band .range {
            font-size: 1.4em;
            font-weight: bold;
        }
    }
</style>
