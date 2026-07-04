<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Research simulation (T1). The exam shell's Literature tab is the searchable
corpus (client-side, offline); the response is a single citation the learner
submits (mode:"research"). Graded correctness-only (1/0); time-to-cite is a
neutral secondary signal, never a credit multiplier (OQ-2). Section-agnostic —
the literature is scoped to the note's section, so ASC (FAR/BAR) shows
paraphrase + link and IRC/PCAOB/NIST show verbatim text.
-->
<script lang="ts">
    import type { StepResult } from "@generated/anki/scheduler_pb";
    import { submitPerformanceAttempt } from "@generated/backend";

    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";

    import ExamShell from "../ankountant-tbs/ExamShell.svelte";
    import type { TbsModel } from "../ankountant-tbs/lib";
    import { buildResearchSubmission, buildRevealModel } from "../ankountant-tbs/lib";
    import ResultsLayer from "../ankountant-tbs/ResultsLayer.svelte";

    export let noteId: bigint;
    export let model: TbsModel;
    export let fields: string[];
    export let tags: string[];

    const startedAt = Date.now();
    let confidence: ConfidenceLevel | null = null;
    let citation = "";
    let submitting = false;
    let results: StepResult[] | null = null;
    let correct: boolean | null = null;
    let elapsedMs = 0;
    let submitError: string | null = null;

    $: reveal = results ? buildRevealModel(fields, tags) : null;

    async function submit(): Promise<void> {
        if (confidence === null || citation.trim() === "" || submitting) {
            return;
        }
        submitting = true;
        elapsedMs = Date.now() - startedAt;
        submitError = null;
        try {
            const resp = await submitPerformanceAttempt(
                {
                    itemNoteId: noteId,
                    mode: "research",
                    submissionJson: buildResearchSubmission(citation),
                    confidence,
                    latencyMs: elapsedMs,
                },
                { alertOnError: false },
            );
            results = resp.steps;
            correct = resp.totalCredit >= 1;
        } catch (error) {
            submitError = error instanceof Error ? error.message : String(error);
        } finally {
            submitting = false;
        }
    }
</script>

<ExamShell
    {model}
    title="Research simulation"
    committed={confidence}
    onCommit={(l) => (confidence = l)}
    onCite={(c) => (citation = c)}
    defaultTool="literature"
>
    <div class="research-response" data-testid="research-surface" data-shape="research">
        <p class="hint">
            Find the governing citation in the Literature tab, then enter it below.
        </p>

        <label class="cite-field">
            <span class="picker-label">Governing citation</span>
            <input
                type="text"
                class="cite-input"
                data-testid="citation-input"
                bind:value={citation}
                placeholder="e.g. ASC 842-20-25-1"
                disabled={results !== null}
            />
        </label>

        <div class="actions">
            <button
                class="submit"
                data-testid="research-submit"
                disabled={submitting ||
                    confidence === null ||
                    citation.trim() === "" ||
                    results !== null}
                on:click={submit}
            >
                Submit citation
            </button>
            {#if confidence === null}
                <span class="gate-hint" data-testid="research-gate-hint">
                    Commit a confidence level first.
                </span>
            {/if}
        </div>

        {#if submitError}
            <p class="submit-error" data-testid="research-submit-error" role="alert">
                Could not submit citation: {submitError}
            </p>
        {/if}

        {#if correct !== null}
            <p
                class="verdict"
                data-testid="research-verdict"
                class:correct
                class:incorrect={!correct}
            >
                <span class="verdict-icon" aria-hidden="true">
                    {correct ? "✓" : "✗"}
                </span>
                <span>{correct ? "Correct citation" : "Incorrect citation"}</span>
            </p>
            <p class="time" data-testid="research-time">
                Found in {(elapsedMs / 1000).toFixed(1)}s
                <span class="time-note">(time is a signal, not part of the score)</span>
            </p>
        {/if}

        {#if results && reveal}
            <ResultsLayer {reveal} {results} />
        {/if}
    </div>
</ExamShell>

<style lang="scss">
    .research-response {
        display: flex;
        flex-direction: column;
        gap: var(--space-md);
    }

    .hint {
        margin: 0;
        color: var(--fg-subtle);
        max-width: 60ch;
    }

    .cite-field {
        display: flex;
        flex-direction: column;
        gap: var(--space-xs);

        .picker-label {
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }
    }

    .cite-input {
        width: 100%;
        max-width: 24rem;
        box-sizing: border-box;
        min-height: 36px;
        padding: var(--space-sm) var(--space-md);
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums lining-nums;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
            border-color: var(--accent);
        }

        &[disabled] {
            opacity: 0.7;
        }
    }

    .actions {
        display: flex;
        align-items: center;
        gap: var(--space-md);
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

    .submit-error {
        margin: 0;
        padding: var(--space-sm) var(--space-md);
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border: 1px solid rgba(214, 69, 65, 0.4);
        border-radius: var(--border-radius);
    }

    .verdict {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        margin: 0;
        font-weight: 600;

        &.correct {
            color: var(--fg-success);
        }

        &.incorrect {
            color: var(--fg-error);
        }
    }

    .verdict-icon {
        font-size: 18px;
        font-weight: 700;
    }

    .time {
        margin: 0;
        font-variant-numeric: tabular-nums lining-nums;
        color: var(--fg-subtle);
        font-size: var(--type-caption-size);

        .time-note {
            font-variant-numeric: normal;
            opacity: 0.85;
        }
    }
</style>
