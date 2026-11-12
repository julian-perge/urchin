# Art for the new-game class-select screen (main-timeline frame label
# "classMenu"): the three class cards in both of their states, plus the blue
# splatter background every menu screen sits on.
#
#   assets/ui/menu/class_cards/<class>_gray.png  - resting card
#   assets/ui/menu/class_cards/<class>.png       - hovered card, full color
#   assets/ui/menu/start_background.png          - the shared menu background
#   assets/ui/menu/logo.png                      - the SONNY 2 logo with its Glow
#   assets/ui/menu/logo.json                     - the logo's rect, size and zoom
#
# The class name under each card is NOT part of these textures. The original
# draws it as a separate DefineEditText above the card and fills it from
# KrinLang at runtime, so scenes/main_menu.tscn carries a Label per card
# instead, and the card art stays just the card.
#
# WHICH CARD IS WHICH CLASS. The main timeline names the three card instances
# bioDis, psychoDis and hydroDis, and two of those three names are wrong. The
# button beside each card is the authority, because it sets the class the
# player actually gets: DefineButton2_2735 sets Krin.Class = 0 (CLASS[0],
# "Biological") and plays bioDis; 2737 sets 1 ("Psychological") and plays
# hydroDis; 2736 sets 2 ("Hydraulic") and plays psychoDis. CARDS below follows
# the buttons, so it reads swapped against the instance names on purpose.
#
# WHICH FRAME IS WHICH STATE. Each card is a 26-frame sprite whose art sits in
# a nested sprite, and the gray-to-color transition is a COLORMATRIXFILTER on
# that nested placement, interpolating between a luminance matrix and identity.
# The sprite has stop() on frames 1, 7 and 26, and each button's rollOver plays
# the "START" label (frame 2) while rollOut plays "STOP" (frame 8):
#
#   frame 1     resting gray, where the sprite sits until the mouse arrives
#   frames 2-6  fading in
#   frame 7     full color, where gotoAndPlay("START") stops
#   frames 8-26 fading back out to gray again
#
# So the two states to export are frames 1 and 7, not the two label frames.
# Nothing in between needs exporting: a matrix lerp applied to fixed pixels is
# the same thing as crossfading its two endpoint images, so main_menu.gd's
# _fade_card() reproduces the animation from these two PNGs alone.
#
# WHERE EACH CARD GOES. A card sprite renders onto a canvas bigger than the
# card, because the art is placed through a bevel, a glow and a drop shadow,
# and ffdec grows the canvas by the filter's dimension on both sides of the
# timeline's displayRect. Symmetric growth means the canvas keeps the
# displayRect's centre, so the centre plus the canvas size locates every
# rendered pixel without any filter math here - the recovery render.py
# does. Each PNG is then trimmed to its own opaque content and the printed
# rect says where that trimmed image belongs on the 800x575 stage.
#
# These renders need java/Render.java. Each card's art sits behind a clip mask
# inside the sprite that carries the filters, and since jpexs afbe4fa33 ffdec
# puts such a mask in the wrong place, which the driver corrects. Without it the
# biological card comes out 159 design px wide instead of 194 with its art past
# its mask, and the other two shift. Nightly build 3544 showed the same symptom,
# at 136 wide. write_cards refuses cards of different sizes, because all three
# draw the same mask through the same filters.
#
# THE LOGO. The title (frame label "mainMenu") places sprite 321, which holds
# only shape 320, and the Glow is a filter on that root placement, not inside
# the sprite. So the logo is a render of the title frame with every depth but
# the logo's hidden, and a render of sprite 321 alone would come out without
# its Glow. The logo's rect on the stage comes from the same render.
#
# Run: uv run extract_start_screens
from __future__ import annotations

import json
import sys
from pathlib import Path

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.swf_index import read_swf

OUT_MENU = REPO_ROOT / "assets" / "ui" / "menu"
CARDS_DIR = OUT_MENU / "class_cards"

# The cards are sketch art the player looks straight at, so they are rendered
# well above the window's 2x default scale. The background is a slow gradient
# stretched across the whole window and gains nothing from the same treatment.
CARD_ZOOM = 5.0
BACKGROUND_ZOOM = 2.0
LOGO_ZOOM = 4.0

FRAME_LABEL = "classMenu"
BASE_CARD_FRAME = 1
HOVER_CARD_FRAME = 7

# Class to card sprite. Read the header before "fixing" these: the sprite ids
# disagree with the instance names the SWF gives them.
CARDS = {"psychological": 2746, "biological": 2766, "hydraulic": 2755}

# Depths 1, 2 and 5 hold the background: a gradient fill, the swirl decoration
# and the paint splatter. All six menu screens (mainMenu, subMenu, nameMenu,
# dataMenu, classMenu, optionsMenu) place exactly those three characters there,
# and everything above depth 5 is that screen's own foreground.
BACKGROUND_MAX_DEPTH = 5

