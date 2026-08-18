# Run: uv run convert_battles
from __future__ import annotations

import json

from urchin_dev import CONVERTED_JSON, require_data_json
from urchin_dev.swf import models

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

# frame_42/DoAction_14.as's battleCreationID reset statements ("battleCreationID
# = 199;" etc., nine of them, reserving per-zone id blocks) retroactively
# relabel the battle whose properties were JUST finished being set, instead of
# the next one about to be created (see SWF_DIFFERENCES.md's "Battle id is not
# battleCreationID's value at creation time"). Three of the nine land exactly
# one battle early, mislabeling each zone's real final story battle with the
# next block's seed id: zone 1's 10th battle (should be 109) comes stamped
# 199/KBR199, zone 4's (should be 409) comes stamped 499/KBR499, zone 5's
# (should be 513) comes stamped 599/KBR599. Confirmed by creation-order
# position against dev/data_json/swf_battles.json (zero content mismatches -
# each mislabeled row's players/phases/speeches are that zone's boss fight,
# not a stray battle from the next zone). Correct them back here so
# resources/battles/ ends up with the ids the original game's own
# BattlePick == 109/409/513 checks (frame_219) actually expect.
MISLABELED_BATTLE_IDS: dict[int, tuple[int, str]] = {
    199: (109, "KBR109"),
    499: (409, "KBR409"),
    599: (513, "KBR513"),
}


def parse_json(parsed_dict: dict):
    """Parse the entire file handling stats that precede battle creation."""
    battles = []

    units_by_id: dict[str, str] = models.load_json(
        CONVERTED_JSON / "converted_units_by_id.json"
    )

    items_by_ids: dict = models.load_json(CONVERTED_JSON / "converted_item_by_id.json")

    # Find all items in this block
    for json_block in parsed_dict.values():
        _root = json_block.get("members", {})

        absolute_start: str = _root.get("absolute_start")
        _id: str = _root.get("id")
        id_name: str = _root.get("id_name")
        if _id in MISLABELED_BATTLE_IDS:
            _id, id_name = MISLABELED_BATTLE_IDS[_id]

        item_drops = []
        item_drops_obj = _root.get("item_drops", {}).get("denseValues", {})
        for itm_drop in item_drops_obj.values():
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
                    {"id": _list_id, "name": items_by_ids.get(str(_list_id))}
                )
            return _item_dict

        item_rare_list = list(
            _root.get("item_rare", {}).get("denseValues", {}).values()
        )
        item_rare = populate_item_dict(item_rare_list)

        item_rare2_list = list(
            _root.get("item_rare2", {}).get("denseValues", {}).values()
        )
        item_rare2 = populate_item_dict(item_rare2_list)

        item_rare3_list = list(
            _root.get("item_rare3", {}).get("denseValues", {}).values()
        )
        item_rare3 = populate_item_dict(item_rare3_list)

        item_rare_dropper: int = _root.get("item_rare_dropper")
        item_rare_dropper2: int = _root.get("item_rare_dropper2")
        item_rare_dropper3: int = _root.get("item_rare_dropper3")

        # Boss-phase entries. Slot "0" is the "EMPTY" placeholder; real entries
        # start at "1" as {player, life, teamLeft?, turn?, endGame, winOrLose}.
        # Unwrap the AVM {"type": "Object", "members": {...}} envelopes so the
        # consumer (BattleRunner) reads plain dictionaries.
        phases_raw = _root.get("phases", {}).get("denseValues", {})
        phases = {}
        for phase_index, phase_entry in phases_raw.items():
            if isinstance(phase_entry, dict) and "members" in phase_entry:
                phases[phase_index] = phase_entry["members"]
            else:
                phases[phase_index] = phase_entry

        players = list(_root.get("players", {}).get("denseValues", {}).values())
        u_players = []
        for player in players:
            if units_by_id.get(str(player), None) is not None:
                u_players.append({"id": player, "name": units_by_id.get(str(player))})
            else:
                u_players.append({"id": player})

        players_levels = list(
            _root.get("players_levels", {}).get("denseValues", {}).values()
        )
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
    content: dict = models.load_json(input_file)

    items = parse_json(content.get("BATTLES", {}).get("denseValues"))

    # Write to JSON file
    with output_file.open("w") as f:
        json.dump({"battles": items}, f, indent=2, sort_keys=True)

    return len(items)


def main() -> None:
    _count = convert_to_json(
        require_data_json("swf_battles.json"), CONVERTED_JSON / "battles.json"
    )
    print(f"Converted {_count} converted_battles to JSON")


if __name__ == "__main__":
    main()
