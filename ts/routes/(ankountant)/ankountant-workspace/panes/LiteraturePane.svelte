<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Standalone, read-only authoritative-literature browser as a tileable workspace
pane (agent 12): the corpus is reference-only, so it needs no cross-pane state
and is genuinely useful tiled beside a research/doc-review/dashboard pane. A
section switcher scopes the bundled corpus (ADR 0008 / D10).
-->
<script lang="ts">
    import LiteratureBrowser from "../../ankountant-tbs/LiteraturePane.svelte";
    import { SECTIONS } from "../../ankountant-tbs/lib";

    let section = "FAR";
</script>

<div class="literature-pane" data-testid="literature-pane">
    <div class="pane-toolbar">
        <label class="section-pick">
            <span class="sr-only">Section</span>
            <select bind:value={section} data-testid="literature-section">
                {#each SECTIONS as s (s)}
                    <option value={s}>{s}</option>
                {/each}
            </select>
        </label>
    </div>
    <div class="pane-body">
        {#key section}
            <LiteratureBrowser {section} />
        {/key}
    </div>
</div>

<style lang="scss">
    .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    .literature-pane {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        padding: var(--space-md);
        gap: var(--space-sm);
    }

    .pane-toolbar {
        display: flex;
        justify-content: flex-end;
    }

    .section-pick select {
        font: inherit;
        font-size: 13px;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-sm);

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }
    }

    .pane-body {
        flex: 1;
        min-height: 0;
    }
</style>
