# The original ability/move icon sheet: DefineSprite 2427, one labeled frame
# per move (equipped bar, unequipped pool, AND skill-tree nodes all draw
# from this one clip) PLUS one labeled frame per passive-node buff family
# (e.g. "SAVAGERY", "INTEGRITY") - the talent tree's passive nodes use the
# same sheet, keyed by buff family name instead of move display name.
# Writes assets/ui/abilities/<label>.png at 2x.
# Confirmed 2026-07-23: all 69 active move ids and all 14 passive buff
# families actually used in TalentTree.TREES have a matching label - no
# fallback-art path is needed for anything currently in the trees.
#
# Each frame is rendered by ffdec's own renderer through render.py, not
# reassembled shape-by-shape. An earlier version of this script pasted each
# frame's shapes onto a canvas by hand and lost three separate things that
# live on the PlaceObject tags rather than on the raw shapes:
#
#   1. The clip mask. Every labeled frame places DefineShape 2242 - a 23x23px
#      circle - with a clipDepth covering the depths the icon art sits on
#      (depth 3 covering depths 4-8 on most frames; a second arrangement at
#      depth 1 covering depth 2 also appears). The art itself is much larger
#      than that circle - "Break"'s streak, DefineShape 2256, measures 47x30px
#      - so without the mask it visibly spilled outside the orb.
#   2. The surface filters. "Break"'s depth-6 placement carries a white
#      GLOWFILTER (blurX/blurY 5.0, strength 1.0) that draws the streak's halo.
#   3. The radial gradient fills that shade the orb, its rim and its highlight.
#
# Same root cause and fix as item_icons.py and faces.py, both of which were
# converted away from hand-compositing for exactly these reasons.
#
# Renders with two characters deleted from the SWF, because both
# are opaque in the tag data but hidden by ActionScript at runtime and would
# otherwise paint over every icon. COOLDOWN_DISPLAY below has which ones and
# the evidence.
#
# The Radial menu draws those two itself over a darkened orb, so this also
# writes them out on their own:
#
#   assets/ui/abilities/cooldown_cover.png - the black disc, rendered alone
#   assets/ui/abilities/cooldown.json      - where the disc sits on the orb,
#                                            and where the turns left go and
#                                            in what size, colour and alignment
#
# The count's font is the same bold _sans Device font as the Combat text
# banner's, so the port draws it in the Stand-in font too.
#
# ffdec sizes every exported frame to the whole sprite timeline's union
# bounding box, so each frame comes back as a large, mostly-transparent canvas
# with the icon in one corner. The mask constrains every frame to the same
# 23.75px orb, so all 104 frames share one identical opaque region; each is
# trimmed to its own content and recentered on a 62x62 canvas, which is what
# every consumer already expects (scripts/ui/menu/abilities_window.gd and
# scripts/battle/battle_scene.gd load these by name).
#
# Requires ffdec.
# Run: uv run extract_ability_icons
from __future__ import annotations

import json
import re
import sys

from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import label_layout, render, strip, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "abilities"
COVER_PNG = OUT_DIR / "cooldown_cover.png"
COOLDOWN_JSON = OUT_DIR / "cooldown.json"

ZOOM = 2.0
ICON_SPRITE = 2427
# The slot viewport is 31x31 design px; icons are drawn centered on (0,0).
ICON_HALF = 15.5
COVER_SPRITE = 2241
COUNT_TEXT = 2245
# The variable the Radial menu's enterFrame writes a cooldown's turns left to
# (frame_217/PlaceObject3_3382_500 enterFrame, lines 23-28).
COUNT_VARIABLE = "ACD"

