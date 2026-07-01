<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Shell chrome for the Ankountant surfaces (Readiness / Confusion / TBS). The
three routes live in a SvelteKit route group `(ankountant)/` so they share this
top bar without changing their flat URLs (`/ankountant-dashboard` etc.), so
mediasrv's first-segment whitelist needs no change.

Rendered inside the desktop single-window "ankountant" state (qt/aqt/main.py):
tab clicks navigate client-side (goto — no reload, no new OS window); "← Decks"
exits via a Qt bridge command that routes to moveToState("deckBrowser"). Styled
with the Ledger design tokens (--accent = Ink Navy, --canvas*, --border*).
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { afterNavigate, goto } from "$app/navigation";
    import { bridgeCommand } from "@tslib/bridgecommand";

    const tabs = [
        { id: "dashboard", label: "Readiness", href: "/ankountant-dashboard" },
        { id: "confusion", label: "Confusion", href: "/ankountant-confusion" },
        { id: "tbs", label: "TBS", href: "/ankountant-tbs" },
    ];

    // Kept in sync on initial load and after every client navigation (incl. the
    // Qt-driven __ankGoto path and browser back/forward).
    let current = "";
    afterNavigate(() => {
        current = window.location.pathname;
    });

    function exitToDecks(): void {
        // Qt routes this to moveToState("deckBrowser") (Qt-only bridge; the
        // shell always runs inside the desktop webview).
        bridgeCommand("ankountant:exit");
    }

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
    <header class="ank-shell-topbar">
        <button
            type="button"
            class="ank-back"
            on:click={exitToDecks}
            aria-label="Back to decks"
        >
            ← Decks
        </button>
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

    // These are plain <button>s, so the global button base applies; the
    // higher-specificity component rules below flatten them to nav chrome.
    .ank-back {
        font: inherit;
        font-weight: 600;
        color: var(--fg);
        background: transparent;
        border: 0;
        box-shadow: none;
        padding: var(--space-sm);
        border-radius: var(--border-radius);

        &:hover {
            background: var(--canvas);
            border: 0;
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
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
