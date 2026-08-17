from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEV_ROOT = Path(__file__).resolve().parents[1]

FFDEC = Path.home() / ".local" / "bin" / "ffdec"

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
