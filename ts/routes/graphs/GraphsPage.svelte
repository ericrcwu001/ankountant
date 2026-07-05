<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { bridgeCommand } from "@tslib/bridgecommand";
    import type { Component } from "svelte";
    import { writable } from "svelte/store";

    import { pageTheme } from "$lib/sveltelib/theme";

    import RangeBox from "./RangeBox.svelte";
    import WithGraphData from "./WithGraphData.svelte";

    export let initialSearch: string;
    export let initialDays: number;

    const search = writable(initialSearch);
    const days = writable(initialDays);

    export let graphs: Component<any>[];
    /** See RangeBox */
    export let controller: Component<any> | null = RangeBox;

    function browserSearch(event: CustomEvent) {
        bridgeCommand(`browserSearch: ${$search} ${event.detail.query}`);
    }
</script>

<WithGraphData
    {search}
    {days}
    let:sourceData
    let:loading
    let:errorMessage
    let:prefs
    let:revlogRange
>
    {#if controller}
        <svelte:component this={controller} {search} {days} {loading} />
    {/if}

    <div class="graphs-container">
        {#if sourceData && revlogRange && prefs}
            {#each graphs as graph}
                <svelte:component
                    this={graph}
                    {sourceData}
                    {prefs}
                    {revlogRange}
                    nightMode={$pageTheme.isDark}
                    on:search={browserSearch}
                />
            {/each}
        {:else if !loading && errorMessage}
            <section class="graphs-error" data-testid="graphs-load-error" role="alert">
                <strong>Statistics unavailable</strong>
                <span>{errorMessage}</span>
            </section>
        {/if}
    </div>
    <div class="spacer"></div>
</WithGraphData>

<style lang="scss">
    .graphs-container {
        display: grid;
        gap: 1em;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        // required on Safari to stretch whole width
        width: calc(100vw - 3em);
        margin-left: 1em;
        margin-right: 1em;

        @media only screen and (max-width: 600px) {
            width: calc(100vw - 1rem);
            margin-left: 0.5rem;
            margin-right: 0.5rem;
        }

        @media only screen and (max-width: 1400px) {
            grid-template-columns: 1fr 1fr;
        }
        @media only screen and (max-width: 1200px) {
            grid-template-columns: 1fr;
        }
        @media only screen and (max-width: 600px) {
            font-size: 12px;
        }

        @media only print {
            // grid layout does not honor page-break-inside
            display: block;
            margin-top: 3em;
        }
    }

    .graphs-error {
        grid-column: 1 / -1;
        min-height: 12rem;
        display: grid;
        place-content: center;
        gap: 0.5rem;
        padding: 2rem;
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        background: var(--canvas-elevated);
        color: var(--fg);
        text-align: center;

        strong {
            font-size: var(--type-card-title-size);
            font-weight: var(--type-card-title-weight);
            line-height: var(--type-card-title-line);
        }

        span {
            max-width: 48rem;
            color: var(--fg-subtle);
        }
    }

    .spacer {
        height: 1.5em;
    }
</style>
