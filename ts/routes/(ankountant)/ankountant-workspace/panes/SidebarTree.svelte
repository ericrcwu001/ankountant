<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Recursive deck/tag tree for the Browse sidebar. Each row is a clickable filter
(plain replaces the search, Ctrl ANDs, Shift ORs, Alt negates — handled by the
parent via the passed event) with a disclosure triangle for branches. Self-
imports to recurse (Svelte 5's svelte:self replacement). While the sidebar
filter box is active, every branch is force-expanded so matches are visible.
-->
<script lang="ts">
    import type { TreeItem } from "./sidebarModel";
    import SidebarTree from "./SidebarTree.svelte";

    export let items: TreeItem[];
    export let onPick: (item: TreeItem, event: MouseEvent) => void;
    export let filtering = false;

    // Per-node open state, defaulting to the backend's collapsed flag.
    let open: Record<string, boolean> = {};
    function isOpen(item: TreeItem): boolean {
        if (filtering) {
            return true;
        }
        return open[item.id] ?? !item.collapsed;
    }
    function toggle(item: TreeItem): void {
        open = { ...open, [item.id]: !isOpen(item) };
    }
</script>

<ul class="tree" role="group">
    {#each items as item (item.id)}
        <li>
            <div class="row" style="padding-left:{item.level * 12}px">
                {#if item.children.length > 0}
                    <button
                        type="button"
                        class="twisty"
                        class:open={isOpen(item)}
                        aria-label={isOpen(item) ? "Collapse" : "Expand"}
                        on:click={() => toggle(item)}
                    >
                        ▸
                    </button>
                {:else}
                    <span class="twisty spacer" aria-hidden="true"></span>
                {/if}
                <button
                    type="button"
                    class="node"
                    title={item.fullName}
                    on:click={(e) => onPick(item, e)}
                >
                    <span class="glyph" aria-hidden="true">
                        {item.kind === "deck" ? "📚" : "🏷"}
                    </span>
                    <span class="label">{item.label}</span>
                </button>
            </div>
            {#if item.children.length > 0 && isOpen(item)}
                <SidebarTree items={item.children} {onPick} {filtering} />
            {/if}
        </li>
    {/each}
</ul>

<style lang="scss">
    .tree {
        list-style: none;
        margin: 0;
        padding: 0;
    }

    .row {
        display: flex;
        align-items: center;
        gap: 2px;
    }

    .twisty {
        flex: 0 0 auto;
        width: 16px;
        height: 22px;
        display: grid;
        place-items: center;
        font-size: 9px;
        color: var(--fg-faint);
        background: transparent;
        border: 0;
        cursor: pointer;
        transition: transform var(--motion-fast) ease;

        &.open {
            transform: rotate(90deg);
        }

        &.spacer {
            cursor: default;
        }
    }

    .node {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
        flex: 1;
        min-width: 0;
        font: inherit;
        font-size: var(--type-caption-size);
        text-align: left;
        color: var(--fg);
        background: transparent;
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-xs);
        cursor: pointer;

        &:hover {
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: -1px;
        }
    }

    .glyph {
        flex: 0 0 auto;
        font-size: 11px;
        opacity: 0.8;
    }

    .label {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    @media (prefers-reduced-motion: reduce) {
        .twisty {
            transition: none;
        }
    }
</style>
