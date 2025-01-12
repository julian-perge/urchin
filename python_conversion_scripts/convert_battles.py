import json

# ["EMPTY","PRISON","VILLAGE","TRAIN","TUNNELS","CITY","ROME","JAPAN","UTOPIA","JAPAN","STORM","EDEN","DOME","BETA"];
# CHURCH
# CHURCH2
# JAIL
# SNOW
# STREETS
# STREETS2
# STREETS3
# TRAIN
# TUNNEL
# WHITE NOVEMBER


def parse_json(parsed_dict: dict):
    """Parse the entire file handling stats that precede battle creation."""
    battles = []

    with open("converted_json/converted_units_by_id.json", 'r') as f4:
        units_by_id: dict[str, str] = json.load(f4)

    with open("converted_json/converted_item_by_id.json", "r") as f:
        items_by_ids: dict = json.load(f)

    # Find all items in this block
    for idx, json_block in parsed_dict.items():
        _root = json_block.get("members", {})

        absolute_start: str = _root.get("absolute_start")
        _id: str = _root.get("id")
        id_name: str = _root.get("id_name")

        item_drops = []
        item_drops_obj = _root.get("item_drops", {}).get("denseValues", {})
        for _idx, itm_drop in item_drops_obj.items():
            _itm_members = itm_drop.get("members", {})
            item_drops.append(
                {
                    "chance": _itm_members.get("CHANCE"),
                    "item": {
                        "id": _itm_members.get("ID"),
                        "name": items_by_ids.get(str(_itm_members.get("ID"))),
                    },
                }
            )

        def populate_item_dict(_item_list):
            _item_dict = []
            for _list_id in _item_list:
                _item_dict.append(
                    {
                        "id": _list_id,
                        "name": items_by_ids.get(str(_list_id)),
                    }
                )
            return _item_dict

        item_rare_list = list(_root.get("item_rare", {}).get("denseValues", {}).values())
        item_rare = populate_item_dict(item_rare_list)

        item_rare2_list = list(_root.get("item_rare2", {}).get("denseValues", {}).values())
        item_rare2 = populate_item_dict(item_rare2_list)

        item_rare3_list = list(_root.get("item_rare3", {}).get("denseValues", {}).values())
        item_rare3 = populate_item_dict(item_rare3_list)

        item_rare_dropper: int = _root.get("item_rare_dropper")
        item_rare_dropper2: int = _root.get("item_rare_dropper2")
        item_rare_dropper3: int = _root.get("item_rare_dropper3")

        phases: str = _root.get("phases", {}).get("denseValues", {})

        players = list(_root.get("players", {}).get("denseValues", {}).values())
        u_players = []
        for player in players:
            if units_by_id.get(str(player), None) is not None:
                u_players.append(
                    {
                        "id": player,
                        "name": units_by_id.get(str(player)),
                    }
                )
            else:
                u_players.append(
                    {
                        "id": player,
                    }
                )

        players_levels = list(_root.get("players_levels", {}).get("denseValues", {}).values())
        sky_background: str = _root.get("sky_background")
        speeches_obj = _root.get("speeches", {}).get("denseValues", {})
        speeches = [speech.get("members") for idx, speech in speeches_obj.items()]
        time_lock: bool = _root.get("time_lock")  # always false?
        win_date: int = _root.get("win_date")
        win_date_condition: int = _root.get("win_date_condition")
        zone_background: str = _root.get("zone_background")

        item = {
            "absolute_start": absolute_start,
            "id": _id,
            "id_name": id_name,
            "item_drops": item_drops,
            "item_rare": item_rare,
            "item_rare2": item_rare2,
            "item_rare3": item_rare3,
            "item_rare_dropper": item_rare_dropper,
            "item_rare_dropper2": item_rare_dropper2,
            "item_rare_dropper3": item_rare_dropper3,
            "phases": phases,
            "players": u_players,
            "players_levels": players_levels,
            "sky_background": sky_background,
            "speeches": speeches,
            "time_lock": time_lock,
            "win_date": win_date,
            "win_date_condition": win_date_condition,
            "zone_background": zone_background,
        }

        battles.append(item)
    return battles


def convert_to_json(input_file, output_file):
    """Convert full ActionScript item definitions to JSON."""
    with open(input_file, "r") as f:
        content: dict = json.load(f)

    items = parse_json(content.get("BATTLES", {}).get("denseValues"))

    # Write to JSON file
    with open(output_file, "w") as f:
        json.dump({"battles": items}, f, indent=2, sort_keys=True)

    return len(items)


# Example usage:
if __name__ == "__main__":
    # Convert to JSON
    _count = convert_to_json("data_json/swf_battles.json", "converted_json/battles.json")
    print(f"Converted {_count} converted_battles to JSON")
