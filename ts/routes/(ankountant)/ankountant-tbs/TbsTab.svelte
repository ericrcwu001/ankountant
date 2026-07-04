<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The unified TBS tab. All four TBS shapes (journal-entry, numeric, research,
doc-review) live here behind a single chooser: the learner clicks a type and the
first sealed task of that shape is loaded into the matching surface. A
concrete task can still be deep-linked via ?note=<id> (the e2e does this), in
which case the chooser opens on that note's shape.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import DocReviewSurface from "../ankountant-doc-review/DocReviewSurface.svelte";
    import ResearchSurface from "../ankountant-research/ResearchSurface.svelte";
    import type { TbsModel, TbsShape } from "./lib";
    import {
        buildTbsModel,
        SECTIONS,
        TBS_SHAPES,
        tbsSearch,
        tbsShapeSearchOrder,
    } from "./lib";
    import TbsSurface from "./TbsSurface.svelte";

    export let initialNoteId: bigint = 0n;
    export let initialModel: TbsModel | null = null;
    export let initialFields: string[] = [];
    export let initialTags: string[] = [];

    const SECTION_SEARCH_ORDER = [
        "FAR",
        ...SECTIONS.filter((section) => section !== "FAR"),
    ];
    const deepLinked = initialNoteId !== 0n && initialModel !== null;

    type Phase = "loading" | "ready" | "empty" | "error";

    let selected: TbsShape = initialModel?.shape ?? "journal_entry";
    let phase: Phase = deepLinked ? "ready" : "loading";
    let noteId = initialNoteId;
    let model: TbsModel | null = initialModel;
    let fields: string[] = initialFields;
    let tags: string[] = initialTags;
    let message = "";
    // Guards against out-of-order responses when the learner clicks quickly.
    let loadSeq = 0;

    $: selectedLabel = TBS_SHAPES.find((s) => s.shape === selected)?.label ?? "TBS";
    $: selectedBlurb = TBS_SHAPES.find((s) => s.shape === selected)?.blurb ?? "";

    interface LoadedShape {
        noteId: bigint;
        model: TbsModel;
        fields: string[];
        tags: string[];
    }

    async function fetchShape(shape: TbsShape): Promise<LoadedShape | null> {
        for (const section of SECTION_SEARCH_ORDER) {
            const found = await searchNotes({ search: tbsSearch(shape, section) });
            const foundNoteId = found.ids.length > 0 ? found.ids[0] : 0n;
            if (foundNoteId !== 0n) {
                const note = await getNote({ nid: foundNoteId });
                return {
                    noteId: foundNoteId,
                    model: buildTbsModel(note.fields, note.tags),
                    fields: note.fields,
                    tags: note.tags,
                };
            }
        }
        return null;
    }

    function applyLoadedShape(shape: TbsShape, loaded: LoadedShape): void {
        selected = shape;
        noteId = loaded.noteId;
        model = loaded.model;
        fields = loaded.fields;
        tags = loaded.tags;
        phase = "ready";
    }

    function clearLoadedShape(): void {
        noteId = 0n;
        model = null;
        fields = [];
        tags = [];
    }

    async function loadShape(shape: TbsShape): Promise<void> {
        selected = shape;
        const seq = ++loadSeq;
        phase = "loading";
        clearLoadedShape();
        message = "";
        try {
            const loaded = await fetchShape(shape);
            if (seq !== loadSeq) {
                return;
            }
            if (!loaded) {
                phase = "empty";
                return;
            }
            applyLoadedShape(shape, loaded);
        } catch (err) {
            if (seq !== loadSeq) {
                return;
            }
            message = err instanceof Error ? err.message : String(err);
            phase = "error";
        }
    }

    async function loadInitialShape(): Promise<void> {
        const requestedShape = selected;
        const seq = ++loadSeq;
        phase = "loading";
        clearLoadedShape();
        message = "";
        try {
            for (const shape of tbsShapeSearchOrder(requestedShape)) {
                const loaded = await fetchShape(shape);
                if (seq !== loadSeq) {
                    return;
                }
                if (loaded) {
                    applyLoadedShape(shape, loaded);
                    return;
                }
            }
            selected = requestedShape;
            phase = "empty";
        } catch (err) {
            if (seq !== loadSeq) {
                return;
            }
            selected = requestedShape;
            message = err instanceof Error ? err.message : String(err);
            phase = "error";
        }
    }

    function choose(shape: TbsShape): void {
        if (shape === selected && phase === "ready") {
            return;
        }
        void loadShape(shape);
    }

    onMount(() => {
        if (!deepLinked) {
            void loadInitialShape();
        }
    });
