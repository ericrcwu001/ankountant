<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { StepResult } from "@generated/anki/scheduler_pb";
    import { submitPerformanceAttempt } from "@generated/backend";

    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";
    import ConfidenceGate from "$lib/components/ConfidenceGate.svelte";

    import type { JeLineInput, NumericCellInput, TbsModel } from "./lib";
    import { buildJeSubmission, buildNumericSubmission, JE_ACCOUNTS } from "./lib";

    export let noteId: bigint;
    export let model: TbsModel;

    const startedAt = Date.now();

    const jeLines: JeLineInput[] = model.steps.map((s) => ({
        id: s.id,
        account: "",
        side: "",
        amount: "",
        noEntry: false,
    }));

    // B4 (agent 07) — spare scratch rows so the number of lines isn't a cue.
    // They are NOT graded (not part of the submission), just a work affordance.
    const SPARE_ROWS = 2;
    const spareLines = Array.from({ length: SPARE_ROWS }, () => ({
        account: "",
        side: "",
        amount: "",
    }));

    function toggleNoEntry(i: number): void {
        const l = jeLines[i];
        l.noEntry = !l.noEntry;
        if (l.noEntry) {
            l.account = "";
            l.side = "";
            l.amount = "";
        }
        // Reassign to trigger reactivity on the parallel array.
        jeLines[i] = l;
    }
    const numericCells: NumericCellInput[] = model.steps.map((s) => ({
        id: s.id,
        value: "",
    }));

    let results: StepResult[] | null = null;
    let total: number | null = null;
    let confidence: ConfidenceLevel | null = null;
    let submitting = false;
    let submitError: string | null = null;

    $: resultById = new Map((results ?? []).map((r) => [r.id, r]));

    async function submit(): Promise<void> {
        if (confidence === null || submitting || results !== null) {
            return;
        }
        submitting = true;
        submitError = null;
        try {
            const submissionJson =
                model.shape === "numeric"
                    ? buildNumericSubmission(numericCells)
                    : buildJeSubmission(jeLines);
            const resp = await submitPerformanceAttempt(
                {
                    itemNoteId: noteId,
                    mode: "tbs",
                    submissionJson,
                    confidence,
                    latencyMs: Date.now() - startedAt,
                },
                { alertOnError: false },
            );
            results = resp.steps;
            total = resp.totalCredit;
        } catch (error) {
            submitError = error instanceof Error ? error.message : String(error);
        } finally {
            submitting = false;
        }
    }
</script>

<!-- NOTE: this is a dedicated task surface, NOT the flashcard reviewer. It must
     never expose Again/Hard/Good/Easy grading buttons (B4-D3 / A52). -->
