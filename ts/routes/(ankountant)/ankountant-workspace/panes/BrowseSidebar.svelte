<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Browse sidebar: saved searches, Today, card state, flags, decks, notetypes and
tags. There is no single "sidebar tree" RPC — the tree is assembled client-side
from deckTree / tagTree / getNotetypeNames / the savedFilters config plus the
hardcoded state/flag/today nodes, exactly like qt/aqt/browser/sidebar/tree.py.
Clicking a row builds a SearchNode and resolves it to a query string, combining
with the current search per modifier keys (Ctrl=AND, Shift=OR, Alt=negate).
Section collapse is kept local (not yet persisted to col config).
-->
<script lang="ts">
    import { onMount } from "svelte";

    import {
        buildSearchString,
        deckTree,
        getConfigJson,
        getNotetypeNames,
        joinSearchNodes,
        tagTree,
    } from "@generated/backend";

    import {
        addedInDays,
        cardStateNode,
        combineFromEvent,
        deckNode,
        dueOnDay,
        editedInDays,
        flagNode,
        introducedInDays,
        joinerFor,
        negate,
        type Node,
        notetypeNode,
        parsableText,
        ratedNode,
        SearchNode_CardState,
        SearchNode_Flag,
        SearchNode_Rating,
        tagNode,
    } from "./searchNodes";
    import type { TreeItem } from "./sidebarModel";
    import { deckTreeToItems, filterItems, tagTreeToItems } from "./sidebarModel";
    import { decodeConfigJson, errorMessage, isMissingConfigJson } from "./configJson";
    import SidebarTree from "./SidebarTree.svelte";

    export let query = "";
    export let onSearch: (search: string) => void;

    interface StaticEntry {
        label: string;
        node: Node;
        swatch?: string;
    }

    const CARD_STATES: StaticEntry[] = [
        { label: "New", node: cardStateNode(SearchNode_CardState.NEW) },
        { label: "Learning", node: cardStateNode(SearchNode_CardState.LEARN) },
        { label: "Review", node: cardStateNode(SearchNode_CardState.REVIEW) },
        { label: "Due", node: cardStateNode(SearchNode_CardState.DUE) },
        { label: "Suspended", node: cardStateNode(SearchNode_CardState.SUSPENDED) },
        { label: "Buried", node: cardStateNode(SearchNode_CardState.BURIED) },
    ];

    const FLAGS: StaticEntry[] = [
        { label: "Red", node: flagNode(SearchNode_Flag.RED), swatch: "#e2564f" },
        { label: "Orange", node: flagNode(SearchNode_Flag.ORANGE), swatch: "#e8912d" },
        { label: "Green", node: flagNode(SearchNode_Flag.GREEN), swatch: "#4aa564" },
        { label: "Blue", node: flagNode(SearchNode_Flag.BLUE), swatch: "#4f8ce2" },
        { label: "Pink", node: flagNode(SearchNode_Flag.PINK), swatch: "#e26fb0" },
        {
            label: "Turquoise",
            node: flagNode(SearchNode_Flag.TURQUOISE),
            swatch: "#3fb8b0",
        },
        { label: "Purple", node: flagNode(SearchNode_Flag.PURPLE), swatch: "#9a6fe2" },
        { label: "No flag", node: flagNode(SearchNode_Flag.NONE) },
    ];

    const TODAY: StaticEntry[] = [
        { label: "Due today", node: dueOnDay(0) },
        { label: "Added today", node: addedInDays(1) },
        { label: "Studied today", node: ratedNode(1, SearchNode_Rating.ANY) },
        { label: "Again today", node: ratedNode(1, SearchNode_Rating.AGAIN) },
        { label: "Edited today", node: editedInDays(1) },
        { label: "First review today", node: introducedInDays(1) },
    ];

    let phase: "loading" | "ready" | "error" = "loading";
    let deckItems: TreeItem[] = [];
    let tagItems: TreeItem[] = [];
    let notetypes: string[] = [];
    let savedSearches: StaticEntry[] = [];
    let filter = "";
    let message = "";

    const sectionOpen: Record<string, boolean> = {
        saved: true,
        today: false,
        state: true,
        flags: false,
        decks: true,
        notetypes: false,
        tags: true,
    };
    let openState = sectionOpen;
    function toggleSection(key: string): void {
        openState = { ...openState, [key]: !openState[key] };
    }

    $: filtering = filter.trim().length > 0;
    $: fLower = filter.trim().toLowerCase();
    $: shownDecks = filterItems(deckItems, filter);
    $: shownTags = filterItems(tagItems, filter);
    // Referencing filtering/fLower directly keeps Svelte's dependency tracking
    // correct (deps inside a called helper wouldn't be tracked).
    $: shownNotetypes = filtering
        ? notetypes.filter((n) => n.toLowerCase().includes(fLower))
        : notetypes;
    $: savedRows = filtering
        ? savedSearches.filter((e) => e.label.toLowerCase().includes(fLower))
        : savedSearches;
    $: todayRows = filtering
        ? TODAY.filter((e) => e.label.toLowerCase().includes(fLower))
        : TODAY;
    $: stateRows = filtering
        ? CARD_STATES.filter((e) => e.label.toLowerCase().includes(fLower))
        : CARD_STATES;
    $: flagRows = filtering
        ? FLAGS.filter((e) => e.label.toLowerCase().includes(fLower))
        : FLAGS;

    async function emit(node: Node, event?: MouseEvent): Promise<void> {
        const combine = event ? combineFromEvent(event) : "replace";
        try {
            let str: string;
            if (combine === "negate") {
                str = (await buildSearchString(negate(node))).val;
            } else if ((combine === "and" || combine === "or") && query.trim()) {
                str = (
                    await joinSearchNodes({
                        joiner: joinerFor(combine),
                        existingNode: parsableText(query),
                        additionalNode: node,
                    })
                ).val;
            } else {
                str = (await buildSearchString(node)).val;
            }
            message = "";
            onSearch(str);
        } catch (error) {
            message = errorMessage(error);
        }
    }

    function pickTree(item: TreeItem, event: MouseEvent): void {
        void emit(
            item.kind === "deck" ? deckNode(item.fullName) : tagNode(item.fullName),
            event,
        );
    }

    async function load(): Promise<void> {
        phase = "loading";
        try {
            const [decks, tags, nts] = await Promise.all([
                deckTree({ now: 0n }),
                tagTree({}),
                getNotetypeNames({}),
            ]);
            deckItems = deckTreeToItems(decks);
            tagItems = tagTreeToItems(tags);
            notetypes = nts.entries.map((e) => e.name);
            try {
                const raw = await getConfigJson(
                    { val: "savedFilters" },
                    { alertOnError: false },
                );
                const parsed = decodeConfigJson<unknown>("savedFilters", raw.json);
                if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                    throw new Error(
                        'Saved preference "savedFilters" must be an object.',
                    );
                }
                savedSearches = Object.entries(parsed).map(([label, value]) => {
                    if (typeof value !== "string") {
                        throw new Error(
                            `Saved search "${label}" is not a search string.`,
                        );
                    }
                    return { label, node: parsableText(value) };
                });
            } catch (error) {
                if (isMissingConfigJson(error, "savedFilters")) {
                    savedSearches = [];
                } else {
                    throw error;
                }
            }
            phase = "ready";
            message = "";
        } catch (error) {
            message = errorMessage(error);
            phase = "error";
        }
    }

    onMount(() => {
        void load();
    });
