# These tests need no Godot. They check which binary is found and that the slot
# lock files limit how many holders run at once.
from __future__ import annotations

import pytest
from urchin_dev import godot
from urchin_dev.godot import godot_bin, godot_slot, slot_count


def test_godot_bin_prefers_the_environment_variable():
    assert godot_bin({"GODOT_BIN": "/opt/godot", "PATH": "/usr/bin"}) == "/opt/godot"


def test_godot_bin_falls_back_to_godot_on_path(tmp_path):
    binary = tmp_path / "godot"
    binary.write_text("#!/bin/sh\n")
    binary.chmod(0o755)
    assert godot_bin({"PATH": str(tmp_path)}) == str(binary)


def test_godot_bin_exits_when_nothing_is_found(tmp_path, monkeypatch):
    monkeypatch.setattr(godot, "MAC_APP", tmp_path / "none")
    with pytest.raises(SystemExit, match="GODOT_BIN"):
        godot_bin({"PATH": str(tmp_path)})


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
