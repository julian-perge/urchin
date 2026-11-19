# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png        - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png       - one sky per label of 3454
#   assets/ui/battle/<NAME>.png                  - the four chrome characters
#   assets/ui/battle/stance/<NAME>.png           - 5 stance icons + 2 covers
#   assets/ui/battle/member_bar_panel.png        - the member bar's dark backing
#   assets/ui/battle/clock_disc.png              - the clock's dark ring
#   assets/ui/battle/clock/<SIDE>_<TIME>.png     - the clock's lit ring
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
import re
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import ACTION_SCRIPT, FFDEC, REPO_ROOT, WEB_SWF, png
from urchin_dev.run import run
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.swf_index import (
    SwfIndex,
    button_records,
    character_kind,
    first_fill_color,
    read_swf,
    shape_bounds,
)

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

# The Radial menu, which the battle frame places as "selector". thing0 to thing7
# are its move icons and thingo0 to thingo7 the buttons over them, which
# RadialMenu builds its orbs from. Its enterFrame tests the mouse with hitTest
# and no shape flag, which tests the bounding box of everything the clip draws
# (frame_217/PlaceObject3_3382_500 enterFrame, line 48).
SELECTOR = 3382
SELECTOR_NAME = "selector"
ORB_BUTTON_NAME = "thingo"
ORB_COUNT = 8


# The clock, battleClocker, which the battle frame places at depth 480. It is
# the dark ring 3388 under thingerClock (3387), whose frames friend and enemy
# differ only in the two Glow filters on its one child, sprite 3386. 3386 holds
# two copies of the hand 3385, a white half ring, each under its own half-stage
# mask: the hand at depth 2 shows through the right half and the hand at depth 6
# through the left. Each hand's enterFrame script sets its _rotation from
# BattleTimeNow and clamps it, so the ring is grey at 0, lights clockwise from
# the top and is whole at BattleTimeLimit. A Traced run in Flash Player 14 read
# the same rotations and pixels at 0, 30, 60, 90 and 120.
#
# ffdec runs no script and draws both hands where the tags place them, which
# hides both under their masks. So each lit ring is rendered with the hands set
# to the rotations the scripts give for one BattleTimeNow. The glow wraps the
# cut ends of each hand, so one render cannot be turned in Godot to show
# another time.
CLOCK = 3389
CLOCK_DISC_DEPTH = 2
CLOCK_RING = 3387
CLOCK_HANDS = 3386
CLOCK_DIR = BATTLE_UI_DIR / "clock"
HAND_SCRIPTS = ACTION_SCRIPT / f"DefineSprite_{CLOCK_HANDS}" / "frame_1"
TIME_LIMIT_SCRIPT = ACTION_SCRIPT / "frame_217" / "DoAction.as"
# Both hands compute -180 + 180 * (BattleTimeNow / (BattleTimeLimit / 2)), each
# written its own way, and then set 0 in place of the angles on one side of 0.
HAND_ANGLE = re.compile(
    r"this\._rotation = (?:-180 \+ 180 \* \(_root\.BattleTimeNow / \(_root\.BattleTimeLimit / 2\)\)"
    r"|180 \* \(_root\.BattleTimeNow / \(_root\.BattleTimeLimit / 2\)\) - 180);"
    r"\s*if\((?:this\.)?_rotation (>=|<) 0\)\s*\{\s*_rotation = 0;\s*\}"
)
HAND_SCRIPT_DIR = re.compile(r"PlaceObject2_3385_(\d+)")
TIME_LIMIT = re.compile(r"^BattleTimeLimit = (\d+);", re.MULTILINE)
# On Heroic a pick (addMoveForPlayer) and a pass (button 3383's release) both
# set BattleTimeNow this many frames short of BattleTimeLimit, so the half-turn
# starts that many frames after the player's last pick or pass.
PICK_SCRIPTS = (
    ACTION_SCRIPT / "frame_42" / "DoAction_11.as",
    ACTION_SCRIPT / "DefineButton2_3383" / "BUTTONCONDACTION on(release).as",
)
PICK_DELAY = re.compile(r"_root\.BattleTimeNow = _root\.BattleTimeLimit - (\d+);")

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
        png.save(trimmed.image, out_dir / name)
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
        png.save(trimmed.image, BATTLE_UI_DIR / f"{name}.png")
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
        png.save(cropped, BATTLE_UI_DIR / "member_bar_panel.png")
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


