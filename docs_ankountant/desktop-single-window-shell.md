# Desktop single-window Ankountant shell — build spec

> Status: **Verified plan + prototype (source of truth)** · Owner: eric · Last updated: 2026-07-01
> Goal: the three Ankountant screens (Readiness Dashboard, Confusion-Set Review, TBS Practice) — today each a **separate OS window** — become **one in-app surface inside the main window with back navigation**, mirroring how the core loop already swaps content in a single window.
>
> Everything below is verified against the code on `main` (file:line evidence in §2). Implement exactly this.

---

## 1. Goal & shape

- Open the Ankountant screens **inside the main window** (no new `QDialog` windows).
- Navigate **dashboard ↔ confusion ↔ TBS** and **back to Decks** with in-app buttons (SPA client routing + a persistent shell top bar).
- Reuse the existing single-window state machine (`AnkiQt.moveToState`) — add one new state, `"ankountant"`, that shows a persistent shell webview hosting a routed SvelteKit surface.
- Zero new backend RPCs; zero `mediasrv` route/whitelist changes (we keep the existing flat route URLs via a SvelteKit **route group**).

---

## 2. Verified current architecture (evidence)

**Main window is ONE window** with a stacked central layout (top toolbar web / main web / bottom web):

```951:966:qt/aqt/main.py
tweb = self.toolbarWeb = TopWebView(self)
self.toolbar = Toolbar(self, tweb)
...
self.web = MainWebView(self)
...
self.mainLayout = QVBoxLayout()
self.mainLayout.addWidget(tweb)
self.mainLayout.addWidget(self.web)
self.mainLayout.addWidget(sweb)
self.form.centralwidget.setLayout(self.mainLayout)
```

**Core loop is already single-window** via a string state machine (`moveToState` → `_<state>State` / optional `_<state>Cleanup`):

```758:788:qt/aqt/main.py
def moveToState(self, state: MainWindowState, *args: Any) -> None:
    oldState = self.state
    cleanup = getattr(self, f"_{oldState}Cleanup", None)
    if cleanup: cleanup(state)
    ...
    getattr(self, f"_{state}State", lambda *_: None)(oldState, *args)
```

`MainWindowState` is a closed `Literal` — a new state must be added here:

```85:86:qt/aqt/main.py
MainWindowState = Literal[
    "startup", "deckBrowser", "overview", "review", "resetRequired", "profileManager"
]
```

**The three screens are separate windows today** — `QDialog` subclasses, one webview each, launched from the menu:

```24:49:qt/aqt/ankountant.py
class _AnkountantPageDialog(QDialog):
    def _setup_ui(self) -> None:
        ...
        self.web = AnkiWebView(kind=self.KIND)
        self.web.load_sveltekit_page(self.PAGE)
```

```1486:1500:qt/aqt/main.py
dashboard = menu.addAction("Readiness Dashboard")
qconnect(dashboard.triggered, lambda: aqt.ankountant.AnkountantDashboardDialog(self))
confusion = menu.addAction("Confusion-Set Review")
qconnect(confusion.triggered, lambda: aqt.ankountant.AnkountantConfusionDialog(self))
tbs = menu.addAction("TBS Practice")
qconnect(tbs.triggered, lambda: aqt.ankountant.AnkountantTbsDialog(self))
```

**All three webview kinds already share the API-access profile** → they can share ONE webview:

```62:64:qt/aqt/webview.py
ANKOUNTANT_DASHBOARD = "ankountant dashboard"
ANKOUNTANT_CONFUSION = "ankountant confusion"
ANKOUNTANT_TBS = "ankountant tbs"
```

```138:151:qt/aqt/webview.py
def _profileForPage(self, kind: AnkiWebViewKind) -> QWebEngineProfile:
    have_api_access = kind in (
        ...
        AnkiWebViewKind.ANKOUNTANT_DASHBOARD,
        AnkiWebViewKind.ANKOUNTANT_CONFUSION,
        AnkiWebViewKind.ANKOUNTANT_TBS,
    )
```

**The web layer is already a client-routed SPA** (static adapter + `index.html` fallback; SSR/prerender off; shared root layout):

```16:19:ts/svelte.config.js
adapter: adapter(
    { pages: "../out/sveltekit", fallback: "index.html", precompress: false },
),
```

```9:15:ts/routes/+layout.ts
export const ssr = false;
export const prerender = false;
export const load: LayoutLoad = async () => {
    checkNightMode();
    await setupGlobalI18n();
};
```

