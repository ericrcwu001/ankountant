<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { invalidateAll } from "$app/navigation";

    export let testId: string;
    export let eyebrow: string;
    export let title: string;
    export let message: string;

    let retrying = false;

    async function retry(): Promise<void> {
        if (retrying) {
            return;
        }
        retrying = true;
        try {
            await invalidateAll();
        } finally {
            retrying = false;
        }
    }
</script>

<section class="error" data-testid={testId} role="alert">
    <div class="state-mark" aria-hidden="true">!</div>
    <p class="eyebrow">{eyebrow}</p>
    <h1>{title}</h1>
    <p class="message">{message}</p>
    <div class="actions">
        <button type="button" class="primary" on:click={retry} disabled={retrying}>
            {retrying ? "Retrying..." : "Retry"}
        </button>
        <a href="/ankountant-tbs">Browse simulations</a>
        <a href="/ankountant-dashboard">View readiness evidence</a>
    </div>
</section>

<style lang="scss">
    .error {
        min-height: calc(100vh - 4rem);
        display: grid;
        justify-items: center;
        align-content: center;
        gap: var(--space-sm);
        margin: 0;
        padding: var(--space-xxl);
        background: var(--canvas);
        color: var(--fg);
        text-align: center;

        h1 {
            margin: 0;
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            line-height: var(--type-section-heading-line);
            letter-spacing: 0;
        }
    }

    .state-mark {
        display: grid;
        place-items: center;
        width: 44px;
        height: 44px;
        border: 1px solid color-mix(in srgb, var(--fg-error) 30%, transparent);
        border-radius: 50%;
        background: color-mix(in srgb, var(--fg-error) 10%, var(--canvas-elevated));
        color: var(--fg-error);
        font-size: 22px;
        font-weight: 750;
        line-height: 1;
    }

    .eyebrow {
        margin: 0;
        color: var(--fg-faint);
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        line-height: var(--type-micro-line);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
    }

    .message {
        max-width: 58ch;
        margin: 0;
        color: var(--fg-subtle);
        font-size: var(--type-callout-size);
        line-height: var(--type-callout-line);
    }

    .actions {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: var(--space-sm);
        margin-top: var(--space-sm);

        :is(a, button) {
            min-height: 40px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 0 var(--space-lg);
            border: 1px solid var(--border-subtle);
            border-radius: var(--border-radius);
            background: var(--canvas-elevated);
            color: var(--fg);
            font: inherit;
            font-size: var(--type-caption-size);
            font-weight: 700;
            text-decoration: none;
            cursor: pointer;

            &:hover:not(:disabled) {
                background: var(--canvas-inset);
            }

            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: 2px;
            }

            &:disabled {
                color: var(--fg-faint);
                cursor: default;
            }

            &.primary {
                border-color: color-mix(in srgb, var(--accent) 24%, transparent);
                background: var(--accent-tint);
                color: var(--accent);
            }
        }
    }
</style>
