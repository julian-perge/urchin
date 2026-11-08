# Checks the die voice convert_units gives each unit against the unit records
# in frame_42/DoAction_13.as.
from __future__ import annotations

import json
import re

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, require_data_json
from urchin_dev.convert import units
from urchin_dev.swf import models


# The records reset the id counter twice, so no unit has an id from 16 to 19
# or from 35 to 39. A record that never sets voiceDie leaves it undefined, and
# the port stores an undefined die voice as an empty string.
def die_voices_by_unit_id() -> dict[int, str]:
    text = (ACTION_SCRIPT / "frame_42" / "DoAction_13.as").read_text()
    die_voices: dict[int, str] = {}
    unit_id = 0
    for line in text.splitlines():
        if match := re.fullmatch(r"createUnitKrinCount = (\d+);", line):
            unit_id = int(match[1])
        elif line.startswith("createNewUnitKrin("):
            unit_id += 1
            die_voices[unit_id] = ""
        elif match := re.fullmatch(r'jesivie\.voiceDie = "(\w*)";', line):
            die_voices[unit_id] = match[1]
    return die_voices


def test_bunny_converts_its_undefined_die_voice_to_an_empty_string():
    capture = models.load_json(require_data_json("swf_units.json"))
    bunny = next(
        block["members"]
        for block in capture["UNITS"]["denseValues"].values()
        if block["members"]["id"] == 56
    )
    voice = bunny["visuals"]["members"]["voice"]["members"]
    assert voice["die"] == {"type": "Undefined"}
    assert units.parse_unit_block(bunny)["visuals"]["voice"]["die"] == ""


def test_every_committed_die_voice_matches_the_unit_records():
    committed = json.loads((CONVERTED_JSON / "units.json").read_text())["units"]
    die_voices = {unit["id"]: unit["visuals"]["voice"]["die"] for unit in committed}
    assert die_voices == die_voices_by_unit_id()
