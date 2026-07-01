<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { StepResult } from "@generated/anki/scheduler_pb";
    import { submitPerformanceAttempt } from "@generated/backend";

    import type { JeLineInput, NumericCellInput, TbsModel } from "./lib";
    import { buildJeSubmission, buildNumericSubmission } from "./lib";

    export let noteId: bigint;
    export let model: TbsModel;

    const startedAt = Date.now();

    const jeLines: JeLineInput[] = model.steps.map((s) => ({
        id: s.id,
        account: "",
        side: "",
        amount: "",
    }));
    const numericCells: NumericCellInput[] = model.steps.map((s) => ({
        id: s.id,
        value: "",
    }));

    let results: StepResult[] | null = null;
    let total: number | null = null;
    let submitting = false;

    $: resultById = new Map((results ?? []).map((r) => [r.id, r]));

    async function submit(): Promise<void> {
        submitting = true;
        try {
            const submissionJson =
                model.shape === "numeric"
                    ? buildNumericSubmission(numericCells)
                    : buildJeSubmission(jeLines);
            const resp = await submitPerformanceAttempt({
                itemNoteId: noteId,
                mode: "tbs",
                submissionJson,
                // The pre-reveal confidence is captured by the confidence gate
                // in the confusion flow; the standalone TBS surface defaults to
                // Unsure so the Attempt Log always records a value.
                confidence: "Unsure",
                latencyMs: Date.now() - startedAt,
            });
            results = resp.steps;
            total = resp.totalCredit;
        } finally {
            submitting = false;
        }
    }
</script>

<!-- NOTE: this is a dedicated task surface, NOT the flashcard reviewer. It must
     never expose Again/Hard/Good/Easy grading buttons (B4-D3 / A52). -->
<div class="tbs-surface" data-testid="tbs-surface" data-shape={model.shape}>
    <div class="task">
        <h1>Task-Based Simulation</h1>
        <p class="prompt" data-testid="tbs-prompt">{model.prompt}</p>

        {#if model.shape === "numeric"}
            <table class="numeric-grid" data-testid="numeric-grid">
                <thead>
                    <tr>
                        <th>Cell</th>
                        <th>Value</th>
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
                                    {resultById.get(step.id)?.correct ? "✓" : "✗"}
                                {/if}
                            </td>
                        </tr>
                    {/each}
                </tbody>
            </table>
        {:else}
            <table class="je-grid" data-testid="je-grid">
                <thead>
                    <tr>
                        <th>Account</th>
                        <th>Debit / Credit</th>
                        <th>Amount</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    {#each model.steps as step, i (step.id)}
                        <tr class="je-row" data-testid="je-row" data-step-id={step.id}>
                            <td>
                                <input
                                    type="text"
                                    data-testid="je-account"
                                    data-step-id={step.id}
                                    bind:value={jeLines[i].account}
                                />
                            </td>
                            <td>
                                <select
                                    data-testid="je-side"
                                    data-step-id={step.id}
                                    bind:value={jeLines[i].side}
                                >
                                    <option value="">—</option>
                                    <option value="dr">Debit</option>
                                    <option value="cr">Credit</option>
                                </select>
                            </td>
                            <td>
                                <input
                                    type="text"
                                    inputmode="decimal"
                                    data-testid="je-amount"
                                    data-step-id={step.id}
                                    bind:value={jeLines[i].amount}
                                />
                            </td>
                            <td class="result" data-testid="je-result">
                                {#if resultById.has(step.id)}
                                    {resultById.get(step.id)?.correct ? "✓" : "✗"}
                                {/if}
                            </td>
                        </tr>
                    {/each}
                </tbody>
            </table>
        {/if}

        <button
            class="submit"
            data-testid="tbs-submit"
            disabled={submitting}
            on:click={submit}
        >
            Submit
        </button>

        {#if total !== null}
            <p class="total" data-testid="tbs-total">
                Partial credit: {Math.round(total * 100)}%
            </p>
        {/if}
    </div>

    <aside class="exhibits" data-testid="exhibits">
        <h2>Exhibits</h2>
        {#each model.exhibits as exhibit, i (i)}
            <div class="exhibit" data-testid="exhibit">
                <h3>{exhibit.title}</h3>
                <pre>{exhibit.body}</pre>
            </div>
        {/each}
    </aside>
</div>

<style lang="scss">
    .tbs-surface {
        display: flex;
        gap: 1.5rem;
        align-items: flex-start;
        padding: 1rem;
        font-size: var(--font-size);

        .task {
            flex: 2;
        }

        .exhibits {
            flex: 1;
            border-left: 1px solid var(--border);
            padding-left: 1rem;

            .exhibit pre {
                white-space: pre-wrap;
                background: var(--canvas-inset, #f4f4f4);
                padding: 0.5rem;
            }
        }
    }

    table {
        width: 100%;
        border-collapse: collapse;

        th,
        td {
            border: 1px solid var(--border);
            padding: 0.3rem 0.5rem;
        }

        input,
        select {
            width: 100%;
            box-sizing: border-box;
        }
    }

    .submit {
        margin-top: 1rem;
    }

    .total {
        font-weight: bold;
        margin-top: 0.75rem;
    }
</style>
