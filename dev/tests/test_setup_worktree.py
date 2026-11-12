# This test needs no git repository, SWF or Godot.
from __future__ import annotations

from urchin_dev.setup_worktree import godot_import_command


def test_the_import_command_runs_the_given_godot_on_the_repo():
    command = godot_import_command("/Godot")
    assert command[:4] == ["/Godot", "--headless", "--import", "--path"]
