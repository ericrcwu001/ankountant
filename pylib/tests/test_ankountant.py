# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Callability + dispatch tests for the Ankountant SchedulerService RPCs.

These verify the four new methods surface through the PyO3 bridge and dispatch
to the correct Rust implementation after `just check` regenerates the bindings
(contract A08 / A39). Score correctness is covered exhaustively in the Rust
suite; here we only confirm the cross-language wiring.
"""

import datetime

from anki.errors import NotFoundError
from tests.shared import getEmptyCol


def test_compute_exam_schedule_callable():
    # A08 — ComputeExamSchedule is callable from Python and returns a response.
    col = getEmptyCol()
    resp = col._backend.compute_exam_schedule(section="FAR", exam_date="")
    # No exam date -> falls back to the configured preset retention (0..1).
    assert 0.0 < resp.desired_retention <= 1.0


def test_exam_date_config_changes_ramp():
    # A09 — exam date read from col config via the existing set-config RPC.
    col = getEmptyCol()
    today = datetime.date.today()
    far = (today + datetime.timedelta(days=90)).isoformat()
    near = (today + datetime.timedelta(days=30)).isoformat()

    col.set_config("ankountant.FAR.exam.date", far)
    r_far = col._backend.compute_exam_schedule(
        section="FAR", exam_date=""
    ).desired_retention
    col.set_config("ankountant.FAR.exam.date", near)
    r_near = col._backend.compute_exam_schedule(
        section="FAR", exam_date=""
    ).desired_retention

    assert abs(r_far - 0.80) < 1e-6
    assert abs(r_near - 0.875) < 1e-6
    assert r_near > r_far


def test_build_confusion_queue_callable():
    # Dispatches; with no CONFUSABLE map configured it returns an empty queue.
    col = getEmptyCol()
    resp = col._backend.build_confusion_queue(section="FAR", max_items=10)
    assert list(resp) == []


def test_get_readiness_callable_and_abstains_when_empty():
    # A16 surfaced through Python: no attempts -> abstain, insufficient volume.
    col = getEmptyCol()
    resp = col._backend.get_readiness(section="FAR")
    assert resp.readiness.abstain is True
    assert resp.readiness.reason == "insufficient volume"


def test_submit_performance_attempt_dispatches():
    # A39 — SubmitPerformanceAttempt is callable and dispatches to the right
    # Rust method (a missing item note surfaces NotFoundError, not a hang or a
    # wrong-method result — which is exactly what mis-dispatch would produce).
    col = getEmptyCol()
    try:
        col._backend.submit_performance_attempt(
            item_note_id=1234567,
            mode="confusion",
            submission_json='{"choice":"x"}',
            confidence="guess",
            latency_ms=100,
        )
        raise AssertionError("expected NotFoundError for a missing item note")
    except NotFoundError:
        pass


def test_load_far_seed_dispatches_and_seeds():
    # F016 — LoadFarSeed (SchedulerService method 43, appended at the tail) is
    # callable from Python and dispatches to the right Rust method. This is the
    # cross-language guard against the service-index drift that must stay in
    # lockstep with the hand-maintained iOS dispatch table (FR-6).
    col = getEmptyCol()
    resp = col._backend.load_far_seed(section="FAR")
    assert resp.confusion_sets >= 4
    assert resp.sealed_items >= 24
    assert resp.sealed_je_tbs >= 3
    assert resp.sealed_numeric_tbs >= 2
    assert len(resp.sealed_tbs_note_ids) >= 5

    # The seed is real: GetReadiness now sees the CONFUSABLE map / sealed bank.
    queue = col._backend.build_confusion_queue(section="FAR", max_items=10)
    assert len(list(queue)) > 0
