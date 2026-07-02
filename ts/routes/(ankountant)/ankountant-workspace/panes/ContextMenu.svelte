<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A lightweight right-click / dropdown menu. Fixed-positioned at (x, y) and
clamped to the viewport, it closes on Escape, outside click, or after an item
runs. Items may be plain actions, checkable toggles (column menu), separators,
or non-interactive headers.
-->
<script context="module" lang="ts">
    export interface MenuItem {
        type?: "item" | "separator" | "header";
        label?: string;
        /** Renders a check mark when true (toggle rows). */
        checked?: boolean;
        disabled?: boolean;
        /** Styles the item as destructive (delete). */
        danger?: boolean;
        onClick?: () => void;
    }
</script>

<script lang="ts">
    import { onMount, tick } from "svelte";

    export let x: number;
    export let y: number;
    export let items: MenuItem[];
    export let onClose: () => void;

    let menuEl: HTMLDivElement | undefined;
    let left = x;
    let top = y;

    function choose(item: MenuItem): void {
        if (item.disabled || item.type === "separator" || item.type === "header") {
            return;
        }
        item.onClick?.();
        onClose();
    }

    async function clamp(): Promise<void> {
        await tick();
        if (!menuEl) {
            return;
        }
        const rect = menuEl.getBoundingClientRect();
        const pad = 8;
        left = Math.min(x, window.innerWidth - rect.width - pad);
        top = Math.min(y, window.innerHeight - rect.height - pad);
        left = Math.max(pad, left);
        top = Math.max(pad, top);
    }

    onMount(() => {
        void clamp();
        function onKey(e: KeyboardEvent): void {
            if (e.key === "Escape") {
                e.stopPropagation();
                onClose();
            }
        }
        // Defer so the opening click doesn't immediately dismiss it.
        const onDown = (e: MouseEvent): void => {
            if (menuEl && !menuEl.contains(e.target as Node)) {
                onClose();
            }
        };
        const t = window.setTimeout(() => {
            window.addEventListener("mousedown", onDown, true);
            window.addEventListener("contextmenu", onDown, true);
        }, 0);
        window.addEventListener("keydown", onKey, true);
        return () => {
            window.clearTimeout(t);
            window.removeEventListener("mousedown", onDown, true);
            window.removeEventListener("contextmenu", onDown, true);
            window.removeEventListener("keydown", onKey, true);
        };
    });
</script>

<div
    class="context-menu"
    bind:this={menuEl}
    style="left:{left}px; top:{top}px"
    role="menu"
    tabindex="-1"
>
    {#each items as item, i (i)}
        {#if item.type === "separator"}
            <div class="sep" role="separator"></div>
        {:else if item.type === "header"}
            <div class="header">{item.label}</div>
        {:else}
            <button
                type="button"
                class="menu-item"
                class:danger={item.danger}
                role="menuitem"
                disabled={item.disabled}
                on:click={() => choose(item)}
            >
                <span class="check" aria-hidden="true">{item.checked ? "✓" : ""}</span>
                <span class="label">{item.label}</span>
            </button>
        {/if}
    {/each}
</div>

<style lang="scss">
    .context-menu {
        position: fixed;
        z-index: 1000;
        min-width: 12rem;
        max-width: 20rem;
        padding: var(--space-xxs);
        background: var(--canvas-elevated);
        border: 1px solid var(--border);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e3);
        color: var(--fg);
        overflow: hidden;
    }

    .sep {
        height: 1px;
        margin: var(--space-xxs) var(--space-xs);
        background: var(--border-subtle);
    }

    .header {
        padding: var(--space-xxs) var(--space-sm);
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
        color: var(--fg-faint);
    }

    .menu-item {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
        width: 100%;
        font: inherit;
        font-size: var(--type-callout-size);
        text-align: left;
        color: var(--fg);
        background: transparent;
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-sm);
        cursor: pointer;

        &:hover:not([disabled]),
        &:focus-visible {
            background: var(--accent-tint);
            outline: none;
        }

        &.danger {
            color: var(--fg-error);
        }

        &[disabled] {
            opacity: 0.4;
            cursor: default;
        }
    }

    .check {
        width: 1em;
        flex: 0 0 auto;
        color: var(--accent);
    }

    .label {
        flex: 1;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }
</style>
