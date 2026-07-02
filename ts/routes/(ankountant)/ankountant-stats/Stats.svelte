<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Shared Ankountant Stats surface: the statistics graphs. Reuses the existing
graphs Svelte components (ts/routes/graphs/) — the same GraphsPage + RangeBox
controller the standalone /graphs route uses — so a single surface backs both
the first-class `ankountant-stats` route and the workspace Stats pane. The
STATISTICS/SCHEDULING i18n modules are loaded by the root layout's
setupGlobalI18n(), so no extra setup is needed here.
-->
<script lang="ts">
    import AddedGraph from "../../graphs/AddedGraph.svelte";
    import ButtonsGraph from "../../graphs/ButtonsGraph.svelte";
    import CalendarGraph from "../../graphs/CalendarGraph.svelte";
    import CardCounts from "../../graphs/CardCounts.svelte";
    import DifficultyGraph from "../../graphs/DifficultyGraph.svelte";
    import EaseGraph from "../../graphs/EaseGraph.svelte";
    import FutureDue from "../../graphs/FutureDue.svelte";
    import GraphsPage from "../../graphs/GraphsPage.svelte";
    import HourGraph from "../../graphs/HourGraph.svelte";
    import IntervalsGraph from "../../graphs/IntervalsGraph.svelte";
    import RangeBox from "../../graphs/RangeBox.svelte";
    import RetrievabilityGraph from "../../graphs/RetrievabilityGraph.svelte";
    import ReviewsGraph from "../../graphs/ReviewsGraph.svelte";
    import StabilityGraph from "../../graphs/StabilityGraph.svelte";
    import TodayStats from "../../graphs/TodayStats.svelte";
    import TrueRetention from "../../graphs/TrueRetention.svelte";

    // Same set + order as the standalone /graphs route.
    const graphs = [
        TodayStats,
        FutureDue,
        CalendarGraph,
        ReviewsGraph,
        CardCounts,
        IntervalsGraph,
        StabilityGraph,
        EaseGraph,
        DifficultyGraph,
        RetrievabilityGraph,
        TrueRetention,
        HourGraph,
        ButtonsGraph,
        AddedGraph,
    ];
</script>

<div class="stats-surface" data-testid="stats">
    <GraphsPage
        {graphs}
        initialSearch="deck:current"
        initialDays={365}
        controller={RangeBox}
    />
</div>

<style lang="scss">
    // The graphs page centers itself; give it a little breathing room whether it
    // fills the shell body or a workspace tile.
    .stats-surface {
        padding: var(--space-sm) var(--space-md);
    }
</style>