def compose(outer, inner) -> tuple[float, float, float, float, float, float]:
    """-> the matrix that places a point as `inner` and then `outer` would.
    Both matrices may only scale and translate."""
    for matrix in (outer, inner):
        if matrix[1] or matrix[2]:
            raise RuntimeError(f"matrix {matrix} rotates or skews")
    return (
        outer[0] * inner[0],
        0.0,
        0.0,
        outer[3] * inner[3],
        outer[4] + outer[0] * inner[4],
        outer[5] + outer[3] * inner[5],
    )


def union(rects) -> tuple[float, float, float, float]:
    """-> the smallest (xmin, ymin, xmax, ymax) that holds every rect given."""
    rects = list(rects)
    if not rects:
        raise RuntimeError("no rects to join")
    return (
        min(r[0] for r in rects),
        min(r[1] for r in rects),
        max(r[2] for r in rects),
        max(r[3] for r in rects),
    )


def drawn_bounds(
    index: SwfIndex, cid: int, matrix
) -> tuple[float, float, float, float]:
    """-> the bounds of what `cid` draws before any script runs, placed by
    `matrix`, as (xmin, ymin, xmax, ymax) in twips: a shape's ShapeBounds, a
    sprite's frame 1 and a button's up state. A clip mask counts with its own
    bounds. On the selector this choice changes nothing: each icon's frame 1
    holds only its mask and the disc under it, which have the same bounds.

    It reads the tags rather than a render's rect, because hitTest leaves out
    the filters that a render's canvas grows by."""
    kind = character_kind(index, cid)
    if kind == "shape":
        return placed_rect(matrix, timeline.IDENTITY, shape_bounds(index, cid))
    if kind == "sprite":
        layers = timeline.frames(index, cid)[0].values()
        return union(
            drawn_bounds(index, layer.character_id, compose(matrix, layer.matrix))
            for layer in layers
        )
    if kind == "button":
        return union(
            drawn_bounds(index, record.character_id, compose(matrix, record.matrix))
            for record in button_records(index, cid)
            if "up" in record.states
        )
    raise RuntimeError(f"character {cid} is a {kind}, which drawn_bounds can't measure")


def px_rect(rect) -> dict[str, float]:
    """-> an (xmin, ymin, xmax, ymax) rect in twips as rect_entry() records it,
    in px."""
    twips = render.TWIPS
    return rect_entry(
        (
            rect[0] / twips,
            rect[1] / twips,
            (rect[2] - rect[0]) / twips,
            (rect[3] - rect[1]) / twips,
        )
    )


def ring_layout(selector_matrix, orb_rects, child_bounds) -> dict:
    """-> what RadialMenu needs from the Radial menu clip: the scale the battle
    frame places it at, the rect of each orb's button in the clip's own px, and
    the box of everything the clip draws in its own px. orb_rects and
    child_bounds are (xmin, ymin, xmax, ymax) rects in twips, orb_rects in orb
    order."""
    scale_x, skew0, skew1, scale_y = selector_matrix[:4]
    if skew0 or skew1 or scale_x != scale_y:
        raise RuntimeError(f"the Radial menu clip is placed with {selector_matrix}")
    return {
        "box": px_rect(union(child_bounds)),
        "orb_rects": [px_rect(rect) for rect in orb_rects],
        "scale": round(scale_x, 4),
    }


