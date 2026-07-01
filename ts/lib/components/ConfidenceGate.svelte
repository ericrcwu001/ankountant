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
        margin: 0.75rem 0;

        .levels {
            display: flex;
            gap: 0.5rem;
        }

        .level {
            padding: 0.4rem 0.9rem;
            cursor: pointer;

            &.selected {
                font-weight: bold;
                outline: 2px solid var(--fg-link, #08c);
            }

            kbd {
                opacity: 0.6;
                margin-right: 0.3rem;
            }
        }
    }
</style>
