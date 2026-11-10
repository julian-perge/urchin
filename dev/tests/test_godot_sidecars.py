# These tests hand godot_sidecars.py index listings built by hand, so none of
# them needs a git repository.
from __future__ import annotations

from urchin_dev.checks.godot_sidecars import missing_sidecars


def test_a_png_without_its_import_is_reported_wherever_godot_imports_it():
    pngs = ["assets/ui/buffs/AMEND.png", "resources/sprites/a.png"]
    assert missing_sidecars(pngs, set(pngs)) == [
        "assets/ui/buffs/AMEND.png.import",
        "resources/sprites/a.png.import",
    ]


def test_a_script_without_its_uid_is_reported():
    assert missing_sidecars(["scripts/a.gd"], {"scripts/a.gd"}) == ["scripts/a.gd.uid"]


def test_audio_fonts_shaders_and_video_need_their_sidecars_too():
    paths = ["assets/a.mp3", "assets/a.ttf", "shaders/a.gdshader", "assets/a.ogv"]
    assert missing_sidecars(paths, set(paths)) == [
        "assets/a.mp3.import",
        "assets/a.ttf.import",
        "shaders/a.gdshader.uid",
        "assets/a.ogv.uid",
    ]


def test_a_sidecar_in_the_index_satisfies_its_file():
    index = {"assets/a.png", "assets/a.png.import", "scripts/a.gd", "scripts/a.gd.uid"}
    assert missing_sidecars(["assets/a.png", "scripts/a.gd"], index) == []


def test_a_file_under_a_gdignored_folder_needs_no_sidecar():
    index = {"dev/save_presets/.gdignore", "dev/save_presets/sub/generate.gd"}
    assert missing_sidecars(["dev/save_presets/sub/generate.gd"], index) == []


def test_a_gdignore_in_a_sibling_folder_does_not_excuse_a_file():
    index = {"dev/save_presets/.gdignore", "dev/tools/generate.gd"}
    assert missing_sidecars(["dev/tools/generate.gd"], index) == [
        "dev/tools/generate.gd.uid"
    ]


def test_a_file_godot_keeps_no_sidecar_for_is_ignored():
    paths = ["AGENTS.md", "resources/items/a.tres", "scenes/battle.tscn"]
    assert missing_sidecars(paths, set(paths)) == []
