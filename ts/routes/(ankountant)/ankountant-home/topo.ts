// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

export interface TopoTopic {
    key: string;
    label: string;
    score: number | null;
    cx: number;
    height: number;
    tier: "front" | "back";
    unproven?: boolean;
}

export interface TopoLayer {
    fill: string;
    contours: string;
    ridge: string;
    shadows: string;
    highlights: string;
}

export interface TopoFlag {
    key: string;
    label: string;
    score: number | null;
    tier: "front" | "back";
    x: number;
    y: number;
    unproven: boolean;
}

export interface TopoRange {
    width: number;
    height: number;
    baseY: number;
    layers: TopoLayer[];
    flags: TopoFlag[];
}

export const TOPIC_MAX_SCORE = 100;
const TOPIC_SCORE_CURVE = 1.35;
const FRONT_HEIGHT_SCALE = 0.82;
const FRONT_HEIGHT_CURVE = 1.12;

function mulberry32(seed: number): () => number {
    let a = seed >>> 0;
    return () => {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), 1 | t);
        t ^= t + Math.imul(t ^ (t >>> 7), 61 | t);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function makeNoise(seed: number, points: number): (t: number) => number {
    const rng = mulberry32(seed);
    const lattice = Array.from({ length: points + 1 }, () => rng() * 2 - 1);
    return (t: number) => {
        const x = t * points;
        const i = Math.floor(x);
        const f = x - i;
        const a = lattice[Math.max(0, Math.min(points, i))];
        const b = lattice[Math.max(0, Math.min(points, i + 1))];
        const s = f * f * (3 - 2 * f);
        return a + (b - a) * s;
    };
}

interface LayerSpec {
    peaks: { cx: number; height: number; spread: number }[];
    floor: number;
    seed: number;
    roughness: number;
    contourCount: number;
    contourStep: number;
}

function clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
}

function peakSpread(count: number, tier: "front" | "back"): number {
    if (count <= 1) {
        return tier === "back" ? 0.13 : 0.095;
    }
    const min = tier === "back" ? 0.1 : 0.045;
    const max = tier === "back" ? 0.9 : 0.955;
    const spacing = (max - min) / (count - 1);
    const maxSpread = tier === "back" ? 0.13 : 0.095;
    return clamp(spacing * 0.62, 0.058, maxSpread);
}

function rawHeightForTopicScore(score: number): number {
    return Math.pow(
        clamp(score, 0, TOPIC_MAX_SCORE) / TOPIC_MAX_SCORE,
        TOPIC_SCORE_CURVE,
    );
}

export function heightForTopicScore(
    score: number,
    tier: "front" | "back" = "back",
): number {
    const height = rawHeightForTopicScore(score);
    if (tier === "back") {
        return height;
    }

    return Math.pow(height, FRONT_HEIGHT_CURVE) * FRONT_HEIGHT_SCALE;
}

export function yForTopicScore(
    score: number,
    baseY: number,
    plotH: number,
    tier: "front" | "back" = "back",
): number {
    return baseY - heightForTopicScore(score, tier) * plotH;
}

function fmt(value: number): string {
    return value.toFixed(1);
}

function curvePath(points: { x: number; y: number }[]): string {
    if (points.length === 0) {
        return "";
    }

    let path = `M${fmt(points[0].x)} ${fmt(points[0].y)}`;
    for (let i = 0; i < points.length - 1; i++) {
        const p0 = points[Math.max(0, i - 1)];
        const p1 = points[i];
        const p2 = points[i + 1];
        const p3 = points[Math.min(points.length - 1, i + 2)];
        const cp1x = p1.x + (p2.x - p0.x) / 6;
        const cp1y = p1.y + (p2.y - p0.y) / 6;
        const cp2x = p2.x - (p3.x - p1.x) / 6;
        const cp2y = p2.y - (p3.y - p1.y) / 6;
        path += ` C${fmt(cp1x)} ${fmt(cp1y)} ${fmt(cp2x)} ${fmt(cp2y)} ${fmt(p2.x)} ${fmt(p2.y)}`;
    }
    return path;
}

function cubicSegment(
    cp1: { x: number; y: number },
    cp2: { x: number; y: number },
    end: { x: number; y: number },
): string {
    return `C${fmt(cp1.x)} ${fmt(cp1.y)} ${fmt(cp2.x)} ${fmt(cp2.y)} ${fmt(end.x)} ${fmt(end.y)}`;
}

