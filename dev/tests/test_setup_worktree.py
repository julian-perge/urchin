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


def test_the_import_goes_through_the_slot_script_when_it_and_fish_exist(tmp_path):
    slot = tmp_path / "godot-slot.fish"
    slot.write_text("")
    command = godot_import_command(Path("/Godot"), slot, "/bin/fish")
    assert command[:3] == ["/bin/fish", str(slot), "/Godot"]
    assert command[3:6] == ["--headless", "--import", "--path"]


def test_the_import_runs_godot_directly_without_the_slot_script(tmp_path):
    command = godot_import_command(Path("/Godot"), tmp_path / "none.fish", "/bin/fish")
    assert command[:4] == ["/Godot", "--headless", "--import", "--path"]
    command = godot_import_command(Path("/Godot"), tmp_path / "none.fish", None)
    assert command[0] == "/Godot"
