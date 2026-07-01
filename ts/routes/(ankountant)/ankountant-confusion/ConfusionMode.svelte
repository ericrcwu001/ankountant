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

    // Confusion review is label-stripped (B2-D1): drop any trailing dev slug
    // like " (capitalize_vs_expense q0)" so the stem never leaks the category.
    function stem(prompt: string): string {
        return prompt.replace(/\s*\([a-z0-9_]+\s+q\d+\)\s*$/i, "");
    }

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
        <div class="card finished-card">
            <span class="finished-icon" aria-hidden="true">&#10003;</span>
            <p class="finished" data-testid="confusion-finished">
                Queue complete — {items.length} items reviewed.
            </p>
            <a
                class="primary-link"
                href="/ankountant-dashboard"
                data-testid="to-dashboard"
            >
                View readiness
            </a>
        </div>
    {:else}
        <div class="card item" data-testid="confusion-item" data-set-id={current.setId}>
            <!-- Label-stripped prompt: NO topic/category/deck label element
                 (B2-D1 / A44). Do NOT render data-testid="category-label". -->
            <p class="prompt" data-testid="confusion-prompt">{stem(current.prompt)}</p>

            <div class="gate">
                <ConfidenceGate committed={confidence} {onCommit} />
            </div>

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
                <div class="feedback">
                    <!-- Feedback dominates post-reveal (Ledger §5); pairs colour
                         with an icon + text label (color-never-alone, C8). -->
                    <p
                        class="verdict"
                        data-testid="verdict"
                        class:correct={lastCorrect}
                        class:incorrect={!lastCorrect}
                    >
                        <span class="verdict-icon" aria-hidden="true">
                            {lastCorrect ? "✓" : "✗"}
                        </span>
                        <span class="verdict-label">
                            {lastCorrect ? "Correct" : "Incorrect"}
                        </span>
                    </p>
                    <div class="feedback-actions">
                        <button
                            type="button"
                            class="next-btn"
                            data-testid="next-item"
                            on:click={next}
                        >
                            Next
                        </button>
                    </div>
                </div>
            {/if}
        </div>
    {/if}
</div>

<style lang="scss">
    // Focus mode: center the single card in the viewport so empty space is
    // balanced, not dumped below the fold. (48px = shell top bar.)
    .confusion-mode {
        display: grid;
        place-items: center;
        min-height: calc(100vh - 48px);
        padding: var(--space-xl) var(--space-lg);
        font-size: var(--font-size);
        color: var(--fg);
    }

    // Focus-mode surface: one item, minimal chrome, content-dominant (Ledger §5).
    .card {
        width: 100%;
        max-width: 40rem;
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow:
            0 1px 2px rgba(14, 15, 19, 0.06),
            0 1px 3px rgba(14, 15, 19, 0.05);
    }

    .item {
        padding: var(--space-xl);
    }

    .prompt {
        // Card title
        margin: 0;
        font-size: 20px;
        font-weight: 600;
        letter-spacing: -0.01em;
        line-height: 1.35;
    }

    .gate {
        margin-top: var(--space-lg);
    }

    .treatments {
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
        margin-top: var(--space-lg);
    }

    // Recognition-style choice rows (not free recall). Scoped styles beat the
    // global <button> base on specificity.
    .treatment {
        display: block;
        width: 100%;
        text-align: left;
        min-height: 44px;
        padding: var(--space-md);
        margin: 0;
        font: inherit;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control); // clears 3:1 (C3)
        border-radius: var(--border-radius);
        cursor: pointer;
        transition:
            border-color var(--transition) ease,
            background var(--transition) ease;

        &:hover:not([disabled]) {
            border-color: var(--accent);
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }

        &[disabled] {
            cursor: default;
            opacity: 0.7;
        }
    }

    .feedback {
        margin-top: var(--space-lg);
    }

    // The verdict is the dominant element post-reveal; icon + label + colour +
    // a defined boundary (so the chip clears 3:1 in dark mode).
    .verdict {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        margin: 0;
        padding: var(--space-md);
        font-size: 18px;
        font-weight: 600;
        border-radius: var(--border-radius);
        border: 1px solid transparent;
    }

    .verdict.correct {
        color: var(--fg-success);
        background: rgba(31, 157, 87, 0.12);
        border-color: rgba(31, 157, 87, 0.4);
    }

    .verdict.incorrect {
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border-color: rgba(214, 69, 65, 0.4);
    }

    .verdict-icon {
        font-size: 20px;
        font-weight: 700;
    }

    .feedback-actions {
        display: flex;
        justify-content: flex-end;
        margin-top: var(--space-md);
    }

    // Secondary/ghost action — navigation does not out-shout the answer.
    .next-btn {
        font: inherit;
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-xl);
        cursor: pointer;

        &:hover {
            border-color: var(--accent);
            color: var(--accent);
        }

        &:active {
            transform: translateY(1px);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .finished-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--space-md);
        padding: var(--space-xxl) var(--space-xl);
        text-align: center;
    }

    .finished-icon {
        display: grid;
        place-items: center;
        width: 48px;
        height: 48px;
        border-radius: var(--border-radius-large);
        font-size: 24px;
        color: var(--fg-success);
        background: rgba(31, 157, 87, 0.12);
    }

    .finished {
        margin: 0;
        font-size: 18px;
        font-weight: 600;
    }

    .primary-link {
        font-weight: 600;
        color: #fff;
        text-decoration: none;
        background: var(--button-primary-bg);
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-xl);
        box-shadow: 0 1px 2px rgba(31, 58, 95, 0.24);

        &:hover {
            background: var(--button-primary-hover-bg);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }
</style>
