# convert_menu_math's reading of the element bar formulas. The script sample
# copies the statement shapes of DefineSprite_3142/frame_1/DoAction.as with
# other numbers, so a test passes only when the parser reads each number from
# its own place. The SWF is built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, place2, swf, tag
from urchin_dev.convert import menu_math
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
