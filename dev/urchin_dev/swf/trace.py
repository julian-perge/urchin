# trace.py
# Builds a Traced copy of one build of the original. It exports the scripts of
# the build's SWF in URCHIN_SWF_DIR to a temporary folder with ffdec, puts each
# Probe file of dev/probes/ in front of the build's own frame_1/DoAction.as, and
# compiles the result back into the first frame with `ffdec -replace`. The
# Traced copy goes to $URCHIN_SWF_DIR/traced/ under the build's file name, and
# its path is printed.
#
# Each build gets its own export, because the Steam build's first frame script
# is not in the repo, and dev/source_files/action_script/ is the web build's.
#
# It also reads a Trace log, which is the raw log of a player that ran a Traced
# copy, and compares two of them. Only the GOTO lines of the goto Probe are
# read. The comparison needs no SWF, no ffdec and no label data.
#
# trace_run plays a Traced copy in the Flash debug player or in Ruffle and, when
# the player quits, saves the raw player log as
# references/traced_runs/<build>_<player>.txt. The Flash log is a copy of the
# player's flashlog.txt, and the Ruffle log is Ruffle's stdout and stderr. The
# player paths come from FLASH_DEBUG_PLAYER and RUFFLE_BIN. It runs on macOS,
# and on Linux under WSL2, where the Flash player is the Windows debug player
# (a .exe) and reads its mm.cfg and writes its flashlog.txt in the Windows
# profile.
#
# Run: uv run trace_swf <web|steam>
#      uv run trace_run <web|steam> <flash|ruffle>
#      uv run trace_diff <log a> <log b>
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

from urchin_dev import DEV_ROOT, FFDEC, REPO_ROOT, STEAM_SWF, SWF_DIR, WEB_SWF
from urchin_dev.run import run

PROBES = DEV_ROOT / "probes"
TRACED_DIR = SWF_DIR / "traced"
BUILDS = {"web": WEB_SWF, "steam": STEAM_SWF}
GOTO_MARK = "GOTO\t"
HOOK_LINE = "HOOK\tinstalled\ttrue"

TRACED_RUNS = REPO_ROOT / "references" / "traced_runs"
MM_CFG_LINE = "TraceOutputFileEnable=1"
MACOS_FLASHLOG = "Library/Preferences/Macromedia/Flash Player/Logs/flashlog.txt"
WINDOWS_FLASHLOG = "Macromedia/Flash Player/Logs/flashlog.txt"
# The sandboxed Ruffle app opens a SWF only inside its own container, so a
# Ruffle run plays a copy of the Traced copy from this folder.
RUFFLE_CONTAINER = (
    Path.home() / "Library/Containers/rs.ruffle.ruffle/Data/urchin_traced"
)
# Each player's environment variable and its default binary.
PLAYERS = {
    "flash": (
        "FLASH_DEBUG_PLAYER",
        "~/Games/Flashpoint_14/FPSoftware/Flash/Flash 14.app/Contents/MacOS/Flash Player Debugger",
    ),
    "ruffle": ("RUFFLE_BIN", "/Applications/Ruffle.app/Contents/MacOS/ruffle"),
}


@dataclass(frozen=True)
class Goto:
    kind: str
    clip: str
    total_frames: int
    before: int
    target: str
    after: int


@dataclass(frozen=True, order=True)
class DiffRecord:
    kind: str
    clip: str
    total_frames: int
    target: str
    moved: bool


def read_probes(folder: Path) -> list[str]:
    """Return the text of each .as file in `folder`, in name order."""
    return [path.read_text(encoding="utf-8") for path in sorted(folder.glob("*.as"))]


def with_probes(frame_script: str, probes: Sequence[str]) -> str:
    """Return `frame_script` with each Probe in front of it, each ending in one
    newline. The frame script itself is not changed."""
    return "".join(probe.rstrip("\n") + "\n" for probe in probes) + frame_script


def trace_swf(swf: Path) -> Path:
    """Write the Traced copy of `swf` and return its path."""
    traced = TRACED_DIR / swf.name
    traced.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        export = Path(tmp) / "export"
        run([FFDEC, "-export", "script", export, swf])
        frame_script = (export / "scripts/frame_1/DoAction.as").read_text(
            encoding="utf-8", newline=""
        )
        script = Path(tmp) / "DoAction.as"
        script.write_text(
            with_probes(frame_script, read_probes(PROBES)), encoding="utf-8", newline=""
        )
        run([FFDEC, "-replace", swf, traced, "/frame_1/DoAction", script])
    return traced


