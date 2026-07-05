<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TaskErrorState from "../TaskErrorState.svelte";
    import TaskEmptyState from "../TaskEmptyState.svelte";
    import ResearchSurface from "./ResearchSurface.svelte";

    export let data: PageData;
</script>

{#if data.loadError}
    <TaskErrorState
        testId="research-load-error"
        eyebrow="Research practice"
        title="Could not load research task"
        message={data.loadError}
    />
{:else if data.model}
    {#key data.noteId}
        <ResearchSurface
            noteId={data.noteId}
            model={data.model}
            fields={data.fields}
            tags={data.tags}
        />
    {/key}
{:else}
    <TaskEmptyState
        testId="research-empty"
        eyebrow="Research practice"
        title="No research task found"
        description="This profile does not have a sealed research simulation for the selected section yet."
    />
{/if}
