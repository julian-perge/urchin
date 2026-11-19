# The sounds each doll model of extract_model_animations plays from its own
# frame scripts, such as the swing whoosh on the frames of its attack labels.
# Output: dev/converted_json/<model>_sound_cues.json, such as
# model4_sound_cues.json, each {"<1-based frame>": ["<cue>", ...]} in frame
# order. CharacterVisual plays a cue when the doll's playhead reaches its frame.
#
# Run: uv run convert_model_sound_cues
from __future__ import annotations

import json
import re

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON
from urchin_dev.swf.extract.model_animations import MODELS

ADD_SOUND = re.compile(r'_root\.addSound\("Effects","(?P<cue>\w+)"\);')


def read_cues(folder) -> dict[str, list[str]]:
    """Read every `_root.addSound("Effects", cue)` call of the frame scripts in
    `folder`, which holds one frame_<n> folder per frame with a script.

    The result maps the 1-based frame, as a string because it is a JSON key, to
    the cues of its scripts, in frame order. A line that calls addSound in
    another shape raises ValueError naming its frame, and so does a folder with
    no cue.
    """
    cues: dict[str, list[str]] = {}
    frames = sorted(
        (path for path in folder.glob("frame_*") if path.is_dir()),
        key=lambda path: int(path.name.removeprefix("frame_")),
    )
    for frame_folder in frames:
        frame = frame_folder.name.removeprefix("frame_")
        for script in sorted(frame_folder.glob("DoAction*.as")):
            for line in script.read_text(encoding="utf-8").splitlines():
                if "addSound" not in line:
                    continue
                match = ADD_SOUND.fullmatch(line.strip())
                if match is None:
                    raise ValueError(
                        f"frame {frame}: cannot read {line.strip()[:80]!r}"
                    )
                cues.setdefault(frame, []).append(match.group("cue"))
    if not cues:
        raise ValueError("no sound cues found")
    return cues


def source(model: str):
    return ACTION_SCRIPT / f"DefineSprite_{MODELS[model]}_{model}"


def output(model: str):
    return CONVERTED_JSON / f"{model.lower()}_sound_cues.json"


def dumps(cues: dict[str, list[str]]) -> str:
    return json.dumps(cues, indent=2) + "\n"


def main() -> None:
    for model in MODELS:
        cues = read_cues(source(model))
        output(model).write_text(dumps(cues), encoding="utf-8", newline="\n")
        print(f"Wrote the sound cues of {len(cues)} {model} frames to {output(model)}")


if __name__ == "__main__":
    main()