</script>

<div class="sidebar" data-testid="browse-sidebar">
    <div class="filter">
        <input
            bind:value={filter}
            placeholder="Filter…"
            aria-label="Filter sidebar"
            data-testid="sidebar-filter"
            spellcheck="false"
        />
    </div>

    {#if phase === "loading"}
        <p class="hint">Loading…</p>
    {:else if phase === "error"}
        <p class="hint">Couldn’t load the sidebar.</p>
        {#if message}
            <p class="hint detail">{message}</p>
        {/if}
    {:else}
        {#if message}
            <p class="hint detail" role="alert">{message}</p>
        {/if}
        <nav class="sections">
            <button
                type="button"
                class="whole"
                on:click={() => onSearch("")}
                data-testid="whole-collection"
            >
                <span class="glyph" aria-hidden="true">✦</span>
                Whole collection
            </button>

            {#if savedSearches.length > 0 && (!filtering || savedRows.length)}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("saved")}>
                        <span class="caret" class:open={openState.saved || filtering}>
                            ▸
                        </span>
                        Saved searches
                    </button>
                    {#if openState.saved || filtering}
                        {#each savedRows as e (e.label)}
                            <button class="leaf" on:click={(ev) => emit(e.node, ev)}>
                                <span class="glyph" aria-hidden="true">★</span>
                                <span class="lbl">{e.label}</span>
                            </button>
                        {/each}
                    {/if}
                </section>
            {/if}

            {#if !filtering || todayRows.length}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("today")}>
                        <span class="caret" class:open={openState.today || filtering}>
                            ▸
                        </span>
                        Today
                    </button>
                    {#if openState.today || filtering}
                        {#each todayRows as e (e.label)}
                            <button class="leaf" on:click={(ev) => emit(e.node, ev)}>
                                <span class="glyph" aria-hidden="true">◷</span>
                                <span class="lbl">{e.label}</span>
                            </button>
                        {/each}
                    {/if}
                </section>
            {/if}

            {#if !filtering || stateRows.length}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("state")}>
                        <span class="caret" class:open={openState.state || filtering}>
                            ▸
                        </span>
                        Card state
                    </button>
                    {#if openState.state || filtering}
                        {#each stateRows as e (e.label)}
                            <button class="leaf" on:click={(ev) => emit(e.node, ev)}>
                                <span class="glyph" aria-hidden="true">◈</span>
                                <span class="lbl">{e.label}</span>
                            </button>
                        {/each}
                    {/if}
                </section>
            {/if}

            {#if !filtering || flagRows.length}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("flags")}>
                        <span class="caret" class:open={openState.flags || filtering}>
                            ▸
                        </span>
                        Flags
                    </button>
                    {#if openState.flags || filtering}
                        {#each flagRows as e (e.label)}
                            <button class="leaf" on:click={(ev) => emit(e.node, ev)}>
                                <span
                                    class="swatch"
                                    style="background:{e.swatch ??
                                        'transparent'};border-color:{e.swatch ??
                                        'var(--border)'}"
                                    aria-hidden="true"
                                ></span>
                                <span class="lbl">{e.label}</span>
                            </button>
                        {/each}
                    {/if}
                </section>
            {/if}

            {#if !filtering || shownDecks.length}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("decks")}>
                        <span class="caret" class:open={openState.decks || filtering}>
                            ▸
                        </span>
                        Decks
                    </button>
                    {#if openState.decks || filtering}
                        <SidebarTree items={shownDecks} onPick={pickTree} {filtering} />
                    {/if}
                </section>
            {/if}

            {#if !filtering || shownNotetypes.length}
                <section>
                    <button
                        class="sec-head"
                        on:click={() => toggleSection("notetypes")}
                    >
                        <span
                            class="caret"
                            class:open={openState.notetypes || filtering}
                        >
                            ▸
                        </span>
                        Note types
                    </button>
                    {#if openState.notetypes || filtering}
                        {#each shownNotetypes as name (name)}
                            <button
                                class="leaf"
                                on:click={(ev) => emit(notetypeNode(name), ev)}
                            >
                                <span class="glyph" aria-hidden="true">▤</span>
                                <span class="lbl">{name}</span>
                            </button>
                        {/each}
                    {/if}
                </section>
            {/if}

            {#if !filtering || shownTags.length}
                <section>
                    <button class="sec-head" on:click={() => toggleSection("tags")}>
                        <span class="caret" class:open={openState.tags || filtering}>
                            ▸
                        </span>
                        Tags
                    </button>
                    {#if openState.tags || filtering}
                        <SidebarTree items={shownTags} onPick={pickTree} {filtering} />
                    {/if}
                </section>
            {/if}
        </nav>
    {/if}
</div>

<style lang="scss">
    .sidebar {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        background: var(--canvas);
        border-right: 1px solid var(--border-subtle);
    }

    .filter {
        flex: 0 0 auto;
        padding: var(--space-sm);
        border-bottom: 1px solid var(--border-subtle);

        input {
            width: 100%;
            font: inherit;
            font-size: var(--type-caption-size);
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border-control);
            border-radius: var(--border-radius);
            padding: var(--space-xxs) var(--space-sm);

            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: 1px;
                border-color: var(--accent);
            }
        }
    }

    .hint {
        padding: var(--space-lg);
        color: var(--fg-subtle);
        font-size: var(--type-caption-size);
    }

    .sections {
        flex: 1;
        min-height: 0;
        overflow: auto;
        padding: var(--space-xs);
    }

    section {
        margin-bottom: var(--space-xs);
    }

    .sec-head {
        display: flex;
        align-items: center;
        gap: var(--space-xxs);
        width: 100%;
        font: inherit;
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
        color: var(--fg-subtle);
        background: transparent;
        border: 0;
        padding: var(--space-xs) var(--space-xs);
        cursor: pointer;

        &:hover {
            color: var(--fg);
        }
    }

    .caret {
        font-size: 8px;
        color: var(--fg-faint);
        transition: transform var(--motion-fast) ease;

        &.open {
            transform: rotate(90deg);
        }
    }

    .whole,
    .leaf {
        display: flex;
        align-items: center;
        gap: var(--space-xs);
        width: 100%;
        font: inherit;
        font-size: var(--type-caption-size);
        text-align: left;
        color: var(--fg);
        background: transparent;
        border: 0;
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-xs);
        cursor: pointer;

        &:hover {
            background: var(--accent-tint);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: -1px;
        }
    }

    .whole {
        margin-bottom: var(--space-xs);
        font-weight: 600;
    }

    .leaf {
        padding-left: 22px;
    }

    .glyph {
        flex: 0 0 auto;
        font-size: 11px;
        opacity: 0.8;
    }

    .swatch {
        flex: 0 0 auto;
        width: 11px;
        height: 11px;
        border-radius: 3px;
        border: 1px solid var(--border);
    }

    .lbl {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    @media (prefers-reduced-motion: reduce) {
        .caret {
            transition: none;
        }
    }
</style>
