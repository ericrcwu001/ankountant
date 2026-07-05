// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { Preferences } from "@generated/anki/config_pb";
import { Preferences_Scheduling_NewReviewMix } from "@generated/anki/config_pb";
import { getExamDate, getPreferences, setExamDate, setPreferences } from "@generated/backend";

import { SUMMIT_SECTIONS } from "../ankountant-home/summit";

export const settingsSections = [
    {
        id: "study",
        title: "Study Schedule",
        body: "Day rollover, learning cutoff, and new-review ordering.",
    },
    {
        id: "review",
        title: "Review Session",
        body: "Answer buttons, audio behavior, limits, and FSRS runtime toggles.",
    },
    {
        id: "editing",
        title: "Editing",
        body: "Adding defaults, paste behavior, search defaults, and LaTeX rendering.",
    },
    {
        id: "backups",
        title: "Backups",
        body: "Automatic backup retention and minimum backup spacing.",
    },
    {
        id: "readiness",
        title: "Readiness",
        body: "CPA exam dates stored in sync-safe Ankountant settings notes.",
    },
    {
        id: "sync",
        title: "Sync",
        body: "Automatic sync, media sync cadence, custom server, and network timeout.",
    },
] as const;

export type SettingsSectionId = "overview" | (typeof settingsSections)[number]["id"];

export interface PreferencesDraft {
    scheduling: {
        rollover: number;
        learnAheadMins: number;
        newReviewMix: Preferences_Scheduling_NewReviewMix;
    };
    reviewing: {
        showAudioPlayButtons: boolean;
        interruptAudioWhenAnswering: boolean;
        showRemainingDueCounts: boolean;
        showIntervalsOnButtons: boolean;
        timeLimitMins: number;
        loadBalancerEnabled: boolean;
        fsrsShortTermWithStepsEnabled: boolean;
    };
    editing: {
        addingDefaultsToCurrentDeck: boolean;
        pasteImagesAsPng: boolean;
        pasteStripsFormatting: boolean;
        ignoreAccentsInSearch: boolean;
        renderLatex: boolean;
        defaultSearchText: string;
    };
    backups: {
        daily: number;
        weekly: number;
        monthly: number;
        minimumIntervalMins: number;
    };
}

export interface SyncSettings {
    autoSync: boolean;
    syncMedia: boolean;
    periodicSyncMediaMinutes: number;
    customSyncUrl: string;
    networkTimeout: number;
}

export function isSettingsSectionId(
    value: string,
): value is Exclude<SettingsSectionId, "overview"> {
    return settingsSections.some((section) => section.id === value);
}

export function settingsHref(section: SettingsSectionId): string {
    return section === "overview"
        ? "/ankountant-settings"
        : `/ankountant-settings/${section}`;
}

export function settingsTitle(section: SettingsSectionId): string {
    if (section === "overview") {
        return "Settings";
    }
    return sectionDefinition(section).title;
}

export function sectionDefinition(section: Exclude<SettingsSectionId, "overview">) {
    const definition = settingsSections.find((item) => item.id === section);
    if (!definition) {
        throw new Error(`Unknown settings section: ${section}`);
    }
    return definition;
}

export async function loadPreferencesDraft(): Promise<{
    preferences: Preferences;
    draft: PreferencesDraft;
}> {
    const preferences = await getPreferences({});
    return { preferences, draft: draftFromPreferences(preferences) };
}

export async function savePreferencesDraft(
    preferences: Preferences,
    draft: PreferencesDraft,
): Promise<Preferences> {
    applyDraftToPreferences(preferences, draft);
    await setPreferences(preferences);
    return preferences;
}

export async function loadExamDates(): Promise<Record<string, string>> {
    const entries = await Promise.all(
        SUMMIT_SECTIONS.map(
            async (section) =>
                [
                    section.code,
                    (await getExamDate({ section: section.code })).date,
                ] as const,
        ),
    );
    return Object.fromEntries(entries);
}

export async function saveExamDate(section: string, date: string): Promise<void> {
    await setExamDate({ section, date });
}

export async function loadSyncSettings(): Promise<SyncSettings> {
    const response = await fetchJson("getAnkountantSyncSettings", new Uint8Array());
    return decodeSyncSettings(response);
}

export async function saveSyncSettings(settings: SyncSettings): Promise<void> {
    await postBackend("setAnkountantSyncSettings", encodeJson(settings));
}

export function mixLabel(value: Preferences_Scheduling_NewReviewMix): string {
    switch (value) {
        case Preferences_Scheduling_NewReviewMix.DISTRIBUTE:
            return "Distribute new cards and reviews";
        case Preferences_Scheduling_NewReviewMix.REVIEWS_FIRST:
            return "Show reviews before new cards";
        case Preferences_Scheduling_NewReviewMix.NEW_FIRST:
            return "Show new cards before reviews";
        default:
            throw new Error(`Unknown new/review mix: ${value}`);
    }
}

