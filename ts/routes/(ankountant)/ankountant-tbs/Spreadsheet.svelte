<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Lightweight, UNGRADED scratch formula grid for the exam shell (D6). A cell holds
raw text; a leading `=` makes it a formula (cell refs, ranges, + - * /, and
SUM / AVERAGE / ROUND). While a cell is focused you edit its raw formula; on blur
it shows the computed value. Nothing here is ever submitted or graded.
-->
<script lang="ts">
    import {
        cellKey,
        colLabel,
        displayCell,
        GRID_COLS,
        GRID_ROWS,
    } from "./spreadsheet";

    let raw: Record<string, string> = {};
    let editing: string | null = null;

    $: resolve = (ref: string): string => raw[ref] ?? "";

    function onInput(key: string, event: Event): void {
        const target = event.currentTarget as HTMLInputElement;
        raw = { ...raw, [key]: target.value };
    }

    function displayValue(cells: Record<string, string>, key: string): string {
        return displayCell(cells[key] ?? "", (ref) => cells[ref] ?? "");
    }

    function onFocus(key: string, event: FocusEvent): void {
        editing = key;
        const target = event.currentTarget as HTMLInputElement;
        target.value = raw[key] ?? "";
    }

    function onBlur(key: string, event: FocusEvent): void {
        const target = event.currentTarget as HTMLInputElement;
        const nextRaw = { ...raw, [key]: target.value };
        raw = nextRaw;
        editing = null;
        target.value = displayValue(nextRaw, key);
    }

    function onKeydown(key: string, event: KeyboardEvent): void {
        if (event.key !== "Enter") {
            return;
        }

        event.preventDefault();
        const target = event.currentTarget as HTMLInputElement;
        const nextRaw = { ...raw, [key]: target.value };
        raw = nextRaw;
        editing = null;
        target.blur();
        target.value = displayValue(nextRaw, key);
    }

    function shown(key: string): string {
        return editing === key
            ? (raw[key] ?? "")
            : displayCell(raw[key] ?? "", resolve);
    }

    const cols = Array.from({ length: GRID_COLS }, (_, c) => c);
    const rows = Array.from({ length: GRID_ROWS }, (_, r) => r);
</script>

<div class="scratch" data-testid="scratchpad">
    <p class="hint">
        Scratchpad — <strong>ungraded</strong>
        . Start a cell with
        <code>=</code>
        for a formula (e.g.
        <code>=SUM(A1:A3)</code>
        ,
        <code>=ROUND(A1/12, 2)</code>
        ).
    </p>
    <div class="grid-wrap">
        <table class="sheet">
            <thead>
                <tr>
                    <th class="corner" aria-hidden="true"></th>
                    {#each cols as c (c)}
                        <th>{colLabel(c)}</th>
                    {/each}
                </tr>
            </thead>
            <tbody>
                {#each rows as r (r)}
                    <tr>
                        <th class="rownum">{r + 1}</th>
                        {#each cols as c (c)}
                            {@const key = cellKey(c, r)}
                            <td>
                                <input
                                    type="text"
                                    class="cell"
                                    data-testid="sheet-cell"
                                    data-cell={key}
                                    aria-label={key}
                                    value={shown(key)}
                                    on:focus={(e) => onFocus(key, e)}
                                    on:blur={(e) => onBlur(key, e)}
                                    on:input={(e) => onInput(key, e)}
                                    on:keydown={(e) => onKeydown(key, e)}
                                />
                            </td>
                        {/each}
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
</div>

<style lang="scss">
    .scratch {
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
        height: 100%;
        min-height: 0;
    }

    .hint {
        margin: 0;
        font-size: var(--type-caption-size);
        color: var(--fg-subtle);

        code {
            font-family: var(--font-mono);
            font-size: 12px;
        }
    }

    .grid-wrap {
        overflow: auto;
        min-height: 0;
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius);
    }

    .sheet {
        border-collapse: collapse;
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums lining-nums;

        th,
        td {
            border: 1px solid var(--border-subtle);
            padding: 0;
        }

        thead th,
        .rownum {
            font-size: 11px;
            font-weight: 600;
            color: var(--fg-subtle);
            background: var(--canvas-inset);
            text-align: center;
            min-width: 2rem;
            padding: 2px var(--space-xs);
        }

        .corner {
            background: var(--canvas-inset);
        }
    }

    .cell {
        width: 6rem;
        box-sizing: border-box;
        border: 0;
        background: transparent;
        color: var(--fg);
        font: inherit;
        text-align: right;
        padding: var(--space-xs);

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: -2px;
        }
    }
</style>
