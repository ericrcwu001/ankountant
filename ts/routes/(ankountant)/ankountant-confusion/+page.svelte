<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TaskErrorState from "../TaskErrorState.svelte";
    import ConfusionMode from "./ConfusionMode.svelte";

    export let data: PageData;
</script>

{#if data.loadError}
    <TaskErrorState
        testId="confusion-load-error"
        eyebrow="Confusion drill"
        title="Could not load confusion drill"
        message={data.loadError}
    />
{:else}
    <ConfusionMode items={data.items} section={data.section} />
{/if}
