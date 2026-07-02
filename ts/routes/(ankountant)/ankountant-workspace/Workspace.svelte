<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Root of the Ankountant study workspace: owns the BSP layout tree, exposes the
edit actions to descendant panes via context, persists to localStorage, and
renders a slim toolbar over the recursive tile grid. Capped at MAX_PANES (4).
"← Home" returns to the Ankountant shell home (client-side; the shell top bar is
suppressed on this route so the workspace owns its own chrome).
-->
<script lang="ts">
    import { onMount, setContext } from "svelte";

    import { goto } from "$app/navigation";

    import type { WorkspaceActions } from "./context";
    import { WORKSPACE_ACTIONS } from "./context";
    import type { SurfaceKind, TileNode } from "./layout";
    import {
        addPane,
        closeAt,
        countLeaves,
        defaultLayout,
        deserialize,
        ensureSurface,
        MAX_PANES,
        serialize,
        setRatioAt,
        setSurfaceAt,
        splitAt,
        SURFACE_KINDS,
    } from "./layout";
    import { SURFACES } from "./surfaces";
    import TileView from "./TileView.svelte";

    export let initialSurface: SurfaceKind | undefined = undefined;

    const STORAGE_KEY = "ankountant.workspace.layout.v1";

    let tree: TileNode = defaultLayout(initialSurface ?? "dashboard");
    let mounted = false;
    let addKind: SurfaceKind = "confusion";

    $: leaves = countLeaves(tree);
    $: canSplit = leaves < MAX_PANES;
    $: canClose = leaves > 1;

    const actions: WorkspaceActions = {
        split: (path, dir, surface, side) => {
            tree = splitAt(tree, path, dir, surface, side);
        },
        close: (path) => {
            tree = closeAt(tree, path);
        },
        setSurface: (path, surface) => {
            tree = setSurfaceAt(tree, path, surface);
        },
        setRatio: (path, ratio) => {
            tree = setRatioAt(tree, path, ratio);
        },
    };
    setContext<WorkspaceActions>(WORKSPACE_ACTIONS, actions);

    function addSurface(): void {
        tree = addPane(tree, addKind);
    }

    function resetLayout(): void {
        tree = defaultLayout("dashboard");
    }

    function goHome(): void {
        goto("/ankountant-home"); // client-side, back to the shell home
    }

    // Persist on every layout change once we've loaded the saved one.
    $: if (mounted) {
        try {
            localStorage.setItem(STORAGE_KEY, serialize(tree));
        } catch {
            /* private mode / quota — layout just won't persist */
        }
    }

    onMount(() => {
        const restored = deserialize(localStorage.getItem(STORAGE_KEY));
        if (restored) {
            tree = initialSurface ? ensureSurface(restored, initialSurface) : restored;
        } else if (initialSurface) {
            tree = defaultLayout(initialSurface);
        }
        mounted = true;

        // Lets Qt add/focus a surface in the already-open workspace, mirroring
        // the shell's __ankGoto hook (see qt/aqt/workspace.py).
        type Api = { open: (kind: SurfaceKind) => void; reset: () => void };
        const w = window as unknown as { __ankWorkspace?: Api };
        w.__ankWorkspace = {
            open: (kind) => {
                tree = ensureSurface(tree, kind);
            },
            reset: resetLayout,
        };
        return () => {
            delete (window as unknown as { __ankWorkspace?: Api }).__ankWorkspace;
        };
    });
</script>

<div class="workspace" data-testid="ankountant-workspace">
    <header class="ws-toolbar">
        <button
            type="button"
            class="ws-exit"
            on:click={goHome}
            aria-label="Back to Ankountant home"
        >
            ← Home
        </button>
        <span class="ws-title">Study Workspace</span>

        <div class="ws-tools">
            <div class="ws-add">
                <select bind:value={addKind} aria-label="Surface to add">
                    {#each SURFACE_KINDS as kind (kind)}
                        <option value={kind}>{SURFACES[kind].label}</option>
                    {/each}
                </select>
                <button
                    type="button"
                    class="ws-add-btn"
                    disabled={!canSplit}
                    on:click={addSurface}
                    data-testid="add-pane"
                >
                    + Add pane
                </button>
            </div>
            <button
                type="button"
                class="ws-reset"
                on:click={resetLayout}
                title="Reset layout"
            >
                Reset
            </button>
            <span class="ws-count" class:full={!canSplit} title="Open panes">
                {leaves}/{MAX_PANES}
            </span>
        </div>
    </header>

    <div class="ws-grid">
        <TileView node={tree} path={[]} {canSplit} {canClose} />
    </div>
</div>

<style lang="scss">
    .workspace {
        display: flex;
        flex-direction: column;
        height: 100vh;
        background: var(--canvas);
        color: var(--fg);
    }

    .ws-toolbar {
        display: flex;
        align-items: center;
        gap: var(--space-md);
        flex: 0 0 auto;
        height: 48px;
        padding: 0 var(--space-md);
        background: var(--canvas-elevated);
        border-bottom: 1px solid var(--border-subtle);
    }

    .ws-title {
        font-size: var(--type-caption-size);
        font-weight: 600;
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .ws-tools {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        margin-left: auto;
    }

    .ws-add {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
    }

    .ws-add select {
        font: inherit;
        font-size: var(--type-caption-size);
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-sm);
        cursor: pointer;

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }
    }

    // Buttons are scoped to override the global <button> base cleanly.
    .ws-exit,
    .ws-reset,
    .ws-add-btn {
        font: inherit;
        font-size: var(--type-caption-size);
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-md);
        cursor: pointer;
        transition:
            border-color var(--motion-fast) ease,
            background var(--motion-fast) ease;

        &:hover:not([disabled]) {
            border-color: var(--accent);
            color: var(--accent);
        }

        &:active:not([disabled]) {
            transform: translateY(1px);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }
    }

    // Only the add-pane button is ever disabled (at the pane cap).
    .ws-add-btn {
        color: var(--accent);

        &[disabled] {
            opacity: 0.4;
            cursor: default;
        }
    }

    .ws-count {
        font-size: var(--type-caption-size);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        color: var(--fg-subtle);
        padding: var(--space-xxs) var(--space-sm);
        border-radius: var(--border-radius);
        background: var(--canvas-inset);

        &.full {
            color: var(--fg-error);
        }
    }

    .ws-grid {
        flex: 1;
        min-height: 0;
        display: flex;
        padding: var(--space-sm);
    }

    @media (prefers-reduced-motion: reduce) {
        .ws-exit,
        .ws-reset,
        .ws-add-btn {
            transition: none;
        }
    }
</style>
