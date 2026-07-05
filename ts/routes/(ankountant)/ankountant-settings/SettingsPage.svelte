<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { onMount } from "svelte";

    import { goto } from "$app/navigation";
    import {
        Preferences_Scheduling_NewReviewMix,
        type Preferences,
    } from "@generated/anki/config_pb";

    import { DEFAULT_SUMMIT_SECTION, SUMMIT_SECTIONS } from "../ankountant-home/summit";
    import {
        loadExamDates,
        loadPreferencesDraft,
        loadSyncSettings,
        mixLabel,
        saveExamDate,
        savePreferencesDraft,
        saveSyncSettings,
        settingsHref,
        settingsSections,
        settingsTitle,
        type PreferencesDraft,
        type SettingsSectionId,
        type SyncSettings,
    } from "./settings-model";

    export let section: SettingsSectionId;

    let preferences: Preferences | undefined;
    let draft: PreferencesDraft | undefined;
    let syncSettings: SyncSettings | undefined;
    let examDates: Record<string, string> = {};
    let selectedExamSection = DEFAULT_SUMMIT_SECTION;
    let phase: "loading" | "ready" | "error" = "loading";
    let saveState: "idle" | "saving" | "saved" | "error" = "idle";
    let message = "";

    $: title = settingsTitle(section);

    onMount(() => {
        void load();
    });

    async function load(): Promise<void> {
        phase = "loading";
        message = "";
        try {
            const [preferencesData, syncData, dateData] = await Promise.all([
                loadPreferencesDraft(),
                loadSyncSettings(),
                loadExamDates(),
            ]);
            preferences = preferencesData.preferences;
            draft = preferencesData.draft;
            syncSettings = syncData;
            examDates = dateData;
            phase = "ready";
        } catch (error) {
            phase = "error";
            message = errorMessage(error);
        }
    }

    async function savePreferences(): Promise<void> {
        if (!preferences || !draft) {
            throw new Error("Preferences are not loaded.");
        }
        await saveWithState(async () => {
            preferences = await savePreferencesDraft(
                preferences as Preferences,
                draft as PreferencesDraft,
            );
        });
    }

    async function saveSync(): Promise<void> {
        if (!syncSettings) {
            throw new Error("Sync settings are not loaded.");
        }
        await saveWithState(async () => saveSyncSettings(syncSettings as SyncSettings));
    }

    async function saveReadiness(): Promise<void> {
        const date = examDates[selectedExamSection] ?? "";
        await saveWithState(async () => saveExamDate(selectedExamSection, date));
    }

    async function saveWithState(action: () => Promise<void>): Promise<void> {
        saveState = "saving";
        message = "";
        try {
            await action();
            saveState = "saved";
        } catch (error) {
            saveState = "error";
            message = errorMessage(error);
        }
    }

    function navigate(next: SettingsSectionId): void {
        goto(settingsHref(next));
    }

    function errorMessage(error: unknown): string {
        return error instanceof Error ? error.message : String(error);
    }
</script>

