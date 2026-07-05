<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";

    import type { PageData } from "./$types";
    import TaskErrorState from "../TaskErrorState.svelte";
    import Dashboard from "./Dashboard.svelte";

    export let data: PageData;

    function selectSection(section: string): void {
        goto(`/ankountant-dashboard?section=${section}`);
    }
</script>

{#if data.loadError}
    <TaskErrorState
        testId="dashboard-load-error"
        eyebrow="Readiness"
        title="Could not load readiness evidence"
        message={data.loadError}
        secondaryHref="/ankountant-home"
        secondaryLabel="Study home"
        tertiaryHref="/ankountant-tbs"
        tertiaryLabel="Browse simulations"
    />
{:else if data.readiness}
    <Dashboard
        readiness={data.readiness}
        examDate={data.examDate}
        section={data.section}
        onSelectSection={selectSection}
    />
{:else}
    <TaskErrorState
        testId="dashboard-load-error"
        eyebrow="Readiness"
        title="Could not load readiness evidence"
        message="Readiness evidence could not be loaded."
        secondaryHref="/ankountant-home"
        secondaryLabel="Study home"
        tertiaryHref="/ankountant-tbs"
        tertiaryLabel="Browse simulations"
    />
{/if}
