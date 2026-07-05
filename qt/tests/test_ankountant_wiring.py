# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Mechanical checks that the Ankountant feature pages are wired into the app.

The e2e harness runs Qt headless (offscreen) and cannot click Qt menus, so the
menu-to-page navigation itself is validated manually via `just run`. These tests
cover the two registrations that must be present for the menu dialogs to work at
all: the routes must be recognised as SvelteKit pages, and their webview kinds
must exist (and be granted backend API access in webview.py)."""

import json

from aqt.main import (
    CPA_BANK_CATEGORY_SETS,
    CPA_BANK_MEMORY_TAGS,
    ankountant_bank_category_entry,
    ankountant_confusable_patch_updates,
    ankountant_stress_sealed_deck_parts,
    ankountant_submission_for_tbs_fields,
    ankountant_tbs_type,
    require_ankountant_demo_phase,
)
from aqt.mediasrv import exposed_backend_list, is_sveltekit_page
from aqt.webview import AnkiWebViewKind
from aqt.workspace import Workspace, ankountant_route_for_page

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
    "ankountant-sync",
    "ankountant-settings",
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
    "sync": "ankountant-sync",
    "settings": "ankountant-settings",
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


def test_ankountant_review_bridge_starts_far_study_deck() -> None:
    class FakeDecks:
        def __init__(self) -> None:
            self.requested_name = ""
            self.selected_id = None

        def id_for_name(self, name: str) -> int:
            self.requested_name = name
            return 123

        def select(self, deck_id: int) -> None:
            self.selected_id = deck_id

    class FakeMainWindow:
        def __init__(self) -> None:
            self.col = type("FakeCollection", (), {"decks": FakeDecks()})()
            self.states = []

        def moveToState(self, state: str) -> None:
            self.states.append(state)

    class TestWorkspace(Workspace):
        def __init__(self, mw: FakeMainWindow) -> None:
            super().__init__(mw)
            self.home_only = False

        def show_home_only(self) -> None:
            self.home_only = True

    mw = FakeMainWindow()
    workspace = TestWorkspace(mw)
    workspace._start_ankountant_study()

    assert mw.col.decks.requested_name == "Ankountant::Study::FAR"
    assert mw.col.decks.selected_id == 123
    assert workspace.home_only is True
    assert mw.states == ["overview"]


def test_generated_evidence_artifacts_are_not_product_routes() -> None:
    for path in (
        "docs_ankountant/evidence/determinism.html",
        "docs_ankountant/evidence/ablation.html",
        "docs_ankountant/evidence/paraphrase.html",
        "docs_ankountant/evidence/undo.html",
        "docs_ankountant/evidence/latency.html",
        "ankountant-evidence",
    ):
        assert not is_sveltekit_page(path)

    exposed = set(exposed_backend_list)
    assert {"get_readiness", "submit_performance_attempt"} <= exposed
    assert exposed.isdisjoint(
        {
            "ankountant_evidence",
            "determinism_evidence",
            "ablation_evidence",
            "paraphrase_evidence",
            "undo_evidence",
            "latency_evidence",
        }
    )


def test_confusable_patch_updates_group_by_section() -> None:
    updates = ankountant_confusable_patch_updates(
        {
            "set-a": {
                "section": "FAR",
                "tags": ["lease", "liability"],
                "treatments": ["Operating lease", "Finance lease"],
            },
            "set-b": {
                "section": "AUD",
                "tags": ["evidence", "scope"],
                "treatments": ["Sufficient evidence", "Scope limitation"],
            },
        }
    )

    assert updates == {
        "ankountant.confusable.FAR": {
            "set-a": {
                "tags": ["lease", "liability"],
                "treatments": ["Operating lease", "Finance lease"],
            }
        },
        "ankountant.confusable.AUD": {
            "set-b": {
                "tags": ["evidence", "scope"],
                "treatments": ["Sufficient evidence", "Scope limitation"],
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
        {"set": {"section": "FAR", "tags": [], "treatments": ["Capitalize"]}},
        {"set": {"section": "FAR", "tags": ["lease"], "treatments": []}},
        {"set": {"section": "FAR", "tags": [1], "treatments": ["Capitalize"]}},
        {"set": {"section": "FAR", "tags": ["lease"], "treatments": [1]}},
    ]

    for patch in malformed_patches:
        try:
            ankountant_confusable_patch_updates(patch)
        except ValueError:
            pass
        else:
            raise AssertionError(f"expected malformed patch to fail: {patch!r}")


def test_cpa_bank_category_sets_cover_visible_non_far_sections() -> None:
    for section in ("AUD", "REG", "TCP", "ISC"):
        categories = CPA_BANK_CATEGORY_SETS[section]
        assert len(categories) >= 6
        tags = CPA_BANK_MEMORY_TAGS[section]
        assert len(tags) >= 12
        assert all(tag.startswith(f"ds::{section.lower()}::") for tag in tags)


def test_cpa_bank_category_lookup_requires_known_metadata() -> None:
    entry = ankountant_bank_category_entry("AUD", "aud_evidence_sufficiency")
    assert entry["tags"] == ["ds::aud::sufficient", "ds::aud::insufficient"]

    patch_entry = ankountant_bank_category_entry(
        "REG",
        "generated_tax_phaseout",
        {
            "generated_tax_phaseout": {
                "tags": ["ds::reg::phaseout"],
                "treatments": ["MAGI $1 to $2", "No phase-out"],
            }
        },
    )
    assert patch_entry["tags"] == ["ds::reg::phaseout"]

    try:
        ankountant_bank_category_entry("REG", "not_known")
    except ValueError as exc:
        assert "unknown CPA bank category: REG::not_known" in str(exc)
    else:
        raise AssertionError("expected unknown category lookup to fail")


def test_stress_sealed_deck_parts_preserve_section_category() -> None:
    assert ankountant_stress_sealed_deck_parts(
        "Ankountant::Stress::Sealed::ISC::soc1_vs_soc2"
    ) == ("ISC", "soc1_vs_soc2")
    assert (
        ankountant_stress_sealed_deck_parts(
            "Ankountant::Stress::Study::ISC::soc1_vs_soc2"
        )
        is None
    )

    try:
        ankountant_stress_sealed_deck_parts("Ankountant::Stress::Sealed::ISC::")
    except ValueError as exc:
        assert "stress sealed deck is missing a set id" in str(exc)
    else:
        raise AssertionError("expected empty stress set id to fail")


def test_stress_tbs_type_marker_is_ignored_for_submission() -> None:
    assert ankountant_tbs_type("research<!--s123-->") == "research"
    mode, submission = ankountant_submission_for_tbs_fields(
        [
            "research<!--s123-->",
            "Prompt",
            "[]",
            '[{"id":"citation","answer_key":["AU-C 500"],"weight":1.0}]',
            "",
        ],
        True,
    )

    assert mode == "research"
    assert json.loads(submission) == {"citation": "AU-C 500"}
