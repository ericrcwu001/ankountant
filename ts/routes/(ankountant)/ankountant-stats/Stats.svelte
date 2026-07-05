<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type {
        GraphsResponse_Buttons_ButtonCounts,
        GraphsResponse,
        GraphsResponse_CardCounts_Counts,
        GraphsResponse_ReviewCountsAndTimes_Reviews,
    } from "@generated/anki/stats_pb";
    import { bridgeCommand } from "@tslib/bridgecommand";
    import type { Component } from "svelte";
    import { writable } from "svelte/store";

    import { pageTheme } from "$lib/sveltelib/theme";

    import AddedGraph from "../../graphs/AddedGraph.svelte";
    import ButtonsGraph from "../../graphs/ButtonsGraph.svelte";
    import CalendarGraph from "../../graphs/CalendarGraph.svelte";
    import CardCounts from "../../graphs/CardCounts.svelte";
    import DifficultyGraph from "../../graphs/DifficultyGraph.svelte";
    import EaseGraph from "../../graphs/EaseGraph.svelte";
    import FutureDue from "../../graphs/FutureDue.svelte";
    import HourGraph from "../../graphs/HourGraph.svelte";
    import IntervalsGraph from "../../graphs/IntervalsGraph.svelte";
    import RetrievabilityGraph from "../../graphs/RetrievabilityGraph.svelte";
    import ReviewsGraph from "../../graphs/ReviewsGraph.svelte";
    import StabilityGraph from "../../graphs/StabilityGraph.svelte";
    import TrueRetention from "../../graphs/TrueRetention.svelte";
    import WithGraphData from "../../graphs/WithGraphData.svelte";

    type Scope = "deck" | "collection" | "custom";
    type History = "year" | "all";

    const search = writable("");
    const days = writable(365);
    const numberFormat = new Intl.NumberFormat();

    let scope: Scope = "collection";
    let history: History = "year";
    let customSearch = "";

    interface ReviewSummary {
        reviewed: number;
        reviewedMillis: number;
        accuracy: number | null;
        newCount: number;
        learningCount: number;
        reviewCount: number;
        againCount: number;
    }

    const charts: Component<any>[] = [
        CardCounts,
        CalendarGraph,
        ReviewsGraph,
        FutureDue,
        IntervalsGraph,
        EaseGraph,
        HourGraph,
        ButtonsGraph,
        AddedGraph,
        TrueRetention,
        RetrievabilityGraph,
        StabilityGraph,
        DifficultyGraph,
    ];

    function setScope(nextScope: Scope): void {
        scope = nextScope;
        if (nextScope === "deck") {
            customSearch = "deck:current";
            search.set("deck:current");
        } else if (nextScope === "collection") {
            customSearch = "";
            search.set("");
        } else {
            search.set(customSearch.trim());
        }
    }

    function updateCustomSearch(): void {
        scope = "custom";
        search.set(customSearch.trim());
    }

    function setHistory(nextHistory: History): void {
        history = nextHistory;
        days.set(nextHistory === "year" ? 365 : 0);
    }

    function browserSearch(event: CustomEvent): void {
        bridgeCommand(`browserSearch: ${$search} ${event.detail.query}`);
    }

    function openImport(): void {
        bridgeCommand("ankountant:import");
    }

    function emptyAnalyticsTitle(): string {
        return scope === "collection"
            ? "No analytics evidence yet"
            : "No analytics evidence in this view";
    }

    function emptyAnalyticsDescription(): string {
        return scope === "collection"
            ? "Import a study package, then review cards to fill retention, due load, and progress."
            : "This view has no cards or review history. Show the whole collection or import a study package to start tracking evidence.";
    }

    function formatNumber(value: number): string {
        return numberFormat.format(value);
    }

    function formatPercent(value: number | null): string {
        if (value === null) {
            return "--";
        }
        return `${Math.round(value * 100)}%`;
    }

    function formatMinutes(milliseconds: number): string {
        const minutes = Math.max(0, Math.round(milliseconds / 60000));
        if (minutes < 60) {
            return `${minutes}m`;
        }
        const hours = Math.floor(minutes / 60);
        const remainingMinutes = minutes % 60;
        return remainingMinutes ? `${hours}h ${remainingMinutes}m` : `${hours}h`;
    }

    function activeCards(data: GraphsResponse): number {
        const counts = data.cardCounts!.excludingInactive!;
        return (
            counts.newCards +
            counts.learn +
            counts.relearn +
            counts.young +
            counts.mature
        );
    }

    function matureCardCount(data: GraphsResponse): number {
        return data.cardCounts!.excludingInactive!.mature;
    }

    function reviewedToday(data: GraphsResponse): number {
        return data.today!.answerCount;
    }

    function dailyLoad(data: GraphsResponse): number {
        return data.futureDue!.dailyLoad;
    }

    function masteredFraction(data: GraphsResponse): number {
        const active = activeCards(data);
        if (!active) {
            return 0;
        }
        return data.cardCounts!.excludingInactive!.mature / active;
    }

    function retentionFraction(data: GraphsResponse): number | null {
        const retention = data.trueRetention!.month!;
        const passed = retention.youngPassed + retention.maturePassed;
        const failed = retention.youngFailed + retention.matureFailed;
        const total = passed + failed;
        return total ? passed / total : null;
    }

    function reviewSummary(data: GraphsResponse): ReviewSummary {
        const summary: ReviewSummary = {
            reviewed: 0,
            reviewedMillis: 0,
            accuracy: null,
            newCount: 0,
            learningCount: 0,
            reviewCount: 0,
            againCount: 0,
        };
        for (const reviews of Object.values(data.reviews!.count)) {
            summary.newCount += reviews.learn;
            summary.learningCount += reviews.relearn + reviews.filtered;
            summary.reviewCount += reviews.young + reviews.mature;
            summary.reviewed += reviewTotal(reviews);
        }
        for (const reviewTime of Object.values(data.reviews!.time)) {
            summary.reviewedMillis += reviewTotal(reviewTime);
        }

        const buttons = historyButtonCounts(data);
        const buttonTotal = buttonCountTotal(buttons);
        summary.againCount = buttonAt(buttons.learning, 0) +
            buttonAt(buttons.young, 0) +
            buttonAt(buttons.mature, 0);
        if (buttonTotal > 0) {
            summary.accuracy = (buttonTotal - summary.againCount) / buttonTotal;
        }
        return summary;
    }

    function historyButtonCounts(data: GraphsResponse): GraphsResponse_Buttons_ButtonCounts {
        return history === "year" ? data.buttons!.oneYear! : data.buttons!.allTime!;
    }

    function buttonCountTotal(counts: GraphsResponse_Buttons_ButtonCounts): number {
        return totalCount(counts.learning) + totalCount(counts.young) + totalCount(counts.mature);
    }

    function totalCount(values: number[]): number {
        return values.reduce((total, value) => total + value, 0);
    }

    function buttonAt(values: number[], index: number): number {
        return values[index] ?? 0;
    }

    function analyticsEvidenceIsEmpty(data: GraphsResponse): boolean {
        return (
            cardCountTotal(data.cardCounts!.excludingInactive!) === 0 &&
            Object.values(data.added!.added).every((value) => value === 0) &&
            Object.values(data.futureDue!.futureDue).every((value) => value === 0) &&
            data.today!.answerCount === 0 &&
            Object.values(data.reviews!.count).every(
                (reviews) => reviewTotal(reviews) === 0,
            )
        );
    }

    function cardCountTotal(counts: GraphsResponse_CardCounts_Counts): number {
        return (
            counts.newCards +
            counts.learn +
            counts.relearn +
            counts.young +
            counts.mature +
            counts.suspended +
            counts.buried
        );
    }

    function reviewTotal(reviews: GraphsResponse_ReviewCountsAndTimes_Reviews): number {
        return (
            reviews.learn +
            reviews.relearn +
            reviews.young +
            reviews.mature +
            reviews.filtered
        );
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
    let:retry
>
    <section class="stats-surface" data-testid="stats">
        <header class="stats-header">
            <div>
                <p class="eyebrow">Analytics</p>
                <h1>Statistics</h1>
            </div>
            <div class="load-state" class:loading aria-live="polite">
                {loading ? "Updating" : "Current"}
            </div>
        </header>

        <div class="toolbar" aria-label="Statistics filters">
            <div class="chip-group" role="group" aria-label="Scope">
                <button
                    type="button"
                    class:active={scope === "deck"}
                    aria-pressed={scope === "deck"}
                    on:click={() => setScope("deck")}
                >
                    Deck
                </button>
                <button
                    type="button"
                    class:active={scope === "collection"}
                    aria-pressed={scope === "collection"}
                    on:click={() => setScope("collection")}
                >
                    Collection
                </button>
            </div>
            <label class="search-field">
                <span>Search</span>
                <input
                    id="statisticsSearchText"
                    type="text"
                    bind:value={customSearch}
                    on:focus={() => (scope = "custom")}
                    on:change={updateCustomSearch}
                    placeholder="deck:current"
                />
            </label>
            <div class="chip-group" role="group" aria-label="History">
                <button
                    type="button"
                    class:active={history === "year"}
                    aria-pressed={history === "year"}
                    on:click={() => setHistory("year")}
                >
                    12 months
                </button>
                <button
                    type="button"
                    class:active={history === "all"}
                    aria-pressed={history === "all"}
                    on:click={() => setHistory("all")}
                >
                    All history
                </button>
            </div>
        </div>

        {#if sourceData && revlogRange && prefs}
            {#if analyticsEvidenceIsEmpty(sourceData)}
                <section
                    class="stats-state empty"
                    data-testid="stats-empty"
                    aria-label="No analytics evidence"
                >
                    <div class="state-mark" aria-hidden="true">0</div>
                    <p class="eyebrow">No evidence yet</p>
                    <h2>{emptyAnalyticsTitle()}</h2>
                    <p>{emptyAnalyticsDescription()}</p>
                    <div class="state-actions">
                        {#if scope !== "collection"}
                            <button
                                type="button"
                                class="state-action"
                                on:click={() => setScope("collection")}
                            >
                                Show collection
                            </button>
                        {/if}
                        <button
                            type="button"
                            class="state-action primary"
                            on:click={openImport}
                        >
                            Import package
                        </button>
                    </div>
                </section>
            {:else}
                <section class="overview-card" aria-label="Statistics overview">
                    <div
                        class="progress-ring"
                        style:--progress={masteredFraction(sourceData)}
                        aria-label={`Progress ${Math.round(masteredFraction(sourceData) * 100)} percent mastered`}
                    >
                        <span>{Math.round(masteredFraction(sourceData) * 100)}</span>
                        <small>%</small>
                    </div>

                    <div class="overview-copy">
                        <p class="eyebrow">Progress</p>
                        <h2>{formatPercent(masteredFraction(sourceData))} mastered</h2>
                        <p>
                            {formatNumber(activeCards(sourceData))} active cards in this view
                        </p>
                    </div>

                    <div class="overview-metrics">
                        <div>
                            <span>{formatNumber(matureCardCount(sourceData))}</span>
                            <span class="metric-label">Cards mastered</span>
                        </div>
                        <div>
                            <span>{formatPercent(retentionFraction(sourceData))}</span>
                            <span class="metric-label">Month retention</span>
                        </div>
                        <div>
                            <span>{formatNumber(reviewedToday(sourceData))}</span>
                            <span class="metric-label">Reviewed today</span>
                        </div>
                        <div>
                            <span>{formatNumber(dailyLoad(sourceData))}</span>
                            <span class="metric-label">Daily load</span>
                        </div>
                    </div>
                </section>

                {@const summary = reviewSummary(sourceData)}
                <section
                    class="today-card"
                    aria-label="Review summary"
                    data-testid="stats-review-summary"
                >
                    <div>
                        <span data-testid="stats-reviewed">
                            {formatNumber(summary.reviewed)}
                        </span>
                        <span class="metric-label">Reviewed</span>
                    </div>
                    <div>
                        <span data-testid="stats-time">
                            {formatMinutes(summary.reviewedMillis)}
                        </span>
                        <span class="metric-label">Time</span>
                    </div>
                    <div>
                        <span class="positive" data-testid="stats-accuracy">
                            {formatPercent(summary.accuracy)}
                        </span>
                        <span class="metric-label">Accuracy</span>
                    </div>
                    <div>
                        <span data-testid="stats-new-count">
                            {formatNumber(summary.newCount)}
                        </span>
                        <span class="metric-label">New</span>
                    </div>
                    <div>
                        <span data-testid="stats-learning-count">
                            {formatNumber(summary.learningCount)}
                        </span>
                        <span class="metric-label">Learning</span>
                    </div>
                    <div>
                        <span data-testid="stats-review-count">
                            {formatNumber(summary.reviewCount)}
                        </span>
                        <span class="metric-label">Review</span>
                    </div>
                    <div>
                        <span class="danger" data-testid="stats-again-count">
                            {formatNumber(summary.againCount)}
                        </span>
                        <span class="metric-label">Again</span>
                    </div>
                </section>

                <section class="charts" aria-label="Statistics charts">
                    {#each charts as chart}
                        <svelte:component
                            this={chart}
                            {sourceData}
                            {prefs}
                            {revlogRange}
                            nightMode={$pageTheme.isDark}
                            on:search={browserSearch}
                        />
                    {/each}
                </section>
            {/if}
        {:else if !loading && errorMessage}
            <section
                class="stats-state error"
                data-testid="stats-load-error"
                role="alert"
            >
                <div class="state-mark" aria-hidden="true">!</div>
                <p class="eyebrow">Statistics unavailable</p>
                <h2>We couldn't load this evidence.</h2>
                <p>{errorMessage}</p>
                <button type="button" class="retry-button" on:click={retry}>
                    Retry
                </button>
            </section>
        {:else}
            <section
                class="overview-card skeleton"
                aria-label="Loading statistics"
                data-testid="stats-loading"
            >
                <div class="skeleton-ring"></div>
                <div class="skeleton-copy">
                    <span></span>
                    <strong></strong>
                    <p></p>
                </div>
            </section>
        {/if}
    </section>
</WithGraphData>

<style lang="scss">
    .stats-surface {
        min-height: 100vh;
        padding: var(--space-xxl);
        background: var(--canvas);
        color: var(--fg);
    }

    .stats-header {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: var(--space-xl);
        max-width: 1420px;
        margin: 0 auto var(--space-xl);

        h1 {
            margin: 0;
            font-size: 44px;
            font-weight: 650;
            line-height: 1;
            letter-spacing: 0;
        }
    }

    .eyebrow {
        margin: 0 0 var(--space-xs);
        color: var(--fg-faint);
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        line-height: var(--type-micro-line);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
    }

    .load-state {
        display: inline-flex;
        align-items: center;
        gap: var(--space-sm);
        color: var(--fg-faint);
        font-size: var(--type-caption-size);
        font-weight: 600;
        font-variant-numeric: tabular-nums;

        &::before {
            content: "";
            width: 9px;
            height: 9px;
            border-radius: 50%;
            background: var(--fg-disabled);
        }

        &.loading::before {
            background: var(--accent);
            box-shadow: 0 0 0 5px color-mix(in srgb, var(--accent) 14%, transparent);
        }
    }

    .toolbar {
        position: sticky;
        top: 0;
        z-index: 2;
        display: flex;
        align-items: center;
        gap: var(--space-md);
        max-width: 1420px;
        margin: 0 auto var(--space-xl);
        padding: var(--space-sm);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        background: color-mix(in srgb, var(--canvas-elevated) 88%, transparent);
        box-shadow: var(--elevation-e1);
        backdrop-filter: blur(16px);
    }

    .chip-group {
        display: inline-flex;
        align-items: center;
        gap: var(--space-xs);
        padding: var(--space-xs);
        border-radius: var(--border-radius-medium);
        background: var(--canvas);

        button {
            min-height: 34px;
            margin: 0;
            padding: 0 var(--space-md);
            border: 1px solid transparent;
            border-radius: var(--border-radius);
            background: transparent;
            color: var(--fg-subtle);
            box-shadow: none;
            font-size: var(--type-caption-size);
            font-weight: 650;
            white-space: nowrap;

            &:hover {
                color: var(--fg);
                background: var(--canvas-inset);
            }

            &.active {
                color: var(--accent);
                background: var(--accent-tint);
                border-color: color-mix(in srgb, var(--accent) 16%, transparent);
            }
        }
    }

    .search-field {
        flex: 1;
        min-width: 180px;
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        height: 42px;
        padding: 0 var(--space-md);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        background: var(--canvas-inset);
        color: var(--fg-faint);
        font-size: var(--type-caption-size);
        font-weight: 600;

        input {
            flex: 1;
            min-width: 0;
            height: 100%;
            border: 0;
            background: transparent;
            color: var(--fg);
            font: inherit;
            font-weight: 500;

            &:focus {
                border-color: transparent;
                outline: 0;
            }
        }
    }

    .overview-card,
    .today-card,
    .charts,
    .stats-state {
        max-width: 1420px;
        margin-left: auto;
        margin-right: auto;
    }

    .overview-card {
        display: grid;
        grid-template-columns: auto minmax(220px, 0.95fr) minmax(380px, 1.7fr);
        align-items: center;
        gap: var(--space-xl);
        margin-bottom: var(--space-lg);
        padding: var(--space-xl);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        background:
            radial-gradient(circle at 0% 0%, rgba(31, 58, 95, 0.08), transparent 34rem),
            linear-gradient(135deg, var(--canvas-elevated), var(--canvas));
        box-shadow: var(--elevation-e1);
    }

    .progress-ring {
        --ring-size: 132px;
        display: grid;
        place-items: center;
        width: var(--ring-size);
        height: var(--ring-size);
        border-radius: 50%;
        background:
            radial-gradient(circle, var(--canvas-elevated) 0 58%, transparent 59%),
            conic-gradient(
                var(--accent) calc(var(--progress) * 1turn),
                var(--border-subtle) 0
            );
        color: var(--fg);
        font-variant-numeric: tabular-nums;

        span {
            margin-top: 10px;
            font-size: 36px;
            font-weight: 700;
            line-height: 0.85;
        }

        small {
            color: var(--fg-faint);
            font-size: var(--type-caption-size);
            font-weight: 650;
        }
    }

    .overview-copy {
        min-width: 0;

        h2 {
            margin: 0;
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            line-height: var(--type-section-heading-line);
            letter-spacing: 0;
        }

        p:not(.eyebrow) {
            margin: var(--space-xs) 0 0;
            color: var(--fg-faint);
            font-size: var(--type-callout-size);
            line-height: var(--type-callout-line);
        }
    }

    .overview-metrics {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        overflow: hidden;
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        background: var(--canvas-elevated);

        div {
            display: flex;
            flex-direction: column;
            gap: var(--space-xs);
            padding: var(--space-md);
            border-right: 1px solid var(--border-subtle);

            &:last-child {
                border-right: 0;
            }
        }

        span {
            font-size: 22px;
            font-weight: 700;
            line-height: 1.1;
            font-variant-numeric: tabular-nums;
        }

        .metric-label {
            color: var(--fg-faint);
            font-size: var(--type-caption-size);
            line-height: 1.2;
        }
    }

    .today-card {
        display: grid;
        grid-template-columns: repeat(7, minmax(0, 1fr));
        margin-bottom: var(--space-xl);
        padding: var(--space-lg);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        background: var(--canvas-elevated);
        box-shadow: var(--elevation-e1);

        div {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: var(--space-xs);
            min-width: 0;
            padding: var(--space-sm);
        }

        span {
            font-size: 24px;
            font-weight: 700;
            line-height: 1.1;
            font-variant-numeric: tabular-nums;
        }

        .metric-label {
            color: var(--fg-faint);
            font-size: var(--type-caption-size);
        }

        .positive {
            color: var(--fg-success);
        }

        .danger {
            color: var(--fg-error);
        }
    }

    .charts {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--space-lg);
        align-items: start;
        padding-bottom: var(--space-xxl);
    }

    .charts :global(.container) {
        min-width: 0;
        min-height: 360px;
        padding: var(--space-lg);
        border-color: var(--border-subtle);
        border-radius: var(--border-radius-large);
        background: var(--canvas-elevated);
        box-shadow: var(--elevation-e1);
    }

    .charts :global(.container h1) {
        margin: 0 0 var(--space-md);
        padding: 0 0 var(--space-sm);
        border-bottom-color: var(--border-subtle);
        font-size: var(--type-section-heading-size);
        font-weight: var(--type-section-heading-weight);
        line-height: var(--type-section-heading-line);
        letter-spacing: 0;
    }

    .charts :global(.graph) {
        min-height: 260px;
    }

    .charts :global(svg) {
        width: 100%;
        max-height: 260px;
    }

    .charts :global(.subtitle),
    .charts :global(label),
    .charts :global(table) {
        color: var(--fg-subtle);
        font-size: var(--type-caption-size);
    }

    .charts :global(input[type="radio"]),
    .charts :global(input[type="checkbox"]) {
        accent-color: var(--accent);
    }

    .charts :global(button) {
        margin: 0;
    }

    .stats-state {
        min-height: 280px;
        display: grid;
        justify-items: center;
        align-content: center;
        gap: var(--space-sm);
        padding: var(--space-xl);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-large);
        background: var(--canvas-elevated);
        box-shadow: var(--elevation-e1);
        text-align: center;

        h2 {
            margin: 0;
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            line-height: var(--type-section-heading-line);
            letter-spacing: 0;
        }

        p:not(.eyebrow) {
            max-width: 54ch;
            margin: 0;
            color: var(--fg-subtle);
            font-size: var(--type-callout-size);
            line-height: var(--type-callout-line);
        }

        &.error .state-mark {
            color: var(--fg-error);
            background: color-mix(in srgb, var(--fg-error) 12%, transparent);
            border-color: color-mix(in srgb, var(--fg-error) 22%, transparent);
        }
    }

    .retry-button {
        min-height: 40px;
        margin-top: var(--space-sm);
        padding: 0 var(--space-lg);
        border: 1px solid color-mix(in srgb, var(--accent) 24%, transparent);
        border-radius: var(--border-radius);
        background: var(--accent-tint);
        color: var(--accent);
        font-size: var(--type-caption-size);
        font-weight: 700;

        &:hover {
            background: color-mix(in srgb, var(--accent) 16%, transparent);
        }
    }

    .state-actions {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: var(--space-sm);
        margin-top: var(--space-sm);
    }

    .state-action {
        min-height: 40px;
        padding: 0 var(--space-lg);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius);
        background: var(--canvas-elevated);
        color: var(--fg);
        font-size: var(--type-caption-size);
        font-weight: 700;

        &:hover {
            background: var(--canvas-inset);
        }

        &.primary {
            border-color: color-mix(in srgb, var(--accent) 24%, transparent);
            background: var(--accent-tint);
            color: var(--accent);

            &:hover {
                background: color-mix(in srgb, var(--accent) 16%, transparent);
            }
        }
    }

    .state-mark {
        display: grid;
        place-items: center;
        width: 44px;
        height: 44px;
        border: 1px solid var(--border-subtle);
        border-radius: 50%;
        font-size: 22px;
        font-weight: 750;
        line-height: 1;
    }

    .skeleton {
        min-height: 220px;
    }

    .skeleton-ring,
    .skeleton-copy span,
    .skeleton-copy strong,
    .skeleton-copy p {
        display: block;
        border-radius: var(--border-radius);
        background: linear-gradient(
            90deg,
            var(--border-subtle),
            var(--canvas-inset),
            var(--border-subtle)
        );
        background-size: 220% 100%;
        animation: shimmer 1.4s ease-in-out infinite;
    }

    .skeleton-ring {
        width: 132px;
        height: 132px;
        border-radius: 50%;
    }

    .skeleton-copy {
        display: grid;
        gap: var(--space-sm);

        span {
            width: 80px;
            height: 14px;
        }

        strong {
            width: 220px;
            height: 30px;
        }

        p {
            width: 260px;
            height: 18px;
        }
    }

    @keyframes shimmer {
        from {
            background-position: 100% 0;
        }
        to {
            background-position: -100% 0;
        }
    }

    @media only screen and (max-width: 1180px) {
        .overview-card {
            grid-template-columns: auto minmax(0, 1fr);
        }

        .overview-metrics {
            grid-column: 1 / -1;
        }
    }

    @media only screen and (max-width: 900px) {
        .stats-surface {
            padding: var(--space-xl);
        }

        .stats-header h1 {
            font-size: 38px;
        }

        .toolbar {
            position: static;
            flex-wrap: wrap;
        }

        .search-field {
            order: 3;
            flex-basis: 100%;
        }

        .today-card {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .charts {
            grid-template-columns: 1fr;
        }
    }

    @media only screen and (max-width: 640px) {
        .stats-surface {
            padding: var(--space-lg);
        }

        .stats-header {
            align-items: flex-start;
            flex-direction: column;
            gap: var(--space-md);

            h1 {
                font-size: 34px;
            }
        }

        .overview-card {
            grid-template-columns: 1fr;
        }

        .progress-ring {
            justify-self: center;
        }

        .overview-metrics {
            grid-template-columns: 1fr 1fr;

            div:nth-child(2) {
                border-right: 0;
            }

            div:nth-child(-n + 2) {
                border-bottom: 1px solid var(--border-subtle);
            }
        }
    }
</style>
