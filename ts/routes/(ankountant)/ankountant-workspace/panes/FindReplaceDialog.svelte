<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Find & replace over the notes behind the current selection (or the whole
collection when nothing is selected). Mirrors qt/aqt/browser/find_and_replace.py:
the field picker offers All fields, Tags (routes to findAndReplaceTag), or one
specific field; regex + case options map straight onto FindAndReplaceRequest.
-->
<script lang="ts">
    import { onMount } from "svelte";

    import {
        fieldNamesForNotes,
        findAndReplace,
        findAndReplaceTag,
    } from "@generated/backend";

    /** Note ids to operate on; empty means the whole collection. */
    export let noteIds: bigint[];
    export let onClose: () => void;
    export let onApplied: (count: number) => void;

    const ALL_FIELDS = "__all__";
    const TAGS = "__tags__";

    let search = "";
    let replacement = "";
    let regex = false;
    let matchCase = false;
    let field = ALL_FIELDS;
    let fieldNames: string[] = [];
    let loadingFields = true;
    let fieldLoadError = "";
    let busy = false;
    let error = "";
    let searchInput: HTMLInputElement | undefined;

    $: scopeLabel =
        noteIds.length > 0
            ? `${noteIds.length} selected note${noteIds.length === 1 ? "" : "s"}`
            : "the whole collection";

    function errorMessage(err: unknown): string {
        return err instanceof Error ? err.message : String(err);
    }

    async function loadFields(): Promise<void> {
        loadingFields = true;
        fieldLoadError = "";
        try {
            const resp = await fieldNamesForNotes(
                { nids: noteIds },
                { alertOnError: false },
            );
            fieldNames = resp.fields;
        } catch (err) {
            fieldNames = [];
            fieldLoadError = errorMessage(err);
        } finally {
            loadingFields = false;
        }
    }

    async function apply(): Promise<void> {
        if (busy || !search || loadingFields || fieldLoadError) {
            return;
        }
        busy = true;
        error = "";
        try {
            let count: number;
            if (field === TAGS) {
                const resp = await findAndReplaceTag(
                    {
                        noteIds,
                        search,
                        replacement,
                        regex,
                        matchCase,
                    },
                    { alertOnError: false },
                );
                count = resp.count;
            } else {
                const resp = await findAndReplace(
                    {
                        nids: noteIds,
                        search,
                        replacement,
                        regex,
                        matchCase,
                        fieldName: field === ALL_FIELDS ? "" : field,
                    },
                    { alertOnError: false },
                );
                count = resp.count;
            }
            onApplied(count);
            onClose();
        } catch (err) {
            error = errorMessage(err);
        } finally {
            busy = false;
        }
    }

    onMount(() => {
        void loadFields();
        searchInput?.focus();
        function onKey(e: KeyboardEvent): void {
            if (e.key === "Escape") {
                e.stopPropagation();
                onClose();
            } else if (e.key === "Enter" && !e.isComposing) {
                e.preventDefault();
                void apply();
            }
        }
        window.addEventListener("keydown", onKey, true);
        return () => window.removeEventListener("keydown", onKey, true);
    });
</script>

<button
    type="button"
    class="fr-scrim"
    tabindex="-1"
    aria-label="Close find and replace"
    on:click={onClose}
