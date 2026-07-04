# pylib/anki

Read before editing pylib/anki.

The Python library wrapping the Rust layer. This is the Python<->Rust seam:
high-level collection and scheduler abstractions delegate to the Rust backend
over PyO3, with each protobuf RPC exposed as a snake_case Python method.

## What lives here

- `_backend.py` — the RPC bridge. `RustBackend` subclasses the generated
  `RustBackendGenerated` and implements `_run_command(service, method, bytes)`,
  which calls into `_rsbridge.open_backend(...)`'s backend. Handles protobuf
  error mapping, logging, and thread-safety checks.
- `collection.py` — main public API. `Collection` holds a private `_backend`
  and delegates persistent operations to it, exposing public managers instead.
- `scheduler/` — wrapper package. `base.py` (`SchedulerBase`) exposes backend
  scheduler RPCs; `v3.py` (`Scheduler`) adds V3 operations (`get_queued_cards`,
  `answer_card`); `dummy.py`/`legacy.py` cover non-V3 paths.
- `dbproxy.py` — `DBProxy` translates the Python DB API to backend `db_*`
  calls, serializing via JSON (`db_command` is the only JSON-based RPC).
- `models.py`, `decks.py`, `cards.py` — domain managers wrapping notetype,
  deck/config, and card RPCs over their `*_pb2` message types.

## Entry points

- `Collection(path, backend=None, server=False)` — opens an `.anki2` file,
  initializes managers and the scheduler.
- `Collection.sched` — `Scheduler` or `DummyScheduler` per `v3_scheduler()`.
- `Collection.models`/`decks`/`tags`/`conf`/`media`/`db` — domain APIs.
- `Collection.find_cards`/`find_notes(query)` — search RPCs.
- `RustBackend(langs=None, server=False)` — low-level backend construction.

## Gotchas (non-obvious)

- `RustBackendGenerated` is auto-generated at build time to
  `out/pylib/anki/_backend_generated.py` (not in the source tree). Imports fail
  if the build is incomplete.
- `_run_command(service, method, bytes)` takes raw bytes, not a message — the
  generated wrappers call `.SerializeToString()` and parse the reply.
- On import, `_rsbridge.buildhash()` must match `anki.buildinfo.buildhash` or
  import raises (version-skew detection).
- `Collection._backend` is private/deprecated — use the public managers.
- `SchedulerBase.today`/`day_cutoff` call the backend on each access; not cached.
- `DBProxy.transact()` auto-rolls back on exception; handle `DBError` yourself.

## Cross-references

- Proto in `proto/anki/*.proto` (e.g. `backend.proto`) is the source of truth
  for service/method indices and RPC signatures; this layer imports the
  generated `*_pb2` modules.
- `rslib/proto/python.rs` (`write_python_interface`) generates
  `RustBackendGenerated` (each RPC as `name_raw(bytes)` and `name(params)`).
- `pylib/rsbridge/lib.rs` is the PyO3 bridge to `rslib/backend`.
- `pylib/hatch_build.py` packages generated `*_pb2.py` and the compiled
  `_rsbridge` extension into the wheel.

## Ankountant work

This subtree tracks upstream Anki's pylib/anki; it is a passthrough to the Rust
backend with no fork-specific logic. Add domain behavior in `rslib/backend`
(Rust) and surface it here by regenerating the backend interface. After
proto changes, run a full `just check`; for pylib iteration use `just build`,
then `just test-py` / `just lint`.
