# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

from __future__ import annotations

import datetime
import enum
import gc
import json
import os
import re
import signal
import sys
import traceback
import weakref
from argparse import Namespace
from collections.abc import Callable, Sequence
from concurrent.futures import Future
from pathlib import Path
from typing import TYPE_CHECKING, Any, Literal, TypeVar, cast

import anki
import anki.sound
import aqt
import aqt.forms
import aqt.progress
import aqt.sound
from anki import hooks
from anki._backend import RustBackend as _RustBackend
from anki._legacy import deprecated
from anki.buildinfo import version as version_str
from anki.collection import Collection, Config, GithubRelease, OpChanges, UndoStatus
from anki.decks import DeckDict, DeckId
from anki.hooks import runHook
from anki.notes import Note, NoteId
from anki.sound import AVTag, SoundOrVideoTag
from anki.utils import (
    dev_mode,
    ids2str,
    int_time,
    int_version,
    is_lin,
    is_mac,
    is_win,
    split_fields,
)
from aqt import colors, gui_hooks
from aqt.addons import DownloadLogEntry, check_and_prompt_for_updates, show_log_to_user
from aqt.debug_console import show_debug_console
from aqt.flags import FlagManager
from aqt.legacy import install_pylib_legacy
from aqt.mediasync import MediaSyncer
from aqt.operations import QueryOp
from aqt.operations.collection import redo, undo
from aqt.operations.deck import set_current_deck
from aqt.profiles import ProfileManager as ProfileManagerType
from aqt.qt import *
from aqt.qt import sip
from aqt.sync import sync_collection, sync_login
from aqt.taskman import TaskManager
from aqt.theme import Theme, theme_manager
from aqt.toolbar import BottomWebView, Toolbar, TopWebView
from aqt.undo import UndoActionsInfo
from aqt.utils import (
    HelpPage,
    KeyboardModifiersPressed,
    askUser,
    checkInvalidFilename,
    current_window,
    disallow_full_screen,
    getFile,
    getOnlyText,
    openHelp,
    openLink,
    restoreGeom,
    restoreState,
    saveGeom,
    saveState,
    showInfo,
    showWarning,
    tooltip,
    tr,
    widget_effectively_focused,
)
from aqt.webview import AnkiWebView, AnkiWebViewKind

if TYPE_CHECKING:
    from aqt.workspace import Workspace

install_pylib_legacy()

MainWindowState = Literal[
    "startup",
    "deckBrowser",
    "overview",
    "review",
    "resetRequired",
    "profileManager",
]


T = TypeVar("T")
CpaBankCategoryEntry = tuple[tuple[str, ...], tuple[str, ...]]


ANKOUNTANT_DEMO_PHASES = frozenset({"foundation", "discrimination", "consolidation"})
CPA_BANK_SECTIONS = ("FAR", "AUD", "REG", "TCP", "ISC")
CPA_BANK_CATEGORY_SETS: dict[str, dict[str, CpaBankCategoryEntry]] = {
    "FAR": {
        "capitalize_vs_expense": (
            ("ds::cost::capitalize", "ds::cost::expense"),
            ("Capitalize", "Expense"),
        ),
        "operating_vs_finance_lease": (
            ("ds::lease::operating", "ds::lease::finance"),
            ("Operating lease", "Finance lease"),
        ),
        "revrec_step_selection": (
            ("ds::revrec::step4", "ds::revrec::step5"),
            ("Allocate price (Step 4)", "Recognize revenue (Step 5)"),
        ),
        "trading_afs_htm": (
            ("ds::securities::trading", "ds::securities::htm"),
            ("Trading (FV through NI)", "Held-to-maturity (amortized cost)"),
        ),
        "inventory_valuation": (
            ("ds::inventory::lcm", "ds::inventory::lcnrv"),
            ("Lower of cost or market", "Lower of cost and NRV"),
        ),
        "debt_extinguishment": (
            ("ds::debt::extinguish", "ds::debt::modify"),
            ("Extinguishment (derecognize)", "Modification (retain)"),
        ),
        "intangibles_impairment": (
            ("ds::intangible::finite", "ds::intangible::indefinite"),
            ("Finite-life (amortize)", "Indefinite-life (test only)"),
        ),
        "cash_receivables": (
            ("ds::ar::allowance", "ds::ar::writeoff"),
            ("Allowance method", "Direct write-off"),
        ),
        "financial_statements": (
            ("ds::stmt::operating", "ds::stmt::financing"),
            ("Operating activity", "Financing activity"),
        ),
        "conceptual_framework": (
            ("ds::concept::relevance", "ds::concept::faithful"),
            ("Relevance", "Faithful representation"),
        ),
        "tax_timing": (
            ("ds::tax::temporary", "ds::tax::permanent"),
            ("Temporary difference", "Permanent difference"),
        ),
        "pensions_equity": (
            ("ds::pension::service", "ds::pension::interest"),
            ("Service cost", "Interest cost"),
        ),
        "government_nfp": (
            ("ds::govnfp::govtwide", "ds::govnfp::fund"),
            ("Government-wide (accrual)", "Fund (modified accrual)"),
        ),
    },
    "AUD": {
        "qualified_vs_adverse_opinion": (
            ("ds::aud::qualified", "ds::aud::adverse"),
            ("Qualified opinion", "Adverse opinion"),
        ),
        "test_of_controls_vs_substantive": (
            ("ds::aud::controls", "ds::aud::substantive"),
            ("Test of controls", "Substantive procedure"),
        ),
        "aud_evidence_sufficiency": (
            ("ds::aud::sufficient", "ds::aud::insufficient"),
            ("Sufficient appropriate evidence", "Insufficient evidence"),
        ),
        "aud_request_relevance": (
            ("ds::aud::retain", "ds::aud::revise"),
            ("Retain as drafted", "Revise the request"),
        ),
        "materiality_vs_trivial_misstatement": (
            ("ds::aud::material", "ds::aud::trivial"),
            ("Material misstatement", "Clearly trivial misstatement"),
        ),
        "subsequent_events_vs_going_concern": (
            ("ds::aud::subsequent", "ds::aud::going_concern"),
            ("Subsequent event procedure", "Going concern evaluation"),
        ),
    },
    "REG": {
        "s1231_vs_capital_vs_ordinary": (
            ("ds::reg::s1231", "ds::reg::capital", "ds::reg::ordinary"),
            ("Section 1231 gain/loss", "Capital gain/loss", "Ordinary income"),
        ),
        "deduction_for_vs_from_agi": (
            ("ds::reg::for_agi", "ds::reg::from_agi"),
            ("Deduction for AGI", "Deduction from AGI"),
        ),
        "reg_capitalize_vs_deduct": (
            ("ds::reg::deduct", "ds::reg::capitalize"),
            ("Currently deductible", "Capitalize and recover over time"),
        ),
        "circular230_sanction_vs_tax_penalty": (
            ("ds::reg::circular230", "ds::reg::tax_penalty"),
            ("Circular 230 sanction", "Tax penalty"),
        ),
        "basis_vs_amount_realized": (
            ("ds::reg::basis", "ds::reg::amount_realized"),
            ("Adjusted basis", "Amount realized"),
        ),
        "c_corp_vs_s_corp_taxation": (
            ("ds::reg::c_corp", "ds::reg::s_corp"),
            ("C corporation taxation", "S corporation pass-through"),
        ),
    },
    "TCP": {
        "like_kind_vs_taxable_exchange": (
            ("ds::tcp::nonrecognition", "ds::tcp::taxable"),
            ("Nonrecognition (deferral)", "Currently taxable exchange"),
        ),
        "distribution_vs_liquidation": (
            ("ds::tcp::distribution", "ds::tcp::liquidation"),
            ("Nonliquidating distribution", "Complete liquidation"),
        ),
        "tcp_cost_recovery": (
            ("ds::tcp::expense", "ds::tcp::capitalize"),
            ("Expense currently", "Capitalize and recover"),
        ),
        "gift_vs_estate_tax": (
            ("ds::tcp::gift", "ds::tcp::estate"),
            ("Gift tax transfer", "Estate tax inclusion"),
        ),
        "redemption_vs_dividend": (
            ("ds::tcp::redemption", "ds::tcp::dividend"),
            ("Sale/exchange redemption", "Dividend-equivalent distribution"),
        ),
        "active_vs_passive_loss": (
            ("ds::tcp::active", "ds::tcp::passive"),
            ("Active business loss", "Passive activity loss"),
        ),
    },
    "ISC": {
        "soc1_vs_soc2": (
            ("ds::isc::soc1", "ds::isc::soc2"),
            ("SOC 1 (ICFR)", "SOC 2 (trust services)"),
        ),
        "soc_report_type1_vs_type2": (
            ("ds::isc::type1", "ds::isc::type2"),
            (
                "Type 1 (design at a point in time)",
                "Type 2 (operating effectiveness over a period)",
            ),
        ),
        "isc_control_type": (
            ("ds::isc::preventive", "ds::isc::detective"),
            ("Preventive control", "Detective control"),
        ),
        "authentication_vs_authorization": (
            ("ds::isc::authentication", "ds::isc::authorization"),
            ("Authentication", "Authorization"),
        ),
        "backup_vs_disaster_recovery": (
            ("ds::isc::backup", "ds::isc::recovery"),
            ("Backup control", "Disaster recovery procedure"),
        ),
        "incident_detection_vs_response": (
            ("ds::isc::detect", "ds::isc::respond"),
            ("Incident detection", "Incident response"),
        ),
    },
}
CPA_BANK_MEMORY_TAGS = {
    section: tuple(tag for tags, _ in categories.values() for tag in tags)
    for section, categories in CPA_BANK_CATEGORY_SETS.items()
}
CPA_BANK_REVIEW_STRENGTH = {
    "FAR": 8,
    "AUD": 7,
    "REG": 7,
    "TCP": 6,
    "ISC": 8,
}
CPA_BANK_EXAM_OFFSETS_DAYS = {
    "FAR": 45,
    "AUD": 68,
    "REG": 96,
    "TCP": 124,
    "ISC": 82,
}


def require_ankountant_demo_phase(phase: str) -> None:
    if phase not in ANKOUNTANT_DEMO_PHASES:
        raise ValueError(f"unknown Ankountant demo phase: {phase}")


def ankountant_category_metadata(
    label: str,
    tags: Sequence[Any],
    treatments: Sequence[Any],
) -> dict[str, list[str]]:
    if (
        not tags
        or not treatments
        or not all(isinstance(tag, str) and tag for tag in tags)
        or not all(isinstance(treatment, str) and treatment for treatment in treatments)
    ):
        raise ValueError(f"{label} must contain non-empty string tags and treatments")
    return {"tags": list(tags), "treatments": list(treatments)}


def ankountant_confusable_patch_updates(
    patch: Any,
) -> dict[str, dict[str, dict[str, Any]]]:
    if not isinstance(patch, dict):
        raise ValueError("confusable_patch.json must contain an object")

    updates: dict[str, dict[str, dict[str, Any]]] = {}
    for set_id, entry in patch.items():
        if not isinstance(set_id, str) or not set_id:
            raise ValueError("confusable set ids must be non-empty strings")
        if not isinstance(entry, dict):
            raise ValueError(f"confusable set {set_id} must contain an object")
        section = entry.get("section")
        if not isinstance(section, str) or not section:
            raise ValueError(f"confusable set {set_id} is missing section")
        tags = entry.get("tags", [])
        if not isinstance(tags, list):
            raise ValueError(f"confusable set {set_id} tags must be a list")
        treatments = entry.get("treatments", [])
        if not isinstance(treatments, list):
            raise ValueError(f"confusable set {set_id} treatments must be a list")
        key = f"ankountant.confusable.{section}"
        updates.setdefault(key, {})[set_id] = ankountant_category_metadata(
            f"confusable set {set_id}",
            tags,
            treatments,
        )

    return updates


def ankountant_sealed_deck_parts(deck_name: str) -> tuple[str, str] | None:
    parts = deck_name.split("::")
    if len(parts) < 4 or parts[0] != "Ankountant" or parts[1] != "Sealed":
        return None
    section = parts[2].upper()
    if section not in CPA_BANK_SECTIONS:
        return None
    set_id = "::".join(parts[3:]).strip()
    if not set_id:
        raise ValueError(f"sealed deck is missing a set id: {deck_name}")
    return section, set_id


def ankountant_stress_sealed_deck_parts(deck_name: str) -> tuple[str, str] | None:
    parts = deck_name.split("::")
    if (
        len(parts) < 5
        or parts[0] != "Ankountant"
        or parts[1] != "Stress"
        or parts[2] != "Sealed"
    ):
        return None
    section = parts[3].upper()
    if section not in CPA_BANK_SECTIONS:
        return None
    set_id = "::".join(parts[4:]).strip()
    if not set_id:
        raise ValueError(f"stress sealed deck is missing a set id: {deck_name}")
    return section, set_id


def ankountant_bank_study_section(deck_name: str) -> str | None:
    parts = deck_name.split("::")
    if len(parts) < 3 or parts[0] != "Ankountant":
        return None
    if parts[1] not in {"Study", "Community"}:
        return None
    section = parts[2].upper()
    return section if section in CPA_BANK_SECTIONS else None


def ankountant_bank_category_entry(
    section: str,
    set_id: str,
    confusable: dict[str, dict[str, Any]] | None = None,
) -> dict[str, list[str]]:
    if section not in CPA_BANK_SECTIONS:
        raise ValueError(f"unknown CPA bank section: {section}")
    raw = CPA_BANK_CATEGORY_SETS[section].get(set_id)
    if raw is not None:
        tags, treatments = raw
        return ankountant_category_metadata(
            f"CPA bank category {section}::{set_id}",
            tags,
            treatments,
        )
    if confusable is not None and set_id in confusable:
        entry = confusable[set_id]
        tags = entry.get("tags", [])
        treatments = entry.get("treatments", [])
        return ankountant_category_metadata(
            f"CPA bank category {section}::{set_id}",
            tags,
            treatments,
        )
    raise ValueError(f"unknown CPA bank category: {section}::{set_id}")


def ankountant_review_is_correct(section: str, card_index: int, rep_index: int) -> bool:
    threshold = CPA_BANK_REVIEW_STRENGTH[section]
    return ((card_index * 3 + rep_index * 5 + len(section)) % 10) < threshold


def ankountant_first_answer_value(value: Any) -> Any:
    if isinstance(value, list):
        if not value:
            raise ValueError("answer_key list must not be empty")
        return value[0]
    return value