Pages are thin wrappers over a component, fed by a `+page.ts` `load()` that calls the backend via `@generated/backend`:

```1:12:ts/routes/ankountant-dashboard/+page.svelte
<script lang="ts">
    import type { PageData } from "./$types";
    import Dashboard from "./Dashboard.svelte";
    export let data: PageData;
</script>
<Dashboard readiness={data.readiness} examDate={data.examDate} />
```

Webview bridge + eval APIs (used to wire back-nav + client `goto`):

```837:837:qt/aqt/webview.py
def set_bridge_command(self, func: Callable[[str], Any], context: Any) -> None:
```

```78:78:qt/aqt/deckbrowser.py
self.web.set_bridge_command(self._linkHandler, self)
```

**`mediasrv.is_sveltekit_page` matches the FIRST path segment** against a flat whitelist (so we must NOT change the URL first-segment):

```413:428:qt/aqt/mediasrv.py
def is_sveltekit_page(path: str) -> bool:
    page_name = path.split("/")[0]
    return page_name in [ ... "ankountant-dashboard", "ankountant-confusion", "ankountant-tbs" ]
```

---

## 3. Design decisions (locked)

1. **Keep the three flat route URLs** (`/ankountant-dashboard`, `/ankountant-confusion`, `/ankountant-tbs`). Group them under a SvelteKit **route group** `(ankountant)/` so they can share a shell layout **without changing the URL** → `is_sveltekit_page` and `mediasrv` need **no change**.
2. **One persistent in-window webview** (`AnkiQt.ankountant_web`, new kind `ANKOUNTANT_SHELL` with API access), shown by a new `moveToState("ankountant", page)` state. Inter-screen navigation and in-shell "back" happen **client-side** (SvelteKit `goto` / `history.back()`); **exit to Decks** happens via a bridge command → `moveToState("deckBrowser")`.
3. **Retire the three `QDialog`s' menu wiring** (point the menu at `moveToState`). Keep `qt/aqt/ankountant.py` classes for now (harmless) or delete after; not required for the shell.

Why this split: SvelteKit already client-routes within one loaded document, so screen-to-screen is instant and windowless; Qt only owns "which surface is visible" (the state) and "leave Ankountant" (exit). This is the smallest, lowest-risk change that yields true one-window + back buttons.

---

## 4. Web changes (`ts/`)

### 4.1 Route group + shell layout (no URL change)

Move the three existing route folders under a **route group** and add a shared shell layout:

```
ts/routes/
  (ankountant)/
    +layout.svelte          # NEW — the shell chrome (top bar + back + tabs)
    +layout.ts              # NEW (optional) — inherits root; add if shared load needed
    ankountant-dashboard/   # moved (dir + Dashboard.svelte + +page.svelte + +page.ts)
    ankountant-confusion/   # moved (dir + ConfusionMode.svelte + +page.svelte + +page.ts)
    ankountant-tbs/         # moved (dir + TbsSurface.svelte + +page.svelte + +page.ts)
```

Route groups `(name)` are stripped from the URL, so URLs stay `/ankountant-dashboard` etc. Relative imports (`./Dashboard.svelte`, `./$types`) are unaffected because files move together.

### 4.2 `(ankountant)/+layout.svelte` — the shell (prototype)

