<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the document-review surface. Filters by
tbs_type=doc_review and section, preferring FAR and then falling back across
supported sections, so it loads a doc-review item, not the first TBS note.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import DocReviewSurface from "../../ankountant-doc-review/DocReviewSurface.svelte";
    import type { TbsModel } from "../../ankountant-tbs/lib";
    import {
        buildTbsModel,
        SECTION_SEARCH_ORDER,
        tbsSearch,
    } from "../../ankountant-tbs/lib";
    import { errorMessage } from "./configJson";
    import PaneState from "./PaneState.svelte";

    let phase: "loading" | "ready" | "empty" | "error" = "loading";
    let noteId = 0n;
    let model: TbsModel | null = null;
    let fields: string[] = [];
    let tags: string[] = [];
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            noteId = await firstDocReviewNote();
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
            message = errorMessage(err);
            phase = "error";
        }
    }

    onMount(() => {
        void load();
    });

    async function firstDocReviewNote(): Promise<bigint> {
        for (const section of SECTION_SEARCH_ORDER) {
            const found = await searchNotes({
                search: tbsSearch("doc_review", section),
            });
            if (found.ids.length > 0) {
                return found.ids[0];
            }
        }
        return 0n;
    }
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
        emptyText="No document-review task was found in this profile."
    />
{/if}