</script>

<div class="tbs-tab" data-testid="tbs-tab">
    <nav class="tbs-chooser" aria-label="Simulation type" data-testid="tbs-chooser">
        {#each TBS_SHAPES as s (s.shape)}
            <button
                type="button"
                class="chooser-btn"
                class:active={selected === s.shape}
                aria-pressed={selected === s.shape}
                data-testid="tbs-choose-{s.shape}"
                on:click={() => choose(s.shape)}
            >
                <span class="glyph" aria-hidden="true">{s.glyph}</span>
                <span class="chooser-label">{s.label}</span>
            </button>
        {/each}
    </nav>
    <p class="tbs-chooser-blurb" data-testid="tbs-chooser-blurb">{selectedBlurb}</p>

    <div class="tbs-tab-body">
        {#if phase === "ready" && model}
            {@const m = model}
            {#key noteId}
                {#if m.shape === "research"}
                    <ResearchSurface {noteId} model={m} {fields} {tags} />
                {:else if m.shape === "doc_review"}
                    <DocReviewSurface {noteId} model={m} {fields} {tags} />
                {:else}
                    <TbsSurface {noteId} model={m} />
                {/if}
            {/key}
        {:else if phase === "loading"}
            <p class="tbs-state" data-testid="tbs-loading">Loading…</p>
        {:else if phase === "empty"}
            <p class="tbs-state" data-testid="tbs-empty">
                No {selectedLabel} simulation was found in this profile.
            </p>
        {:else}
            <div class="tbs-state" data-testid="tbs-error">
                <p>Couldn't load this simulation.</p>
                {#if message}
                    <p class="err-msg">{message}</p>
                {/if}
                <button
                    type="button"
                    class="retry"
                    on:click={() => loadShape(selected)}
                >
                    Retry
                </button>
            </div>
        {/if}
    </div>
</div>

<style lang="scss">
    .tbs-tab {
        display: flex;
        flex-direction: column;
        min-height: 0;
    }

    // Segmented chooser: a row of type tiles, mirroring the workspace pane
    // switcher (glyph + label). Active tile = brand navy tint (chrome-only).
    .tbs-chooser {
        display: flex;
        flex-wrap: wrap;
        gap: var(--space-sm);
        max-width: 62rem;
        margin: 0 auto;
        width: 100%;
        box-sizing: border-box;
        padding: var(--space-lg) var(--space-lg) 0;
    }

    .chooser-btn {
        display: inline-flex;
        align-items: center;
        gap: var(--space-sm);
        font: inherit;
        font-weight: 500;
        color: var(--fg-subtle);
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
        padding: var(--space-sm) var(--space-md);
        cursor: pointer;

        &:hover {
            border-color: var(--border);
            color: var(--fg);
        }

        &.active {
            color: var(--accent);
            background: var(--accent-tint);
            border-color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .glyph {
        font-size: 15px;
        line-height: 1;
    }

    .tbs-chooser-blurb {
        max-width: 62rem;
        margin: var(--space-sm) auto 0;
        width: 100%;
        box-sizing: border-box;
        padding: 0 var(--space-lg);
        color: var(--fg-subtle);
        font-size: 13px;
    }

    .tbs-tab-body {
        flex: 1;
        min-height: 0;
    }

    .tbs-state {
        max-width: 62rem;
        margin: 0 auto;
        padding: var(--space-xl) var(--space-lg);
        color: var(--fg-subtle);
    }

    .err-msg {
        font-family: var(--font-mono);
        font-size: 13px;
        color: var(--fg-error);
    }

    .retry {
        font: inherit;
        font-weight: 500;
        color: var(--fg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-md);
        cursor: pointer;
        margin-top: var(--space-sm);

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }
</style>
