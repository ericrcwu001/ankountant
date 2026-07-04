# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Single-window, browser-style tabbed workspace.

Every surface lives inside the one main window as a QDockWidget in the top
dock area:

- the permanent, non-closable "home" dock hosts the Decks/Study webview trio
  (the moveToState state machine keeps running inside it, untouched);
- tools (Add Cards, Browser, Stats) and the Ankountant shell open as docks
  tabified onto home, which renders as a North tab bar spanning the window;
- dragging a tab re-orders it, or docks it beside/below others (nested
  splits); floating is disabled everywhere.

Tool lifecycle stays owned by the tools themselves: DialogManager.open()
routes creation here (`embed`), the tools keep their closeEvent/reject veto
chains and their aqt.dialogs.markClosed calls, and dock teardown is driven by
the tool's `destroyed` signal so it happens exactly once, after the tool's own
cleanup.

Layout persistence: the set of open tools plus a QMainWindow.saveState blob
are stored in the profile; the blob is captured in closeAllWindows *before*
DialogManager.closeAll tears the tools down, and restore re-creates docks
(stable objectNames) before applying the blob.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Callable

import aqt
from aqt.qt import *
from aqt.utils import _qt_state_key, _QtStateKeyKind, saveState
from aqt.webview import AnkiWebView, AnkiWebViewKind

if TYPE_CHECKING:
    import aqt.main

WORKSPACE_LAYOUT_VERSION = 1

HOME_TOOL = "Home"
ANKOUNTANT_TOOL = "AnkountantShell"

# DialogManager names that open as workspace tabs instead of windows.
EMBEDDABLE_TOOLS = {"AddCards", "Browser", "NewDeckStats", "DeckStats"}

_TOOL_TITLES = {
    HOME_TOOL: "Decks",
    "AddCards": "Add",
    "Browser": "Browse",
    "NewDeckStats": "Stats",
    "DeckStats": "Stats (legacy)",
    ANKOUNTANT_TOOL: "Ankountant",
}

_ANKOUNTANT_ROUTES = {
    "home": "ankountant-home",
    "workspace": "ankountant-workspace",
    "dashboard": "ankountant-dashboard",
    "confusion": "ankountant-confusion",
    "tbs": "ankountant-tbs",
    "research": "ankountant-research",
    "doc_review": "ankountant-doc-review",
    "stats": "ankountant-stats",
    "sync": "ankountant-sync",
}

# The FAR study deck the Home "Review" button studies.
_ANKOUNTANT_STUDY_DECK = "Ankountant::Study::FAR"

_DOCK_AREA = Qt.DockWidgetArea.TopDockWidgetArea


class WorkspaceDock(QDockWidget):
    """Dock hosting one workspace surface.

    Closing never happens through QDockWidget's own hide-on-close: the
    closeEvent is vetoed and routed to Workspace.request_close, which drives
    the hosted tool's veto-able close chain instead."""

    def __init__(
        self,
        tool_name: str,
        title: str,
        workspace: Workspace,
        *,
        closable: bool,
    ) -> None:
        super().__init__(title, workspace.mw)
        self.tool_name = tool_name
        self.workspace = workspace
        self.closable = closable
        self.setObjectName(
            "workspace_home"
            if tool_name == HOME_TOOL
            else f"workspace_dock_{tool_name}"
        )
        # Movable so a tab can be dragged into a split; never floatable (no
        # separate windows). Closable tool docks also expose a native title-bar
        # close button when they are split out and lose their tab (see
        # Workspace._sync_title_bars); the closeEvent below still routes closing
        # through the tool's own veto chain.
        features = QDockWidget.DockWidgetFeature.DockWidgetMovable
        if closable:
            features |= QDockWidget.DockWidgetFeature.DockWidgetClosable
        self.setFeatures(features)
        self.setAllowedAreas(Qt.DockWidgetArea.AllDockWidgetAreas)
        # Browser-tab look: no per-dock title bar; the North tab is the handle.
        self.setTitleBarWidget(QWidget())

    def closeEvent(self, evt: QCloseEvent | None) -> None:
        assert evt is not None
        evt.ignore()
        if self.closable:
            self.workspace.request_close(self.tool_name)