# characterId -> why the running game never shows it.
#
# Both of these are the move-cooldown display: a black disc with a turn
# counter on it, drawn over the icon art while an ability is cooling down.
# Neither is visible on a ready ability, which is the state every icon is
# extracted in.
COOLDOWN_DISPLAY: dict[int, str] = {
    # DefineSprite 2241, placed at depth 11 and named "bfilter" - a fully
    # opaque black disc covering nearly all of the icon art beneath it. Its
    # onLoad clip handler is `if (_parent.dontHide != true) this._visible =
    # false;`, so it hides itself the moment it loads unless the parent asked
    # for the darkened cooldown look. Decoded from the placement's
    # clipActions bytecode: ActionPush "_parent", GetVariable, ActionPush
    # "dontHide", GetMember, Equals2, ActionIf, then ActionPush ("", 7,
    # false) into SetProperty - where property index 7 is _visible.
    COVER_SPRITE: "cooldown darkener, hides itself in onLoad",
    # DefineEditText 2245, placed at depth 13, initialText "00", grey
    # (153,153,153). The cooldown turn counter that sits on the disc above.
    # It survives a shape-by-shape compositor only by accident, because an
    # edit text carries `bounds` where a shape carries `shapeBounds` and the
    # bounds lookup returns nothing for it.
    COUNT_TEXT: "cooldown turn counter, hidden with its disc",
}


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def origin_on_orb(index: SwfIndex, character: int) -> tuple[float, float]:
    """-> where the orb places `character`, in design px from the orb's
    centre. Raises unless every frame that shows it places it in the one spot
    with a pure translate."""
    matrices = {
        layer.matrix
        for layers in timeline.frames(index, ICON_SPRITE)
        for layer in layers.values()
        if layer.character_id == character
    }
    if len(matrices) != 1:
        raise RuntimeError(
            f"{ICON_SPRITE} places {character} with {len(matrices)} matrices, want 1"
        )
    (matrix,) = matrices
    if matrix[:4] != render.IDENTITY_LINEAR:
        raise RuntimeError(f"{ICON_SPRITE} places {character} with {matrix}")
    return matrix[4] / render.TWIPS, matrix[5] / render.TWIPS


def count_layout(index: SwfIndex) -> dict:
    """-> where the cooldown count's line goes from the orb's centre, and its
    size, colour and alignment. Raises unless it is the field the ring writes
    the turns left to."""
    field = label_layout.plain_device_line(index, COUNT_TEXT)
    if field.variable_name != COUNT_VARIABLE:
        raise RuntimeError(
            f"edit text {COUNT_TEXT} is {field.variable_name!r}, want {COUNT_VARIABLE!r}"
        )
    return label_layout.text_layout(field, origin_on_orb(index, COUNT_TEXT))


def main():
    index = read_swf(WEB_SWF)
    labels = timeline.labels(index, ICON_SPRITE)
    print(f"icon labels: {len(labels)}", file=sys.stderr)

    size = (int(ICON_HALF * 2 * ZOOM), int(ICON_HALF * 2 * ZOOM))
    stripped = tuple(strip.strip_list(WEB_SWF, COOLDOWN_DISPLAY))
    jobs = [
        render.Job(ICON_SPRITE, frame, ZOOM, strip=stripped)
        for frame in sorted(set(labels.values()))
    ]
    cover_job = render.Job(
        COVER_SPRITE, 1, ZOOM, origin=origin_on_orb(index, COVER_SPRITE)
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written: dict[str, str] = {}
    blank = []
    oversized = []
    with render.frames(WEB_SWF, [*jobs, cover_job]) as rendered:
        *rendered, cover_frame = rendered
        cover = render.trim(cover_frame)
        if cover is None:
            raise RuntimeError(f"{COVER_SPRITE} rendered empty")
        cover.image.save(COVER_PNG)
        layout = {
            "art_zoom": ZOOM,
            "count": count_layout(index),
            "cover": rect_entry(cover.rect),
        }
        COOLDOWN_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
        print(
            f"cover -> {COVER_PNG.name} {cover.image.size} at {cover.rect},"
            f" layout -> {COOLDOWN_JSON.name}",
            file=sys.stderr,
        )
        by_frame = {frame.job.frame: frame for frame in rendered}
        for label, frame in labels.items():
            trimmed = render.trim(by_frame[frame])
            canvas = Image.new("RGBA", size, (0, 0, 0, 0))
            if trimmed is None:
                # The empty-slot labels ("None", "Empty", "Empty2") draw
                # nothing at all; they stay a blank canvas of the usual size so
                # every consumer keeps getting one predictable icon size.
                blank.append(label)
            else:
                content = trimmed.image
                if content.width > size[0] or content.height > size[1]:
                    # Nothing on this sheet is expected to outgrow the slot,
                    # so report it rather than silently trimming an icon that
                    # the mask should already have constrained.
                    oversized.append((label, content.size))
                    left = max(0, (content.width - size[0]) // 2)
                    top = max(0, (content.height - size[1]) // 2)
                    content = content.crop(
                        (
                            left,
                            top,
                            left + min(content.width, size[0]),
                            top + min(content.height, size[1]),
                        )
                    )
                canvas.alpha_composite(
                    content,
                    ((size[0] - content.width) // 2, (size[1] - content.height) // 2),
                )
            file_name = sanitize(label) + ".png"
            canvas.save(OUT_DIR / file_name)
            written[label] = file_name
    print(f"icons written: {len(written)}", file=sys.stderr)
    if blank:
        print(f"blank (empty-slot labels): {blank}", file=sys.stderr)
    if oversized:
        print(f"content larger than {size}: {oversized}", file=sys.stderr)


if __name__ == "__main__":
    main()
