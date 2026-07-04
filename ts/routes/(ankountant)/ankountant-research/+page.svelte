<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import ResearchSurface from "./ResearchSurface.svelte";

    export let data: PageData;
</script>

{#if data.model}
    {#key data.noteId}
        <ResearchSurface
            noteId={data.noteId}
            model={data.model}
            fields={data.fields}
            tags={data.tags}
        />
    {/key}
{:else}
    <p class="empty" data-testid="research-empty">
        No research task was found in this profile.
    </p>
{/if}

<style lang="scss">
    .empty {
        margin: 2rem;
        color: var(--fg-subtle);
    }
</style>