def radial_menu_layout(index: SwfIndex, battle_frame: int) -> dict:
    """-> ring_layout() for the Radial menu clip the battle frame places."""
    placed = [
        layer
        for layer in timeline.frames(index, 0)[battle_frame - 1].values()
        if layer.character_id == SELECTOR
    ]
    if len(placed) != 1 or placed[0].name != SELECTOR_NAME:
        raise RuntimeError(
            f"the battle frame places {SELECTOR} as {[p.name for p in placed]},"
            f" want one {SELECTOR_NAME!r}"
        )
    frames = timeline.frames(index, SELECTOR)
    if len(frames) != 1:
        raise RuntimeError(f"{SELECTOR} has {len(frames)} frames, want 1")
    layers = frames[0].values()
    by_name = {layer.name: layer for layer in layers}
    buttons = [by_name.get(f"{ORB_BUTTON_NAME}{i}") for i in range(ORB_COUNT)]
    if None in buttons:
        raise RuntimeError(
            f"{SELECTOR} names {sorted(by_name)}, want {ORB_BUTTON_NAME}0 to 7"
        )
    return ring_layout(
        placed[0].matrix,
        [drawn_bounds(index, b.character_id, b.matrix) for b in buttons],
        [drawn_bounds(index, layer.character_id, layer.matrix) for layer in layers],
    )


def hand_clamp(script: str) -> str:
    """-> the comparison, ">=" or "<", whose angles one hand's enterFrame script
    sets to 0. Raises unless the script computes the angle both hands share."""
    found = HAND_ANGLE.search(script)
    if found is None:
        raise RuntimeError(
            f"a clock hand's script is not the angle this ports:\n{script}"
        )
    return found.group(1)


def hand_rotation(clamp: str, time_now: float, limit: float) -> float:
    """-> the _rotation that a hand whose script clamps with clamp sets when
    BattleTimeNow is time_now and BattleTimeLimit is limit."""
    angle = -180 + 180 * (time_now / (limit / 2))
    if (clamp == ">=" and angle >= 0) or (clamp == "<" and angle < 0):
        return 0.0
    return angle


def hand_clamps() -> dict[int, str]:
    """-> {depth in sprite 3386: clamp} for both hands, read from their scripts."""
    clamps = {}
    for path in sorted(
        HAND_SCRIPTS.glob("*/CLIPACTIONRECORD onClipEvent(enterFrame).as")
    ):
        depth = HAND_SCRIPT_DIR.fullmatch(path.parent.name)
        if depth is None:
            raise RuntimeError(f"{path.parent.name} is not a clock hand")
        clamps[int(depth.group(1))] = hand_clamp(path.read_text("utf-8"))
    if sorted(clamps.values()) != ["<", ">="]:
        raise RuntimeError(f"the clock hands clamp {clamps}, want one each way")
    return clamps


def time_limit(script: str) -> int:
    """-> BattleTimeLimit, which the battle frame's first script sets."""
    found = TIME_LIMIT.findall(script)
    if len(found) != 1:
        raise RuntimeError(f"the battle frame sets BattleTimeLimit {len(found)} times")
    return int(found[0])


def pick_delay(scripts: list[str]) -> int:
    """-> the frames between the player's last pick or pass and the half-turn's
    start. Raises unless each script sets it once and all of them agree."""
    found = [PICK_DELAY.findall(script) for script in scripts]
    if any(len(each) != 1 for each in found) or len({each[0] for each in found}) != 1:
        raise RuntimeError(f"the pick and the pass set BattleTimeNow as {found}")
    return int(found[0][0])


def clock_jobs(
    index: SwfIndex, battle_frame: int, stripped: tuple[int, ...]
) -> tuple[render.Job, dict[str, list[render.Job]], int]:
    """-> the clock's dark ring job, the lit ring's jobs by frame label, one for
    each BattleTimeNow from 0 to BattleTimeLimit, and that limit."""
    clock_origin = render.placement_origin(index, 0, battle_frame, CLOCK)
    inner = render.placement_origin(index, CLOCK, 1, CLOCK_RING)
    ring_origin = (clock_origin[0] + inner[0], clock_origin[1] + inner[1])
    disc = render.Job(
        CLOCK,
        1,
        ZOOM,
        origin=clock_origin,
        strip=stripped,
        only_depths=(CLOCK_DISC_DEPTH,),
    )
    clamps = hand_clamps()
    limit = time_limit(TIME_LIMIT_SCRIPT.read_text("utf-8"))
    rings = {
        label: [
            render.Job(
                CLOCK_RING,
                frame,
                ZOOM,
                origin=ring_origin,
                strip=stripped,
                rotate=tuple(
                    (CLOCK_HANDS, depth, hand_rotation(clamp, time_now, limit))
                    for depth, clamp in sorted(clamps.items())
                ),
            )
            for time_now in range(limit + 1)
        ]
        for label, frame in sorted(sprite_label_frames(index, CLOCK_RING).items())
    }
    return disc, rings, limit