class Workspace:
    """Owns the dock/tab layout of the single main window."""

    def __init__(self, mw: aqt.main.AnkiQt) -> None:
        self.mw = mw
        self._docks: dict[str, WorkspaceDock] = {}
        self._home: WorkspaceDock | None = None
        self._shell_web: AnkiWebView | None = None
        self._restoring = False
        # When true the North dock tab strip is hidden (Ankountant-first layout,
        # see set_chrome_hidden / AnkiQt.set_ankountant_fullscreen).
        self._chrome_hidden = False

    # Construction
    ######################################################################

    def build(self, home_container: QWidget) -> None:
        """Turn mw into an all-docks window with `home_container` as the
        permanent home tab."""
        mw = self.mw
        mw.setDockNestingEnabled(True)
        mw.setDockOptions(
            QMainWindow.DockOption.AllowNestedDocks
            | QMainWindow.DockOption.AllowTabbedDocks
            | QMainWindow.DockOption.GroupedDragging
        )
        mw.setTabPosition(
            Qt.DockWidgetArea.AllDockWidgetAreas, QTabWidget.TabPosition.North
        )
        # A zero-size central widget lets the dock area fill the window.
        placeholder = QWidget()
        placeholder.setFixedSize(0, 0)
        mw.setCentralWidget(placeholder)

        home = WorkspaceDock(HOME_TOOL, _TOOL_TITLES[HOME_TOOL], self, closable=False)
        home.setWidget(home_container)
        mw.addDockWidget(_DOCK_AREA, home)
        self._home = home
        self._docks[HOME_TOOL] = home
        self._watch_dock(home)

    # Opening / raising
    ######################################################################

    def embed(
        self,
        name: str,
        creator: Callable[..., Any],
        args: tuple,
        kwargs: dict,
    ) -> Any:
        """Create a DialogManager tool and host it as a tab.

        The tool's trailing self.show() only schedules mapping; reparenting
        into the dock in this same call stack means its top-level window is
        never actually shown (no flash)."""
        tool = creator(*args, **kwargs)
        dock = self._add_dock(name, tool)
        # The tool tears itself down (markClosed + deleteLater) via its own
        # close chain; remove the dock once the widget is really gone.
        qconnect(tool.destroyed, lambda *_: self._remove_dock(name))
        if not self._restoring:
            self._tabify_and_raise(dock)
            tool.setFocus()
        return tool

    def _add_dock(self, name: str, widget: QWidget) -> WorkspaceDock:
        dock = WorkspaceDock(name, _TOOL_TITLES.get(name, name), self, closable=True)
        dock.setWidget(widget)
        self._docks[name] = dock
        self.mw.addDockWidget(_DOCK_AREA, dock)
        self._watch_dock(dock)
        return dock

    def _tabify_and_raise(self, dock: WorkspaceDock) -> None:
        assert self._home is not None
        self.mw.tabifyDockWidget(self._home, dock)
        dock.show()
        dock.raise_()
        self._schedule_tab_sync()

    def raise_tool(self, name: str) -> None:
        if dock := self._docks.get(name):
            dock.show()
            dock.raise_()
            if widget := dock.widget():
                widget.setFocus()

    def raise_home(self) -> None:
        self.raise_tool(HOME_TOOL)

    def _show_only(self, name: str) -> None:
        """Show exactly one dock and hide every other, so QMainWindow renders no
        dock tab strip — a single visible dock has no tabs. This is how the
        Ankountant-first layout drops the classic "Decks | Ankountant" tab bar:
        Qt re-creates and re-shows that bar on relayout, so hiding the QTabBar
        directly does not stick, whereas hiding the sibling dock does."""
        target = self._docks.get(name)
        if target is None:
            return
        for other, dock in self._docks.items():
            if other == name:
                dock.show()
                dock.raise_()
            else:
                dock.hide()
        if widget := target.widget():
            widget.setFocus()

    def show_home_only(self) -> None:
        """Study surfaces (overview/review) fill the window; the shell and any
        tool docks are hidden so no tab strip appears."""
        self._show_only(HOME_TOOL)

    def restore_all_docks(self) -> None:
        """Escape hatch: bring every dock back (classic tabbed workspace)."""
        for dock in self._docks.values():
            dock.show()
        self.raise_home()

    def enter_home_shell(self) -> None:
        """Make the Ankountant SvelteKit shell the visible surface, opening it if
        necessary and navigating it to Home. On launch and via the escape-hatch
        toggle this is what the user lands on — not the classic deck browser."""
        self.open_ankountant("home")
        if self._chrome_hidden:
            self._show_only(ANKOUNTANT_TOOL)

    def return_to_shell(self) -> None:
        """Raise the Ankountant shell wherever it currently is (no forced
        navigation), opening it if it was closed. Called when a home-surface
        transition (e.g. a post-sync reset back to the deck browser, or the
        end-of-session overview) would otherwise pop the classic chrome over the
        shell."""
        if self._shell_web is None:
            self.open_ankountant("home")
        if self._chrome_hidden:
            self._show_only(ANKOUNTANT_TOOL)
        else:
            self.raise_tool(ANKOUNTANT_TOOL)

    def set_chrome_hidden(self, hidden: bool) -> None:
        """Enter/leave the Ankountant-first layout. When hidden, only one dock is
        ever visible (so QMainWindow shows no North tab strip — no leftover
        "Decks" tab); when shown, all docks return (classic tabbed workspace)."""
        self._chrome_hidden = hidden
        if hidden:
            # Collapse to the shell if it exists yet; on launch enter_home_shell
            # opens it and collapses right after.
            if self._shell_web is not None:
                self._show_only(ANKOUNTANT_TOOL)
        else:
            self.restore_all_docks()
        self._schedule_tab_sync()

    def is_open(self, name: str) -> bool:
        return name in self._docks

    def tool_for_focus(self) -> QWidget | None:
        """The embedded tool whose subtree currently has focus, if any."""
        focus = QApplication.focusWidget()
        if focus is None:
            return None
        for name, dock in self._docks.items():
            if name == HOME_TOOL:
                continue
            widget = dock.widget()
            if widget and (focus is widget or widget.isAncestorOf(focus)):
                return widget
        return None

    # Closing
    ######################################################################

    def request_close(self, name: str) -> None:
        """Route a close request through the tool's own veto chain."""
        if name == HOME_TOOL:
            return
        if name == ANKOUNTANT_TOOL:
            self._close_ankountant()
            return
        dock = self._docks.get(name)
        tool = dock.widget() if dock else None
        if tool is None:
            return
        # AddCards/Browser: close() drives closeEvent -> ifCanClose/save
        # chains; Stats (QDialog): reject() runs its cleanup + markClosed.
        if isinstance(tool, QDialog):
            tool.reject()
        else:
            tool.close()

    def close_tool_widget(self, widget: QWidget) -> None:
        """Close the tab hosting `widget` (used by Ctrl/Cmd+W)."""
        for name, dock in self._docks.items():
            if dock.widget() is widget:
                self.request_close(name)
                return

    def _remove_dock(self, name: str) -> None:
        dock = self._docks.pop(name, None)
        if dock is None:
            return
        self.mw.removeDockWidget(dock)
        dock.setParent(None)
        dock.deleteLater()
        self._schedule_tab_sync()

    # Ankountant shell tab
    ######################################################################

    def open_ankountant(self, page: str = "home") -> None:
        route = _ANKOUNTANT_ROUTES.get(page, "ankountant-home")
        if self._shell_web is not None:
            # Already open: client-side navigate (SPA, no reload) + raise.
            self._shell_web.eval(f"window.__ankGoto && window.__ankGoto('/{route}')")
            self.raise_tool(ANKOUNTANT_TOOL)
            return
        web = AnkiWebView(kind=AnkiWebViewKind.ANKOUNTANT_SHELL)
        web.set_bridge_command(self._ankountant_bridge, self.mw)
        web.load_sveltekit_page(route)
        self._shell_web = web
        dock = self._add_dock(ANKOUNTANT_TOOL, web)
        if not self._restoring:
            self._tabify_and_raise(dock)
            web.setFocus()

    def _close_ankountant(self) -> None:
        if self._shell_web is not None:
            self._shell_web.cleanup()
            self._shell_web = None
        self._remove_dock(ANKOUNTANT_TOOL)

    def _ankountant_bridge(self, cmd: str) -> None:
        """Bridge commands from ts/routes/(ankountant)/+layout.svelte and the
        Ankountant Home hero."""
        if cmd == "ankountant:exit":
            self.raise_home()
        elif cmd == "ankountant:review":
            self._start_ankountant_study()
        elif cmd == "ankountant:stats":
            aqt.dialogs.open("NewDeckStats", self.mw)
        elif cmd == "ankountant:prefs":
            self.mw.onPrefs()
        elif cmd == "ankountant:sync":
            self.mw.on_sync_button_clicked()
        elif cmd.startswith("ankountant:nav:"):
            self.open_ankountant(cmd.split(":")[-1])

    def _start_ankountant_study(self) -> None:
        """Home "Review" -> study the FAR study deck in the home dock's reviewer.

        Routes through the deck overview (selecting the deck first) so new/review
        limits and the empty-deck congrats screen behave exactly like a normal
        "Study Now"."""
        did = self.mw.col.decks.id_for_name(_ANKOUNTANT_STUDY_DECK)
        if did is not None:
            self.mw.col.decks.select(did)
        self.show_home_only()
        self.mw.moveToState("overview")

    # Tab bar close buttons
    ######################################################################
    # QMainWindow creates/destroys the dock tab bars on the fly while docks
    # are tabified/dragged; re-sync close buttons whenever the layout shifts.

    def _watch_dock(self, dock: WorkspaceDock) -> None:
        qconnect(dock.dockLocationChanged, lambda *_: self._schedule_tab_sync())
        qconnect(dock.visibilityChanged, lambda *_: self._schedule_tab_sync())

    def _schedule_tab_sync(self) -> None:
        # Deferred: let Qt finish (re)building its internal tab bars first.
        QTimer.singleShot(0, self._sync_tab_bars)

    def _sync_tab_bars(self) -> None:
        home_title = _TOOL_TITLES[HOME_TOOL]
        for bar in self.mw.findChildren(QTabBar):
            # Only the dock-area tab bars (direct children of mw) — not tab
            # bars inside embedded tools.
            if bar.parent() is not self.mw:
                continue
            # Best-effort: in the Ankountant-first layout only one dock is ever
            # visible so Qt normally builds no strip at all, but hide any
            # transient bar it does build during a relayout too.
            bar.setVisible(not self._chrome_hidden)
            if not bar.property("workspace_wired"):
                bar.setProperty("workspace_wired", True)
                bar.setTabsClosable(True)
                bar.setElideMode(Qt.TextElideMode.ElideRight)
                bar.setUsesScrollButtons(True)
                qconnect(
                    bar.tabCloseRequested,
                    lambda idx, b=bar: self._on_tab_close_requested(b, idx),
                )
            # The home tab is permanent: strip its close button (both sides —
            # the platform style decides where it goes).
            for i in range(bar.count()):
                if bar.tabText(i) == home_title:
                    bar.setTabButton(i, QTabBar.ButtonPosition.RightSide, None)
                    bar.setTabButton(i, QTabBar.ButtonPosition.LeftSide, None)
        self._sync_title_bars()

    def _sync_title_bars(self) -> None:
        """Give split-out (untabbed) tool panes a native title bar — and thus a
        close button — while keeping tabbed panes chrome-free.

        Once a tab is dragged out of the North strip into its own split region
        it has neither a tab nor a title bar, so there is no way to close it.
        Restoring Qt's native title bar there (the dock is DockWidgetClosable)
        brings back a close button; re-tabbing strips it again."""
        for name, dock in self._docks.items():
            if name == HOME_TOOL:
                continue
            # In the Ankountant-first layout the sole visible dock must stay
            # chrome-free — never fall back to a native title bar (which would be
            # a new bar with a close button).
            if self._chrome_hidden or self.mw.tabifiedDockWidgets(dock):
                # Tabbed / chrome-hidden: the tab strip (or nothing) owns chrome.
                if dock.titleBarWidget() is None:
                    dock.setTitleBarWidget(QWidget())
            elif dock.titleBarWidget() is not None:
                # Standalone/split: fall back to Qt's native title bar.
                dock.setTitleBarWidget(None)  # type: ignore[arg-type]

    def _on_tab_close_requested(self, bar: QTabBar, index: int) -> None:
        title = bar.tabText(index)
        for name, dock in self._docks.items():
            if dock.windowTitle() == title:
                self.request_close(name)
                return

    # Persistence
    ######################################################################

    def save_layout(self) -> None:
        """Snapshot open tools + dock layout. Must run while the tool docks
        still exist (i.e. before DialogManager.closeAll)."""
        profile = self.mw.pm.profile
        if profile is None:
            return
        profile["workspace_open_tools"] = [
            name for name in self._docks if name != HOME_TOOL
        ]
        profile["workspace_layout_version"] = WORKSPACE_LAYOUT_VERSION
        saveState(self.mw, "workspace")

    def restore_layout(self) -> None:
        profile = self.mw.pm.profile
        if profile is None:
            return
        if profile.get("workspace_layout_version") != WORKSPACE_LAYOUT_VERSION:
            # Missing/old keys (fresh or pre-workspace profile): home only.
            return
        tools: list[str] = profile.get("workspace_open_tools") or []
        created = self._reopen_tools(tools)
        self._apply_saved_state(created, tools)
        self.raise_home()
        self._schedule_tab_sync()

    def _reopen_tools(self, tools: list[str]) -> list[str]:
        """Re-create each saved tool as a dock; skip any that fail."""
        self._restoring = True
        created: list[str] = []
        try:
            for name in tools:
                try:
                    opened = self._reopen_one(name)
                except Exception as exc:
                    print(f"workspace: could not restore {name}: {exc}")
                    continue
                if opened:
                    created.append(name)
        finally:
            self._restoring = False
        return created

    def _reopen_one(self, name: str) -> bool:
        if name == ANKOUNTANT_TOOL:
            self.open_ankountant()
            return True
        if name in EMBEDDABLE_TOOLS:
            aqt.dialogs.open(name, self.mw)
            return True
        return False

    def _apply_saved_state(self, created: list[str], tools: list[str]) -> None:
        """Apply the saved dock geometry, or fall back to plain tabs."""
        if created and set(created) == set(tools) and self._restore_state_blob():
            return
        # Fall back to plain tabs beside home rather than a broken layout.
        assert self._home is not None
        for name in created:
            if dock := self._docks.get(name):
                self.mw.tabifyDockWidget(self._home, dock)

    def _restore_state_blob(self) -> bool:
        profile = self.mw.pm.profile
        if profile is None:
            return False
        key = _qt_state_key(_QtStateKeyKind.STATE, "workspace")
        data = profile.get(key)
        return bool(data) and bool(self.mw.restoreState(data))

    def shutdown(self) -> None:
        """Profile unload: dispose surfaces that DialogManager doesn't own."""
        self._close_ankountant()
