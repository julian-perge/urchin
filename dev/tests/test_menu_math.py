# convert_menu_math's reading of the element bar formulas. The script sample
# copies the statement shapes of DefineSprite_3142/frame_1/DoAction.as with
# other numbers, so a test passes only when the parser reads each number from
# its own place. The SWF is built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, place2, swf, tag
from urchin_dev.convert import menu_math
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

LEVEL = "_root.Krin.LevelStats[_root.Krin.MenuPlayerSelect]"
PIERCING = f"""
      yut_per2[wefjnew] = _root.Krin["PerSets" + _root.Krin.MenuPlayerSelect][wefjnew] + Math.ceil(90 + 12 * {LEVEL});
      yut_def2[wefjnew] = _root.Krin["DefSets" + _root.Krin.MenuPlayerSelect][wefjnew] + Math.ceil(90 + 12 * {LEVEL});
      AVGNUMC = 90 + 12 * {LEVEL};
      CRITCALC_X = yut_per2[wefjnew] / AVGNUMC;
      nT1 = 0.5 * Math.pow(CRITCALC_X + 1,4) - 0.25 * Math.pow(CRITCALC_X + 1,3) + 2.5 * Math.pow(CRITCALC_X + 1,2) - 1.5 * (CRITCALC_X + 1) + 0.75;
      nT2 = 14 * (yut_per2[wefjnew] / (90 + 12 * {LEVEL}));
      nT3 = 0.06 * (CRITCALC_X - 2);
      if(perBarShow["bar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {{
      }}
      if(perBarShow["gbar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {{
      }}
"""
DEFENSE = f"""
      CRITCALC_X = yut_def2[wefjnew] / AVGNUMC;
      DEF_FACTOR = 1;
      DEF_CALC_ER = 1 / CRITCALC_X;
      if(DEF_CALC_ER > 1)
      {{
         DEF_FACTOR = 0;
      }}
      if(DEF_CALC_ER < 0.8)
      {{
         DEF_FACTOR = 3;
      }}
      if(DEF_CALC_ER < 0.30000000000000004)
      {{
         DEF_FACTOR = 6;
      }}
      nT4 = 0.5 * Math.pow(CRITCALC_X + 1,4) - 0.25 * Math.pow(CRITCALC_X + 1,3) + 2.5 * Math.pow(CRITCALC_X + 1,2) - 1.5 * (CRITCALC_X + 1) + 0.75;
      nT5 = 14 * (yut_def2[wefjnew] / (90 + 12 * {LEVEL}));
      nT6 = 0.06 * (CRITCALC_X - 2);
      if(defBarShow["bar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {{
      }}
      if(defBarShow["gbar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {{
      }}
"""
SETUP = """
   perBarShow["gbar" + wefjnew].saveH = perBarShow["bar" + wefjnew]._height / 50;
"""
SAMPLE = PIERCING + DEFENSE + SETUP


def test_the_parser_reads_every_number_from_its_own_statement():
    assert menu_math.parse_element_bars(SAMPLE) == {
        "average": {"base": 90, "per_level": 12},
        "value": {"average_rounding": "ceil"},
        "bar_quartic": [0.5, -0.25, 2.5, -1.5, 0.75],
        "gbar": {"factor": 14, "divisor": 50},
        "xbar": {"factor": 0.06, "offset": -2},
        "capped": ["bar", "gbar"],
        "defense_tips": {
            "default": 1,
            "rules": [
                {"compare": ">", "threshold": 1, "tip": 0},
                {"compare": "<", "threshold": 0.8, "tip": 3},
                {"compare": "<", "threshold": 0.30000000000000004, "tip": 6},
            ],
        },
    }


def test_a_defense_term_that_differs_from_its_piercing_term_is_refused():
    changed = SAMPLE.replace("nT6 = 0.06", "nT6 = 0.07")
    with pytest.raises(ValueError, match="nT6"):
        menu_math.parse_element_bars(changed)


def test_an_average_that_differs_between_statements_is_refused():
    changed = SAMPLE.replace("AVGNUMC = 90", "AVGNUMC = 91")
    with pytest.raises(ValueError, match="average"):
        menu_math.parse_element_bars(changed)


