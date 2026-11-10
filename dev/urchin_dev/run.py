# run.py
# The two wrappers every external command goes through. run() is for the ffdec
# CLI, the ffdec_lib driver, ffmpeg, ffprobe and git. Its output is always
# captured and a failure always raises with all of it, because a wrapper that
# let ffdec's stderr scroll past, or swallowed it, is how several of the
# extractors' own copies of this hid why a render failed. stream() is for
# Godot in `uv run gut`, which a person watches as it runs. It prints each line
# when it arrives and also returns all of them, so the caller can read the log
# for failures that GUT exits 0 on.
from __future__ import annotations

import subprocess
import sys
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


def stream(cmd: Sequence[str | Path]) -> tuple[int, str]:
    """Run `cmd` with its stderr joined to its stdout, print each line as it
    arrives, and return the exit code and the whole log."""
    lines = []
    with subprocess.Popen(
        [str(arg) for arg in cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    ) as proc:
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            lines.append(line)
    return proc.returncode, "".join(lines)
