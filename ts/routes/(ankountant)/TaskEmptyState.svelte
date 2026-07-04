<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { bridgeCommand } from "@tslib/bridgecommand";

    export let testId: string;
    export let eyebrow: string;
    export let title: string;
    export let description: string;

    function openImport(): void {
        bridgeCommand("ankountant:import");
    }
</script>

<section class="empty" data-testid={testId}>
    <div class="state-mark" aria-hidden="true">0</div>
    <p class="eyebrow">{eyebrow}</p>
    <h1>{title}</h1>
    <p>{description}</p>
    <div class="actions">
        <button type="button" class="primary" on:click={openImport}>
            Import package
        </button>
        <a href="/ankountant-tbs">Browse simulations</a>
        <a href="/ankountant-dashboard">View readiness evidence</a>
    </div>
</section>

<style lang="scss">
    .empty {
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

        p:not(.eyebrow) {
            max-width: 52ch;
            margin: 0;
            color: var(--fg-subtle);
            font-size: var(--type-callout-size);
            line-height: var(--type-callout-line);
        }
    }

    .state-mark {
        display: grid;
        place-items: center;
        width: 44px;
        height: 44px;
        border: 1px solid var(--border-subtle);
        border-radius: 50%;
        background: var(--canvas-elevated);
        color: var(--fg-faint);
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

            &:hover {
                background: var(--canvas-inset);
            }

            &.primary {
                border-color: color-mix(in srgb, var(--accent) 24%, transparent);
                background: var(--accent-tint);
                color: var(--accent);
            }
        }
    }
</style>