function terrainAt(
    x: number,
    spec: LayerSpec,
    W: number,
    plotH: number,
    noise: (t: number) => number,
): number {
    const t = clamp(x / W, 0, 1);
    let lift = 0;

    for (const peak of spec.peaks) {
        const center = peak.cx * W;
        const spread = peak.spread * W;
        const distance = Math.abs(x - center) / spread;
        const capacity = Math.max(0, peak.height - spec.floor);
        const crown = Math.exp(-Math.pow(distance / 0.92, 2.55));
        const shoulder = Math.exp(-Math.pow(distance / 1.65, 2.1));
        const skirt = Math.exp(-Math.pow(distance / 2.65, 2));
        const profile = Math.min(1, crown * 0.72 + shoulder * 0.22 + skirt * 0.06);
        lift = Math.max(lift, capacity * profile);
    }

    const texture = noise(t) * spec.roughness;
    const height = spec.floor + lift;
    return clamp(height + texture, 0.03, 1) * plotH;
}

function ridgePoints(
    spec: LayerSpec,
    W: number,
    baseY: number,
    plotH: number,
): { x: number; y: number }[] {
    const noise = makeNoise(spec.seed, 64);
    const points: { x: number; y: number }[] = [];
    const start = -90;
    const end = W + 90;
    const step = 16;

    for (let x = start; x <= end; x += step) {
        points.push({ x, y: baseY - terrainAt(x, spec, W, plotH, noise) });
    }
    points.push({ x: end, y: baseY - terrainAt(end, spec, W, plotH, noise) });
    return points;
}

function buildLayer(
    spec: LayerSpec,
    W: number,
    baseY: number,
    plotH: number,
): TopoLayer {
    let fill = "";
    let ridge = "";
    let contours = "";
    let shadows = "";
    let highlights = "";
    const terrainNoise = makeNoise(spec.seed, 64);
    const ridgeSamples = ridgePoints(spec, W, baseY, plotH);
    const contourPaths: string[] = [];

    fill = `${curvePath(ridgeSamples)} L${fmt(W + 90)} ${fmt(baseY)} L-90 ${fmt(baseY)} Z`;
    ridge = curvePath(ridgeSamples);

    const bandCount = Math.round(spec.contourCount * 1.35);
    for (let k = 1; k <= bandCount; k++) {
        const contourNoise = makeNoise(spec.seed + k * 47, 54);
        const points: { x: number; y: number }[] = [];
        const heightRatio = k / (bandCount + 1);
        const level = baseY - 16 - heightRatio * plotH * 0.76;
        let insideSamples = 0;

        for (let x = -70; x <= W + 70; x += 18) {
            const t = clamp(x / W, 0, 1);
            const ridgeY = baseY - terrainAt(x, spec, W, plotH, terrainNoise);
            const belowRidge = level - ridgeY;
            const depthRatio = clamp(belowRidge / (plotH * 0.42), 0, 1);
            const drift = contourNoise(t) * (2.2 + depthRatio * 4.2);
            const weavePhase = t * Math.PI * (5.1 + heightRatio * 2.8) + k * 0.72;
            const weave = Math.sin(weavePhase) * (1.2 + depthRatio * 2.8);
            const y = level + drift + weave;

            if (belowRidge > 4 && y < baseY - 8) {
                insideSamples += 1;
            }
            points.push({ x, y });
        }

        if (insideSamples > 3) {
            contourPaths.push(curvePath(points));
        }
    }

    for (const [index, peak] of spec.peaks.entries()) {
        const peakNoise = makeNoise(spec.seed + index * 131, 42);
        const x = peak.cx * W + peakNoise(0.23) * W * 0.006;
        const half = peak.spread * W;
        const apex = baseY - terrainAt(x, spec, W, plotH, terrainNoise);
        const left = clamp(x - half * (0.82 + peakNoise(0.11) * 0.08), -90, W + 90);
        const right = clamp(x + half * (0.82 + peakNoise(0.83) * 0.08), -90, W + 90);
        const leftMid = x - half * (0.32 + peakNoise(0.39) * 0.08);
        const rightMid = x + half * (0.32 + peakNoise(0.61) * 0.08);
        const leftTerrain = terrainAt(left, spec, W, plotH, terrainNoise);
        const rightTerrain = terrainAt(right, spec, W, plotH, terrainNoise);
        const leftToe = baseY - leftTerrain + plotH * 0.2;
        const rightToe = baseY - rightTerrain + plotH * 0.18;

        shadows += [
            `M${fmt(x)} ${fmt(apex)}`,
            cubicSegment(
                { x: rightMid, y: apex + 58 },
                { x: x + half * 0.52, y: rightToe - 42 },
                { x: right, y: rightToe },
            ),
            cubicSegment(
                { x: x + half * 0.28, y: rightToe - 16 },
                { x: x + half * 0.09, y: apex + 116 },
                { x, y: apex },
            ),
            "Z",
        ].join(" ");
        highlights += [
            `M${fmt(x)} ${fmt(apex)}`,
            cubicSegment(
                { x: leftMid, y: apex + 50 },
                { x: x - half * 0.52, y: leftToe - 32 },
                { x: left, y: leftToe },
            ),
            cubicSegment(
                { x: x - half * 0.28, y: leftToe - 20 },
                { x: x - half * 0.08, y: apex + 110 },
                { x, y: apex },
            ),
            "Z",
        ].join(" ");

        const summitCount = Math.max(4, Math.round(spec.contourCount * 0.34));
        for (let k = 1; k <= summitCount; k++) {
            const t = k / (summitCount + 2);
            const contourNoise = makeNoise(spec.seed + index * 211 + k * 7, 18);
            const span = half * (0.11 + t * 0.36);
            const bias = contourNoise(0.31) * half * 0.03;
            const rimY = apex + spec.contourStep * (k * 0.94 + 0.72);
            const lift = clamp((rimY - apex) * (0.18 + t * 0.05), 5, 17);
            if (rimY >= baseY - 34) {
                continue;
            }
            const points: { x: number; y: number }[] = [];

            for (let i = 0; i <= 8; i++) {
                const u = i / 8;
                const centered = u * 2 - 1;
                const crown = Math.max(0, 1 - Math.abs(centered));
                points.push({
                    x: x + centered * span * (0.94 + contourNoise(u) * 0.045) + bias,
                    y: rimY - Math.pow(crown, 0.74) * lift + contourNoise(1 - u) * 2.6,
                });
            }

            contourPaths.push(curvePath(points));
        }
    }
    contours = contourPaths.join(" ");
    return { fill, contours, ridge, shadows, highlights };
}

