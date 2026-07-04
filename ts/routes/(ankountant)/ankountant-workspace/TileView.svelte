<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Recursively renders the tiling tree: a leaf becomes a Pane; a split becomes two
child TileViews (self-import — the Svelte 5 replacement for svelte:self) sized by
`ratio` with a Resizer between them. `canSplit`/`canClose` are global flags
threaded down so every pane's header enables/disables consistently.
-->
<script lang="ts">
    import type { Path, TileNode } from "./workspace-layout";
    import Pane from "./Pane.svelte";
    import Resizer from "./Resizer.svelte";
    import TileView from "./TileView.svelte";

    export let node: TileNode;
    export let path: Path;
    export let canSplit: boolean;
    export let canClose: boolean;
</script>

{#if node.type === "leaf"}
    <Pane {node} {path} {canSplit} {canClose} />
{:else}
    <div class="tile-split {node.dir}">
        <div class="tile-child" style="flex-grow:{node.ratio}">
            <TileView node={node.a} path={[...path, "a"]} {canSplit} {canClose} />
        </div>
        <Resizer dir={node.dir} {path} ratio={node.ratio} />
        <div class="tile-child" style="flex-grow:{1 - node.ratio}">
            <TileView node={node.b} path={[...path, "b"]} {canSplit} {canClose} />
        </div>
    </div>
{/if}

<style lang="scss">
    .tile-split {
        display: flex;
        width: 100%;
        height: 100%;
        min-width: 0;
        min-height: 0;
    }

    .tile-split.row {
        flex-direction: row;
    }

    .tile-split.col {
        flex-direction: column;
    }

    .tile-child {
        display: flex;
        flex-basis: 0;
        min-width: 0;
        min-height: 0;
        overflow: hidden;
    }
</style>