def parse(text: str) -> list[Goto]:
    """Return one record for each GOTO line of a Trace log. A line is read from
    its first `GOTO<tab>`, so a player's prefix does not matter, and every other
    line is skipped."""
    gotos = []
    for number, line in enumerate(text.splitlines(), start=1):
        _, mark, rest = line.partition(GOTO_MARK)
        if not mark:
            continue
        fields = rest.split("\t")
        try:
            kind, clip, total_frames, before, target, after = fields
            gotos.append(
                Goto(kind, clip, int(total_frames), int(before), target, int(after))
            )
        except ValueError as error:
            raise ValueError(
                f"line {number}: bad GOTO line {line!r}: {error}"
            ) from None
    return gotos


def diff_records(gotos: Iterable[Goto]) -> set[DiffRecord]:
    """Return the distinct gotos of a log. `moved` is true when at least one
    occurrence of that goto changed the frame."""
    moved: dict[tuple[str, str, int, str], bool] = {}
    for goto in gotos:
        key = (goto.kind, goto.clip, goto.total_frames, goto.target)
        moved[key] = moved.get(key, False) or goto.before != goto.after
    return {DiffRecord(*key, did_move) for key, did_move in moved.items()}


def diff(
    a: Iterable[Goto], b: Iterable[Goto]
) -> tuple[list[DiffRecord], list[DiffRecord]]:
    """Return the diff records that only `a` has and those that only `b` has,
    each sorted."""
    records_a = diff_records(a)
    records_b = diff_records(b)
    return sorted(records_a - records_b), sorted(records_b - records_a)