></button>
<div class="fr-dialog" role="dialog" aria-modal="true" aria-label="Find and replace">
    <h2 class="fr-title">Find and Replace</h2>
    <p class="fr-scope">In {scopeLabel}.</p>

    <label class="fr-row">
        <span>Find</span>
        <input bind:this={searchInput} bind:value={search} spellcheck="false" />
    </label>
    <label class="fr-row">
        <span>Replace with</span>
        <input bind:value={replacement} spellcheck="false" />
    </label>
    <label class="fr-row">
        <span>In</span>
        <select bind:value={field} disabled={loadingFields || fieldLoadError !== ""}>
            <option value={ALL_FIELDS}>All fields</option>
            <option value={TAGS}>Tags</option>
            {#if loadingFields}
                <option value="" disabled>Loading fields…</option>
            {/if}
            {#each fieldNames as name (name)}
                <option value={name}>{name}</option>
            {/each}
        </select>
    </label>

    <div class="fr-opts">
        <label>
            <input type="checkbox" bind:checked={regex} />
            Treat input as regex
        </label>
        <label>
            <input type="checkbox" bind:checked={matchCase} />
            Match case
        </label>
    </div>

    {#if field === TAGS}
        <p class="fr-note">Tags mode replaces within tag text, not fields.</p>
    {/if}
    {#if fieldLoadError}
        <div class="fr-load-error" role="alert" data-testid="fr-field-load-error">
            <p>Could not load fields: {fieldLoadError}</p>
            <button type="button" class="fr-btn small" on:click={loadFields}>
                Retry fields
            </button>
        </div>
    {/if}
    {#if error}
        <p class="fr-error" role="alert" data-testid="fr-apply-error">{error}</p>
    {/if}

    <div class="fr-actions">
        <button type="button" class="fr-btn" on:click={onClose}>Cancel</button>
        <button
            type="button"
            class="fr-btn primary"
            data-testid="fr-replace"
            disabled={busy || !search || loadingFields || fieldLoadError !== ""}
            on:click={apply}
        >
            {busy ? "Replacing…" : "Replace"}
        </button>
    </div>
</div>

<style lang="scss">
    .fr-scrim {
        position: fixed;
        inset: 0;
        z-index: 1100;
        padding: 0;
        background: rgba(0, 0, 0, 0.35);
        border: 0;
    }

    .fr-dialog {
        position: fixed;
        z-index: 1101;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        width: min(30rem, calc(100vw - 2rem));
        padding: var(--space-lg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border);
        border-radius: var(--border-radius-large);
        box-shadow: var(--elevation-e3);
        color: var(--fg);
    }

    .fr-title {
        margin: 0 0 var(--space-xs);
        font-size: var(--type-title-size);
        font-weight: 600;
    }

    .fr-scope {
        margin: 0 0 var(--space-md);
        font-size: var(--type-caption-size);
        color: var(--fg-subtle);
    }

    .fr-row {
        display: grid;
        grid-template-columns: 7rem 1fr;
        align-items: center;
        gap: var(--space-sm);
        margin-bottom: var(--space-sm);

        span {
            font-size: var(--type-callout-size);
            color: var(--fg-subtle);
        }

        input,
        select {
            font: inherit;
            font-size: var(--type-callout-size);
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border-control);
            border-radius: var(--border-radius);
            padding: var(--space-xs) var(--space-sm);

            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: 1px;
            }
        }
    }

    .fr-opts {
        display: flex;
        gap: var(--space-lg);
        margin: var(--space-sm) 0;

        label {
            display: flex;
            align-items: center;
            gap: var(--space-xs);
            font-size: var(--type-caption-size);
            color: var(--fg-subtle);
        }
    }

    .fr-note {
        margin: 0 0 var(--space-sm);
        font-size: var(--type-caption-size);
        color: var(--fg-faint);
    }

    .fr-error {
        margin: 0 0 var(--space-sm);
        font-size: var(--type-caption-size);
        color: var(--fg-error);
        overflow-wrap: anywhere;
    }

    .fr-load-error {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-sm);
        margin: 0 0 var(--space-sm);
        padding: var(--space-sm);
        color: var(--fg-error);
        background: var(--gap-warning-bg);
        border: 1px solid rgba(214, 69, 65, 0.4);
        border-radius: var(--border-radius);

        p {
            margin: 0;
            overflow-wrap: anywhere;
        }
    }

    .fr-actions {
        display: flex;
        justify-content: flex-end;
        gap: var(--space-sm);
        margin-top: var(--space-md);
    }

    .fr-btn {
        font: inherit;
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-lg);
        cursor: pointer;

        &:hover:not([disabled]) {
            border-color: var(--accent);
        }

        &.primary {
            color: #fff;
            background: var(--button-primary-bg);
            border-color: transparent;

            &:hover:not([disabled]) {
                background: var(--button-primary-hover-bg);
            }
        }

        &[disabled] {
            opacity: 0.5;
            cursor: default;
        }

        &.small {
            flex: 0 0 auto;
            padding: var(--space-xxs) var(--space-sm);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }
    }
</style>
