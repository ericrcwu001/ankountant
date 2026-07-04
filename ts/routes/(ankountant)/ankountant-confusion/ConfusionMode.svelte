<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

B3 (F013) — confusion-set review mode. Plays the interleaved, label-stripped
queue (A3), running the B1 confidence gate + the B2 which-treatment gate per
item, and submitting each choice via SubmitPerformanceAttempt(mode=confusion).
-->
<script lang="ts">
    import type { ConfusionItem } from "@generated/anki/scheduler_pb";
    import { getNote, submitPerformanceAttempt } from "@generated/backend";

    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";
    import ConfidenceGate from "$lib/components/ConfidenceGate.svelte";

    import type { ConfusionRevealModel } from "./lib";
    import {
        buildChoiceSubmission,
        buildConfusionRevealModel,
        confusionQueuePhase,
        stripConfusionSlug,
    } from "./lib";

    export let items: ConfusionItem[];
    export let section = "ALL";

    let index = 0;
    let confidence: ConfidenceLevel | null = null;
    let itemStartedAt = Date.now();
    let lastCorrect: boolean | null = null;
    let reveal: ConfusionRevealModel | null = null;
    let submitting = false;
    let submitError: string | null = null;
    let revealError: string | null = null;

    $: current = items[index];
    $: phase = confusionQueuePhase(index, items.length);
    $: empty = phase === "empty";
    $: done = phase === "finished";
    $: dashboardHref =
        section === "ALL"
            ? "/ankountant-dashboard"
            : `/ankountant-dashboard?section=${section}`;
    $: emptyDetail =
        section === "ALL"
            ? "Load or import CPA practice to build the drill queue."
            : `No ${section} confusion items are available yet. Load or import section practice to build the drill queue.`;

    function onCommit(level: ConfidenceLevel): void {
        confidence = level;
    }

    async function choose(treatment: string): Promise<void> {
        // B2: discrimination is gated behind the committed confidence.
        if (
            confidence === null ||
            submitting ||
            current == null ||
            lastCorrect !== null
        ) {
            return;
        }
        const answered = current;
        submitting = true;
        submitError = null;
        reveal = null;
        revealError = null;
        try {
            const resp = await submitPerformanceAttempt(
                {
                    itemNoteId: answered.noteId,
                    mode: "confusion",
                    submissionJson: buildChoiceSubmission(treatment),
                    confidence,
                    latencyMs: Date.now() - itemStartedAt,
                },
                { alertOnError: false },
            );
            lastCorrect = resp.totalCredit >= 1;
            try {
                const note = await getNote({ nid: answered.noteId });
                reveal = buildConfusionRevealModel(note.fields, answered.setId);
            } catch (error) {
                revealError = error instanceof Error ? error.message : String(error);
            }
        } catch (error) {
            submitError = error instanceof Error ? error.message : String(error);
        } finally {
            submitting = false;
        }
    }

    function next(): void {
        index += 1;
        confidence = null;
        lastCorrect = null;
        reveal = null;
        submitError = null;
        revealError = null;
        itemStartedAt = Date.now();
    }
</script>

