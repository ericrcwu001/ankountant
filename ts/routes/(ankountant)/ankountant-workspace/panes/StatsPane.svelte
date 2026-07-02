<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Workspace-pane wrapper around the statistics graphs. Mounts the same shared
Stats surface as the first-class ankountant-stats route; the graphs self-load
their own data, so no pane-level loader (PaneState) is needed here.
-->
<script lang="ts">
    import Stats from "../../ankountant-stats/Stats.svelte";
</script>

<Stats />
