<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the TBS task surface. Mirrors the data load of
ankountant-tbs/TbsTab.svelte for the JE/numeric task types this pane can render.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import type { TbsModel, TbsShape } from "../../ankountant-tbs/lib";
    import {
        buildTbsModel,
        SECTION_SEARCH_ORDER,
        tbsSearch,
    } from "../../ankountant-tbs/lib";
    import { errorMessage } from "./configJson";
    import TbsSurface from "../../ankountant-tbs/TbsSurface.svelte";
    import PaneState from "./PaneState.svelte";

    const WORKSPACE_TBS_SHAPES: readonly TbsShape[] = ["journal_entry", "numeric"];

    let phase: "loading" | "ready" | "empty" | "error" = "loading";
    let noteId = 0n;
    let model: TbsModel | null = null;
    let fields: string[] = [];
    let tags: string[] = [];
    let message = "";

    async function load(): Promise<void> {
        phase = "loading";
        try {
            noteId = await firstWorkspaceTbsNote();
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

    async function firstWorkspaceTbsNote(): Promise<bigint> {
        for (const shape of WORKSPACE_TBS_SHAPES) {
            for (const section of SECTION_SEARCH_ORDER) {
                const found = await searchNotes({ search: tbsSearch(shape, section) });
                if (found.ids.length > 0) {
                    return found.ids[0];
                }
            }
        }
        return 0n;
    }
</script>

{#if phase === "ready" && model}
    {#key noteId}
        <TbsSurface {noteId} {model} {fields} {tags} />
    {/key}
{:else if phase !== "ready"}
    <PaneState
        {phase}
        {message}
        onRetry={load}
        emptyTitle="No simulation task found"
        emptyText="This profile has no sealed journal-entry or numeric simulations for the workspace queue yet."
        emptyActionHref="/ankountant-tbs"
        emptyActionLabel="Browse simulations"
        emptySecondaryHref="/ankountant-dashboard"
        emptySecondaryLabel="Readiness evidence"
    />
{/if}
