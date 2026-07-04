<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Post-submit results layer (the differentiator): per-step reveal of the correct
value + your correctness, plus the item's authoritative basis (citation) and a
Blueprint-ish tag (section + confusion set). RENDERED ONLY AFTER SUBMIT — the
correct value comes from `buildRevealModel`, which the parent constructs only
once results are in, so nothing is revealed before the learner commits.
-->
<script lang="ts">
    import type { StepResult } from "@generated/anki/scheduler_pb";

    import { schemaTagLabel } from "../topic-labels";
    import { revealResultPresentation, type RevealModel } from "./lib";

    export let reveal: RevealModel;
    export let results: StepResult[];

    $: schemaLabel = schemaTagLabel(reveal.schemaTag);
</script>

<section class="results-layer" data-testid="results-layer">
    <h2>Answer key & rationale</h2>
    <ul class="reveal-list">
        {#each reveal.steps as step (step.id)}
            {@const result = revealResultPresentation(step.id, results)}
            <li class="reveal-row" data-testid="reveal-row" data-step-id={step.id}>
                <span
                    class="mark"
                    class:correct={result.status === "correct"}
                    class:incorrect={result.status === "incorrect"}
                    class:ungraded={result.status === "ungraded"}
                    role="img"
                    aria-label={result.ariaLabel}
                >
                    {result.mark}
                </span>
                <span class="label">{step.label}</span>
                <span class="correct-value" data-testid="reveal-correct">
                    {step.correctText}
                </span>
            </li>
        {/each}
    </ul>

    <div class="basis">
        <span class="blueprint" data-testid="reveal-blueprint">
            {reveal.section}{schemaLabel ? ` · ${schemaLabel}` : ""}
        </span>
        {#if reveal.source}
            <p class="source" data-testid="reveal-source">{reveal.source}</p>
        {/if}
    </div>
</section>

<style lang="scss">
    .results-layer {
        margin-top: var(--space-lg);
        padding: var(--space-lg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);

        h2 {
            margin: 0 0 var(--space-md);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }
    }

    .reveal-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
    }

    .reveal-row {
        display: grid;
        grid-template-columns: 1.5rem 1fr auto;
        align-items: baseline;
        gap: var(--space-sm);
    }

    .mark {
        font-weight: 700;
        text-align: center;

        &.correct {
            color: var(--fg-success);
        }

        &.incorrect {
            color: var(--fg-error);
        }

        &.ungraded {
            color: var(--fg-subtle);
        }
    }

    .label {
        color: var(--fg);
    }

    .correct-value {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums lining-nums;
        font-weight: 600;
        color: var(--accent);
        text-align: right;
    }

    .basis {
        margin-top: var(--space-md);
        padding-top: var(--space-md);
        border-top: 1px solid var(--border-subtle);
    }

    .blueprint {
        display: inline-block;
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.03em;
        color: var(--accent);
        background: var(--accent-tint);
        border-radius: var(--border-radius);
        padding: 1px var(--space-sm);
    }

    .source {
        margin: var(--space-sm) 0 0;
        font-size: 13px;
        line-height: 1.5;
        color: var(--fg-subtle);
        max-width: 66ch;
    }
</style>
