# export_swf_sources.py
# Regenerates everything in source_files/ from the two SWFs at the repo
# root, using ffdec (JPEXS decompiler CLI at ~/.local/bin/ffdec):
#   source_files/action_script/  - full script export of the web SWF (~2s)
#   source_files/swf_xml/        - swf2xml dumps of BOTH SWFs (the Steam
#                                  dump fills asset gaps: DOG/WOLF art etc.)
#
# Run: uv run python3 conversion_scripts/swf_extraction/export_swf_sources.py
from __future__ import annotations

import subprocess
import sys

from .. import (
    ACTION_SCRIPT,
    FFDEC,
    STEAM_SWF,
    STEAM_SWF_XML,
    SWF_XML,
    WEB_SWF,
    WEB_SWF_XML,
)


def run(args):
    print("$", " ".join(str(a) for a in args), file=sys.stderr)
    subprocess.run([str(a) for a in args], check=True)


def main():
    SWF_XML.mkdir(parents=True, exist_ok=True)
    ACTION_SCRIPT.parent.mkdir(parents=True, exist_ok=True)
    # Full script export lands in <dir>/scripts/ - export to a temp sibling
    # then keep the scripts tree as action_script/.
    tmp = ACTION_SCRIPT.parent / "_action_script_export"
    run([FFDEC, "-export", "script", tmp, WEB_SWF])
    if ACTION_SCRIPT.exists():
        subprocess.run(["rm", "-rf", str(ACTION_SCRIPT)], check=True)
    (tmp / "scripts").rename(ACTION_SCRIPT)
    subprocess.run(["rm", "-rf", str(tmp)], check=True)
    run([FFDEC, "-swf2xml", WEB_SWF, WEB_SWF_XML])
    run([FFDEC, "-swf2xml", STEAM_SWF, STEAM_SWF_XML])
    # Every image asset: raw bitmaps, shape renders (2x), full frame renders
    # (2x) - the frame renders are the ground truth for screen layouts.
    assets = SWF_XML.parent / "exported_assets"
    run([FFDEC, "-export", "image", assets / "images", WEB_SWF])
    run(
        [
            FFDEC,
            "-zoom",
            "2",
            "-format",
            "shape:png",
            "-export",
            "shape",
            assets / "shapes",
            WEB_SWF,
        ]
    )
    run([FFDEC, "-zoom", "2", "-export", "frame", assets / "frames", WEB_SWF])
    # Keep Godot from importing the export tree.
    (SWF_XML.parent / ".gdignore").touch()


if __name__ == "__main__":
    main()
