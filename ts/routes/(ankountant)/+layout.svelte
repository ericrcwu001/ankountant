<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Shell chrome for the Ankountant surfaces. A fixed navy left sidebar (brand mark,
primary navigation, focus + profile) frames the light study surfaces to its
right. Routes live in a SvelteKit route group `(ankountant)/` so they share this
chrome without changing their flat URLs. On launch the classic Qt chrome is
hidden and this loads full-window (qt/aqt/main.py). Styled with the Ledger design
tokens (--accent = Ink Navy).
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { afterNavigate, goto } from "$app/navigation";
    import { bridgeCommand } from "@tslib/bridgecommand";
    import { activeShellNavId } from "./shell-nav";

    // The Ankountant study surfaces are always presented in light mode, even when
    // the host Anki app requests night-mode (via the `#night` hash the Qt shell
    // appends). The dashboard (`ankountant-home`) pins its own light palette, so
    // this leaves it untouched while flipping the token-driven surfaces to light.
    // Done synchronously here (not in onMount) so it lands before first paint.
    if (typeof document !== "undefined") {
        document.documentElement.classList.remove("night-mode");
        document.documentElement.dataset.bsTheme = "light";
    }

    // Line-icon paths (24x24, stroke=currentColor). Kept inline so the sidebar
    // has no asset dependency.
    const icons: Record<string, string> = {
        dashboard:
            '<rect x="3" y="3" width="7" height="7" rx="1.4"/><rect x="14" y="3" width="7" height="7" rx="1.4"/><rect x="14" y="14" width="7" height="7" rx="1.4"/><rect x="3" y="14" width="7" height="7" rx="1.4"/>',
        study: '<path d="M3 4.6h5.2a2.8 2.8 0 0 1 2.8 2.8V20a2.4 2.4 0 0 0-2.4-2.4H3z"/><path d="M21 4.6h-5.2a2.8 2.8 0 0 0-2.8 2.8V20a2.4 2.4 0 0 1 2.4-2.4H21z"/>',
        practice:
            '<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="4.4"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>',
        review: '<circle cx="12" cy="12" r="8.4"/><path d="M12 7.2V12l3.4 2"/>',
        analytics: '<path d="M5 20V11"/><path d="M12 20V4.5"/><path d="M19 20v-6.5"/>',
        browse: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M20 20l-4.7-4.7"/>',
        settings:
            '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V15z"/>',
        sync: '<path d="M21 12a9 9 0 0 1-9 9 9 9 0 0 1-7.4-3.9"/><path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 7.4 3.9"/><path d="M21 4v4h-4"/><path d="M3 20v-4h4"/>',
        flame: '<path d="M12 3s4.4 3.2 4.4 7.6a4.4 4.4 0 0 1-8.8 0c0-1 .3-1.9.9-2.7.4 1.6 1.7 2.1 1.7 2.1s-.9-2.5.2-4.3c.6-1 1.6-2 1.6-2.7z"/>',
        chevron: '<path d="M6 9.5l6 6 6-6"/>',
    };

    interface NavItem {
        id: string;
        label: string;
        href?: string;
        command?: string;
    }

    const settingsCommand = "ankountant:prefs";

    const nav: NavItem[] = [
        { id: "dashboard", label: "Dashboard", href: "/ankountant-home" },
        { id: "study", label: "Study", href: "/ankountant-workspace" },
        { id: "practice", label: "Practice", href: "/ankountant-confusion" },
        { id: "review", label: "TBS", href: "/ankountant-tbs" },
        { id: "analytics", label: "Analytics", href: "/ankountant-stats" },
        {
            id: "browse",
            label: "Browse",
            href: "/ankountant-workspace?initial=browse",
        },
        { id: "sync", label: "Sync", href: "/ankountant-sync" },
        { id: "settings", label: "Settings", command: settingsCommand },
    ];

    let currentPath = typeof window !== "undefined" ? window.location.pathname : "";
    let currentSearch = typeof window !== "undefined" ? window.location.search : "";
    afterNavigate(() => {
        currentPath = window.location.pathname;
        currentSearch = window.location.search;
    });

    $: activeNavId = activeShellNavId(nav, currentPath, currentSearch);

    function isActive(item: NavItem): boolean {
        return activeNavId === item.id;
    }

    function navigate(item: NavItem): void {
        if (item.command) {
            bridgeCommand(item.command);
        } else if (item.href) {
            setCurrentLocation(item.href);
            goto(item.href);
        }
    }

    function setCurrentLocation(href: string): void {
        const [path, search = ""] = href.split("?");
        currentPath = path;
        currentSearch = search ? `?${search}` : "";
    }

    function openSettings(): void {
        bridgeCommand(settingsCommand);
    }

    onMount(() => {
        (window as unknown as { __ankGoto?: (href: string) => void }).__ankGoto = (
            href: string,
        ) => goto(href);
    });
</script>