def write_clock(
    disc: render.Frame, rings: dict[str, list[render.Frame]], limit: int
) -> tuple[dict, dict]:
    """Write the dark ring and every lit ring, and return the dark ring's rect and
    the lit rings' record. The lit rings share one crop, so one TextureRect at one
    rect shows any of them."""
    trimmed = render.trim(disc)
    if trimmed is None:
        raise RuntimeError(f"the clock's dark ring {CLOCK} rendered empty")
    png.save(trimmed.image, BATTLE_UI_DIR / "clock_disc.png")
    print(f"  {CLOCK} depth {CLOCK_DISC_DEPTH} -> clock_disc.png", file=sys.stderr)
    labels = sorted(rings)
    cut = render.trim_union([frame for label in labels for frame in rings[label]])
    if cut is None:
        raise RuntimeError(
            f"the clock's ring {CLOCK_RING} rendered empty at every time"
        )
    CLOCK_DIR.mkdir(parents=True, exist_ok=True)
    count = limit + 1
    for n, label in enumerate(labels):
        for time_now, piece in enumerate(cut[n * count : (n + 1) * count]):
            png.save(piece.image, CLOCK_DIR / f"{label}_{time_now:03d}.png")
    print(f"  {CLOCK_RING} {labels} x {count} -> clock/", file=sys.stderr)
    record = {
        "labels": labels,
        "limit": limit,
        "rect": rect_entry(cut[0].rect),
        "size": list(cut[0].image.size),
        "zoom": ZOOM,
    }
    return rect_entry(trimmed.rect), record


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
    disc_job, ring_jobs, limit = clock_jobs(index, battle_frame, stripped)
    clock_start = len(jobs)
    jobs += [
        disc_job,
        *(job for label in sorted(ring_jobs) for job in ring_jobs[label]),
    ]
    # Every PNG and every rect below comes out of this one render, so no rect
    # can be measured off a different copy of the SWF than the PNG it
    # describes, which is how 5 of 10 hall rects went wrong in ecf28fd.
    with render.frames(WEB_SWF, jobs) as rendered:
        clock = rendered[clock_start:]
        rendered = rendered[:clock_start]
        by_sprite: dict[int, dict[int, render.Frame]] = {}
        for frame in rendered:
            by_sprite.setdefault(frame.job.timeline, {})[frame.job.frame] = frame

        print(f"halls ({len(halls)}):", file=sys.stderr)
        layout = {"halls": write_labels(by_sprite[HALL_SPRITE], halls, HALL_DIR, "")}
        print(f"skies ({len(skies)}):", file=sys.stderr)
        layout["skies"] = write_labels(by_sprite[SKY_SPRITE], skies, SKY_DIR, "SKY_")
        print(f"chrome ({len(CHROME)}):", file=sys.stderr)
        layout["chrome"] = write_chrome({cid: by_sprite[cid][1] for cid in CHROME})
        print("clock:", file=sys.stderr)
        count = limit + 1
        layout["chrome"]["clock_disc"], layout["clock"] = write_clock(
            clock[0],
            {
                label: clock[1 + n * count : 1 + (n + 1) * count]
                for n, label in enumerate(sorted(ring_jobs))
            },
            limit,
        )

        print("stance button art:", file=sys.stderr)
        write_labels(by_sprite[STANCE_ICONS], icons, STANCE_DIR, "")
        write_labels(by_sprite[STANCE_COVER], covers, STANCE_DIR, "cover_")
        render_member_bar_panel()
        layout["stance_row"] = stance_row_layout(
            index, by_sprite[MEMBER_BAR][1], by_sprite[STANCE_ICONS][1]
        )

    layout["clock"]["pick_delay"] = pick_delay(
        [path.read_text("utf-8") for path in PICK_SCRIPTS]
    )
    layout["fade"] = fade_layout(index, battle_frame)
    layout["radial_menu"] = radial_menu_layout(index, battle_frame)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
