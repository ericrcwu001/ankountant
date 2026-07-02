<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Web-native Add Cards surface. Reuses the real note editor (ts/editor/) but is
orchestrated from TypeScript + RPCs instead of the Python aqt.editor.Editor:
`defaults_for_adding` → `new_note` + `get_field_names` seed the editor via
setFields; the Add button collects fields with the getFields() hook and calls
`add_note`. Notetype/deck pickers are web dropdowns.

KNOWN LIMITATION (v1): rich media (image paste/drag, audio) is NOT handled here
— that path is Python/Qt-only (clipboard + collection.media file I/O) and can't
run in a plain webview. Use the classic Add dialog for media-heavy notes until a
media bridge lands.
-->
<script lang="ts">
    import "@tslib/runtime-require";
    import "../../../../editor/editor-base.scss";
    import "../../../../editor/legacy.scss";

    import { onMount, tick } from "svelte";

    import type { Note } from "@generated/anki/notes_pb";
    import {
        addNote,
        defaultsForAdding,
        getDeckNames,
        getNotetype,
        getNotetypeNames,
        newNote,
    } from "@generated/backend";

    import type { NoteEditorAPI } from "../../../../editor/NoteEditor.svelte";
    import NoteEditor from "../../../../editor/NoteEditor.svelte";
    import { loadNoteIntoEditor } from "./editorInit";
    import PaneState from "./PaneState.svelte";

    let phase: "loading" | "ready" | "error" = "loading";
    let message = "";

    let editor: NoteEditor | undefined;
    const api: Partial<NoteEditorAPI> = {};

    let notetypes: { id: bigint; name: string }[] = [];
    let decks: { id: bigint; name: string }[] = [];
    let notetypeId = 0n;
    let deckId = 0n;
    let note: Note | null = null;
    let adding = false;
    let addedCount = 0;

    // Seed the editor with a fresh blank note for the current notetype. The
    // notetype carries the per-field fonts/descriptions the editor needs to
    // mount without erroring — see editorInit.loadNoteIntoEditor.
    async function loadNote(): Promise<void> {
        const [freshNote, notetype] = await Promise.all([
            newNote({ ntid: notetypeId }),
            getNotetype({ ntid: notetypeId }),
        ]);
        note = freshNote;
        await tick();
        if (editor) {
            loadNoteIntoEditor(editor, notetype, freshNote, { focus: true });
        }
    }

    async function load(): Promise<void> {
        phase = "loading";
        try {
            const defaults = await defaultsForAdding({
                homeDeckOfCurrentReviewCard: 0n,
            });
            notetypeId = defaults.notetypeId;
            deckId = defaults.deckId;
            const [nt, dk] = await Promise.all([
                getNotetypeNames({}),
                getDeckNames({ skipEmptyDefault: false, includeFiltered: false }),
            ]);
            notetypes = nt.entries.map((e) => ({ id: e.id, name: e.name }));
            decks = dk.entries.map((e) => ({ id: e.id, name: e.name }));
            phase = "ready";
            await tick();
            await loadNote();
        } catch (err) {
            message = err instanceof Error ? err.message : String(err);
            phase = "error";
        }
    }

    async function onNotetypeChange(): Promise<void> {
        try {
            await loadNote();
        } catch (err) {
            message = err instanceof Error ? err.message : String(err);
        }
    }

    async function submit(): Promise<void> {
        if (adding || !editor || !note) {
            return;
        }
        adding = true;
        message = "";
        try {
            note.fields = editor.getFields();
            note.tags = [];
            const resp = await addNote({ note, deckId });
            if (resp.noteId) {
                addedCount += 1;
                await loadNote(); // fresh blank note for the next entry
            }
        } catch (err) {
            message = err instanceof Error ? err.message : String(err);
        } finally {
            adding = false;
        }
    }

    onMount(() => {
        void load();
    });
</script>

{#if phase === "error"}
    <PaneState phase="error" {message} onRetry={load} />
{:else}
    <div class="add-pane" data-testid="add-pane">
        <header class="add-bar">
            <label class="picker">
                <span class="picker-label">Type</span>
                <select
                    bind:value={notetypeId}
                    on:change={onNotetypeChange}
                    disabled={phase !== "ready"}
                    aria-label="Notetype"
                >
                    {#each notetypes as nt (nt.id)}
                        <option value={nt.id}>{nt.name}</option>
                    {/each}
                </select>
            </label>
            <label class="picker">
                <span class="picker-label">Deck</span>
                <select
                    bind:value={deckId}
                    disabled={phase !== "ready"}
                    aria-label="Deck"
                >
                    {#each decks as d (d.id)}
                        <option value={d.id}>{d.name}</option>
                    {/each}
                </select>
            </label>
            <div class="add-actions">
                {#if addedCount > 0}
                    <span class="added" data-testid="added-count">
                        {addedCount} added
                    </span>
                {/if}
                <button
                    type="button"
                    class="add-btn"
                    on:click={submit}
                    disabled={adding || phase !== "ready"}
                    data-testid="add-note"
                >
                    Add
                </button>
            </div>
        </header>

        <div class="editor-host">
            <NoteEditor bind:this={editor} {api} />
        </div>

        {#if message}
            <p class="add-error" role="alert">{message}</p>
        {/if}
    </div>
{/if}

<style lang="scss">
    .add-pane {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
    }

    .add-bar {
        display: flex;
        align-items: center;
        gap: var(--space-md);
        flex: 0 0 auto;
        padding: var(--space-sm) var(--space-md);
        background: var(--canvas);
        border-bottom: 1px solid var(--border-subtle);
    }

    .picker {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
    }

    .picker-label {
        font-size: var(--type-caption-size);
        font-weight: 600;
        color: var(--fg-subtle);
    }

    .picker select {
        font: inherit;
        font-size: var(--type-caption-size);
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-sm);
        max-width: 12rem;
        cursor: pointer;

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }
    }

    .add-actions {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        margin-left: auto;
    }

    .added {
        font-size: var(--type-caption-size);
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums;
    }

    .add-btn {
        font: inherit;
        font-weight: 600;
        color: #fff;
        background: var(--button-primary-bg);
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-lg);
        cursor: pointer;
        box-shadow: 0 1px 2px rgba(31, 58, 95, 0.24);

        &:hover:not([disabled]) {
            background: var(--button-primary-hover-bg);
        }

        &:active:not([disabled]) {
            transform: translateY(1px);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }

        &[disabled] {
            opacity: 0.5;
            cursor: default;
        }
    }

    .editor-host {
        position: relative;
        flex: 1;
        min-height: 0;
        overflow: auto;
    }

    .add-error {
        margin: 0;
        flex: 0 0 auto;
        padding: var(--space-xs) var(--space-md);
        color: var(--fg-error);
        font-size: var(--type-caption-size);
    }
</style>