export function buildTopoRange(
    topics: TopoTopic[],
    opts: { width?: number; height?: number } = {},
): TopoRange {
    const W = opts.width ?? 1000;
    const H = opts.height ?? 680;
    const baseY = H;
    const plotH = H * 0.86;

    const front = topics.filter((t) => t.tier === "front");
    const back = topics.filter((t) => t.tier === "back");

    const farLayer = buildLayer(
        {
            peaks: [
                { cx: 0.1, height: 0.36, spread: 0.25 },
                { cx: 0.32, height: 0.32, spread: 0.26 },
                { cx: 0.55, height: 0.38, spread: 0.25 },
                { cx: 0.78, height: 0.34, spread: 0.27 },
                { cx: 0.97, height: 0.28, spread: 0.24 },
            ],
            floor: 0.2,
            seed: 7,
            roughness: 0.012,
            contourCount: 13,
            contourStep: 15,
        },
        W,
        baseY,
        plotH,
    );

    const backSpec: LayerSpec = {
        peaks: back.map((t) => ({
            cx: t.cx,
            height: topicHeight(t),
            spread: peakSpread(back.length, "back"),
        })),
        floor: 0.1,
        seed: 23,
        roughness: 0.01,
        contourCount: 15,
        contourStep: 14,
    };
    const backLayer = buildLayer(backSpec, W, baseY, plotH);

    const frontSpec: LayerSpec = {
        peaks: front.map((t) => ({
            cx: t.cx,
            height: topicHeight(t),
            spread: peakSpread(front.length, "front"),
        })),
        floor: 0.07,
        seed: 41,
        roughness: 0.009,
        contourCount: 18,
        contourStep: 13,
    };
    const frontLayer = buildLayer(frontSpec, W, baseY, plotH);

    const flags: TopoFlag[] = topics.map((t) => {
        const x = t.cx * W;
        return {
            key: t.key,
            label: t.label,
            score: t.score,
            tier: t.tier,
            x,
            y: yForTopicScore(t.score ?? 0, baseY, plotH, t.tier),
            unproven: t.unproven ?? false,
        };
    });

    return {
        width: W,
        height: H,
        baseY,
        layers: [farLayer, backLayer, frontLayer],
        flags,
    };
}

function topicHeight(topic: TopoTopic): number {
    if (topic.score === null) {
        return topic.height;
    }
    return heightForTopicScore(topic.score, topic.tier);
}
