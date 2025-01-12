import json


def parse_move_block(move_dict: dict):
    """Parse a move creation block into a dictionary."""

    moves = []
    for idx, block in move_dict.items():
        _move_block: dict[str, str | int | dict] = block.get("members")

        ability_two = _move_block.get("ability_two", {}).get("denseValues", {})

        element_types_affected_15 = ability_two.get("15")
        # Only Baron Brixius unit uses move 539, value set as `-100`
        if isinstance(element_types_affected_15, dict):
            element_types_affected_15 = list(element_types_affected_15.get("denseValues", {}).values())

        ab_two_dict = {
            "0_damage_element_type": ability_two.get("0"),
            "1_base_strength_bonus": ability_two.get("1"),
            "2_strength_damage_multiplier": ability_two.get("2"),
            "3_base_magic_bonus": ability_two.get("3"),
            "4_magic_damage_multiplier": ability_two.get("4"),
            "5_base_speed_bonus": ability_two.get("5"),
            "6_speed_damage_multiplier": ability_two.get("6"),
            "7_effect_duration_turns": ability_two.get("7"),
            "8_base_damage_multiplier": ability_two.get("8"),
            "9_focus_amount_change": ability_two.get("9"),  # positive for gain, negative for loss
            "10_focus_effect_multiplier": ability_two.get("10"),
            "11_focus_scaling_modifier": ability_two.get("11"),
            "12_heal_percent_max_health": ability_two.get("12"),  # for healing abilities
            "13_status_effect_id": ability_two.get("13"),
            "14_effect_proc_chance": ability_two.get("14"),
            "15_element_types_affected": element_types_affected_15,
            "16_dispel_buff_count": ability_two.get("16"),  # number of buffs to remove
            "17_tooltip_description": ability_two.get("17"),
            "18_tooltip_cost": ability_two.get("18"),
            "19_status_effect_tick_rate": ability_two.get("19"),
            "20_is_multi_target": bool(ability_two.get("20")),  # 0 = single target, 1 = multi
            "21_effect_target": ability_two.get("21"),  # 0 = target, 1 = self
            "22_buff_application_chance": ability_two.get("22"),
            "23_secondary_element_type": ability_two.get("23"),
            "24_required_buff_count": ability_two.get("24"),
            "25_focus_cost_multiplier": ability_two.get("25"),
        }

        move = {
            "id_name": _move_block.get("id_name"),  # a, KRINABILITY1
            "0_display_name": _move_block.get("a_0"),  # a
            "1_id": _move_block.get("b_1"),  # MoveCount

            # Heal Move, id 235, Safe Guard
            # can target self or allies, not enemies
            # "Heal a friendly unit for 5% of your maximum Health..."
            # 2_move_type    == 1
            # 3_target       == 0 (can target self, or allies)
            # 4              == 1 (1 equals friendly?)

            # Heal Move, id 241, Ice Wall
            # can target self, allies, or enemies
            # "Encases the target in Ice..."
            # 2_move_type    == 1
            # 3_target       == 1 (can target self, allies, or enemies)
            # 4              == 1 (1 equals friendly?)

            # Heal Move, id 243, Mirage1
            # cannot target self or enemies, only allies
            # "Make an allied unit appear stronger that it actually is, lowering the chance that it will be targeted for an attack...",
            # 2_move_type    == 0 (cannot target self or enemies)
            # 3_target       == 1 (targeting ally)
            # 4              == 1
            #
            # Heal Move, id 251, Guardian Form
            # can only target self, not enemies or allies
            # "Morph into a resilient icy guardian. Reduces damage taken by 30..."
            # 2_move_type    == 1
            # 3_target       == 0 (targets self)
            # 4              == 0

            # self-targeting flag, (1 = can target self, 0 = cannot)
            "2_can_target_self": bool(_move_block.get("c_2")),  # c, always 0 or 1
            # enemy/ally targeting flag, (1 = can target other units, 0 = cannot)
            "3_can_target_others": bool(_move_block.get("d_3")),  # d, always 0 or 1
            # target type flag, (1 = targets allies, 0 = targets enemies)
            "4_targets_allies": bool(_move_block.get("e_4")),  # e, always 0 or 1
            "5_focus_resource_cost": _move_block.get("f_5"),  # f

            # index 6, g, seems to only ever be a value of 0, and is checked when attempting to use a move that costs health
            # if(rovnrevbnr.LIFEN <= mAry5[6] + Math.round(rovnrevbnr.LIFEU * mAry5[16]))
            # {
            # 		checkPassforKrinMove = false;
            # 		KrinCombatText.combatTexter = "You cannot use this move because you don\'t have enough Health.";
            # }
            # if(rovnrevbnr.LIFEN <= 0 + Math.round(rovnrevbnr.LIFEU * health_cost_percent_of_move))
            "6_deprecated_life_check": _move_block.get("g_6"),  # g, legacy value always 0
            "7_cooldown_turns": _move_block.get("h_7"),  # h
            "8_hotbar_slot_limit": _move_block.get("i_8"),  # i, 1,2,3,4,5,8
            "9_combat_speed_modifier": _move_block.get("j_9"),  # j
            "10_attack_animation_type": _move_block.get("k_10"),  # k, "Melee", "Missile", "Shock"
            "11_visual_effect_color": _move_block.get("l_11"),  # l
            "12_animation_model_name": _move_block.get("m_12"),  # m
            "13_impact_effect_name": _move_block.get("n_13"),  # n
            "14_effect_category": _move_block.get("o_14"),  # o, Full damage / Heal / Focus
            "15_deprecated_flag": _move_block.get("p_15"),  # p, legacy value always 1
            "16_health_cost_percentage": _move_block.get("q_16"),  # q
            "17_localized_name": _move_block.get("r_17"),  # r, _root.KrinLang[KLangChoosen].SKILLNAME[skill_name];, tooltip title
            "18_sound_effect_name": _move_block.get("s_18"),  # s
            "ability_two": ab_two_dict,
        }

        moves.append(move)

    return moves


def convert_to_json(input_file, output_file):
    """Convert full ActionScript move definitions to JSON."""
    with open(input_file, "r") as f:
        content: dict = json.load(f)

    all_moves = parse_move_block(content.get("ABILITIES").get("denseValues"))
    # Write to JSON file
    with open(output_file, "w") as f:
        json.dump(all_moves, f, indent=2)

    with open("converted_json/converted_moves_by_id.json", 'w') as f2:
        ids_objs = {}
        for _i in all_moves:
            _val = f"{_i.get('0_display_name')}_{_i.get('ability_two').get('13_status_effect_id')}"
            ids_objs.update(
                {
                    _i.get("1_id"): _val
                }
            )

        json.dump(ids_objs, f2, indent=2)

    return len(all_moves)


# Example usage:
if __name__ == "__main__":
    # Convert to JSON
    moves_count = convert_to_json("data_json/swf_move_abilities.json", "converted_json/moves_abilities.json")
    print(f"Converted {moves_count} moves to JSON")