TITLE_LABEL = "mainMenu"
LOGO = 321
LOGO_RECORD = OUT_MENU / "logo.json"


def logo_job(index) -> render.Job:
    """-> the render of the title frame with only the logo's depth kept.
    Raises unless the title places the logo exactly once."""
    frame_number = timeline.frame_of(index, 0, TITLE_LABEL)
    depths = [
        depth
        for depth, layer in timeline.frames(index, 0)[frame_number - 1].items()
        if layer.character_id == LOGO
    ]
    if len(depths) != 1:
        raise render.RenderError(
            f"{TITLE_LABEL} (frame {frame_number}) places the logo {LOGO}"
            f" {len(depths)} times"
        )
    return render.Job(0, frame_number, LOGO_ZOOM, only_depths=(depths[0],))


def logo_record(job: render.Job, cut: render.Trimmed) -> dict:
    return {
        "rect": [round(v, 4) for v in cut.rect],
        "size": list(cut.image.size),
        "zoom": job.zoom,
    }


def write_logo(job: render.Job, frame: render.Frame) -> None:
    cut = render.trim(frame)
    if cut is None:
        raise RuntimeError(f"the logo {LOGO} rendered fully transparent")
    cut.image.save(OUT_MENU / "logo.png")
    record = logo_record(job, cut)
    LOGO_RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    print(f"wrote logo.png {record['rect']} {cut.image.size}", file=sys.stderr)


def write_background(frame: render.Frame, stripped: int, out_path: Path) -> None:
    """Save the classMenu frame, drawn with every foreground character
    deleted, as the background the menu screens share."""
    image = frame.image()
    png.save(image, out_path)
    print(
        f"wrote {out_path} {image.size} ({stripped} foreground characters stripped)",
        file=sys.stderr,
    )


def write_cards(
    cards: dict[tuple[str, int], render.Frame],
) -> dict[str, tuple[float, float, float, float]]:
    """Write both states of all three cards, trimmed to the card itself, and
    return each one's rect on the stage."""
    CARDS_DIR.mkdir(parents=True, exist_ok=True)
    rests = {}
    for name in sorted(CARDS):
        # Both states draw the same card through the same filters, so the
        # resting state's bbox keeps the two PNGs the same size and the same
        # rect.
        rests[name] = render.trim(cards[(name, BASE_CARD_FRAME)])
        if rests[name] is None:
            raise RuntimeError(f"{name} (cid {CARDS[name]}) rendered empty")
    sizes = {name: rest.image.size for name, rest in rests.items()}
    if len(set(sizes.values())) != 1:
        raise RuntimeError(f"the three cards came out different sizes: {sizes}")
    rects = {}
    for name, base in rests.items():
        rects[name] = base.rect
        for frame, suffix in ((BASE_CARD_FRAME, "_gray"), (HOVER_CARD_FRAME, "")):
            out = CARDS_DIR / f"{name}{suffix}.png"
            image = render.crop(cards[(name, frame)], base.bbox).image
            png.save(image, out)
            print(f"wrote {out} {image.size}", file=sys.stderr)
    return rects


def main():
    index = read_swf(WEB_SWF)
    frame_number = timeline.frame_of(index, 0, FRAME_LABEL)
    placements = timeline.frames(index, 0)[frame_number - 1]
    print(f"{FRAME_LABEL}: main-timeline frame {frame_number}", file=sys.stderr)

    foreground = {
        layer.character_id: f"classMenu foreground at depth {depth}"
        for depth, layer in sorted(placements.items())
        if depth > BACKGROUND_MAX_DEPTH
    }
    stripped = tuple(strip.strip_list(WEB_SWF, foreground))
    background = render.Job(
        0, frame_number, BACKGROUND_ZOOM, strip=stripped, background=True
    )
    card_jobs = {
        (name, frame): render.Job(
            cid,
            frame,
            CARD_ZOOM,
            origin=render.placement_origin(index, 0, frame_number, cid),
        )
        for name, cid in sorted(CARDS.items())
        for frame in (BASE_CARD_FRAME, HOVER_CARD_FRAME)
    }
    logo = logo_job(index)
    with render.frames(WEB_SWF, [background, logo, *card_jobs.values()]) as rendered:
        write_background(
            rendered[0], len(foreground), OUT_MENU / "start_background.png"
        )
        write_logo(logo, rendered[1])
        rects = write_cards(dict(zip(card_jobs, rendered[2:], strict=True)))

    print("card rects on the 800x575 stage, in design px:", file=sys.stderr)
    print(
        json.dumps(
            {
                name: {
                    "x": round(rect[0], 2),
                    "y": round(rect[1], 2),
                    "w": round(rect[2], 2),
                    "h": round(rect[3], 2),
                }
                for name, rect in sorted(rects.items())
            },
            indent=1,
            sort_keys=True,
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
