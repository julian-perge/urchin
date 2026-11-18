# convert_buff_looks's reading of frame_42's krinChangeColor, its GlowFilter
# lists and applyChangesKrin, on scripts written by hand, so no test needs the
# AS export.
from __future__ import annotations

import json

import pytest
from urchin_dev import CONVERTED_JSON
from urchin_dev.convert import buff_looks

COLORS = """\
function krinChangeColor(target, colorType)
{
   if(colorType == "Enrage")
   {
      _loc6_ = new flash.geom.ColorTransform();
      _loc6_.redOffset = 30;
      _loc6_.greenOffset = -130;
      _loc6_.blueOffset = -130;
   }
   if(colorType == "Normal")
   {
      _loc7_ = new flash.geom.ColorTransform();
      _loc7_.redOffset = 0;
      _loc7_.greenOffset = 0;
      _loc7_.blueOffset = 0;
   }
   if(colorType == "Poison")
   {
      _loc5_ = new flash.geom.ColorTransform();
      _loc5_.redOffset = -50;
      _loc5_.greenOffset = 0;
      _loc5_.blueOffset = -225;
   }
}
var KrinFilterNone = new Array();
var KFIce1 = new flash.filters.GlowFilter(16777215,1,14,14,1.4000000000000001,1,true,true);
var KFIce2 = new flash.filters.GlowFilter(3381759,1,24,24,3.8000000000000003,1,false,false);
var KrinFilterFrost = new Array();
KrinFilterFrost.push(KFIce1);
KrinFilterFrost.push(KFIce2);
var KFRed1 = new flash.filters.GlowFilter(16737792,1,10,10,1.7,1,false,false);
var KrinFilterRed = new Array();
KrinFilterRed.push(KFRed1);
"""

APPLY = """\
function applyChangesKrin(ukcb)
{
   statusOfC = "Normal";
   statusOfF = KrinFilterNone;
   statusOfM = "STANDARD";
   if(ukcb.FILTERSBUFFARRAY[1] > 0)
   {
      statusOfC = "Poison";
   }
   if(ukcb.FILTERSBUFFARRAY[18] > 0)
   {
      statusOfF = KrinFilterRed;
   }
   if(ukcb.FILTERSBUFFARRAY[4] > 0)
   {
      statusOfM = "BARON";
   }
   if(ukcb.FILTERSBUFFARRAY[16] > 0)
   {
      statusOfM = "HOUND";
   }
   if(ukcb.FILTERSBUFFARRAY[7] > 0)
   {
      statusOfC = "Enrage";
   }
   if(ukcb.FILTERSBUFFARRAY[2] > 0)
   {
      statusOfF = KrinFilterFrost;
   }
   if(ukcb.dressNow != statusOfM)
   {
      changeForm(statusOfM,ukcb.playerID);
   }
}
function changeForm(changeTo, p_id)
{
   if(changeTo == "BARON")
   {
      dressChar("BARON",p_id,"","MODEL1","ZOMBIE2","M","","XADER2","");
   }
   else if(changeTo == "STANDARD")
   {
      dressChar("STANDARD",p_id,"STANDARD","model","skin","gender","hair","wep1","wep2");
   }
   else if(changeTo == "HOUND")
   {
      dressChar("HOUND",p_id,"","MODEL5","HOUND","M","","NONE","NONE");
   }
}
"""


def looks() -> dict:
    return buff_looks.read_looks(COLORS, APPLY)


def test_a_color_is_the_three_offsets_krinChangeColor_gives_it():
    assert looks()["colors"] == {
        "Enrage": [30, -130, -130],
        "Normal": [0, 0, 0],
        "Poison": [-50, 0, -225],
    }


def test_a_filter_is_its_glows_in_the_order_they_are_pushed():
    frost = looks()["filters"]["Frost"]
    assert [glow["color"] for glow in frost] == ["ffffff", "3399ff"]
    assert frost[0] == {
        "color": "ffffff",
        "alpha": 1,
        "blur_x": 14,
        "blur_y": 14,
        "strength": 1.4,
        "quality": 1,
        "inner": True,
        "knockout": True,
    }
    assert frost[1]["inner"] is False and frost[1]["knockout"] is False


