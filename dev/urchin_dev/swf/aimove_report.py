# aimove_report.py
# Counts the AImoveAdder calls of the original whose outcome a global that an
# earlier call left behind changed. It reads the AIMOVE lines that the Probe
# dev/probes/aimove.as writes to a Trace log.
#
# Each AIMOVE line holds the real outcome of one call and the outcome of
# replays of the same call with the same dice. The "none" replay resets
# nothing, so it must match the real outcome. The "all" replay sets every
# left-behind global to the value the port's BattleAI.choose_move starts from,
# and each other replay resets one group of them. A call counts as changed
# when the real outcome differs from the "all" replay.
#
# Run: just aimove-report <log> [<log> ...]
from __future__ import annotations

import re
import sys
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

MARK = "AIMOVE\t"
GROUPS = ("focus", "fmove", "darr", "alive", "lock")


@dataclass(frozen=True)
class Outcome:
    move: str
    target: str
    heals: str


@dataclass
class Call:
    number: int
    battle: str
    phase: str
    caster: str
    last_caster: str
    absolute: bool
    fields: dict[str, str] = field(default_factory=dict)


def parse(text: str) -> list[Call]:
    """Return one Call for each AIMOVE line of a Trace log, in log order. A
    line is read from its AIMOVE mark, so a player's prefix does not matter."""
    calls = []
    for line in text.splitlines():
        start = line.find(MARK)
        if start < 0:
            continue
        parts = line[start:].split("\t")
        call = Call(
            int(parts[1]), parts[2], parts[3], parts[4], parts[5], parts[6] == "true"
        )
        for item in parts[7:]:
            key, _, value = item.partition("=")
            call.fields[key] = value
        calls.append(call)
    return calls


def outcome(text: str, caster: str) -> Outcome:
    """Return the move, the target and the healedThisTurn slots that a call
    changed. A replay with no aliveEnemies list reaches the fallback of
    frame_42/DoAction_9.as:437-439 with target undefined, and the port targets
    the caster there. Line 399 writes healedThisTurn[false] when the heal scan
    found no one, and nothing reads that key, so only slots 0 to 7 count."""
    move, target, heals = (text.split(">") + ["", ""])[:3]
    if target == "undefined":
        target = caster
    return Outcome(move, target, "".join(re.findall(r"h[0-7]", heals)))


def count(calls: Sequence[Call]) -> dict[str, Counter[str]]:
    """Return the counts of each battle, keyed by battle id."""
    battles: dict[str, Counter[str]] = {}
    # The D_Array_* lists are rebuilt only by a call that does not use its
    # absolute pool (frame_42/DoAction_9.as:134-139).
    lists_from = ""
    for call in calls:
        counts = battles.setdefault(call.battle, Counter())
        counts["calls"] += 1
        counts["absolute"] += call.absolute
        # Only the absolute path reads focusMove without resetting it first
        # (frame_42/DoAction_9.as:84 and 405).
        counts["absolute_with_focus_move"] += (
            call.absolute and call.fields["fm"] == "true"
        )
        real = outcome(call.fields["real"], call.caster)
        if outcome(call.fields["none"], call.caster) != real:
            counts["replay_mismatch"] += 1
        # The alive replay rebuilds aliveEnemies and leaves counterFilter1
        # undefined, so its target is undefined exactly when the call reaches
        # lines 437-439 with that list. A real call whose left list is empty
        # passes the turn at line 413 instead, and then shows as a changed
        # move, not as a fallback.
        if call.fields["alive"].split(">")[1:2] == ["undefined"]:
            counts["fallback"] += 1
            if real.target != call.caster:
                counts["fallback_not_caster"] += 1
        fresh = outcome(call.fields["all"], call.caster)
        if fresh != real:
            counts["changed"] += 1
            if fresh.move != real.move:
                counts["changed_move"] += 1
            elif fresh.target != real.target:
                counts["changed_target"] += 1
            else:
                counts["changed_heal_guess"] += 1
            for group in GROUPS:
                if outcome(call.fields[group], call.caster) != real:
                    counts["by_" + group] += 1
            if outcome(call.fields["darr"], call.caster) != real:
                counts[
                    "lists_from_"
                    + ("caster" if lists_from == call.caster else "other_unit")
                ] += 1
        if not call.absolute:
            lists_from = call.caster
    return battles


def main(argv: Sequence[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    if not args:
        raise SystemExit("usage: aimove_report <log> [<log> ...]")
    for arg in args:
        log = Path(arg)
        if not log.is_file():
            raise SystemExit(f"error: no Trace log at {log}.")
        print(f"{log}:")
        for battle, counts in count(
            parse(log.read_text(encoding="utf-8", errors="replace"))
        ).items():
            print(
                f"  battle {battle}: "
                + ", ".join(f"{key} {value}" for key, value in sorted(counts.items()))
            )
