# strip.py
# The one place that deletes or hides characters before ffdec renders, for
# characters the game never shows: ones ActionScript hides at runtime, the
# author's placeholder rigs and the overlays an extractor wants the art
# without. Each extractor keeps its own {characterId: reason} and hands it
# here. stripped_copy() gives back one copy of the SWF with every id deleted
# by a single ffdec -removeCharacter call, and hide_list() gives the ids for
# a ffdec_lib.render job's hide_characters.
#
# Both refuse first. A clip mask looks just like an unwanted shape on top of
# the art, but deleting or hiding one unclips everything it covered:
# DefineShape 1913 masks the item sheet 2064, and stripping it took item 69
# "A Broken Pipe" from 63x63 to 101x140 (6622d79). So an id that any
# placement in the SWF uses as a clip mask is refused, naming every such
# placement, and so is an id nothing places, since that can only be a stale
# entry. Render.java keeps its own refusal for the driver as a second check.
#
# An extractor renders and measures from the same copy. ecf28fd fixed 5 of
# 10 hall rects that were measured from the unstripped SWF while the PNGs
# were cropped from the stripped one.
from __future__ import annotations

import subprocess
import sys
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from urchin_dev import FFDEC
from urchin_dev.swf.swf_index import SwfIndex, read_swf


class StripError(ValueError):
    pass


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )


def check(index: SwfIndex, characters: dict[int, str]) -> None:
    """Raise StripError for every id that is placed as a clip mask anywhere
    or placed nowhere, naming each masking placement."""
    placed: dict[int, list] = {cid: [] for cid in characters}
    for p in index.placements:
        if p.character_id in placed:
            placed[p.character_id].append(p)
    problems = []
    for cid, reason in sorted(characters.items()):
        masks = [p for p in placed[cid] if p.clip_depth is not None]
        if masks:
            where = "; ".join(
                f"timeline {p.owner} frame {p.frame} depth {p.depth}"
                f" clipDepth {p.clip_depth}"
                for p in masks
            )
            problems.append(
                f"character {cid} ({reason}) is a clip mask, and removing it"
                f" unclips what it covers: {where}"
            )
        elif not placed[cid]:
            problems.append(
                f"character {cid} ({reason}): nothing places it, so the entry is stale"
            )
    if problems:
        raise StripError("\n".join(problems))


def hide_list(swf: Path, characters: dict[int, str]) -> list[int]:
    """-> the ids, sorted, for a ffdec_lib.render job's hide_characters."""
    check(read_swf(swf), characters)
    for cid, reason in sorted(characters.items()):
        print(f"hiding {cid}: {reason}", file=sys.stderr)
    return sorted(characters)


@contextmanager
def stripped_copy(swf: Path, characters: dict[int, str]) -> Iterator[Path]:
    """Yield a copy of `swf` with every id in `characters` deleted, which is
    removed again when the block exits."""
    check(read_swf(swf), characters)
    with tempfile.TemporaryDirectory(prefix="strip_") as tmp:
        copy = Path(tmp) / f"{Path(swf).stem}.stripped.swf"
        ids = [str(cid) for cid in sorted(characters)]
        run([str(FFDEC), "-removeCharacter", str(swf), str(copy), *ids])
        if not copy.is_file():
            raise RuntimeError(f"ffdec reported success but wrote no {copy}")
        for cid, reason in sorted(characters.items()):
            print(f"stripped {cid}: {reason}", file=sys.stderr)
        yield copy
