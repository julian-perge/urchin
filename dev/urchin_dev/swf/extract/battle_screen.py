# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png        - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png       - one sky per label of 3454
#   assets/ui/battle/<NAME>.png                  - the four chrome characters
#   assets/ui/battle/stance/<NAME>.png           - 5 stance icons + 2 covers
#   assets/ui/battle/member_bar_panel.png        - the member bar's dark backing
#   assets/backgrounds/battle/battle_layout.json - where those sit on the stage,
#                                                  and blacker5's fade timing
#
# THE HALL AND THE SKY ARE INDEPENDENT. The original drives DefineSprite 3435
# from Krin.ZoneBG and DefineSprite 3454 from Krin.SkyBG, two separate
# per-battle fields, and 16 of its 99 battles set them to different labels -
# zone 6 fights in the CHURCH hall under the ROME sky. The two label sets are
# not the same, which is why each sprite is rendered against its own labels
# rather than one shared list.
#
# WHY 2676 AND 3312 ARE STRIPPED. Every hall label places DefineSprite 2676 six
# times, at depths 40 through 240. It is the character rig: three slots per
# side, the right side mirrored. Rendered as-is, each hall bakes in six
# placeholder fighters holding swords under "!" speech bubbles, authoring
# scaffolding the game never draws. DefineSprite 3312 is the bottom bar's
# member bar container; see the MEMBER_BARS constant below for why it is
# stripped too. Deleting both before the render leaves ffdec drawing the
# scene art alone, the same approach zone_hub.py uses for the orb.
#
# Run: uv run extract_battle_screen
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF
from urchin_dev.run import run
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.swf_index import SwfIndex, first_fill_color, read_swf, shape_bounds

HALL_DIR = REPO_ROOT / "assets" / "backgrounds" / "battle"
SKY_DIR = REPO_ROOT / "assets" / "backgrounds" / "sky"
BATTLE_UI_DIR = REPO_ROOT / "assets" / "ui" / "battle"

HALL_SPRITE = 3435
SKY_SPRITE = 3454
# The character rig each hall label places six times, deleted so the halls
# render as bare scene art.
FIGHTER_RIG = 2676
# The team member bar container, which 3317 places at depth 7. It holds two
# copies of one member bar, each carrying the SWF author's placeholder name
# "Thurman McPown" in a DefineEditText the game fills at runtime from
# playerKrin<n>.playerName. Rendered as-is the bar bakes in two dead rows. The
# port rebuilds them from scenes/battle/stance_row.tscn instead.
MEMBER_BARS = 3312
# What every battle render here and in verify_battle_screen.py goes without.
BATTLE_STRIP: dict[int, str] = {
    FIGHTER_RIG: "the placeholder fighter rig each hall label places six times",
    MEMBER_BARS: "the member bars, with the author's placeholder name in them",
}
# These fill the window behind everything else, so they are rendered well above
# the window's 2x default scale.
ZOOM = 4.0

# The four chrome characters the battle frame places, named for what they are.
# 3317 sits at depth 1 on the Navigation frame too, so the bottom bar is one
# shared asset rather than the two copies the repo keeps.
CHROME: dict[int, str] = {
    3317: "bottom_bar",
    3465: "top_panel",
    3460: "alert_icon",
    3455: "stage_rect",
}

STANCE_DIR = BATTLE_UI_DIR / "stance"

# The pieces one team member bar is built from. The port draws the bar itself
# out of these rather than extracting it whole, because a faithful texture
# would need one render per stance per selection state and still could not
# carry the player-supplied name. See
# spec/old/2026-08-23-battle-bottom-bar-and-stance-rows.md.
#
# 3305 labels its five frames Phalanx, Defensive, Tactical, Aggressive and
# Relentless, which is _root.agModeNames verbatim and also the order of
# Party.AggressionStance in the port. 3293 labels its two BLACK, for a button
# the player has not picked, and WHITE for the one they have; setAG sets all
# five to BLACK and then one to WHITE.
MEMBER_BAR = 3311
STANCE_BUTTON = 3306
STANCE_ICONS = 3305
STANCE_COVER = 3293
MEMBER_BAR_PANEL = 3309

# The DefineEditText the bar shows the companion's name in. Its initialText is
# the author's placeholder, so only its position is wanted here.
NAME_FIELD = 3308