def test_a_missing_statement_is_refused_by_name():
    changed = SAMPLE.replace("nT2 = 14", "nT2 = ")
    with pytest.raises(ValueError, match="nT2"):
        menu_math.parse_element_bars(changed)


def test_a_defense_value_rounded_another_way_is_refused():
    defense = '"DefSets" + _root.Krin.MenuPlayerSelect][wefjnew] + Math.'
    changed = SAMPLE.replace(defense + "ceil", defense + "floor")
    with pytest.raises(ValueError, match="yut_def2"):
        menu_math.parse_element_bars(changed)


def test_a_missing_x_statement_is_refused_by_name():
    changed = SAMPLE.replace("CRITCALC_X = yut_def2", "CRITCALC_X = yut_def3")
    with pytest.raises(ValueError, match="x of yut_def2"):
        menu_math.parse_element_bars(changed)


def matrix(scale_y: float, skew: float = 0.0) -> bytes:
    """A matrix with x scale 1, the given y scale and both skew terms, as
    16.16 values in 20 bits."""
    fields = [(1, 1), (20, 5), (65536, 20), (round(scale_y * 65536), 20)]
    if skew:
        fixed = round(skew * 65536)
        fields += [(1, 1), (20, 5), (fixed, 20), (fixed, 20)]
    else:
        fields += [(0, 1)]
    return bits(*fields, (0, 5))


def bar_swf(holder_matrix: bytes) -> bytes:
    """A 6000 twip shape placed with holder_matrix inside "inner", inside a
    bar clip at y scale 2, in sprite 13."""
    rect = bits((14, 5), (0, 14), (220, 14), (0, 14), (6000, 14))
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + rect + b"\0\0\0\0")
    holder = struct.pack("<HH", 11, 1) + place2(1, cid=10, matrix=holder_matrix)
    holder += tag(TAG_SHOW_FRAME) + tag(TAG_END)
    clip = struct.pack("<HH", 12, 1) + place2(1, cid=11, name="inner")
    clip += tag(TAG_SHOW_FRAME) + tag(TAG_END)
    bars = struct.pack("<HH", 13, 1) + place2(3, cid=12, name="ybar0")
    bars += place2(5, cid=12, name="bar0", matrix=matrix(2.0))
    bars += tag(TAG_SHOW_FRAME) + tag(TAG_END)
    return swf(
        shape,
        tag(TAG_DEFINE_SPRITE, holder),
        tag(TAG_DEFINE_SPRITE, clip),
        tag(TAG_DEFINE_SPRITE, bars),
        tag(TAG_SHOW_FRAME),
    )


def test_the_save_height_is_the_bar_shape_height_through_each_scale():
    # At y scale 0.25 and then 2, the 6000 twip shape is 3000 twips, which is
    # 150 px.
    index = parse_swf(bar_swf(matrix(0.25)))
    assert menu_math.bar_save_height(index, 13) == 150.0


def test_a_skewed_bar_shape_is_refused():
    index = parse_swf(bar_swf(matrix(0.25, skew=0.1)))
    with pytest.raises(ValueError, match="character 10 is placed rotated or skewed"):
        menu_math.bar_save_height(index, 13)


# The statement shapes of one victory experience row's scripts
# (DefineSprite_3142/frame_9/PlaceObject3_3002_*), with other numbers.
ROW_LOAD = """onClipEvent(load){
   prx = _root.Krin.friendlySlotsFFTT[0];
   if(prx == undefined)
   {
      _visible = false;
   }
   else
   {
      setLimiter = 24;
      adderPer = _root.Krin.totalXP / setLimiter;
   }
}
"""
PLAYER_ROW_LOAD = ROW_LOAD.replace("setLimiter = 24", "setLimiter = sLmT2 = 24")
ROW_ENTER_FRAME = """onClipEvent(enterFrame){
   if(prx != undefined)
   {
      if(setLimiter > 0)
      {
         if(_root.Krin.LevelStats[prx] < 40)
         {
            setLimiter--;
            exp += adderPer;
            bar._width = exp / 100 * 88.4;
            if(exp >= 100)
            {
               exp -= 100;
               bar.gotoAndStop("level");
               bar._width = 88.4;
            }
         }
      }
   }
}
"""


