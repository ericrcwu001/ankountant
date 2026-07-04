<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TaskEmptyState from "../TaskEmptyState.svelte";
    import DocReviewSurface from "./DocReviewSurface.svelte";

    export let data: PageData;
</script>

{#if data.model}
    {#key data.noteId}
        <DocReviewSurface
            noteId={data.noteId}
            model={data.model}
            fields={data.fields}
            tags={data.tags}
        />
    {/key}
{:else}
    <TaskEmptyState
        testId="docreview-empty"
        eyebrow="Document review"
        title="No document-review task found"
        description="This profile does not have a sealed document-review simulation for the selected section yet."
    />
{/if}
