# godot_sidecars.py
# The prek hook that fails a commit when a staged file is missing the sidecar
# Godot keeps beside it: a .import file for each asset it imports, and a .uid
# file for each script, shader and video. A commit that left one out has broken
# a fresh checkout at least six times (54ff0b9, 9e72d69, ec53f69, 011cb96,
# 18cf5c3, 37de6ed). SIDECAR_SUFFIX lists every file type the repo tracks a
# sidecar for, so a new type needs a line there before the hook guards it.
from __future__ import annotations

import sys
from collections.abc import Collection, Sequence
from pathlib import PurePosixPath

from urchin_dev.checks import indexed_paths

SIDECAR_SUFFIX = {
    ".fnt": ".import",
    ".mp3": ".import",
    ".otf": ".import",
    ".png": ".import",
    ".svg": ".import",
    ".ttf": ".import",
    ".gd": ".uid",
    ".gdshader": ".uid",
    ".ogv": ".uid",
}


def godot_ignores(path: str, index: Collection[str]) -> bool:
    """Godot skips a folder holding a `.gdignore`, and everything under it, so
    it writes no sidecars there. Only a committed `.gdignore` counts, because a
    fresh checkout has no other."""
    return any(
        str(folder / ".gdignore") in index for folder in PurePosixPath(path).parents
    )


def missing_sidecars(paths: Sequence[str], index: Collection[str]) -> list[str]:
    missing = []
    for path in paths:
        sidecar_suffix = SIDECAR_SUFFIX.get(PurePosixPath(path).suffix)
        if (
            sidecar_suffix
            and not godot_ignores(path, index)
            and path + sidecar_suffix not in index
        ):
            missing.append(path + sidecar_suffix)
    return missing


def main() -> int:
    missing = missing_sidecars(sys.argv[1:], indexed_paths())
    for sidecar in missing:
        print(
            f"{sidecar} is neither staged nor tracked. Godot writes it when it"
            " imports the project, so run the --import command in AGENTS.md and"
            " stage it.",
            file=sys.stderr,
        )
    return 1 if missing else 0
