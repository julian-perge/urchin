# gd_parse.py
# The prek hook that fails a commit when a staged .gd file does not parse. A
# multi-line edit once joined a comment to the `static func` line below it. The
# GUT run that followed failed 92 tests with "Cannot infer the type" errors, and
# only `Godot --check-only` on that one file named the real cause.
#
# `--check-only` exits 0 on macOS even when the script is broken, and exits 1 on
# Linux for a Compile Error, so the hook reads the log and ignores the exit
# code. It reports only "Parse Error" lines. Every script that names an
# autoload also logs "Compile Error: Identifier not found", because `--check-only`
# compiles a script without the project's autoloads. That is not a real error,
# so the hook leaves Compile Errors to the GUT run.
from __future__ import annotations

import re
import subprocess
import sys
from collections.abc import Sequence

from urchin_dev import REPO_ROOT
from urchin_dev.godot import godot_bin

COLOR_CODE = re.compile(r"\x1b\[[0-9;]*m")
PARSE_ERROR = re.compile(r"^SCRIPT ERROR: Parse Error: .*\n\s+at: .*$", re.MULTILINE)


def parse_errors(log: str) -> list[str]:
    """Each Parse Error in the log, with the `at:` line that locates it."""
    return PARSE_ERROR.findall(COLOR_CODE.sub("", log))


def check_script(path: str) -> list[str]:
    result = subprocess.run(
        [godot_bin(), "--headless", "--path", str(REPO_ROOT), "--check-only"]
        + ["-s", f"res://{path}"],
        capture_output=True,
        text=True,
    )
    return parse_errors(result.stdout + result.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    failed = False
    for path in sys.argv[1:] if argv is None else argv:
        for error in check_script(path):
            print(error, file=sys.stderr)
            failed = True
    return 1 if failed else 0
