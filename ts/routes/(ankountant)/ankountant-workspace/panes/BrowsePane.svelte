<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Web-native Browse surface. Composes the sidebar, a virtualized card/note table,
and an inline note editor, driven by the same backend as the native browser:
search_cards / search_notes -> ids, all_browser_columns +
set_active_browser_columns for the column set, browser_row_for_id per row, and
find_and_replace / suspend / tag / flag / delete for the row actions.

Parity added on top of the v1 table core: sidebar tree, notes-mode toggle,
click-to-sort columns, column show/hide, multi-select + keyboard navigation, an
editor pane that saves through update_notes, a right-click context menu, and
find & replace. Deferred: sidebar drag-drop + per-node collapse persistence,
column drag-reorder, and rich-media/tag persistence in the editor (Qt-only).
-->
<script lang="ts">
    import type { PlainMessage } from "@bufbuild/protobuf";
    import { onMount, tick } from "svelte";

    import { ConfigKey_Bool } from "@generated/anki/config_pb";
    import { BuryOrSuspendCardsRequest_Mode } from "@generated/anki/scheduler_pb";
    import type {
        BrowserColumns_Column,
        BrowserRow,
        SortOrder,
    } from "@generated/anki/search_pb";
    import {
        addNoteTags,
        allBrowserColumns,
        buryOrSuspendCards,
        cardsOfNote,
        getCard,
        getConfigBool,
        getConfigJson,
        removeNoteTags,
        removeNotes,
        restoreBuriedAndSuspendedCards,
        searchCards,
        searchNotes,
        setActiveBrowserColumns,
        setConfigBool,
        setConfigJson,
        setFlag,
    } from "@generated/backend";

    import BrowseEditor from "./BrowseEditor.svelte";
    import BrowseRow from "./BrowseRow.svelte";
    import BrowseSidebar from "./BrowseSidebar.svelte";
    import {
        activeColsKey,
        defaultColumns,
        defaultReverse,
        isSortable,
        labelFor,
        sortBackwardsKey,
        sortTypeKey,
    } from "./browseColumns";
    import {
        deleteNotesConfirmation,
        deleteSelectionMenuLabel,
        normalizeTagPrompt,
    } from "./browseActions";
    import ContextMenu, { type MenuItem } from "./ContextMenu.svelte";
    import {
        decodeConfigJson,
        encodeConfigJson,
        errorMessage,
        isMissingConfigJson,
    } from "./configJson";
    import FindReplaceDialog from "./FindReplaceDialog.svelte";
    import PaneState from "./PaneState.svelte";

    const DEFAULT_QUERY = "deck:current";
    const ROW_HEIGHT = 28;
    const OVERSCAN = 6;
    const FLAG_LABELS = [
        "No flag",
        "Red",
        "Orange",
        "Green",
        "Blue",
        "Pink",
        "Turquoise",
        "Purple",
    ];

    function launchParams(): URLSearchParams {
        return typeof window === "undefined"
            ? new URLSearchParams()
            : new URLSearchParams(window.location.search);
    }

    const initialParams = launchParams();
    const initialMode = initialParams.get("mode");

    function initialNotesModeFrom(mode: string | null): boolean | undefined {
        if (mode === "notes") {
            return true;
        }
        if (mode === "cards") {
            return false;
        }
        return undefined;
    }

    const initialNotesMode = initialNotesModeFrom(initialMode);

    let phase: "loading" | "ready" | "error" = "loading";
    let message = "";

    let query = initialParams.get("search") ?? DEFAULT_QUERY;
    let notesMode = initialNotesMode ?? false;
    let allColumns: BrowserColumns_Column[] = [];
    let columnByKey = new Map<string, BrowserColumns_Column>();
    let activeKeys: string[] = [];
    let sortColumn = "noteFld";
    let sortReverse = false;

    let ids: bigint[] = [];
    let cache = new Map<string, BrowserRow>();
    let rowVersion = 0;

    // Selection is keyed by id string (the mode's native id: card or note).
    let selection = new Set<string>();
    let anchorIndex = -1;
    let focusIndex = -1;

    let showSidebar = true;
    let editorNoteId = 0n;
    let editorToken = 0;

    let rowMenu: { x: number; y: number; items: MenuItem[] } | null = null;
    let columnMenu: { x: number; y: number; items: MenuItem[] } | null = null;
    let findReplaceOpen = false;
    let findReplaceNoteIds: bigint[] = [];

    let paneEl: HTMLElement | undefined;
    let scrollEl: HTMLElement | undefined;
    let searchInput: HTMLInputElement | undefined;
    let scrollTop = 0;
    let viewportH = 0;
    let emptyTitle = "";
    let emptyDetail = "";

    $: total = ids.length;
    $: activeColumns = activeKeys
        .map((k) => columnByKey.get(k))
        .filter((c): c is BrowserColumns_Column => c !== undefined);
    $: startIndex = Math.max(0, Math.floor(scrollTop / ROW_HEIGHT) - OVERSCAN);
    $: endIndex = Math.min(
        total,
        Math.ceil((scrollTop + viewportH) / ROW_HEIGHT) + OVERSCAN,
    );
    $: visible = Array.from(
        { length: Math.max(0, endIndex - startIndex) },
        (_, i) => startIndex + i,
    );
    $: gridTemplate = activeColumns.length
        ? "minmax(0, 2fr) " +
          "minmax(0, 1fr) ".repeat(Math.max(0, activeColumns.length - 1))
        : "1fr";
    $: showEditor = selection.size === 1;
    $: browseKind = notesMode ? "notes" : "cards";
    $: normalizedQuery = query.trim();
    $: hasRecoverableSearch =
        normalizedQuery !== "" && normalizedQuery !== DEFAULT_QUERY;
    $: canShowWholeCollection = normalizedQuery !== "";
    $: {
        if (hasRecoverableSearch) {
            emptyTitle = `No ${browseKind} match this search`;
            emptyDetail = `This search returned no ${browseKind}. Return to the current deck, show the whole collection, or adjust the sidebar filters.`;
        } else if (normalizedQuery === DEFAULT_QUERY) {
            emptyTitle = `No ${browseKind} in the current deck`;
            emptyDetail = `The current deck has no ${browseKind} in this view. Show the whole collection, or choose a specific deck or tag in the sidebar.`;
        } else {
            emptyTitle = `No ${browseKind} available`;
            emptyDetail = `There are no ${browseKind} to show for this workspace view yet.`;
        }
    }

    // ---- config helpers -----------------------------------------------------

    async function readJson<T>(key: string, fallback: T): Promise<T> {
        try {
            const raw = await getConfigJson({ val: key }, { alertOnError: false });
            return decodeConfigJson<T>(key, raw.json);
        } catch (error) {
            if (isMissingConfigJson(error, key)) {
                return fallback;
            }
            throw error;
        }
    }

    async function writeJson(key: string, value: unknown): Promise<void> {
        const valueJson = encodeConfigJson(key, value);
        await setConfigJson({ key, valueJson, undoable: false });
    }

    function reportError(error: unknown): void {
        message = errorMessage(error);
    }

    async function runPaneAction(action: () => Promise<void>): Promise<void> {
        try {
            await action();
            message = "";
        } catch (error) {
            reportError(error);
        }
    }

    // ---- search + columns ---------------------------------------------------

    function buildOrder(): PlainMessage<SortOrder> {
        if (!sortColumn) {
            return { value: { case: "none", value: {} } };
        }
        return {
            value: {
                case: "builtin",
                value: { column: sortColumn, reverse: sortReverse },
            },
        };
    }

    async function loadColumnsAndSort(): Promise<void> {
        const columnKey = activeColsKey(notesMode);
        const saved = await readJson<unknown>(columnKey, defaultColumns(notesMode));
        if (!Array.isArray(saved) || saved.some((key) => typeof key !== "string")) {
            throw new Error(`Saved preference "${columnKey}" must be a string list.`);
        }
        activeKeys = saved.filter((k) => columnByKey.has(k));
        if (activeKeys.length === 0) {
            activeKeys = defaultColumns(notesMode).filter((k) => columnByKey.has(k));
        }
        const sortKey = sortTypeKey(notesMode);
        const savedSortColumn = await readJson<unknown>(sortKey, "noteFld");
        if (typeof savedSortColumn !== "string") {
            throw new Error(`Saved preference "${sortKey}" must be a string.`);
        }
        sortColumn = savedSortColumn;
        const reverseKey = sortBackwardsKey(notesMode);
        const savedSortReverse = await readJson<unknown>(reverseKey, false);
        if (typeof savedSortReverse !== "boolean") {
            throw new Error(`Saved preference "${reverseKey}" must be a boolean.`);
        }
        sortReverse = savedSortReverse;
        await setActiveBrowserColumns({ vals: activeKeys });
    }

    async function doSearch(preserveSelection = false): Promise<void> {
        const order = buildOrder();
        const resp = notesMode
            ? await searchNotes({ search: query, order })
            : await searchCards({ search: query, order });
        const newIds = resp.ids;
        if (preserveSelection) {
            const alive = new Set(newIds.map((id) => id.toString()));
            selection = new Set([...selection].filter((k) => alive.has(k)));
        } else {
            selection = new Set();
            anchorIndex = -1;
            focusIndex = -1;
            if (scrollEl) {
                scrollEl.scrollTop = 0;
            }
            scrollTop = 0;
        }
        // Fresh cache + version bump so reused rows re-fetch (colors/edits).
        cache = new Map();
        rowVersion += 1;
        ids = newIds;
    }

    async function setup(): Promise<void> {
        phase = "loading";
        try {
            const all = await allBrowserColumns({});
            allColumns = all.columns;
            columnByKey = new Map(all.columns.map((c) => [c.key, c]));
            const configuredNotesMode = (
                await getConfigBool({
                    key: ConfigKey_Bool.BROWSER_TABLE_SHOW_NOTES_MODE,
                })
            ).val;
            notesMode = initialNotesMode ?? configuredNotesMode;
            if (
                initialNotesMode !== undefined &&
                initialNotesMode !== configuredNotesMode
            ) {
                await setConfigBool({
                    key: ConfigKey_Bool.BROWSER_TABLE_SHOW_NOTES_MODE,
                    value: notesMode,
                    undoable: false,
                });
            }
            await loadColumnsAndSort();
            phase = "ready";
            await doSearch();
            await tick();
            paneEl?.focus();
        } catch (error) {
            message = errorMessage(error);
            phase = "error";
        }
    }

    function onSubmit(event: Event): void {
        event.preventDefault();
        void runPaneAction(() => doSearch());
    }

    function runSearch(newQuery: string): void {
        query = newQuery;
        void runPaneAction(() => doSearch());
    }

    function searchFor(nextQuery: string): void {
        query = nextQuery;
        void runPaneAction(async () => {
            await doSearch();
            await tick();
            searchInput?.focus();
        });
    }

    function showCurrentDeck(): void {
        searchFor(DEFAULT_QUERY);
    }

    function showWholeCollection(): void {
        searchFor("");
    }

    async function toggleNotesMode(next: boolean): Promise<void> {
        if (next === notesMode) {
            return;
        }
        const previous = notesMode;
        notesMode = next;
        try {
            // browser_row_for_id reads this config, so it must be set first.
            await setConfigBool({
                key: ConfigKey_Bool.BROWSER_TABLE_SHOW_NOTES_MODE,
                value: notesMode,
                undoable: false,
            });
            await loadColumnsAndSort();
            await doSearch();
            message = "";
        } catch (error) {
            notesMode = previous;
            reportError(error);
        }
    }

    async function sortBy(col: BrowserColumns_Column): Promise<void> {
        if (!isSortable(col, notesMode)) {
            return;
        }
        const previousColumn = sortColumn;
        const previousReverse = sortReverse;
        if (sortColumn === col.key) {
            sortReverse = !sortReverse;
        } else {
            sortColumn = col.key;
            sortReverse = defaultReverse(col, notesMode);
        }
        try {
            await writeJson(sortTypeKey(notesMode), sortColumn);
            await writeJson(sortBackwardsKey(notesMode), sortReverse);
            await doSearch(true);
            message = "";
        } catch (error) {
            sortColumn = previousColumn;
            sortReverse = previousReverse;
            reportError(error);
        }
    }

    async function setColumns(keys: string[]): Promise<void> {
        if (keys.length === 0) {
            return;
        }
        try {
            await setActiveBrowserColumns({ vals: keys });
            await writeJson(activeColsKey(notesMode), keys);
            activeKeys = keys;
            cache = new Map();
            rowVersion += 1;
            message = "";
        } catch (error) {
            reportError(error);
        }
    }

    function toggleColumn(key: string): void {
        const keys = activeKeys.includes(key)
            ? activeKeys.filter((k) => k !== key)
            : [...activeKeys, key];
        void setColumns(keys);
    }

    function openColumnMenu(event: MouseEvent): void {
        const items: MenuItem[] = [{ type: "header", label: "Columns" }];
        const sorted = [...allColumns]
            .filter((c) => labelFor(c, notesMode))
            .sort((a, b) =>
                labelFor(a, notesMode).localeCompare(labelFor(b, notesMode)),
            );
        for (const col of sorted) {
            items.push({
                label: labelFor(col, notesMode),
                checked: activeKeys.includes(col.key),
                onClick: () => toggleColumn(col.key),
            });
        }
        columnMenu = { x: event.clientX, y: event.clientY, items };
    }

    // ---- selection ----------------------------------------------------------

    function selectAt(index: number, event: MouseEvent): void {
        const key = ids[index]?.toString();
        if (key === undefined) {
            return;
        }
        paneEl?.focus();
        if (event.button === 2) {
            // Right-click: select the row unless it's already in the selection.
            if (!selection.has(key)) {
                selection = new Set([key]);
                anchorIndex = index;
                focusIndex = index;
            }
            return;
        }
        if (event.shiftKey && anchorIndex >= 0) {
            const lo = Math.min(anchorIndex, index);
            const hi = Math.max(anchorIndex, index);
            const base =
                event.ctrlKey || event.metaKey ? new Set(selection) : new Set<string>();
            for (let i = lo; i <= hi; i++) {
                base.add(ids[i].toString());
            }
            selection = base;
        } else if (event.ctrlKey || event.metaKey) {
            const base = new Set(selection);
            if (base.has(key)) {
                base.delete(key);
            } else {
                base.add(key);
            }
            selection = base;
            anchorIndex = index;
        } else {
            selection = new Set([key]);
            anchorIndex = index;
        }
        focusIndex = index;
    }

    function scrollToFocus(): void {
        if (!scrollEl || focusIndex < 0) {
            return;
        }
        const y = focusIndex * ROW_HEIGHT;
        const top = scrollEl.scrollTop;
        const h = scrollEl.clientHeight;
        if (y < top) {
            scrollEl.scrollTop = y;
        } else if (y + ROW_HEIGHT > top + h) {
            scrollEl.scrollTop = y + ROW_HEIGHT - h;
        }
    }

    function moveFocus(next: number, extend: boolean): void {
        if (ids.length === 0) {
            return;
        }
        const clamped = Math.max(0, Math.min(ids.length - 1, next));
        if (extend && anchorIndex >= 0) {
            const lo = Math.min(anchorIndex, clamped);
            const hi = Math.max(anchorIndex, clamped);
            const base = new Set<string>();
            for (let i = lo; i <= hi; i++) {
                base.add(ids[i].toString());
            }
            selection = base;
        } else {
            selection = new Set([ids[clamped].toString()]);
            anchorIndex = clamped;
        }
        focusIndex = clamped;
        scrollToFocus();
    }

    function selectAll(): void {
        selection = new Set(ids.map((id) => id.toString()));
    }

    // ---- id resolution for row actions -------------------------------------

    function selectedNativeIds(): bigint[] {
        return [...selection].map((s) => BigInt(s));
    }

    async function resolveCardIds(): Promise<bigint[]> {
        const native = selectedNativeIds();
        if (!notesMode) {
            return native;
        }
        const out: bigint[] = [];
        for (const nid of native) {
            const res = await cardsOfNote({ nid });
            out.push(...res.cids);
        }
        if (native.length > 0 && out.length === 0) {
            throw new Error("Selected notes have no cards for this action.");
        }
        return out;
    }

    async function resolveNoteIds(): Promise<bigint[]> {
        const native = selectedNativeIds();
        if (notesMode) {
            return native;
        }
        const seen = new Set<string>();
        const out: bigint[] = [];
        for (const cid of native) {
            const card = await getCard({ cid });
            const key = card.noteId.toString();
            if (!seen.has(key)) {
                seen.add(key);
                out.push(card.noteId);
            }
        }
        if (native.length > 0 && out.length === 0) {
            throw new Error("Selected cards have no note for this action.");
        }
        return out;
    }

    // ---- row actions --------------------------------------------------------

    async function run(action: () => Promise<void>): Promise<void> {
        try {
            await action();
            await doSearch(true);
            message = "";
        } catch (error) {
            reportError(error);
        }
    }

    async function suspendSelected(): Promise<void> {
        const native = selectedNativeIds();
        await buryOrSuspendCards({
            cardIds: notesMode ? [] : native,
            noteIds: notesMode ? native : [],
            mode: BuryOrSuspendCardsRequest_Mode.SUSPEND,
        });
    }

    async function unsuspendSelected(): Promise<void> {
        const cids = await resolveCardIds();
        if (cids.length) {
            await restoreBuriedAndSuspendedCards({ cids });
        }
    }

    async function flagSelected(flag: number): Promise<void> {
        const cids = await resolveCardIds();
        if (cids.length) {
            await setFlag({ cardIds: cids, flag });
        }
    }

    async function addTagsSelected(): Promise<void> {
        const tags = normalizeTagPrompt(
            window.prompt("Tags to add (space separated):"),
        );
        if (!tags) {
            return;
        }
        const noteIds = await resolveNoteIds();
        if (noteIds.length) {
            await addNoteTags({ noteIds, tags });
        }
    }

    async function removeTagsSelected(): Promise<void> {
        const tags = normalizeTagPrompt(
            window.prompt("Tags to remove (space separated):"),
        );
        if (!tags) {
            return;
        }
        const noteIds = await resolveNoteIds();
        if (noteIds.length) {
            await removeNoteTags({ noteIds, tags });
        }
    }

    async function deleteSelected(): Promise<void> {
        const native = selectedNativeIds();
        if (native.length === 0) {
            return;
        }
        const noteIds = notesMode ? native : await resolveNoteIds();
        if (noteIds.length === 0) {
            return;
        }
        if (!window.confirm(deleteNotesConfirmation(noteIds.length))) {
            return;
        }
        await removeNotes({
            noteIds: notesMode ? native : [],
            cardIds: notesMode ? [] : native,
        });
    }

    function openRowMenu(index: number, event: MouseEvent): void {
        selectAt(index, event);
        const n = selection.size;
        const items: MenuItem[] = [
            { type: "header", label: `${n} selected` },
            { label: "Suspend", onClick: () => void run(suspendSelected) },
            { label: "Unsuspend", onClick: () => void run(unsuspendSelected) },
            { type: "separator" },
            { label: "Add tags…", onClick: () => void run(addTagsSelected) },
            { label: "Remove tags…", onClick: () => void run(removeTagsSelected) },
            { type: "separator" },
            { type: "header", label: "Flag" },
            ...FLAG_LABELS.map((label, flag) => ({
                label,
                onClick: () => void run(() => flagSelected(flag)),
            })),
            { type: "separator" },
            {
                label: deleteSelectionMenuLabel(n, notesMode),
                danger: true,
                onClick: () => void run(deleteSelected),
            },
        ];
        rowMenu = { x: event.clientX, y: event.clientY, items };
    }

    // ---- editor -------------------------------------------------------------

    async function resolveEditorNote(): Promise<void> {
        const token = ++editorToken;
        if (selection.size !== 1) {
            editorNoteId = 0n;
            return;
        }
        const native = BigInt([...selection][0]);
        if (notesMode) {
            editorNoteId = native;
            return;
        }
        try {
            const card = await getCard({ cid: native });
            if (token === editorToken) {
                editorNoteId = card.noteId;
            }
        } catch (error) {
            if (token === editorToken) {
                editorNoteId = 0n;
                reportError(error);
            }
        }
    }

    $: (selection, notesMode, void resolveEditorNote());

    function onEditorSaved(): void {
        // The row's cells changed; drop the cache + re-fetch visible rows.
        cache = new Map();
        rowVersion += 1;
    }

    // ---- find & replace -----------------------------------------------------

    async function openFindReplace(): Promise<void> {
        try {
            findReplaceNoteIds = selection.size > 0 ? await resolveNoteIds() : [];
            findReplaceOpen = true;
            message = "";
        } catch (error) {
            reportError(error);
        }
    }

    function onFindReplaceApplied(): void {
        void doSearch(true);
    }

    // ---- keyboard -----------------------------------------------------------

    function isEditingTarget(target: EventTarget | null): boolean {
        const el = target as HTMLElement | null;
        if (!el) {
            return false;
        }
        return (
            el.isContentEditable ||
            el.tagName === "INPUT" ||
            el.tagName === "TEXTAREA" ||
            el.tagName === "SELECT"
        );
    }

    function onKeydown(event: KeyboardEvent): void {
        const mod = event.ctrlKey || event.metaKey;
        // Global shortcuts work even while editing / typing a search.
        if (mod && event.key.toLowerCase() === "f" && event.altKey) {
            event.preventDefault();
            void openFindReplace();
            return;
        }
        if (mod && !event.altKey && event.key.toLowerCase() === "f") {
            event.preventDefault();
            searchInput?.focus();
            searchInput?.select();
            return;
        }
        if (isEditingTarget(event.target)) {
            return;
        }
        switch (event.key) {
            case "ArrowDown":
                event.preventDefault();
                moveFocus(focusIndex + 1, event.shiftKey);
                break;
            case "ArrowUp":
                event.preventDefault();
                moveFocus(focusIndex - 1, event.shiftKey);
                break;
            case "Home":
                event.preventDefault();
                moveFocus(0, event.shiftKey);
                break;
            case "End":
                event.preventDefault();
                moveFocus(ids.length - 1, event.shiftKey);
                break;
            default:
                if (mod && event.key.toLowerCase() === "a") {
                    event.preventDefault();
                    selectAll();
                } else if (
                    mod &&
                    (event.key === "Delete" || event.key === "Backspace")
                ) {
                    event.preventDefault();
                    void run(deleteSelected);
                }
        }
    }

    onMount(() => {
        void setup();
    });
