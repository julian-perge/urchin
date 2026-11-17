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
# Run: uv run trace_swf <web|steam>
from __future__ import annotations

import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path

from urchin_dev import DEV_ROOT, FFDEC, STEAM_SWF, SWF_DIR, WEB_SWF
from urchin_dev.run import run

PROBES = DEV_ROOT / "probes"
TRACED_DIR = SWF_DIR / "traced"
BUILDS = {"web": WEB_SWF, "steam": STEAM_SWF}


def read_probes(folder: Path) -> list[str]:
    """Return the text of each .as file in `folder`, in name order."""
    return [path.read_text() for path in sorted(folder.glob("*.as"))]


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
        # Bytes keep the export's own line endings in the frame script.
        frame_script = (export / "scripts/frame_1/DoAction.as").read_bytes()
        script = Path(tmp) / "DoAction.as"
        script.write_bytes(
            with_probes(frame_script.decode("utf-8"), read_probes(PROBES)).encode(
                "utf-8"
            )
        )
        run([FFDEC, "-replace", swf, traced, "/frame_1/DoAction", script])
    return traced


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in BUILDS:
        raise SystemExit(f"usage: trace_swf <{'|'.join(BUILDS)}>")
    swf = BUILDS[sys.argv[1]]
    if not swf.is_file():
        raise SystemExit(f"error: no SWF at {swf}. Set URCHIN_SWF_DIR.")
    print(trace_swf(swf))


if __name__ == "__main__":
    main()
