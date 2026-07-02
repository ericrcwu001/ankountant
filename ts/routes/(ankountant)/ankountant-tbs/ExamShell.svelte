<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The composite exam shell (ADR 0007). ONE surface with an INTERNAL split so the
work area and its references stay co-visible without depending on the user tiling
a second pane (C13; panes share no state). Left: requirement tabs + the shape's
response (default slot) with the confidence gate. Right: tabbed tools — the typed
Exhibits pane, the read-only Literature browser, and the ungraded scratch
spreadsheet. Section-agnostic: the same shell renders every shape for every CPA
section; the Literature tab is scoped to the note's section.
-->
<script lang="ts">
    import type { ConfidenceLevel } from "$lib/components/ConfidenceGate.svelte";
    import ConfidenceGate from "$lib/components/ConfidenceGate.svelte";

    import ExhibitsPane from "./ExhibitsPane.svelte";
    import type { TbsModel } from "./lib";
    import { paneExhibits } from "./lib";
    import LiteraturePane from "./LiteraturePane.svelte";
    import Spreadsheet from "./Spreadsheet.svelte";

    export let model: TbsModel;
    export let title: string;
    export let committed: ConfidenceLevel | null = null;
    export let onCommit: (level: ConfidenceLevel) => void = () => {};
    export let onCite: ((citation: string) => void) | undefined = undefined;

    type Tool = "exhibits" | "literature" | "scratch";
    export let defaultTool: Tool = "exhibits";

    let tool: Tool = defaultTool;
    $: exhibits = paneExhibits(model);

    const TOOLS: { id: Tool; label: string }[] = [
        { id: "exhibits", label: "Exhibits" },
        { id: "literature", label: "Literature" },
        { id: "scratch", label: "Scratchpad" },
    ];
</script>

<div
    class="exam-shell"
    data-testid="exam-shell"
    data-shape={model.shape}
    data-section={model.section}
>
    <header class="exam-head">
        <div class="title-row">
            <h1>{title}</h1>
            <span class="section-chip" data-testid="exam-section">{model.section}</span>
        </div>
        <!-- Requirement tabs (single requirement today; multi-part items add tabs). -->
        <div class="req-tabs" role="tablist" aria-label="Requirements">
            <button
                type="button"
                role="tab"
                class="req-tab active"
                aria-selected="true"
                data-testid="requirement-tab"
            >
                Requirement 1
            </button>
        </div>
        {#if model.prompt}
            <p class="prompt" data-testid="exam-prompt">{model.prompt}</p>
        {/if}
    </header>

    <div class="exam-body">
        <div class="exam-response" data-testid="exam-response">
            <div class="gate">
                <ConfidenceGate {committed} {onCommit} />
            </div>
            <slot />
        </div>

        <aside class="exam-tools" data-testid="exam-tools">
            <div class="tool-tabs" role="tablist" aria-label="Reference tools">
                {#each TOOLS as t (t.id)}
                    <button
                        type="button"
                        role="tab"
                        class="tool-tab"
                        class:active={tool === t.id}
                        aria-selected={tool === t.id}
                        data-testid="tool-tab-{t.id}"
                        on:click={() => (tool = t.id)}
                    >
                        {t.label}
                    </button>
                {/each}
            </div>

            <div class="tool-panel" role="tabpanel">
                {#if tool === "exhibits"}
                    <ExhibitsPane {exhibits} />
                {:else if tool === "literature"}
                    <LiteraturePane section={model.section} {onCite} />
                {:else}
                    <Spreadsheet />
                {/if}
            </div>
        </aside>
    </div>
</div>

<style lang="scss">
    .exam-shell {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        padding: var(--space-lg);
        color: var(--fg);
    }

    .exam-head {
        margin-bottom: var(--space-md);
    }

    .title-row {
        display: flex;
        align-items: center;
        gap: var(--space-sm);

        h1 {
            margin: 0;
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            letter-spacing: var(--type-section-heading-tracking);
            line-height: var(--type-section-heading-line);
        }
    }

    .section-chip {
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.04em;
        color: var(--accent);
        background: var(--accent-tint);
        border-radius: var(--border-radius);
        padding: 1px var(--space-sm);
    }

    .req-tabs {
        display: flex;
        gap: var(--space-xs);
        margin-top: var(--space-sm);
    }

    .req-tab {
        font: inherit;
        font-size: 13px;
        font-weight: 600;
        color: var(--fg-subtle);
        background: transparent;
        border: 0;
        border-bottom: 2px solid transparent;
        padding: var(--space-xs) var(--space-sm);

        &.active {
            color: var(--accent);
            border-bottom-color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .prompt {
        margin: var(--space-sm) 0 0;
        color: var(--fg-subtle);
        max-width: 66ch;
    }

    .exam-body {
        display: flex;
        gap: var(--space-lg);
        align-items: stretch;
        flex: 1;
        min-height: 0;
    }

    // Left: the work area. Its own scroll so the tools stay put (C13).
    .exam-response {
        flex: 3;
        min-width: 0;
        overflow: auto;
        display: flex;
        flex-direction: column;
        gap: var(--space-lg);
    }

    // Right: tabbed reference tools, co-visible with the response.
    .exam-tools {
        flex: 2;
        min-width: 0;
        display: flex;
        flex-direction: column;
        min-height: 0;
        border-left: 1px solid var(--border-subtle);
        padding-left: var(--space-lg);
    }

    .tool-tabs {
        display: flex;
        gap: var(--space-xs);
        margin-bottom: var(--space-md);
    }

    .tool-tab {
        font: inherit;
        font-size: 13px;
        font-weight: 500;
        color: var(--fg-subtle);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-md);
        cursor: pointer;

        &.active {
            color: var(--accent);
            border-color: var(--accent);
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    .tool-panel {
        flex: 1;
        min-height: 0;
        overflow: hidden;
        display: flex;
        flex-direction: column;
    }

    .gate {
        margin-bottom: var(--space-xs);
    }
</style>
