from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = Path(__file__).resolve().parent

FFDEC = Path.home() / ".local" / "bin" / "ffdec"

CONVERTED_JSON = SCRIPTS_ROOT / "converted_json"
DATA_JSON = SCRIPTS_ROOT / "data_json"

SOURCE_FILES = REPO_ROOT / "source_files"
ACTION_SCRIPT = SOURCE_FILES / "action_script"
ACTION_SCRIPT_CURATED = SOURCE_FILES / "action_script_curated"
SWF_XML = SOURCE_FILES / "swf_xml"

WEB_SWF_XML = SWF_XML / "sonny-2-2900.xml"
STEAM_SWF_XML = SWF_XML / "SONNY2_steam.xml"

WEB_SWF = REPO_ROOT / "sonny-2-2900.swf"
STEAM_SWF = REPO_ROOT / "SONNY2.swf"
