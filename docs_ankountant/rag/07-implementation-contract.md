# 7 — Implementation Contract (`tools/cardgen/`)

[← Provenance & ops](06-provenance-output-and-ops.md) · [Index](README.md)

> The build contract for the Phase-2a pipeline. Design rationale is in docs 1–6
> and ADRs 0003/0009; **this doc is the interface every module codes against** so
> the pieces integrate. Stack per **ADR 0009**: OpenAI `gpt-5-mini` gen (model-aware
> chat params; `gpt-4o` fallback) + `text-embedding-3-small` + LanceDB (vector +
> BM25) + a hybrid-arm reranker + in-session Cursor-subagent judge, with a
> deterministic **offline** backend for keyless tests.

## Principles

- **Offline-first.** Every provider (embed / generate / judge) has a
  deterministic **offline** backend selected when `CARDGEN_OFFLINE=1` or no key is
  present. `just` and CI run fully offline, no secrets, no network.
- **Resumable DAG.** Each stage reads the prior stage's artifact and writes its
  own under `tools/cardgen/out/<run_id>/<NN-stage>/`, keyed by a content hash;
  re-runs skip unchanged work.
- **Provenance or drop.** No card leaves a stage without `source_passage` +
  `source_id`/`locator` + `gen_method`; self-check proves the passage is a real
  substring of a retrieved chunk.
- **Secrets** live only in gitignored `tools/cardgen/.env`
  (`OPENAI_API_KEY=...`); never logged, never committed.

## Repo layout

```
tools/cardgen/
  pyproject.toml            # standalone (uv); not shipped in wheels/xcframework
  README.md
  .env.example              # OPENAI_API_KEY=...   (.env is gitignored)
  cardgen/
    __init__.py
    config.py               # RunConfig, model IDs, paths, offline flag
    models.py               # dataclasses: Chunk, WorkItem, Candidate, Verdict, EmittedNote
    providers/
      __init__.py
      base.py               # Embedder / Generator / Judge protocols
      openai_embed.py       # text-embedding-3-small
      openai_generate.py    # gpt-4o-mini
      offline.py            # deterministic embedder+generator+judge (hash-based)
      cursor_judge.py       # file-based subagent judge contract (see §Judge)
    ingest.py chunk.py index.py            # stages 0–3
    taxonomy.py worklist.py                # stages 4
    retrieve.py generate.py                # stages 5–6
    selfcheck.py judge.py                  # stages 7–8
    leakage.py dedup.py baseline.py        # stages 9–11
    emit.py                                # stage 12  (genanki)
    reports.py                             # coverage_report.md, baseline_report.md
    cli.py                                 # `python -m cardgen.cli <stage|all> ...`
  taxonomy/                 # taxonomy.<section>.yaml, confusion_catalog.<section>.yaml
  corpus/                   # source snapshots + manifest.json (gitignored, large)
  gold/                     # gold.<section>.jsonl (positive+negative)
  out/                      # run artifacts, LanceDB index, .apkg (gitignored)
  tests/                    # pytest, all offline
```

## Config & CLI

`RunConfig` fields: `run_id`, `sections: list[str]`, `target_total: int`
(default 900 proof; 50000 full), `offline: bool`, `gen_model="gpt-5-mini"`,
`gen_fallback_model="gpt-4o"`, `gen_reasoning_effort="low"`,
`embed_model="text-embedding-3-small"`, `prompt_version="v2"`, `judge_batch=25`,
`top_k=6`, `relevance_floor`, `leakage_threshold=0.92`, `dedup_threshold=0.95`,
`seed=0`, plus scale/quality knobs: `rerank=True` + `rerank_model="gpt-4o-mini"`
(hybrid-arm reranker), `gen_concurrency=24` / `embed_concurrency=8` /
`use_batch_api=False` (fan-out), `judge_mode="full"|"audit"` +
`audit_fraction=0.10` / `audit_min=50` / `judge_parallelism=8` (scaled judging).
All are env-overridable (`CARDGEN_*`, see `.env.example`).

