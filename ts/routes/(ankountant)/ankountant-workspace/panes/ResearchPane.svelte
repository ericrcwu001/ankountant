<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the research surface. Unlike TbsPane (which grabs
the first TBS note regardless of shape), this filters by BOTH tbs_type=research
and section (ADR 0008), defaulting to FAR, so it never collides with a JE/numeric
or a different section's item.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import ResearchSurface from "../../ankountant-research/ResearchSurface.svelte";
    import type { TbsModel } from "../../ankountant-tbs/lib";
    import { buildTbsModel } from "../../ankountant-tbs/lib";
    import PaneState from "./PaneState.svelte";

    const SECTION = "FAR";
    const SEARCH = `"note:Ankountant TBS" "tbs_type:research" deck:Ankountant::Sealed::${SECTION}::*`;

    let phase: "loading" | "ready" | "empty" | "error" = "loading";
    let noteId = 0n;
    let model: TbsModel | null = null;
    let fields: string[] = [];
    let tags: string[] = [];
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            const found = await searchNotes({ search: SEARCH });
            noteId = found.ids.length > 0 ? found.ids[0] : 0n;
            if (noteId === 0n) {
                phase = "empty";
                return;
            }
            const note = await getNote({ nid: noteId });
            model = buildTbsModel(note.fields, note.tags);
            fields = note.fields;
            tags = note.tags;
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
    <ResearchSurface {noteId} {model} {fields} {tags} />
{:else if phase !== "ready"}
    <PaneState
        {phase}
        {message}
        onRetry={load}
        emptyText="No research task available yet. Load the FAR demo content from the Ankountant menu."
    />
{/if}
