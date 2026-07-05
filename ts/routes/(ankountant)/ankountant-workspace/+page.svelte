<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import Workspace from "./Workspace.svelte";

    export let data: PageData;
</script>

{#key data.launchKey}
    <Workspace initialSurface={data.initial} singleSurface={data.single} />
{/key}