```svelte
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { bridgeCommand } from "@tslib/bridgecommand";

    const tabs = [
        { id: "dashboard", label: "Readiness", href: "/ankountant-dashboard" },
        { id: "confusion", label: "Confusion", href: "/ankountant-confusion" },
        { id: "tbs",       label: "TBS",       href: "/ankountant-tbs" },
    ];
    $: current = $page.url.pathname;

    function exitToDecks() {
        // Qt-side: AnkiQt bridge handler routes this to moveToState("deckBrowser")
        bridgeCommand("ankountant:exit");
    }
    function navigate(href: string) {
        goto(href); // client-side, no reload, no window
    }
</script>

<header class="ank-shell-topbar">
    <button class="ank-back" onclick={exitToDecks} aria-label="Back to decks">
        ← Decks
    </button>
    <nav class="ank-tabs" aria-label="Ankountant sections">
        {#each tabs as t}
            <button
                class="ank-tab"
                class:active={current === t.href}
                aria-current={current === t.href ? "page" : undefined}
                onclick={() => navigate(t.href)}>{t.label}</button>
        {/each}
    </nav>
</header>

<main class="ank-shell-body"><slot /></main>

<style lang="scss">
    /* Uses the Ledger design tokens — see design-system-implementation.md.
       Top bar: surface bg, 1px hairline bottom border, brand-navy active tab. */
    .ank-shell-topbar {
        display: flex; align-items: center; gap: 16px;
        height: 48px; padding: 0 16px;
        background: var(--canvas-elevated);
        border-bottom: 1px solid var(--border-subtle);
    }
    .ank-back {
        font: inherit; font-weight: 600; color: var(--fg);
        background: transparent; border: 0; padding: 6px 8px; border-radius: 8px;
    }
    .ank-back:hover { background: var(--canvas); }
    .ank-tabs { display: flex; gap: 4px; margin-left: auto; }
    .ank-tab {
        font: inherit; font-weight: 500; color: var(--fg-subtle);
        background: transparent; border: 0; padding: 6px 12px; border-radius: 8px;
    }
    .ank-tab.active { color: var(--accent); border-bottom: 2px solid var(--accent); border-radius: 0; }
    .ank-shell-body { min-height: 0; }
</style>
```

Notes:

- `bridgeCommand` is `@tslib/bridgecommand` (Qt-only; the shell always runs in Qt so it is safe here).
- In-shell "back" between screens = `history.back()` or `goto(previousHref)`; add if a drill-down (e.g. a TBS item detail) is introduced later. For the three top-level tabs, tab clicks + `exitToDecks` are sufficient.
- Style with the Ledger tokens (`--accent` = Ink Navy, `--canvas*`, `--border*`); see `design-system-implementation.md`.

---

## 5. Qt changes (`qt/aqt/`)

### 5.1 `webview.py` — add a shell kind with API access

```python
# in class AnkiWebViewKind(Enum):  (near lines 62-64)
    ANKOUNTANT_SHELL = "ankountant shell"

# in AnkiWebPage._profileForPage(...) have_api_access tuple (lines 139-151), add:
            AnkiWebViewKind.ANKOUNTANT_SHELL,
```

### 5.2 `main.py` — new state + persistent shell webview (prototype)

```python
# 1) extend the state type (line 85)
MainWindowState = Literal[
    "startup", "deckBrowser", "overview", "review",
    "resetRequired", "profileManager", "ankountant",
]

# 2) lazily create the shell webview (e.g. in setupMainWindow near self.web setup ~954-966)
#    add it to mainLayout, hidden by default:
from aqt.webview import AnkiWebView, AnkiWebViewKind
self.ankountant_web = AnkiWebView(kind=AnkiWebViewKind.ANKOUNTANT_SHELL)
self.ankountant_web.set_bridge_command(self._ankountant_link_handler, self)
self.ankountant_web.hide()
self.mainLayout.addWidget(self.ankountant_web)  # sits alongside self.web

# 3) the new state + cleanup
_ankountant_loaded: bool = False  # instance attr; init False

def _ankountantState(self, oldState: MainWindowState, page: str = "dashboard") -> None:
    route = {
        "dashboard": "ankountant-dashboard",
        "confusion": "ankountant-confusion",
        "tbs": "ankountant-tbs",
    }[page]
    self.web.hide()
    self.bottomWeb.hide()
    self.ankountant_web.show()
    if not self._ankountant_loaded:
        self.ankountant_web.load_sveltekit_page(route)   # first entry: full load
        self._ankountant_loaded = True
    else:
        # already loaded: client-side navigate (no reload, no window)
        self.ankountant_web.eval(
            f"window.__ankGoto && window.__ankGoto('/{route}')"
        )

def _ankountantCleanup(self, newState: MainWindowState) -> None:
    if newState != "ankountant":
        self.ankountant_web.hide()
        self.web.show()
        self.bottomWeb.show()

def _ankountant_link_handler(self, cmd: str) -> None:
    # bridge commands from (ankountant)/+layout.svelte
    if cmd == "ankountant:exit":
        self.moveToState("deckBrowser")
    elif cmd.startswith("ankountant:nav:"):
        self.moveToState("ankountant", cmd.split(":")[-1])
```

`window.__ankGoto` is a tiny hook the shell registers so Python can drive client navigation without a reload. Add to `(ankountant)/+layout.svelte`:

```svelte
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";
    onMount(() => { (window as any).__ankGoto = (href: string) => goto(href); });
</script>
```

