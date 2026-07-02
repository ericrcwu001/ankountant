<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Document-review simulation (T3). The exam shell's Exhibits tab holds the source
documents; the response is the primary document rendered with each `<blank
step="id">` marker replaced by a label-stripped `<select>` of that blank's
options (keep / delete / replace). All blanks submit in one attempt
(mode:"doc_review"); grading is per-blank with a partial-credit total (A10 math).
Never renders which option is correct before submit (options carry no key).
-->
<script lang="ts">
    import type { StepResult } from "@generated/anki/scheduler_pb";
    import { submitPerformanceAttempt } from "@generated/backend";

    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";

    import ExamShell from "../ankountant-tbs/ExamShell.svelte";
    import type { RenderStep, TbsModel } from "../ankountant-tbs/lib";
    import {
        buildDocReviewSubmission,
        buildRevealModel,
        segmentDocument,
    } from "../ankountant-tbs/lib";
    import ResultsLayer from "../ankountant-tbs/ResultsLayer.svelte";

    export let noteId: bigint;
    export let model: TbsModel;
    export let fields: string[];
    export let tags: string[];

    const startedAt = Date.now();
    let confidence: ConfidenceLevel | null = null;
    let submitting = false;
    let results: StepResult[] | null = null;
    let total: number | null = null;

    const answers: Record<string, string> = Object.fromEntries(
        model.steps.map((s) => [s.id, ""]),
    );

    $: segments = segmentDocument(model.document);
    $: stepById = new Map<string, RenderStep>(model.steps.map((s) => [s.id, s]));
    $: resultById = new Map((results ?? []).map((r) => [r.id, r]));
    $: reveal = results ? buildRevealModel(fields, tags) : null;

    async function submit(): Promise<void> {
        if (confidence === null || submitting) {
            return;
        }
        submitting = true;
        try {
            const resp = await submitPerformanceAttempt({
                itemNoteId: noteId,
                mode: "doc_review",
                submissionJson: buildDocReviewSubmission(
                    model.steps.map((s) => ({ id: s.id, value: answers[s.id] ?? "" })),
                ),
                confidence,
                latencyMs: Date.now() - startedAt,
            });
            results = resp.steps;
            total = resp.totalCredit;
        } finally {
            submitting = false;
        }
    }
</script>

<ExamShell
    {model}
    title="Document review"
    committed={confidence}
    onCommit={(l) => (confidence = l)}
    defaultTool="exhibits"
>
    <div
        class="docreview-response"
        data-testid="docreview-surface"
        data-shape="doc_review"
    >
        <article class="document card" data-testid="dr-document">
            {#each segments as seg (seg.key)}
                {#if seg.type === "text"}{seg.text}{:else}
                    {@const step = stepById.get(seg.blankId)}
                    <span
                        class="blank"
                        data-testid="dr-blank"
                        data-blank-id={seg.blankId}
                    >
                        <select
                            class="blank-select"
                            data-testid="dr-blank-select"
                            data-blank-id={seg.blankId}
                            bind:value={answers[seg.blankId]}
                            disabled={results !== null}
                            aria-label={step?.label ?? seg.blankId}
                        >
                            <option value="">Select…</option>
                            {#each step?.options ?? [] as opt (opt.id)}
                                <option value={opt.id}>{opt.text}</option>
                            {/each}
                        </select>
                        {#if resultById.has(seg.blankId)}
                            {@const ok = resultById.get(seg.blankId)?.correct}
                            <span
                                class="step-mark"
                                class:correct={ok}
                                class:incorrect={!ok}
                                role="img"
                                aria-label={ok ? "Correct" : "Incorrect"}
                            >
                                {ok ? "✓" : "✗"}
                            </span>
                        {/if}
                    </span>
                {/if}
            {/each}
        </article>

        <div class="actions">
            <button
                class="submit"
                data-testid="docreview-submit"
                disabled={submitting || confidence === null || results !== null}
                on:click={submit}
            >
                Submit review
            </button>
            {#if confidence === null}
                <span class="gate-hint">Commit a confidence level first.</span>
            {/if}
            {#if total !== null}
                <p class="total" data-testid="docreview-total">
                    <span class="total-label">Partial credit</span>
                    <span class="total-value">{Math.round(total * 100)}%</span>
                </p>
            {/if}
        </div>

        {#if results && reveal}
            <ResultsLayer {reveal} {results} />
        {/if}
    </div>
</ExamShell>

<style lang="scss">
    .docreview-response {
        display: flex;
        flex-direction: column;
        gap: var(--space-lg);
    }

    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
    }

    // The primary document reads as prose; blanks are inline controls.
    .document {
        padding: var(--space-lg);
        white-space: pre-wrap;
        line-height: 1.9;
        max-width: 70ch;
        color: var(--fg);
    }

    .blank {
        display: inline-flex;
        align-items: center;
        gap: var(--space-xs);
        white-space: normal;
    }

    .blank-select {
        font: inherit;
        min-height: 30px;
        max-width: 22rem;
        padding: 2px var(--space-xl) 2px var(--space-sm);
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        appearance: none;
        -webkit-appearance: none;
        background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath d='M2.5 4.5 6 8l3.5-3.5' fill='none' stroke='%23767c88' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
        background-repeat: no-repeat;
        background-position: right var(--space-sm) center;

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
            border-color: var(--accent);
        }

        &[disabled] {
            opacity: 0.85;
        }
    }

    .step-mark {
        font-weight: 700;

        &.correct {
            color: var(--fg-success);
        }

        &.incorrect {
            color: var(--fg-error);
        }
    }

    .actions {
        display: flex;
        align-items: center;
        gap: var(--space-lg);
    }

    .submit {
        font: inherit;
        font-weight: 600;
        color: #fff;
        background: var(--button-primary-bg);
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-xl);
        cursor: pointer;

        &:hover:not([disabled]) {
            background: var(--button-primary-hover-bg);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }

        &[disabled] {
            opacity: 0.6;
            cursor: not-allowed;
        }
    }

    .gate-hint {
        font-size: 13px;
        color: var(--fg-subtle);
    }

    .total {
        display: inline-flex;
        align-items: baseline;
        gap: var(--space-sm);
        margin: 0;
        padding: var(--space-xs) var(--space-md);
        border-radius: var(--border-radius);
        background: var(--accent-tint);

        .total-label {
            font-size: 13px;
            color: var(--fg-subtle);
        }

        .total-value {
            font-weight: 600;
            font-variant-numeric: tabular-nums lining-nums;
            color: var(--accent);
        }
    }
</style>
