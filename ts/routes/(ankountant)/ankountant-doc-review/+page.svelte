<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import DocReviewSurface from "./DocReviewSurface.svelte";

    export let data: PageData;
</script>

{#if data.model}
    {#key data.noteId}
        <DocReviewSurface
            noteId={data.noteId}
            model={data.model}
            fields={data.fields}
            tags={data.tags}
        />
    {/key}
{:else}
    <p class="empty" data-testid="docreview-empty">
        No document-review task was found in this profile.
    </p>
{/if}

<style lang="scss">
    .empty {
        margin: 2rem;
        color: var(--fg-subtle);
    }
</style>
