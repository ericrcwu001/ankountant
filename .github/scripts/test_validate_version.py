# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import pytest
from validate_version import validate_version


@pytest.mark.parametrize(
    "version, current, expected",
    [
        ("1.0", "0.1", False),
        ("1.0.1", "1.0", False),
        ("1.1", "1.0", False),
        ("1.0b1", "0.9", True),
        ("1.0a1", "0.9", True),
        ("1.0rc1", "0.9", True),
        ("1.0.1rc2", "1.0", True),
        ("1.0.1b1", "1.0", True),
    ],
)
def test_valid_versions(version: str, current: str, expected: bool) -> None:
    assert validate_version(version, current) is expected


@pytest.mark.parametrize(
    "version, current, match",
    [
        ("1.0", "1.0", "must be greater"),
        ("0.9", "1.0", "must be greater"),
        ("1.0b1", "1.0", "must be greater"),
        ("1", "0.9", "major.minor"),
        ("", "0.9", "major.minor"),
        ("not-a-version", "0.9", "major.minor"),
        ("1.0.dev1", "0.9", "major.minor"),
        ("1.0.post1", "0.9", "major.minor"),
        ("1.0.0.1", "0.9", "major.minor"),
    ],
)
def test_invalid_versions(version: str, current: str, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        validate_version(version, current)