CLI: `python -m cardgen.cli all --sections FAR,REG,AUD,BAR,ISC,TCP --target 900`
runs the DAG up to the judge, **pauses** for the Cursor-subagent judge (writes a
judge queue + a `queue/plan.json` wave plan for N parallel subagents), then
`... resume` continues. Flags: `--gen-model`, `--prompt-version {v1,v2}`,
`--no-rerank`, `--concurrency`, `--batch-api`, `--judge-mode {full,audit}`,
`--judge-parallelism`. `just cardgen` wraps it; `scripts/fetch_corpus.py`
registers Tier-A corpus (Stage 0). Generation is resumable/idempotent (existing
candidates are skipped), so `all`/`resume` re-runs cheaply.

## Provider interfaces (`providers/base.py`)

```python
class Embedder(Protocol):
    def embed(self, texts: list[str]) -> list[list[float]]: ...
    dim: int

class Generator(Protocol):
    # returns raw model JSON text (parsed+validated by selfcheck)
    def generate(self, system: str, user: str, *, seed: int) -> str: ...

class Judge(Protocol):
    # cards: list of {id, card, source_passage, citation}; returns Verdict per id
    def judge(self, cards: list[dict], rubric: str) -> list["Verdict"]: ...
```

**Offline backends** must be deterministic (hash of input → stable vector /
stable well-formed card JSON / stable verdict), so tests assert exact outputs.

## Stage DAG (artifact contracts)

| #  | Stage     | Reads                       | Writes                                                                                                                           |
| -- | --------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 0  | snapshot  | corpus sources              | `corpus/manifest.json` `[{source_id,title,path/url,tier,license,sha256,retrieved_at}]`                                           |
| 1  | ingest    | manifest                    | `00-ingest/<source_id>.jsonl` `{source_id,locator,heading_path,text}`                                                            |
| 2  | chunk     | ingest                      | `01-chunks/<section>.jsonl` `{chunk_id,source_id,locator,license,heading_path,section,text}`                                     |
| 3  | index     | chunks                      | LanceDB table `chunks` (cols: `chunk_id,section,text,vector,source_id,locator,license`) + BM25 FTS; `02-index/index_version.txt` |
| 4  | worklist  | taxonomy+catalog            | `03-worklist/worklist.jsonl` `{item_id,section,area,topic,task_id,skill_level,card_type,seed}`                                   |
| 5  | retrieve  | worklist+index              | `04-retrieved/<item_id>.json` `{item_id,passages:[{chunk_id,text,source_id,locator,score}],arm}`                                 |
| 6  | generate  | retrieved                   | `05-candidates/<item_id>.json` → `Candidate` (see §models)                                                                       |
| 7  | selfcheck | candidates                  | `06-checked/passed.jsonl` + `dropped.jsonl{reason}`                                                                              |
| 8  | judge     | checked                     | `07-judge/queue/*.json` (out) → `07-judge/verdicts/*.json` (in) → `07-judge/graded.jsonl`                                        |
| 9  | leakage   | graded + sealed bank        | `08-leak/kept.jsonl` + `dropped.jsonl`                                                                                           |
| 10 | dedup     | kept                        | `09-dedup/kept.jsonl` + `dropped.jsonl`                                                                                          |
| 11 | baseline  | held-out slice (arms A/B/C) | `out/baseline_report.md` + `10-baseline/metrics.json`                                                                            |
| 12 | emit      | dedup kept                  | `out/cpa_bank.apkg` + `out/confusable_patch.json` + `out/coverage_report.md`                                                     |

## Core record (`models.py`)

```python
@dataclass
class Candidate:
    item_id: str
    section: str            # FAR|REG|AUD|BAR|ISC|TCP
    card_type: str          # recall | mcq | tbs_research | tbs_numeric | tbs_je | tbs_doc_review
    payload: dict           # shape-specific (see Emit)
    source_passage: str     # verbatim substring of a retrieved chunk (proven in selfcheck)
    source_id: str
    locator: str
    citation: str           # ASC/IRC/PCAOB § shown to candidate
    gen_method: dict        # {model, prompt_version, retrieval_config, index_version, arm, seed}
    tags: list[str]         # sec::X, cog::rote|applied, topic::..., ds::... (as applicable)
```

