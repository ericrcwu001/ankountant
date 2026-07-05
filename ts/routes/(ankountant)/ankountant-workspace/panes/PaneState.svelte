<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Loading / empty / error placeholder shown inside a workspace pane while its
surface fetches (or fails to fetch) its data. Kept token-styled + centered so a
pane never renders blank.
-->
<script lang="ts">
    import { bridgeCommand } from "@tslib/bridgecommand";

    export let phase: "loading" | "empty" | "error";
    export let message = "";
    export let emptyTitle = "";
    export let emptyText = "Nothing to show yet.";
    export let emptyImportLabel = "";
    export let emptyActionHref = "";
    export let emptyActionLabel = "";
    export let emptySecondaryHref = "";
    export let emptySecondaryLabel = "";
    export let onRetry: (() => void) | undefined = undefined;

    $: hasEmptyActions =
        emptyImportLabel !== "" ||
        (emptyActionHref !== "" && emptyActionLabel !== "") ||
        (emptySecondaryHref !== "" && emptySecondaryLabel !== "");

    function openImport(): void {
        bridgeCommand("ankountant:import");
    }
</script>

<div class="pane-state" data-phase={phase} data-testid="pane-state">
    {#if phase === "loading"}
        <span class="spinner" role="progressbar" aria-label="Loading"></span>
        <p class="muted">Loading…</p>
    {:else if phase === "empty"}
        <div class="state-mark" aria-hidden="true">0</div>
        {#if emptyTitle}
            <h2 class="empty-title">{emptyTitle}</h2>
        {/if}
        <p class="muted">{emptyText}</p>
        {#if hasEmptyActions}
            <div class="empty-actions">
                {#if emptyImportLabel}
                    <button type="button" class="primary" on:click={openImport}>
                        {emptyImportLabel}
                    </button>
                {/if}
                {#if emptyActionHref && emptyActionLabel}
                    <a href={emptyActionHref}>{emptyActionLabel}</a>
                {/if}
                {#if emptySecondaryHref && emptySecondaryLabel}
                    <a href={emptySecondaryHref}>{emptySecondaryLabel}</a>
                {/if}
            </div>
        {/if}
    {:else}
        <p class="err">Couldn’t load this surface.</p>
        {#if message}
            <p class="detail">{message}</p>
        {/if}
        {#if onRetry}
            <button type="button" class="retry" on:click={onRetry}>Retry</button>
        {/if}
    {/if}
</div>

<style lang="scss">
    .pane-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: var(--space-md);
        height: 100%;
        min-height: 8rem;
        padding: var(--space-xl);
        text-align: center;
        color: var(--fg);
    }

    .state-mark {
        display: grid;
        place-items: center;
        width: 38px;
        height: 38px;
        border: 1px solid var(--border-subtle);
        border-radius: 50%;
        background: var(--canvas-elevated);
        color: var(--fg-faint);
        font-size: 19px;
        font-weight: 750;
        line-height: 1;
    }

    .empty-title {
        margin: 0;
        max-width: 32ch;
        font-size: var(--type-callout-size);
        font-weight: 750;
        line-height: var(--type-callout-line);
        letter-spacing: 0;
        color: var(--fg);
    }

    .muted {
        margin: 0;
        max-width: 40ch;
        font-size: var(--type-callout-size);
        color: var(--fg-subtle);
    }

    .err {
        margin: 0;
        font-weight: 600;
        color: var(--fg-error);
    }

    .detail {
        margin: 0;
        max-width: 48ch;
        font-size: var(--type-callout-size);
        line-height: 1.45;
        color: var(--fg-subtle);
        overflow-wrap: anywhere;
    }

    .empty-actions {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: var(--space-xs);
        margin-top: var(--space-xs);

        :is(a, button) {
            min-height: 34px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 0 var(--space-md);
            border: 1px solid var(--border-subtle);
            border-radius: var(--border-radius);
            background: var(--canvas-elevated);
            color: var(--fg);
            font: inherit;
            font-size: var(--type-caption-size);
            font-weight: 700;
            line-height: 1.1;
            text-decoration: none;
            cursor: pointer;

            &:hover {
                background: var(--canvas-inset);
            }

            &:focus-visible {
                outline: 2px solid var(--accent) !important;
                outline-offset: 2px;
            }

            &.primary {
                border-color: color-mix(in srgb, var(--accent) 24%, transparent);
                background: var(--accent-tint);
                color: var(--accent);
            }
        }
    }

    .spinner {
        width: 22px;
        height: 22px;
        border: 2px solid var(--border);
        border-top-color: var(--accent);
        border-radius: var(--border-radius-large);
        animation: pane-spin 700ms linear infinite;
    }

    @keyframes pane-spin {
        to {
            transform: rotate(360deg);
        }
    }

    .retry {
        font: inherit;
        font-weight: 600;
        color: var(--accent);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-lg);
        cursor: pointer;

        &:hover {
            border-color: var(--accent);
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }
</style>