def ankountant_wrong_answer_value(value: Any) -> Any:
    if isinstance(value, bool):
        return not value
    if isinstance(value, (int, float)):
        return value + 999
    if isinstance(value, dict):
        wrong = dict(value)
        if not wrong:
            return {"wrong": True}
        first = next(iter(wrong))
        wrong[first] = ankountant_wrong_answer_value(wrong[first])
        return wrong
    return "__wrong_answer__"


def ankountant_tbs_type(value: str) -> str:
    return re.sub(r"<!--s\d+-->$", "", value).strip()


def ankountant_research_submission(steps: list[Any], correct: bool) -> str:
    answer = ankountant_first_answer_value(steps[0].get("answer_key"))
    citation = str(answer if correct else "NOT-A-VALID-CITATION")
    return json.dumps({"citation": citation})


def ankountant_confusion_submission(steps: list[Any], correct: bool) -> str:
    answer = ankountant_first_answer_value(steps[0].get("answer_key"))
    choice = str(answer if correct else "__wrong_choice__")
    return json.dumps({"choice": choice})


def ankountant_step_submission(steps: list[Any], correct: bool) -> str:
    submitted_steps = []
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            raise ValueError("Ankountant TBS step must contain an object")
        step_id = step.get("id")
        if not isinstance(step_id, str) or not step_id:
            raise ValueError("Ankountant TBS step is missing an id")
        value = ankountant_first_answer_value(step.get("answer_key"))
        if index == 0 and not correct:
            value = ankountant_wrong_answer_value(value)
        submitted_steps.append({"id": step_id, "value": value})
    return json.dumps({"steps": submitted_steps})


def ankountant_submission_for_tbs_fields(
    fields: list[str],
    correct: bool,
) -> tuple[str, str]:
    if len(fields) <= 4:
        raise ValueError("Ankountant TBS note is missing required fields")
    tbs_type = ankountant_tbs_type(fields[0])
    steps = json.loads(fields[3])
    if not isinstance(steps, list) or not steps:
        raise ValueError("Ankountant TBS note has invalid steps_json")

    if tbs_type == "research":
        return "research", ankountant_research_submission(steps, correct)

    if tbs_type == "mcq":
        return "confusion", ankountant_confusion_submission(steps, correct)

    if tbs_type in {"journal_entry", "numeric", "doc_review"}:
        mode = "doc_review" if tbs_type == "doc_review" else "tbs"
        return mode, ankountant_step_submission(steps, correct)

    raise ValueError(f"Unsupported Ankountant TBS type: {tbs_type}")


class MainWebView(AnkiWebView):
    def __init__(self, mw: AnkiQt) -> None:
        AnkiWebView.__init__(self, kind=AnkiWebViewKind.MAIN)
        self.mw = mw
        self.setFocusPolicy(Qt.FocusPolicy.WheelFocus)
        self.setMinimumWidth(400)
        self.setAcceptDrops(True)

    # Importing files via drag & drop
    ##########################################################################

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if self.mw.state != "deckBrowser":
            return super().dragEnterEvent(event)
        mime = event.mimeData()
        if not mime.hasUrls():
            return
        for url in mime.urls():
            path = url.toLocalFile()
            if not os.path.exists(path) or os.path.isdir(path):
                return
        event.accept()

    def dropEvent(self, event: QDropEvent) -> None:
        import aqt.importing
        from aqt.import_export.importing import import_file

        if self.mw.state != "deckBrowser":
            return super().dropEvent(event)
        mime = event.mimeData()
        paths = [url.toLocalFile() for url in mime.urls()]
        deck_paths = filter(lambda p: not p.endswith(".colpkg"), paths)
        for path in deck_paths:
            if not self.mw.pm.legacy_import_export():
                import_file(self.mw, path)
            else:
                aqt.importing.importFile(self.mw, path)

            # importing continues after the above call returns, so it is not
            # currently safe for us to import more than one file at once
            return

    # Main webview specific event handling
    def eventFilter(self, obj: QObject | None, evt: QEvent | None) -> bool:
        if handled := super().eventFilter(obj, evt):
            return handled

        if evt.type() == QEvent.Type.Leave:
            handled_leave = False

            # Show menubar when mouse moves outside main webview in fullscreen
            if self.mw.fullscreen:
                self.mw.show_menubar()
                handled_leave = True

            # Show toolbar when mouse moves outside main webview
            # and automatically hide it with delay after mouse has entered again
            # The toolbar's hide timer will also trigger menubar hiding when in fullscreen mode
            if self.mw.pm.hide_top_bar() or self.mw.pm.hide_bottom_bar():
                self.mw.toolbarWeb.show()
                self.mw.bottomWeb.show()
                handled_leave = True

            return handled_leave

        if evt.type() == QEvent.Type.Enter:
            self.mw.toolbarWeb.hide_timer.start()
            self.mw.bottomWeb.hide_timer.start()
            return True

        return False


