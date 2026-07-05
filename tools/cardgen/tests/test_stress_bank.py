from scripts import stress_bank


def test_stress_fields_preserve_tbs_type() -> None:
    model = {
        "flds": [
            {"name": "tbs_type", "ord": 0},
            {"name": "prompt", "ord": 1},
        ]
    }

    fields = stress_bank._stress_fields(model, ["research", "Prompt"], 42)

    assert fields[0] == "research"
    assert fields[1] == "Prompt<!--s42-->"


def test_stress_fields_mark_study_front() -> None:
    model = {
        "flds": [
            {"name": "Front", "ord": 0},
            {"name": "Back", "ord": 1},
        ]
    }

    fields = stress_bank._stress_fields(model, ["Front", "Back"], 42)

    assert fields[0] == "Front<!--s42-->"
    assert fields[1] == "Back"
