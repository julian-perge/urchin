# These tests build fake checkouts in tmp_path, so none of them needs a git
# repository, a SWF or Godot.
from __future__ import annotations

from pathlib import Path

from urchin_dev.setup_worktree import godot_import_command, swf_links


def checkout(root: Path, *files: str) -> Path:
    root.mkdir()
    for name in files:
        (root / name).write_bytes(b"FWS")
    return root


def test_a_new_worktree_links_both_swfs_from_the_main_checkout(tmp_path):
    main = checkout(tmp_path / "main", "sonny-2-2900.swf", "SONNY2.swf")
    worktree = checkout(tmp_path / "worktree")
    assert swf_links(worktree, main) == [
        (worktree / "sonny-2-2900.swf", main / "sonny-2-2900.swf"),
        (worktree / "SONNY2.swf", main / "SONNY2.swf"),
    ]


def test_a_swf_the_worktree_already_has_is_left_alone(tmp_path):
    main = checkout(tmp_path / "main", "sonny-2-2900.swf", "SONNY2.swf")
    worktree = checkout(tmp_path / "worktree", "SONNY2.swf")
    assert swf_links(worktree, main) == [
        (worktree / "sonny-2-2900.swf", main / "sonny-2-2900.swf")
    ]


def test_a_swf_the_main_checkout_lacks_is_not_linked(tmp_path):
    main = checkout(tmp_path / "main", "sonny-2-2900.swf")
    worktree = checkout(tmp_path / "worktree")
    assert swf_links(worktree, main) == [
        (worktree / "sonny-2-2900.swf", main / "sonny-2-2900.swf")
    ]


def test_the_main_checkout_links_nothing_to_itself(tmp_path):
    main = checkout(tmp_path / "main")
    assert swf_links(main, main) == []


def test_the_import_command_runs_the_given_godot_on_the_repo():
    command = godot_import_command("/Godot")
    assert command[:4] == ["/Godot", "--headless", "--import", "--path"]
