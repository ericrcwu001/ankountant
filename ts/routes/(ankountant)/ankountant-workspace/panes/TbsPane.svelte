<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the TBS task surface. Mirrors the data load of
ankountant-tbs/+page.ts: find the first sealed TBS note in the section (there is
no deep-link inside the workspace) and build its render model.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import type { TbsModel } from "../../ankountant-tbs/lib";
    import { buildTbsModel } from "../../ankountant-tbs/lib";
    import TbsSurface from "../../ankountant-tbs/TbsSurface.svelte";
    import PaneState from "./PaneState.svelte";

    const SECTION = "FAR";
    // Mirrors rslib TBS_NOTETYPE + the sealed-bank deck layout (confusion.rs).
    const FIRST_TBS_SEARCH = `"note:Ankountant TBS" deck:Ankountant::Sealed::${SECTION}::*`;

    let phase: "loading" | "ready" | "empty" | "error" = "loading";
    let noteId = 0n;
    let model: TbsModel | null = null;
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            const found = await searchNotes({ search: FIRST_TBS_SEARCH });
            noteId = found.ids.length > 0 ? found.ids[0] : 0n;
            if (noteId === 0n) {
                phase = "empty";
                return;
            }
            const note = await getNote({ nid: noteId });
            model = buildTbsModel(note.fields, note.tags);
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

{#if phase === "ready" && model}
    <TbsSurface {noteId} {model} />
{:else if phase !== "ready"}
    <PaneState
        {phase}
        {message}
        onRetry={load}
        emptyText="No TBS task available yet. Load the FAR demo content from the Ankountant menu."
    />
{/if}
