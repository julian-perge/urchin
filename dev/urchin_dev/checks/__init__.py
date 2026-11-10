from __future__ import annotations

from urchin_dev.run import run


def indexed_paths() -> set[str]:
    """The commit will hold exactly the paths in the git index, staged and
    tracked alike, so the hooks check against these rather than the disk."""
    return set(filter(None, run(["git", "ls-files", "-z"]).stdout.split("\0")))
