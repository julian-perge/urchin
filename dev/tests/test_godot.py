# These tests need no Godot. They check which binary is found and that the slot
# lock files limit how many holders run at once.
from __future__ import annotations

import pytest
from urchin_dev import godot
from urchin_dev.godot import godot_bin, godot_slot, slot_count


def test_godot_bin_is_the_environment_variable():
    assert godot_bin({"GODOT_BIN": "/opt/godot"}) == "/opt/godot"


def test_godot_bin_exits_and_names_just_when_the_variable_is_unset():
    with pytest.raises(SystemExit, match="through `just`"):
        godot_bin({})
    with pytest.raises(SystemExit, match="through `just`"):
        godot_bin({"GODOT_BIN": ""})


def test_slot_count_reads_godot_slots(monkeypatch):
    assert slot_count({"GODOT_SLOTS": "5"}) == 5
    assert slot_count({"GODOT_SLOTS": "0"}) == 1


def test_slot_count_is_the_core_count_when_unset_auto_or_not_a_number(monkeypatch):
    monkeypatch.setattr(godot.os, "cpu_count", lambda: 12)
    assert slot_count({}) == 12
    assert slot_count({"GODOT_SLOTS": "auto"}) == 12
    assert slot_count({"GODOT_SLOTS": "many"}) == 12


def test_a_slot_is_free_again_after_its_block_ends(tmp_path):
    with godot_slot(slots=1, slot_dir=tmp_path):
        pass
    with godot_slot(slots=1, slot_dir=tmp_path):
        pass


def test_a_second_holder_waits_while_every_slot_is_taken(tmp_path, monkeypatch):
    waits = []

    def fake_sleep(seconds):
        waits.append(seconds)
        raise TimeoutError

    monkeypatch.setattr(godot.time, "sleep", fake_sleep)
    with (
        godot_slot(slots=1, slot_dir=tmp_path),
        pytest.raises(TimeoutError),
        godot_slot(slots=1, slot_dir=tmp_path),
    ):
        pass
    assert waits == [0.5]
