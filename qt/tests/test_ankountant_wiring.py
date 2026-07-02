# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Mechanical checks that the Ankountant feature pages are wired into the app.

The e2e harness runs Qt headless (offscreen) and cannot click Qt menus, so the
menu-to-page navigation itself is validated manually via `just run`. These tests
cover the two registrations that must be present for the menu dialogs to work at
all: the routes must be recognised as SvelteKit pages, and their webview kinds
must exist (and be granted backend API access in webview.py)."""

from aqt.mediasrv import is_sveltekit_page
from aqt.webview import AnkiWebViewKind

ANKOUNTANT_PAGES = (
    "ankountant-dashboard",
    "ankountant-confusion",
    "ankountant-tbs",
    # Research + doc-review are section-agnostic TBS surfaces (ADR 0008). Like
    # Stats they live inside the shell webview (tab / open_ankountant(...)) and
    # in the tiling workspace, so they have routes but no dedicated webview kind.
    "ankountant-research",
    "ankountant-doc-review",
    # Stats is a first-class destination too, but it is navigated inside the
    # shell webview (menu/tab -> open_ankountant("stats")) rather than a
    # dedicated dialog, so it has a route but no separate webview kind.
    "ankountant-stats",
)

ANKOUNTANT_KINDS = (
    "ANKOUNTANT_DASHBOARD",
    "ANKOUNTANT_CONFUSION",
    "ANKOUNTANT_TBS",
)


def test_ankountant_pages_are_registered_sveltekit_routes() -> None:
    for page in ANKOUNTANT_PAGES:
        assert is_sveltekit_page(page), f"{page} not whitelisted in is_sveltekit_page"


def test_ankountant_webview_kinds_exist() -> None:
    for name in ANKOUNTANT_KINDS:
        assert hasattr(AnkiWebViewKind, name), f"missing AnkiWebViewKind.{name}"
