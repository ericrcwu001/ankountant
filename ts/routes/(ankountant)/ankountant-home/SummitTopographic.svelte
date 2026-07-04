<script lang="ts">
    import { createEventDispatcher } from "svelte";

    import { buildTopoRange, type TopoFlag, type TopoTopic } from "./topo";

    export let topics: TopoTopic[] = [];
    export let sectionLabel = "FAR";

    const NAVY = "#1f3a5f";
    const AMBER = "#e08a2e";
    const MUTED = "#7f8da2";
    const POLE = 40;
    const dispatch = createEventDispatcher<{
        flagenter: { key: string; x: number; y: number };
        flagleave: undefined;
    }>();

    $: range = buildTopoRange(topics, { width: 1000, height: 680 });

    function flagPennant(x: number, topY: number): string {
        return `M${x} ${topY} L${x + 19} ${topY + 6.5} L${x} ${topY + 13} Z`;
    }

    function flagColor(below: boolean, unproven: boolean): string {
        if (unproven) {
            return MUTED;
        }
        return below ? AMBER : NAVY;
    }

    function showFlag(flag: TopoFlag): void {
        dispatch("flagenter", { key: flag.key, x: flag.x, y: flag.y });
    }

    function hideFlag(): void {
        dispatch("flagleave");
    }
</script>

<svg
    class="topo"
    viewBox="0 0 {range.width} {range.height}"
    preserveAspectRatio="xMidYMax meet"
    role="img"
    aria-label="Topographic range of {sectionLabel} topics; each peak is a topic, pass line at CPA 75."
