<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

One leaf of the tiling tree: a slim header (surface switcher + split-right /
split-down / close) over the mounted study surface. Splitting duplicates the
current surface into the new pane; the user re-points it with the switcher.
-->
<script lang="ts">
    import { getContext } from "svelte";

    import type { WorkspaceActions } from "./context";
    import { WORKSPACE_ACTIONS } from "./context";
    import type { LeafNode, Path, SurfaceKind } from "./layout";
    import { SURFACE_KINDS } from "./layout";
    import { SURFACES } from "./surfaces";

    export let node: LeafNode;
    export let path: Path;
    export let canSplit: boolean;
    export let canClose: boolean;

    const actions = getContext<WorkspaceActions>(WORKSPACE_ACTIONS);

    $: def = SURFACES[node.surface];

    function onSwitch(event: Event): void {
        const value = (event.currentTarget as HTMLSelectElement).value as SurfaceKind;
        actions.setSurface(path, value);
    }
</script>

<section class="pane" data-testid="workspace-pane" data-surface={node.surface}>
    <header class="pane-head">
        <span class="glyph" aria-hidden="true">{def.glyph}</span>
        <select
            class="switcher"
            value={node.surface}
            on:change={onSwitch}
            aria-label="Surface shown in this pane"
            data-testid="pane-switcher"
        >
            {#each SURFACE_KINDS as kind (kind)}
                <option value={kind}>{SURFACES[kind].label}</option>
            {/each}
        </select>

        <div class="pane-actions">
            <button
                type="button"
                class="pane-btn"
                title="Split left / right"
                aria-label="Split left and right"
                disabled={!canSplit}
                on:click={() => actions.split(path, "row", node.surface)}
                data-testid="split-row"
            >
                <svg
                    viewBox="0 0 16 16"
                    width="14"
                    height="14"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.4"
                >
                    <rect x="2.5" y="3.5" width="11" height="9" rx="1.5" />
                    <line x1="8" y1="3.5" x2="8" y2="12.5" />
                </svg>
            </button>
            <button
                type="button"
                class="pane-btn"
                title="Split top / bottom"
                aria-label="Split top and bottom"
                disabled={!canSplit}
                on:click={() => actions.split(path, "col", node.surface)}
                data-testid="split-col"
            >
                <svg
                    viewBox="0 0 16 16"
                    width="14"
                    height="14"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.4"
                >
                    <rect x="2.5" y="3.5" width="11" height="9" rx="1.5" />
                    <line x1="2.5" y1="8" x2="13.5" y2="8" />
                </svg>
            </button>
            <button
                type="button"
                class="pane-btn close"
                title="Close pane"
                aria-label="Close pane"
                disabled={!canClose}
                on:click={() => actions.close(path)}
                data-testid="close-pane"
            >
                <svg
                    viewBox="0 0 16 16"
                    width="13"
                    height="13"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                >
                    <line x1="4" y1="4" x2="12" y2="12" />
                    <line x1="12" y1="4" x2="4" y2="12" />
                </svg>
            </button>
        </div>
    </header>

    <div class="pane-body">
        <svelte:component this={def.component} />
    </div>
</section>

<style lang="scss">
    .pane {
        display: flex;
        flex-direction: column;
        flex: 1;
        min-width: 0;
        min-height: 0;
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
        overflow: hidden;
    }

    .pane-head {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
        flex: 0 0 auto;
        height: 36px;
        padding: 0 var(--space-xs) 0 var(--space-sm);
        background: var(--canvas);
        border-bottom: 1px solid var(--border-subtle);
    }

    .glyph {
        color: var(--fg-faint);
        font-size: 13px;
        line-height: 1;
    }

    .switcher {
        font: inherit;
        font-size: var(--type-caption-size);
        font-weight: 600;
        color: var(--fg);
        background: transparent;
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-xs);
        max-width: 12rem;
        cursor: pointer;
        appearance: none;
        -webkit-appearance: none;

        &:hover {
            background: var(--canvas-elevated);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }
    }

    .pane-actions {
        display: flex;
        align-items: center;
        gap: 2px;
        margin-left: auto;
    }

    .pane-btn {
        display: grid;
        place-items: center;
        width: 26px;
        height: 26px;
        color: var(--fg-subtle);
        background: transparent;
        border: 0;
        border-radius: var(--border-radius);
        cursor: pointer;
        transition:
            color var(--motion-fast) ease,
            background var(--motion-fast) ease;

        &:hover:not([disabled]) {
            background: var(--canvas-elevated);
            color: var(--fg);
        }

        &.close:hover:not([disabled]) {
            color: var(--fg-error);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }

        &[disabled] {
            opacity: 0.35;
            cursor: default;
        }
    }

    .pane-body {
        flex: 1;
        min-height: 0;
        overflow: auto;
    }

    @media (prefers-reduced-motion: reduce) {
        .pane-btn {
            transition: none;
        }
    }
</style>
