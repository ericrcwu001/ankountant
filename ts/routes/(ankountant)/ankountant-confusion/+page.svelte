<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import ConfusionMode from "./ConfusionMode.svelte";

    export let data: PageData;
</script>

<ConfusionMode items={data.items} section={data.section} />
