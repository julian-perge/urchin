# trace.py
# Builds a Traced copy of one build of the original. It exports the scripts of
# the build's SWF in URCHIN_SWF_DIR to a temporary folder with ffdec, puts each
# Probe file of dev/probes/ in front of the build's own frame_1/DoAction.as, and
# compiles the result back into the first frame with `ffdec -replace`. The
# Traced copy goes to $URCHIN_SWF_DIR/traced/ under the build's file name, and
# its path is printed.
#
# Each build gets its own export, because the Steam build's first frame script
# is not in the repo, and dev/source_files/action_script/ is the web build's.
#
# It also reads a Trace log, which is the raw log of a player that ran a Traced
# copy, and compares two of them. Only the GOTO lines of the goto Probe are
# read. The comparison needs no SWF, no ffdec and no label data.
#
# Run: uv run trace_swf <web|steam>
#      uv run trace_diff <log a> <log b>
from __future__ import annotations

import sys
import tempfile
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

from urchin_dev import DEV_ROOT, FFDEC, STEAM_SWF, SWF_DIR, WEB_SWF
from urchin_dev.run import run

PROBES = DEV_ROOT / "probes"
TRACED_DIR = SWF_DIR / "traced"
BUILDS = {"web": WEB_SWF, "steam": STEAM_SWF}
GOTO_MARK = "GOTO\t"


@dataclass(frozen=True)
class Goto:
    kind: str
    clip: str
    total_frames: int
    before: int
    target: str
    after: int


@dataclass(frozen=True, order=True)
class DiffRecord:
    kind: str
    clip: str
    total_frames: int
    target: str
    moved: bool


def read_probes(folder: Path) -> list[str]:
    """Return the text of each .as file in `folder`, in name order."""
    return [path.read_text(encoding="utf-8") for path in sorted(folder.glob("*.as"))]


def with_probes(frame_script: str, probes: Sequence[str]) -> str:
    """Return `frame_script` with each Probe in front of it, each ending in one
    newline. The frame script itself is not changed."""
    return "".join(probe.rstrip("\n") + "\n" for probe in probes) + frame_script


def trace_swf(swf: Path) -> Path:
    """Write the Traced copy of `swf` and return its path."""
    traced = TRACED_DIR / swf.name
    traced.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        export = Path(tmp) / "export"
        run([FFDEC, "-export", "script", export, swf])
        frame_script = (export / "scripts/frame_1/DoAction.as").read_text(
            encoding="utf-8", newline=""
        )
        script = Path(tmp) / "DoAction.as"
        script.write_text(
            with_probes(frame_script, read_probes(PROBES)), encoding="utf-8", newline=""
        )
        run([FFDEC, "-replace", swf, traced, "/frame_1/DoAction", script])
    return traced


def parse(text: str) -> list[Goto]:
    """Return one record for each GOTO line of a Trace log. A line is read from
    its first `GOTO<tab>`, so a player's prefix does not matter, and every other
    line is skipped."""
    gotos = []
    for number, line in enumerate(text.splitlines(), start=1):
        _, mark, rest = line.partition(GOTO_MARK)
        if not mark:
            continue
        fields = rest.split("\t")
        try:
            kind, clip, total_frames, before, target, after = fields
            gotos.append(
                Goto(kind, clip, int(total_frames), int(before), target, int(after))
            )
        except ValueError as error:
            raise ValueError(
                f"line {number}: bad GOTO line {line!r}: {error}"
            ) from None
    return gotos


def diff_records(gotos: Iterable[Goto]) -> set[DiffRecord]:
    """Return the distinct gotos of a log. `moved` is true when at least one
    occurrence of that goto changed the frame."""
    moved: dict[tuple[str, str, int, str], bool] = {}
    for goto in gotos:
        key = (goto.kind, goto.clip, goto.total_frames, goto.target)
        moved[key] = moved.get(key, False) or goto.before != goto.after
    return {DiffRecord(*key, did_move) for key, did_move in moved.items()}


def diff(
    a: Iterable[Goto], b: Iterable[Goto]
) -> tuple[list[DiffRecord], list[DiffRecord]]:
    """Return the diff records that only `a` has and those that only `b` has,
    each sorted."""
    records_a = diff_records(a)
    records_b = diff_records(b)
    return sorted(records_a - records_b), sorted(records_b - records_a)


def diff_main(argv: Sequence[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        raise SystemExit("usage: trace_diff <log a> <log b>")
    logs = [Path(arg) for arg in args]
    for log in logs:
        if not log.is_file():
            raise SystemExit(f"error: no Trace log at {log}.")
    gotos = []
    for log in logs:
        try:
            gotos.append(parse(log.read_text(encoding="utf-8")))
        except ValueError as error:
            raise SystemExit(f"error: {log}: {error}") from None
    sides = diff(*gotos)
    for log, records in zip(logs, sides, strict=True):
        print(f"only in {log} ({len(records)}):")
        for record in records:
            state = "moved" if record.moved else "stayed"
            print(
                f"{record.kind}\t{record.clip}\t{record.total_frames}\t{record.target}\t{state}"
            )


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in BUILDS:
        raise SystemExit(f"usage: trace_swf <{'|'.join(BUILDS)}>")
    swf = BUILDS[sys.argv[1]]
    if not swf.is_file():
        raise SystemExit(f"error: no SWF at {swf}. Set URCHIN_SWF_DIR.")
    print(trace_swf(swf))


if __name__ == "__main__":
    main()