function draftFromPreferences(preferences: Preferences): PreferencesDraft {
    const scheduling = requirePart(preferences.scheduling, "scheduling preferences");
    const reviewing = requirePart(preferences.reviewing, "review preferences");
    const editing = requirePart(preferences.editing, "editing preferences");
    const backups = requirePart(preferences.backups, "backup preferences");
    return {
        scheduling: {
            rollover: scheduling.rollover,
            learnAheadMins: Math.round(scheduling.learnAheadSecs / 60),
            newReviewMix: scheduling.newReviewMix,
        },
        reviewing: {
            showAudioPlayButtons: !reviewing.hideAudioPlayButtons,
            interruptAudioWhenAnswering: reviewing.interruptAudioWhenAnswering,
            showRemainingDueCounts: reviewing.showRemainingDueCounts,
            showIntervalsOnButtons: reviewing.showIntervalsOnButtons,
            timeLimitMins: Math.round(reviewing.timeLimitSecs / 60),
            loadBalancerEnabled: reviewing.loadBalancerEnabled,
            fsrsShortTermWithStepsEnabled: reviewing.fsrsShortTermWithStepsEnabled,
        },
        editing: {
            addingDefaultsToCurrentDeck: editing.addingDefaultsToCurrentDeck,
            pasteImagesAsPng: editing.pasteImagesAsPng,
            pasteStripsFormatting: editing.pasteStripsFormatting,
            ignoreAccentsInSearch: editing.ignoreAccentsInSearch,
            renderLatex: editing.renderLatex,
            defaultSearchText: editing.defaultSearchText,
        },
        backups: {
            daily: backups.daily,
            weekly: backups.weekly,
            monthly: backups.monthly,
            minimumIntervalMins: backups.minimumIntervalMins,
        },
    };
}

function applyDraftToPreferences(
    preferences: Preferences,
    draft: PreferencesDraft,
): void {
    const scheduling = requirePart(preferences.scheduling, "scheduling preferences");
    scheduling.rollover = draft.scheduling.rollover;
    scheduling.learnAheadSecs = draft.scheduling.learnAheadMins * 60;
    scheduling.newReviewMix = draft.scheduling.newReviewMix;

    const reviewing = requirePart(preferences.reviewing, "review preferences");
    reviewing.hideAudioPlayButtons = !draft.reviewing.showAudioPlayButtons;
    reviewing.interruptAudioWhenAnswering = draft.reviewing.interruptAudioWhenAnswering;
    reviewing.showRemainingDueCounts = draft.reviewing.showRemainingDueCounts;
    reviewing.showIntervalsOnButtons = draft.reviewing.showIntervalsOnButtons;
    reviewing.timeLimitSecs = draft.reviewing.timeLimitMins * 60;
    reviewing.loadBalancerEnabled = draft.reviewing.loadBalancerEnabled;
    reviewing.fsrsShortTermWithStepsEnabled = draft.reviewing.fsrsShortTermWithStepsEnabled;

    const editing = requirePart(preferences.editing, "editing preferences");
    editing.addingDefaultsToCurrentDeck = draft.editing.addingDefaultsToCurrentDeck;
    editing.pasteImagesAsPng = draft.editing.pasteImagesAsPng;
    editing.pasteStripsFormatting = draft.editing.pasteStripsFormatting;
    editing.ignoreAccentsInSearch = draft.editing.ignoreAccentsInSearch;
    editing.renderLatex = draft.editing.renderLatex;
    editing.defaultSearchText = draft.editing.defaultSearchText;

    const backups = requirePart(preferences.backups, "backup preferences");
    backups.daily = draft.backups.daily;
    backups.weekly = draft.backups.weekly;
    backups.monthly = draft.backups.monthly;
    backups.minimumIntervalMins = draft.backups.minimumIntervalMins;
}

function requirePart<T>(value: T | undefined, name: string): T {
    if (!value) {
        throw new Error(`Missing ${name}.`);
    }
    return value;
}

async function fetchJson(method: string, body: Uint8Array): Promise<unknown> {
    const text = await postBackend(method, body);
    if (text.length === 0) {
        throw new Error(`${method} did not return JSON.`);
    }
    return JSON.parse(text) as unknown;
}

async function postBackend(method: string, body: Uint8Array): Promise<string> {
    const result = await fetch(`/_anki/${method}`, {
        method: "POST",
        headers: { "Content-Type": "application/binary" },
        body,
    });
    if (!result.ok) {
        throw new Error(`${result.status}: ${await result.text()}`);
    }
    return await result.text();
}

function encodeJson(value: unknown): Uint8Array {
    return new TextEncoder().encode(JSON.stringify(value));
}

function decodeSyncSettings(value: unknown): SyncSettings {
    if (!isRecord(value)) {
        throw new Error("Sync settings response must be an object.");
    }
    return {
        autoSync: requireBoolean(value, "autoSync"),
        syncMedia: requireBoolean(value, "syncMedia"),
        periodicSyncMediaMinutes: requireNumber(value, "periodicSyncMediaMinutes"),
        customSyncUrl: requireString(value, "customSyncUrl"),
        networkTimeout: requireNumber(value, "networkTimeout"),
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireBoolean(value: Record<string, unknown>, key: string): boolean {
    const field = value[key];
    if (typeof field !== "boolean") {
        throw new Error(`${key} must be a boolean.`);
    }
    return field;
}

function requireNumber(value: Record<string, unknown>, key: string): number {
    const field = value[key];
    if (typeof field !== "number") {
        throw new Error(`${key} must be a number.`);
    }
    return field;
}

function requireString(value: Record<string, unknown>, key: string): string {
    const field = value[key];
    if (typeof field !== "string") {
        throw new Error(`${key} must be a string.`);
    }
    return field;
}