def test_the_row_parser_reads_the_frames_the_bar_width_and_the_level_cap():
    rows = [(ROW_LOAD, ROW_ENTER_FRAME), (PLAYER_ROW_LOAD, ROW_ENTER_FRAME)]
    assert menu_math.parse_victory_rows(rows) == {
        "frames": 24,
        "bar_width": 88.4,
        "level_cap": 40,
    }


def test_rows_that_disagree_are_refused():
    other = ROW_ENTER_FRAME.replace("< 40", "< 41")
    rows = [(ROW_LOAD, ROW_ENTER_FRAME), (ROW_LOAD, other)]
    with pytest.raises(ValueError, match="level_cap"):
        menu_math.parse_victory_rows(rows)


def test_a_full_bar_width_that_differs_from_the_scaled_one_is_refused():
    changed = ROW_ENTER_FRAME.replace("bar._width = 88.4;", "bar._width = 88.5;")
    with pytest.raises(ValueError, match="bar_width"):
        menu_math.parse_victory_rows([(ROW_LOAD, changed)])


def test_a_row_that_does_not_divide_the_gain_by_its_frames_is_refused():
    changed = ROW_LOAD.replace("totalXP / setLimiter", "totalXP / 20")
    with pytest.raises(ValueError, match="adderPer"):
        menu_math.parse_victory_rows([(changed, ROW_ENTER_FRAME)])


BAR_LOAD = """onClipEvent(load){
   _width = _root.Krin.ExpSets[_root.Krin.MenuPlayerSelect] / 100 * 88.4;
   _parent.exp2 = Math.round(_root.Krin.ExpSets[_root.Krin.MenuPlayerSelect]) + "%";
}
"""
BAR_ENTER_FRAME = BAR_LOAD.replace("onClipEvent(load)", "onClipEvent(enterFrame)")


def test_the_experience_bar_parser_reads_the_width_of_the_full_bar():
    assert menu_math.parse_experience_bar(BAR_LOAD, BAR_ENTER_FRAME) == {"width": 88.4}


def test_an_experience_bar_whose_two_scripts_disagree_is_refused():
    changed = BAR_ENTER_FRAME.replace("88.4", "88.5")
    with pytest.raises(ValueError, match="width"):
        menu_math.parse_experience_bar(BAR_LOAD, changed)


def test_an_experience_bar_script_that_does_not_scale_the_width_is_refused():
    changed = BAR_LOAD.replace("_width =", "_height =")
    with pytest.raises(ValueError, match="width"):
        menu_math.parse_experience_bar(changed, changed)


# The statements that colour the bar layers
# (DefineSprite_3142/frame_1/DoAction.as:196-220), with the layer names of one
# block. The script colours the inner shape of ybar and bar, the clip of gbar,
# and does not colour xbar.
TINTS = """
   var my_colorKKCCXX = new Color(perBarShow["bar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(perBarShow["gbar" + wefjnew]);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(perBarShow["ybar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(defBarShow["bar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(defBarShow["gbar" + wefjnew]);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(defBarShow["ybar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
"""


def test_the_tint_parser_says_what_each_layer_colours():
    assert menu_math.parse_layer_tints(TINTS) == {
        "bar": "inner",
        "gbar": "clip",
        "ybar": "inner",
    }


def test_a_layer_tinted_in_one_block_only_is_refused():
    changed = TINTS.replace(
        'defBarShow["gbar" + wefjnew]', 'defBarShow["xbar" + wefjnew]'
    )
    with pytest.raises(ValueError, match="piercing and defense"):
        menu_math.parse_layer_tints(changed)


def test_a_tint_that_is_not_the_element_color_is_refused():
    changed = TINTS.replace("elementColorArray[wefjnew]", "elementColorArray[0]", 1)
    with pytest.raises(ValueError, match="elementColorArray"):
        menu_math.parse_layer_tints(changed)


def placed(name: str, color_transform=None):
    return timeline.Layer(character_id=12, name=name, color_transform=color_transform)


