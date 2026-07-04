<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Loading / empty / error placeholder shown inside a workspace pane while its
surface fetches (or fails to fetch) its data. Kept token-styled + centered so a
pane never renders blank.
-->
<script lang="ts">
    export let phase: "loading" | "empty" | "error";
    export let message = "";
    export let emptyText = "Nothing to show yet.";
    export let onRetry: (() => void) | undefined = undefined;
</script>

<div class="pane-state" data-phase={phase} data-testid="pane-state">
    {#if phase === "loading"}
        <span class="spinner" role="progressbar" aria-label="Loading"></span>
        <p class="muted">Loading…</p>
    {:else if phase === "empty"}
        <p class="muted">{emptyText}</p>
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