# blacker5, the clip the battle frame places on its top depth. Every battle
# opens on its frame 1, which fades the battle in from black, and its frame 31
# runs stop() (DefineSprite_3355/frame_31/DoAction.as). Once winCondition is set,
# the conductor's blacker5.play() resumes it from there
# (frame_217/PlaceObject2_3389_480 enterFrame, lines 257-261), and it fades back
# to black before its frame 85 sends the result
# (DefineSprite_3355/frame_85/DoAction.as:5-16).
FADE_CLIP = 3355
FADE_STOP_FRAME = 31
FADE_RESULT_FRAME = 85
# A colour transform that leaves a shape as it is: four multiply terms of 1.0,
# which the SWF stores as 256, and four add terms of 0.
IDENTITY_COLOR_TRANSFORM = (256, 256, 256, 256, 0, 0, 0, 0)

LAYOUT_JSON = HALL_DIR / "battle_layout.json"
FRAME_LABEL = "KRINBATTLESCENE"


def sprite_label_frames(index: SwfIndex, sprite: int) -> dict[str, int]:
    """-> {frame label: frame number} for one sprite's own timeline."""
    labels = timeline.labels(index, sprite)
    if not labels:
        raise RuntimeError(f"sprite {sprite} has no frame labels")
    return labels


def first_frame_offsets(
    index: SwfIndex, sprite: int, character: int
) -> list[tuple[float, float]]:
    """-> where one sprite's first frame places `character`, one (x, y) in
    design px per placement, sorted."""
    return sorted(
        (layer.matrix[4] / 20.0, layer.matrix[5] / 20.0)
        for layer in timeline.frames(index, sprite)[0].values()
        if layer.character_id == character
    )


def write_labels(
    rendered: dict[int, render.Frame],
    frames: dict[str, int],
    out_dir: Path,
    prefix: str,
) -> dict[str, dict[str, float]]:
    """Trim each labelled frame to its own opaque content, write
    <prefix><LABEL>.png into out_dir and return {LABEL: rect} on the stage."""
    out_dir.mkdir(parents=True, exist_ok=True)
    rects = {}
    for label, frame in sorted(frames.items()):
        trimmed = render.trim(rendered[frame])
        if trimmed is None:
            raise RuntimeError(
                f"sprite {rendered[frame].job.timeline} label {label}"
                f" (frame {frame}) rendered empty"
            )
        name = f"{prefix}{label.replace(' ', '_')}.png"
        trimmed.image.save(out_dir / name)
        print(
            f"  {label:<16} frame {frame:>3} -> {name} {trimmed.image.size}",
            file=sys.stderr,
        )
        rects[label.replace(" ", "_")] = rect_entry(trimmed.rect)
    return rects


def write_chrome(rendered: dict[int, render.Frame]) -> dict[str, dict[str, float]]:
    """Trim each chrome character's first frame to its content, write it and
    return {name: rect} on the stage. The chrome carries no frame labels and
    holds a single frame each."""
    BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
    rects = {}
    for cid, name in sorted(CHROME.items()):
        trimmed = render.trim(rendered[cid])
        if trimmed is None:
            raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
        trimmed.image.save(BATTLE_UI_DIR / f"{name}.png")
        print(f"  {cid} -> {name}.png {trimmed.image.size}", file=sys.stderr)
        rects[name] = rect_entry(trimmed.rect)
    return rects


