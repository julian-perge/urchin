from __future__ import annotations

import json
import math

from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract import doll_art


def test_dress_rules_reads_the_parts_of_each_code_and_model5s_size_from_dresschar():
    parts, sizes = doll_art.dress_rules(doll_art.DRESS_CHAR.read_text("utf-8"))
    assert parts["ARM"] == ["arm1", "arm2", "leg1", "leg2"]
    assert parts["FOOT"] == ["foot1", "foot2"]
    assert sizes == {"MODEL5": 0.8}


def test_art_key_tells_a_skin_from_an_item_and_skips_hair():
    codes = {"HEAD", "FOOT", "SHOULDER"}
    assert doll_art.art_key("M_SFOOT_HYDRA2", codes) == ("FOOT", "HYDRA2", True)
    assert doll_art.art_key("M_SHOULDER_ULTI", codes) == ("SHOULDER", "ULTI", False)
    assert doll_art.art_key("HAIR_MAD", codes) is None


def test_wearers_maps_skins_and_looks_to_the_models_that_wear_them():
    units = [
        {
            "visuals": {
                "model": ["MODEL8", "HYDRA2", "", "M"],
                "skin": "0",
                "equipment": [{"id": 0}],
            }
        },
        {
            "visuals": {
                "model": ["MODEL3", "ONE", "", "M"],
                "skin": "ZPCI",
                "equipment": [{"id": 7}],
            }
        },
    ]
    items = {7: {"looks": "AK"}}
    forms = {
        "HOUND": {"model": "MODEL5", "skin": "HOUND", "weapon1": "NONE", "weapon2": ""}
    }
    skins, looks = doll_art.wearers(units, items, forms, {"MODEL1", "MODEL5", "MODEL8"})
    assert skins["HYDRA2"] == {"MODEL8"}
    assert skins["ONE"] == {"MODEL1"}
    assert skins["HOUND"] == {"MODEL5"}
    assert looks["ZPCI"] == {"MODEL1"}
    assert looks["AK"] == {"MODEL1"}
    assert looks["NONE"] == {"MODEL5"}


def test_part_scales_spans_each_parts_scale_over_the_frames():
    animations = {
        "frames": [
            {"head": [0.5, 0.0, 0.0, 0.5, 0, 0]},
            {"head": [0.0, 0.8, -0.8, 0.0, 0, 0]},
            None,
        ]
    }
    assert doll_art.part_scales(animations) == {"head": (0.5, 0.8)}


def test_zoom_peak_sums_gridzoomers_steps():
    variables = json.loads(doll_art.BATTLE_MOTION.read_text())["zoomer"]["variables"]
    expected = (
        1
        + sum(
            variables["scaleChange"] / variables["zoomFactor"] * left
            for left in range(1, int(variables["zoomTime"]) + 1)
        )
        / 100
    )
    assert math.isclose(doll_art.zoom_peak(variables), expected)


def test_menu_dolls_reads_each_character_visuals_scale_and_rest_model():
    scene = (REPO_ROOT / "scenes/ui/menu/inventory_window.tscn").read_text("utf-8")
    dolls = doll_art.menu_dolls(scene)
    assert [model for model, _ in dolls] == ["MODEL1", "MODEL4"]
    assert math.isclose(dolls[0][1], 1.3075)
    assert math.isclose(dolls[1][1], math.sqrt(1.4249 * 1.2709))


def test_grid_covers_the_range_in_steps_with_1_first():
    assert [round(s, 4) for s in doll_art.grid(0.669, 0.8)] == [
        1.0,
        0.8696,
        0.7561,
        0.6575,
    ]
    assert [round(s, 4) for s in doll_art.grid(1.1, 1.2)] == [1.0, 1.15, 1.3225]


def test_distinct_drops_a_scale_whose_blurs_round_like_an_earlier_ones():
    # A blur of 2 at zoom 2 is 4 px at scale 1, 4.6 rounds to 5 at 0.87 and
    # 5.29 rounds to 5 at 0.756, so the last adds nothing.
    assert doll_art.distinct([1.0, 0.8696, 0.7561], [2.0]) == [1.0, 0.8696]
    assert doll_art.distinct([1.0, 0.8696, 0.7561], [7.0]) == [1.0, 0.8696, 0.7561]


def test_glow_scales_spans_the_models_that_wear_an_art():
    found = doll_art.glow_scales(
        ["M_SFOOT_HYDRA2", "M_CHEST_ULTI", "M_SFOOT_PLAIN"],
        {
            "M_SFOOT_HYDRA2": ([7.0, 7.0], []),
            "M_CHEST_ULTI": ([7.0, 7.0], []),
            "M_SFOOT_PLAIN": ([], []),
        },
        parts_by_code={"FOOT": ["foot1", "foot2"], "CHEST": ["chest"]},
        skins={"HYDRA2": {"MODEL8"}},
        looks={},
        scales={"MODEL8": {"foot1": (0.669, 0.669)}, "MODEL1": {"chest": (1.0, 1.0)}},
        sizes={},
        peak=1.0,
        menus=[("MODEL1", 1.3075)],
    )
    assert [round(s, 4) for s in found["M_SFOOT_HYDRA2"]] == [1.0, 0.7561, 0.6575]
    assert [round(s, 4) for s in found["M_CHEST_ULTI"]] == [1.0, 1.15, 1.3225]
    assert "M_SFOOT_PLAIN" not in found


def test_distinct_keeps_a_scale_whose_distance_differs_when_its_blurs_round_alike():
    assert doll_art.distinct([1.0, 0.8696, 0.7561], [2.0], [4.0]) == [
        1.0,
        0.8696,
        0.7561,
    ]
