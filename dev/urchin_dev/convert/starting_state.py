# Run: uv run convert_starting_state
# Writes dev/converted_json/starting_state.json, Sonny's gear (equipArray0) and
# stat allocation (StatSets0) at the two points a new game sets them. The
# frame_42 script sets them when the game loads, before class select, and the
# Tutorial is fought in that state. frame_180 sets them again before battle 100
# on every route from class select.
from __future__ import annotations

import json
import re
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON

SOURCES = {"before_story": "frame_42/DoAction_17.as", "story": "frame_180/DoAction.as"}
EQUIP_SLOTS = 7
STAT_COUNT = 5


def _array(source: str, name: str, length: int, where: str) -> list[int]:
    found = re.findall(rf"^Krin\.{name} = \[([^\]]*)\];$", source, re.MULTILINE)
    if len(found) != 1:
        raise ValueError(f"{where}: {len(found)} statements set Krin.{name}, not 1")
    values = [int(value) for value in found[0].split(",")]
    if len(values) != length:
        raise ValueError(
            f"{where}: Krin.{name} has {len(values)} entries, not {length}"
        )
    return values


def parse_state(source: str, where: str) -> dict:
    """-> the gear and the stat allocation that one frame script sets."""
    return {
        "source": where,
        "equip": _array(source, "equipArray0", EQUIP_SLOTS, where),
        "stat_allocation": _array(source, "StatSets0", STAT_COUNT, where),
    }


def convert(action_script: Path) -> dict:
    return {
        name: parse_state((action_script / path).read_text("utf-8"), path)
        for name, path in SOURCES.items()
    }


def main() -> None:
    output = CONVERTED_JSON / "starting_state.json"
    state = convert(ACTION_SCRIPT)
    output.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
