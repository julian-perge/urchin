import json


def parse_move_block(move_dict: dict):
    """Parse a move creation block into a dictionary."""

    moves = []
    for idx, block in move_dict.items():
        _move_block: dict[str, str | int | dict] = block.get("members")

        ability_two = _move_block.get("ability_two", {}).get("denseValues", {})
        ab_two_dict = {
            "element_type": ability_two.get("0"),
            "strength": ability_two.get("1"),
            "strength_modifier": ability_two.get("2"),
            "magic": ability_two.get("3"),
            "magic_modifier": ability_two.get("4"),
            "speed": ability_two.get("5"),
            "speed_modifier": ability_two.get("6"),
            "unknown7": ability_two.get("7"),
            "unknown8_usenum": ability_two.get("8"),
            "focus_to_apply": ability_two.get("9"),
            "unknown10": ability_two.get("10"),
            "unknown11_focus_mod": ability_two.get("11"),
            "buff_apply_percent": ability_two.get("12"),
            "buff_id": ability_two.get("13"),
            "chance_to_recover_health": ability_two.get("14"),
            "unknown15_element_type_arr": ability_two.get("15"),
            "number_of_dispels": ability_two.get("16"),
            "tooltip": ability_two.get("17"),
            "tooltip2": ability_two.get("18"),
            "unknown19_buff_cd_tick": ability_two.get("19"),
            "unknown20": ability_two.get("20"),
            "applies_to": "target" if ability_two.get("21") == 0 else "caster",
            "unknown22_numberRandomerBuffHit": ability_two.get("22"),
            "element_type2": ability_two.get("23"),
            "buffs_required_to_use": ability_two.get("24"),
            "unknown24_focus_mod": ability_two.get("24"),
        }

        move = {
            "id": _move_block.get("id"),  # a
            "id_name": _move_block.get("id_name"),  # a
            "name": _move_block.get("name"),  # a
            "move_type": _move_block.get("move_type"),  # c
            "damage_base": _move_block.get("damage_base"),  # d
            "damage_scale": _move_block.get("damage_scale"),  # e
            "focus_cost": _move_block.get("focus_cost"),  # f
            "g": _move_block.get("g"),  # g
            "cooldown": _move_block.get("cooldown"),  # h
            "i": _move_block.get("i"),  # i
            "j": _move_block.get("j"),  # j
            "projectile_type": _move_block.get("projectile_type"),  # k
            "projectile_color": _move_block.get("projectile_color"),  # l
            "projectile_model": _move_block.get("projectile_model"),  # m
            "impact_effect": _move_block.get("impact_effect"),  # n
            "damage_type": _move_block.get("damage_type"),  # o, full damage, heal, focus
            "p": _move_block.get("p"),  # p, always 1?
            "health_cost_percent": _move_block.get("health_cost_percent"),  # q
            "skill_name": _move_block.get("skill_name"),  # r
            "sound_effect": _move_block.get("sound_effect"),  # s
            "ability_two": ab_two_dict,
        }

        moves.append(move)

    return moves


def convert_moves_to_json(input_file, output_file):
    """Convert full ActionScript move definitions to JSON."""
    with open(input_file, "r") as f:
        content: dict = json.load(f)

    all_moves = parse_move_block(content.get("ABILITIES").get("denseValues"))
    # Write to JSON file
    with open(output_file, "w") as f:
        json.dump(all_moves, f, indent=2)

    return len(all_moves)


# Example usage:
if __name__ == "__main__":
    # Convert to JSON
    moves_count = convert_moves_to_json("data_json/swf_move_abilities.json", "converted_json/moves_abilities.json")
    print(f"Converted {moves_count} moves to JSON")
