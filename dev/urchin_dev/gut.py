# gut.py
# `uv run gut`, the command that runs the GUT suite, or only the test files it
# is given. GUT 9.7.1 exits 0 on some runs that failed: a test file that does
# not parse prints "SCRIPT ERROR" and "Nothing was run", and the exit code still
# reads as a pass (~/.config/papercuts.md, 2026-11-10). So this command also
# fails a run whose log has a script or parse error, or that ran no tests.
# It also fails a run in which Godot reports objects or resources still alive
# at exit, because such a leak shows no failing test (julian-perge/urchin#187).
from __future__ import annotations

import re
import shutil
import sys
import tempfile
from collections.abc import Callable, Sequence
from pathlib import Path

from urchin_dev import REPO_ROOT
from urchin_dev.godot import godot_bin, godot_slot
from urchin_dev.run import stream

# Godot colors its log even when the log goes to a pipe.
COLOR_CODE = re.compile(r"\x1b\[[0-9;]*m")
TESTS_TOTAL = re.compile(r"^Tests +(\d+)$", re.MULTILINE)

# The Path is the HOME the Godot process gets. None means Godot gets the real HOME.
Godot = Callable[[Sequence[str], Path | None], tuple[int, str]]


def godot_command(args: Sequence[str], home: Path | None) -> list[str | Path]:
    """The command that runs Godot. `env` sets the new HOME for the Godot
    process only."""
    env = ["env", f"HOME={home}"] if home is not None else []
    return [*env, godot_bin(), *args]


def godot_in_a_slot(args: Sequence[str], home: Path | None = None) -> tuple[int, str]:
    with godot_slot():
        return stream(godot_command(args, home))


def failures(code: int, log: str) -> list[str]:
    text = COLOR_CODE.sub("", log)
    reasons = []
    if code != 0:
        reasons.append(f"Godot exited with code {code}")
    for marker in (
        "SCRIPT ERROR",
        "Parse Error",
        "leaked at exit",
        "still in use at exit",
    ):
        if marker in text:
            reasons.append(f"the log has {marker!r}")
    tests_ran = [int(count) for count in TESTS_TOTAL.findall(text)]
    if "Nothing was run" in text or not any(tests_ran):
        reasons.append("GUT ran no tests")
    return reasons


def res_path(arg: str, cwd: Path, root: Path) -> str:
    """A test file named by a res:// path, or by a path from the shell's folder,
    as the res:// path GUT takes. Exits when the file is not in the project."""
    if arg.startswith("res://"):
        path = (root / arg.removeprefix("res://")).resolve()
    else:
        path = (cwd / arg).resolve()
    if not path.is_file() or not path.is_relative_to(root):
        raise SystemExit(f"uv run gut: {arg} is not a test file in {root}.")
    return f"res://{path.relative_to(root).as_posix()}"


def gut_args(argv: Sequence[str], cwd: Path, root: Path) -> list[str]:
    """GUT 9.7.1 adds -gtest files to the dirs in .gutconfig.json instead of
    running them alone, so a run of named files also clears the dirs with an
    empty -gdir=. Arguments that start with -g are GUT options and pass through
    unchanged."""
    args = ["--headless", "-s", "res://addons/gut/gut_cmdln.gd", "--path", str(root)]
    options = [arg for arg in argv if arg.startswith("-g")]
    tests = [res_path(arg, cwd, root) for arg in argv if not arg.startswith("-g")]
    if tests:
        args += ["-gdir=", "-gtest=" + ",".join(tests)]
    return args + options


def run_gut(argv: Sequence[str], cwd: Path, root: Path, godot: Godot) -> int:
    root = root.resolve()
    args = gut_args(argv, cwd, root)
    if not (root / ".godot").is_dir():
        print("uv run gut: there is no .godot/ import cache, so importing first.")
        code, _ = godot(["--headless", "--import", "--path", str(root)], None)
        if code != 0:
            print(f"uv run gut: the import exited with code {code}.", file=sys.stderr)
            return code
    # Godot builds user:// from HOME on macOS and Linux, so a new HOME gives the run a user://
    # of its own. Runs from other checkouts, and the real game, never share it.
    home = Path(tempfile.mkdtemp(prefix="urchin-gut-home-"))
    try:
        code, log = godot(args, home)
    finally:
        shutil.rmtree(home, ignore_errors=True)
    reasons = failures(code, log)
    for reason in reasons:
        print(f"uv run gut: the run failed because {reason}.", file=sys.stderr)
    return (code or 1) if reasons else 0


def main() -> int:
    return run_gut(sys.argv[1:], Path.cwd(), REPO_ROOT, godot_in_a_slot)