def test_a_dimmed_layer_is_its_multiplier_over_256_with_no_add():
    eight = [placed(f"ybar{k}", (26, 26, 26, 256, 0, 0, 0, 0)) for k in range(8)]
    assert menu_math.layer_look(eight, "ybar", "inner", None) == {
        "tint": "inner",
        "multiplier": 26 / 256,
        "add": 0.0,
        "glow": None,
    }


def test_a_brightened_layer_adds_its_offset_over_255():
    eight = [
        placed(f"xbar{k}", (256, 256, 256, 256, 100, 100, 100, 0)) for k in range(8)
    ]
    look = menu_math.layer_look(eight, "xbar", None, None)
    assert (look["multiplier"], look["add"]) == (1.0, 100 / 255)


def test_a_layer_with_no_colour_transform_is_left_as_it_is():
    eight = [placed(f"bar{k}") for k in range(8)]
    look = menu_math.layer_look(eight, "bar", "inner", None)
    assert (look["multiplier"], look["add"]) == (1.0, 0.0)


def test_eight_bars_that_are_placed_with_different_transforms_are_refused():
    eight = [placed(f"bar{k}", (77, 77, 77, 256, 0, 0, 0, 0)) for k in range(8)]
    eight[3] = placed("bar3", (78, 77, 77, 256, 0, 0, 0, 0))
    with pytest.raises(ValueError, match="bar"):
        menu_math.layer_look(eight, "bar", "inner", None)


def test_a_colour_transform_that_changes_alpha_is_refused():
    eight = [placed(f"bar{k}", (256, 256, 256, 128, 0, 0, 0, 0)) for k in range(8)]
    with pytest.raises(ValueError, match="alpha"):
        menu_math.layer_look(eight, "bar", "inner", None)


# The Glow record of sprite 2872's "inner": white, blur 9 by 9, strength 1.797,
# the source drawn over it, three passes.
GLOW = b"\x02\xff\xff\xff\xff\x00\x00\t\x00\x00\x00\t\x00\xcc\x01#"


def test_a_glow_is_its_color_blur_strength_and_passes():
    assert menu_math.glow_look(GLOW) == {
        "color": "#ffffff",
        "alpha": 1.0,
        "blur_x": 9.0,
        "blur_y": 9.0,
        "strength": 0x01CC / 256,
        "passes": 3,
        "composite_source": True,
    }


def test_a_drop_shadow_on_a_bar_is_refused():
    shadow = bytes([0]) + GLOW[1:5] + bytes(16) + bytes([0, 1, 0x20 | 3])
    with pytest.raises(ValueError, match="Glow"):
        menu_math.glow_look(shadow)


def test_an_inner_or_knockout_glow_is_refused():
    inner = GLOW[:-1] + bytes([0x80 | 0x20 | 3])
    with pytest.raises(ValueError, match="inner or knockout"):
        menu_math.glow_look(inner)


# The statement of frame_41/DoAction_2.as that gives every element its colour,
# in the order of the elements.
COLORS = 'elementColorArray = ["0xC40000","0xFB95C8","0x68CBF4","0xFF6600","0xFFCC00","0x856B47","0x664D80","0x508349"];'


def test_the_colour_parser_reads_the_eight_element_colours_in_order():
    assert menu_math.parse_element_colors("junk;\n" + COLORS + "\nmore;") == [
        "#c40000",
        "#fb95c8",
        "#68cbf4",
        "#ff6600",
        "#ffcc00",
        "#856b47",
        "#664d80",
        "#508349",
    ]


def test_a_colour_list_of_another_length_is_refused():
    with pytest.raises(ValueError, match="8"):
        menu_math.parse_element_colors(COLORS.replace(',"0x508349"', ""))


def test_a_colour_that_is_not_six_hex_digits_is_refused():
    with pytest.raises(ValueError, match="0x50834"):
        menu_math.parse_element_colors(COLORS.replace("0x508349", "0x50834"))


def test_a_script_with_no_colour_array_is_refused():
    with pytest.raises(ValueError, match="elementColorArray"):
        menu_math.parse_element_colors("elementMainArray = [];")
