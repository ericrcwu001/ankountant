<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { PageData } from "./$types";
    import TbsTab from "./TbsTab.svelte";

    export let data: PageData;
</script>

<TbsTab
    initialNoteId={data.noteId}
    initialModel={data.model}
    initialFields={data.fields}
    initialTags={data.tags}
/>
