# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png        - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png       - one sky per label of 3454
#   assets/ui/battle/<NAME>.png                  - the four chrome characters
#   assets/backgrounds/battle/battle_layout.json - where those sit on the stage
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

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import root_placements, snapshot_timeline
from urchin_dev.swf.xml_lib import find_matrix, sprite_body

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
# docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md.
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

# Matches the whole tag or its closing partner, so a walk can tell a
# self-closing PlaceObject from one wrapping child elements.
_ITEM_TOKENS = re.compile(r"<item\b[^>]*?(/?)>|</item>")

LAYOUT_JSON = HALL_DIR / "battle_layout.json"
FRAME_LABEL = "KRINBATTLESCENE"

# The first matrix() in an exported SVG is the root group's, which carries the
# displayRect's negated minimums scaled by the export zoom.
_ROOT_MATRIX = re.compile(
    r'<g transform="matrix\('
    r"[-0-9.]+, [-0-9.]+, [-0-9.]+, [-0-9.]+, ([-0-9.]+), ([-0-9.]+)\)\""
)
_SVG_WIDTH = re.compile(r'\bwidth="([0-9.]+)px"')
_SVG_HEIGHT = re.compile(r'\bheight="([0-9.]+)px"')


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


def frame_one_placements(
    xml: str, sprite: int
) -> dict[int, tuple[int, str, float, float]]:
    """-> {depth: (characterId, instance name, x, y)} for one sprite's first
    frame, with the translate converted from twips to design px.

    This is the same walk zone_hub.py's orb_layers does. It is written out
    again rather than shared, because the two want different things back and a
    little repetition reads better here than a parameterised helper.
    """
    body = sprite_body(xml, sprite)
    out: dict[int, tuple[int, str, float, float]] = {}
    depth = 0
    start = None
    for token in _ITEM_TOKENS.finditer(body):
        text = token.group(0)
        if text == "</item>":
            depth -= 1
            if depth == 0 and start is not None:
                element = body[start : token.end()]
                cid = re.search(r'characterId="(\d+)"', element)
                place_depth = re.search(r'depth="(\d+)"', element)
                if cid is not None and place_depth is not None:
                    name = re.search(r'name="([^"]*)"', element)
                    matrix = find_matrix(element)
                    out[int(place_depth.group(1))] = (
                        int(cid.group(1)),
                        name.group(1) if name else "",
                        matrix[4] / 20.0,
                        matrix[5] / 20.0,
                    )
                start = None
            continue
        self_closing = bool(token.group(1))
        if depth == 0:
            if 'type="ShowFrameTag"' in text:
                break
            if "PlaceObject" in text and not self_closing:
                start = token.start()
        if not self_closing:
            depth += 1
    return out


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


