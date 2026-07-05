<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TaskErrorState from "../TaskErrorState.svelte";
    import TbsTab from "./TbsTab.svelte";

    export let data: PageData;
</script>

{#if data.loadError}
    <TaskErrorState
        testId="tbs-load-error"
        eyebrow="Task-based simulation"
        title="Could not load simulation"
        message={data.loadError}
    />
{:else}
    <TbsTab
        initialNoteId={data.noteId}
        initialModel={data.model}
        initialFields={data.fields}
        initialTags={data.tags}
    />
{/if}
