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

    const steps = [
        {
            title: "Uploads your latest work",
            body: "New cards and reviews on this Mac are sent to your sync server.",
        },
        {
            title: "Pulls in your other devices",
            body: "Changes made on your phone or another machine are merged back in.",
        },
        {
            title: "First run asks a couple of questions",
            body: "You may be prompted to log in, then to choose an upload/download direction.",
        },
    ];
</script>

<div class="sync-screen" data-testid="sync">
    <div class="panel">
        <div class="badge" class:spin={triggered} aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 12a9 9 0 0 1-9 9 9 9 0 0 1-7.4-3.9" />
                <path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 7.4 3.9" />
                <path d="M21 4v4h-4" />
                <path d="M3 20v-4h4" />
            </svg>
        </div>

        <h1>Sync</h1>
        <p class="lead">
            Keep this Mac and your other devices in step through your sync server.
        </p>

        <button type="button" class="sync-cta" onclick={syncNow}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
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
                &nbsp;
            {/if}
        </p>

        <ul class="steps">
            {#each steps as step (step.title)}
                <li>
                    <span class="dot" aria-hidden="true"></span>
                    <span class="step-text">
                        <strong>{step.title}</strong>
                        <small>{step.body}</small>
                    </span>
                </li>
            {/each}
        </ul>

        <p class="foot">
            Your sync server must be running and reachable for this to work.
        </p>
    </div>
</div>

<style lang="scss">
    .sync-screen {
        --accent: #0e3a66;
        --fg: #0f2744;
        --fg-subtle: #51657e;
        --fg-faint: #7e8da1;
        --panel: rgba(255, 255, 255, 0.92);
        --border-subtle: #d8e2ef;

        display: grid;
        place-items: center;
        box-sizing: border-box;
        height: 100vh;
        min-height: 100vh;
        padding: var(--space-xl);
        overflow: auto;
        background: radial-gradient(120% 80% at 70% 0%, #eef4fb 0%, #eef0f4 55%, #eef0f4 100%);
        color: var(--fg);
    }

    .panel {
        width: 100%;
        max-width: 460px;
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
        padding: var(--space-xl);
        background: var(--panel);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        box-shadow: var(--elevation-e1);
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
        margin: var(--space-lg) 0 0;
        font-size: 26px;
        font-weight: 700;
        letter-spacing: 0;
        color: var(--fg);
    }

    .lead {
        margin: var(--space-xs) 0 0;
        max-width: 34ch;
        font-size: 14.5px;
        line-height: 1.5;
        color: var(--fg-subtle);
    }

    .sync-cta {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: var(--space-sm);
        margin-top: var(--space-lg);
        padding: 12px 24px;
        font-size: 15px;
        font-weight: 600;
        color: #fff;
        background: var(--accent);
        border: 1px solid var(--accent);
        border-radius: 10px;
        cursor: pointer;

        svg {
            width: 18px;
            height: 18px;
        }

        &:hover {
            background: #123f70;
        }

        &:focus-visible {
            outline: 2px solid #7ea6d6;
            outline-offset: 2px;
        }
    }

    .status {
        min-height: 18px;
        margin: var(--space-sm) 0 0;
        font-size: 13px;
        font-weight: 500;
        color: var(--accent);
    }

    .steps {
        width: 100%;
        list-style: none;
        margin: var(--space-lg) 0 0;
        padding: var(--space-lg) 0 0;
        border-top: 1px solid var(--border-subtle);
        display: flex;
        flex-direction: column;
        gap: var(--space-md);

        li {
            display: flex;
            align-items: flex-start;
            gap: var(--space-sm);
            text-align: left;
        }
    }

    .dot {
        flex: none;
        width: 8px;
        height: 8px;
        margin-top: 7px;
        border-radius: 999px;
        background: var(--accent);
        opacity: 0.55;
    }

    .step-text {
        display: grid;
        gap: 2px;

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

    .foot {
        margin: var(--space-lg) 0 0;
        font-size: 12.5px;
        color: var(--fg-faint);
    }
</style>
