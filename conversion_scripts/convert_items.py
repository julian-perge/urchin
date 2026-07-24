from __future__ import annotations

import json

import swf_models

from . import CONVERTED_JSON

# ["Physical","Magic","Ice","Fire","Lightning","Earth","Shadow","Poison"]

# The runtime dump captured KRINITEM.looks as Undefined - the real values
# are the `gghhjjuu.looks = "X"` assignments in
# source_files/action_script/frame_42/DoAction_16.as (default "NINJA" for
# wearables), extracted by swf_extraction/extract_item_looks.py.
_LOOKS_TABLE_PATH = CONVERTED_JSON / "item_looks.json"

try:
    LOOKS_BY_ID = swf_models.load_json(_LOOKS_TABLE_PATH)
except FileNotFoundError:
    LOOKS_BY_ID = {}


def parse_items_with_stats(parsed_dict: dict):
    """Parse the entire file handling stats that precede item creation."""
    items = []

    # Find all items in this block
    for idx, item_dict in parsed_dict.items():
        _item = item_dict.get("members", {})
        _id: str = _item.get("id")
        _type: str = _item.get("type")
        internal_name: str = _item.get("internal_name")

        item_name = _item.get("name")
        if isinstance(item_name, dict):
            item_name = ""

        item_looks = _item.get("looks")
        if isinstance(item_looks, dict):
            item_looks = LOOKS_BY_ID.get(str(_id), "")

        rarity: str = _item.get("rarity")

        class_type: str = _item.get("class_type")
        if isinstance(class_type, dict):
            class_type = "None"

        # The dump's class_type strings are junk labels: the raw AS3 value is
        # a required UNIT id (KRINITEM[3], matched against ClassStats), and
        # the dump named it via krinClassArray by index. Decoded 2026-07-18:
        # "Dreadnaught" = 0 (anyone), "Phaser" = 4 (Veradux-only gear - his
        # Medic/KLIMA sets). No item restricts by player class.
        class_unit_id = {
            "Dreadnaught": 0,
            "Phantom": 1,
            "Enigma": 2,
            "Templar": 3,
            "Phaser": 4,
            "None": 0,
        }.get(class_type, 0)

        required_level = int(_item.get("required_level"))
        price = int(_item.get("price"))
        price_modifier = float(_item.get("price_modifier"))

        ele_stats = _item.get("element_stats").get("members")

        tool_tip = _item.get("tool_tip")
        if isinstance(tool_tip, dict):
            tool_tip = ""

        item = {
            "id": _id,
            "name": item_name,
            "internal_name": internal_name,
            "display_name": item_name or internal_name,
            "item_type": _type,
            "looks": item_looks,
            "rarity": rarity,
            "class_type": class_type,
            "class_unit_id": class_unit_id,
            "required_level": required_level,
            "price": price,
            "price_modifier": price_modifier,
            "tool_tip": tool_tip,
            "tool_tip_alt": list(_item.get("tool_tip_alt").get("denseValues").values()),
            "stats": {
                "attributes": _item.get("stats").get("members"),
                "piercing": ele_stats.get("attack").get("members"),
                "defense": ele_stats.get("defense").get("members"),
            },
        }

        items.append(item)
    return items


def convert_items_to_json(input_file, output_file):
    """Convert full ActionScript item definitions to JSON."""
    content: dict = swf_models.load_json(input_file)

    items = parse_items_with_stats(content.get("ITEMS", {}).get("denseValues"))

    # Write to JSON file
    with open(output_file, "w") as f:
        json.dump({"items": items}, f, indent=2)

    with open("converted_json/converted_item_by_id.json", "w") as f2:
        ids_objs = {}
        for _i in items:
            ids_objs.update({_i.get("id"): _i.get("display_name")})

        json.dump(ids_objs, f2, indent=2)

    return len(items)


# Example usage:
if __name__ == "__main__":
    # Convert to JSON
    item_count = convert_items_to_json(
        "data_json/swf_items.json", "converted_json/items.json"
    )
    print(f"Converted {item_count} items to JSON")
