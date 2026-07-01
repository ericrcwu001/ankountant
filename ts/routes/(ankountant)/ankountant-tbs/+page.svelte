<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TbsSurface from "./TbsSurface.svelte";

    export let data: PageData;
</script>

{#if data.model}
    <TbsSurface noteId={data.noteId} model={data.model} />
{:else}
    <p class="tbs-empty" data-testid="tbs-empty">
        No TBS task available yet. Load the FAR demo content from the Ankountant menu,
        then reopen TBS Practice.
    </p>
{/if}

<style lang="scss">
    .tbs-empty {
        margin: 2rem;
        color: var(--fg-subtle);
    }
</style>
