# godot.py
# Where the Godot binary is, and how many Godot processes run at once. The
# binary is at a different path on each machine, so every script that runs
# Godot asks this module. The limit keeps parallel agents from running more
# Godot processes than the machine has memory for.
from __future__ import annotations

import fcntl
import os
import shutil
import tempfile
import time
from collections.abc import Iterator
from contextlib import ExitStack, contextmanager
from pathlib import Path
from typing import IO

MAC_APP = Path("/Applications/Godot.app/Contents/MacOS/Godot")
SLOT_DIR = Path(tempfile.gettempdir()) / "urchin-godot-slots"


def godot_bin(env: dict[str, str] | None = None) -> str:
    """$GODOT_BIN when it is set, else `godot` on PATH, else the macOS app.
    Exits with a message that names all three when none of them exists."""
    env = os.environ if env is None else env
    if env.get("GODOT_BIN"):
        return env["GODOT_BIN"]
    found = shutil.which("godot", path=env.get("PATH"))
    if found:
        return found
    if MAC_APP.exists():
        return str(MAC_APP)
    raise SystemExit(
        "no Godot found. Set GODOT_BIN, put `godot` on PATH, or install "
        f"Godot at {MAC_APP}."
    )


def slot_count(env: dict[str, str] | None = None) -> int:
    """$GODOT_SLOTS, the most Godot processes that run at once. It is the
    number of CPU cores when it is unset, "auto" or not a number."""
    env = os.environ if env is None else env
    cores = os.cpu_count() or 1
    try:
        return max(1, int(env.get("GODOT_SLOTS", "auto")))
    except ValueError:
        return cores


@contextmanager
def godot_slot(
    slots: int | None = None, slot_dir: Path | None = None
) -> Iterator[None]:
    """Holds one of `slots` lock files until the block ends, and waits when all
    of them are held. The operating system drops a lock when its process dies,
    so a crashed run never leaves a slot taken."""
    slots = slot_count() if slots is None else slots
    slot_dir = SLOT_DIR if slot_dir is None else slot_dir
    slot_dir.mkdir(parents=True, exist_ok=True)
    with ExitStack() as stack:
        files = [
            stack.enter_context((slot_dir / f"slot-{n}.lock").open("w"))
            for n in range(slots)
        ]
        while not any(try_lock(file) for file in files):
            time.sleep(0.5)
        yield


def try_lock(file: IO[str]) -> bool:
    try:
        fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return False
    return True