</script>

{#if phase === "error"}
    <PaneState phase="error" {message} onRetry={setup} />
{:else}
    <div
        class="browse-pane"
        data-testid="browse-pane"
        bind:this={paneEl}
        tabindex="-1"
        role="grid"
        aria-label="Browse"
        on:keydown={onKeydown}
    >
        <form class="toolbar" on:submit={onSubmit}>
            <button
                type="button"
                class="tool-btn"
                class:on={showSidebar}
                title="Toggle sidebar"
                aria-label="Toggle sidebar"
                aria-pressed={showSidebar}
                on:click={() => (showSidebar = !showSidebar)}
            >
                ☰
            </button>
            <input
                bind:this={searchInput}
                bind:value={query}
                placeholder="Search…"
                aria-label="Search"
                data-testid="browse-search"
                spellcheck="false"
            />
            <span class="count tabular" title="Matches">{total}</span>
            <div class="mode" role="group" aria-label="Row mode">
                <button
                    type="button"
                    class:active={!notesMode}
                    aria-pressed={!notesMode}
                    on:click={() => toggleNotesMode(false)}
                >
                    Cards
                </button>
                <button
                    type="button"
                    class:active={notesMode}
                    aria-pressed={notesMode}
                    on:click={() => toggleNotesMode(true)}
                >
                    Notes
                </button>
            </div>
            <button
                type="button"
                class="tool-btn"
                title="Columns"
                aria-label="Columns"
                on:click={openColumnMenu}
            >
                ▦
            </button>
            <button
                type="button"
                class="tool-btn"
                title="Find and replace (Ctrl+Alt+F)"
                aria-label="Find and replace"
                on:click={openFindReplace}
            >
                ⇄
            </button>
        </form>

        <div class="body">
            {#if showSidebar}
                <div class="sidebar-host">
                    <BrowseSidebar {query} onSearch={runSearch} />
                </div>
            {/if}

            <div class="main">
                <div class="table-region">
                    <div class="col-head" style="grid-template-columns:{gridTemplate}">
                        {#each activeColumns as col (col.key)}
                            <button
                                type="button"
                                class="col-label"
                                class:sortable={isSortable(col, notesMode)}
                                on:click={() => sortBy(col)}
                                on:contextmenu|preventDefault={openColumnMenu}
                                title={labelFor(col, notesMode)}
                            >
                                <span class="col-text">{labelFor(col, notesMode)}</span>
                                {#if sortColumn === col.key}
                                    <span class="sort-caret" aria-hidden="true">
                                        {sortReverse ? "▾" : "▴"}
                                    </span>
                                {/if}
                            </button>
                        {/each}
                    </div>

                    <div
                        class="table-body"
                        bind:this={scrollEl}
                        bind:clientHeight={viewportH}
                        on:scroll={() => (scrollTop = scrollEl?.scrollTop ?? 0)}
                    >
                        {#if total === 0 && phase === "ready"}
                            <div class="empty" data-testid="browse-empty">
                                <div class="empty-mark" aria-hidden="true">0</div>
                                <p class="empty-title">{emptyTitle}</p>
                                <p class="empty-detail">{emptyDetail}</p>
                                {#if hasRecoverableSearch}
                                    <button
                                        type="button"
                                        class="empty-action"
                                        data-testid="browse-clear-search"
                                        on:click={showCurrentDeck}
                                    >
                                        Show current deck
                                    </button>
                                {/if}
                                {#if canShowWholeCollection}
                                    <button
                                        type="button"
                                        class="empty-action secondary"
                                        data-testid="browse-show-all"
                                        on:click={showWholeCollection}
                                    >
                                        Show whole collection
                                    </button>
                                {/if}
                            </div>
                        {:else}
                            <div
                                class="table-spacer"
                                style="height:{total * ROW_HEIGHT}px"
                            >
                                {#each visible as index (index)}
                                    <BrowseRow
                                        id={ids[index]}
                                        columnCount={activeColumns.length}
                                        {gridTemplate}
                                        top={index * ROW_HEIGHT}
                                        selected={selection.has(ids[index].toString())}
                                        focused={focusIndex === index}
                                        version={rowVersion}
                                        {cache}
                                        onSelect={(e) => selectAt(index, e)}
                                        onContextMenu={(e) => openRowMenu(index, e)}
                                    />
                                {/each}
                            </div>
                        {/if}
                    </div>
                </div>

                {#if showEditor}
                    <div class="editor-region">
                        <BrowseEditor noteId={editorNoteId} onSaved={onEditorSaved} />
                    </div>
                {/if}
            </div>
        </div>

        {#if message && phase === "ready"}
            <p class="pane-error" role="alert">{message}</p>
        {/if}
    </div>

    {#if rowMenu}
        <ContextMenu
            x={rowMenu.x}
            y={rowMenu.y}
            items={rowMenu.items}
            onClose={() => (rowMenu = null)}
        />
    {/if}
    {#if columnMenu}
        <ContextMenu
            x={columnMenu.x}
            y={columnMenu.y}
            items={columnMenu.items}
            onClose={() => (columnMenu = null)}
        />
    {/if}
    {#if findReplaceOpen}
        <FindReplaceDialog
            noteIds={findReplaceNoteIds}
            onClose={() => (findReplaceOpen = false)}
            onApplied={onFindReplaceApplied}
        />
    {/if}
{/if}

<style lang="scss">
    .browse-pane {
        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        color: var(--fg);
        outline: none;
    }

    .toolbar {
        display: flex;
        align-items: center;
        gap: var(--space-sm);
        flex: 0 0 auto;
        padding: var(--space-sm) var(--space-md);
        background: var(--canvas);
        border-bottom: 1px solid var(--border-subtle);

        input {
            flex: 1;
            min-width: 0;
            font: inherit;
            font-size: var(--type-callout-size);
            color: var(--fg);
            background: var(--canvas-inset);
            border: 1px solid var(--border-control);
            border-radius: var(--border-radius);
            padding: var(--space-xs) var(--space-sm);

            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: 1px;
                border-color: var(--accent);
            }
        }

        .count {
            font-size: var(--type-caption-size);
            color: var(--fg-subtle);
            min-width: 3ch;
            text-align: right;
        }
    }

    .tool-btn {
        flex: 0 0 auto;
        display: grid;
        place-items: center;
        width: 28px;
        height: 28px;
        font-size: 14px;
        color: var(--fg-subtle);
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--border-radius);
        cursor: pointer;

        &:hover {
            background: var(--canvas-elevated);
            color: var(--fg);
        }

        &.on {
            color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
        }
    }

    .mode {
        display: flex;
        flex: 0 0 auto;
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        overflow: hidden;

        button {
            font: inherit;
            font-size: var(--type-caption-size);
            font-weight: 600;
            color: var(--fg-subtle);
            background: var(--canvas-inset);
            border: 0;
            padding: var(--space-xxs) var(--space-sm);
            cursor: pointer;

            &.active {
                color: #fff;
                background: var(--button-primary-bg);
            }

            &:focus-visible {
                outline: 2px solid var(--accent);
                outline-offset: -2px;
            }
        }
    }

    .body {
        flex: 1;
        min-height: 0;
        display: flex;
    }

    .sidebar-host {
        flex: 0 0 auto;
        width: 216px;
        min-width: 0;
        height: 100%;
        overflow: hidden;
    }

    .main {
        flex: 1;
        min-width: 0;
        min-height: 0;
        display: flex;
        flex-direction: column;
    }

    .table-region {
        flex: 1;
        min-height: 0;
        display: flex;
        flex-direction: column;
    }

    .col-head {
        display: grid;
        align-items: stretch;
        flex: 0 0 auto;
        height: 30px;
        padding: 0 var(--space-md);
        background: var(--canvas-elevated);
        border-bottom: 1px solid var(--border);
    }

    .col-label {
        display: flex;
        align-items: center;
        gap: 2px;
        min-width: 0;
        font: inherit;
        font-size: var(--type-micro-size);
        font-weight: var(--type-micro-weight);
        letter-spacing: var(--type-micro-tracking);
        text-transform: uppercase;
        color: var(--fg-subtle);
        background: transparent;
        border: 0;
        padding: 0 var(--space-sm) 0 0;
        text-align: left;
        cursor: default;

        &.sortable {
            cursor: pointer;

            &:hover {
                color: var(--fg);
            }
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: -2px;
        }
    }

    .col-text {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .sort-caret {
        flex: 0 0 auto;
        color: var(--accent);
        font-size: 9px;
    }

    .table-body {
        flex: 1;
        min-height: 0;
        overflow: auto;
        position: relative;
    }

    .table-spacer {
        position: relative;
        width: 100%;
    }

    .empty {
        min-height: 100%;
        padding: var(--space-xl);
        display: grid;
        align-content: center;
        justify-items: center;
        gap: var(--space-sm);
        color: var(--fg-subtle);
        text-align: center;
    }

    .empty-mark {
        display: grid;
        place-items: center;
        width: 42px;
        height: 42px;
        border: 1px solid var(--border-subtle);
        border-radius: 50%;
        background: var(--canvas-elevated);
        color: var(--fg-faint);
        font-size: 21px;
        font-weight: 750;
        line-height: 1;
    }

    .empty-title {
        margin: 0;
        color: var(--fg);
        font-weight: 650;
    }

    .empty-detail {
        max-width: 30rem;
        margin: 0;
        color: var(--fg-subtle);
        line-height: 1.45;
    }

    .empty-action {
        min-height: 34px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 0 var(--space-md);
        border: 1px solid color-mix(in srgb, var(--accent) 24%, transparent);
        border-radius: var(--border-radius-sm);
        background: var(--accent-tint);
        color: var(--accent);
        font-size: var(--type-caption-size);
        font-weight: 700;
        cursor: pointer;

        &:hover {
            background: var(--canvas-inset);
        }

        &:active {
            transform: translateY(1px);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }

        &.secondary {
            background: transparent;
            color: var(--fg-subtle);

            &:hover {
                background: var(--canvas-inset);
                color: var(--fg);
            }
        }
    }

    .editor-region {
        flex: 0 0 45%;
        min-height: 160px;
        display: flex;
        flex-direction: column;
    }

    .pane-error {
        margin: 0;
        flex: 0 0 auto;
        padding: var(--space-xs) var(--space-md);
        color: var(--fg-error);
        font-size: var(--type-caption-size);
        border-top: 1px solid var(--border-subtle);
    }
</style>
