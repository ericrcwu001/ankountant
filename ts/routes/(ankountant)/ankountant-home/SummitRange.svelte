<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The Home "summit": each CPA section as a peak on a shared CPA 0–99 axis with a
dashed pass line at 75. A faded navy Wilson band spans low–high with a neutral
midpoint marker, and a neutral triangle glyph encodes above/below. Abstaining
sections render as a dashed "unproven" ghost at the base (no height). Mirrors the
iOS RangeHeroChart; the section list below owns navigation. Ledger tokens only —
navy is chrome/band.
-->
<script lang="ts">
    import { CPA_PASS_SCORE } from "../ankountant-dashboard/lib";
    import { yForScore, type SectionPeak } from "./summit";

    export let peaks: SectionPeak[] = [];

    // SVG user-space geometry (the <svg> scales to its container via viewBox).
    const W = 520;
    const TOP = 14;
    const PLOT_H = 180;
    const BASE = TOP + PLOT_H; // y at CPA score 0
    const VH = BASE + 30;

    // Score (0–99) → SVG y (top-down): 99 sits at the top, 0 at the base.
    // Delegates to the pure, unit-tested yForScore so geometry can't drift.
    function y(score: number): number {
        return yForScore(score, TOP, PLOT_H);
    }

    // Fixed reference line (never changes); only the peaks are reactive.
    const passY = y(CPA_PASS_SCORE);

    $: colW = W / Math.max(peaks.length, 1);
    $: cols = peaks.map((p, i) => {
        const cx = colW * (i + 0.5);
        const barW = Math.min(colW * 0.44, 52);
        if (p.standing === "unproven" || p.point === null) {
            return { p, cx, barW, unproven: true, top: 0, bottom: 0, markerY: 0 };
        }
        return {
            p,
            cx,
            barW,
            unproven: false,
            top: y(p.bandHigh ?? p.point),
            bottom: y(p.bandLow ?? p.point),
            markerY: y(p.point),
        };
    });
</script>

<div class="summit">
    <div class="summit-head">
        <span class="summit-label">Your range</span>
        <span class="summit-scale">CPA 0–99</span>
    </div>

    <svg
        class="range"
        viewBox="0 0 {W} {VH}"
        preserveAspectRatio="xMidYMid meet"
        role="img"
        aria-label="Projected readiness range across CPA sections; pass line at 75. See the section list below for details."
    >
        <defs>
            <!-- 45° hatch for "unproven" ghosts (mirrors the abstain hatch used
                 in the hero + Readiness dashboard). -->
            <pattern
                id="ghost-hatch"
                width="6"
                height="6"
                patternTransform="rotate(45)"
                patternUnits="userSpaceOnUse"
            >
                <line class="ghost-hatch-line" x1="0" y1="0" x2="0" y2="6" />
            </pattern>
        </defs>

        <!-- Dashed pass line at CPA 75 (neutral, reads over the navy peaks). -->
        <line
            class="pass-line"
            x1="0"
            x2={W}
            y1={passY}
            y2={passY}
            vector-effect="non-scaling-stroke"
        />
        <text class="pass-label" x={W - 2} y={passY - 5} text-anchor="end">
            Pass 75
        </text>

        {#each cols as c (c.p.code)}
            {#if c.unproven}
                <!-- Unproven: dashed ghost pinned at the base, never a height. -->
                <rect
                    class="ghost"
                    x={c.cx - c.barW / 2}
                    y={BASE - 13}
                    width={c.barW}
                    height="12"
                    rx="2"
                />
            {:else}
                <!-- Faded-navy Wilson band (never a crisp apex). -->
                <rect
                    class="band"
                    x={c.cx - c.barW / 2}
                    y={c.top}
                    width={c.barW}
                    height={Math.max(c.bottom - c.top, 2)}
                    rx="3"
                />
                <!-- Midpoint marker. -->
                <line
                    class="marker"
                    x1={c.cx - c.barW / 2}
                    x2={c.cx + c.barW / 2}
                    y1={c.markerY}
                    y2={c.markerY}
                    vector-effect="non-scaling-stroke"
                />
                <!-- Neutral glyph; the band owns the numeric readout. -->
                <text class="score" x={c.cx} y={c.markerY - 6} text-anchor="middle">
                    {c.p.standing === "above" ? "▲" : "▼"}
                </text>
            {/if}
            <text class="code" x={c.cx} y={BASE + 18} text-anchor="middle">
                {c.p.code}
            </text>
        {/each}
    </svg>

    <p class="summit-note">
        Bars show projected CPA ranges. Triangles mark whether the midpoint is above or
        below pass 75.
    </p>
</div>

<style lang="scss">
    .summit {
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
    }

    .summit-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
    }

    .summit-label,
    .summit-scale {
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .range {
        display: block;
        width: 100%;
        height: auto;
    }

    // Dashed pass line + label — neutral, high-contrast over the navy bands.
    .pass-line {
        stroke: var(--fg-subtle);
        stroke-width: 1;
        stroke-dasharray: 5 4;
        opacity: 0.8;
    }

    .pass-label {
        fill: var(--fg-subtle);
        font-size: 10px;
        font-weight: 600;
        letter-spacing: 0.06em;
    }

    // Faded navy Wilson band (the summit) — soft, never a crisp point (C12).
    .band {
        fill: var(--accent);
        opacity: 0.18;
    }

    .marker {
        stroke: var(--accent);
        stroke-width: 2;
    }

    .score {
        fill: var(--fg);
        font-size: 12px;
        font-weight: 600;
        font-variant-numeric: tabular-nums lining-nums;
    }

    .code {
        fill: var(--fg-subtle);
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.04em;
    }

    // Unproven ghost: dashed neutral outline + 45° hatch fill (matches the
    // abstain treatment in the hero + dashboard), visually unlike a real peak.
    .ghost {
        fill: url(#ghost-hatch);
        stroke: var(--border-strong);
        stroke-width: 1;
        stroke-dasharray: 3 3;
    }

    .ghost-hatch-line {
        stroke: var(--border-strong);
        stroke-width: 1;
    }

    .summit-note {
        margin: 0;
        font-size: 13px;
        color: var(--fg-faint);
    }
</style>