<div class="tbs-surface" data-testid="tbs-surface" data-shape={model.shape}>
    <header class="tbs-head">
        <h1>Task-Based Simulation</h1>
        <p class="prompt" data-testid="tbs-prompt">{model.prompt}</p>
    </header>

    <div class="gate card">
        <ConfidenceGate
            committed={confidence}
            onCommit={(level) => (confidence = level)}
        />
    </div>

    <div class="tbs-body">
        <div class="task card">
            {#if model.shape === "numeric"}
                <table class="grid numeric-grid" data-testid="numeric-grid">
                    <thead>
                        <tr>
                            <th>Cell</th>
                            <th>Value</th>
                            <th class="result-col">
                                <span class="sr-only">Result</span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each model.steps as step, i (step.id)}
                            <tr
                                class="cell-row"
                                data-testid="cell-row"
                                data-step-id={step.id}
                            >
                                <td class="label">{step.label}</td>
                                <td>
                                    <input
                                        type="text"
                                        inputmode="decimal"
                                        data-testid="cell-input"
                                        data-step-id={step.id}
                                        bind:value={numericCells[i].value}
                                    />
                                </td>
                                <td class="result" data-testid="cell-result">
                                    {#if resultById.has(step.id)}
                                        {@const ok = resultById.get(step.id)?.correct}
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
                                </td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            {:else}
                <table class="grid je-grid" data-testid="je-grid">
                    <thead>
                        <tr>
                            <th>Account</th>
                            <th>Debit / Credit</th>
                            <th class="amount-col">Amount</th>
                            <th class="noentry-col">No entry</th>
                            <th class="result-col">
                                <span class="sr-only">Result</span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each model.steps as step, i (step.id)}
                            <tr
                                class="je-row"
                                class:no-entry={jeLines[i].noEntry}
                                data-testid="je-row"
                                data-step-id={step.id}
                            >
                                <td>
                                    <!-- Controlled account picker (not free text), agent 07. -->
                                    <select
                                        data-testid="je-account"
                                        data-step-id={step.id}
                                        bind:value={jeLines[i].account}
                                        disabled={jeLines[i].noEntry ||
                                            resultById.has(step.id)}
                                    >
                                        <option value="">Select account…</option>
                                        {#each JE_ACCOUNTS as acct (acct)}
                                            <option value={acct}>{acct}</option>
                                        {/each}
                                    </select>
                                </td>
                                <td>
                                    <select
                                        data-testid="je-side"
                                        data-step-id={step.id}
                                        bind:value={jeLines[i].side}
                                        disabled={jeLines[i].noEntry ||
                                            resultById.has(step.id)}
                                    >
                                        <option value="">Select</option>
                                        <option value="dr">Debit</option>
                                        <option value="cr">Credit</option>
                                    </select>
                                </td>
                                <td class="amount-col">
                                    <input
                                        type="text"
                                        inputmode="decimal"
                                        data-testid="je-amount"
                                        data-step-id={step.id}
                                        bind:value={jeLines[i].amount}
                                        disabled={jeLines[i].noEntry ||
                                            resultById.has(step.id)}
                                    />
                                </td>
                                <td class="noentry-col">
                                    <input
                                        type="checkbox"
                                        data-testid="je-no-entry"
                                        data-step-id={step.id}
                                        aria-label="No entry required for this line"
                                        checked={jeLines[i].noEntry}
                                        disabled={resultById.has(step.id)}
                                        on:change={() => toggleNoEntry(i)}
                                    />
                                </td>
                                <td class="result" data-testid="je-result">
                                    {#if resultById.has(step.id)}
                                        {@const ok = resultById.get(step.id)?.correct}
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
                                </td>
                            </tr>
                        {/each}
                        <!-- Spare scratch rows (ungraded): the number of lines is
                             not a cue, and the learner has room to work. -->
                        {#each spareLines as spare, i (i)}
                            <tr class="je-row spare" data-testid="je-spare-row">
                                <td>
                                    <select
                                        bind:value={spare.account}
                                        aria-label="Spare account"
                                    >
                                        <option value="">Spare (not graded)…</option>
                                        {#each JE_ACCOUNTS as acct (acct)}
                                            <option value={acct}>{acct}</option>
                                        {/each}
                                    </select>
                                </td>
                                <td>
                                    <select
                                        bind:value={spare.side}
                                        aria-label="Spare debit/credit"
                                    >
                                        <option value="">Select</option>
                                        <option value="dr">Debit</option>
                                        <option value="cr">Credit</option>
                                    </select>
                                </td>
                                <td class="amount-col">
                                    <input
                                        type="text"
                                        inputmode="decimal"
                                        bind:value={spare.amount}
                                        aria-label="Spare amount"
                                    />
                                </td>
                                <td class="noentry-col"></td>
                                <td class="result"></td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            {/if}

            <div class="actions">
                <button
                    class="submit"
                    data-testid="tbs-submit"
                    disabled={submitting || confidence === null || results !== null}
                    on:click={submit}
                >
                    Submit
                </button>

                {#if confidence === null}
                    <span class="gate-hint">Commit a confidence level first.</span>
                {/if}

                {#if total !== null}
                    <p class="total" data-testid="tbs-total">
                        <span class="total-label">Partial credit</span>
                        <span class="total-value">{Math.round(total * 100)}%</span>
                    </p>
                {/if}
            </div>
            {#if submitError}
                <p class="submit-error" data-testid="tbs-submit-error" role="alert">
                    Could not submit attempt: {submitError}
                </p>
            {/if}
        </div>

        <aside class="exhibits" data-testid="exhibits">
            <h2>Exhibits</h2>
            {#each model.exhibits as exhibit, i (i)}
                <div class="exhibit card" data-testid="exhibit">
                    <h3>{exhibit.title}</h3>
                    <pre>{exhibit.body}</pre>
                </div>
            {/each}
        </aside>
    </div>
</div>

<style lang="scss">
    .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    .tbs-surface {
        max-width: 62rem;
        margin: 0 auto;
        padding: var(--space-xl) var(--space-lg) var(--space-xxl);
        font-size: var(--font-size);
        color: var(--fg);
    }

    .tbs-head {
        margin-bottom: var(--space-lg);

        h1 {
            // Section heading
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            letter-spacing: var(--type-section-heading-tracking);
            line-height: var(--type-section-heading-line);
            margin: 0;
        }

        .prompt {
            margin: var(--space-xs) 0 0;
            color: var(--fg-subtle);
            max-width: 60ch;
        }
    }

    .tbs-body {
        display: flex;
        gap: var(--space-xl);
        align-items: flex-start;
    }

    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        // Theme-aware Ledger elevation (dark mode gets a real shadow, not the
        // near-invisible light-ink one).
        box-shadow: var(--elevation-e1);
    }

    .gate {
        max-width: 62rem;
        margin: 0 0 var(--space-lg);
        padding: var(--space-lg);
    }

    .task {
        flex: 2;
        min-width: 0;
        padding: var(--space-lg);
    }

    .exhibits {
        flex: 1;
        min-width: 0;
        // Keep exhibits co-visible with the active cell (kill split-attention).
        position: sticky;
        top: var(--space-lg);

        h2 {
            margin: 0 0 var(--space-sm);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }
    }

    .exhibit {
        padding: var(--space-md);

        & + & {
            margin-top: var(--space-md);
        }

        h3 {
            margin: 0 0 var(--space-xs);
            font-size: 15px;
            font-weight: 600;
        }

        pre {
            margin: 0;
            white-space: pre-wrap;
            font-family: var(--font-mono);
            font-size: 13px;
            line-height: 1.5;
            color: var(--fg-subtle);
        }
    }

    // Ledger grid: hairline row dividers only (no full grid), tabular figures.
    .grid {
        width: 100%;
        border-collapse: collapse;

        th,
        td {
            padding: var(--space-sm);
            text-align: left;
            vertical-align: middle;
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

        .label {
            font-weight: 500;
        }

        .result-col,
        .result {
            width: 2rem;
            text-align: center;
        }

        .noentry-col {
            width: 4rem;
            text-align: center;
        }

        // Spare scratch rows read as secondary (they are ungraded).
        .spare {
            opacity: 0.7;
        }

        input,
        select {
            width: 100%;
            box-sizing: border-box;
            min-height: 30px; // >= 24px target floor (C7)
            padding: var(--space-sm);
            font: inherit;
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border-control); // clears 3:1 (C3)
            border-radius: var(--border-radius);

            // Visible 2px navy focus ring + offset, never a glow (C3 / §3).
            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: 1px;
                border-color: var(--accent);
            }
        }

        // Style the select to the control token instead of raw OS chrome, with
        // a custom caret (no em-dash placeholder).
        select {
            appearance: none;
            -webkit-appearance: none;
            padding-right: calc(var(--space-xl) - var(--space-xxs));
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath d='M2.5 4.5 6 8l3.5-3.5' fill='none' stroke='%23767c88' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: right var(--space-sm) center;
        }

        // Ledger/JE numeric cells: monospace + tabular figures, right-aligned so
        // columns line up (Ledger §2, C10).
        input[inputmode="decimal"] {
            font-family: var(--font-mono);
            font-variant-numeric: tabular-nums lining-nums;
            text-align: right;
        }
    }

    // Step state = icon + label (aria) + color (color-never-alone, C8).
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
        margin-top: var(--space-lg);
    }

    .gate-hint {
        color: var(--fg-subtle);
        font-size: 13px;
    }

    .submit-error {
        margin: var(--space-md) 0 0;
        padding: var(--space-sm) var(--space-md);
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border: 1px solid rgba(214, 69, 65, 0.4);
        border-radius: var(--border-radius);
    }

    // Primary navy action (scoped → overrides the global button base).
    .submit {
        font: inherit;
        font-weight: 600;
        color: #fff;
        background: var(--button-primary-bg);
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-xl);
        box-shadow: 0 1px 2px rgba(31, 58, 95, 0.24);
        cursor: pointer;

        &:hover:not([disabled]) {
            background: var(--button-primary-hover-bg);
        }

        &:active:not([disabled]) {
            transform: translateY(1px);
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
