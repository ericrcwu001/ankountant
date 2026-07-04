<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";

    import type { PageData } from "./$types";
    import Dashboard from "./Dashboard.svelte";

    export let data: PageData;

    function selectSection(section: string): void {
        goto(`/ankountant-dashboard?section=${section}`);
    }
</script>

<Dashboard
    readiness={data.readiness}
    examDate={data.examDate}
    section={data.section}
    onSelectSection={selectSection}
/>
