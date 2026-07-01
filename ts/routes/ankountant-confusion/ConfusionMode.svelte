<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

B3 (F013) — confusion-set review mode. Plays the interleaved, label-stripped
queue (A3), running the B1 confidence gate + the B2 which-treatment gate per
item, and submitting each choice via SubmitPerformanceAttempt(mode=confusion).
-->
<script lang="ts">
    import type { ConfusionItem } from "@generated/anki/scheduler_pb";
    import { submitPerformanceAttempt } from "@generated/backend";

    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";
    import ConfidenceGate from "$lib/components/ConfidenceGate.svelte";

    import { buildChoiceSubmission } from "./lib";

    export let items: ConfusionItem[];

    let index = 0;
    let confidence: ConfidenceLevel | null = null;
    let itemStartedAt = Date.now();
    let lastCorrect: boolean | null = null;
    let submitting = false;

    $: current = items[index];
    $: done = index >= items.length;

    function onCommit(level: ConfidenceLevel): void {
        confidence = level;
    }

    async function choose(treatment: string): Promise<void> {
        // B2: discrimination is gated behind the committed confidence.
        if (confidence === null || submitting || current == null) {
            return;
        }
        submitting = true;
        try {
            const resp = await submitPerformanceAttempt({
                itemNoteId: current.noteId,
                mode: "confusion",
                submissionJson: buildChoiceSubmission(treatment),
                confidence,
                latencyMs: Date.now() - itemStartedAt,
            });
            lastCorrect = resp.totalCredit >= 1;
        } finally {
            submitting = false;
        }
    }

    function next(): void {
        index += 1;
        confidence = null;
        lastCorrect = null;
        itemStartedAt = Date.now();
    }
</script>

<div class="confusion-mode" data-testid="confusion-mode">
    {#if done}
        <p class="finished" data-testid="confusion-finished">
            Queue complete — {items.length} items reviewed.
        </p>
        <a href="/ankountant-dashboard" data-testid="to-dashboard">View readiness</a>
    {:else}
        <div class="item" data-testid="confusion-item" data-set-id={current.setId}>
            <!-- Label-stripped prompt: NO topic/category/deck label element
                 (B2-D1 / A44). Do NOT render data-testid="category-label". -->
            <p class="prompt" data-testid="confusion-prompt">{current.prompt}</p>

            <ConfidenceGate committed={confidence} {onCommit} />

            {#if confidence !== null}
                <div class="treatments" data-testid="treatments">
                    {#each current.treatments as treatment (treatment)}
                        <button
                            type="button"
                            class="treatment"
                            data-testid="treatment"
                            data-value={treatment}
                            disabled={submitting || lastCorrect !== null}
                            on:click={() => choose(treatment)}
                        >
                            {treatment}
                        </button>
                    {/each}
                </div>
            {/if}

            {#if lastCorrect !== null}
                <p
                    class="verdict"
                    data-testid="verdict"
                    class:correct={lastCorrect}
                    class:incorrect={!lastCorrect}
                >
                    {lastCorrect ? "Correct" : "Incorrect"}
                </p>
                <button type="button" data-testid="next-item" on:click={next}>
                    Next
                </button>
            {/if}
        </div>
    {/if}
</div>

<style lang="scss">
    .confusion-mode {
        max-width: 34em;
        margin: 1rem auto;
        font-size: var(--font-size);

        .treatments {
            display: flex;
            flex-direction: column;
            gap: 0.4rem;
            margin: 0.75rem 0;
        }

        .verdict.correct {
            color: var(--fg-success, #093);
        }

        .verdict.incorrect {
            color: var(--fg-error, #c00);
        }
    }
</style>
