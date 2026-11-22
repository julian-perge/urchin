# This test needs no git repository, SWF or Godot.
from __future__ import annotations

import contextlib
import subprocess

import pytest
from urchin_dev import setup_worktree
from urchin_dev.setup_worktree import godot_import_command, submodule_command


def test_the_import_command_runs_the_given_godot_on_the_repo():
    command = godot_import_command("/Godot")
    assert command[:4] == ["/Godot", "--headless", "--import", "--path"]


def test_the_submodule_command_fills_only_the_godot_mcp_submodule():
    assert submodule_command() == [
        "git",
        "submodule",
        "update",
        "--init",
        "vendor/godot-mcp",
    ]


def test_a_failed_submodule_fill_warns_and_still_runs_the_import(monkeypatch, capsys):
    calls = []

    def fake_run(command, **_):
        calls.append(command)
        if command == submodule_command():
            return subprocess.CompletedProcess(command, 1, "", "fatal: no network\n")
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(setup_worktree.subprocess, "run", fake_run)
    monkeypatch.setattr(setup_worktree, "godot_bin", lambda: "/Godot")
    monkeypatch.setattr(setup_worktree, "godot_slot", contextlib.nullcontext)
    with pytest.raises(SystemExit) as exit_info:
        setup_worktree.main()
    assert exit_info.value.code == 0
    assert calls == [submodule_command(), godot_import_command("/Godot")]
    out = capsys.readouterr().out
    assert "fatal: no network" in out
    assert "verify-urchin cannot launch" in out
