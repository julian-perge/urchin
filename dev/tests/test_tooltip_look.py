# extract_tooltip_look's readers, on small ActionScript samples and on a shape
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, swf, tag
from urchin_dev.swf.extract import tooltip_look
from urchin_dev.swf.swf_index import TAG_DEFINE_SHAPE3, first_gradient, parse_swf

CHANGE_COLOR = """
function krinChangeColor(target, colorType)
{
   if(colorType == "Common")
   {
      _loc3_.redOffset = 0;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = 0;
   }
   if(colorType == "Uncommon")
   {
      _loc3_.redOffset = -62;
      _loc3_.greenOffset = -51;
      _loc3_.blueOffset = 0;
   }
   if(colorType == "Rare")
   {
      _loc3_.redOffset = 86;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = -164;
   }
   if(colorType == "Orange")
   {
      _loc3_.redOffset = 126;
      _loc3_.greenOffset = 15;
      _loc3_.blueOffset = -200;
   }
   if(colorType == "Unique")
   {
      _loc3_.redOffset = -67;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = -159;
   }
   if(colorType == "Hit")
   {
      _loc4_.redOffset = 255;
      _loc4_.greenOffset = 255;
      _loc4_.blueOffset = 255;
   }
}
"""

PLAIN_LAYOUT = """
if(_root._xmouse < 570)
{
   scaffold = 13;
}
else
{
   scaffold = -183;
}
if(_root._ymouse > 500)
{
   scaffold2 = -50;
}
else
{
   scaffold2 = 0;
}
this.createTextField("my_txt",0,scaffold,21 + scaffold2,170,120);
this.createTextField("my_txt2",1,scaffold,scaffold2,170,120);
"""

ITEM_LAYOUT = """
if(_root._xmouse < 570)
{
   scaffold = 13;
}
else
{
   scaffold = -213;
}
this.createTextField("my_txt2",90,scaffold,0,200,120);
"""

PASS = """
onClipEvent(load){
   if(!_root.turnBasedKrin)
   {
      thinger1 = "No ability selected!";
      thinger2 = "First select your target then choose an ability to use.";
      thinger3 = "Cannot cancel during action.";
   }
   else
   {
      thinger1 = "No ability selected!";
      thinger2 = "You may click here to skip your turn.";
      thinger3 = "Cannot skip during action.";
   }
}
"""

PICK = """
         _root.krinToMove.toolTipTitle = mAry5[0];
         _root.krinToMove.toolTip = "You will use this ability on " + _root["playerKrin" + _root.theEnemyToMoveVS].playerName + ". Click to cancel this ability.";
"""


def test_rarity_add_reads_each_rarity_and_skips_other_names():
    terms = tooltip_look.rarity_add(CHANGE_COLOR)
    assert terms == {
        "Common": [0, 0, 0],
        "Uncommon": [-62, -51, 0],
        "Rare": [86, 0, -164],
        "Orange": [126, 15, -200],
        "Unique": [-67, 0, -159],
    }


def test_rarity_add_raises_on_a_missing_rarity_or_term():
    with pytest.raises(ValueError, match="no Rare block"):
        tooltip_look.rarity_add(CHANGE_COLOR.replace('"Rare"', '"Rarer"'))
    with pytest.raises(ValueError, match="Uncommon"):
        tooltip_look.rarity_add(CHANGE_COLOR.replace("-51;", "x;"))


def test_layout_reads_the_offsets_and_the_move_up_of_the_plain_layout():
    assert tooltip_look.layout(PLAIN_LAYOUT, "GO") == {
        "far_x": -183,
        "field_width": 170,
        "low_shift_y": -50,
        "mouse_x_limit": 570,
        "mouse_y_limit": 500,
        "near_x": 13,
    }


def test_layout_without_a_move_up_has_no_y_keys():
    assert tooltip_look.layout(ITEM_LAYOUT, "GO4") == {
        "far_x": -213,
        "field_width": 200,
        "mouse_x_limit": 570,
        "near_x": 13,
    }


def test_layout_raises_on_lines_it_cannot_read():
    with pytest.raises(ValueError, match="GO4"):
        tooltip_look.layout(
            ITEM_LAYOUT.replace("scaffold = -213;", "scaffold = far;"), "GO4"
        )
    with pytest.raises(ValueError, match="scaffold2"):
        tooltip_look.layout(
            PLAIN_LAYOUT.replace("scaffold2 = -50;", "scaffold2 = low;"), "GO"
        )


def test_detail_delay_frames_reads_the_hitter_threshold():
    script = "if(hitter == 5)\n{\n}\nelse\n{\n   hitter++;\n}"
    assert tooltip_look.detail_delay_frames(script) == 5
    with pytest.raises(ValueError):
        tooltip_look.detail_delay_frames("hitter++;")


def test_pass_texts_reads_both_modes_and_the_pick():
    assert tooltip_look.pass_texts(PASS, PICK) == {
        "picked": "You will use this ability on %s. Click to cancel this ability.",
        "real_time": {
            "action": "Cannot cancel during action.",
            "idle": "First select your target then choose an ability to use.",
        },
        "title": "No ability selected!",
        "turn_based": {
            "action": "Cannot skip during action.",
            "idle": "You may click here to skip your turn.",
        },
    }


def test_picked_text_raises_on_a_percent_sign():
    with pytest.raises(ValueError, match="holds a %"):
        tooltip_look.picked_text(PICK.replace("this ability.", "this 100% ability."))


def test_pass_texts_raises_when_the_titles_differ():
    broken = PASS.replace(
        'thinger1 = "No ability selected!";', 'thinger1 = "Other";', 1
    )
    with pytest.raises(ValueError, match="titles"):
        tooltip_look.pass_texts(broken, PICK)


def gradient_shape(cid: int) -> bytes:
    """A DefineShape3 over (0, 0) to (600, 600) twips whose one fill is a linear
    gradient turned 90 degrees, with two stops."""
    rect = bits((11, 5), (0, 11), (600, 11), (0, 11), (600, 11))
    # 0.018310546875 is 1200 in 16.16 fixed point.
    matrix = bits(
        (0, 1), (1, 1), (13, 5), (1200, 13), (-1200, 13),
        (11, 5), (300, 11), (300, 11),
    )  # fmt: skip
    stops = bytes([0, 255, 255, 255, 255, 60, 170, 170, 170, 217])
    fill = b"\x01\x10" + matrix + bytes([2]) + stops
    return tag(TAG_DEFINE_SHAPE3, struct.pack("<H", cid) + rect + fill + b"\0\0\0")


def test_first_gradient_reads_the_matrix_and_the_stops():
    index = parse_swf(swf(gradient_shape(7)))
    matrix, stops = first_gradient(index, 7)
    assert matrix == (1.0, 1200 / 65536, -1200 / 65536, 1.0, 300, 300)
    assert stops == ((0, (255, 255, 255, 255)), (60, (170, 170, 170, 217)))


SELL_LINE = 'x = MENU[4] + " €" + Math.ceil(_root["KRINITEM" + _root.Krin.mouseItem][5] * 0.15);'


def test_sell_ratio_reads_the_share_both_scripts_use():
    assert tooltip_look.sell_ratio(SELL_LINE, SELL_LINE) == 0.15


def test_sell_ratio_raises_when_the_tooltip_and_the_press_differ():
    with pytest.raises(ValueError, match="names 0.15"):
        tooltip_look.sell_ratio(SELL_LINE, SELL_LINE.replace("0.15", "0.2"))
