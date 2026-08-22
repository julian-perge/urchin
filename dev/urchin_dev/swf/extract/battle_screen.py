# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png  - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png - one sky per label of 3454
#
# THE HALL AND THE SKY ARE INDEPENDENT. The original drives DefineSprite 3435
# from Krin.ZoneBG and DefineSprite 3454 from Krin.SkyBG, two separate
# per-battle fields, and 16 of its 99 battles set them to different labels -
# zone 6 fights in the CHURCH hall under the ROME sky. The two label sets are
# not the same, which is why each sprite is rendered against its own labels
# rather than one shared list.
#
# WHY 2676 IS STRIPPED. Every hall label places DefineSprite 2676 six times, at
# depths 40 through 240. It is the character rig: three slots per side, the
# right side mirrored. Rendered as-is, each hall bakes in six placeholder
# fighters holding swords under "!" speech bubbles, authoring scaffolding the
# game never draws. Deleting it from a working copy leaves ffdec drawing the
# scene art alone, the same approach zone_hub.py uses for the orb.
#
# Run: uv run extract_battle_screen
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

HALL_DIR = REPO_ROOT / "assets" / "backgrounds" / "battle"
SKY_DIR = REPO_ROOT / "assets" / "backgrounds" / "sky"

HALL_SPRITE = 3435
SKY_SPRITE = 3454
# The character rig each hall label places six times, deleted so the halls
# render as bare scene art.
FIGHTER_RIG = 2676
# These fill the window behind everything else, so they are rendered well above
# the window's 2x default scale.
ZOOM = 4.0


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def sprite_label_frames(xml: str, sprite: int) -> dict[str, int]:
    """-> {frame label: frame number} for one sprite's own timeline."""
    _snaps, labels = snapshot_timeline(xml, sprite, set())
    if not labels:
        raise RuntimeError(f"sprite {sprite} has no frame labels")
    return labels


def render_labels(
    swf: Path, sprite: int, frames: dict[str, int], out_dir: Path, prefix: str
) -> None:
    """Render one sprite at each of its labelled frames, trim each to its own
    opaque content, and write <prefix><LABEL>.png into out_dir."""
    work = Path(tempfile.mkdtemp(prefix="battle_screen_"))
    try:
        wanted = sorted(set(frames.values()))
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(sprite),
                "-select",
                ",".join(f"{sprite}:{f}" for f in wanted),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        rendered = work / f"DefineSprite_{sprite}"
        out_dir.mkdir(parents=True, exist_ok=True)
        for label, frame in sorted(frames.items()):
            image = Image.open(rendered / f"{frame}.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(
                    f"sprite {sprite} label {label} (frame {frame}) rendered empty"
                )
            cropped = image.crop(bbox)
            name = f"{prefix}{label.replace(' ', '_')}.png"
            cropped.save(out_dir / name)
            print(
                f"  {label:<16} frame {frame:>3} -> {name} {cropped.size}",
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    xml = WEB_SWF_XML.read_text()
    halls = sprite_label_frames(xml, HALL_SPRITE)
    skies = sprite_label_frames(xml, SKY_SPRITE)

    work = Path(tempfile.mkdtemp(prefix="battle_screen_swf_"))
    try:
        stripped = work / "battle.swf"
        run(
            [
                str(FFDEC),
                "-removeCharacter",
                str(WEB_SWF),
                str(stripped),
                str(FIGHTER_RIG),
            ]
        )
        print(f"halls ({len(halls)}):", file=sys.stderr)
        render_labels(stripped, HALL_SPRITE, halls, HALL_DIR, "")
        print(f"skies ({len(skies)}):", file=sys.stderr)
        render_labels(stripped, SKY_SPRITE, skies, SKY_DIR, "SKY_")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
