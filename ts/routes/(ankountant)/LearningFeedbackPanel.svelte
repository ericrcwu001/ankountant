<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import type { LearningFeedbackPanelState } from "./learning-feedback";

    export let state: LearningFeedbackPanelState;
    export let retry: (() => void) | undefined = undefined;
</script>

<section
    class="learning-feedback"
    class:error={state.phase === "error"}
    data-testid="learning-feedback"
    aria-live="polite"
>
    {#if state.phase === "loading"}
        <div class="feedback-head">
            <span class="kicker">AI feedback</span>
            <h2>Reviewing your attempt</h2>
        </div>
        <p class="muted" data-testid="learning-feedback-loading">
            Generating grounded feedback from this item.
        </p>
    {:else if state.phase === "error"}
        <div class="feedback-head">
            <span class="kicker">AI feedback</span>
            <h2>Feedback unavailable</h2>
        </div>
        <p class="error-text" data-testid="learning-feedback-error">{state.message}</p>
        {#if retry}
            <button
                type="button"
                class="retry"
                data-testid="learning-feedback-retry"
                on:click={() => retry?.()}
            >
                Retry
            </button>
        {/if}
    {:else}
        <div class="feedback-head">
            <span class="kicker">AI feedback</span>
            <h2 data-testid="learning-feedback-title">{state.feedback.title}</h2>
        </div>
        <dl>
            <div>
                <dt>What to revisit</dt>
                <dd data-testid="learning-feedback-why-wrong">
                    {state.feedback.whyWrong}
                </dd>
            </div>
            <div>
                <dt>Correct approach</dt>
                <dd data-testid="learning-feedback-correct-approach">
                    {state.feedback.correctApproach}
                </dd>
            </div>
            <div>
                <dt>Remember</dt>
                <dd data-testid="learning-feedback-remember">
                    {state.feedback.remember}
                </dd>
            </div>
        </dl>
        {#if state.feedback.sourceIds.length > 0}
            <p class="sources" data-testid="learning-feedback-sources">
                <span>Sources</span>
                {state.feedback.sourceIds.join(", ")}
            </p>
        {/if}
    {/if}
</section>

<style lang="scss">
    .learning-feedback {
        display: grid;
        gap: var(--space-md);
        margin-top: var(--space-lg);
        padding: var(--space-lg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-left: 4px solid var(--accent);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
    }

    .learning-feedback.error {
        border-left-color: var(--fg-error);
    }

    .feedback-head {
        display: grid;
        gap: var(--space-xs);
    }

    .kicker,
    dt,
    .sources span {
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    h2 {
        margin: 0;
        font-size: 16px;
        line-height: 1.3;
        color: var(--fg);
    }

    dl {
        display: grid;
        gap: var(--space-md);
        margin: 0;
    }

    dt {
        margin: 0 0 var(--space-xs);
    }

    dd,
    .muted,
    .error-text,
    .sources {
        margin: 0;
        color: var(--fg-subtle);
        line-height: 1.5;
    }

    dd {
        color: var(--fg);
    }

    .error-text {
        color: var(--fg-error);
    }

    .sources {
        padding-top: var(--space-sm);
        border-top: 1px solid var(--border-subtle);
        font-size: 13px;
    }

    .sources span {
        margin-right: var(--space-xs);
    }

    .retry {
        justify-self: start;
        min-height: 36px;
        padding: 0 var(--space-lg);
        font: inherit;
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        cursor: pointer;
    }

    .retry:hover {
        color: var(--accent);
        border-color: var(--accent);
    }

    .retry:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
    }
</style>
