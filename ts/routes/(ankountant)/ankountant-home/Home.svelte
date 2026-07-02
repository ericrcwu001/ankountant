<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The Ankountant Home hub. Its hero widget is a days-until-exam countdown fed by
a user-entered exam date; saving that date (via the generic SetConfigJson RPC)
is what makes the live scheduler deadline-anchored (A1-live). Home also surfaces
Readiness and links out to the study surfaces — it is a hub, not a settings
page. Styled with the Ledger design tokens: navy --accent is chrome-only;
numerals are neutral ink + tabular figures; abstain is first-class.
-->
<script lang="ts">
    import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";
    import { setConfigJson } from "@generated/backend";

    import { goto } from "$app/navigation";
    import { bridgeCommand } from "@tslib/bridgecommand";

    import {
        buildReadinessView,
        GAP_WARNING_THRESHOLD,
    } from "../ankountant-dashboard/lib";
    import { buildCountdown, buildPhaseCta, choosePhase } from "./lib";

    export let readiness: GetReadinessResponse;
    export let section = "FAR";
    export let examDate = "";

    let date = examDate;
    let saveState: "idle" | "saving" | "saved" = "idle";

    $: countdown = buildCountdown(date);
    $: view = buildReadinessView(readiness.readiness);
    $: topicCount = readiness.topics.length;
    $: gapsToClose = readiness.topics.filter(
        (t) => t.gap >= GAP_WARNING_THRESHOLD,
    ).length;

    // A topic with enough in-window recall reps counts as a memory base; with
    // none the student is a beginner, so the CTA routes to blocked recall.
    $: memoryReady = readiness.topics.some((t) => !t.memoryInsufficient);
    $: phase = choosePhase({ days: countdown.days, memoryReady });
    $: cta = buildPhaseCta(phase);

    async function onDateChange(): Promise<void> {
        saveState = "saving";
        try {
            // The value is a bare ISO date string, JSON-encoded (Rust decodes it
            // as a String). Key mirrors config::exam_date_key(section).
            await setConfigJson({
                key: `ankountant.${section}.exam.date`,
                valueJson: new TextEncoder().encode(JSON.stringify(date)),
                undoable: true,
            });
            saveState = "saved";
        } catch (error) {
            saveState = "idle";
            console.log("ankountant: failed to save exam date", error);
        }
    }

    function nav(href: string): void {
        goto(href); // client-side SPA nav within the shell
    }

    // The phase-aware CTA opens whichever surface the current phase recommends:
    // recall leaves the shell via the Qt bridge, confusion is an in-shell route.
    function runCta(): void {
        if (cta.target === "confusion") {
            nav("/ankountant-confusion");
        } else {
            bridgeCommand("ankountant:review");
        }
    }
</script>

