# setup_worktree.py
# Readies a new git worktree of urchin for tests and extractors. The
# post-checkout hook skips the first checkout of a new worktree, so it has no
# .godot/ cache, and GUT fails with "Could not find type" until an import runs.
# This runs Godot's import in a Godot slot, so parallel agents stay under the
# machine's Godot limit. The SWFs need no setup here, because every checkout
# reads them from URCHIN_SWF_DIR (see urchin_dev/__init__.py).
from __future__ import annotations

import subprocess
import sys

from urchin_dev import REPO_ROOT, STEAM_SWF, SWF_DIR, WEB_SWF
from urchin_dev.godot import godot_bin, godot_slot


def godot_import_command(godot: str) -> list[str]:
    return [godot, "--headless", "--import", "--path", str(REPO_ROOT)]


def main() -> None:
    missing = [swf.name for swf in (WEB_SWF, STEAM_SWF) if not swf.exists()]
    if missing:
        print(
            f"no {', '.join(missing)} in {SWF_DIR}, so extractors that read it"
            " will fail. Set URCHIN_SWF_DIR to the folder that holds the SWFs."
        )
    command = godot_import_command(godot_bin())
    print("running Godot's import")
    with godot_slot():
        sys.exit(subprocess.run(command, cwd=REPO_ROOT).returncode)
