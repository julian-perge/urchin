# setup_worktree.py
# Readies a new git worktree of urchin for tests and extractors. The two SWFs
# are gitignored, so a worktree has none, and every extractor that reads one
# fails with "No such file". The post-checkout hook skips the first checkout of
# a new worktree, so it also has no .godot/ cache, and GUT fails with "Could
# not find type" until an import runs. This links each SWF from the main
# checkout and then runs Godot's import, through the shared slot script when it
# exists so parallel agents stay under the machine's Godot limit.
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from urchin_dev import REPO_ROOT, STEAM_SWF, WEB_SWF
from urchin_dev.run import run

GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
GODOT_SLOT = Path.home() / "tmp" / "2026-11-07-godot-slots" / "godot-slot.fish"
SWF_NAMES = (WEB_SWF.name, STEAM_SWF.name)


def main_checkout() -> Path:
    """Every worktree shares the main checkout's .git directory, so its parent
    is the main checkout."""
    common = run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"])
    return Path(common.stdout.strip()).parent


def swf_links(worktree: Path, main: Path) -> list[tuple[Path, Path]]:
    """Each (link, target) pair to create: a SWF the main checkout has and the
    worktree lacks. A worktree that is the main checkout needs none."""
    if worktree.resolve() == main.resolve():
        return []
    return [
        (worktree / name, main / name)
        for name in SWF_NAMES
        if (main / name).exists() and not (worktree / name).exists()
    ]


def godot_import_command(godot: Path, slot: Path, fish: str | None) -> list[str]:
    command = [str(godot), "--headless", "--import", "--path", str(REPO_ROOT)]
    if slot.exists() and fish:
        return [fish, str(slot), *command]
    return command


def main() -> None:
    main = main_checkout()
    for link, target in swf_links(REPO_ROOT, main):
        link.symlink_to(target)
        print(f"linked {link.name} from {main}")
    missing = [name for name in SWF_NAMES if not (REPO_ROOT / name).exists()]
    if missing:
        print(
            f"no {', '.join(missing)} in {main}, so extractors that read it will fail"
        )
    if not GODOT.exists():
        sys.exit(f"no Godot at {GODOT}, so the import did not run")
    command = godot_import_command(GODOT, GODOT_SLOT, shutil.which("fish"))
    print("running Godot's import")
    sys.exit(subprocess.run(command, cwd=REPO_ROOT).returncode)