def diff_main(argv: Sequence[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        raise SystemExit("usage: trace_diff <log a> <log b>")
    logs = [Path(arg) for arg in args]
    for log in logs:
        if not log.is_file():
            raise SystemExit(f"error: no Trace log at {log}.")
    gotos = []
    for log in logs:
        try:
            gotos.append(parse(log.read_text(encoding="utf-8")))
        except ValueError as error:
            raise SystemExit(f"error: {log}: {error}") from None
    sides = diff(*gotos)
    for log, records in zip(logs, sides, strict=True):
        print(f"only in {log} ({len(records)}):")
        for record in records:
            state = "moved" if record.moved else "stayed"
            print(
                f"{record.kind}\t{record.clip}\t{record.total_frames}\t{record.target}\t{state}"
            )


def is_windows_player(binary: Path) -> bool:
    return binary.suffix.lower() == ".exe"


def windows_folder(variable: str) -> Path:
    """Return the folder that a Windows environment variable, such as
    USERPROFILE, names, as a WSL path."""
    # cmd.exe starts in /mnt/c, because it warns about a working folder that is
    # a WSL path.
    folder = subprocess.run(
        ["cmd.exe", "/c", f"echo %{variable}%"],
        capture_output=True,
        text=True,
        check=True,
        cwd="/mnt/c",
    ).stdout.strip()
    return Path(
        subprocess.run(
            ["wslpath", "-u", folder], capture_output=True, text=True, check=True
        ).stdout.strip()
    )


def flash_files(binary: Path, windows_folder=windows_folder) -> tuple[Path, Path]:
    """Return the mm.cfg that the Flash debug player at `binary` reads and the
    flashlog.txt it writes."""
    if is_windows_player(binary):
        return (
            windows_folder("USERPROFILE") / "mm.cfg",
            windows_folder("APPDATA") / WINDOWS_FLASHLOG,
        )
    return Path.home() / "mm.cfg", Path.home() / MACOS_FLASHLOG


def ruffle_env(platform: str, environ: dict[str, str]) -> dict[str, str]:
    """Return the environment Ruffle runs in."""
    # Under WSLg, Ruffle 0.8.0 on Wayland stops within a second with "Event
    # loop failure", and on X11 it plays on (#492). Without WAYLAND_DISPLAY it
    # takes X11.
    if platform == "linux":
        return {
            name: value for name, value in environ.items() if name != "WAYLAND_DISPLAY"
        }
    return dict(environ)


def preflight(player: str, *, platform: str, binary: Path, mm_cfg: Path) -> None:
    """Stop with a message when this machine cannot play a Traced run in
    `player`."""
    if platform not in ("darwin", "linux"):
        raise SystemExit(
            f"error: trace-run needs macOS, or Linux on WSL2. This OS is {platform}."
        )
    if not binary.is_file():
        raise SystemExit(
            f"error: no {player} player at {binary}. Set {PLAYERS[player][0]}."
        )
    if player == "flash" and platform == "linux" and not is_windows_player(binary):
        raise SystemExit(
            f"error: {binary} is not a .exe. On Linux, trace-run plays Flash only in"
            " the Windows debug player through WSL2. Set FLASH_DEBUG_PLAYER."
        )
    if player == "flash":
        lines = (
            mm_cfg.read_text(encoding="utf-8").splitlines() if mm_cfg.is_file() else []
        )
        if MM_CFG_LINE not in (line.strip() for line in lines):
            raise SystemExit(
                f"error: {mm_cfg} does not have {MM_CFG_LINE}, "
                "so the debug player writes no flashlog.txt. Add that line."
            )


def play_flash(binary: Path, traced: Path | str, flashlog: Path, dest: Path) -> None:
    """Play `traced` in the Flash debug player, wait until it quits, and copy
    its flashlog.txt to `dest`. A Windows player gets `traced` as a Windows
    path."""
    # The player empties flashlog.txt at each launch. Deleting it first means
    # that a player which fails to start cannot leave the log of an older
    # launch to be saved as this run.
    flashlog.unlink(missing_ok=True)
    subprocess.run([binary, traced])
    if not flashlog.is_file():
        raise SystemExit(f"error: the player wrote no log at {flashlog}.")
    shutil.copyfile(flashlog, dest)


def play_ruffle(
    binary: Path,
    traced: Path,
    container: Path | None,
    dest: Path,
    env: dict[str, str] | None = None,
) -> None:
    """Play `traced` with Ruffle in `env`, wait until it quits, and save its
    output as `dest`. With a `container`, Ruffle plays a copy of `traced` in
    that folder."""
    if container is not None:
        container.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(traced, container / traced.name)
        traced = container / traced.name
    with dest.open("wb") as log:
        # Ruffle 0.7.1 on macOS and 0.8.0 on WSL2 write their log, with the
        # trace() lines, as "INFO avm_trace:" lines. Both streams are saved, so
        # the trace() lines are in the log whichever stream they go to.
        subprocess.run([binary, traced], stdout=log, stderr=subprocess.STDOUT, env=env)


def report(log: Path) -> None:
    """Print the number of GOTO lines of `log`, and exit 1 when it has no HOOK
    line."""
    text = log.read_text(encoding="utf-8", errors="replace")
    print(f"{log}: {len(parse(text))} GOTO lines")
    if not any(HOOK_LINE in line for line in text.splitlines()):
        raise SystemExit(
            f"error: {log} has no HOOK<tab>installed<tab>true line, "
            "so the goto Probe did not install."
        )


def run_main(argv: Sequence[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2 or args[0] not in BUILDS or args[1] not in PLAYERS:
        raise SystemExit(f"usage: trace_run <{'|'.join(BUILDS)}> <{'|'.join(PLAYERS)}>")
    build, player = args
    variable, default = PLAYERS[player]
    binary = Path(os.environ.get(variable, default)).expanduser()
    mm_cfg, flashlog = flash_files(binary)
    preflight(player, platform=sys.platform, binary=binary, mm_cfg=mm_cfg)
    swf = BUILDS[build]
    if not swf.is_file():
        raise SystemExit(f"error: no SWF at {swf}. Set URCHIN_SWF_DIR.")
    traced = trace_swf(swf)
    TRACED_RUNS.mkdir(parents=True, exist_ok=True)
    dest = TRACED_RUNS / f"{build}_{player}.txt"
    if player == "flash" and is_windows_player(binary):
        # The Windows player opens the Traced copy in the WSL file system
        # through its \\wsl.localhost path (#492).
        windows_path = subprocess.run(
            ["wslpath", "-w", traced], capture_output=True, text=True, check=True
        ).stdout.strip()
        play_flash(binary, windows_path, flashlog, dest)
    elif player == "flash":
        play_flash(binary, traced, flashlog, dest)
    else:
        container = RUFFLE_CONTAINER if sys.platform == "darwin" else None
        play_ruffle(
            binary, traced, container, dest, ruffle_env(sys.platform, dict(os.environ))
        )
    report(dest)


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in BUILDS:
        raise SystemExit(f"usage: trace_swf <{'|'.join(BUILDS)}>")
    swf = BUILDS[sys.argv[1]]
    if not swf.is_file():
        raise SystemExit(f"error: no SWF at {swf}. Set URCHIN_SWF_DIR.")
    print(trace_swf(swf))


if __name__ == "__main__":
    main()