## Emit contract (must match the app exactly)

Field orders are authoritative in `rslib/src/ankountant/notetypes.rs`. genanki
models MUST mirror names+order. `gen_method` is JSON-stringified into the
`gen_method` field; `checker_status` = judge bucket (`pass`/`reworked`/`wrong`).

**`Ankountant Study`** (recall) — extended by WS `rust-provenance` to:
`["Front","Back","source_passage","gen_method","checker_status"]`. Back =
`"{back}\n\nSource: {citation}"`. Deck `Ankountant::Study::<section>::<topic>`,
tags `sec::<S>`, `cog::rote`, `topic::…`. Cards ARE queued for FSRS.

**`Ankountant TBS`** — 8 fields:
`["tbs_type","prompt","exhibits_json","steps_json","schema_tag","source_passage","gen_method","checker_status"]`.
Deck `Ankountant::Sealed::<section>::<set_id>`, **suspended**, tags
`sec::<S>` + one `ds::…`. `exhibits_json` = JSON array of
`{id,title,kind,role?,body,columns?,rows?}`. `steps_json` per shape:

- `research`: exactly one step `{"id":"citation","kind":"citation","answer_key":[<accepted…>],"weight":1.0,"label":…,"corpus_refs":[…],"granularity":"paragraph"}`
- `numeric`: `{"id":…,"kind":"numeric","answer_key":<number>,"weight":w,"label":…,"tolerance":t}`
- `journal_entry`: `{"id":…,"kind":"je","answer_key":{"account":…,"side":"dr|cr","amount":<num>},"weight":w}`
- `doc_review`: document exhibit `role:"document"` with `<blank step="s1">…</blank>` markers; steps `{"id":"s1","kind":"blank","answer_key":"<option_id>","weight":w,"options":[{"id":"o1","kind":"keep|delete|replace","text":…}],"confusion_set_id":…,"original_text":…}`

**MCQ / confusion** — `Ankountant TBS` note, `tbs_type:"mcq"`,
`steps_json:[{"id":"choice","answer_key":"<treatment>","weight":1.0}]`,
`schema_tag` = the item's `ds::…`. Treatments live in the CONFUSABLE map, **not**
in the note → emit also appends `{section,set_id,tags,treatments}` to
`out/confusable_patch.json`. **Integration note:** `.apkg` cannot carry `col`
config, so shipping confusion items requires applying the patch (small follow-up:
extend the seed/config loader). Recall + all four TBS shapes + doc-review are
self-contained in the `.apkg`; **prioritize those**, MCQ best-effort.

**Notetype matching note:** import into a collection where the app's note types
already exist (they're created lazily by name); genanki models must use the same
name+field order so notes bind to them. The verify step confirms cards render and
are found by the app's deck/tag queries.

## Gold set (`gold/gold.<section>.jsonl`)

`{id, polarity: "positive"|"negative", card_type, payload, citation, expected_bucket, defect?}`.
Bootstrap **positive** gold from the already-verified `rslib/src/ankountant/seed_content.json`;
**author negatives** by mutating positives (wrong number, outdated standard,
two-facts-in-one). Judge calibration reports precision/recall on negatives.

## Baseline A/B/C

On a held-out worklist slice, run stage 5 three times — `arm=bm25`, `arm=vector`,
`arm=hybrid` — through generate→selfcheck→judge, score each with faithfulness /
answer-relevancy / context-precision/recall (Ragas or our own metric fn using
the offline/live judge). `baseline_report.md` = per-arm metrics + deltas + example
wins; **success = hybrid beats both baselines** on faithfulness + bucket-1 rate.

## Testing & `just`

- `just cardgen` → run DAG (proof defaults). `just cardgen-full` → `--target 50000`.
- `just test-cardgen` → `uv run pytest tools/cardgen/tests` (offline, keyless).
- Wire `test-cardgen` into `just check` (or `just test-py`) so the pipeline is
  gated. All tests use the offline backends; **no test needs a key or network.**
