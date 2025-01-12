import json

with open("converted_json/converted_moves_by_id.json", 'r') as f2:
    moves_by_id = json.load(f2)

with open("converted_json/converted_item_by_id.json", "r") as f:
    items_by_id = json.load(f)

def parse_moves(abs_moves: list[list[int]], attacks: list[int], defenses: list[int]):
    u_abs = []
    u_attacks = []
    u_defenses = []

    for move_arr in abs_moves:
        u_abs.append(
            {
                "id": move_arr[0],
                "name": moves_by_id.get(str(move_arr[0])),
                "turn": move_arr[1],
            }
        )

    for move_id in attacks:
        u_attacks.append(
            {
                "id": move_id,
                "name": moves_by_id.get(str(move_id))
            }
        )

    for move_id in defenses:
        u_defenses.append(
            {
                "id": move_id,
                "name": moves_by_id.get(str(move_id))
            }
        )

    return u_abs, u_attacks, u_defenses

def parse_unit_block(parsed_unit: dict):
    """Parse a unit creation block into a dictionary."""

    moves = parsed_unit.get("moves").get("members")
    stats = parsed_unit.get("stats").get("members")
    visuals = parsed_unit.get("visuals").get("members")

    abs_moves: list[list[int]] = [
        list(_abs.get("denseValues").values())
        for idx, _abs in moves.get("abs").get("denseValues").items()
    ]

    u_abs, u_attacks, u_defenses = parse_moves(
        abs_moves,
        list(moves.get("attack").get("denseValues").values()),
        list(moves.get("defense").get("denseValues").values())
    )

    visual_equips = list(visuals.get("equipment").get("denseValues").values())
    u_equips = []
    for equip_id in visual_equips:
        if equip_id != 0:
            u_equips.append(
                {
                    "id": equip_id,
                    "name": items_by_id.get(str(equip_id)),
                }
            )
        else:
            u_equips.append({"id": 0})

    unit = {
        "id":       parsed_unit.get("id"),
        "name":     parsed_unit.get("name"),
        "health":   int(parsed_unit.get("health")),
        "strength": int(parsed_unit.get("strength")),
        "magic":    int(parsed_unit.get("magic")),
        "speed":    int(parsed_unit.get("speed")),
        "focus":    int(parsed_unit.get("focus")),
        "moves":    {
            "absolute": u_abs,
            "attack":   u_attacks,
            "defense":  u_defenses,
        },
        "stats":    {
            "aggression": stats.get("aggression").get("members"),
            "piercing":   stats.get("piercing").get("members"),
            "defense":    stats.get("defense").get("members")
        },
        "visuals":  {
            "model":     list(visuals.get("model").get("denseValues").values()),
            "equipment": u_equips,
            "skin":      str(visuals.get("skin")),
            "voice":     {
                "hit": list(
                    visuals.get("voice").get("members").get("hit").get(
                        "denseValues"
                    ).values()
                ),
                "die": visuals.get("voice").get("members").get("die")
            }
        }
    }

    return unit


def convert_units_to_json(input_file, output_file):
    """Convert full ActionScript unit definitions to JSON."""
    with open(input_file, 'r') as f:
        content = json.load(f)

    # Split content into unit blocks
    unit_blocks = content.get("UNITS").get("denseValues")

    units = []
    for idx, block in unit_blocks.items():  # Skip first empty split
        unit = parse_unit_block(block.get("members"))
        if unit:
            units.append(unit)

    # Write to JSON file
    with open(output_file, 'w') as f3:
        json.dump({"units": units}, f3, indent=2)

    with open("converted_json/converted_units_by_id.json", 'w') as f4:
        ids_objs = {}
        for _i in units:
            ids_objs.update(
                {
                    _i.get("id"): _i.get("name"),
                }
            )

        json.dump(ids_objs, f4, indent=2)

    return len(units)


if __name__ == "__main__":
    # Convert to JSON
    unit_count = convert_units_to_json(
        'data_json/swf_units.json',
        'converted_json/units.json'
    )
    print(f"Converted {unit_count} units to JSON")
