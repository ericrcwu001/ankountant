<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

First-class Ankountant Stats destination. The graphs self-load their own data,
so (unlike the dashboard/tbs routes) there is no +page.ts loader — the shared
Stats surface is mounted directly.
-->
<script lang="ts">
    import Stats from "./Stats.svelte";
</script>

<Stats />