>
    <defs>
        <linearGradient id="topo-far" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#edf5fc" />
            <stop offset="100%" stop-color="#d7e5f3" />
        </linearGradient>
        <linearGradient id="topo-back" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#f8fbfe" />
            <stop offset="58%" stop-color="#dce8f4" />
            <stop offset="100%" stop-color="#c5d8eb" />
        </linearGradient>
        <linearGradient id="topo-front" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#f4f9fd" />
            <stop offset="50%" stop-color="#cfdeee" />
            <stop offset="100%" stop-color="#adc3dc" />
        </linearGradient>
        <clipPath id="topo-clip-far" clipPathUnits="userSpaceOnUse">
            <path d={range.layers[0].fill} />
        </clipPath>
        <clipPath id="topo-clip-back" clipPathUnits="userSpaceOnUse">
            <path d={range.layers[1].fill} />
        </clipPath>
        <clipPath id="topo-clip-front" clipPathUnits="userSpaceOnUse">
            <path d={range.layers[2].fill} />
        </clipPath>
    </defs>

    <path d={range.layers[0].fill} fill="url(#topo-far)" opacity="0.64" />
    <path
        d={range.layers[0].highlights}
        class="slope-light far"
        clip-path="url(#topo-clip-far)"
    />
    <path
        d={range.layers[0].shadows}
        class="slope-shade far"
        clip-path="url(#topo-clip-far)"
    />
    <path
        d={range.layers[0].contours}
        clip-path="url(#topo-clip-far)"
        fill="none"
        stroke="#9eb3cc"
        stroke-width="0.44"
        opacity="0.34"
        vector-effect="non-scaling-stroke"
    />

    <path d={range.layers[1].fill} fill="url(#topo-back)" opacity="0.88" />
    <path
        d={range.layers[1].highlights}
        class="slope-light back"
        clip-path="url(#topo-clip-back)"
    />
    <path
        d={range.layers[1].shadows}
        class="slope-shade back"
        clip-path="url(#topo-clip-back)"
    />
    <path
        d={range.layers[1].contours}
        clip-path="url(#topo-clip-back)"
        fill="none"
        stroke="#5f7fa8"
        stroke-width="0.5"
        opacity="0.48"
        vector-effect="non-scaling-stroke"
    />
    <path
        d={range.layers[1].ridge}
        fill="none"
        stroke="#153b65"
        stroke-width="1.12"
        opacity="0.5"
        vector-effect="non-scaling-stroke"
    />

    <path d={range.layers[2].fill} fill="url(#topo-front)" />
    <path
        d={range.layers[2].highlights}
        class="slope-light front"
        clip-path="url(#topo-clip-front)"
    />
    <path
        d={range.layers[2].shadows}
        class="slope-shade front"
        clip-path="url(#topo-clip-front)"
    />
    <path
        d={range.layers[2].contours}
        clip-path="url(#topo-clip-front)"
        fill="none"
        stroke="#234d78"
        stroke-width="0.54"
        opacity="0.52"
        vector-effect="non-scaling-stroke"
    />
    <path
        d={range.layers[2].ridge}
        fill="none"
        stroke="#0e345d"
        stroke-width="1.18"
        opacity="0.58"
        vector-effect="non-scaling-stroke"
    />

    <line
        class="pass-line"
        x1="0"
        x2={range.width}
        y1={range.passY}
        y2={range.passY}
        vector-effect="non-scaling-stroke"
    />
    <text class="pass-label" x={range.width - 6} y={range.passY - 8} text-anchor="end">
        PASS LINE · 75
    </text>

    {#each range.flags as f (f.key)}
        {@const top = f.y - POLE}
        {@const color = flagColor(f.below, f.unproven)}
        <g
            class="flag"
            role="img"
            aria-label={`${f.label}, ${f.score === null ? "not enough data yet" : `${f.score} performance`}`}
            on:mouseenter={() => showFlag(f)}
            on:mouseleave={hideFlag}
        >
            <title>
                {f.label}, {f.score === null
                    ? "not enough data yet"
                    : `${f.score} performance`}
            </title>
            <text class="flag-name" x={f.x} y={top - 22} text-anchor="middle">
                {f.label}
            </text>
            <text
                class="flag-score"
                class:unproven={f.unproven}
                x={f.x}
                y={top - 4}
                text-anchor="middle"
            >
                {f.score === null ? "—" : f.score}
            </text>
            <line
                x1={f.x}
                x2={f.x}
                y1={f.y}
                y2={top}
                stroke={color}
                stroke-width="2"
                vector-effect="non-scaling-stroke"
            />
            <path
                d={flagPennant(f.x, top)}
                fill={color}
                opacity={f.unproven ? 0.45 : 1}
            />
            <circle
                cx={f.x}
                cy={f.y}
                r="4.5"
                fill="#fff"
                stroke={color}
                stroke-width="2"
                vector-effect="non-scaling-stroke"
            />
        </g>
    {/each}
</svg>

<style lang="scss">
    .topo {
        display: block;
        width: 100%;
        height: 100%;
    }

    .pass-line {
        stroke: var(--accent);
        stroke-width: 1.4;
        stroke-dasharray: 7 6;
        opacity: 0.75;
    }

    .pass-label {
        fill: var(--accent);
        font-size: 13px;
        font-weight: 700;
        letter-spacing: 0.06em;
    }

    .slope-light {
        fill: #fff;
        opacity: 0.16;

        &.far {
            opacity: 0.08;
        }

        &.back {
            opacity: 0.12;
        }
    }

    .slope-shade {
        fill: #133a64;
        opacity: 0.045;

        &.far {
            opacity: 0.016;
        }

        &.back {
            opacity: 0.032;
        }
    }

    .flag-name {
        fill: var(--fg);
        font-size: 15px;
        font-weight: 600;
        paint-order: stroke;
        stroke: var(--canvas);
        stroke-linejoin: round;
        stroke-width: 5px;
    }

    .flag-score {
        fill: var(--accent);
        font-size: 15px;
        font-weight: 700;
        font-variant-numeric: tabular-nums lining-nums;
        paint-order: stroke;
        stroke: var(--canvas);
        stroke-linejoin: round;
        stroke-width: 5px;

        &.unproven {
            fill: var(--fg-faint);
        }
    }
</style>