<div class="ank-shell">
    <aside class="ank-sidebar">
        <div class="brand">
            <svg class="brand-mark" viewBox="0 0 64 34" aria-hidden="true">
                <path
                    d="M2 31 L18 9 L26 19 L33 7 L44 22 L50 15 L62 31 Z"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.4"
                    stroke-linejoin="round"
                />
                <path
                    d="M14 15 L18 9 L22 15 M29 12 L33 7 L38 14 M46 18 L50 15 L54 20"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1"
                    stroke-linejoin="round"
                    opacity="0.7"
                />
            </svg>
            <div class="wordmark">Ankountant</div>
            <div class="brand-sub">CPA FAR EXAM PREP</div>
        </div>

        <nav class="nav" aria-label="Ankountant">
            {#each nav as item (item.id)}
                <button
                    type="button"
                    class="nav-item"
                    class:active={isActive(item)}
                    aria-current={isActive(item) ? "page" : undefined}
                    on:click={() => navigate(item)}
                >
                    <svg
                        class="nav-icon"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.7"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                    >
                        <!-- eslint-disable-next-line svelte/no-at-html-tags -->
                        {@html icons[item.id]}
                    </svg>
                    <span class="nav-label">{item.label}</span>
                </button>
            {/each}
        </nav>

        <div class="sidebar-foot">
            <div class="focus-card" aria-label="Study focus">
                <div class="focus-row">
                    <span class="focus-name">
                        <svg
                            class="focus-icon"
                            viewBox="0 0 24 24"
                            fill="currentColor"
                            aria-hidden="true"
                        >
                            <!-- eslint-disable-next-line svelte/no-at-html-tags -->
                            {@html icons.flame}
                        </svg>
                        Focus
                    </span>
                    <span class="focus-count">FAR</span>
                </div>
            </div>

            <button
                type="button"
                class="profile"
                aria-label="Open Ankountant preferences"
                on:click={openSettings}
            >
                <span class="avatar">AK</span>
                <span class="profile-name">Preferences</span>
                <svg
                    class="profile-caret"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                >
                    <!-- eslint-disable-next-line svelte/no-at-html-tags -->
                    {@html icons.chevron}
                </svg>
            </button>
        </div>
    </aside>

    <main class="ank-shell-body"><slot /></main>
</div>

<style lang="scss">
    .ank-shell {
        display: flex;
        min-height: 100vh;
        background: var(--canvas);
        color: var(--fg);
    }

    // --- Navy sidebar -------------------------------------------------------
    .ank-sidebar {
        flex: none;
        width: 248px;
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        padding: var(--space-xl) var(--space-lg) var(--space-lg);
        color: #fff;
        background: linear-gradient(180deg, #1b3a63 0%, #143255 42%, #0e2748 100%);
        border-right: 1px solid rgba(0, 0, 0, 0.25);
    }

    .brand {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 2px;
        padding: var(--space-xs) 0 var(--space-lg);
    }

    .brand-mark {
        width: 62px;
        height: 33px;
        color: rgba(255, 255, 255, 0.92);
        margin-bottom: var(--space-xs);
    }

    .wordmark {
        font-family: "Iowan Old Style", Palatino, Georgia, "Times New Roman", serif;
        font-size: 25px;
        font-weight: 600;
        letter-spacing: 0.01em;
        color: #fff;
    }

    .brand-sub {
        font-size: 10.5px;
        font-weight: 600;
        letter-spacing: 0.16em;
        color: #7ea6d6;
    }

    .nav {
        display: flex;
        flex-direction: column;
        gap: 3px;
        margin-top: var(--space-sm);
    }

    .nav-item {
        display: flex;
        align-items: center;
        gap: var(--space-md);
        width: 100%;
        padding: 10px var(--space-md);
        border: 1px solid transparent;
        border-radius: 10px;
        background: transparent;
        color: rgba(255, 255, 255, 0.74);
        font-size: 15px;
        font-weight: 500;
        text-align: left;
        box-shadow: none;
        cursor: pointer;

        &:hover:not(.inert) {
            background: rgba(255, 255, 255, 0.07);
            color: #fff;
            border-color: transparent;
        }

        &.active {
            background: rgba(255, 255, 255, 0.11);
            border-color: rgba(255, 255, 255, 0.14);
            color: #fff;
        }

        &:focus-visible {
            outline: 2px solid #7ea6d6 !important;
            outline-offset: 2px;
        }
    }

    .nav-icon {
        flex: none;
        width: 20px;
        height: 20px;
        opacity: 0.92;
    }

    .nav-label {
        line-height: 1;
    }

    .sidebar-foot {
        margin-top: auto;
        display: flex;
        flex-direction: column;
        gap: var(--space-md);
        padding-top: var(--space-lg);
    }

    .focus-card {
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
        padding: 0 var(--space-xs);
    }

    .focus-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
    }

    .focus-name {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        font-size: 13.5px;
        font-weight: 500;
        color: rgba(255, 255, 255, 0.82);
    }

    .focus-icon {
        width: 15px;
        height: 15px;
        color: #e08a2e;
    }

    .focus-count {
        font-size: 13.5px;
        font-weight: 700;
        color: #fff;
    }

    .profile {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        width: 100%;
        padding: var(--space-sm);
        border: 1px solid rgba(255, 255, 255, 0.12);
        border-radius: 12px;
        background: rgba(255, 255, 255, 0.05);
        color: #fff;
        box-shadow: none;
        cursor: pointer;

        &:hover {
            background: rgba(255, 255, 255, 0.09);
            border-color: rgba(255, 255, 255, 0.12);
        }
    }

    .avatar {
        flex: none;
        display: grid;
        place-items: center;
        width: 32px;
        height: 32px;
        border-radius: 999px;
        border: 1.5px solid rgba(255, 255, 255, 0.55);
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.02em;
    }

    .profile-name {
        flex: 1;
        text-align: left;
        font-size: 14px;
        font-weight: 500;
    }

    .profile-caret {
        width: 18px;
        height: 18px;
        opacity: 0.7;
    }

    // --- Body ---------------------------------------------------------------
    .ank-shell-body {
        flex: 1;
        min-width: 0;
        min-height: 0;
    }
</style>