def render_chrome(swf: Path) -> None:
    """Render each chrome character's first frame, trimmed to its content."""
    work = Path(tempfile.mkdtemp(prefix="battle_chrome_"))
    try:
        ids = ",".join(str(c) for c in CHROME)
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                ids,
                "-select",
                ",".join(f"{c}:1" for c in CHROME),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        for cid, name in sorted(CHROME.items()):
            image = Image.open(work / f"DefineSprite_{cid}" / "1.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
            cropped = image.crop(bbox)
            cropped.save(BATTLE_UI_DIR / f"{name}.png")
            print(f"  {cid} -> {name}.png {cropped.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def render_member_bar_panel(swf: Path) -> None:
    """Draw the dark rounded backing one member bar sits on, trimmed to its
    content. It is a DefineShape rather than a sprite, so this exports a shape
    the way zone_hub.py exports the orb's arcs."""
    work = Path(tempfile.mkdtemp(prefix="battle_member_panel_"))
    try:
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                str(MEMBER_BAR_PANEL),
                "-export",
                "shape",
                str(work),
                str(swf),
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


def read_display_rect(svg_path: Path):
    """-> (x, y, w, h) of the sprite's displayRect in design px, relative to
    the sprite's own origin."""
    head = svg_path.read_text()[:2000]
    matrix = _ROOT_MATRIX.search(head)
    width = _SVG_WIDTH.search(head)
    height = _SVG_HEIGHT.search(head)
    if matrix is None or width is None or height is None:
        raise RuntimeError(f"no displayRect in {svg_path}")
    return (
        -float(matrix.group(1)) / ZOOM,
        -float(matrix.group(2)) / ZOOM,
        float(width.group(1)) / ZOOM,
        float(height.group(1)) / ZOOM,
    )


def content_rect(origin, display_rect, canvas, bbox):
    """The trimmed render's rect on the stage in design px, given where the
    main timeline places the sprite, its displayRect, the canvas ffdec
    produced and the canvas-pixel bbox of what it drew there.

    ffdec grows a canvas by the filter dimension on both sides of the
    displayRect, so the growth is symmetric and the canvas keeps the
    displayRect's centre. That centre plus the canvas size locates every
    rendered pixel without any filter math here.
    """
    centre_x = origin[0] + display_rect[0] + display_rect[2] / 2
    centre_y = origin[1] + display_rect[1] + display_rect[3] / 2
    canvas_x = centre_x - canvas[0] / ZOOM / 2
    canvas_y = centre_y - canvas[1] / ZOOM / 2
    return (
        canvas_x + bbox[0] / ZOOM,
        canvas_y + bbox[1] / ZOOM,
        (bbox[2] - bbox[0]) / ZOOM,
        (bbox[3] - bbox[1]) / ZOOM,
    )


def local_content_rect(swf: Path, sprite: int) -> tuple[float, float, float, float]:
    """-> (x, y, w, h) of a sprite's first frame in design px, relative to
    the sprite's own origin.

    Same recovery as content_rect with the placement origin left at zero,
    because these sprites are nested inside another sprite rather than placed
    on the main timeline, so there is no root placement to read.
    """
    work = Path(tempfile.mkdtemp(prefix="battle_local_rect_"))
    try:
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    str(sprite),
                    "-select",
                    f"{sprite}:1",
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        image = Image.open(work / "png" / f"DefineSprite_{sprite}" / "1.png").convert(
            "RGBA"
        )
        bbox = image.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"sprite {sprite} rendered empty")
        display_rect = read_display_rect(
            work / "svg" / f"DefineSprite_{sprite}" / "1.svg"
        )
        return content_rect((0.0, 0.0), display_rect, image.size, bbox)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def placement_origin(xml: str, character: int) -> tuple[float, float]:
    """-> where the battle frame places one character, in design px."""
    _frame, placements = root_placements(xml, FRAME_LABEL)
    placed = [e for e in placements.values() if e.get("cid") == character]
    if len(placed) != 1:
        raise RuntimeError(
            f"character {character} placed {len(placed)} times on {FRAME_LABEL}"
        )
    matrix = placed[0]["mat"]
    return (matrix[4] / 20.0, matrix[5] / 20.0)


def rect_entry(rect) -> dict[str, float]:
    """-> one (x, y, w, h) tuple as the JSON file records it."""
    return {
        "x": round(rect[0], 2),
        "y": round(rect[1], 2),
        "w": round(rect[2], 2),
        "h": round(rect[3], 2),
    }


def layout_rects(swf: Path, xml: str, sprite: int, frames: dict[str, int]) -> dict:
    """-> {label: {x, y, w, h}} on the 800x575 stage, in design px."""
    origin = placement_origin(xml, sprite)

    work = Path(tempfile.mkdtemp(prefix="battle_layout_"))
    try:
        wanted = sorted(set(frames.values()))
        select = ",".join(f"{sprite}:{f}" for f in wanted)
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    str(sprite),
                    "-select",
                    select,
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        out = {}
        for label, frame in sorted(frames.items()):
            image = Image.open(
                work / "png" / f"DefineSprite_{sprite}" / f"{frame}.png"
            ).convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"sprite {sprite} label {label} rendered empty")
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{sprite}" / f"{frame}.svg"
            )
            rect = content_rect(origin, display_rect, image.size, bbox)
            out[label.replace(" ", "_")] = rect_entry(rect)
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)


