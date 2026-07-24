# Run: uv run convert_buffs
from __future__ import annotations

import json

from . import CONVERTED_JSON, DATA_JSON, swf_models


def parse_buff_block(buff_dict: dict):
    """Parse a buff creation block into a dictionary.

    Field indices decoded from frame42/sonny2_addNewBuffKrin.txt:
    addNewBuffKrin (array shape), applyBuffKrin (what each index does when a
    buff is applied/removed), and applyChangesKrin (how changeArray[0..11]
    gets folded into final stats). Indices 20/27/32/34 are defined in the
    KRINBUFF array but never read by either of those two functions - likely
    consumed by a dispel/stacking function not present in the extracted
    frames, so they're kept as raw unknown_field_N rather than guessed at.
    """

    buffs = []
    for idx, block in buff_dict.items():
        _members: dict = block.get("members")
        hack_move = _members.get("hack_move", {}).get("denseValues", {})

        buff = {
            "id": int(idx),
            "internal_name": _members.get("name"),
            "0_display_name": hack_move.get("0"),
            "1_element_type": hack_move.get("1"),
            # changeArray[0..11], folded into final stats by applyChangesKrin.
            "2_change_strength_flat": hack_move.get("2"),
            "3_change_strength_percent": hack_move.get("3"),
            "4_change_magic_flat": hack_move.get("4"),
            "5_change_magic_percent": hack_move.get("5"),
            "6_change_speed_flat": hack_move.get("6"),
            "7_change_speed_percent": hack_move.get("7"),
            "8_change_life_flat": hack_move.get("8"),
            "9_change_life_percent": hack_move.get("9"),
            "10_outgoing_damage_flat": hack_move.get("10"),  # DMG
            "11_outgoing_damage_percent": hack_move.get("11"),  # DMG2
            "12_incoming_damage_flat": hack_move.get("12"),  # IDMG
            # Dual purpose (applyBuffKrin s==11 special case): positive feeds
            # IDMG2 (extra % damage taken), negative feeds IDMGP (% damage
            # reduction, inverted into IDMGP2 = 1 - IDMGP).
            "13_incoming_damage_percent_or_reduction": hack_move.get("13"),
            # DOT/HOT tick (buffTicker), negative value = heal over time.
            "14_dot_hot_base_value": hack_move.get("14"),
            "15_focus_per_turn": hack_move.get("15"),  # DOTTICKERARRAY[9]
            "16_duration_turns": hack_move.get("16"),
            "17_stun_delta": hack_move.get("17"),
            "18_reflect_delta": hack_move.get("18"),
            "19_shield_flat": hack_move.get("19"),
            # Polarity: 1 = beneficial buff, -1 = harmful debuff, 0 = neutral.
            # Dispel moves only remove buffs whose polarity matches the move's
            # ability_two[19] (decoded 2026-07-18 from the dispel block in
            # frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt).
            "20_polarity": hack_move.get("20"),
            # Per-element offense/defense change - only applied when the
            # buff's own element_type (index 1) matches the loop element.
            "21_change_element_piercing": hack_move.get("21"),
            "22_change_element_defense": hack_move.get("22"),
            "23_change_element_piercing_percent": hack_move.get("23"),
            "24_change_element_defense_percent": hack_move.get("24"),
            "25_tooltip_description": hack_move.get("25"),
            "26_sswitch_delta": hack_move.get(
                "26"
            ),  # flips healing/damage on the affected unit
            # Unique/no-stack flag: 1 = re-applying refreshes the existing
            # instance's duration instead of stacking a second copy ("This
            # effect cannot stack" tooltips). Decoded 2026-07-18 from the
            # status-effect block in frame217's onClipEvent_enterFrame.txt.
            "27_is_unique": hack_move.get("27"),
            # DOT/HOT magnitude scaling off the CASTER's stats (ukcb4 in applyBuffKrin).
            "28_dot_scale_caster_strength": hack_move.get("28"),
            "29_dot_scale_caster_magic": hack_move.get("29"),
            "30_dot_scale_caster_speed": hack_move.get("30"),
            "31_visual_filter_index": hack_move.get("31"),  # FILTERSBUFFARRAY slot
            # Chance (0..1) that this buff RESISTS a dispel attempt ("has a N%
            # chance to resist being dispelled" tooltips). Decoded 2026-07-18
            # from the dispel block: dispel succeeds when
            # randf() >= dispel_resist_chance.
            "32_dispel_resist_chance": hack_move.get("32"),
            "33_dot_scale_caster_life": hack_move.get("33"),
            "34_unknown_field_34": hack_move.get("34"),
            "35_heal_mod_plus_delta": hack_move.get("35"),
            "36_heal_mod_minus_delta": hack_move.get("36"),
            "37_heal_mod_delta": hack_move.get("37"),
            # Shield magnitude scaling off the CASTER's stats.
            "38_shield_scale_caster_strength": hack_move.get("38"),
            "39_shield_scale_caster_magic": hack_move.get("39"),
            "40_shield_scale_caster_speed": hack_move.get("40"),
            "41_shield_scale_caster_life": hack_move.get("41"),
            # DOT/HOT magnitude scaling off the TARGET's own stats (ukcb2).
            "42_dot_scale_target_strength": hack_move.get("42"),
            "43_dot_scale_target_magic": hack_move.get("43"),
            "44_dot_scale_target_speed": hack_move.get("44"),
            "45_dot_scale_target_life": hack_move.get("45"),
            "46_idot_delta": hack_move.get("46"),  # incoming DOT multiplier
            "47_ihot_delta": hack_move.get("47"),  # incoming HOT multiplier
            "48_odot_delta": hack_move.get("48"),  # outgoing DOT multiplier
            "49_focus_change_delta": hack_move.get("49"),
            "50_silenced_delta": hack_move.get("50"),
        }

        buffs.append(buff)

    return buffs


def convert_to_json(input_file, output_file):
    """Convert full ActionScript buff definitions to JSON."""
    content: dict = swf_models.load_json(input_file)

    all_buffs = parse_buff_block(content.get("BUFFS").get("denseValues"))
    with output_file.open("w") as f:
        json.dump(all_buffs, f, indent=2)

    return len(all_buffs)


def main() -> None:
    buffs_count = convert_to_json(
        DATA_JSON / "swf_buffs.json", CONVERTED_JSON / "buffs.json"
    )
    print(f"Converted {buffs_count} buffs to JSON")


if __name__ == "__main__":
    main()
