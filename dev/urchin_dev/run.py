# run.py
# The one wrapper every external command goes through: the ffdec CLI, the
# ffdec_lib driver, ffmpeg and ffprobe. Output is always captured and a
# failure always raises with all of it, because a wrapper that let ffdec's
# stderr scroll past, or swallowed it, is how several of the extractors'
# own copies of this hid why a render failed.
from __future__ import annotations

import subprocess
from collections.abc import Sequence
from pathlib import Path


def run(cmd: Sequence[str | Path]) -> subprocess.CompletedProcess[str]:
    """Run `cmd` and return its result, raising RuntimeError with the
    command, exit code, stdout and stderr when it exits non-zero."""
    args = [str(arg) for arg in cmd]
    proc = subprocess.run(args, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(args)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc
