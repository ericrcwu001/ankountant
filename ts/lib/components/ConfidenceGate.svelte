<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

B1 (F011) — the pre-reveal confidence commitment. The reveal/answer is blocked
until the learner commits one of three discrete levels (Guess / Unsure /
Confident). The three levels are keyboard-selectable (1/2/3). Emits the chosen
level via the `commit` callback; the parent is responsible for actually
revealing only after a commit (A41–A43).
-->
<script lang="ts" context="module">
    export type ConfidenceLevel = "Guess" | "Unsure" | "Confident";

    export const CONFIDENCE_LEVELS: ConfidenceLevel[] = [
        "Guess",
        "Unsure",
        "Confident",
    ];
</script>

<script lang="ts">
    export let committed: ConfidenceLevel | null = null;
    /** Called once, when a level is first committed. */
    export let onCommit: (level: ConfidenceLevel) => void = () => {};

    function choose(level: ConfidenceLevel): void {
        if (committed !== null) {
            return;
        }
        committed = level;
        onCommit(level);
    }

    function onKeydown(event: KeyboardEvent): void {
        if (committed !== null) {
            return;
        }
        const idx = ["1", "2", "3"].indexOf(event.key);
        if (idx >= 0) {
            event.preventDefault();
            choose(CONFIDENCE_LEVELS[idx]);
        }
    }
</script>

<svelte:window on:keydown={onKeydown} />

<div
    class="confidence-gate"
    data-testid="confidence-gate"
    data-committed={committed ?? ""}
>
    <p class="prompt">How confident are you? (pick before revealing)</p>
    <div class="levels" role="group" aria-label="confidence">
        {#each CONFIDENCE_LEVELS as level, i (level)}
            <button
                type="button"
                class="level"
                class:selected={committed === level}
                data-testid="confidence-{level.toLowerCase()}"
                data-level={level}
                disabled={committed !== null && committed !== level}
                on:click={() => choose(level)}
            >
                <kbd>{i + 1}</kbd>
                {level}
            </button>
        {/each}
    </div>
</div>

<style lang="scss">
    .confidence-gate {
        margin: 0;

        // Promote the prompt so the gate reads as a required decision, not a
        // toolbar (Ledger §5).
        .prompt {
            margin: 0 0 var(--space-sm);
            font-weight: 600;
        }

        // Three equal-weight options on a shared row — no default, no leading
        // size/colour (Ledger §5); "Guess" is visually as safe to pick as any.
        .levels {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: var(--space-sm);
        }

        .level {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: var(--space-xs);
            min-height: 44px; // comfortable target (C7)
            padding: var(--space-sm) var(--space-md);
            font: inherit; // 16px, overrides the global 12/13px button size (C1)
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border-control); // clears 3:1 (C3)
            border-radius: var(--border-radius);
            cursor: pointer;

            &:hover:not(:disabled) {
                border-color: var(--accent);
            }

            // Selection is brand chrome (navy), never a semantic hue.
            &.selected {
                font-weight: 600;
                color: var(--accent);
                border-color: var(--accent);
                background: var(--accent-tint);
            }

            &:disabled {
                opacity: 0.55;
                cursor: default;
            }

            // Visible 2px navy focus ring + offset (never a glow); beats the
            // global `outline: none !important` on buttons.
            &:focus-visible {
                outline: 2px solid var(--accent) !important;
                outline-offset: 2px;
            }

            kbd {
                display: inline-grid;
                place-items: center;
                min-width: 20px;
                height: 20px;
                padding: 0 4px;
                font-family: var(--font-mono);
                font-size: 12px;
                color: var(--fg-subtle);
                background: var(--canvas);
                border: 1px solid var(--border-subtle);
                border-radius: 6px;
            }
        }
    }
</style>
