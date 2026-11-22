# This test needs no git repository, SWF or Godot.
from __future__ import annotations

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
