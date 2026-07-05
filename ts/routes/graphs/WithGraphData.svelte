<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { GraphsResponse } from "@generated/anki/stats_pb";
    import {
        getGraphPreferences,
        graphs,
        setGraphPreferences,
    } from "@generated/backend";
    import type { Writable } from "svelte/store";

    import { autoSavingPrefs } from "$lib/sveltelib/preferences";

    import { readableBackendError } from "../(ankountant)/backendError";
    import { daysToRevlogRange, type GraphPrefs } from "./graph-helpers";

    export let search: Writable<string>;
    export let days: Writable<number>;

    let prefs: GraphPrefs | null = null;
    let sourceData: GraphsResponse | null = null;
    let errorMessage = "";
    let loading = true;
    $: updateSourceData($search, $days);

    void loadPrefs();

    async function loadPrefs(): Promise<void> {
        loading = true;
        errorMessage = "";
        try {
            prefs = await autoSavingPrefs(
                () => getGraphPreferences({}),
                setGraphPreferences,
            );
            await updateSourceData($search, $days);
        } catch (error) {
            prefs = null;
            sourceData = null;
            errorMessage = readableBackendError(
                error,
                "Statistics preferences could not be loaded.",
            );
            loading = false;
        }
    }

    async function updateSourceData(search: string, days: number): Promise<void> {
        if (!prefs) {
            return;
        }
        loading = true;
        errorMessage = "";
        try {
            sourceData = await graphs({ search, days }, { alertOnError: false });
        } catch (error) {
            sourceData = null;
            errorMessage = readableBackendError(
                error,
                "Statistics could not be loaded.",
            );
        } finally {
            loading = false;
        }
    }

    function retry(): void {
        if (prefs) {
            void updateSourceData($search, $days);
        } else {
            void loadPrefs();
        }
    }

    $: revlogRange = daysToRevlogRange($days);
</script>

<slot {revlogRange} {prefs} {sourceData} {loading} {errorMessage} {retry} />
