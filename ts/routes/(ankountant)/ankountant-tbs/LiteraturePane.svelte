<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Read-only authoritative-literature browser (T2 / OQ-3): client-side search over
the bundled, per-section corpus. Handles BOTH corpus bodies (D10): FASB ASC
(FAR/BAR) shows OUR paraphrase + a deep link to asc.fasb.org (cite-only, Tier-B);
IRC/PCAOB/NIST show real verbatim public-domain text. Also usable as a standalone
tileable pane. Optional `onCite` fills a caller's citation input (intra-surface
sync — the cross-pane version is impossible without a shared store).
-->
<script lang="ts">
    import {
        corpusForSection,
        searchCorpus,
        type CorpusEntry,
    } from "../ankountant-research/lib";

    export let section: string;
    /** Optional: called when the learner clicks "Use this citation". */
    export let onCite: ((citation: string) => void) | undefined = undefined;
    export let citationEnabled = true;

    let query = "";
    let entries: CorpusEntry[] = [];
    let corpusError: string | null = null;
    $: {
        try {
            entries = corpusForSection(section);
            corpusError = null;
        } catch (error) {
            entries = [];
            corpusError = error instanceof Error ? error.message : String(error);
        }
    }
    $: results = corpusError ? [] : searchCorpus(entries, query);

    function clearSearch(): void {
        query = "";
    }
</script>

<div class="literature" data-testid="literature">
    <div class="lit-head">
        <h2>Authoritative literature — {section}</h2>
        <label class="search">
            <span class="sr-only">Search literature</span>
            <input
                type="search"
                data-testid="lit-search"
                bind:value={query}
                placeholder="Search the {section} literature…"
            />
        </label>
    </div>

    <ul class="results" data-testid="lit-results">
        {#if corpusError}
            <li class="error card" data-testid="lit-error" role="alert">
                Literature unavailable: {corpusError}
            </li>
        {:else}
            {#each results as e (e.id)}
                <li
                    class="result card"
                    data-testid="lit-result"
                    data-citation={e.citation}
                >
                    <div class="result-head">
                        <span class="cite">{e.citation}</span>
                        <span class="kind-tag" class:verbatim={e.verbatim}>
                            {e.verbatim
                                ? "Verbatim · public domain"
                                : "Paraphrase · cite-only"}
                        </span>
                    </div>
                    <p class="title">{e.title}</p>
                    <p class="body" class:paraphrase={!e.verbatim}>{e.body}</p>
                    <div class="result-actions">
                        {#if e.deepLink}
                            <a
                                class="deep-link"
                                href={e.deepLink}
                                target="_blank"
                                rel="noreferrer noopener"
                                data-testid="lit-deeplink"
                            >
                                Open source ↗
                            </a>
                        {/if}
                        {#if onCite}
                            <button
                                type="button"
                                class="cite-btn"
                                data-testid="lit-cite"
                                disabled={!citationEnabled}
                                on:click={() => onCite?.(e.citation)}
                            >
                                Use this citation
                            </button>
                        {/if}
                    </div>
                </li>
            {/each}
        {/if}
        {#if !corpusError && results.length === 0}
            <li class="empty" data-testid="lit-none">
                <span>
                    {query
                        ? `No passages match "${query}".`
                        : "No literature bundled for this section yet."}
                </span>
                {#if query}
                    <button
                        type="button"
                        class="clear-search"
                        data-testid="lit-clear-search"
                        on:click={clearSearch}
                    >
                        Clear search
                    </button>
                {/if}
            </li>
        {/if}
    </ul>
</div>

<style lang="scss">
    .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    .literature {
        display: flex;
        flex-direction: column;
        gap: var(--space-md);
        height: 100%;
        min-height: 0;
    }

    .lit-head {
        h2 {
            margin: 0 0 var(--space-sm);
            font-size: 12px;
            font-weight: 600;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            color: var(--fg-subtle);
        }
    }

    .search input {
        width: 100%;
        box-sizing: border-box;
        min-height: 36px;
        padding: var(--space-sm) var(--space-md);
        font: inherit;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
            border-color: var(--accent);
        }
    }

    .results {
        flex: 1;
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--space-sm);
        overflow: auto;
        min-height: 0;
    }

    .card {
        background: var(--canvas-elevated);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius-medium);
        box-shadow: var(--elevation-e1);
    }

    .result {
        padding: var(--space-md);
    }

    .error {
        padding: var(--space-md);
        color: var(--fg-error);
    }

    .result-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--space-sm);
    }

    .cite {
        font-family: var(--font-mono);
        font-weight: 600;
        color: var(--accent);
    }

    .kind-tag {
        flex: none;
        font-size: 10px;
        font-weight: 600;
        letter-spacing: 0.03em;
        text-transform: uppercase;
        color: var(--fg-subtle);
        border: 1px solid var(--border-subtle);
        border-radius: var(--border-radius);
        padding: 1px var(--space-xs);

        &.verbatim {
            color: var(--accent);
            border-color: var(--accent);
        }
    }

    .title {
        margin: var(--space-xs) 0;
        font-weight: 600;
    }

    .body {
        margin: 0;
        font-size: 13px;
        line-height: 1.5;
        color: var(--fg-subtle);
        max-width: 66ch;

        &.paraphrase {
            font-style: italic;
        }
    }

    .result-actions {
        display: flex;
        gap: var(--space-md);
        align-items: center;
        margin-top: var(--space-sm);
    }

    .deep-link {
        font-size: 13px;
        color: var(--accent);
    }

    .cite-btn {
        font: inherit;
        font-size: 13px;
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xs) var(--space-md);
        cursor: pointer;

        &:hover:not([disabled]) {
            border-color: var(--accent);
            color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent) !important;
            outline-offset: 2px;
        }

        &[disabled] {
            opacity: 0.6;
            cursor: not-allowed;
        }
    }

    .empty {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--space-sm);
        color: var(--fg-subtle);
        font-size: var(--type-caption-size);
    }

    .clear-search {
        font: inherit;
        font-size: var(--type-caption-size);
        font-weight: 600;
        color: var(--fg);
        background: var(--canvas-inset);
        border: 1px solid var(--border-control);
        border-radius: var(--border-radius);
        padding: var(--space-xxs) var(--space-sm);
        cursor: pointer;

        &:hover {
            border-color: var(--accent);
            color: var(--accent);
        }

        &:focus-visible {
            outline: 2px solid var(--accent);
            outline-offset: 2px;
        }
    }
</style>
