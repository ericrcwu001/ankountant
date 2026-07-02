<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

One row of the Browse table. Lazily fetches its cells via browser_row_for_id
(cached across scrolls), absolutely positioned by the pane's windowing so only
visible rows are mounted. Selection/focus styling and marked/suspended/flag
colors mirror the native browser; clicks and right-clicks bubble up with the
event so the pane can do range/multi-select and show the context menu.
-->
<script lang="ts">
    import type { BrowserRow } from "@generated/anki/search_pb";
    import { BrowserRow_Color } from "@generated/anki/search_pb";
    import { browserRowForId } from "@generated/backend";

    export let id: bigint;
    export let columnCount: number;
    export let gridTemplate: string;
    export let top: number;
    export let selected = false;
    export let focused = false;
    export let cache: Map<string, BrowserRow>;
    /** Bumped by the pane to force a re-fetch after an edit/mutation. */
    export let version = 0;
    export let onSelect: ((event: MouseEvent) => void) | undefined = undefined;
    export let onContextMenu: ((event: MouseEvent) => void) | undefined = undefined;

    let row: BrowserRow | null = null;

    async function fetchRow(rowId: bigint, _version: number): Promise<void> {
        const key = rowId.toString();
        const cached = cache.get(key);
        if (cached) {
            row = cached;
            return;
        }
        row = null;
        try {
            const fetched = await browserRowForId({ val: rowId });
            cache.set(key, fetched);
            if (rowId === id) {
                row = fetched;
            }
        } catch {
            row = null;
        }
    }

    $: void fetchRow(id, version);

    // Flag colors for the left stripe; marked/suspended tint the whole row.
    const FLAG_COLORS: Partial<Record<BrowserRow_Color, string>> = {
        [BrowserRow_Color.FLAG_RED]: "#e2564f",
        [BrowserRow_Color.FLAG_ORANGE]: "#e8912d",
        [BrowserRow_Color.FLAG_GREEN]: "#4aa564",
        [BrowserRow_Color.FLAG_BLUE]: "#4f8ce2",
        [BrowserRow_Color.FLAG_PINK]: "#e26fb0",
        [BrowserRow_Color.FLAG_TURQUOISE]: "#3fb8b0",
        [BrowserRow_Color.FLAG_PURPLE]: "#9a6fe2",
    };

    $: color = row?.color ?? BrowserRow_Color.DEFAULT;
    $: flagColor = FLAG_COLORS[color] ?? "transparent";
    $: marked = color === BrowserRow_Color.MARKED;
    $: suspended = color === BrowserRow_Color.SUSPENDED;
    $: buried = color === BrowserRow_Color.BURIED;
</script>

<div
    class="browse-row"
    class:selected
    class:focused
    class:marked
    class:suspended
    class:buried
    style="top:{top}px; grid-template-columns:{gridTemplate}; --flag:{flagColor}"
    role="row"
    aria-selected={selected}
    tabindex="-1"
    on:mousedown={(e) => onSelect?.(e)}
    on:contextmenu|preventDefault={(e) => onContextMenu?.(e)}
>
    {#if row}
        {#each row.cells as cell, i (i)}
            <span class="cell" class:rtl={cell.isRtl} role="cell">{cell.text}</span>
        {/each}
    {:else}
        {#each Array(columnCount) as _, i (i)}
            <span class="cell placeholder" role="cell"></span>
        {/each}
    {/if}
</div>

<style lang="scss">
    .browse-row {
        position: absolute;
        left: 0;
        right: 0;
        display: grid;
        align-items: center;
        height: 28px;
        padding: 0 var(--space-md);
        gap: var(--space-md);
        border-bottom: 1px solid var(--border-subtle);
        border-left: 3px solid var(--flag);
        font-size: var(--type-caption-size);
        white-space: nowrap;
        cursor: pointer;

        &:hover {
            background: var(--canvas);
        }

        &.marked {
            background: color-mix(in srgb, #9a6fe2 12%, transparent);
        }

        &.suspended {
            background: color-mix(in srgb, #e8b64a 16%, transparent);
            color: var(--fg-subtle);
        }

        &.buried {
            color: var(--fg-faint);
        }

        &.selected {
            background: var(--accent-tint);
        }

        &.focused {
            box-shadow: inset 0 0 0 1px var(--accent);
        }
    }

    .cell {
        overflow: hidden;
        text-overflow: ellipsis;

        &.rtl {
            direction: rtl;
        }
    }
</style>
