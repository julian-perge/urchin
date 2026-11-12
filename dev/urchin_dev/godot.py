# godot.py
# Which Godot binary to run, and how many Godot processes run at once. The
# justfile picks the binary for the machine and passes it in GODOT_BIN, so
# every script that runs Godot asks this module. The limit keeps parallel
# agents from running more Godot processes than the machine has memory for.
from __future__ import annotations

import fcntl
import os
import tempfile
import time
from collections.abc import Iterator
from contextlib import ExitStack, contextmanager
from pathlib import Path
from typing import IO

SLOT_DIR = Path(tempfile.gettempdir()) / "urchin-godot-slots"


def godot_bin(env: dict[str, str] | None = None) -> str:
    """$GODOT_BIN. The justfile sets it for every recipe, so a run outside
    `just` exits with a message that says so."""
    env = os.environ if env is None else env
    if not env.get("GODOT_BIN"):
        raise SystemExit("GODOT_BIN is not set. Run this through `just`.")
    return env["GODOT_BIN"]


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
