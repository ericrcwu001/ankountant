<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the document-review surface. Filters by
tbs_type=doc_review and section (default FAR) so it loads a doc-review item, not
the first TBS note.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import DocReviewSurface from "../../ankountant-doc-review/DocReviewSurface.svelte";
    import type { TbsModel } from "../../ankountant-tbs/lib";
    import { buildTbsModel } from "../../ankountant-tbs/lib";
    import PaneState from "./PaneState.svelte";

    const SECTION = "FAR";
    const SEARCH = `"note:Ankountant TBS" "tbs_type:doc_review" deck:Ankountant::Sealed::${SECTION}::*`;

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
    {#key noteId}
        <DocReviewSurface {noteId} {model} {fields} {tags} />
    {/key}
{:else if phase !== "ready"}
    <PaneState
        {phase}
        {message}
        onRetry={load}
        emptyText="No document-review task available yet. Load the FAR demo content from the Ankountant menu."
    />
{/if}
