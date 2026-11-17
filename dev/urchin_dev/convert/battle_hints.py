# Run: uv run convert_battle_hints
from __future__ import annotations

import json
import re

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON

SOURCE = ACTION_SCRIPT / "frame_42" / "DoAction_21.as"
OUTPUT = CONVERTED_JSON / "battle_hints.json"

COUNTER_SET = re.compile(r"pggKKuuIIoo = (\d+);")
COUNTER_STEP = "pggKKuuIIoo++;"
BATTLE = re.compile(r"Krin\.bEr = (\d+);")
NEW_HINT = "Krin.progressSpeech[Krin.bEr] = new Array();"
TEXT_LINE = re.compile(
    r"Krin\.progressSpeech\[Krin\.bEr\]\[(?P<slot>[01])\]"
    r" = _root\.KrinLang\[KLangChoosen\]\.(?P<name>NAVTITLE2|NAVTEXT2)\[pggKKuuIIoo\];"
)
SLOT_NAMES = {"0": "NAVTITLE2", "1": "NAVTEXT2"}
PREFIXES = ("Krin.bEr", "Krin.progressSpeech[Krin.bEr]", "pggKKuuIIoo")


def parse_hints(source: str) -> dict[str, int]:
    """Read the post-battle hint table of an AS script.

    The original gives each battle with a hint the next index of NAVTITLE2 and
    NAVTEXT2: a counter starts at 0 and goes up by one after each block. The
    result maps the battle id, as a string because it is a JSON key, to that
    index, in the order of the AS. A battle whose index has no text in
    NAVTITLE2 is kept, because this module does not read the strings. A line
    that starts like the table but has another shape raises ValueError, and so
    does a block that lacks its title line, its text line, or that reads two
    indexes. A script with no hint raises ValueError too.
    """
    hints: dict[str, int] = {}
    counter = 0
    battle: str | None = None
    seen: dict[str, int] = {}

    def close_block() -> None:
        if battle is None:
            return
        if set(seen) != set(SLOT_NAMES.values()) or len(set(seen.values())) != 1:
            raise ValueError(
                f"battle {battle}: needs one NAVTITLE2 and one NAVTEXT2 line at one index"
            )
        hints[battle] = seen["NAVTITLE2"]

    for line_number, line in enumerate(source.splitlines(), start=1):
        line = line.strip()
        if not line.startswith(PREFIXES):
            continue
        if line == COUNTER_STEP:
            counter += 1
        elif match := COUNTER_SET.fullmatch(line):
            counter = int(match.group(1))
        elif match := BATTLE.fullmatch(line):
            close_block()
            battle = match.group(1)
            seen = {}
        elif line == NEW_HINT:
            continue
        elif (match := TEXT_LINE.fullmatch(line)) and battle is not None:
            if SLOT_NAMES[match.group("slot")] != match.group("name"):
                raise ValueError(
                    f"line {line_number}: slot {match.group('slot')} reads {match.group('name')}"
                )
            seen[match.group("name")] = counter
        else:
            raise ValueError(f"line {line_number}: cannot read {line[:80]!r}")
    close_block()
    if not hints:
        raise ValueError("no hints found")
    return hints


def dumps(table: dict[str, int]) -> str:
    return json.dumps(table, indent=2) + "\n"


def main() -> None:
    table = parse_hints(SOURCE.read_text(encoding="utf-8"))
    OUTPUT.write_text(dumps(table), encoding="utf-8", newline="\n")
    print(f"Wrote {len(table)} battle hints to {OUTPUT}")


if __name__ == "__main__":
    main()
