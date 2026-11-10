# godot_sidecars.py
# The prek hook that fails a commit when a staged PNG or script is missing the
# sidecar Godot keeps beside it: a .import file for every PNG it imports and a
# .uid file for every script. A commit that left one out has broken a fresh
# checkout at least six times (54ff0b9, 9e72d69, ec53f69, 011cb96, 18cf5c3,
# 37de6ed). The sidecar counts when the git index holds it, whether this commit
# stages it or an earlier one committed it.
from __future__ import annotations

import sys
from collections.abc import Collection, Sequence
from pathlib import PurePosixPath

from urchin_dev.run import run

SIDECAR_SUFFIX = {".png": ".import", ".gd": ".uid"}


def indexed_paths() -> set[str]:
    """Every path in the git index, which is what the commit will hold."""
    return set(filter(None, run(["git", "ls-files", "-z"]).stdout.split("\0")))


def godot_ignores(path: str, index: Collection[str]) -> bool:
    """Whether a folder holding `path` has a `.gdignore` in the index. Godot
    skips that folder and everything under it, so it writes no sidecars there."""
    return any(
        str(folder / ".gdignore") in index for folder in PurePosixPath(path).parents
    )


def missing_sidecars(paths: Sequence[str], index: Collection[str]) -> list[str]:
    """The sidecars `paths` need that the index lacks, in the order of `paths`."""
    missing = []
    for path in paths:
        suffix = SIDECAR_SUFFIX.get(PurePosixPath(path).suffix)
        if suffix and not godot_ignores(path, index) and path + suffix not in index:
            missing.append(path + suffix)
    return missing


def main(argv: Sequence[str] | None = None) -> int:
    missing = missing_sidecars(sys.argv[1:] if argv is None else argv, indexed_paths())
    for sidecar in missing:
        print(
            f"{sidecar} is neither staged nor tracked. Godot writes it when it"
            " imports the project, so run the --import command in AGENTS.md and"
            " stage it.",
            file=sys.stderr,
        )
    return 1 if missing else 0
