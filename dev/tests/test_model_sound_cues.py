# convert_model_sound_cues's reading of a doll model's frame scripts, on a
# folder of scripts written by hand, so no test needs the AS export.
from __future__ import annotations

import pytest
from urchin_dev.convert import model_sound_cues


def write_script(folder, frame, text, name="DoAction.as"):
    path = folder / f"frame_{frame}"
    path.mkdir()
    (path / name).write_text(text, encoding="utf-8")


def test_cues_map_each_frame_to_the_sounds_its_script_adds(tmp_path):
    write_script(tmp_path, 88, '_root.addSound("Effects","sfx_swing");\n')
    write_script(tmp_path, 118, '_root.addSound("Effects","sfx_swing");\n')
    write_script(tmp_path, 146, '_root.addSound("Effects","sfx_swing");\n')
    assert model_sound_cues.read_cues(tmp_path) == {
        "88": ["sfx_swing"],
        "118": ["sfx_swing"],
        "146": ["sfx_swing"],
    }


def test_cues_come_in_frame_order_not_folder_order(tmp_path):
    write_script(tmp_path, 146, '_root.addSound("Effects","sfx_swing");\n')
    write_script(tmp_path, 88, '_root.addSound("Effects","sfx_swing");\n')
    write_script(tmp_path, 9, '_root.addSound("Effects","sfx_swing");\n')
    assert list(model_sound_cues.read_cues(tmp_path)) == ["9", "88", "146"]


def test_a_frame_script_with_no_sound_adds_no_cue(tmp_path):
    write_script(tmp_path, 30, 'gotoAndStop("stand");\nplay();\n')
    write_script(tmp_path, 88, '_root.addSound("Effects","sfx_swing");\n')
    assert model_sound_cues.read_cues(tmp_path) == {"88": ["sfx_swing"]}


def test_a_frame_with_two_sounds_keeps_both_in_script_order(tmp_path):
    write_script(
        tmp_path,
        50,
        '_root.addSound("Effects","sfx_swing");\n_root.addSound("Effects","sfx_hit");\n',
    )
    assert model_sound_cues.read_cues(tmp_path) == {"50": ["sfx_swing", "sfx_hit"]}


def test_a_second_script_of_a_frame_adds_its_cues_after_the_first(tmp_path):
    write_script(tmp_path, 50, '_root.addSound("Effects","sfx_swing");\n')
    (tmp_path / "frame_50" / "DoAction_2.as").write_text(
        '_root.addSound("Effects","sfx_hit");\n', encoding="utf-8"
    )
    assert model_sound_cues.read_cues(tmp_path) == {"50": ["sfx_swing", "sfx_hit"]}


def test_a_sound_call_of_another_shape_fails_naming_its_frame(tmp_path):
    write_script(tmp_path, 88, '_root.addSound("Music","sfx_swing");\n')
    with pytest.raises(ValueError, match="frame 88"):
        model_sound_cues.read_cues(tmp_path)


def test_a_folder_with_scripts_and_no_cue_gives_no_cues(tmp_path):
    # MODEL8's frame scripts only move its playhead.
    write_script(tmp_path, 30, 'gotoAndStop("stand");\n')
    assert model_sound_cues.read_cues(tmp_path) == {}


def test_a_folder_with_no_frame_script_fails(tmp_path):
    with pytest.raises(ValueError, match="no frame scripts"):
        model_sound_cues.read_cues(tmp_path)


def test_each_model_reads_its_own_sprite_and_writes_its_own_file():
    assert model_sound_cues.source("MODEL4").name == "DefineSprite_2668_MODEL4"
    assert model_sound_cues.output("MODEL4").name == "model4_sound_cues.json"
    assert model_sound_cues.source("MODEL1").name == "DefineSprite_166_MODEL1"
    assert model_sound_cues.output("MODEL1").name == "model1_sound_cues.json"