class AnkiQt(QMainWindow):
    col: Collection
    pm: ProfileManagerType
    web: MainWebView
    bottomWeb: BottomWebView
    # Container for the home (Decks/Study) surface; the toolbar/web/bottom trio
    # lives inside it. Home-scoped shortcuts + focus checks key off this widget.
    _home_content: QWidget
    # The tabbed/dockable workspace hosting home + tool tabs (see workspace.py).
    # The Ankountant SvelteKit shell (Readiness / Confusion / TBS) is one of its
    # tool tabs (workspace.open_ankountant), not a main-window state.
    workspace: Workspace

    def __init__(
        self,
        app: aqt.AnkiApp,
        profileManager: ProfileManagerType,
        backend: _RustBackend,
        opts: Namespace,
        args: list[Any],
    ) -> None:
        QMainWindow.__init__(self)
        self.backend = backend
        self.state: MainWindowState = "startup"
        self.opts = opts
        self.col: Collection | None = None
        self.taskman = TaskManager(self)
        self.media_syncer = MediaSyncer(self)
        aqt.mw = self
        self.app = app
        self.pm = profileManager
        self.fullscreen = False
        # Ankountant-first layout: land on the SvelteKit shell with the classic
        # Qt chrome (menubar, dock tab strip, top toolbar) hidden. Toggle with
        # the escape-hatch shortcut to reach the classic tools. Set in
        # loadProfile once the workspace exists.
        self._ankountant_fullscreen = False
        # init rest of app
        self.safeMode = (
            bool(self.app.queryKeyboardModifiers() & Qt.KeyboardModifier.ShiftModifier)
            or self.opts.safemode
        )
        try:
            self.setupUI()
            self.setupAddons(args)
            self.finish_ui_setup()
        except Exception:
            showInfo(tr.qt_misc_error_during_startup(val=traceback.format_exc()))
            sys.exit(1)
        # must call this after ui set up
        if self.safeMode:
            tooltip(tr.qt_misc_shift_key_was_held_down_skipping())
        # were we given a file to import?
        if args and args[0] and not self._isAddon(args[0]):
            self.onAppMsg(args[0])
        # Load profile in a timer so we can let the window finish init and not
        # close on profile load error.
        if is_win:
            fn = self.setupProfileAfterWebviewsLoaded
        else:
            fn = self.setupProfile

        def on_window_init() -> None:
            fn()
            gui_hooks.main_window_did_init()

        self.progress.single_shot(10, on_window_init, False)

    def setupUI(self) -> None:
        self.col = None
        # Container for the home (Decks/Study) surface: the toolbar/web/bottom
        # trio lives inside it (filled in setupMainWindow). Created before
        # setupKeys so home-scoped shortcuts can be parented to it.
        self._home_content = QWidget()
        self.disable_automatic_garbage_collection()
        self.setupAppMsg()
        self.setupKeys()
        self.setupThreads()
        self.setupMediaServer()
        self.setupSpellCheck()
        self.setupProgress()
        self.setupStyle()
        self.setupMainWindow()
        self.setupSystemSpecific()
        self.setupMenus()
        self.setupErrorHandler()
        self.setupSignals()
        self.setupHooks()
        self.setup_timers()
        self.updateTitleBar()
        self.setup_focus()
        # screens
        self.setupDeckBrowser()
        self.setupOverview()
        self.setupReviewer()

    def finish_ui_setup(self) -> None:
        "Actions that are deferred until after add-on loading."
        self.toolbar.draw()
        # add-ons are only available here after setupAddons
        gui_hooks.reviewer_did_init(self.reviewer)

    def setupProfileAfterWebviewsLoaded(self) -> None:
        for w in (self.web, self.bottomWeb):
            if not w._domDone:
                self.progress.single_shot(
                    10,
                    self.setupProfileAfterWebviewsLoaded,
                    False,
                )
                return
            else:
                w.requiresCol = True

        self.setupProfile()

    def weakref(self) -> AnkiQt:
        "Shortcut to create a weak reference that doesn't break code completion."
        return weakref.proxy(self)  # type: ignore

    def setup_focus(self) -> None:
        qconnect(self.app.focusChanged, self.on_focus_changed)

    def on_focus_changed(self, old: QWidget, new: QWidget) -> None:
        gui_hooks.focus_did_change(new, old)

    # Profiles
    ##########################################################################

    class ProfileManager(QMainWindow):
        onClose = pyqtSignal()
        closeFires = True

        def closeEvent(self, evt: QCloseEvent) -> None:
            if self.closeFires:
                self.onClose.emit()  # type: ignore
            evt.accept()

        def closeWithoutQuitting(self) -> None:
            self.closeFires = False
            self.close()
            self.closeFires = True

    def setupProfile(self) -> None:
        if self.pm.meta["firstRun"]:
            # load the new deck user profile
            self.pm.load(self.pm.profiles()[0])
            self.pm.meta["firstRun"] = False
            self.pm.save()

        self.pendingImport: str | None = None
        self.restoring_backup = False
        # - if a valid profile was provided on commandline, we load it
        # - if an invalid profile was provided, we skip this step and show the picker
        # - if no profile was provided, we use this step
        if not self.pm.name and not self.pm.invalid_profile_provided_on_commandline:
            profs = self.pm.profiles()
            name = self.pm.last_loaded_profile_name()
            if len(profs) == 1:
                self.pm.load(profs[0])
            elif name in profs:
                self.pm.load(name)

        if not self.pm.name:
            self.showProfileManager()
        else:
            self.loadProfile()

    def showProfileManager(self) -> None:
        self.pm.profile = None
        self.moveToState("profileManager")
        d = self.profileDiag = self.ProfileManager()
        f = self.profileForm = aqt.forms.profiles.Ui_MainWindow()
        f.setupUi(d)
        qconnect(f.login.clicked, self.onOpenProfile)
        qconnect(f.profiles.itemDoubleClicked, self.onOpenProfile)
        qconnect(f.openBackup.clicked, self.onOpenBackup)
        qconnect(f.quit.clicked, d.close)
        qconnect(d.onClose, self.cleanupAndExit)
        qconnect(f.add.clicked, self.onAddProfile)
        qconnect(f.rename.clicked, self.onRenameProfile)
        qconnect(f.delete_2.clicked, self.onRemProfile)
        qconnect(f.profiles.currentRowChanged, self.onProfileRowChange)
        f.statusbar.setVisible(False)
        qconnect(f.downgrade_button.clicked, self._on_downgrade)
        f.downgrade_button.setText(tr.profiles_downgrade_and_quit())
        # enter key opens profile
        QShortcut(QKeySequence("Return"), d, activated=self.onOpenProfile)  # type: ignore
        self.refreshProfilesList()
        # raise first, for osx testing
        d.show()
        d.activateWindow()
        d.raise_()

    def refreshProfilesList(self) -> None:
        f = self.profileForm
        f.profiles.clear()
        profs = self.pm.profiles()
        f.profiles.addItems(profs)
        try:
            idx = profs.index(self.pm.name)
        except Exception:
            idx = 0
        f.profiles.setCurrentRow(idx)

    def onProfileRowChange(self, n: int) -> None:
        if n < 0:
            # called on .clear()
            return
        name = self.pm.profiles()[n]
        self.pm.load(name)

    def openProfile(self) -> None:
        name = self.pm.profiles()[self.profileForm.profiles.currentRow()]
        self.pm.load(name)

    def onOpenProfile(self, *, callback: Callable[[], None] | None = None) -> None:
        def on_done() -> None:
            self.profileDiag.closeWithoutQuitting()
            if callback:
                callback()

        self.profileDiag.hide()
        # code flow is confusing here - if load fails, profile dialog
        # will be shown again
        self.loadProfile(on_done)

    def profileNameOk(self, name: str) -> bool:
        return not checkInvalidFilename(name) and name != "addons21"

    def onAddProfile(self) -> None:
        name = getOnlyText(tr.actions_name()).strip()
        if name:
            if name in self.pm.profiles():
                showWarning(tr.qt_misc_name_exists())
                return
            if not self.profileNameOk(name):
                return
            self.pm.create(name)
            self.pm.name = name
            self.refreshProfilesList()

    def onRenameProfile(self) -> None:
        name = getOnlyText(tr.actions_new_name(), default=self.pm.name).strip()
        if not name:
            return
        if name == self.pm.name:
            return
        if name in self.pm.profiles():
            showWarning(tr.qt_misc_name_exists())
            return
        if not self.profileNameOk(name):
            return
        self.pm.rename(name)
        self.refreshProfilesList()

    def onRemProfile(self) -> None:
        profs = self.pm.profiles()
        if len(profs) < 2:
            showWarning(tr.qt_misc_there_must_be_at_least_one())
            return
        # sure?
        if not askUser(
            tr.qt_misc_all_cards_notes_and_media_for2(name=self.pm.name),
            msgfunc=QMessageBox.warning,
            defaultno=True,
        ):
            return
        self.pm.remove(self.pm.name)
        self.refreshProfilesList()

    def _handle_load_backup_success(self) -> None:
        """
        Actions that occur when profile backup has been loaded successfully
        """
        if self.state == "profileManager":
            self.profileDiag.closeWithoutQuitting()

        self.loadProfile()

    def _handle_load_backup_failure(self, error: Exception) -> None:
        """
        Actions that occur when a profile has loaded unsuccessfully
        """
        showWarning(str(error))
        if self.state != "profileManager":
            self.loadProfile()

    def onOpenBackup(self) -> None:
        def do_open(path: str) -> None:
            if not askUser(
                tr.qt_misc_replace_your_collection_with_an_earlier2(
                    os.path.basename(path)
                ),
                msgfunc=QMessageBox.warning,
                defaultno=True,
            ):
                return

            showInfo(tr.qt_misc_automatic_syncing_and_backups_have_been())

            # Collection is still loaded if called from main window, so we unload. This is already
            # unloaded if called from the ProfileManager window.
            if self.col:
                self.unloadProfile(lambda: self._start_restore_backup(path))
                return

            self._start_restore_backup(path)

        getFile(
            self.profileDiag if self.state == "profileManager" else self,
            tr.qt_misc_revert_to_backup(),
            cb=do_open,  # type: ignore
            filter="*.colpkg",
            dir=self.pm.backupFolder(),
        )

    def _start_restore_backup(self, path: str):
        self.restoring_backup = True

        from aqt.import_export.importing import import_collection_package_op

        import_collection_package_op(
            self, path, success=self._handle_load_backup_success
        ).failure(self._handle_load_backup_failure).run_in_background()

    def _on_downgrade(self) -> None:
        self.progress.start()
        profiles = self.pm.profiles()

        def downgrade() -> list[str]:
            return self.pm.downgrade(profiles)

        def on_done(future: Future) -> None:
            self.progress.finish()
            problems = future.result()
            if not problems:
                showInfo("Profiles can now be opened with an older version of Anki.")
            else:
                showWarning(
                    "The following profiles could not be downgraded: {}".format(
                        ", ".join(problems)
                    )
                )
                return
            self.profileDiag.close()

        self.taskman.run_in_background(downgrade, on_done)

    def loadProfile(self, onsuccess: Callable | None = None) -> None:
        if not self.loadCollection():
            return

        self.setup_sound()
        self.flags = FlagManager(self)
        # show main window
        restoreGeom(self, "mainWindow")
        restoreState(self, "mainWindow")
        # re-open the workspace tool tabs + dock layout saved for this profile
        # (must run after restoreState so its own saveState blob wins)
        self.workspace.restore_layout()
        # Ankountant is the app: land on the SvelteKit shell with the classic Qt
        # chrome hidden, instead of the Python-rendered deck browser. The state
        # machine still runs underneath (for the study flow); the shell dock
        # simply sits on top. Escape-hatch shortcut reveals the classic tools.
        self.set_ankountant_fullscreen(True)
        self.workspace.enter_home_shell()
        # titlebar
        self.setWindowTitle(f"{self.pm.name} - Ankountant")
        # show and raise window for osx
        self.show()
        self.activateWindow()
        self.raise_()

        # import pending?
        if self.pendingImport:
            if self._isAddon(self.pendingImport):
                self.installAddon(self.pendingImport)
            else:
                self.handleImport(self.pendingImport)
            self.pendingImport = None

        def _onsuccess(synced: bool) -> None:
            if synced:
                self._refresh_after_sync()
            if onsuccess:
                onsuccess()
            if not self.safeMode:
                self.maybe_check_for_addon_updates(self.setup_auto_update)

        last_day_cutoff = self.col.sched.day_cutoff

        def refresh_reviewer_on_day_rollover_change():
            from aqt.reviewer import RefreshNeeded

            # need to refresh?
            nonlocal last_day_cutoff
            current_cutoff = self.col.sched.day_cutoff
            if self.state == "review" and last_day_cutoff != current_cutoff:
                last_day_cutoff = self.col.sched.day_cutoff
                self.reviewer._refresh_needed = RefreshNeeded.QUEUES
                self.reviewer.refresh_if_needed()
            if last_day_cutoff != current_cutoff:
                gui_hooks.day_did_change()

            # schedule another check
            secs_until_cutoff = current_cutoff - int_time()
            self._reviewer_refresh_timer = self.progress.timer(
                secs_until_cutoff * 1000,
                refresh_reviewer_on_day_rollover_change,
                repeat=False,
                parent=self,
            )

        refresh_reviewer_on_day_rollover_change()
        gui_hooks.profile_did_open()
        self.maybe_auto_sync_on_open_close(_onsuccess)

    def unloadProfile(self, onsuccess: Callable) -> None:
        def callback() -> None:
            self._unloadProfile()
            onsuccess()

        gui_hooks.profile_will_close()
        self.unloadCollection(callback)

    def _unloadProfile(self) -> None:
        self.cleanup_sound()
        saveGeom(self, "mainWindow")
        saveState(self, "mainWindow")
        self.pm.save()
        self.hide()

        self.restoring_backup = False

        # at this point there should be no windows left
        self._checkForUnclosedWidgets()
        self._reviewer_refresh_timer.deleteLater()

    def _checkForUnclosedWidgets(self) -> None:
        for w in self.app.topLevelWidgets():
            if w.isVisible():
                # windows with this property are safe to close immediately
                if getattr(w, "silentlyClose", None):
                    w.close()
                else:
                    print(f"Window should have been closed: {w}")

    def unloadProfileAndExit(self) -> None:
        self.unloadProfile(self.cleanupAndExit)

    def unloadProfileAndShowProfileManager(self) -> None:
        self.unloadProfile(self.showProfileManager)

    def cleanupAndExit(self) -> None:
        self.errorHandler.unload()
        self.mediaServer.shutdown()
        # Rust background jobs are not awaited implicitly
        self.backend.await_backup_completion()
        self.deleteLater()
        app = self.app
        app._unset_windows_shutdown_block_reason()

        def exit():
            # try to ensure Qt objects are deleted in a logical order,
            # to prevent crashes on shutdown
            gc.collect()
            app.exit(0)

        self.progress.single_shot(100, exit, False)

    # Sound/video
    ##########################################################################

    def setup_sound(self) -> None:
        aqt.sound.setup_audio(self.taskman, self.pm.base, self.col.media.dir())

    def cleanup_sound(self) -> None:
        aqt.sound.cleanup_audio()

    def _add_play_buttons(self, text: str) -> str:
        "Return card text with play buttons added, or stripped."
        if self.col.get_config_bool(Config.Bool.HIDE_AUDIO_PLAY_BUTTONS):
            return anki.sound.strip_av_refs(text)
        else:
            return aqt.sound.av_refs_to_play_icons(text)

    def prepare_card_text_for_display(self, text: str) -> str:
        text = self.col.media.escape_media_filenames(text)
        text = self._add_play_buttons(text)
        return text

    # Collection load/unload
    ##########################################################################

    def loadCollection(self) -> bool:
        try:
            self._loadCollection()
        except Exception as e:
            if "FileTooNew" in str(e):
                showWarning(
                    "This profile requires a newer version of Anki to open. Did you forget to use the Downgrade button prior to switching Anki versions?"
                )
            else:
                showWarning(
                    f"{tr.errors_unable_open_collection()}\n{traceback.format_exc()}"
                )
            # clean up open collection if possible
            try:
                self.backend.close_collection(downgrade_to_schema11=False)
            except Exception as e:
                print("unable to close collection:", e)
            self.col = None
            # return to profile manager
            self.hide()
            self.showProfileManager()
            return False

        # make sure we don't get into an inconsistent state if an add-on
        # has broken the deck browser or the did_load hook
        try:
            self.update_undo_actions()
            gui_hooks.collection_did_load(self.col)
            self.apply_collection_options()
            self.moveToState("deckBrowser")
        except Exception:
            # dump error to stderr so it gets picked up by errors.py
            traceback.print_exc()

        return True

    def _loadCollection(self) -> None:
        cpath = self.pm.collectionPath()
        self.col = Collection(cpath, backend=self.backend)
        self.setEnabled(True)

    def reopen(self, after_full_sync: bool = False) -> None:
        self.col.reopen(after_full_sync=after_full_sync)
        gui_hooks.collection_did_temporarily_close(self.col)

    def unloadCollection(self, onsuccess: Callable) -> None:
        def after_media_sync() -> None:
            self._unloadCollection()
            onsuccess()

        def after_sync(synced: bool) -> None:
            self.media_syncer.show_diag_until_finished(after_media_sync)

        def before_sync() -> None:
            self.setEnabled(False)
            self.maybe_auto_sync_on_open_close(after_sync)

        self.closeAllWindows(before_sync)

    def _unloadCollection(self) -> None:
        if not self.col:
            return

        label = (
            tr.qt_misc_closing() if self.restoring_backup else tr.qt_misc_backing_up()
        )
        self.progress.start(label=label)

        corrupt = False

        try:
            self.maybeOptimize()
            if not dev_mode:
                corrupt = self.col.db.scalar("pragma quick_check") != "ok"
        except Exception:
            corrupt = True

        try:
            if not corrupt and not dev_mode and not self.restoring_backup:
                try:
                    # default 5 minute throttle
                    self.col.create_backup(
                        backup_folder=self.pm.backupFolder(),
                        force=False,
                        wait_for_completion=False,
                    )
                except Exception:
                    print("backup on close failed")
            self.col.close(downgrade=False)
        except Exception as e:
            print(e)
            corrupt = True
        finally:
            self.col = None
            self.progress.finish()

        if corrupt:
            showWarning(tr.qt_misc_your_collection_file_appears_to_be())

    def apply_collection_options(self) -> None:
        "Setup audio after collection loaded."
        aqt.sound.av_player.interrupt_current_audio = self.col.get_config_bool(
            Config.Bool.INTERRUPT_AUDIO_WHEN_ANSWERING
        )

    # Auto-optimize
    ##########################################################################

    def maybeOptimize(self) -> None:
        # have two weeks passed?
        if (last_optimize := self.pm.profile.get("lastOptimize")) is not None:
            if (int_time() - last_optimize) < 86400 * 14:
                return
        self.progress.start(label=tr.qt_misc_optimizing())
        self.col.optimize()
        self.pm.profile["lastOptimize"] = int_time()
        self.pm.save()
        self.progress.finish()

    # Tracking main window state (deck browser, reviewer, etc)
    ##########################################################################

    def moveToState(self, state: MainWindowState, *args: Any) -> None:
        # print("-> move from", self.state, "to", state)
        oldState = self.state
        cleanup = getattr(self, f"_{oldState}Cleanup", None)
        if cleanup:
            cleanup(state)
        self.clearStateShortcuts()
        self.state = state
        gui_hooks.state_will_change(state, oldState)
        getattr(self, f"_{state}State", lambda *_: None)(oldState, *args)
        if state != "resetRequired":
            self.bottomWeb.adjustHeightToFit()
        # Bring the home tab forward when entering a home surface, in case the
        # user was in a tool tab (workspace is absent very early in startup).
        if getattr(self, "workspace", None):
            if self._ankountant_fullscreen:
                # Ankountant-first: the study surfaces show the home dock, but
                # the deck browser (e.g. a post-sync/reset transition) and the
                # end-of-session overview return to the shell instead, so the
                # classic deck table / congrats never pops over it.
                if state == "review" or (state == "overview" and oldState != "review"):
                    self.workspace.show_home_only()
                elif state == "deckBrowser" or (
                    state == "overview" and oldState == "review"
                ):
                    self.workspace.return_to_shell()
            elif state in ("deckBrowser", "overview", "review"):
                self.workspace.raise_home()
        gui_hooks.state_did_change(state, oldState)

    def _deckBrowserState(self, oldState: MainWindowState) -> None:
        self.deckBrowser.show()

    def _selectedDeck(self) -> DeckDict | None:
        did = self.col.decks.selected()
        if not self.col.decks.name_if_exists(did):
            showInfo(tr.qt_misc_please_select_a_deck())
            return None
        return self.col.decks.get(did)

    def _overviewState(self, oldState: MainWindowState) -> None:
        if not self._selectedDeck():
            return self.moveToState("deckBrowser")
        self.overview.show()

    def _reviewState(self, oldState: MainWindowState) -> None:
        self.reviewer.show()

        fullscreen_was_checked = False

        if self.pm.hide_top_bar():
            self.toolbarWeb.hide_timer.setInterval(500)
            self.toolbarWeb.hide_timer.start()

            # check the `hide_if_allowed` method in `qt/aqt/toolbar.py`
            fullscreen_was_checked = True
        else:
            self.toolbarWeb.flatten()

        if not fullscreen_was_checked and self.fullscreen:
            self.hide_menubar()

        if self.pm.hide_bottom_bar():
            self.bottomWeb.hide_timer.setInterval(500)
            self.bottomWeb.hide_timer.start()

    def _reviewCleanup(self, newState: MainWindowState) -> None:
        if newState not in {"resetRequired", "review"}:
            self.reviewer.auto_advance_enabled = False
            self.reviewer.cleanup()
            self.toolbarWeb.elevate()
            self.toolbarWeb.show()
            self.bottomWeb.show()

    # Resetting state
    ##########################################################################

    def _increase_background_ops(self) -> None:
        if not self._background_op_count:
            gui_hooks.backend_will_block()
        self._background_op_count += 1

    def _decrease_background_ops(self) -> None:
        self._background_op_count -= 1
        if not self._background_op_count:
            gui_hooks.backend_did_block()
        if self._background_op_count < 0:
            raise Exception("no background ops active")

    def _synthesize_op_did_execute_from_reset(self) -> None:
        """Fire the `operation_did_execute` hook with everything marked as changed,
        after legacy code has called .reset()"""
        op = OpChanges()
        for field in op.DESCRIPTOR.fields:
            if field.name != "kind":
                setattr(op, field.name, True)
        gui_hooks.operation_did_execute(op, None)

    def on_operation_did_execute(
        self, changes: OpChanges, handler: object | None
    ) -> None:
        "Notify current screen of changes."
        # Containment-aware: the home surface counts as focused only when focus
        # is actually inside it, not merely anywhere in the (single) window —
        # e.g. not while the user works in a workspace tool tab.
        focused = widget_effectively_focused(self._home_content)
        if self.state == "review":
            dirty = self.reviewer.op_executed(changes, handler, focused)
        elif self.state == "overview":
            dirty = self.overview.op_executed(changes, handler, focused)
        elif self.state == "deckBrowser":
            dirty = self.deckBrowser.op_executed(changes, handler, focused)
        else:
            dirty = False

        if not focused and dirty:
            self.fade_out_webview()

        if changes.mtime:
            self.toolbar.update_sync_status()

        if changes.notetype:
            self.col.models._clear_cache()

    def on_focus_did_change(
        self, new_focus: QWidget | None, _old: QWidget | None
    ) -> None:
        "If the home surface has received focus, ensure current UI state is updated."
        if new_focus and (
            new_focus is self._home_content
            or self._home_content.isAncestorOf(new_focus)
        ):
            if self.state == "review":
                self.reviewer.refresh_if_needed()
            elif self.state == "overview":
                self.overview.refresh_if_needed()
            elif self.state == "deckBrowser":
                self.deckBrowser.refresh_if_needed()

    def fade_out_webview(self) -> None:
        self.web.eval("document.body.style.opacity = 0.3")

    def fade_in_webview(self) -> None:
        self.web.eval("document.body.style.opacity = 1")

    def reset(self, unused_arg: bool = False) -> None:
        """Legacy method of telling UI to refresh after changes made to DB.

        New code should use CollectionOp() instead."""
        if self.col:
            # fire new `operation_did_execute` hook first. If the overview
            # or review screen are currently open, they will rebuild the study
            # queues (via mw.col.reset())
            self._synthesize_op_did_execute_from_reset()
            # fire the old reset hook
            gui_hooks.state_did_reset()
            self.update_undo_actions()

    # legacy

    def requireReset(
        self,
        modal: bool = False,
        reason: Any | None = None,
        context: Any | None = None,
    ) -> None:
        traceback.print_stack(file=sys.stdout)
        print("requireReset() is obsolete; please use CollectionOp()")
        self.reset()

    def maybeReset(self) -> None:
        pass

    def delayedMaybeReset(self) -> None:
        pass

    def _resetRequiredState(self, oldState: MainWindowState) -> None:
        pass

    # HTML helpers
    ##########################################################################

    def button(
        self,
        link: str,
        name: str,
        key: str | None = None,
        class_: str = "",
        id: str = "",
        extra: str = "",
    ) -> str:
        class_ = f"but {class_}"
        if key:
            key = tr.actions_shortcut_key(val=key)
        else:
            key = ""
        return """
<button id="{}" class="{}" onclick="pycmd('{}');return false;"
title="{}" {}>{}</button>""".format(
            id,
            class_,
            link,
            key,
            extra,
            name,
        )

    # Main window setup
    ##########################################################################

    def setupMainWindow(self) -> None:
        from aqt.workspace import Workspace

        # main window
        self.form = aqt.forms.main.Ui_MainWindow()
        self.form.setupUi(self)
        # toolbar
        tweb = self.toolbarWeb = TopWebView(self)
        self.toolbar = Toolbar(self, tweb)
        # main area
        self.web = MainWebView(self)
        # bottom area
        sweb = self.bottomWeb = BottomWebView(self)
        sweb.setFocusPolicy(Qt.FocusPolicy.WheelFocus)
        sweb.disable_zoom()
        # the home (Decks/Study) surface: trio stacked inside _home_content
        # (created early in setupUI so home-scoped shortcuts can bind to it).
        # The moveToState state machine keeps driving these three webviews.
        self.mainLayout = QVBoxLayout(self._home_content)
        self.mainLayout.setContentsMargins(0, 0, 0, 0)
        self.mainLayout.setSpacing(0)
        self.mainLayout.addWidget(tweb)
        self.mainLayout.addWidget(self.web)
        self.mainLayout.addWidget(sweb)
        # Turn the main window into a browser-style tabbed workspace: home
        # becomes a permanent tab; tools (Add/Browse/Stats/Ankountant) open as
        # dockable tabs alongside it. See qt/aqt/workspace.py.
        self.workspace = Workspace(self)
        self.workspace.build(self._home_content)
        # Keep the Ankountant window frame painted with the design-system canvas
        # across light/dark theme switches.
        gui_hooks.theme_did_change.append(self._apply_ankountant_window_style)

        # force webengine processes to load before cwd is changed
        if is_win:
            for webview in self.web, self.bottomWeb:
                webview.force_load_hack()

        gui_hooks.card_review_webview_did_init(self.web, AnkiWebViewKind.MAIN)

    def closeAllWindows(self, onsuccess: Callable) -> None:
        # Snapshot the workspace layout while the tool docks still exist —
        # dialogs.closeAll (below) tears them down.
        if getattr(self, "workspace", None):
            self.workspace.save_layout()

        def after_dialogs_closed() -> None:
            if getattr(self, "workspace", None):
                # Dispose surfaces the DialogManager doesn't own (shell webview).
                self.workspace.shutdown()
            onsuccess()

        aqt.dialogs.closeAll(after_dialogs_closed)

    # Components
    ##########################################################################

    def setupSignals(self) -> None:
        signal.signal(signal.SIGINT, self.onUnixSignal)
        signal.signal(signal.SIGTERM, self.onUnixSignal)

    def onUnixSignal(self, signum: Any, frame: Any) -> None:
        def quit() -> None:
            self.close()

        self.progress.single_shot(100, quit)

    def setupProgress(self) -> None:
        self.progress = aqt.progress.ProgressManager(self)

    def setupErrorHandler(self) -> None:
        import aqt.errors

        self.errorHandler = aqt.errors.ErrorHandler(self)

    def setupAddons(self, args: list | None) -> None:
        import aqt.addons

        self.addonManager = aqt.addons.AddonManager(self)

        if args and args[0] and self._isAddon(args[0]):
            self.installAddon(args[0], startup=True)

        if not self.safeMode:
            self.addonManager.loadAddons()

    def maybe_check_for_addon_updates(
        self, on_done: Callable[[list[DownloadLogEntry]], None] | None = None
    ) -> None:
        if not self.pm.check_for_addon_updates():
            if on_done:
                on_done([])
            return

        last_check = self.pm.last_addon_update_check()
        elap = int_time() - last_check

        if elap > 86_400 or self.pm.last_run_version != int_version():
            self.check_for_addon_updates(by_user=False, on_done=on_done)
        elif on_done:
            on_done([])

    def check_for_addon_updates(
        self,
        by_user: bool,
        on_done: Callable[[list[DownloadLogEntry]], None] | None = None,
    ) -> None:
        def wrap_on_updates_installed(log: list[DownloadLogEntry]) -> None:
            self.on_updates_installed(log)
            self.pm.set_last_addon_update_check(int_time())
            if on_done:
                on_done(log)

        check_and_prompt_for_updates(
            self,
            self.addonManager,
            wrap_on_updates_installed,
            requested_by_user=by_user,
        )

    def on_updates_installed(self, log: list[DownloadLogEntry]) -> None:
        if log:
            show_log_to_user(self, log)

    def setupSpellCheck(self) -> None:
        os.environ["QTWEBENGINE_DICTIONARIES_PATH"] = os.path.join(
            self.pm.base, "dictionaries"
        )

    def setupThreads(self) -> None:
        self._mainThread = QThread.currentThread()
        self._background_op_count = 0

    def inMainThread(self) -> bool:
        return self._mainThread == QThread.currentThread()

    def setupDeckBrowser(self) -> None:
        from aqt.deckbrowser import DeckBrowser

        self.deckBrowser = DeckBrowser(self)

    def setupOverview(self) -> None:
        from aqt.overview import Overview

        self.overview = Overview(self)

    def setupReviewer(self) -> None:
        from aqt.reviewer import Reviewer

        self.reviewer = Reviewer(self)

    # Syncing
    ##########################################################################

    def on_sync_button_clicked(self) -> None:
        if self.media_syncer.is_syncing():
            self.media_syncer.show_sync_log()
        else:
            auth = self.pm.sync_auth()
            if not auth:
                sync_login(
                    self,
                    lambda: self._sync_collection_and_media(self._refresh_after_sync),
                )
            else:
                self._sync_collection_and_media(self._refresh_after_sync)

    def _refresh_after_sync(self) -> None:
        self.toolbar.redraw()
        self.flags.require_refresh()

    def _sync_collection_and_media(self, after_sync: Callable[[], None]) -> None:
        "Caller should ensure auth available."

        def on_collection_sync_finished() -> None:
            self.col.models._clear_cache()
            gui_hooks.sync_did_finish()
            self.reset()

            after_sync()

        gui_hooks.sync_will_start()
        sync_collection(self, on_done=on_collection_sync_finished)

    def maybe_auto_sync_on_open_close(self, after_sync: Callable[[bool], None]) -> None:
        "If disabled, after_sync() is called immediately."
        if self.can_auto_sync():
            self._sync_collection_and_media(lambda: after_sync(True))
        else:
            after_sync(False)

    def can_auto_sync(self) -> bool:
        "True if syncing on startup/shutdown enabled."
        return self._can_sync_unattended() and self.pm.auto_syncing_enabled()

    def _can_sync_unattended(self) -> bool:
        return (
            bool(self.pm.sync_auth())
            and not self.safeMode
            and not self.restoring_backup
        )

    # legacy
    def _sync(self) -> None:
        pass

    onSync = on_sync_button_clicked

    # Tools
    ##########################################################################

    def raiseMain(self) -> bool:
        if not self.app.activeWindow():
            # make sure window is shown
            self.setWindowState(self.windowState() & ~Qt.WindowState.WindowMinimized)  # type: ignore
        return True

    def setupStyle(self) -> None:
        theme_manager.apply_style()
        if is_lin:
            # On Linux, the check requires invoking an external binary,
            # and can potentially produce verbose logs on systems where
            # the preferred theme cannot be determined,
            # which we don't want to be doing frequently
            interval_secs = 300
        else:
            interval_secs = 2
        self.progress.timer(
            interval_secs * 1000,
            theme_manager.apply_style,
            True,
            False,
            parent=self,
        )

    def set_theme(self, theme: Theme) -> None:
        self.pm.set_theme(theme)
        self.setupStyle()

    # Key handling
    ##########################################################################

    def setupKeys(self) -> None:
        # Single-letter shortcuts are scoped to the home surface (see
        # applyShortcuts) so they don't fire — or eat typed text — while the
        # user works inside a workspace tool tab (Add/Browse/Stats/...).
        globalShortcuts = [
            ("d", lambda: self.moveToState("deckBrowser")),
            ("s", self.onStudyKey),
            ("a", self.onAddCard),
            ("b", self.onBrowse),
            ("t", self.onStats),
            ("Shift+t", self.onStats),
            ("y", self.on_sync_button_clicked),
        ]
        self.applyShortcuts(globalShortcuts)
        # The debug console stays reachable from anywhere in the window.
        debug_shortcut = QShortcut(QKeySequence("Ctrl+:"), self)
        debug_shortcut.setAutoRepeat(False)
        qconnect(debug_shortcut.activated, show_debug_console)
        # Ankountant-first layout: an escape hatch to reveal the classic Qt
        # chrome (menubar + deck browser + tools, for deck management etc.) and a
        # quick way back to the Ankountant home shell. Application-scoped so they
        # fire from any surface, including inside the SvelteKit webview and the
        # reviewer.
        chrome_toggle = QShortcut(QKeySequence("Ctrl+Shift+D"), self)
        chrome_toggle.setContext(Qt.ShortcutContext.ApplicationShortcut)
        qconnect(chrome_toggle.activated, self.toggle_ankountant_fullscreen)
        home_shortcut = QShortcut(QKeySequence("Ctrl+Shift+H"), self)
        home_shortcut.setContext(Qt.ShortcutContext.ApplicationShortcut)
        qconnect(
            home_shortcut.activated,
            lambda: self.workspace.enter_home_shell()
            if getattr(self, "workspace", None)
            else None,
        )
        self.stateShortcuts: list[QShortcut] = []

    def _close_active_window(self) -> None:
        # If focus is inside a workspace tool tab, Ctrl/Cmd+W closes that tab
        # (current_window() would otherwise resolve to the main window).
        if (
            not QApplication.activeModalWidget()
            and (ws := getattr(self, "workspace", None))
            and (tool := ws.tool_for_focus())
        ):
            ws.close_tool_widget(tool)
            return
        window = (
            QApplication.activeModalWidget()
            or current_window()
            or self.app.activeWindow()
        )
        if not window or window is self:
            return
        if window is getattr(self, "profileDiag", None):
            # Do not allow closing of ProfileManager
            return
        if isinstance(window, QDialog):
            window.reject()
        else:
            window.close()

    def _normalize_shortcuts(
        self, shortcuts: Sequence[tuple[str, Callable]]
    ) -> Sequence[tuple[QKeySequence, Callable]]:
        """
        Remove duplicate shortcuts (possibly added by add-ons)
        by normalizing them and filtering through a dictionary.
        The last duplicate shortcut wins, so add-ons will override
        standard shortcuts if they append to the shortcut list.
        """
        return tuple({QKeySequence(key): fn for key, fn in shortcuts}.items())

    def applyShortcuts(
        self, shortcuts: Sequence[tuple[str, Callable]]
    ) -> list[QShortcut]:
        """Bind shortcuts scoped to the home (Decks/Study) surface.

        Parenting to `_home_content` with WidgetWithChildrenShortcut keeps
        single-letter keys and reviewer answer keys from firing while focus is
        inside a workspace tool tab (Add Cards / Browser / Stats / ...)."""
        qshortcuts = []
        for key, fn in self._normalize_shortcuts(shortcuts):
            scut = QShortcut(key, self._home_content, activated=fn)  # type: ignore
            scut.setContext(Qt.ShortcutContext.WidgetWithChildrenShortcut)
            scut.setAutoRepeat(False)
            qshortcuts.append(scut)
        return qshortcuts

    def setStateShortcuts(self, shortcuts: list[tuple[str, Callable]]) -> None:
        gui_hooks.state_shortcuts_will_change(self.state, shortcuts)
        # legacy hook
        runHook(f"{self.state}StateShortcuts", shortcuts)
        self.stateShortcuts = self.applyShortcuts(shortcuts)

    def clearStateShortcuts(self) -> None:
        for qs in self.stateShortcuts:
            sip.delete(qs)  # type: ignore
        self.stateShortcuts = []

    def onStudyKey(self) -> None:
        if self.state == "overview":
            self.col.startTimebox()
            self.moveToState("review")
        else:
            self.moveToState("overview")

    # App exit
    ##########################################################################

    def closeEvent(self, event: QCloseEvent) -> None:
        if self.state == "profileManager":
            # if profile manager active, this event may fire via OS X menu bar's
            # quit option
            self.profileDiag.close()
            event.accept()
        else:
            # ignore the event for now, as we need time to clean up
            event.ignore()
            self.unloadProfileAndExit()

    # Undo & autosave
    ##########################################################################

    def undo(self) -> None:
        "Call operations/collection.py:undo() directly instead."
        undo(parent=self)

    def redo(self) -> None:
        "Call operations/collection.py:redo() directly instead."
        redo(parent=self)

    def undo_actions_info(self) -> UndoActionsInfo:
        "Info about the current undo/redo state for updating menus."
        status = self.col.undo_status() if self.col else UndoStatus()
        return UndoActionsInfo.from_undo_status(status)

    def update_undo_actions(self) -> None:
        """Tell the UI to redraw the undo/redo menu actions based on the current state.

        Usually you do not need to call this directly; it is called when a
        CollectionOp is run, and will be called when the legacy .reset() or
        .checkpoint() methods are used."""
        info = self.undo_actions_info()
        self.form.actionUndo.setText(info.undo_text)
        self.form.actionUndo.setEnabled(info.can_undo)
        self.form.actionRedo.setText(info.redo_text)
        self.form.actionRedo.setEnabled(info.can_redo)
        self.form.actionRedo.setVisible(info.show_redo)
        gui_hooks.undo_state_did_change(info)

    @deprecated(info="checkpoints are no longer supported")
    def checkpoint(self, name: str) -> None:
        pass

    @deprecated(info="saving is automatic")
    def autosave(self) -> None:
        pass

    onUndo = undo

    # Other menu operations
    ##########################################################################

    def onAddCard(self) -> None:
        aqt.dialogs.open("AddCards", self)

    def onBrowse(self) -> None:
        aqt.dialogs.open("Browser", self, card=self.reviewer.card)

    def onEditCurrent(self) -> None:
        aqt.dialogs.open("EditCurrent", self)

    def onOverview(self) -> None:
        self.moveToState("overview")

    def onStats(self) -> None:
        deck = self._selectedDeck()
        if not deck:
            return
        want_old = KeyboardModifiersPressed().shift
        if want_old:
            aqt.dialogs.open("DeckStats", self)
        else:
            aqt.dialogs.open("NewDeckStats", self)

    def onPrefs(self) -> None:
        aqt.dialogs.open("Preferences", self)

    def on_check_for_updates(self) -> None:
        from packaging.version import Version

        from aqt.update import get_latest_release_op, prompt_and_install_github_update

        version = Version(version_str)

        def on_success(release: GithubRelease) -> None:
            if Version(release.tag_name) > version:
                prompt_and_install_github_update(self, release)
            else:
                tooltip(tr.addons_no_updates_available(), parent=self)

        get_latest_release_op(
            parent=self, include_prerelease=version.is_prerelease, on_success=on_success
        ).with_progress().run_in_background()

    def onNoteTypes(self) -> None:
        import aqt.models

        aqt.models.Models(self, self, fromMain=True)

    def onAbout(self) -> None:
        aqt.dialogs.open("About", self)

    def onDonate(self) -> None:
        openLink(aqt.appDonate)

    def onDocumentation(self) -> None:
        openHelp(HelpPage.INDEX)

    # legacy

    def onDeckConf(self, deck: DeckDict | None = None) -> None:
        pass

    # Importing & exporting
    ##########################################################################

    def handleImport(self, path: str) -> None:
        "Importing triggered via file double-click, or dragging file onto Anki icon."
        from aqt.import_export.importing import import_file

        if not os.path.exists(path):
            # there were instances in the distant past where the received filename was not
            # valid (encoding issues?), so this was added to direct users to try
            # file>import instead.
            showInfo(f"{tr.qt_misc_please_use_fileimport_to_import_this()} ({path})")
            return None

        if not self.pm.legacy_import_export():
            import_file(self, path)
        else:
            import aqt.importing

            aqt.importing.importFile(self, path)

    def onImport(self) -> None:
        "Importing triggered via File>Import."
        import aqt.importing
        from aqt.import_export.importing import prompt_for_file_then_import

        if not self.pm.legacy_import_export():
            prompt_for_file_then_import(self)
        else:
            aqt.importing.onImport(self)

    def onExport(self, did: DeckId | None = None) -> None:
        import aqt.exporting
        from aqt.import_export.exporting import ExportDialog

        if not self.pm.legacy_import_export():
            ExportDialog(self, did=did)
        else:
            aqt.exporting.ExportDialog(self, did=did)

    # Installing add-ons from CLI / mimetype handler
    ##########################################################################

    def installAddon(self, path: str, startup: bool = False) -> None:
        from aqt.addons import installAddonPackages

        installAddonPackages(
            self.addonManager,
            [path],
            warn=True,
            advise_restart=not startup,
            strictly_modal=startup,
            parent=None if startup else self,
            force_enable=True,
        )

    # Cramming
    ##########################################################################

    def onCram(self) -> None:
        aqt.dialogs.open("FilteredDeckConfigDialog", self)

    # Menu, title bar & status
    ##########################################################################

    def setupMenus(self) -> None:
        m = self.form

        # File
        qconnect(
            m.actionSwitchProfile.triggered, self.unloadProfileAndShowProfileManager
        )
        qconnect(m.actionImport.triggered, self.onImport)
        qconnect(m.actionExport.triggered, self.onExport)
        qconnect(m.action_create_backup.triggered, self.on_create_backup_now)
        qconnect(m.action_open_backup.triggered, self.onOpenBackup)
        qconnect(m.actionExit.triggered, self.close)

        # Help
        qconnect(m.actionDocumentation.triggered, self.onDocumentation)
        qconnect(m.actionDonate.triggered, self.onDonate)
        qconnect(m.actionAbout.triggered, self.onAbout)
        m.actionAbout.setText(tr.qt_accel_about_mac())

        # Edit
        qconnect(m.actionUndo.triggered, self.undo)
        qconnect(m.actionRedo.triggered, self.redo)

        # Tools
        qconnect(m.actionFullDatabaseCheck.triggered, self.onCheckDB)
        qconnect(m.actionCheckMediaDatabase.triggered, self.on_check_media_db)
        qconnect(m.actionStudyDeck.triggered, self.onStudyDeck)
        qconnect(m.actionCreateFiltered.triggered, self.onCram)
        qconnect(m.actionEmptyCards.triggered, self.onEmptyCards)
        qconnect(m.actionNoteTypes.triggered, self.onNoteTypes)
        qconnect(m.action_check_for_updates.triggered, self.on_check_for_updates)
        qconnect(m.actionPreferences.triggered, self.onPrefs)

        # View
        qconnect(
            m.actionZoomIn.triggered,
            lambda: self.web.setZoomFactor(self.web.zoomFactor() + 0.1),
        )
        qconnect(
            m.actionZoomOut.triggered,
            lambda: self.web.setZoomFactor(self.web.zoomFactor() - 0.1),
        )
        qconnect(m.actionResetZoom.triggered, lambda: self.web.setZoomFactor(1))
        # app-wide shortcut
        qconnect(m.actionFullScreen.triggered, self.on_toggle_full_screen)
        m.actionFullScreen.setShortcut(
            QKeySequence("F11") if is_lin else QKeySequence.StandardKey.FullScreen
        )
        m.actionFullScreen.setShortcutContext(Qt.ShortcutContext.ApplicationShortcut)

        # Ankountant
        self._setup_ankountant_menu()

    def _setup_ankountant_menu(self) -> None:
        """Add the Ankountant menu with entry points to its feature screens.

        Built programmatically (rather than in the .ui form) so it does not
        depend on regenerated form attributes. Each action opens the Ankountant
        shell as a workspace tab (see aqt.workspace.Workspace.open_ankountant)."""
        # Attach via the same form.menubar.addMenu idiom the .ui menus use.
        # (Creating a QMenu manually and insertMenu()-ing it before the Help
        # menu fails to appear in macOS's native menu bar, since Help is an
        # OS-managed special menu.)
        menu = self.form.menubar.addMenu("&Ankountant")
        assert menu is not None

        home = menu.addAction("Home")
        qconnect(
            home.triggered,
            lambda: self.workspace.open_ankountant("home"),
        )
        workspace = menu.addAction("Study Workspace")
        qconnect(
            workspace.triggered,
            lambda: self.workspace.open_ankountant("workspace"),
        )
        menu.addSeparator()

        dashboard = menu.addAction("Readiness Dashboard")
        qconnect(
            dashboard.triggered,
            lambda: self.workspace.open_ankountant("dashboard"),
        )
        confusion = menu.addAction("Confusion-Set Review")
        qconnect(
            confusion.triggered,
            lambda: self.workspace.open_ankountant("confusion"),
        )
        tbs = menu.addAction("TBS Practice")
        qconnect(
            tbs.triggered,
            lambda: self.workspace.open_ankountant("tbs"),
        )
        stats = menu.addAction("Statistics")
        qconnect(
            stats.triggered,
            lambda: self.workspace.open_ankountant("stats"),
        )

        menu.addSeparator()
        # Three demo phases, each loading user data tuned so the Home
        # phase-aware CTA lands in that phase (see load_ankountant_phase).
        foundation = menu.addAction("Load demo \u00b7 Foundation (beginner)")
        qconnect(
            foundation.triggered,
            lambda: self.load_ankountant_phase("foundation"),
        )
        discrimination = menu.addAction("Load demo \u00b7 Discrimination (exam far)")
        qconnect(
            discrimination.triggered,
            lambda: self.load_ankountant_phase("discrimination"),
        )
        consolidation = menu.addAction("Load demo \u00b7 Consolidation (exam soon)")
        qconnect(
            consolidation.triggered,
            lambda: self.load_ankountant_phase("consolidation"),
        )

        menu.addSeparator()
        # One-click loader for the full generated CPA bank: the AI/template deck
        # plus the online-sourced (AnkiWeb) community deck. Also exposed as a top
        # toolbar link ("CPA Bank") via setupHooks.
        cpa_bank = menu.addAction("Load All CPA Cards (AI + Online)")
        qconnect(cpa_bank.triggered, self.load_cpa_bank)
        cpa_stress = menu.addAction("Load 50k Stress Test (duplicates)")
        qconnect(cpa_stress.triggered, self.load_cpa_stress_bank)

    def load_ankountant_phase(self, phase: str) -> None:
        """Seed the CPA demo profile tuned so the Home phase-aware CTA lands in a
        specific phase, for demoing/QA of the dynamic study recommendation:

        - "foundation": content only, no history and no exam date, so every topic
          reads memory-insufficient (no memory base) and Home recommends "Build
          foundation" (blocked recall).
        - "discrimination": full history + the seed's own ~45-day exam date (far
          from the exam), so Home recommends the "Discrimination drill" (confusion
          set) — the core practice primitive.
        - "consolidation": full history + an exam date 7 days out (inside the
          final-stretch window), so Home recommends "Consolidate" (recall to peak).

        Each calls the LoadFarSeed backend RPC (F016), then sets/clears each
        visible section's exam date, and refreshes. Best on a fresh/throwaway
        profile."""
        require_ankountant_demo_phase(phase)
        if self.col is None:
            return
        if not askUser(
            f"Load the CPA demo profile in its '{phase}' state? This adds sample"
            " CPA starter content, category attempts, and phase-appropriate study"
            " history so the Home screen's recommended action reflects that phase."
            " Best on a fresh/throwaway profile.",
            parent=self,
        ):
            return

        import datetime

        attempts = 0
        if phase == "foundation":
            resp = self.col._backend.load_far_seed(section="FAR", with_history=False)
            attempts = self._seed_cpa_bank_attempt_history(self.col)
            for section in CPA_BANK_SECTIONS:
                self.col._backend.set_exam_date(section=section, date="")
        elif phase == "consolidation":
            resp = self.col._backend.load_far_seed(section="FAR", with_history=True)
            iso = (datetime.date.today() + datetime.timedelta(days=7)).isoformat()
            for section in CPA_BANK_SECTIONS:
                self.col._backend.set_exam_date(section=section, date=iso)
        else:
            resp = self.col._backend.load_far_seed(section="FAR", with_history=True)
            self._set_cpa_bank_exam_dates(self.col)

        self.reset()
        history = "no history" if phase == "foundation" else "sample history"
        attempt_text = (
            f" Seeded {attempts:,} starter category attempts." if attempts else ""
        )
        tooltip(
            f"Loaded CPA demo \u00b7 {phase}: "
            f"{resp.study_recall_cards} recall cards, "
            f"{resp.confusion_sets} confusion sets, "
            f"{resp.sealed_items} sealed items ({history})."
            f"{attempt_text}"
            " Open the Ankountant Home to see the recommended action.",
            parent=self,
        )

    # --- Ankountant: one-click CPA bank loader ------------------------------
    def _cpa_bank_dir(self) -> Path | None:
        """Resolve the directory holding the generated packs.

        Order: ``ANKOUNTANT_CPA_BANK_DIR`` env override, then the dev cardgen
        output (``<repo>/tools/cardgen/out/tmpl4``). Returns the first that holds
        at least one pack, else ``None``."""
        candidates: list[Path] = []
        env = os.environ.get("ANKOUNTANT_CPA_BANK_DIR")
        if env:
            candidates.append(Path(env))
        # qt/aqt/main.py -> qt/aqt -> qt -> <repo root>
        candidates.append(
            Path(__file__).resolve().parents[2] / "tools" / "cardgen" / "out" / "tmpl4"
        )
        for d in candidates:
            if any(
                (d / n).exists()
                for n in ("cpa_bank.apkg", "online_bank.apkg", "stress_bank.apkg")
            ):
                return d
            if any(d.glob("stress_bank_part*.apkg")):
                return d
        return None

    def _stress_bank_packs(self, pack_dir: Path) -> list[Path]:
        shards = sorted(pack_dir.glob("stress_bank_part*.apkg"))
        if shards:
            return shards
        pack = pack_dir / "stress_bank.apkg"
        return [pack] if pack.exists() else []

    def _cpa_bank_patch_updates(
        self,
        pack_dir: Path,
    ) -> dict[str, dict[str, dict[str, Any]]]:
        patch_path = pack_dir / "confusable_patch.json"
        if not patch_path.exists():
            return {}
        return ankountant_confusable_patch_updates(
            json.loads(patch_path.read_text(encoding="utf-8"))
        )

    def load_cpa_bank(self) -> None:
        """Import the full generated CPA bank in one click: the AI/template deck
        (``cpa_bank.apkg``) and the online-sourced community deck
        (``online_bank.apkg``), seed the shared CPA demo profile, then apply the
        follow-ups an ``.apkg`` can't carry."""
        if self.col is None:
            return

        from anki.collection import ImportAnkiPackageOptions, ImportAnkiPackageRequest
        from aqt.operations import CollectionOp

        pack_dir = self._cpa_bank_dir()
        if pack_dir is None:
            showInfo(
                "Couldn't find the generated CPA bank. Expected cpa_bank.apkg /"
                " online_bank.apkg under tools/cardgen/out/tmpl4/ (or set"
                " ANKOUNTANT_CPA_BANK_DIR).",
                parent=self,
            )
            return
        packs = [
            p
            for p in (pack_dir / "cpa_bank.apkg", pack_dir / "online_bank.apkg")
            if p.exists()
        ]
        if not packs:
            showInfo("No .apkg packs found to import.", parent=self)
            return
        try:
            patch_updates = self._cpa_bank_patch_updates(pack_dir)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            showWarning(f"Invalid confusable_patch.json: {exc}", parent=self)
            return
        if not askUser(
            f"Load {len(packs)} generated CPA pack(s) into this collection?\n\n"
            f"From: {pack_dir}\n\n"
            "This imports the AI/template cards and the online-sourced community"
            " cards, loads the CPA demo profile, suspends sealed practice cards,"
            " and seeds realistic user history for FAR, AUD, REG, TCP, and ISC."
            " Best on a fresh/throwaway profile.",
            parent=self,
        ):
            return

        seeded = {"cards": 0, "attempts": 0}

        def op(col: Collection) -> Any:
            col._backend.load_far_seed(section="FAR", with_history=True)
            changes: Any = None
            for pack in packs:
                req = ImportAnkiPackageRequest(
                    package_path=str(pack),
                    options=ImportAnkiPackageOptions(
                        merge_notetypes=True,
                        with_scheduling=False,
                        with_deck_configs=False,
                    ),
                )
                changes = col.import_anki_package(req)
            # (a) Sealed cards must be suspended (the .apkg can't carry it).
            sealed = col.find_cards("deck:Ankountant::Sealed::*")
            if sealed:
                col.sched.suspend_cards(sealed)
            self._apply_cpa_bank_patch_updates(col, patch_updates)
            self._prepare_cpa_bank_sections(col)
            seeded["cards"] = self._seed_cpa_bank_review_history(col)
            seeded["attempts"] = self._seed_cpa_bank_attempt_history(col)
            self._set_cpa_bank_exam_dates(col)
            return changes

        def on_success(_out: Any) -> None:
            tooltip(
                f"Loaded the CPA bank: imported {len(packs)} pack(s);"
                f" seeded {seeded['cards']:,} reviewed cards and"
                f" {seeded['attempts']:,} sealed attempts.",
                parent=self,
            )

        CollectionOp(parent=self, op=op).success(on_success).run_in_background()

    def _apply_cpa_bank_patch_updates(
        self,
        col: Collection,
        patch_updates: dict[str, dict[str, dict[str, Any]]],
    ) -> None:
        for key, entries in patch_updates.items():
            current = col.get_config(key, default={}) or {}
            if not isinstance(current, dict):
                raise ValueError(f"{key} config must contain an object")
            merged = dict(current)
            merged.update(entries)
            col.set_config(key, merged)

    def _prepare_cpa_bank_sections(self, col: Collection) -> None:
        self._tag_cpa_bank_study_cards(col)
        deck_names = {int(deck.id): deck.name for deck in col.decks.all_names_and_ids()}
        confusable_by_section = self._cpa_bank_confusable_by_section(col)
        notes_to_update = []
        for section in CPA_BANK_SECTIONS:
            query = f'"note:Ankountant TBS" deck:Ankountant::Sealed::{section}::*'
            for nid in col.find_notes(query):
                note = self._prepare_cpa_bank_sealed_note(
                    col,
                    nid,
                    deck_names,
                    confusable_by_section,
                )
                if note is not None:
                    notes_to_update.append(note)

        if notes_to_update:
            col.update_notes(notes_to_update, skip_undo_entry=True)
        for section, confusable in confusable_by_section.items():
            col.set_config(f"ankountant.confusable.{section}", confusable)

    def _prepare_stress_bank_sections(self, col: Collection) -> None:
        deck_names = {int(deck.id): deck.name for deck in col.decks.all_names_and_ids()}
        confusable_by_section = self._cpa_bank_confusable_by_section(col)
        notes_to_update = []
        for section in CPA_BANK_SECTIONS:
            query = (
                f'"note:Ankountant TBS" deck:Ankountant::Stress::Sealed::{section}::*'
            )
            for nid in col.find_notes(query):
                note = self._prepare_stress_bank_sealed_note(
                    col,
                    NoteId(nid),
                    deck_names,
                    confusable_by_section,
                )
                if note is not None:
                    notes_to_update.append(note)

        if notes_to_update:
            col.update_notes(notes_to_update, skip_undo_entry=True)
        for section, confusable in confusable_by_section.items():
            col.set_config(f"ankountant.confusable.{section}", confusable)

    def _cpa_bank_confusable_by_section(
        self,
        col: Collection,
    ) -> dict[str, dict[str, dict[str, Any]]]:
        out: dict[str, dict[str, dict[str, Any]]] = {}
        for section in CPA_BANK_SECTIONS:
            key = f"ankountant.confusable.{section}"
            current = col.get_config(key, default={}) or {}
            if not isinstance(current, dict):
                raise ValueError(f"{key} config must contain an object")
            out[section] = self._normalized_cpa_bank_confusable_map(key, current)
        return out

    def _normalized_cpa_bank_confusable_map(
        self,
        key: str,
        current: dict[Any, Any],
    ) -> dict[str, dict[str, Any]]:
        confusable: dict[str, dict[str, Any]] = {}
        for set_id, entry in current.items():
            if not isinstance(set_id, str) or not isinstance(entry, dict):
                raise ValueError(f"{key} contains an invalid confusable entry")
            tags = entry.get("tags", [])
            treatments = entry.get("treatments", [])
            if not isinstance(tags, list) or not isinstance(treatments, list):
                raise ValueError(f"{key}.{set_id} must contain tags and treatments")
            confusable[set_id] = ankountant_category_metadata(
                f"{key}.{set_id}",
                tags,
                treatments,
            )
        return confusable

    def _prepare_cpa_bank_sealed_note(
        self,
        col: Collection,
        nid: NoteId,
        deck_names: dict[int, str],
        confusable_by_section: dict[str, dict[str, dict[str, Any]]],
    ) -> Note | None:
        deck_name = self._cpa_bank_note_deck_name(col, nid, deck_names)
        parts = ankountant_sealed_deck_parts(deck_name)
        if parts is None:
            return None
        section, set_id = parts
        note = col.get_note(nid)
        if len(note.fields) <= 4:
            raise ValueError(f"sealed TBS note is missing schema_tag: {nid}")
        schema_tag, field_changed = self._cpa_bank_schema_tag_for_note(
            note,
            section,
            set_id,
            confusable_by_section[section],
        )
        tags_changed = self._ensure_cpa_bank_note_tags(note, section, schema_tag)
        self._ensure_cpa_bank_confusable_set(
            confusable_by_section[section],
            section,
            set_id,
            schema_tag,
        )
        return note if field_changed or tags_changed else None

    def _prepare_stress_bank_sealed_note(
        self,
        col: Collection,
        nid: NoteId,
        deck_names: dict[int, str],
        confusable_by_section: dict[str, dict[str, dict[str, Any]]],
    ) -> Note | None:
        deck_name = self._cpa_bank_note_deck_name(col, nid, deck_names)
        parts = ankountant_stress_sealed_deck_parts(deck_name)
        if parts is None:
            return None
        section, set_id = parts
        note = col.get_note(nid)
        if len(note.fields) <= 4:
            raise ValueError(f"stress sealed TBS note is missing schema_tag: {nid}")
        tbs_type_changed = self._normalize_stress_tbs_type(note)
        try:
            schema_tag, field_changed = self._cpa_bank_schema_tag_for_note(
                note,
                section,
                set_id,
                confusable_by_section[section],
            )
        except ValueError:
            if self._stress_note_has_category_hint(note):
                raise
            return note if tbs_type_changed else None
        tags_changed = self._ensure_cpa_bank_note_tags(note, section, schema_tag)
        self._ensure_cpa_bank_confusable_set(
            confusable_by_section[section],
            section,
            set_id,
            schema_tag,
        )
        return note if tbs_type_changed or field_changed or tags_changed else None

    def _normalize_stress_tbs_type(self, note: Note) -> bool:
        tbs_type = ankountant_tbs_type(note.fields[0])
        if tbs_type == note.fields[0]:
            return False
        note.fields[0] = tbs_type
        return True

    def _stress_note_has_category_hint(self, note: Note) -> bool:
        return bool(note.fields[4].strip()) or any(
            tag.startswith("ds::") for tag in note.tags
        )

    def _cpa_bank_note_deck_name(
        self,
        col: Collection,
        nid: NoteId,
        deck_names: dict[int, str],
    ) -> str:
        did = col.db.scalar(
            "SELECT did FROM cards WHERE nid = ? ORDER BY ord LIMIT 1",
            int(nid),
        )
        if did is None:
            raise ValueError(f"sealed note has no card: {nid}")
        deck_name = deck_names.get(int(did))
        if deck_name is None:
            raise ValueError(f"sealed note has unknown deck id: {did}")
        return deck_name

    def _cpa_bank_schema_tag_for_note(
        self,
        note: Note,
        section: str,
        set_id: str,
        confusable: dict[str, dict[str, Any]],
    ) -> tuple[str, bool]:
        known = ankountant_bank_category_entry(section, set_id, confusable)
        schema_tag = note.fields[4].strip()
        if schema_tag:
            if schema_tag not in known["tags"]:
                raise ValueError(
                    f"sealed note {section}::{set_id} has unknown schema_tag: {schema_tag}"
                )
            return schema_tag, False
        schema_tag = known["tags"][0]
        note.fields[4] = schema_tag
        return schema_tag, True

    def _ensure_cpa_bank_note_tags(
        self,
        note: Note,
        section: str,
        schema_tag: str,
    ) -> bool:
        changed = False
        for tag in (f"sec::{section}", schema_tag):
            if tag and tag not in note.tags:
                note.tags.append(tag)
                changed = True
        return changed

    def _ensure_cpa_bank_confusable_set(
        self,
        confusable: dict[str, dict[str, Any]],
        section: str,
        set_id: str,
        schema_tag: str,
    ) -> None:
        known = ankountant_bank_category_entry(section, set_id, confusable)
        if schema_tag and schema_tag not in known["tags"]:
            raise ValueError(
                f"sealed note {section}::{set_id} has unknown schema_tag: {schema_tag}"
            )
        if set_id not in confusable:
            confusable[set_id] = known
            return
        existing = ankountant_category_metadata(
            f"CPA bank category {section}::{set_id}",
            confusable[set_id]["tags"],
            confusable[set_id]["treatments"],
        )
        if schema_tag and schema_tag not in existing["tags"]:
            raise ValueError(
                f"sealed note {section}::{set_id} has unknown schema_tag: {schema_tag}"
            )

    def _tag_cpa_bank_study_cards(self, col: Collection) -> None:
        notes_to_update = []
        for section, tags in CPA_BANK_MEMORY_TAGS.items():
            if not tags:
                raise ValueError(f"{section} has no CPA bank memory tags")
            nids: set[int] = set()
            for kind in ("Study", "Community"):
                query = f"deck:Ankountant::{kind}::{section}::*"
                nids.update(int(nid) for nid in col.find_notes(query))
            for index, nid in enumerate(sorted(nids)):
                note = col.get_note(NoteId(nid))
                if any(tag.startswith("ds::") for tag in note.tags):
                    continue
                tag = tags[index % len(tags)]
                if tag not in note.tags:
                    note.tags.append(tag)
                    notes_to_update.append(note)
        if notes_to_update:
            col.update_notes(notes_to_update, skip_undo_entry=True)

    def _seed_cpa_bank_review_history(self, col: Collection) -> int:
        import time

        sorted_cids = self._cpa_bank_review_card_ids(col)
        if not sorted_cids:
            return 0
        meta = self._cpa_bank_review_meta(col, sorted_cids)
        now_ms = int(time.time() * 1000)
        seeded_cids = self._seed_cpa_bank_review_cards(
            col, sorted_cids, meta, now_ms // 1000
        )
        if seeded_cids:
            self._insert_cpa_bank_review_revlogs(col, seeded_cids, meta, now_ms)
        col.set_config("ankountant.latency.rote", 4200)
        return len(seeded_cids)

    def _cpa_bank_review_card_ids(self, col: Collection) -> list[int]:
        cids: set[int] = set()
        for section in CPA_BANK_SECTIONS:
            for kind in ("Study", "Community"):
                query = f"deck:Ankountant::{kind}::{section}::*"
                cids.update(int(cid) for cid in col.find_cards(query))
        return sorted(cids)

    def _cpa_bank_review_meta(
        self,
        col: Collection,
        sorted_cids: list[int],
    ) -> dict[int, tuple[int, int, int, int, str]]:
        deck_names = {int(deck.id): deck.name for deck in col.decks.all_names_and_ids()}
        meta: dict[int, tuple[int, int, int, int, str]] = {}
        sql_query_batch_size = 900
        for start in range(0, len(sorted_cids), sql_query_batch_size):
            self._add_cpa_bank_review_meta_batch(
                col,
                sorted_cids[start : start + sql_query_batch_size],
                deck_names,
                meta,
            )
        return meta

    def _add_cpa_bank_review_meta_batch(
        self,
        col: Collection,
        chunk: list[int],
        deck_names: dict[int, str],
        meta: dict[int, tuple[int, int, int, int, str]],
    ) -> None:
        placeholders = ",".join("?" for _ in chunk)
        for cid, nid, did, ordv, reps in col.db.all(
            f"SELECT id, nid, did, ord, reps FROM cards WHERE id IN ({placeholders})",
            *chunk,
        ):
            deck_name = deck_names.get(int(did))
            if deck_name is None:
                raise ValueError(f"CPA bank card has unknown deck id: {did}")
            section = ankountant_bank_study_section(deck_name)
            if section is not None:
                meta[int(cid)] = (int(nid), int(did), int(ordv), int(reps), section)

    def _seed_cpa_bank_review_cards(
        self,
        col: Collection,
        sorted_cids: list[int],
        meta: dict[int, tuple[int, int, int, int, str]],
        now_s: int,
    ) -> list[int]:
        from anki import cards_pb2
        from anki.cards import Card

        card_update_batch_size = 1000
        today = col.sched.today
        batch: list[Card] = []
        seeded_cids: list[int] = []
        for i, cid in enumerate(sorted_cids):
            item = meta.get(cid)
            if item is None:
                continue
            nid, did, ordv, reps, section = item
            if reps > 0:
                continue
            interval = 7 + ((i * 11 + len(section)) % 84)
            offset = (i % 45) - 14
            batch.append(
                Card(
                    col,
                    backend_card=cards_pb2.Card(
                        id=cid,
                        note_id=nid,
                        deck_id=did,
                        template_idx=ordv,
                        ctype=2,
                        queue=2,
                        due=today + offset,
                        interval=interval,
                        ease_factor=2450 + (i % 5) * 20,
                        reps=3 + (i % 8),
                        lapses=1 if (i + len(section)) % 11 == 0 else 0,
                        remaining_steps=0,
                        memory_state=cards_pb2.FsrsMemoryState(
                            stability=float(interval) * 1.35 + 4.0,
                            difficulty=3.8 + float((i + len(section)) % 6) * 0.7,
                        ),
                        desired_retention=0.9,
                        last_review_time_secs=now_s - (1 + i % 28) * 86_400,
                    ),
                )
            )
            seeded_cids.append(cid)
            if len(batch) >= card_update_batch_size:
                col.update_cards(batch, skip_undo_entry=True)
                batch = []
        if batch:
            col.update_cards(batch, skip_undo_entry=True)
        return seeded_cids

    def _insert_cpa_bank_review_revlogs(
        self,
        col: Collection,
        seeded_cids: list[int],
        meta: dict[int, tuple[int, int, int, int, str]],
        now_ms: int,
    ) -> None:
        revlog_insert_batch_size = 5000
        revlog_sql = (
            "INSERT OR IGNORE INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )

        def insert_revlog() -> None:
            rows: list[tuple] = []
            seq = 0

            def flush() -> None:
                nonlocal rows
                if rows:
                    col.db.executemany(revlog_sql, rows)
                    rows = []

            for i, cid in enumerate(seeded_cids):
                section = meta[cid][4]
                interval = 7 + ((i * 11 + len(section)) % 84)
                reps = 3 + (i + len(section)) % 4
                last_ivl = 0
                for j in range(reps):
                    days_ago = 1 + ((i * 5 + j * 7 + len(section)) % 28)
                    rid = now_ms - days_ago * 86_400_000 + seq
                    seq += 1
                    correct = ankountant_review_is_correct(section, i, j)
                    ivl = max(1, int(interval * (j + 1) / reps))
                    rows.append(
                        (
                            rid,
                            cid,
                            -1,
                            3 if correct else 1,
                            ivl,
                            last_ivl,
                            2450,
                            2500 + (seq * 379) % 7000,
                            1,
                        )
                    )
                    last_ivl = ivl
                    if len(rows) >= revlog_insert_batch_size:
                        flush()
            flush()

        col.db.transact(insert_revlog)

    def _seed_cpa_bank_attempt_history(self, col: Collection) -> int:
        return self._seed_category_attempt_history(col, "Ankountant::Sealed")

    def _seed_stress_attempt_history(self, col: Collection) -> int:
        return self._seed_category_attempt_notes(
            col,
            self._stress_attempt_category_notes(col),
        )

    def _seed_category_attempt_history(
        self,
        col: Collection,
        deck_prefix: str,
    ) -> int:
        category_notes: dict[tuple[str, str], list[int]] = {}
        for section in ("AUD", "REG", "TCP", "ISC"):
            for set_id in CPA_BANK_CATEGORY_SETS[section]:
                query = f'"note:Ankountant TBS" deck:{deck_prefix}::{section}::{set_id}'
                nids = sorted(int(nid) for nid in col.find_notes(query))
                if not nids:
                    raise ValueError(f"{deck_prefix} is missing {section}::{set_id}")
                category_notes[(section, set_id)] = nids
        return self._seed_category_attempt_notes(col, category_notes)

    def _stress_attempt_category_notes(
        self,
        col: Collection,
    ) -> dict[tuple[str, str], list[int]]:
        deck_names = {int(deck.id): deck.name for deck in col.decks.all_names_and_ids()}
        confusable_by_section = self._cpa_bank_confusable_by_section(col)
        category_notes: dict[tuple[str, str], list[int]] = {}
        for section in ("AUD", "REG", "TCP", "ISC"):
            query = (
                f'"note:Ankountant TBS" deck:Ankountant::Stress::Sealed::{section}::*'
            )
            for nid in col.find_notes(query):
                note_id = NoteId(nid)
                note = col.get_note(note_id)
                if len(note.fields) <= 4:
                    raise ValueError(
                        f"stress sealed TBS note is missing schema_tag: {nid}"
                    )
                deck_name = self._cpa_bank_note_deck_name(col, note_id, deck_names)
                parts = ankountant_stress_sealed_deck_parts(deck_name)
                if parts is None:
                    continue
                note_section, set_id = parts
                if not self._cpa_bank_note_resolves_category(
                    note,
                    note_section,
                    set_id,
                    confusable_by_section[note_section],
                ):
                    continue
                category_notes.setdefault((note_section, set_id), []).append(int(nid))
        return category_notes

    def _cpa_bank_note_resolves_category(
        self,
        note: Note,
        section: str,
        set_id: str,
        confusable: dict[str, dict[str, Any]],
    ) -> bool:
        try:
            known = ankountant_bank_category_entry(section, set_id, confusable)
        except ValueError:
            return False
        schema_tag = note.fields[4].strip()
        return schema_tag in known["tags"] or any(
            tag in known["tags"] for tag in note.tags
        )

    def _seed_category_attempt_notes(
        self,
        col: Collection,
        category_notes: dict[tuple[str, str], list[int]],
    ) -> int:
        seeded = 0
        for (section, _set_id), nids in sorted(category_notes.items()):
            if not nids:
                raise ValueError(f"{section} category has no sealed notes")
            attempts = max(6, min(24, len(nids) * 3))
            for i in range(attempts):
                nid = nids[i % len(nids)]
                note = col.get_note(NoteId(nid))
                correct = ankountant_review_is_correct(section, seeded + i, i % 4)
                mode, submission_json = ankountant_submission_for_tbs_fields(
                    note.fields,
                    correct,
                )
                col._backend.submit_performance_attempt(
                    item_note_id=nid,
                    mode=mode,
                    submission_json=submission_json,
                    confidence=self._cpa_bank_attempt_confidence(
                        section,
                        correct,
                        seeded + i,
                    ),
                    latency_ms=self._cpa_bank_attempt_latency(
                        mode, section, seeded + i
                    ),
                )
                seeded += 1
        return seeded

    def _cpa_bank_attempt_confidence(
        self,
        section: str,
        correct: bool,
        index: int,
    ) -> str:
        marker = (index * 7 + len(section)) % 10
        if correct:
            return "unsure" if marker < 2 else "confident"
        return "confident" if marker == 0 else "guess"

    def _cpa_bank_attempt_latency(self, mode: str, section: str, index: int) -> int:
        base = {
            "confusion": 2_600,
            "research": 48_000,
            "tbs": 38_000,
            "doc_review": 44_000,
        }.get(mode)
        if base is None:
            raise ValueError(f"Unsupported performance attempt mode: {mode}")
        return base + ((index * 1_379 + len(section) * 311) % base)

    def _set_cpa_bank_exam_dates(self, col: Collection) -> None:
        today = datetime.date.today()
        for section, offset in CPA_BANK_EXAM_OFFSETS_DAYS.items():
            col._backend.set_exam_date(
                section=section,
                date=(today + datetime.timedelta(days=offset)).isoformat(),
            )

    def load_cpa_stress_bank(self) -> None:
        """Scale test: import the duplicated >50k-card stress pack (``stress_bank.apkg``).

        These are identical copies of the finalized bank with unique GUIDs, filed
        under ``Ankountant::Stress::`` and tagged ``stress`` — purely to check the
        app can handle tens of thousands of cards. Use a fresh/throwaway profile."""
        if self.col is None:
            return
        from anki.collection import ImportAnkiPackageOptions, ImportAnkiPackageRequest
        from aqt.operations import CollectionOp

        pack_dir = self._cpa_bank_dir()
        packs = self._stress_bank_packs(pack_dir) if pack_dir else []
        if not packs:
            showInfo(
                "Couldn't find stress_bank.apkg or stress_bank_part*.apkg. Generate it with"
                " just cardgen-stress (or set ANKOUNTANT_CPA_BANK_DIR).",
                parent=self,
            )
            return
        try:
            patch_updates = self._cpa_bank_patch_updates(pack_dir)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            showWarning(f"Invalid confusable_patch.json: {exc}", parent=self)
            return
        if not askUser(
            f"Import the ~50k-card STRESS TEST deck from {len(packs)} pack(s) and seed a synthetic review"
            " history across ALL of them plus category attempts for AUD, REG, TCP,"
            " and ISC, so review-driven features work at scale? This adds tens of"
            " thousands of duplicate cards under Ankountant::Stress:: (tagged"
            " 'stress') and may take a little while. Strongly recommend a"
            " fresh/throwaway profile.",
            parent=self,
        ):
            return

        seeded = {"n": 0, "attempts": 0}

        def op(col: Collection) -> Any:
            col._backend.load_far_seed(section="FAR", with_history=True)
            self._apply_cpa_bank_patch_updates(col, patch_updates)
            changes = None
            for pack in packs:
                req = ImportAnkiPackageRequest(
                    package_path=str(pack),
                    options=ImportAnkiPackageOptions(
                        merge_notetypes=True,
                        with_scheduling=False,
                        with_deck_configs=False,
                    ),
                )
                changes = col.import_anki_package(req)
            self._prepare_stress_bank_sections(col)
            seeded["n"] = self._seed_stress_history(col)
            seeded["attempts"] = self._seed_stress_attempt_history(col)
            self._set_cpa_bank_exam_dates(col)
            return changes

        def on_success(_out: Any) -> None:
            tooltip(
                f"Loaded the stress-test deck and seeded review history for"
                f" {seeded['n']:,} cards plus {seeded['attempts']:,} category attempts.",
                parent=self,
            )

        CollectionOp(parent=self, op=op).success(on_success).run_in_background()

    def _seed_stress_history(self, col: Collection) -> int:
        """Synthesize a plausible review history for every stress-test card so
        review-driven features work at scale: each card is set to a matured review
        state with an FSRS memory state, and several revlog rows are spread over
        the trailing ~180 days (for stats / heatmap / true-retention). Work is
        chunked to avoid huge Python<->Rust JSON payloads at 50k+ cards. Returns
        the number of cards seeded."""
        import time

        from anki import cards_pb2
        from anki.cards import Card

        cids = list(col.find_cards("deck:Ankountant::Stress::*")) or list(
            col.find_cards("tag:stress")
        )
        if not cids:
            return 0
        today = col.sched.today
        now_ms = int(time.time() * 1000)
        now_s = now_ms // 1000

        card_update_batch_size = 1000
        sql_query_batch_size = 900
        revlog_insert_batch_size = 5000

        # nid/did/ord for the stress cards, read in chunks. Querying every card in
        # the collection and filtering in Python is expensive in large profiles.
        meta: dict[int, tuple[int, int, int]] = {}
        for start in range(0, len(cids), sql_query_batch_size):
            chunk = cids[start : start + sql_query_batch_size]
            placeholders = ",".join("?" for _ in chunk)
            for cid, nid, did, ordv in col.db.all(
                f"SELECT id, nid, did, ord FROM cards WHERE id IN ({placeholders})",
                *chunk,
            ):
                meta[cid] = (nid, did, ordv)

        # 1) Matured review state + FSRS memory, batched.
        seeded = 0
        batch: list[Card] = []
        for i, cid in enumerate(cids):
            m = meta.get(cid)
            if m is None:
                continue
            nid, did, ordv = m
            interval = 1 + (i * 7) % 90
            offset = (
                i % 60
            ) - 20  # spread overdue..future so the review queue populates
            batch.append(
                Card(
                    col,
                    backend_card=cards_pb2.Card(
                        id=cid,
                        note_id=nid,
                        deck_id=did,
                        template_idx=ordv,
                        ctype=2,  # review
                        queue=2,  # review
                        due=today + offset,
                        interval=interval,
                        ease_factor=2500,
                        reps=3 + i % 18,
                        lapses=1 if i % 6 == 0 else 0,
                        remaining_steps=0,
                        memory_state=cards_pb2.FsrsMemoryState(
                            stability=float(interval) * 1.5 + 5.0,
                            difficulty=3.0 + float(i % 7),
                        ),
                        desired_retention=0.9,
                        last_review_time_secs=now_s
                        - max(0, interval - offset) * 86_400,
                    ),
                )
            )
            seeded += 1
            if len(batch) >= card_update_batch_size:
                col.update_cards(batch, skip_undo_entry=True)
                batch = []
        if batch:
            col.update_cards(batch, skip_undo_entry=True)

        # 2) Revlog rows spread across the trailing window. ``seq`` keeps ids unique
        # while staying within the intended day (seq << ms/day), and OR IGNORE
        # tolerates the astronomically-rare clash with a real row.
        revlog_sql = (
            "INSERT OR IGNORE INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )

        def insert_revlog() -> None:
            rows: list[tuple] = []
            seq = 0

            def flush() -> None:
                nonlocal rows
                if rows:
                    col.db.executemany(revlog_sql, rows)
                    rows = []

            for i, cid in enumerate(cids):
                interval = 1 + (i * 7) % 90
                last_ivl = 0
                for j in range(1 + (i % 4)):
                    days_ago = 1 + ((i * 3 + j * 29) % 179)
                    rid = (now_ms - days_ago * 86_400_000) + seq
                    seq += 1
                    ease = 1 if (i + j) % 9 == 0 else 3
                    ivl = interval if j == (i % 4) else max(1, interval // 2)
                    rows.append(
                        (
                            rid,
                            cid,
                            -1,
                            ease,
                            ivl,
                            last_ivl,
                            2500,
                            2000 + (seq % 8000),
                            1,
                        )
                    )
                    last_ivl = ivl
                    if len(rows) >= revlog_insert_batch_size:
                        flush()
            flush()

        col.db.transact(insert_revlog)

        # Seed the rote-latency EMA so that latency-based feature isn't empty.
        col.set_config("ankountant.latency.rote", 4200)
        return seeded

    def _on_top_toolbar_did_init_links(self, links: list[str], toolbar: Any) -> None:
        """Add visible one-click loader links ('CPA Bank' + '50k Test') to the top toolbar."""
        links.append(
            toolbar.create_link(
                "cpa_bank",
                "CPA Bank",
                self.load_cpa_bank,
                tip="Import the generated CPA bank (AI + online)",
                id="cpa_bank",
            )
        )
        links.append(
            toolbar.create_link(
                "cpa_stress",
                "50k Test",
                self.load_cpa_stress_bank,
                tip="Import the ~50k-card stress-test deck (duplicates)",
                id="cpa_stress",
            )
        )

    def updateTitleBar(self) -> None:
        self.setWindowTitle("Ankountant")

    # View
    ##########################################################################

    def on_toggle_full_screen(self) -> None:
        if disallow_full_screen():
            showWarning(
                tr.actions_fullscreen_unsupported(),
                parent=self,
                help=HelpPage.FULL_SCREEN_ISSUE,
            )
            return
        else:
            window = self.app.activeWindow()
            window.setWindowState(
                window.windowState() ^ Qt.WindowState.WindowFullScreen
            )

        # Hide Menubar on Windows and Linux
        if window.windowState() & Qt.WindowState.WindowFullScreen and not is_mac:
            self.fullscreen = True
            self.hide_menubar()
        else:
            self.fullscreen = False
            self.show_menubar()

        # Update Toolbar states
        self.toolbarWeb.hide_if_allowed()
        self.bottomWeb.hide_if_allowed()

    def hide_menubar(self) -> None:
        self.form.menubar.setFixedHeight(0)

    def show_menubar(self) -> None:
        self.form.menubar.setMaximumSize(QWIDGETSIZE_MAX, QWIDGETSIZE_MAX)
        self.form.menubar.setMinimumSize(0, 0)

    # Ankountant-first chrome
    ##########################################################################

    def set_ankountant_fullscreen(self, on: bool) -> None:
        """Hide (or restore) the classic Qt chrome so the Ankountant SvelteKit
        shell is the whole app: the native menubar, the workspace North tab
        strip, and the classic top toolbar. The bottom bar is left alone since
        it carries the reviewer's answer buttons and the overview Study button.
        Menu QActions keep their shortcuts, so Sync/Preferences/etc. still work
        while the menubar is hidden."""
        self._ankountant_fullscreen = on
        if on:
            self.hide_menubar()
        else:
            self.show_menubar()
        # The toolbar's own hide()/show() only toggle CSS classes, so a real
        # setVisible here isn't fought by the reviewer's auto-hide logic.
        self.toolbarWeb.setVisible(not on)
        if getattr(self, "workspace", None):
            self.workspace.set_chrome_hidden(on)
        self._apply_ankountant_window_style()

    def toggle_ankountant_fullscreen(self) -> None:
        """Escape hatch: flip between the Ankountant shell and the classic
        chrome (deck browser + menubar + tools) for deck management etc."""
        self.set_ankountant_fullscreen(not self._ankountant_fullscreen)
        if getattr(self, "workspace", None):
            if self._ankountant_fullscreen:
                self.workspace.enter_home_shell()
            else:
                self.workspace.raise_home()

    def _apply_ankountant_window_style(self) -> None:
        """Paint the QMainWindow/QDockWidget frame with the design-system canvas
        color while in Ankountant mode, so nothing flashes Qt gray around the
        webviews. Re-applied on theme change.

        The Ankountant shell is a light-only experience, so the frame is always
        the light canvas (never the dark one) to match the light webviews."""
        if self._ankountant_fullscreen:
            canvas = colors.CANVAS["light"]
            self.setStyleSheet(
                f"QMainWindow {{ background-color: {canvas}; }}"
                f" QDockWidget {{ background-color: {canvas}; }}"
            )
        else:
            self.setStyleSheet("")

    # Auto update
    ##########################################################################

    def setup_auto_update(self, _log: list[DownloadLogEntry]) -> None:
        # Desktop update checks are disabled: this fork must not query upstream
        # Anki's ankiweb.net servers, which always report it as out of date.
        return

    # Timers
    ##########################################################################

    def setup_timers(self) -> None:
        # refresh decks every 10 minutes
        self.progress.timer(10 * 60 * 1000, self.onRefreshTimer, True, parent=self)
        # check media sync every 5 minutes
        self.progress.timer(
            5 * 60 * 1000, self.on_periodic_sync_timer, True, parent=self
        )
        # periodic garbage collection
        self.progress.timer(
            15 * 60 * 1000, self.garbage_collect_now, True, False, parent=self
        )
        # ensure Python interpreter runs at least once per second, so that
        # SIGINT/SIGTERM is processed without a long delay
        self.progress.timer(1000, lambda: None, True, False, parent=self)
        # periodic backups are checked every 5 minutes
        self.progress.timer(
            5 * 60 * 1000,
            self.on_periodic_backup_timer,
            True,
            parent=self,
        )

    def onRefreshTimer(self) -> None:
        if self.state == "deckBrowser":
            self.deckBrowser.refresh()
        elif self.state == "overview":
            self.overview.refresh()

    def on_periodic_sync_timer(self) -> None:
        elap = self.media_syncer.seconds_since_last_sync()
        minutes = self.pm.periodic_sync_media_minutes()
        if not minutes:
            return
        if elap > minutes * 60:
            if not self._can_sync_unattended():
                return
            # media_syncer takes care of media syncing preference check
            self.media_syncer.start(True)

    # Backups
    ##########################################################################

    def on_periodic_backup_timer(self) -> None:
        """Create a backup if enough time has elapsed and collection changed."""
        self._create_backup_with_progress(user_initiated=False)

    def on_create_backup_now(self) -> None:
        self._create_backup_with_progress(user_initiated=True)

    def create_backup_now(self) -> None:
        """Create a backup immediately, regardless of when the last one was created.
        Waits until the backup completes. Intended to be used as part of a longer-running
        CollectionOp/QueryOp."""
        self.col.create_backup(
            backup_folder=self.pm.backupFolder(),
            force=True,
            wait_for_completion=True,
        )

    def _create_backup_with_progress(self, user_initiated: bool) -> None:
        # The initial copy will display a progress window if it takes too long
        def backup(col: Collection) -> bool:
            return col.create_backup(
                backup_folder=self.pm.backupFolder(),
                force=user_initiated,
                wait_for_completion=False,
            )

        def on_success(val: None) -> None:
            if user_initiated:
                tooltip(tr.profiles_backup_created(), parent=self)

        def on_failure(exc: Exception) -> None:
            showWarning(
                tr.profiles_backup_creation_failed(reason=str(exc)), parent=self
            )

        def after_backup_started(created: bool) -> None:
            self.update_undo_actions()

            if user_initiated and not created:
                tooltip(tr.profiles_backup_unchanged(), parent=self)
                return

            # We await backup completion to confirm it was successful, but this step
            # does not block collection access, so we don't need to show the progress
            # window anymore.
            QueryOp(
                parent=self,
                op=lambda col: col.await_backup_completion(),
                success=on_success,
            ).failure(on_failure).without_collection().run_in_background()

        QueryOp(parent=self, op=backup, success=after_backup_started).failure(
            on_failure
        ).with_progress(tr.profiles_creating_backup()).run_in_background()

    # Permanent hooks
    ##########################################################################

    def setupHooks(self) -> None:
        hooks.schema_will_change.append(self.onSchemaMod)
        hooks.notes_will_be_deleted.append(self.onRemNotes)
        hooks.card_odue_was_invalid.append(self.onOdueInvalid)

        gui_hooks.av_player_will_play.append(self.on_av_player_will_play)
        gui_hooks.av_player_did_end_playing.append(self.on_av_player_did_end_playing)
        gui_hooks.operation_did_execute.append(self.on_operation_did_execute)
        gui_hooks.focus_did_change.append(self.on_focus_did_change)
        gui_hooks.top_toolbar_did_init_links.append(self._on_top_toolbar_did_init_links)

        self._activeWindowOnPlay: QWidget | None = None

    def onOdueInvalid(self) -> None:
        showWarning(tr.qt_misc_invalid_property_found_on_card_please())

    def _isVideo(self, tag: AVTag) -> bool:
        if isinstance(tag, SoundOrVideoTag):
            head, ext = os.path.splitext(tag.filename.lower())
            return ext in (".mp4", ".mov", ".mpg", ".mpeg", ".mkv", ".avi")

        return False

    def on_av_player_will_play(self, tag: AVTag) -> None:
        "Record active window to restore after video playing."
        if not self._isVideo(tag):
            return

        self._activeWindowOnPlay = self.app.activeWindow() or self._activeWindowOnPlay

    def on_av_player_did_end_playing(self, player: Any) -> None:
        "Restore window focus after a video was played."
        w = self._activeWindowOnPlay
        if not self.app.activeWindow() and w and not sip.isdeleted(w) and w.isVisible():
            w.activateWindow()
            w.raise_()
        self._activeWindowOnPlay = None

    # Log note deletion
    ##########################################################################

    def onRemNotes(self, col: Collection, nids: Sequence[NoteId]) -> None:
        path = os.path.join(self.pm.profileFolder(), "deleted.txt")
        existed = os.path.exists(path)
        with open(path, "ab") as f:
            if not existed:
                f.write(b"#guid column:1\n")
                f.write(b"#notetype column:2\n")
                f.write(b"#nid\tmid\tfields\n")
            for id, mid, flds in col.db.execute(
                f"select id, mid, flds from notes where id in {ids2str(nids)}"
            ):
                fields = split_fields(flds)
                f.write(("\t".join([str(id), str(mid)] + fields)).encode("utf8"))
                f.write(b"\n")

    # Schema modifications
    ##########################################################################

    # this will gradually be phased out
    def onSchemaMod(self, arg: bool) -> bool:
        if not self.inMainThread():
            raise Exception("not in main thread")
        progress_shown = self.progress.busy()
        if progress_shown:
            self.progress.finish()
        ret = askUser(tr.qt_misc_the_requested_change_will_require_a())
        if progress_shown:
            self.progress.start()
        return ret

    # in favour of this
    def confirm_schema_modification(self) -> bool:
        """If schema unmodified, ask user to confirm change.
        True if confirmed or already modified."""
        if self.col.schema_changed():
            return True
        return askUser(tr.qt_misc_the_requested_change_will_require_a())

    # Advanced features
    ##########################################################################

    def onCheckDB(self) -> None:
        from aqt.dbcheck import check_db

        check_db(self)

    def on_check_media_db(self) -> None:
        from aqt.mediacheck import check_media_db

        gui_hooks.media_check_will_start()
        check_media_db(self)

    def onStudyDeck(self) -> None:
        from aqt.studydeck import StudyDeck

        def callback(ret: StudyDeck) -> None:
            if not ret.name:
                return
            deck_id = self.col.decks.id(ret.name)
            set_current_deck(parent=self, deck_id=deck_id).success(
                lambda out: self.moveToState("overview")
            ).run_in_background()

        StudyDeck(
            self,
            parent=self,
            dyn=True,
            current=self.col.decks.current()["name"],
            callback=callback,
        )

    def onEmptyCards(self) -> None:
        from aqt.emptycards import show_empty_cards

        show_empty_cards(self)

    # System specific code
    ##########################################################################

    def setupSystemSpecific(self) -> None:
        self.hideMenuAccels = False
        if is_mac:
            # mac users expect a minimize option
            self.minimizeShortcut = QShortcut("Ctrl+M", self)
            qconnect(self.minimizeShortcut.activated, self.onMacMinimize)
            self.hideMenuAccels = True
            self.maybeHideAccelerators()
            self.hideStatusTips()

    def maybeHideAccelerators(self, tgt: Any | None = None) -> None:
        if not self.hideMenuAccels:
            return
        tgt = tgt or self
        for action_ in tgt.findChildren(QAction):
            action = cast(QAction, action_)
            txt = str(action.text())
            m = re.match(r"^(.+)\(&.+\)(.+)?", txt)
            if m:
                action.setText(m.group(1) + (m.group(2) or ""))

    def hideStatusTips(self) -> None:
        for action in self.findChildren(QAction):
            # On Windows, this next line gives a 'redundant cast' error after moving to
            # PyQt6.5.2.
            cast(QAction, action).setStatusTip("")  # type: ignore

    def onMacMinimize(self) -> None:
        self.setWindowState(self.windowState() | Qt.WindowState.WindowMinimized)  # type: ignore

    # Single instance support
    ##########################################################################

    def setupAppMsg(self) -> None:
        qconnect(self.app.appMsg, self.onAppMsg)

    def onAppMsg(self, buf: str) -> None:
        is_addon = self._isAddon(buf)

        if self.state == "startup":
            # try again in a second
            self.progress.single_shot(
                1000,
                lambda: self.onAppMsg(buf),
                False,
            )
            return
        elif self.state == "profileManager":
            # can't raise window while in profile manager
            if buf == "raise":
                return None
            self.pendingImport = buf
            if is_addon:
                msg = tr.qt_misc_addon_will_be_installed_when_a()
            else:
                msg = tr.qt_misc_deck_will_be_imported_when_a()
            tooltip(msg)
            return
        if not self.interactiveState() or self.progress.busy():
            # we can't raise the main window while in profile dialog, syncing, etc
            if buf != "raise":
                showInfo(
                    tr.qt_misc_please_ensure_a_profile_is_open(),
                    parent=None,
                )
            return None
        # raise window
        if is_win:
            # on windows we can raise the window by minimizing and restoring
            self.showMinimized()
            self.setWindowState(Qt.WindowState.WindowActive)
            self.showNormal()
        else:
            # on osx we can raise the window. on unity the icon in the tray will just flash.
            self.activateWindow()
            self.raise_()
        if buf == "raise":
            return None

        # import / add-on installation
        if is_addon:
            self.installAddon(buf)
        else:
            self.handleImport(buf)

        return None

    def _isAddon(self, buf: str) -> bool:
        # only accept primary extension here to avoid conflicts with deck packages
        return buf.endswith(self.addonManager.exts[0])

    def interactiveState(self) -> bool:
        "True if not in profile manager, syncing, etc."
        return self.state in ("overview", "review", "deckBrowser")

    # GC
    ##########################################################################
    # The default Python garbage collection can trigger on any thread. This can
    # cause crashes if Qt objects are garbage-collected, as Qt expects access
    # only on the main thread. So Anki disables the default GC on startup, and
    # instead runs it on a timer, and after dialog close.
    # The gc after dialog close is necessary to free up the memory and extra
    # processes that webviews spawn, as a lot of the GUI code creates ref cycles.

    def garbage_collect_on_dialog_finish(self, dialog: QDialog) -> None:
        qconnect(
            dialog.finished, lambda: self.deferred_delete_and_garbage_collect(dialog)
        )

    def deferred_delete_and_garbage_collect(self, obj: QObject) -> None:
        obj.deleteLater()
        self.progress.single_shot(1000, self.garbage_collect_now, False)

    def disable_automatic_garbage_collection(self) -> None:
        gc.collect()
        gc.disable()

    def garbage_collect_now(self) -> None:
        # gc.collect() has optional arguments that will cause problems if
        # it's passed directly to a QTimer, and pylint complains if we
        # wrap it in a lambda, so we use this trivial wrapper
        gc.collect()

    # legacy aliases

    setupDialogGC = garbage_collect_on_dialog_finish
    gcWindow = deferred_delete_and_garbage_collect

    # Media server
    ##########################################################################

    def setupMediaServer(self) -> None:
        import aqt.mediasrv

        self.mediaServer = aqt.mediasrv.MediaServer(self)
        self.mediaServer.start()

    def baseHTML(self) -> str:
        return f'<base href="{self.serverURL()}">'

    def serverURL(self) -> str:
        return "http://127.0.0.1:%d/" % self.mediaServer.getPort()


# legacy
class ResetReason(enum.Enum):
    Unknown = "unknown"
    AddCardsAddNote = "addCardsAddNote"
    EditCurrentInit = "editCurrentInit"
    EditorBridgeCmd = "editorBridgeCmd"
    BrowserSetDeck = "browserSetDeck"
    BrowserAddTags = "browserAddTags"
    BrowserRemoveTags = "browserRemoveTags"
    BrowserSuspend = "browserSuspend"
    BrowserReposition = "browserReposition"
    BrowserReschedule = "browserReschedule"
    BrowserFindReplace = "browserFindReplace"
    BrowserTagDupes = "browserTagDupes"
    BrowserDeleteDeck = "browserDeleteDeck"
