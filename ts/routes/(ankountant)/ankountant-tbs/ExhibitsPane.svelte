<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Typed exhibits pane (ADR 0008 / D9). Renders each exhibit by kind: `table`
exhibits get a real table (columns + rows); everything else renders its text
body in a mono block. Its own scroll region so it can sit beside a work area
and stay co-visible (C13). Reused by the exam shell + surfaces.
-->
<script lang="ts">
    import type { Exhibit } from "./lib";

    export let exhibits: Exhibit[];
</script>

<div class="exhibits" data-testid="exhibits">
    <h2>Exhibits</h2>
    {#if exhibits.length === 0}
        <p class="empty">No exhibits for this task.</p>
    {/if}
    {#each exhibits as exhibit, i (exhibit.id ?? i)}
        <div class="exhibit card" data-testid="exhibit" data-kind={exhibit.kind}>
            <h3>
                {exhibit.title}
                <span class="kind-tag">{exhibit.kind}</span>
            </h3>
            {#if exhibit.kind === "table" && exhibit.rows && exhibit.rows.length > 0}
                <table class="exhibit-table">
                    {#if exhibit.columns && exhibit.columns.length > 0}
                        <thead>
                            <tr>
                                {#each exhibit.columns as col (col)}
                                    <th>{col}</th>
                                {/each}
                            </tr>
                        </thead>
                    {/if}
                    <tbody>
                        {#each exhibit.rows as row, r (r)}
                            <tr>
                                {#each row as cell, c (c)}
                                    <td>{cell}</td>
                                {/each}
                            </tr>
                        {/each}
                    </tbody>
                </table>
            {:else}
                <pre>{exhibit.body}</pre>
            {/if}
        </div>
    {/each}
</div>

<style lang="scss">
    .exhibits {
        min-width: 0;
        height: 100%;
        overflow: auto;

        h2 {
            margin: 0 0 var(--space-sm);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }
    }

    .empty {
        margin: 0;
        color: var(--fg-subtle);
        font-size: var(--type-caption-size);
    }

    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
    }

    .exhibit {
        padding: var(--space-md);

        & + & {
            margin-top: var(--space-md);
        }

        h3 {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: var(--space-sm);
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

    // Small uppercase kind chip so the exhibit vocabulary (email/invoice/table)
    // is legible without leaning on colour alone.
    .kind-tag {
        flex: none;
        font-size: 10px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
        background: var(--canvas-inset);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius);
        padding: 1px var(--space-xs);
    }

    .exhibit-table {
        width: 100%;
        border-collapse: collapse;
        font-family: var(--font-mono);
        font-size: 12px;
        font-variant-numeric: tabular-nums lining-nums;

        th,
        td {
            padding: var(--space-xs) var(--space-sm);
            text-align: left;
            border-bottom: 1px solid var(--border-subtle);
        }

        thead th {
            color: var(--fg-subtle);
            border-bottom: 1px solid var(--border);
        }
    }
</style>
