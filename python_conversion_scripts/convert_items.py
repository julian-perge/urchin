import json


# ["Physical","Magic","Ice","Fire","Lightning","Earth","Shadow","Poison"]

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
            item_looks = ""

        rarity: str = _item.get("rarity")

        class_type: str = _item.get("class_type")
        if isinstance(class_type, dict):
            class_type = "None"

        required_level = int(_item.get("required_level"))
        price = int(_item.get("price"))
        price_modifier = float(_item.get("price_modifier"))

        ele_stats = _item.get("element_stats").get("members")

        tool_tip = _item.get("tool_tip")
        if isinstance(tool_tip, dict):
            tool_tip = ""

        item = {
            "id":             _id,
            "name":           item_name,
            "internal_name":  internal_name,
            "display_name":   item_name or internal_name,
            "item_type":      _type,
            "looks":          item_looks,
            "rarity":         rarity,
            "class_type":     class_type,
            "required_level": required_level,
            "price":          price,
            "price_modifier": price_modifier,
            "tool_tip":       tool_tip,
            "tool_tip_alt":   list(
                _item.get("tool_tip_alt").get("denseValues").values()
            ),
            "stats":          {
                "attributes": _item.get("stats").get("members"),
                "piercing":   ele_stats.get("attack").get("members"),
                "defense":    ele_stats.get("defense").get("members")
            },
        }

        items.append(item)
    return items


def convert_items_to_json(input_file, output_file):
    """Convert full ActionScript item definitions to JSON."""
    with open(input_file, 'r') as f:
        content: dict = json.load(f)

    items = parse_items_with_stats(content.get("ITEMS", {}).get("denseValues"))

    # Write to JSON file
    with open(output_file, 'w') as f:
        json.dump({"items": items}, f, indent=2)

    with open("converted_json/converted_item_by_id.json", 'w') as f2:
        ids_objs = {}
        for _i in items:
            ids_objs.update({_i.get("id"): _i.get("display_name")})

        json.dump(ids_objs, f2, indent=2)

    return len(items)


# Example usage:
if __name__ == "__main__":
    # Convert to JSON
    item_count = convert_items_to_json(
        'data_json/swf_items.json',
        'converted_json/items.json'
    )
    print(f"Converted {item_count} items to JSON")