def render_member_bar_panel() -> None:
    """Draw the dark rounded backing one member bar sits on, trimmed to its
    content. It is a DefineShape rather than a sprite, so this exports a shape
    through the CLI the way zone_hub.py exports the orb's arcs."""
    work = Path(tempfile.mkdtemp(prefix="battle_member_panel_"))
    try:
        run(
            [
                FFDEC,
                "-zoom",
                str(ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                str(MEMBER_BAR_PANEL),
                "-export",
                "shape",
                work,
                WEB_SWF,
            ]
        )
        image = Image.open(work / f"{MEMBER_BAR_PANEL}.png").convert("RGBA")
        bbox = image.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"member bar panel {MEMBER_BAR_PANEL} rendered empty")
        cropped = image.crop(bbox)
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        cropped.save(BATTLE_UI_DIR / "member_bar_panel.png")
        print(
            f"  {MEMBER_BAR_PANEL} -> member_bar_panel.png {cropped.size}",
            file=sys.stderr,
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def rect_entry(rect) -> dict[str, float]:
    """-> one (x, y, w, h) tuple as the JSON file records it."""
    return {
        "x": round(rect[0], 2),
        "y": round(rect[1], 2),
        "w": round(rect[2], 2),
        "h": round(rect[3], 2),
    }


def stance_row_layout(
    index: SwfIndex, bar_frame: render.Frame, icon_frame: render.Frame
) -> dict:
    """-> one member bar's internal layout in design px, measured off the SWF.

    Offsets are from the bar's own top-left corner, which is what StanceRow
    needs to place its children. The bar's position on the stage is not
    recorded, because the port puts its rows in BottomBar/StanceHost rather
    than where the original puts them.
    """
    bar_trim, icon_trim = render.trim(bar_frame), render.trim(icon_frame)
    if bar_trim is None or icon_trim is None:
        raise RuntimeError(f"{MEMBER_BAR} or {STANCE_ICONS} rendered empty")
    bar, icon = bar_trim.rect, icon_trim.rect

    buttons = first_frame_offsets(index, MEMBER_BAR, STANCE_BUTTON)
    if len(buttons) != 5:
        raise RuntimeError(f"{MEMBER_BAR} places {len(buttons)} stance buttons, want 5")
    names = first_frame_offsets(index, MEMBER_BAR, NAME_FIELD)
    if len(names) != 1:
        raise RuntimeError(f"{MEMBER_BAR} places {len(names)} name fields, want 1")
    pics = first_frame_offsets(index, STANCE_BUTTON, STANCE_ICONS)
    if len(pics) != 1:
        raise RuntimeError(f"{STANCE_BUTTON} places {len(pics)} icons, want 1")
    rows = sorted(y for _x, y in first_frame_offsets(index, MEMBER_BARS, MEMBER_BAR))
    if len(rows) != 2:
        raise RuntimeError(f"{MEMBER_BARS} places {len(rows)} member bars, want 2")

    return {
        "art_zoom": ZOOM,
        "bar_size": {"w": round(bar[2], 2), "h": round(bar[3], 2)},
        "button_pitch": round(buttons[1][0] - buttons[0][0], 2),
        "button_size": {"w": round(icon[2], 2), "h": round(icon[3], 2)},
        "first_button": {
            "x": round(buttons[0][0] + pics[0][0] + icon[0] - bar[0], 2),
            "y": round(buttons[0][1] + pics[0][1] + icon[1] - bar[1], 2),
        },
        "name_offset": {
            "x": round(names[0][0] - bar[0], 2),
            "y": round(names[0][1] - bar[1], 2),
        },
        "row_pitch": round(rows[1] - rows[0], 2),
    }


def placed_rect(outer, inner, bounds) -> tuple[float, float, float, float]:
    """-> bounds as `inner` places them inside a clip that `outer` places on
    the stage, as (xmin, ymin, xmax, ymax) in twips. Both matrices may only
    scale and translate."""
    for matrix in (outer, inner):
        if matrix[1] or matrix[2]:
            raise RuntimeError(f"matrix {matrix} rotates or skews")
    xs = [
        outer[4] + outer[0] * (inner[4] + inner[0] * x) for x in (bounds[0], bounds[2])
    ]
    ys = [
        outer[5] + outer[3] * (inner[5] + inner[3] * y) for y in (bounds[1], bounds[3])
    ]
    return min(xs), min(ys), max(xs), max(ys)


def fade_layout(index: SwfIndex, battle_frame: int) -> dict:
    """-> what the port needs to play blacker5: the SWF's frame rate, the clip's
    stop and result frames, the colour of its shape, and the alpha that shape
    shows on each of the clip's frames, 0.0 on a frame without it.

    The port draws that one colour over its whole window and changes only the
    alpha, so this refuses a clip that shows a second shape, a shape that is not
    one opaque colour, a frame that leaves part of the stage uncovered, or a
    colour transform that does more than scale the alpha.
    """
    scripted = sorted(
        block.frame
        for block in index.code
        if block.kind == "frame" and block.owner == FADE_CLIP
    )
    if scripted != [FADE_STOP_FRAME, FADE_RESULT_FRAME]:
        raise RuntimeError(
            f"{FADE_CLIP} runs code on frames {scripted},"
            f" want {FADE_STOP_FRAME} and {FADE_RESULT_FRAME}"
        )
    placed = [
        layer.matrix
        for layer in timeline.frames(index, 0)[battle_frame - 1].values()
        if layer.character_id == FADE_CLIP
    ]
    if len(placed) != 1:
        raise RuntimeError(
            f"the battle frame places {FADE_CLIP} {len(placed)} times, want 1"
        )
    stage = index.stage
    shapes = set()
    alphas = []
    for number, layers in enumerate(timeline.frames(index, FADE_CLIP), start=1):
        if not layers:
            alphas.append(0.0)
            continue
        if len(layers) != 1:
            raise RuntimeError(f"{FADE_CLIP} frame {number} shows {len(layers)} layers")
        (layer,) = layers.values()
        shapes.add(layer.character_id)
        rect = placed_rect(
            placed[0], layer.matrix, shape_bounds(index, layer.character_id)
        )
        if (
            rect[0] > stage[0]
            or rect[1] > stage[1]
            or rect[2] < stage[2]
            or rect[3] < stage[3]
        ):
            raise RuntimeError(
                f"{FADE_CLIP} frame {number} covers {rect} of the stage {stage}"
            )
        transform = layer.color_transform or IDENTITY_COLOR_TRANSFORM
        if transform[:3] != (256, 256, 256) or transform[4:] != (0, 0, 0, 0):
            raise RuntimeError(
                f"{FADE_CLIP} frame {number} transforms more than the alpha: {transform}"
            )
        alphas.append(max(0, min(transform[3], 256)) / 256)
    if len(shapes) != 1:
        raise RuntimeError(f"{FADE_CLIP} shows shapes {sorted(shapes)}, want one")
    color = first_fill_color(index, shapes.pop())
    if color is None or color[3] != 255:
        raise RuntimeError(
            f"{FADE_CLIP}'s shape fills with {color}, want one opaque colour"
        )
    return {
        "alphas": alphas,
        "color": "#{:02x}{:02x}{:02x}".format(*color[:3]),
        "fps": index.frame_rate,
        "result_frame": FADE_RESULT_FRAME,
        "stop_frame": FADE_STOP_FRAME,
    }


def main():
    index = read_swf(WEB_SWF)
    halls = sprite_label_frames(index, HALL_SPRITE)
    skies = sprite_label_frames(index, SKY_SPRITE)
    icons = sprite_label_frames(index, STANCE_ICONS)
    covers = sprite_label_frames(index, STANCE_COVER)
    battle_frame = timeline.frame_of(index, 0, FRAME_LABEL)
    stripped = tuple(strip.strip_list(WEB_SWF, BATTLE_STRIP))

    def placed(cid: int) -> tuple[float, float]:
        return render.placement_origin(index, 0, battle_frame, cid)

    # Each sprite's frames, and where the battle frame puts the sprite. The
    # stance icons and the member bar are nested in the bottom bar rather
    # than placed on the root, so their rects stay relative to their own
    # origin, and the stance row's icon size reads 3305's frame 1, which its
    # labels render anyway.
    wanted = {
        HALL_SPRITE: (set(halls.values()), placed(HALL_SPRITE)),
        SKY_SPRITE: (set(skies.values()), placed(SKY_SPRITE)),
        **{cid: ({1}, placed(cid)) for cid in CHROME},
        STANCE_ICONS: (set(icons.values()) | {1}, (0.0, 0.0)),
        STANCE_COVER: (set(covers.values()), (0.0, 0.0)),
        MEMBER_BAR: ({1}, (0.0, 0.0)),
    }
    jobs = [
        render.Job(cid, frame, ZOOM, origin=origin, strip=stripped)
        for cid, (frames, origin) in wanted.items()
        for frame in sorted(frames)
    ]
    # Every PNG and every rect below comes out of this one render, so no rect
    # can be measured off a different copy of the SWF than the PNG it
    # describes, which is how 5 of 10 hall rects went wrong in ecf28fd.
    with render.frames(WEB_SWF, jobs) as rendered:
        by_sprite: dict[int, dict[int, render.Frame]] = {}
        for frame in rendered:
            by_sprite.setdefault(frame.job.timeline, {})[frame.job.frame] = frame

        print(f"halls ({len(halls)}):", file=sys.stderr)
        layout = {"halls": write_labels(by_sprite[HALL_SPRITE], halls, HALL_DIR, "")}
        print(f"skies ({len(skies)}):", file=sys.stderr)
        layout["skies"] = write_labels(by_sprite[SKY_SPRITE], skies, SKY_DIR, "SKY_")
        print(f"chrome ({len(CHROME)}):", file=sys.stderr)
        layout["chrome"] = write_chrome({cid: by_sprite[cid][1] for cid in CHROME})

        print("stance button art:", file=sys.stderr)
        write_labels(by_sprite[STANCE_ICONS], icons, STANCE_DIR, "")
        write_labels(by_sprite[STANCE_COVER], covers, STANCE_DIR, "cover_")
        render_member_bar_panel()
        layout["stance_row"] = stance_row_layout(
            index, by_sprite[MEMBER_BAR][1], by_sprite[STANCE_ICONS][1]
        )

    layout["fade"] = fade_layout(index, battle_frame)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