<div class="settings-screen" data-testid="settings">
    <div class="settings-shell">
        <header class="settings-header">
            <p class="eyebrow">Workspace controls</p>
            <h1>{title}</h1>
            <p>
                Settings are edited in Svelte and saved through the backend APIs that
                own the underlying collection or profile state.
            </p>
        </header>

        <nav class="settings-nav" aria-label="Settings sections">
            <button
                type="button"
                class:active={section === "overview"}
                aria-current={section === "overview" ? "page" : undefined}
                onclick={() => navigate("overview")}
            >
                Overview
            </button>
            {#each settingsSections as item (item.id)}
                <button
                    type="button"
                    class:active={section === item.id}
                    aria-current={section === item.id ? "page" : undefined}
                    onclick={() => navigate(item.id)}
                >
                    {item.title}
                </button>
            {/each}
        </nav>

        {#if phase === "loading"}
            <section class="settings-panel" data-testid="settings-loading">
                <h2>Loading settings</h2>
                <p>Reading collection and profile settings.</p>
            </section>
        {:else if phase === "error"}
            <section class="settings-panel error" data-testid="settings-error">
                <h2>Settings unavailable</h2>
                <p>{message}</p>
                <button type="button" class="primary-action" onclick={load}>
                    Retry
                </button>
            </section>
        {:else if draft && syncSettings}
            {#if section === "overview"}
                <section class="settings-grid" aria-label="Settings sections">
                    {#each settingsSections as item (item.id)}
                        <button
                            type="button"
                            class="section-card"
                            data-testid={`settings-card-${item.id}`}
                            onclick={() => navigate(item.id)}
                        >
                            <span>{item.title}</span>
                            <small>{item.body}</small>
                        </button>
                    {/each}
                </section>
            {:else if section === "study"}
                <section class="settings-panel" data-testid="settings-study">
                    <div class="panel-heading">
                        <h2>Study Schedule</h2>
                        <button
                            type="button"
                            class="primary-action"
                            onclick={savePreferences}
                        >
                            Save study settings
                        </button>
                    </div>
                    <label>
                        <span>Rollover hour</span>
                        <input
                            type="number"
                            min="0"
                            max="23"
                            bind:value={draft.scheduling.rollover}
                        />
                    </label>
                    <label>
                        <span>Learn ahead minutes</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={draft.scheduling.learnAheadMins}
                        />
                    </label>
                    <label>
                        <span>New/review order</span>
                        <select bind:value={draft.scheduling.newReviewMix}>
                            <option
                                value={Preferences_Scheduling_NewReviewMix.DISTRIBUTE}
                            >
                                {mixLabel(
                                    Preferences_Scheduling_NewReviewMix.DISTRIBUTE,
                                )}
                            </option>
                            <option
                                value={Preferences_Scheduling_NewReviewMix.REVIEWS_FIRST}
                            >
                                {mixLabel(
                                    Preferences_Scheduling_NewReviewMix.REVIEWS_FIRST,
                                )}
                            </option>
                            <option
                                value={Preferences_Scheduling_NewReviewMix.NEW_FIRST}
                            >
                                {mixLabel(
                                    Preferences_Scheduling_NewReviewMix.NEW_FIRST,
                                )}
                            </option>
                        </select>
                    </label>
                </section>
            {:else if section === "review"}
                <section class="settings-panel" data-testid="settings-review">
                    <div class="panel-heading">
                        <h2>Review Session</h2>
                        <button
                            type="button"
                            class="primary-action"
                            onclick={savePreferences}
                        >
                            Save review settings
                        </button>
                    </div>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.showAudioPlayButtons}
                        />
                        <span>Show audio replay buttons</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.interruptAudioWhenAnswering}
                        />
                        <span>Interrupt audio when answering</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.showRemainingDueCounts}
                        />
                        <span>Show remaining due counts</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.showIntervalsOnButtons}
                        />
                        <span>Show intervals on answer buttons</span>
                    </label>
                    <label>
                        <span>Answer time limit minutes</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={draft.reviewing.timeLimitMins}
                        />
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.loadBalancerEnabled}
                        />
                        <span>Enable load balancer</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.reviewing.fsrsShortTermWithStepsEnabled}
                        />
                        <span>Enable FSRS short-term with steps</span>
                    </label>
                </section>
            {:else if section === "editing"}
                <section class="settings-panel" data-testid="settings-editing">
                    <div class="panel-heading">
                        <h2>Editing</h2>
                        <button
                            type="button"
                            class="primary-action"
                            onclick={savePreferences}
                        >
                            Save editing settings
                        </button>
                    </div>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.editing.addingDefaultsToCurrentDeck}
                        />
                        <span>Add cards to the current deck by default</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.editing.pasteImagesAsPng}
                        />
                        <span>Paste images as PNG</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.editing.pasteStripsFormatting}
                        />
                        <span>Strip formatting when pasting text</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.editing.ignoreAccentsInSearch}
                        />
                        <span>Ignore accents in search</span>
                    </label>
                    <label class="check-row">
                        <input
                            type="checkbox"
                            bind:checked={draft.editing.renderLatex}
                        />
                        <span>Render LaTeX previews</span>
                    </label>
                    <label>
                        <span>Default browser search</span>
                        <input
                            type="text"
                            bind:value={draft.editing.defaultSearchText}
                        />
                    </label>
                </section>
            {:else if section === "backups"}
                <section class="settings-panel" data-testid="settings-backups">
                    <div class="panel-heading">
                        <h2>Backups</h2>
                        <button
                            type="button"
                            class="primary-action"
                            onclick={savePreferences}
                        >
                            Save backup settings
                        </button>
                    </div>
                    <label>
                        <span>Daily backups to keep</span>
                        <input type="number" min="0" bind:value={draft.backups.daily} />
                    </label>
                    <label>
                        <span>Weekly backups to keep</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={draft.backups.weekly}
                        />
                    </label>
                    <label>
                        <span>Monthly backups to keep</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={draft.backups.monthly}
                        />
                    </label>
                    <label>
                        <span>Minimum minutes between backups</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={draft.backups.minimumIntervalMins}
                        />
                    </label>
                </section>
            {:else if section === "readiness"}
                <section class="settings-panel" data-testid="settings-readiness">
                    <div class="panel-heading">
                        <h2>Readiness</h2>
                        <button
                            type="button"
                            class="primary-action"
                            onclick={saveReadiness}
                        >
                            Save exam date
                        </button>
                    </div>
                    <label>
                        <span>CPA section</span>
                        <select bind:value={selectedExamSection}>
                            {#each SUMMIT_SECTIONS as item (item.code)}
                                <option value={item.code}>
                                    {item.code} - {item.name}
                                </option>
                            {/each}
                        </select>
                    </label>
                    <label>
                        <span>Exam date</span>
                        <input
                            type="date"
                            bind:value={examDates[selectedExamSection]}
                        />
                    </label>
                </section>
            {:else if section === "sync"}
                <section class="settings-panel" data-testid="settings-sync">
                    <div class="panel-heading">
                        <h2>Sync</h2>
                        <button type="button" class="primary-action" onclick={saveSync}>
                            Save sync settings
                        </button>
                    </div>
                    <label class="check-row">
                        <input type="checkbox" bind:checked={syncSettings.autoSync} />
                        <span>Sync when opening and closing the profile</span>
                    </label>
                    <label class="check-row">
                        <input type="checkbox" bind:checked={syncSettings.syncMedia} />
                        <span>Sync audio and images</span>
                    </label>
                    <label>
                        <span>Periodic media sync minutes</span>
                        <input
                            type="number"
                            min="0"
                            bind:value={syncSettings.periodicSyncMediaMinutes}
                        />
                    </label>
                    <label>
                        <span>Custom sync server URL</span>
                        <input type="url" bind:value={syncSettings.customSyncUrl} />
                    </label>
                    <label>
                        <span>Network timeout seconds</span>
                        <input
                            type="number"
                            min="1"
                            bind:value={syncSettings.networkTimeout}
                        />
                    </label>
                </section>
            {/if}

            <p
                class="save-status"
                aria-live="polite"
                data-testid="settings-save-status"
            >
                {#if saveState === "saving"}
                    Saving...
                {:else if saveState === "saved"}
                    Saved.
                {:else if saveState === "error"}
                    {message}
                {/if}
            </p>
        {/if}
    </div>
</div>

<style lang="scss">
    .settings-screen {
        --accent: #24546a;
        --accent-strong: #193c4d;
        --olive: #526640;
        --amber: #a65f28;
        --fg: #172033;
        --fg-subtle: #536174;
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

    .settings-shell {
        width: 100%;
        max-width: 1080px;
        margin: 0 auto;
        display: grid;
        grid-template-columns: 240px minmax(0, 1fr);
        grid-template-areas:
            "header header"
            "nav content"
            "nav status";
        gap: 16px;
    }

    .settings-header,
    .settings-nav,
    .settings-panel,
    .section-card {
        box-sizing: border-box;
        background: var(--panel);
        border: 1px solid var(--border-subtle);
        border-radius: 8px;
        box-shadow: 0 12px 32px rgba(37, 45, 55, 0.07);
    }

    .settings-header {
        grid-area: header;
        padding: 28px 32px;
        border-top: 5px solid var(--accent);
    }

    .eyebrow {
        margin: 0 0 12px;
        color: var(--amber);
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0;
        text-transform: uppercase;
    }

    h1,
    h2,
    p {
        margin: 0;
    }

    h1 {
        font-family: "Iowan Old Style", Georgia, serif;
        font-size: 64px;
        line-height: 0.98;
        font-weight: 600;
        color: var(--accent-strong);
    }

    .settings-header p {
        max-width: 50rem;
        margin-top: 14px;
        color: var(--fg-subtle);
        font-size: 18px;
        line-height: 1.5;
    }

    .settings-nav {
        grid-area: nav;
        align-self: start;
        padding: 8px;
        display: grid;
        gap: 4px;
    }

    .settings-nav button {
        width: 100%;
        min-height: 42px;
        padding: 0 12px;
        border: 1px solid transparent;
        border-radius: 7px;
        background: transparent;
        color: var(--fg-subtle);
        font-size: 14px;
        font-weight: 750;
        text-align: left;
        box-shadow: none;
        cursor: pointer;
    }

    .settings-nav button:hover,
    .settings-nav button.active {
        background: #edf2ec;
        border-color: #d7dfd2;
        color: var(--accent-strong);
    }

    .settings-grid {
        grid-area: content;
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
    }

    .section-card {
        min-height: 168px;
        padding: 22px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        gap: 18px;
        color: var(--fg);
        text-align: left;
        cursor: pointer;
    }

    .section-card:hover {
        border-color: #b9c8b2;
    }

    .section-card span,
    .settings-panel h2 {
        color: var(--accent-strong);
        font-size: 24px;
        line-height: 1.15;
        font-weight: 750;
    }

    .section-card small {
        color: var(--fg-subtle);
        font-size: 15px;
        line-height: 1.45;
    }

    .settings-panel {
        grid-area: content;
        padding: 26px;
        display: grid;
        gap: 18px;
    }

    .settings-panel.error {
        border-top: 5px solid #a94b3f;
    }

    .panel-heading {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding-bottom: 8px;
        border-bottom: 1px solid var(--border-subtle);
    }

    label {
        display: grid;
        grid-template-columns: minmax(190px, 0.42fr) minmax(220px, 0.58fr);
        align-items: center;
        gap: 18px;
        color: var(--fg-subtle);
        font-size: 15px;
        line-height: 1.4;
    }

    label span {
        color: var(--fg);
        font-weight: 700;
    }

    .check-row {
        grid-template-columns: 22px minmax(0, 1fr);
    }

    input,
    select {
        width: 100%;
        min-height: 40px;
        box-sizing: border-box;
        border: 1px solid #c8d2c4;
        border-radius: 7px;
        background: #fff;
        color: var(--fg);
        font-size: 15px;
    }

    input[type="checkbox"] {
        width: 18px;
        min-height: 18px;
        accent-color: var(--accent);
    }

    input:not([type="checkbox"]),
    select {
        padding: 0 11px;
    }

    input:focus,
    select:focus,
    button:focus-visible {
        outline: 2px solid var(--amber);
        outline-offset: 2px;
    }

    .primary-action {
        min-height: 42px;
        padding: 0 18px;
        border: 1px solid var(--accent-strong);
        border-radius: 8px;
        background: var(--accent-strong);
        color: #fff;
        font-size: 14px;
        font-weight: 750;
        box-shadow: none;
        cursor: pointer;
        white-space: nowrap;
    }

    .primary-action:hover {
        background: #102f3f;
    }

    .save-status {
        grid-area: status;
        min-height: 22px;
        color: var(--olive);
        font-size: 14px;
        font-weight: 750;
    }

    @media (max-width: 900px) {
        .settings-shell {
            grid-template-columns: 1fr;
            grid-template-areas:
                "header"
                "nav"
                "content"
                "status";
        }

        .settings-nav {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .settings-grid {
            grid-template-columns: 1fr;
        }
    }

    @media (max-width: 620px) {
        .settings-screen {
            padding: 16px;
        }

        .settings-header {
            padding: 24px;
        }

        h1 {
            font-size: 46px;
        }

        .settings-nav,
        label,
        .panel-heading {
            grid-template-columns: 1fr;
        }

        .panel-heading {
            align-items: stretch;
        }
    }
</style>
