# Run: uv run convert_strings
from __future__ import annotations

import json
import re

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON

SOURCE = ACTION_SCRIPT / "frame_1" / "DoAction.as"
OUTPUT = CONVERTED_JSON / "strings.json"

PREFIX = "KrinLang.ENGLISH."
ASSIGNMENT = re.compile(
    r"KrinLang\.ENGLISH\.(?P<name>\w+)(?:\.(?P<member>\w+))?(?:\[(?P<index>\d+)\])?"
    r' = (?P<value>"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?|new Array\(\)|new Object\(\));$'
)
ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}


def unescape(literal: str, line_number: int) -> str:
    def replace(match: re.Match[str]) -> str:
        character = match.group(1)
        if character not in ESCAPES:
            raise ValueError(f"line {line_number}: unknown escape \\{character}")
        return ESCAPES[character]

    return re.sub(r"\\(.)", replace, literal[1:-1])


def parse_value(literal: str, line_number: int) -> str | int | float:
    if literal.startswith('"'):
        return unescape(literal, line_number)
    if "." in literal:
        return float(literal)
    return int(literal)


def parse_english(source: str) -> dict:
    """Read every KrinLang.ENGLISH member of an AS script into a dict.

    An array becomes a list in which each value keeps its AS index, and an
    index the AS never writes becomes None. A later write to the same index
    replaces the earlier one, as it does when the AS runs. A line that
    starts with KrinLang.ENGLISH but has another shape raises ValueError, so
    no string is dropped without notice.
    """
    table: dict = {}
    for line_number, line in enumerate(source.splitlines(), start=1):
        line = line.strip()
        if not line.startswith(PREFIX):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if match is None:
            raise ValueError(f"line {line_number}: cannot read {line[:80]!r}")
        name, member, index, literal = match.group("name", "member", "index", "value")
        if member is not None and index is not None:
            raise ValueError(f"line {line_number}: indexed object member")
        if literal == "new Array()":
            table[name] = []
            continue
        if literal == "new Object()":
            table[name] = {}
            continue
        value = parse_value(literal, line_number)
        if member is not None:
            table[name][member] = value
        elif index is not None:
            array = table[name]
            position = int(index)
            array.extend([None] * (position + 1 - len(array)))
            array[position] = value
        else:
            table[name] = value
    return table


def dumps(table: dict) -> str:
    return json.dumps(table, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def main() -> None:
    table = parse_english(SOURCE.read_text(encoding="utf-8"))
    OUTPUT.write_text(dumps(table), encoding="utf-8", newline="\n")
    print(f"Wrote {len(table)} KrinLang.ENGLISH members to {OUTPUT}")


if __name__ == "__main__":
    main()
