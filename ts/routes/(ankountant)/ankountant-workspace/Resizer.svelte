<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The draggable gutter between a split's two children. Reports a new ratio as the
pointer moves (measured against the split container it sits inside); also
keyboard-operable as an ARIA separator. Purpose-built for the ratio model rather
than reusing resizable.ts, whose px/store API does not fit a fractional BSP.
-->
<script lang="ts">
    import { getContext } from "svelte";

    import type { WorkspaceActions } from "./context";
    import { WORKSPACE_ACTIONS } from "./context";
    import type { Path, SplitDir } from "./workspace-layout";

    export let dir: SplitDir;
    export let path: Path;
    export let ratio: number;

    const actions = getContext<WorkspaceActions>(WORKSPACE_ACTIONS);
    let active = false;

    function onPointerDown(event: PointerEvent): void {
        event.preventDefault();
        const container = (event.currentTarget as HTMLElement).parentElement;
        if (!container) {
            return;
        }
        // The split container keeps its size while only the child ratios change,
        // so a rect captured once is valid for the whole drag.
        const rect = container.getBoundingClientRect();
        active = true;
        document.body.style.userSelect = "none";

        const move = (ev: PointerEvent): void => {
            const next =
                dir === "row"
                    ? (ev.clientX - rect.left) / rect.width
                    : (ev.clientY - rect.top) / rect.height;
            actions.setRatio(path, next);
        };
        const up = (): void => {
            active = false;
            document.body.style.userSelect = "";
            window.removeEventListener("pointermove", move);
            window.removeEventListener("pointerup", up);
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
    }

    function onKeyDown(event: KeyboardEvent): void {
        const step = 0.02;
        const decrease = dir === "row" ? "ArrowLeft" : "ArrowUp";
        const increase = dir === "row" ? "ArrowRight" : "ArrowDown";
        let delta = 0;
        if (event.key === decrease) {
            delta = -step;
        } else if (event.key === increase) {
            delta = step;
        }
        if (delta !== 0) {
            event.preventDefault();
            actions.setRatio(path, ratio + delta);
        }
    }
</script>

<!-- A resize separator is legitimately focusable + operable, which the generic
     non-interactive-element a11y rules don't model. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex a11y_no_noninteractive_element_interactions -->
<div
    class="resizer {dir}"
    class:active
    role="separator"
    tabindex="0"
    aria-orientation={dir === "row" ? "vertical" : "horizontal"}
    aria-label="Resize panes"
    on:pointerdown={onPointerDown}
    on:keydown={onKeyDown}
></div>

<style lang="scss">
    .resizer {
        position: relative;
        flex: 0 0 auto;
        background: transparent;
        z-index: 1;

        &.row {
            width: var(--space-sm);
            cursor: col-resize;
        }

        &.col {
            height: var(--space-sm);
            cursor: row-resize;
        }

        // Hairline centered in the gutter; brightens to accent on hover/drag.
        &::after {
            content: "";
            position: absolute;
            background: var(--border-subtle);
            transition: background var(--motion-fast) ease;
        }

        &.row::after {
            top: 0;
            bottom: 0;
            left: 50%;
            width: 1px;
            transform: translateX(-0.5px);
        }

        &.col::after {
            left: 0;
            right: 0;
            top: 50%;
            height: 1px;
            transform: translateY(-0.5px);
        }

        &:hover::after,
        &.active::after {
            background: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: -2px;
        }
    }

    @media (prefers-reduced-motion: reduce) {
        .resizer::after {
            transition: none;
        }
    }
</style>
