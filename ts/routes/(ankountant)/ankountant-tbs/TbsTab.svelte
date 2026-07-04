<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The unified TBS tab. All four TBS shapes (journal-entry, numeric, research,
doc-review) live here behind shape and section choosers. A concrete task can
still be deep-linked via ?note=<id> (the e2e does this), in which case the
chooser opens on that note's shape and section.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { getNote, searchNotes } from "@generated/backend";

    import DocReviewSurface from "../ankountant-doc-review/DocReviewSurface.svelte";
    import ResearchSurface from "../ankountant-research/ResearchSurface.svelte";
    import type { SectionChoice, TbsModel, TbsShape } from "./lib";
    import {
        ALL_SECTIONS,
        buildTbsModel,
        sectionChoiceFromModel,
        sectionChoiceLabel,
        sectionChoiceSearchOrder,
        TBS_SHAPES,
        TBS_SECTION_CHOICES,
        readableTbsLoadError,
        tbsSearch,
        tbsShapeSearchOrder,
    } from "./lib";
    import TbsSurface from "./TbsSurface.svelte";

    export let initialNoteId: bigint = 0n;
    export let initialModel: TbsModel | null = null;
    export let initialFields: string[] = [];
    export let initialTags: string[] = [];

    const deepLinked = initialNoteId !== 0n && initialModel !== null;

    type Phase = "loading" | "ready" | "empty" | "error";

    let selected: TbsShape = initialModel?.shape ?? "journal_entry";
    let selectedSection: SectionChoice = sectionChoiceFromModel(initialModel?.section);
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
    $: selectedSectionLabel = sectionChoiceLabel(selectedSection);
    $: emptySectionLabel =
        selectedSection === ALL_SECTIONS ? "all sections" : selectedSectionLabel;
    $: readinessHref =
        selectedSection === ALL_SECTIONS
            ? "/ankountant-dashboard"
            : `/ankountant-dashboard?section=${selectedSection}`;

    interface LoadedShape {
        noteId: bigint;
        model: TbsModel;
        fields: string[];
        tags: string[];
    }

    async function fetchShape(
        shape: TbsShape,
        sectionChoice: SectionChoice,
    ): Promise<LoadedShape | null> {
        for (const section of sectionChoiceSearchOrder(sectionChoice)) {
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

    async function loadShape(
        shape: TbsShape,
        sectionChoice: SectionChoice = selectedSection,
    ): Promise<void> {
        selected = shape;
        selectedSection = sectionChoice;
        const seq = ++loadSeq;
        phase = "loading";
        clearLoadedShape();
        message = "";
        try {
            const loaded = await fetchShape(shape, sectionChoice);
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
            message = readableTbsLoadError(err);
            phase = "error";
        }
    }

    async function loadInitialShape(): Promise<void> {
        const requestedShape = selected;
        const requestedSection = selectedSection;
        const seq = ++loadSeq;
        phase = "loading";
        clearLoadedShape();
        message = "";
        try {
            for (const shape of tbsShapeSearchOrder(requestedShape)) {
                const loaded = await fetchShape(shape, requestedSection);
                if (seq !== loadSeq) {
                    return;
                }
                if (loaded) {
                    applyLoadedShape(shape, loaded);
                    return;
                }
            }
            selected = requestedShape;
            selectedSection = requestedSection;
            phase = "empty";
        } catch (err) {
            if (seq !== loadSeq) {
                return;
            }
            selected = requestedShape;
            selectedSection = requestedSection;
            message = readableTbsLoadError(err);
            phase = "error";
        }
    }

    function choose(shape: TbsShape): void {
        if (shape === selected && phase === "ready") {
            return;
        }
        void loadShape(shape);
    }

    function chooseSection(sectionChoice: SectionChoice): void {
        if (sectionChoice === selectedSection && phase === "ready") {
            return;
        }
        void loadShape(selected, sectionChoice);
    }

    onMount(() => {
        if (!deepLinked) {
            void loadInitialShape();
        }
    });
</script>

<div class="tbs-tab" data-testid="tbs-tab">
    <nav
        class="section-chooser"
        aria-label="CPA section"
        data-testid="tbs-section-chooser"
    >
        {#each TBS_SECTION_CHOICES as choice (choice)}
            <button
                type="button"
                class="section-btn"
                class:active={selectedSection === choice}
                aria-pressed={selectedSection === choice}
                data-testid="tbs-section-{choice.toLowerCase()}"
                on:click={() => chooseSection(choice)}
            >
                {sectionChoiceLabel(choice)}
            </button>
        {/each}
    </nav>

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
                    <TbsSurface {noteId} model={m} {fields} {tags} />
                {/if}
            {/key}
        {:else if phase === "loading"}
            <p class="tbs-state" data-testid="tbs-loading">Loading…</p>
        {:else if phase === "empty"}
            <div class="tbs-state empty-state" data-testid="tbs-empty">
                <div class="state-mark" aria-hidden="true">0</div>
                <p class="state-title">No {selectedLabel} simulation found</p>
                <p class="state-detail">
                    No {selectedLabel} simulation was found for {emptySectionLabel} in this
                    profile. Switch the section or simulation type above, or use readiness
                    evidence to choose the next practice target.
                </p>
                <a class="state-link" href={readinessHref}>Readiness evidence</a>
            </div>
        {:else}
            <div class="tbs-state error-state" data-testid="tbs-error">
                <p class="state-title">Couldn't load this simulation.</p>
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
        height: 100%;
        min-height: 0;
        overflow: hidden;
    }

    .section-chooser,
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

    .section-chooser {
        gap: var(--space-xs);
        padding-top: var(--space-lg);
    }

    .tbs-chooser {
        padding-top: var(--space-sm);
    }

    .chooser-btn,
    .section-btn {
        display: inline-flex;
        align-items: center;
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

    .chooser-btn {
        gap: var(--space-sm);
    }

    .section-btn {
        min-height: 32px;
        padding: var(--space-2xs) var(--space-sm);
        font-size: 12px;
        box-shadow: none;
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
        overflow: auto;
    }

    .tbs-state {
        max-width: 62rem;
        margin: 0 auto;
        padding: var(--space-xl) var(--space-lg);
        color: var(--fg-subtle);
    }

    .error-state {
        color: var(--fg);
    }

    .empty-state {
        display: grid;
        justify-items: start;
        gap: var(--space-sm);
        color: var(--fg);
    }

    .state-mark {
        display: grid;
        place-items: center;
        width: 42px;
        height: 42px;
        border: 1px solid var(--border-subtle);
        border-radius: 50%;
        background: var(--canvas-elevated);
        color: var(--fg-faint);
        font-size: 21px;
        font-weight: 750;
        line-height: 1;
    }

    .state-title {
        margin: 0 0 var(--space-xs);
        font-weight: 650;
    }

    .state-detail {
        max-width: 46rem;
        margin: 0;
        color: var(--fg-subtle);
        line-height: 1.45;
    }

    .state-link {
        min-height: 36px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 0 var(--space-lg);
        border: 1px solid color-mix(in srgb, var(--accent) 24%, transparent);
        border-radius: var(--border-radius);
        background: var(--accent-tint);
        color: var(--accent);
        font-size: var(--type-caption-size);
        font-weight: 700;
        text-decoration: none;

        &:hover {
            background: var(--canvas-inset);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .err-msg {
        max-width: 46rem;
        margin: 0;
        color: var(--fg-subtle);
        line-height: 1.45;
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