<div class="ankountant-home" data-testid="home">
    <header class="page-head">
        <p class="eyebrow">{section} section</p>
        <h1>Home</h1>
    </header>

    <!-- Hero: the days-until-exam countdown + the date that drives the live
         deadline-anchored scheduler. The numeral is the display hero. -->
    <section class="card hero-card" data-testid="countdown">
        <div class="hero-main">
            <span class="hero-numeral tabular" data-testid="countdown-days">
                {countdown.numeral}
            </span>
            <span class="hero-caption">{countdown.caption}</span>
        </div>
        <div class="exam-date">
            <label class="date-label" for="exam-date">Exam date</label>
            <input
                id="exam-date"
                type="date"
                bind:value={date}
                on:change={onDateChange}
                data-testid="exam-date-input"
            />
            <span class="save-state" data-testid="save-state" aria-live="polite">
                {#if saveState === "saving"}
                    Saving…
                {:else if saveState === "saved"}
                    Saved
                {/if}
            </span>
        </div>
    </section>

    <!-- Readiness at a glance (full breakdown lives on the Readiness tab). -->
    <section class="card readiness" data-testid="readiness">
        <h2 class="card-label">Exam-day projection</h2>
        {#if view.abstain}
            <div class="abstain" data-testid="abstain">
                <span class="abstain-icon" role="img" aria-label="Insufficient data">
                    &#9636;
                </span>
                <div class="abstain-text">
                    <p class="abstain-title">Not enough data yet</p>
                    <p class="abstain-reason">{view.reason}.</p>
                    <p class="coverage" data-testid="coverage">
                        {view.coveragePct}% of exam topics covered
                    </p>
                </div>
            </div>
        {:else}
            <p class="band" data-testid="readiness-band">
                <span class="range tabular hero">{view.bandLabel}</span>
                <span class="point tabular" data-testid="point-estimate">
                    point {view.pointLabel}
                </span>
                <span class="confidence" data-testid="confidence">
                    {view.confidence} confidence
                </span>
            </p>
            <div
                class="band-track"
                role="img"
                aria-label="Projected CPA band {view.bandLabel}, pass line 75"
            >
                <div
                    class="band-fill"
                    style="left:{view.trackLeftPct}%; width:{view.trackWidthPct}%"
                ></div>
                <div class="pass-tick" style="left:{view.trackPassPct}%"></div>
            </div>
            <p class="coverage" data-testid="coverage">
                {view.coveragePct}% of exam covered · CPA 0–99, pass 75 (projection)
            </p>
        {/if}
    </section>

    <!-- Quick stats derived from the readiness rollup. Neutral-ink numerals. -->
    <section class="quick-stats" data-testid="quick-stats">
        <div class="card stat">
            <span class="stat-num tabular">{topicCount}</span>
            <span class="stat-label">Topics tracked</span>
        </div>
        <div class="card stat">
            <span class="stat-num tabular">{gapsToClose}</span>
            <span class="stat-label">Gaps to close</span>
        </div>
    </section>

    <!-- Hub navigation. Row 1 (double-width): the phase-aware CTA (recall via
         the Qt bridge, or confusion in-shell) + an explicit Confusion review.
         Row 2: the remaining surfaces. -->
    <nav class="actions" aria-label="Ankountant surfaces">
        <button
            type="button"
            class="action primary wide"
            data-testid="start-review"
            data-phase={cta.phase}
            on:click={runCta}
        >
            <span class="cta-label">{cta.label}</span>
            <span class="cta-sub">{cta.subtitle}</span>
        </button>
        <button
            type="button"
            class="action wide"
            data-testid="start-confusion"
            on:click={() => nav("/ankountant-confusion")}
        >
            Confusion review
        </button>
        <button
            type="button"
            class="action"
            on:click={() => nav("/ankountant-workspace")}
        >
            Study workspace
        </button>
        <button
            type="button"
            class="action"
            on:click={() => nav("/ankountant-dashboard")}
        >
            Readiness
        </button>
        <button type="button" class="action" on:click={() => nav("/ankountant-tbs")}>
            TBS
        </button>
        <button
            type="button"
            class="action"
            data-testid="open-stats"
            on:click={() => nav("/ankountant-stats")}
        >
            Stats
        </button>
    </nav>
</div>

<style lang="scss">
    .ankountant-home {
        max-width: 48rem;
        margin: 0 auto;
        padding: var(--space-xl) var(--space-lg) var(--space-xxl);
        font-size: var(--font-size);
        color: var(--fg);
    }

    .page-head {
        margin-bottom: var(--space-lg);

        .eyebrow {
            margin: 0 0 var(--space-xxs);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }

        h1 {
            font-size: var(--type-section-heading-size);
            font-weight: var(--type-section-heading-weight);
            letter-spacing: var(--type-section-heading-tracking);
            line-height: var(--type-section-heading-line);
            margin: 0;
        }
    }

    // Shared card surface (Ledger §3: borders-first, tinted-ink elevation).
    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
    }

    .card-label {
        margin: 0 0 var(--space-sm);
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .hero-card {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-end;
        justify-content: space-between;
        gap: var(--space-lg);
        padding: var(--space-xl);
        margin-bottom: var(--space-xl);
    }

    .hero-main {
        display: flex;
        flex-direction: column;
        gap: var(--space-xs);
    }

    // The countdown is the display hero — neutral ink + tabular figures, NOT the
    // brand navy (which is chrome-only).
    .hero-numeral {
        font-size: var(--type-display-hero-size);
        font-weight: var(--type-display-hero-weight);
        letter-spacing: var(--type-display-hero-tracking);
        line-height: var(--type-display-hero-line);
        color: var(--fg);
    }

    .hero-caption {
        font-size: 14px;
        color: var(--fg-subtle);
    }

    .exam-date {
        display: flex;
        flex-direction: column;
        gap: var(--space-xxs);
    }

    .date-label {
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--fg-subtle);
    }

    .exam-date input {
        font: inherit;
        color: var(--fg);
        background: var(--canvas);
        border: 1px solid var(--border);
        border-radius: var(--border-radius);
        padding: var(--space-sm) var(--space-md);
        -webkit-appearance: none;
        appearance: none;

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }
    }

    .save-state {
        min-height: 1em;
        font-size: 12px;
        color: var(--fg-faint);
    }

    .readiness {
        padding: var(--space-xl);
        margin-bottom: var(--space-xl);
    }

    .hero {
        font-size: var(--type-display-hero-size);
        font-weight: var(--type-display-hero-weight);
        letter-spacing: var(--type-display-hero-tracking);
        line-height: var(--type-display-hero-line);
    }

    .band {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: var(--space-sm) var(--space-md);
        margin: 0;
    }

    .band .range {
        color: var(--accent);
    }

    .band .point {
        font-size: 14px;
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums lining-nums;
    }

    .band .confidence {
        font-size: 14px;
        color: var(--fg-subtle);
    }

    .band-track {
        position: relative;
        height: 10px;
        margin: var(--space-md) 0 var(--space-sm);
        border-radius: var(--border-radius);
        background: var(--canvas);
    }

    .band-fill {
        position: absolute;
        top: 0;
        height: 100%;
        min-width: 2px;
        border-radius: var(--border-radius);
        // Faded navy Wilson band — soft edges, never a crisp point (C12).
        background: linear-gradient(
            90deg,
            transparent 0%,
            var(--accent) 30%,
            var(--accent) 70%,
            transparent 100%
        );
        opacity: 0.75;
    }

    .pass-tick {
        position: absolute;
        top: -3px;
        width: 2px;
        height: 16px;
        margin-left: -1px;
        background: var(--fg-subtle);
        opacity: 0.7;
    }

    .coverage {
        margin: var(--space-xs) 0 0;
        font-size: 13px;
        color: var(--fg-subtle);
        font-variant-numeric: tabular-nums lining-nums;
    }

    // First-class abstain: neutral + hatch + icon + label (Ledger §5, C12).
    .abstain {
        display: flex;
        align-items: flex-start;
        gap: var(--space-md);
        padding: var(--space-md);
        border: 1px dashed var(--border-strong);
        border-radius: var(--border-radius);
        background: repeating-linear-gradient(
            45deg,
            transparent,
            transparent 7px,
            var(--border) 7px,
            var(--border) 8px
        );
    }

    .abstain-icon {
        font-size: 20px;
        line-height: 1.2;
        color: var(--fg-subtle);
    }

    .abstain-text {
        display: flex;
        flex-direction: column;
        gap: 2px;
    }

    .abstain-title {
        margin: 0;
        font-weight: 600;
        color: var(--fg);
    }

    .abstain-reason {
        margin: 0;
        color: var(--fg-subtle);
    }

    .quick-stats {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: var(--space-md);
        margin-bottom: var(--space-xl);
    }

    .stat {
        display: flex;
        flex-direction: column;
        gap: var(--space-xxs);
        padding: var(--space-lg);
    }

    .stat-num {
        font-size: var(--type-section-heading-size);
        font-weight: 600;
        color: var(--fg);
    }

    .stat-label {
        font-size: 13px;
        color: var(--fg-subtle);
    }

    .tabular {
        font-variant-numeric: tabular-nums lining-nums;
    }

    .actions {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: var(--space-md);
    }

    // Row 1: two double-width buttons (phase CTA + Confusion review).
    .action.wide {
        grid-column: span 2;
    }

    // Plain <button>s: the global button base applies; flatten to hub tiles.
    .action {
        font: inherit;
        font-weight: 500;
        color: var(--fg);
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
        padding: var(--space-md) var(--space-lg);
        text-align: center;

        &:hover {
            border-color: var(--border);
            background: var(--canvas);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }
    }

    // The one brand-accented action (chrome-only navy). The phase CTA stacks a
    // dynamic label over a subtitle.
    .action.primary {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--space-xxs);
        color: var(--canvas-elevated);
        background: var(--accent);
        border-color: var(--accent);

        &:hover {
            background: var(--accent);
            filter: brightness(1.05);
        }
    }

    .cta-label {
        font-weight: 600;
    }

    .cta-sub {
        font-size: 12px;
        font-weight: 400;
        opacity: 0.85;
    }

    // Narrow docks: collapse to two columns; wide buttons fill the row.
    @media (max-width: 34rem) {
        .actions {
            grid-template-columns: repeat(2, 1fr);
        }
    }
</style>
