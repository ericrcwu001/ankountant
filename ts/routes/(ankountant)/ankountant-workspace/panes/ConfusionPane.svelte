<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around confusion-set review. Mirrors the data load of
ankountant-confusion/+page.ts.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import type { ConfusionItem } from "@generated/anki/scheduler_pb";
    import { buildConfusionQueue } from "@generated/backend";

    import ConfusionMode from "../../ankountant-confusion/ConfusionMode.svelte";
    import { errorMessage } from "./configJson";
    import PaneState from "./PaneState.svelte";

    const SECTION = "ALL";

    let phase: "loading" | "ready" | "empty" | "error" = "loading";
    let items: ConfusionItem[] = [];
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            const resp = await buildConfusionQueue({ section: SECTION, maxItems: 60 });
            items = resp.items;
            phase = items.length > 0 ? "ready" : "empty";
        } catch (err) {
            message = errorMessage(err);
            phase = "error";
        }
    }

    onMount(() => {
        void load();
    });
</script>

{#if phase === "ready"}
    <ConfusionMode {items} />
{:else}
    <PaneState
        {phase}
        {message}
        onRetry={load}
        emptyText="No confusion items yet. Load or import CPA practice to build the drill queue."
    />
{/if}
