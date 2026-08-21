from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEV_ROOT = Path(__file__).resolve().parents[1]

FFDEC = Path.home() / ".local" / "bin" / "ffdec"

# Force every ffdec run headless. Its launcher script adds
# "-Xdock:name=FFDec -Xdock:icon=icon.png" on macOS and sets no headless
# property, so each export registers a Dock application that can take focus
# mid-run. Setting the property wins over those flags (verified: with -Xdock
# alone GraphicsEnvironment.isHeadless() is false, with both it is true), and
# it does not change what ffdec draws - sprite PNG exports come back
# byte-identical, glyph rendering included. Set here because the launcher
# reads no variable for extra JVM options, so there is nowhere closer to the
# call sites to put it; subprocesses inherit it. Only Java processes read it,
# so the Godot test runs are unaffected. setdefault, to stay overridable.
os.environ.setdefault("JAVA_TOOL_OPTIONS", "-Djava.awt.headless=true")

CONVERTED_JSON = DEV_ROOT / "converted_json"
DATA_JSON = DEV_ROOT / "data_json"

SOURCE_FILES = DEV_ROOT / "source_files"
ACTION_SCRIPT = SOURCE_FILES / "action_script"
ACTION_SCRIPT_CURATED = SOURCE_FILES / "action_script_curated"
SWF_XML = SOURCE_FILES / "swf_xml"

WEB_SWF_XML = SWF_XML / "sonny-2-2900.xml"
STEAM_SWF_XML = SWF_XML / "SONNY2_steam.xml"

WEB_SWF = REPO_ROOT / "sonny-2-2900.swf"
STEAM_SWF = REPO_ROOT / "SONNY2.swf"

# The web SWF with every runtime-hidden overlay character deleted, so ffdec's
# own renderer draws what the game draws. Built by prepare_extract_swf.py,
# which explains what is stripped and why. Gitignored like every other .swf.
WEB_SWF_EXTRACT = REPO_ROOT / "sonny-2-2900.extract.swf"


def require_data_json(file_name: str) -> Path:
    """Resolve a converter input in data_json/, failing with a usable message.

    These dumps are runtime AMF captures of the game's live _root arrays. No
    script in this repo produces them, so a missing one cannot be rebuilt -
    it has to come back out of git history.
    """
    path = DATA_JSON / file_name
    if not path.is_file():
        raise SystemExit(
            f"Missing converter input: {path}\n"
            f"Restore it with:\n"
            f"  git show ccf7375^:python_conversion_scripts/data_json/{file_name} > {path}"
        )
    return path
