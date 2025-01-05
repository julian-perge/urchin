import json


def parse_unit_block(parsed_unit: dict):
    """Parse a unit creation block into a dictionary."""

    moves = parsed_unit.get("moves").get("members")
    stats = parsed_unit.get("stats").get("members")
    visuals = parsed_unit.get("visuals").get("members")

    abs_moves = [
        list(_abs.get("denseValues").values())
        for idx, _abs in moves.get("abs").get("denseValues").items()
    ]

    unit = {
        "id":       parsed_unit.get("id"),
        "name":     parsed_unit.get("name"),
        "health":   int(parsed_unit.get("health")),
        "strength": int(parsed_unit.get("strength")),
        "magic":    int(parsed_unit.get("magic")),
        "speed":    int(parsed_unit.get("speed")),
        "focus":    int(parsed_unit.get("focus")),
        "moves":    {
            "absolute": abs_moves,
            "attack":   list(moves.get("attack").get("denseValues").values()),
            "defense":  list(moves.get("defense").get("denseValues").values()),
        },
        "stats":    {
            "aggression": stats.get("aggression").get("members"),
            "piercing":   stats.get("piercing").get("members"),
            "defense":    stats.get("defense").get("members")
        },
        "visuals":  {
            "model":     list(visuals.get("model").get("denseValues").values()),
            "equipment": list(
                visuals.get("equipment").get("denseValues").values()
            ),
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
    with open(output_file, 'w') as f:
        json.dump({"units": units}, f, indent=2)

    return len(units)


if __name__ == "__main__":
    # Convert to JSON
    unit_count = convert_units_to_json(
        'data_json/swf_units.json',
        'converted_json/units.json'
    )
    print(f"Converted {unit_count} units to JSON")
