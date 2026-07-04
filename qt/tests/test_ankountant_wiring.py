# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Mechanical checks that the Ankountant feature pages are wired into the app.

The e2e harness runs Qt headless (offscreen) and cannot click Qt menus, so the
menu-to-page navigation itself is validated manually via `just run`. These tests
cover the two registrations that must be present for the menu dialogs to work at
all: the routes must be recognised as SvelteKit pages, and their webview kinds
must exist (and be granted backend API access in webview.py)."""

from aqt.main import (
    ankountant_confusable_patch_updates,
    require_ankountant_demo_phase,
)
from aqt.mediasrv import is_sveltekit_page
from aqt.webview import AnkiWebViewKind
from aqt.workspace import ankountant_route_for_page

ANKOUNTANT_PAGES = (
    "ankountant-home",
    "ankountant-workspace",
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

ANKOUNTANT_PAGE_ROUTES = {
    "home": "ankountant-home",
    "workspace": "ankountant-workspace",
    "dashboard": "ankountant-dashboard",
    "confusion": "ankountant-confusion",
    "tbs": "ankountant-tbs",
    "research": "ankountant-research",
    "doc_review": "ankountant-doc-review",
    "stats": "ankountant-stats",
}

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


def test_ankountant_route_lookup_rejects_unknown_pages() -> None:
    for page, route in ANKOUNTANT_PAGE_ROUTES.items():
        assert ankountant_route_for_page(page) == route

    try:
        ankountant_route_for_page("dasboard")
    except ValueError as exc:
        assert "unknown Ankountant page: dasboard" in str(exc)
    else:
        raise AssertionError("expected route lookup to reject typo")


def test_ankountant_demo_phase_lookup_rejects_unknown_phases() -> None:
    for phase in ("foundation", "discrimination", "consolidation"):
        require_ankountant_demo_phase(phase)

    try:
        require_ankountant_demo_phase("exam-soon")
    except ValueError as exc:
        assert "unknown Ankountant demo phase: exam-soon" in str(exc)
    else:
        raise AssertionError("expected demo phase lookup to reject typo")


def test_confusable_patch_updates_group_by_section() -> None:
    updates = ankountant_confusable_patch_updates(
        {
            "set-a": {
                "section": "FAR",
                "tags": ["lease", "liability"],
                "treatments": [{"front": "A"}],
            },
            "set-b": {
                "section": "AUD",
                "tags": [],
                "treatments": [],
            },
        }
    )

    assert updates == {
        "ankountant.confusable.FAR": {
            "set-a": {
                "tags": ["lease", "liability"],
                "treatments": [{"front": "A"}],
            }
        },
        "ankountant.confusable.AUD": {
            "set-b": {
                "tags": [],
                "treatments": [],
            }
        },
    }


def test_confusable_patch_updates_reject_malformed_entries() -> None:
    malformed_patches = [
        [],
        {"": {"section": "FAR"}},
        {"set": []},
        {"set": {"tags": []}},
        {"set": {"section": "FAR", "tags": "lease"}},
        {"set": {"section": "FAR", "treatments": "drill"}},
    ]

    for patch in malformed_patches:
        try:
            ankountant_confusable_patch_updates(patch)
        except ValueError:
            pass
        else:
            raise AssertionError(f"expected malformed patch to fail: {patch!r}")
