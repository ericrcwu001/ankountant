<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TaskErrorState from "../TaskErrorState.svelte";
    import Home from "./Home.svelte";

    export let data: PageData;
</script>

{#if data.loadError}
    <TaskErrorState
        testId="home-load-error"
        eyebrow="Home"
        title="Could not load study home"
        message={data.loadError}
    />
{:else}
    <Home
        readiness={data.readiness}
        section={data.section}
        examDate={data.examDate}
        sections={data.sections}
    />
{/if}
