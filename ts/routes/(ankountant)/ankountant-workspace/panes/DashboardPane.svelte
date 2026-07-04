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
    import { decodeConfigJson, errorMessage, isMissingConfigJson } from "./configJson";
    import PaneState from "./PaneState.svelte";

    let phase: "loading" | "ready" | "error" = "loading";
    let section = "FAR";
    let readiness: GetReadinessResponse;
    let examDate = "";
    let message = "";

    async function load(nextSection = section): Promise<void> {
        section = nextSection;
        phase = "loading";
        message = "";
        try {
            readiness = await getReadiness({ section: nextSection });
            try {
                const key = `ankountant.${nextSection}.exam.date`;
                const raw = await getConfigJson({ val: key }, { alertOnError: false });
                const parsed = decodeConfigJson<unknown>(key, raw.json);
                if (typeof parsed !== "string") {
                    throw new Error(`Saved preference "${key}" must be a string.`);
                }
                examDate = parsed;
            } catch (error) {
                if (isMissingConfigJson(error, `ankountant.${nextSection}.exam.date`)) {
                    examDate = "";
                } else {
                    throw error;
                }
            }
            phase = "ready";
        } catch (error) {
            message = errorMessage(error);
            phase = "error";
        }
    }

    function retry(): void {
        void load();
    }

    function selectSection(nextSection: string): void {
        void load(nextSection);
    }

    onMount(() => {
        void load();
    });
</script>

{#if phase === "ready"}
    <Dashboard {readiness} {examDate} {section} onSelectSection={selectSection} />
{:else}
    <PaneState {phase} {message} onRetry={retry} />
{/if}
