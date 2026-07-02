<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The Browse editor pane. Loads the selected note into the shared NoteEditor and
owns saving in TS (there is no Python editor behind this webview): field edits
are debounced and flushed through updateNotes, and flushed again on blur, note
switch, and teardown. Rich media (image paste/drag) and tag edits are not yet
persisted here — that path is still Qt/clipboard-only, same caveat as Add.
-->
<script lang="ts">
    import "@tslib/runtime-require";
    import "../../../../editor/editor-base.scss";
    import "../../../../editor/legacy.scss";

    import { onDestroy, tick } from "svelte";

    import type { Note } from "@generated/anki/notes_pb";
    import type { Notetype } from "@generated/anki/notetypes_pb";
    import { getNote, getNotetype, updateNotes } from "@generated/backend";

    import type { NoteEditorAPI } from "../../../../editor/NoteEditor.svelte";
    import NoteEditor from "../../../../editor/NoteEditor.svelte";
    import { loadNoteIntoEditor } from "./editorInit";

    /** The note to edit; 0n means nothing selected. */
    export let noteId: bigint;
    /** Notify the table so it can drop the stale cached row after a save. */
    export let onSaved: ((noteId: bigint) => void) | undefined = undefined;

    let editor: NoteEditor | undefined;
    const api: Partial<NoteEditorAPI> = {};

    let currentNote: Note | null = null;
    let lastSavedFields: string[] = [];
    let status: "idle" | "saving" | "saved" | "error" = "idle";
    let message = "";

    const notetypeCache = new Map<string, Notetype>();
    let loadToken = 0;
    let saveTimer: number | undefined;

    function fieldsEqual(a: string[], b: string[]): boolean {
        return a.length === b.length && a.every((v, i) => v === b[i]);
    }

    async function save(): Promise<void> {
        if (saveTimer !== undefined) {
            window.clearTimeout(saveTimer);
            saveTimer = undefined;
        }
        if (!editor || !currentNote) {
            return;
        }
        const fields = editor.getFields();
        if (fieldsEqual(fields, lastSavedFields)) {
            return;
        }
        status = "saving";
        try {
            currentNote.fields = fields;
            await updateNotes({ notes: [currentNote], skipUndoEntry: false });
            lastSavedFields = [...fields];
            status = "saved";
            onSaved?.(currentNote.id);
        } catch (err) {
            status = "error";
            message = err instanceof Error ? err.message : String(err);
        }
    }

    function scheduleSave(): void {
        if (saveTimer !== undefined) {
            window.clearTimeout(saveTimer);
        }
        saveTimer = window.setTimeout(() => void save(), 600);
    }

    async function selectNote(id: bigint): Promise<void> {
        const token = ++loadToken;
        // Persist any edits to the previously-open note before switching.
        await save();
        if (token !== loadToken) {
            return;
        }
        currentNote = null;
        status = "idle";
        message = "";
        if (id === 0n) {
            return;
        }
        try {
            const note = await getNote({ nid: id });
            if (token !== loadToken) {
                return;
            }
            const key = note.notetypeId.toString();
            let notetype = notetypeCache.get(key);
            if (!notetype) {
                notetype = await getNotetype({ ntid: note.notetypeId });
                notetypeCache.set(key, notetype);
            }
            if (token !== loadToken) {
                return;
            }
            currentNote = note;
            await tick(); // let the editor mount
            if (editor && token === loadToken) {
                loadNoteIntoEditor(editor, notetype, note);
                lastSavedFields = editor.getFields();
            }
        } catch (err) {
            status = "error";
            message = err instanceof Error ? err.message : String(err);
        }
    }

    $: void selectNote(noteId);

    onDestroy(() => {
        void save();
    });
</script>

<div class="browse-editor" data-testid="browse-editor">
    <header class="ed-bar">
        <span class="ed-title">Editor</span>
        <span class="ed-status" data-status={status}>
            {#if status === "saving"}Saving…{:else if status === "saved"}Saved{:else if status === "error"}Save
                failed{/if}
        </span>
    </header>

    {#if noteId === 0n}
        <p class="ed-empty">Select a card to edit its note.</p>
    {:else}
        <div
            class="editor-host"
            role="group"
            on:input|capture={scheduleSave}
            on:focusout|capture={() => void save()}
        >
            <NoteEditor bind:this={editor} {api} />
        </div>
        {#if status === "error" && message}
            <p class="ed-error" role="alert">{message}</p>
        {/if}
    {/if}
</div>

<style lang="scss">
    .browse-editor {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        background: var(--canvas-elevated);
        border-top: 1px solid var(--border-subtle);
    }

    .ed-bar {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        flex: 0 0 auto;
        height: 30px;
        padding: 0 var(--space-md);
        background: var(--canvas);
        border-bottom: 1px solid var(--border-subtle);
    }

    .ed-title {
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .ed-status {
        margin-left: auto;
        font-size: var(--type-caption-size);
        color: var(--fg-faint);

        &[data-status="error"] {
            color: var(--fg-error);
        }
    }

    .ed-empty {
        margin: 0;
        padding: var(--space-xl);
        text-align: center;
        color: var(--fg-subtle);
    }

    .editor-host {
        position: relative;
        flex: 1;
        min-height: 0;
        overflow: auto;
    }

    .ed-error {
        margin: 0;
        flex: 0 0 auto;
        padding: var(--space-xs) var(--space-md);
        color: var(--fg-error);
        font-size: var(--type-caption-size);
    }
</style>
