# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Unit test for utils.widget_effectively_focused.

This helper backs the single-window workspace: it decides whether a surface
"has focus" in a way that stays correct when the surface is a nested widget
(a dock tab) rather than a top-level window. Focus is monkeypatched so the test
is deterministic and needs no event loop."""

from __future__ import annotations

import os

import pytest

# Render to memory so a QApplication can be created on a headless machine.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from aqt.qt import QApplication, QWidget

    _app = QApplication.instance() or QApplication([])
except Exception as exc:  # pragma: no cover - platform without Qt GUI
    pytest.skip(f"Qt GUI unavailable: {exc}", allow_module_level=True)

from aqt import utils


def test_widget_effectively_focused(monkeypatch: pytest.MonkeyPatch) -> None:
    parent = QWidget()
    child = QWidget(parent)
    grandchild = QWidget(child)
    sibling = QWidget()  # separate top-level, not under `parent`

    def set_focus(widget: QWidget | None) -> None:
        monkeypatch.setattr(QApplication, "focusWidget", staticmethod(lambda: widget))

    # The widget itself.
    set_focus(parent)
    assert utils.widget_effectively_focused(parent) is True

    # A descendant (direct + nested) counts as focused.
    set_focus(child)
    assert utils.widget_effectively_focused(parent) is True
    set_focus(grandchild)
    assert utils.widget_effectively_focused(parent) is True

    # A widget outside the subtree does not.
    set_focus(sibling)
    assert utils.widget_effectively_focused(parent) is False

    # No focus widget at all.
    set_focus(None)
    assert utils.widget_effectively_focused(parent) is False