def test_the_none_filter_has_no_glows():
    assert looks()["filters"]["None"] == []


def test_the_defaults_are_what_applyChangesKrin_starts_from():
    result = looks()
    assert result["default_color"] == "Normal"
    assert result["default_filter"] == "None"


def test_a_state_list_keeps_the_order_the_ifs_run_in_so_the_last_one_wins():
    result = looks()
    assert result["color_by_index"] == [[1, "Poison"], [7, "Enrage"]]
    assert result["filter_by_index"] == [[18, "Red"], [2, "Frost"]]


def test_a_form_is_what_changeForm_hands_dressChar():
    assert looks()["forms"] == {
        "BARON": {
            "model": "MODEL1",
            "skin": "ZOMBIE2",
            "gender": "M",
            "hair": "",
            "weapon1": "XADER2",
            "weapon2": "",
        },
        "HOUND": {
            "model": "MODEL5",
            "skin": "HOUND",
            "gender": "M",
            "hair": "",
            "weapon1": "NONE",
            "weapon2": "NONE",
        },
    }


def test_the_standard_form_is_the_default_and_holds_no_dress_of_its_own():
    result = looks()
    assert result["default_form"] == "STANDARD"
    assert "STANDARD" not in result["forms"]


def test_the_form_list_keeps_the_order_the_ifs_run_in_so_the_last_one_wins():
    assert looks()["form_by_index"] == [[4, "BARON"], [16, "HOUND"]]


def test_a_state_that_names_an_unknown_form_is_refused():
    broken = APPLY.replace('statusOfM = "HOUND"', 'statusOfM = "MUMMY"')
    with pytest.raises(ValueError, match="MUMMY"):
        buff_looks.read_looks(COLORS, broken)


def test_a_form_that_draws_an_armor_layer_is_refused():
    broken = APPLY.replace(
        'dressChar("BARON",p_id,"",', 'dressChar("BARON",p_id,"BARON",'
    )
    with pytest.raises(ValueError, match="BARON"):
        buff_looks.read_looks(COLORS, broken)


def test_a_state_that_names_an_unknown_filter_is_refused():
    broken = APPLY.replace("KrinFilterRed", "KrinFilterTeal")
    with pytest.raises(ValueError, match="KrinFilterTeal"):
        buff_looks.read_looks(COLORS, broken)


def test_a_state_that_names_an_unknown_color_is_refused():
    broken = APPLY.replace('"Enrage"', '"Purple"')
    with pytest.raises(ValueError, match="Purple"):
        buff_looks.read_looks(COLORS, broken)


def test_a_glow_with_two_passes_is_refused():
    broken = COLORS.replace(
        "GlowFilter(16737792,1,10,10,1.7,1,", "GlowFilter(16737792,1,10,10,1.7,3,"
    )
    with pytest.raises(ValueError, match="KrinFilterRed"):
        buff_looks.read_looks(broken, APPLY)


def test_a_glow_with_a_different_blur_each_way_is_refused():
    broken = COLORS.replace(
        "GlowFilter(16737792,1,10,10,", "GlowFilter(16737792,1,10,20,"
    )
    with pytest.raises(ValueError, match="KrinFilterRed"):
        buff_looks.read_looks(broken, APPLY)


# The committed output, which the Fighter presenter reads.
def test_the_committed_output_holds_the_poison_color_and_the_frost_filter():
    committed = json.loads((CONVERTED_JSON / "buff_looks.json").read_text())
    assert committed["colors"]["Poison"] == [-50, 0, -225]
    assert len(committed["filters"]["Frost"]) == 2
    assert committed["filter_by_index"][-1] == [2, "Frost"]
    assert committed["forms"]["BARON"]["skin"] == "ZOMBIE2"
    assert committed["form_by_index"][-1] == [19, "GHOSTBOSS2"]