(If you prefer not to expose a global, instead always `load_sveltekit_page(route)` on entry — simpler, costs one reload per menu click. The `__ankGoto` path keeps it a true SPA.)

### 5.3 `main.py` — point the menu at the state (replace dialog construction)

```python
# in _setup_ankountant_menu (lines 1486-1500):
    dashboard = menu.addAction("Readiness Dashboard")
    qconnect(dashboard.triggered, lambda: self.moveToState("ankountant", "dashboard"))
    confusion = menu.addAction("Confusion-Set Review")
    qconnect(confusion.triggered, lambda: self.moveToState("ankountant", "confusion"))
    tbs = menu.addAction("TBS Practice")
    qconnect(tbs.triggered, lambda: self.moveToState("ankountant", "tbs"))
```

`import aqt.ankountant` and the three `QDialog` classes are no longer needed by the menu. Leave the file or delete the classes in a follow-up.

### 5.4 Toolbar during the shell (choose one)

- **Recommended:** hide the top toolbar in `_ankountantState` (`self.toolbarWeb.hide()`) and rely on the shell's own top bar; restore it in `_ankountantCleanup` (`self.toolbarWeb.show()`), mirroring how `_reviewState`/`_reviewCleanup` manage `toolbarWeb`.
- Simplest: leave the toolbar visible (the shell bar sits under it). Works, slightly redundant.

---

## 6. Back-navigation mechanism (summary)

| Navigation                         | Mechanism                                                         |
| ---------------------------------- | ----------------------------------------------------------------- |
| Dashboard ↔ Confusion ↔ TBS (tabs) | SvelteKit `goto()` (client, in-SPA)                               |
| In-screen drill-down back (future) | `history.back()`                                                  |
| Exit Ankountant → Decks            | `bridgeCommand("ankountant:exit")` → `moveToState("deckBrowser")` |
| OS/menu re-entry                   | `moveToState("ankountant", <page>)` (reuses the loaded shell)     |

Add an `Esc` shortcut in `_ankountantState` that calls `moveToState("deckBrowser")` for parity with dialog-close muscle memory (register via the same per-state shortcut mechanism used elsewhere; cleared automatically by `clearStateShortcuts` in `moveToState`).

---

## 7. Risks / gotchas (all verified)

- **`MainWindowState` is a closed `Literal`** (main.py:85) — you MUST add `"ankountant"` or typing/`just check-py` fails.
- **API access:** the shell webview kind MUST be in `_profileForPage`'s `have_api_access` tuple (webview.py:139-151) or `postProto` backend calls fail.
- **First-segment whitelist:** keep the flat route names (`ankountant-dashboard/…`) via the `(ankountant)` route group so `is_sveltekit_page` (mediasrv:413-428) needs no change. If you instead nest as `/ankountant/dashboard`, you MUST add `"ankountant"` to that whitelist.
- **Lifecycle:** the shell webview lives on the main window, so it is torn down with it; no `DialogManager`/`garbage_collect_on_dialog_finish` needed. Do call `self.ankountant_web.cleanup()` in the main window's close path if you add explicit teardown (grep how `self.web` is cleaned on close).
- **Night mode:** `load_sveltekit_page` appends `#night` from `theme_manager.night_mode` (webview.py:890-905); client `goto` preserves it. Verify the shell restyles on theme toggle.
- **Refresh on data change:** if a screen must refresh after a `CollectionOp`, hook `on_operation_did_execute` for `state == "ankountant"` (main.py:840-858) and `eval` a refresh, mirroring the other states.
- **`bridgeCommand` is Qt-only** (`@tslib/bridgecommand`) — fine here (shell always runs in Qt), but it throws in a plain browser, so guard e2e/browser usage.

---

## 8. Acceptance criteria

- [ ] Ankountant menu items switch the **main window** content (no new OS window appears).
- [ ] Tabs switch dashboard/confusion/TBS **without a full reload** (SPA `goto`).
- [ ] "← Decks" returns to the deck browser in the same window.
- [ ] Backend data still loads on each screen (readiness/confusion/TBS) — API access intact.
- [ ] Night mode + the Ledger tokens apply to the shell top bar.
- [ ] `just check` passes (Python typing incl. the new `MainWindowState` member; svelte/ts checks).
- [ ] The three `QDialog`s are no longer opened by the menu.

Verify: `just check` (full), then `just run` and click each Ankountant menu item + the tabs + "← Decks".