def chrome_rects(swf: Path, xml: str) -> dict:
    """-> {name: {x, y, w, h}} on the 800x575 stage, in design px.

    The chrome characters carry no frame labels and hold a single frame each,
    so this renders them at frame 1 instead of walking a label list the way
    layout_rects does.
    """
    origins = {cid: placement_origin(xml, cid) for cid in CHROME}
    work = Path(tempfile.mkdtemp(prefix="battle_chrome_layout_"))
    try:
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    ",".join(str(c) for c in CHROME),
                    "-select",
                    ",".join(f"{c}:1" for c in CHROME),
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        out = {}
        for cid, name in sorted(CHROME.items()):
            image = Image.open(work / "png" / f"DefineSprite_{cid}" / "1.png").convert(
                "RGBA"
            )
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{cid}" / "1.svg"
            )
            out[name] = rect_entry(
                content_rect(origins[cid], display_rect, image.size, bbox)
            )
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)


def stance_row_layout(swf: Path, xml: str) -> dict:
    """-> one member bar's internal layout in design px, measured off the SWF.

    Offsets are from the bar's own top-left corner, which is what StanceRow
    needs to place its children. The bar's position on the stage is not
    recorded, because the port puts its rows in BottomBar/StanceHost rather
    than where the original puts them.
    """
    bar = local_content_rect(swf, MEMBER_BAR)
    icon = local_content_rect(swf, STANCE_ICONS)
    inside_bar = frame_one_placements(xml, MEMBER_BAR)
    inside_button = frame_one_placements(xml, STANCE_BUTTON)
    inside_container = frame_one_placements(xml, MEMBER_BARS)

    buttons = sorted(
        (x, y) for cid, _name, x, y in inside_bar.values() if cid == STANCE_BUTTON
    )
    if len(buttons) != 5:
        raise RuntimeError(f"{MEMBER_BAR} places {len(buttons)} stance buttons, want 5")
    names = [(x, y) for c, _n, x, y in inside_bar.values() if c == NAME_FIELD]
    if len(names) != 1:
        raise RuntimeError(f"{MEMBER_BAR} places {len(names)} name fields, want 1")
    pics = [(x, y) for c, _n, x, y in inside_button.values() if c == STANCE_ICONS]
    if len(pics) != 1:
        raise RuntimeError(f"{STANCE_BUTTON} places {len(pics)} icons, want 1")
    rows = sorted(y for c, _n, _x, y in inside_container.values() if c == MEMBER_BAR)
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
                str(MEMBER_BARS),
            ]
        )
        print(f"halls ({len(halls)}):", file=sys.stderr)
        render_labels(stripped, HALL_SPRITE, halls, HALL_DIR, "")
        print(f"skies ({len(skies)}):", file=sys.stderr)
        render_labels(stripped, SKY_SPRITE, skies, SKY_DIR, "SKY_")
        # The layout recovery has to run against this same stripped copy,
        # while it still exists: the fighter rig's placeholder figure pokes
        # above the hall's own opaque art on 5 of the 10 hall labels, so
        # measuring against the unstripped SWF would inflate their y and h
        # past what the PNGs above were actually cropped to.
        layout = {
            "halls": layout_rects(stripped, xml, HALL_SPRITE, halls),
            "skies": layout_rects(stripped, xml, SKY_SPRITE, skies),
        }
        # The chrome renders from this same stripped copy. 2676 sits nowhere in
        # the four chrome characters' trees so it changes nothing for them, and
        # 3312 has to be gone or the bottom bar bakes in the member bars.
        print(f"chrome ({len(CHROME)}):", file=sys.stderr)
        render_chrome(stripped)
        layout["chrome"] = chrome_rects(stripped, xml)

        print("stance button art:", file=sys.stderr)
        render_labels(
            stripped,
            STANCE_ICONS,
            sprite_label_frames(xml, STANCE_ICONS),
            STANCE_DIR,
            "",
        )
        render_labels(
            stripped,
            STANCE_COVER,
            sprite_label_frames(xml, STANCE_COVER),
            STANCE_DIR,
            "cover_",
        )
        render_member_bar_panel(stripped)
        layout["stance_row"] = stance_row_layout(stripped, xml)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
