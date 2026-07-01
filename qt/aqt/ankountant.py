# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Ankountant feature dialogs.

Each dialog embeds one of the Ankountant SvelteKit pages (dashboard /
confusion-set review / TBS practice) in an AnkiWebView, mirroring the
change-notetype dialog pattern. The webview kinds are whitelisted for backend
API access in webview.py, and the routes are whitelisted in
mediasrv.is_sveltekit_page().
"""

from __future__ import annotations

from typing import ClassVar

import aqt
import aqt.main
from aqt.qt import *
from aqt.utils import disable_help_button, restoreGeom, saveGeom
from aqt.webview import AnkiWebView, AnkiWebViewKind


class _AnkountantPageDialog(QDialog):
    """Base dialog that hosts a single Ankountant SvelteKit page."""

    KIND: ClassVar[AnkiWebViewKind]
    PAGE: ClassVar[str]
    TITLE: ClassVar[str]
    GEOM_KEY: ClassVar[str]

    def __init__(self, mw: aqt.main.AnkiQt) -> None:
        QDialog.__init__(self, mw)
        self.mw = mw
        self._setup_ui()
        self.show()

    def _setup_ui(self) -> None:
        self.mw.garbage_collect_on_dialog_finish(self)
        self.setMinimumSize(600, 400)
        disable_help_button(self)
        restoreGeom(self, self.GEOM_KEY, default_size=(900, 800))

        self.web = AnkiWebView(kind=self.KIND)
        self.web.load_sveltekit_page(self.PAGE)
        layout = QVBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.web)
        self.setLayout(layout)

        self.setWindowTitle(self.TITLE)

    def reject(self) -> None:
        self.web.cleanup()
        self.web = None  # type: ignore
        saveGeom(self, self.GEOM_KEY)
        QDialog.reject(self)


class AnkountantDashboardDialog(_AnkountantPageDialog):
    KIND = AnkiWebViewKind.ANKOUNTANT_DASHBOARD
    PAGE = "ankountant-dashboard"
    TITLE = "Ankountant — Readiness"
    GEOM_KEY = "ankountantDashboard"


class AnkountantConfusionDialog(_AnkountantPageDialog):
    KIND = AnkiWebViewKind.ANKOUNTANT_CONFUSION
    PAGE = "ankountant-confusion"
    TITLE = "Ankountant — Confusion-Set Review"
    GEOM_KEY = "ankountantConfusion"


class AnkountantTbsDialog(_AnkountantPageDialog):
    KIND = AnkiWebViewKind.ANKOUNTANT_TBS
    PAGE = "ankountant-tbs"
    TITLE = "Ankountant — TBS Practice"
    GEOM_KEY = "ankountantTbs"
