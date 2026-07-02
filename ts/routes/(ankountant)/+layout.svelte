<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Shell chrome for the Ankountant surfaces (Home / Readiness / Confusion / TBS /
Stats / Workspace). The routes live in a SvelteKit route group `(ankountant)/` so they
share this top bar without changing their flat URLs (`/ankountant-dashboard`
etc.), so mediasrv's first-segment whitelist needs no change.

This shell is the desktop app's primary surface: on launch the classic Qt chrome
(menubar, dock tab strip, deck browser) is hidden and this loads full-window
(qt/aqt/main.py: set_ankountant_fullscreen + Workspace.enter_home_shell). Tab
clicks navigate client-side (goto — no reload, no new OS window). Styled with the
Ledger design tokens (--accent = Ink Navy, --canvas*, --border*).
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { afterNavigate, goto } from "$app/navigation";

    const tabs = [
        { id: "home", label: "Home", href: "/ankountant-home" },
        { id: "dashboard", label: "Readiness", href: "/ankountant-dashboard" },
        { id: "confusion", label: "Confusion", href: "/ankountant-confusion" },
        { id: "tbs", label: "TBS", href: "/ankountant-tbs" },
        { id: "research", label: "Research", href: "/ankountant-research" },
        { id: "doc-review", label: "Doc Review", href: "/ankountant-doc-review" },
        { id: "stats", label: "Stats", href: "/ankountant-stats" },
        { id: "workspace", label: "Workspace", href: "/ankountant-workspace" },
    ];

    // Kept in sync on initial load and after every client navigation (incl. the
    // Qt-driven __ankGoto path and browser back/forward). Seeded from the URL so
    // the workspace route never flashes the surface-tab bar (ssr is off).
    let current = typeof window !== "undefined" ? window.location.pathname : "";
    afterNavigate(() => {
        current = window.location.pathname;
    });

    // The tiling workspace provides its own toolbar, so the shared surface-tab
    // bar is suppressed there.
    $: isWorkspace = current === "/ankountant-workspace";

    function navigate(href: string): void {
        goto(href); // client-side, no reload, no window
    }

    onMount(() => {
        // Lets Qt drive client navigation without a reload when re-entering the
        // already-loaded shell (see _ankountantState in qt/aqt/main.py).
        (window as unknown as { __ankGoto?: (href: string) => void }).__ankGoto = (
            href: string,
        ) => goto(href);
    });
</script>

<div class="ank-shell">
    {#if !isWorkspace}
        <header class="ank-shell-topbar">
            <span class="ank-brand">Ankountant</span>
            <nav class="ank-tabs" aria-label="Ankountant sections">
                {#each tabs as t (t.id)}
                    <button
                        type="button"
                        class="ank-tab"
                        class:active={current === t.href}
                        aria-current={current === t.href ? "page" : undefined}
                        on:click={() => navigate(t.href)}
                    >
                        {t.label}
                    </button>
                {/each}
            </nav>
        </header>
    {/if}

    <main class="ank-shell-body"><slot /></main>
</div>

<style lang="scss">
    .ank-shell {
        display: flex;
        flex-direction: column;
        min-height: 100vh;
        background: var(--canvas);
        color: var(--fg);
    }

    .ank-shell-topbar {
        display: flex;
        align-items: center;
        gap: var(--space-lg);
        height: 48px;
        padding: 0 var(--space-lg);
        background: var(--canvas-elevated);
        border-bottom: 1px solid var(--border-subtle);
    }

    // Brand wordmark anchoring the shell top bar (chrome-only navy).
    .ank-brand {
        font-weight: 600;
        letter-spacing: -0.01em;
        color: var(--accent);
    }

    .ank-tabs {
        display: flex;
        gap: var(--space-xs);
        margin-left: auto;
    }

    .ank-tab {
        font: inherit;
        font-weight: 500;
        color: var(--fg-subtle);
        background: transparent;
        border: 0;
        box-shadow: none;
        padding: var(--space-sm) var(--space-md);
        border-radius: var(--border-radius);

        &:hover {
            background: var(--canvas);
            border: 0;
            color: var(--fg);
        }

        // Active tab = brand navy (chrome-only accent).
        &.active {
            color: var(--accent);
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .ank-shell-body {
        flex: 1;
        min-height: 0;
    }
</style>
