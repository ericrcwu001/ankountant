<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Ankountant Sync surface. A native entry point in the SvelteKit shell so users
never have to reveal the classic Qt chrome to sync. The "Sync now" action fires
the `ankountant:sync` bridge command, which the Qt host routes to
`AnkiQt.on_sync_button_clicked` (qt/aqt/workspace.py) — reusing the existing
desktop sync flow (login prompt, direction choice, progress, error dialogs).
-->
<script lang="ts">
    import { bridgeCommand } from "@tslib/bridgecommand";

    let triggered = $state(false);
    let resetTimer: ReturnType<typeof setTimeout> | undefined;

    function syncNow(): void {
        bridgeCommand("ankountant:sync");
        triggered = true;
        clearTimeout(resetTimer);
        resetTimer = setTimeout(() => (triggered = false), 6000);
    }

    const syncPath = [
        {
            title: "Desktop reviews",
            body: "Local card reviews, note edits, deck changes, and media updates are uploaded first.",
        },
        {
            title: "Phone reviews",
            body: "Mobile work is pulled through the same Anki collection engine and merged into this profile.",
        },
        {
            title: "Readiness data",
            body: "Hidden attempt notes and sync-safe settings travel with the collection, so scoring abstains consistently.",
        },
    ];
</script>

<div class="sync-screen" data-testid="sync">
    <div class="sync-shell">
        <section class="sync-command" aria-labelledby="sync-title">
            <div class="badge" class:spin={triggered} aria-hidden="true">
                <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.9"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                >
                    <path d="M21 12a9 9 0 0 1-9 9 9 9 0 0 1-7.4-3.9" />
                    <path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 7.4 3.9" />
                    <path d="M21 4v4h-4" />
                    <path d="M3 20v-4h4" />
                </svg>
            </div>

            <div>
                <p class="eyebrow">Collection transport</p>
                <h1 id="sync-title">Sync</h1>
                <p class="lead">
                    Push this Mac, pull other devices, then let readiness read from the
                    merged collection.
                </p>
            </div>

            <button type="button" class="sync-cta" onclick={syncNow}>
                <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                >
                    <path d="M21 12a9 9 0 0 1-9 9 9 9 0 0 1-7.4-3.9" />
                    <path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 7.4 3.9" />
                    <path d="M21 4v4h-4" />
                    <path d="M3 20v-4h4" />
                </svg>
                <span>{triggered ? "Sync started" : "Sync now"}</span>
            </button>

            <p class="status" aria-live="polite">
                {#if triggered}
                    Follow any prompts that appear to finish syncing.
                {:else}
                    Sync server required. Local study continues when the server is
                    unavailable.
                {/if}
            </p>
        </section>

        <section class="sync-path" aria-labelledby="sync-path-title">
            <h2 id="sync-path-title">What Moves</h2>
            <ul>
                {#each syncPath as step (step.title)}
                    <li>
                        <span class="dot" aria-hidden="true"></span>
                        <span class="step-text">
                            <strong>{step.title}</strong>
                            <small>{step.body}</small>
                        </span>
                    </li>
                {/each}
            </ul>
        </section>
    </div>
</div>

<style lang="scss">
    .sync-screen {
        --accent: #24546a;
        --accent-strong: #193c4d;
        --olive: #4d653d;
        --fg: #172033;
        --fg-subtle: #536174;
        --fg-faint: #7a8493;
        --panel: #ffffff;
        --surface: #f4f6f1;
        --border-subtle: #d9dfd6;

        box-sizing: border-box;
        min-height: 100vh;
        overflow: auto;
        padding: clamp(20px, 4vw, 48px);
        background: var(--surface);
        color: var(--fg);
    }

    .sync-shell {
        width: 100%;
        max-width: 1040px;
        margin: 0 auto;
        display: grid;
        grid-template-columns: minmax(280px, 0.86fr) minmax(340px, 1.14fr);
        gap: 16px;
        align-items: stretch;
    }

    .sync-command,
    .sync-path {
        box-sizing: border-box;
        background: var(--panel);
        border: 1px solid var(--border-subtle);
        border-radius: 8px;
        box-shadow: 0 12px 32px rgba(37, 45, 55, 0.07);
    }

    .sync-command {
        min-height: 420px;
        padding: clamp(22px, 3vw, 34px);
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        gap: 24px;
        border-top: 5px solid var(--accent);
    }

    .sync-path {
        padding: clamp(20px, 2.6vw, 30px);
        border-top: 5px solid var(--olive);
    }

    .badge {
        display: grid;
        place-items: center;
        width: 64px;
        height: 64px;
        border-radius: 999px;
        color: var(--accent);
        background: rgba(14, 58, 102, 0.08);
        border: 1px solid rgba(14, 58, 102, 0.14);

        svg {
            width: 30px;
            height: 30px;
        }

        &.spin svg {
            animation: sync-spin 1s linear infinite;
        }
    }

    @keyframes sync-spin {
        to {
            transform: rotate(360deg);
        }
    }

    h1 {
        margin: 3px 0 0;
        font-size: 36px;
        line-height: 1.02;
        font-weight: 700;
        letter-spacing: 0;
        color: var(--fg);
    }

    h2 {
        margin: 0;
        font-size: 15px;
        line-height: 1.25;
        font-weight: 700;
        color: var(--fg);
    }

    .eyebrow {
        margin: 0;
        font-size: 11px;
        font-weight: 700;
        line-height: 1.2;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--fg-faint);
    }

    .lead {
        margin: 12px 0 0;
        max-width: 38ch;
        font-size: 15px;
        line-height: 1.5;
        color: var(--fg-subtle);
    }

    .sync-cta {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
        width: fit-content;
        min-height: 48px;
        padding: 12px 24px;
        font-size: 15px;
        font-weight: 600;
        color: #fff;
        background: var(--accent);
        border: 1px solid var(--accent);
        border-radius: 8px;
        cursor: pointer;

        svg {
            width: 18px;
            height: 18px;
        }

        &:hover {
            background: var(--accent-strong);
        }

        &:focus-visible {
            outline: 2px solid #83a9bc;
            outline-offset: 2px;
        }
    }

    .status {
        min-height: 20px;
        margin: 0;
        font-size: 13px;
        font-weight: 500;
        line-height: 1.45;
        color: var(--fg-subtle);
    }

    .sync-path ul {
        width: 100%;
        list-style: none;
        margin: 18px 0 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 14px;

        li {
            display: flex;
            align-items: flex-start;
            gap: 10px;
            text-align: left;
            min-height: 56px;
        }
    }

    .dot {
        flex: none;
        width: 8px;
        height: 8px;
        margin-top: 7px;
        border-radius: 999px;
        background: var(--olive);
    }

    .step-text {
        display: grid;
        gap: 3px;

        strong {
            font-size: 14px;
            font-weight: 600;
            color: var(--fg);
        }

        small {
            font-size: 13px;
            line-height: 1.45;
            color: var(--fg-subtle);
        }
    }

    @media (max-width: 780px) {
        .sync-screen {
            padding: 16px;
        }

        .sync-shell {
            grid-template-columns: 1fr;
        }

        .sync-command {
            min-height: 360px;
        }

        h1 {
            font-size: 32px;
        }

        .sync-cta {
            width: 100%;
        }
    }
</style>
