# These tests hand doc_paths.py Markdown and index listings built by hand, and
# point the home folder at pytest's tmp_path for the paths under ~/.
from __future__ import annotations

from urchin_dev.checks.doc_paths import broken_paths, code_spans

INDEX = {
    "AGENTS.md",
    "addons/gut/gut_cmdln.gd",
    "assets/ui/buffs/AMEND.png",
    "assets/ui/buffs/AMEND.png.import",
    "dev/source_files/action_script/frame_41/DoAction_2.as",
    "dev/source_files/action_script_curated/frame_42/DoAction_8.as",
    "dev/urchin_dev/swf/render.py",
    "pyproject.toml",
    "scripts/a.gd.uid",
    "test/integration/test_battle_runner.gd",
}


def test_a_code_span_starts_on_its_line_and_folds_its_line_breaks():
    text = "Intro.\n- Tests: `godot -s\n  res://a.gd --path .` and `AGENTS.md`.\n"
    assert list(code_spans(text)) == [
        (2, "godot -s res://a.gd --path ."),
        (3, "AGENTS.md"),
    ]


def test_a_fenced_block_holds_no_code_spans():
    text = "```\n`missing/x.py`\n```\n`AGENTS.md`\n"
    assert list(code_spans(text)) == [(4, "AGENTS.md")]


def test_a_path_resolves_from_any_folder_above_it():
    text = (
        "`frame_41/DoAction_2.as` in `action_script_curated/`, `render.py`,"
        " `dev/urchin_dev/swf/` and `AGENTS.md`"
    )
    assert broken_paths(text, INDEX, []) == []


def test_a_path_that_names_nothing_is_reported_with_its_line():
    text = "`render.py`\n\n`frame_42/DoAction_16` and `swf/render2.py`\n"
    assert broken_paths(text, INDEX, []) == [
        (3, "frame_42/DoAction_16"),
        (3, "swf/render2.py"),
    ]


def test_a_path_matches_whole_components_only():
    assert broken_paths("`der.py` and `urchin_dev/sw`", INDEX, []) == [
        (1, "der.py"),
        (1, "urchin_dev/sw"),
    ]


def test_each_word_of_a_command_is_judged_on_its_own():
    text = (
        "`godot -s res://addons/gut/gut_cmdln.gd --path .`,"
        " `rg x pyproject.toml missing.toml` and `godot -s res://addons/gut/gone.gd`"
    )
    assert broken_paths(text, INDEX, []) == [
        (1, "missing.toml"),
        (1, "res://addons/gut/gone.gd"),
    ]


def test_a_gdscript_test_id_stands_for_its_file():
    text = "`test_battle_runner.gd::test_misses` and `test_gone.gd::test_hits`"
    assert broken_paths(text, INDEX, []) == [(1, "test_gone.gd")]


def test_words_that_only_look_like_paths_are_skipped():
    text = (
        "`.png.import` `.uid` `/triage` `res://<path>` `-gtest=res://a.gd`"
        " `src/<context>/docs/adr/` `Krin.zoneName` `timeline.frames()`"
        " `user://achievements.cfg` `https://example.com/a.md`"
    )
    assert broken_paths(text, INDEX, []) == []


def test_a_span_listed_as_not_a_path_is_skipped():
    assert broken_paths("`Timeline.py`", INDEX, ["Timeline.py"]) == []


def test_a_path_under_home_or_root_must_exist_on_this_machine(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    config = tmp_path / "Library/Application Support/FFDec/config.toml"
    config.parent.mkdir(parents=True)
    config.touch()
    text = (
        "`~/Library/Application Support/FFDec/config.toml`,"
        f" `{tmp_path}/gone` and `unzip -p ~/gone.jar project.properties`"
    )
    assert broken_paths(text, INDEX, []) == [(1, f"{tmp_path}/gone"), (1, "~/gone.jar")]