<div class="confusion-mode" data-testid="confusion-mode">
    {#if empty}
        <div class="card state-card empty-card" data-testid="confusion-empty">
            <span class="state-icon empty-icon" aria-hidden="true">?</span>
            <p class="finished">No confusion items yet.</p>
            <p class="state-note">{emptyDetail}</p>
            <div class="state-actions">
                <a
                    class="primary-link"
                    href="/ankountant-tbs"
                    data-testid="confusion-to-tbs"
                >
                    Practice simulations
                </a>
                <a
                    class="secondary-link"
                    href={dashboardHref}
                    data-testid="confusion-to-dashboard"
                >
                    Readiness evidence
                </a>
            </div>
        </div>
    {:else if done}
        <div class="card state-card finished-card">
            <span class="state-icon finished-icon" aria-hidden="true">&#10003;</span>
            <p class="finished" data-testid="confusion-finished">
                Queue complete — {items.length} items reviewed.
            </p>
            <a class="primary-link" href={dashboardHref} data-testid="to-dashboard">
                View readiness
            </a>
        </div>
    {:else}
        <div class="card item" data-testid="confusion-item" data-set-id={current.setId}>
            <!-- Label-stripped prompt: NO topic/category/deck label element
                 (B2-D1 / A44). Do NOT render data-testid="category-label". -->
            <p class="prompt" data-testid="confusion-prompt">
                {stripConfusionSlug(current.prompt)}
            </p>

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

            {#if submitError}
                <p
                    class="submit-error"
                    data-testid="confusion-submit-error"
                    role="alert"
                >
                    Could not submit choice: {submitError}
                </p>
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
                    {#if reveal}
                        <div class="correct-treatment" data-testid="confusion-reveal">
                            <span class="reveal-label">Correct treatment</span>
                            <strong data-testid="confusion-correct-treatment">
                                {reveal.correctText}
                            </strong>
                            <span
                                class="blueprint"
                                data-testid="confusion-reveal-blueprint"
                            >
                                {reveal.topicLabel}{reveal.schemaLabel
                                    ? ` · ${reveal.schemaLabel}`
                                    : ""}
                            </span>
                            {#if reveal.source}
                                <p class="source" data-testid="confusion-reveal-source">
                                    {reveal.source}
                                </p>
                            {/if}
                        </div>
                    {/if}
                    {#if revealError}
                        <p
                            class="reveal-error"
                            data-testid="confusion-reveal-error"
                            role="alert"
                        >
                            Attempt recorded, but the correct treatment could not be
                            shown:
                            {revealError}
                        </p>
                    {/if}
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
    .confusion-mode {
        display: grid;
        align-content: start;
        justify-items: center;
        min-height: 100%;
        padding: clamp(72px, 14vh, 160px) var(--space-lg) var(--space-xl);
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
        // Theme-aware Ledger elevation (dark mode gets a real shadow).
        box-shadow: var(--elevation-e1);
    }

    .item {
        padding: var(--space-xl);
    }

    .prompt {
        // Card title
        margin: 0;
        font-size: var(--type-card-title-size);
        font-weight: var(--type-card-title-weight);
        letter-spacing: var(--type-card-title-tracking);
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

    .submit-error {
        margin: var(--space-lg) 0 0;
        padding: var(--space-sm) var(--space-md);
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border: 1px solid rgba(214, 69, 65, 0.4);
        border-radius: var(--border-radius);
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

    .correct-treatment {
        display: flex;
        flex-direction: column;
        gap: var(--space-xs);
        margin-top: var(--space-md);
        padding: var(--space-md);
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius);
    }

    .reveal-label {
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .correct-treatment strong {
        font-size: 16px;
        color: var(--accent);
    }

    .blueprint {
        width: fit-content;
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.03em;
        color: var(--accent);
        background: var(--accent-tint);
        border-radius: var(--border-radius);
        padding: 1px var(--space-sm);
    }

    .source {
        margin: 0;
        color: var(--fg-subtle);
        font-size: 13px;
        line-height: 1.5;
    }

    .reveal-error {
        margin: var(--space-md) 0 0;
        padding: var(--space-sm) var(--space-md);
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border: 1px solid rgba(214, 69, 65, 0.4);
        border-radius: var(--border-radius);
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

    .state-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--space-md);
        padding: var(--space-xxl) var(--space-xl);
        text-align: center;
    }

    .state-icon {
        display: grid;
        place-items: center;
        width: 48px;
        height: 48px;
        border-radius: var(--border-radius-large);
        font-size: 24px;
    }

    .finished-icon {
        color: var(--fg-success);
        background: rgba(31, 157, 87, 0.12);
    }

    .empty-icon {
        color: var(--fg-muted);
        background: var(--canvas-inset);
        border: 1px solid var(--border-subtle);
    }

    .finished {
        margin: 0;
        font-size: 18px;
        font-weight: 600;
    }

    .state-note {
        max-width: 26rem;
        margin: 0;
        color: var(--fg-muted);
        line-height: 1.45;
    }

    .state-actions {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: var(--space-sm);
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

    .secondary-link {
        font-weight: 600;
        color: var(--fg-subtle);
        text-decoration: none;
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-xl);

        &:hover {
            color: var(--fg);
            border-color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }
</style>
