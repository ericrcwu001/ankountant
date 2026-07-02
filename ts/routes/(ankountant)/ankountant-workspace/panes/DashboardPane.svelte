<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the Readiness dashboard. Mirrors the data load of
ankountant-dashboard/+page.ts so the surface can be mounted in any tile without
a route loader.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";
    import { getConfigJson, getReadiness } from "@generated/backend";

    import Dashboard from "../../ankountant-dashboard/Dashboard.svelte";
    import PaneState from "./PaneState.svelte";

    const SECTION = "FAR";

    let phase: "loading" | "ready" | "error" = "loading";
    let readiness: GetReadinessResponse;
    let examDate = "";
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            readiness = await getReadiness({ section: SECTION });
            // Exam date is optional col config; NotFound is the normal state.
            try {
                const raw = await getConfigJson(
                    { val: `ankountant.${SECTION}.exam.date` },
                    { alertOnError: false },
                );
                const parsed = JSON.parse(new TextDecoder().decode(raw.json));
                examDate = typeof parsed === "string" ? parsed : "";
            } catch {
                examDate = "";
            }
            phase = "ready";
        } catch (err) {
            message = err instanceof Error ? err.message : String(err);
            phase = "error";
        }
    }

    onMount(() => {
        void load();
    });
</script>

{#if phase === "ready"}
    <Dashboard {readiness} {examDate} />
{:else}
    <PaneState {phase} {message} onRetry={load} />
{/if}
