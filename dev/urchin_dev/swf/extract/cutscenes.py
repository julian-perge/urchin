# Story cutscenes as playable video: each cutscene is a pair of DefineSprites
# on the root timeline, gotoAndStop-jumped into by frame label (see
# frame_219/DoAction.as's afterCut assignments, and each cutscene sprite's own
# final-frame DoAction setting cutSceneEnd). Produces
# assets/cutscenes/<label>.ogv for every label in CUTSCENES below - Ogg Theora
# is Godot's only built-in video codec (WebM was removed from Godot core in
# 4.0).
#
# The pair is an *animation* sprite (chid N, one frame per animation frame)
# nested inside a *wrapper* sprite (chid N+1, frameCount 1), and it is the
# wrapper the root timeline actually places. The wrapper is not a pass-through
# - it does two things that decide what the player of the original ever sees:
#
#   1. It places the animation sprite offset by translate (5395, 3049) twips
#      = (269.75, 152.45) px, identical across every wrapper.
#   2. It places DefineShape 2870 - a plain 10660x6000-twip (533x300 px)
#      rectangle - at depth 1 with a clipDepth covering the animation
#      sprite's depth. That is a clip mask: everything the animation draws
#      outside that 533x300 box is invisible in the original.
#
# An earlier version of this script exported the *animation* sprite directly,
# which skipped both. That shipped four clips at four different aspect ratios,
# each one the animation's own full untrimmed bounding box - unmasked, unplaced
# and mostly empty. Exporting through the wrapper instead hands the masking
# and the placement to ffdec's own renderer, which honours the clipDepth.
#
# Every animation sprite places a Cutscene camera as a direct child (3478,
# 3645, 3812, 3962 and 4041 all run the same frame script,
# DefineSprite_3478/frame_1/DoAction.as). Its own art is a red bounding box, a
# center crosshair and a color-bar swatch, which the original never shows: the
# script hides the clip on its first frame, then every frame it moves, scales
# and tints the parent animation so that the camera's box fills the 533x300
# view. ffdec does not run ActionScript, so this script does both halves
# itself. It strips the clip, because ffdec would draw the box, and
# camera_view() turns each frame's camera placement into the animation's
# placement, which write_cutscene_swf() writes into the wrapper as one
# PlaceObject2 move per frame. ffdec's -removeCharacterWithDependencies was
# tried for the strip first and rejected: it cascades and deletes the
# *parent* cutscene sprite too, because the parent places the camera clip as
# a child of itself. Plain -removeCharacter only drops that one placement.
#
# The wrapper declares frameCount="1", and ffdec sizes a sprite export to the
# union of all its children's bounds, clip mask or not, which a zoomed camera
# makes as large as 16695x8756 px. So write_cutscene_swf() also gives the
# working copy a new root timeline, as long as the animation, that places
# what the game's root shows on the cutscene's frame: the dark backdrop shape
# 3475 and the wrapper over it. ffdec sizes a root export to the 800x575
# stage, renders as many frames as the header declares, and ticks the nested
# wrapper and animation forward one frame per frame. The backdrop fills what
# the animation leaves transparent, which the sprite export used to fill
# white: 83% of CS_CUT4's first frame and a strip down CS_CUT2's left edge.
#
# Each label's wrapper is the one sprite the root timeline places on that
# label's own frame, which label_xref.json records as the label's "places" and
# dev/tests/test_cutscenes.py checks. A label shares its root frame with the
# placement written after it in the file, so the placement just above a label
# belongs to the label before it. Reading it the other way shipped CS_CUT2 to
# CS_CUT5 one label early: the intro played after battle 109, CS_CUT1 after
# 210, and the real CS_CUT2 (3810) and CS_CUT5 (4153) were never extracted.
# The frame counts are each animation sprite's own frameCount, and each camera
# clip is a sprite the animation places directly on its frame 1.
#
# ffdec's sprite:avi export renders video only (no audio track) - each
# cutscene's dialogue/music is a SoundStreamBlockTag-per-frame MP3 stream
# attached to the *animation* sprite's timeline (not the wrapper's and not the
# main timeline), so it has to be reconstructed by hand: per the SWF10 spec,
# an MP3-compressed stream block is a 4-byte header (2-byte sample count,
# 2-byte seek-samples) followed by raw MPEG frame bytes - stripping that
# header from every block in frame order and concatenating gives a valid,
# playable MP3.
#
# The exported AVI stores frames as PNG-in-AVI, and one ffmpeg pass crops
# and pads them, encodes them as Theora and the MP3 as Vorbis, and writes the
# Ogg file. ffmpeg needs libtheora and libvorbis for that, which Homebrew's
# ffmpeg-full has. The settings match what the Theora and Vorbis
# identification headers of the clips this replaced carry: Theora quality 38
# of 63, a keyframe at least every 64 frames, and Vorbis at a nominal
# 80 kbps. Those clips went through ffmpeg2theora, which Homebrew deprecated,
# by way of an x264 intermediate that only worked around ffmpeg2theora's
# bundled ffmpeg misreading the color matrix as GBR.
#
# No -shortest trim on the encode: a couple of these cutscenes' audio streams
# run somewhat short of their frame count (trailing silent frames with no
# new sound block), and trimming to the shorter stream would clip the tail
# of the video instead of just leaving it silent.
#
# Twenty shapes of the web SWF hold a fill of bitmap 65535, the SWF id for
# "no such bitmap", and the SWF defines no bitmap with that id. In every one of
# them, no edge paints with that fill, so it draws nothing. CS_CUT3 (sprite
# 3960) and CS_CUT4 (sprite 4038) place eleven of these shapes. Their edges
# paint with the other fill, a real bitmap. In CS_CUT3, that bitmap is one of
# four frames of grey TV static (bitmaps 3950 to 3956). In CS_CUT4, it is the
# skull and blood art. The Steam SWF has the same four static bitmaps in shapes
# 3883 to 3889, with no 65535 fill. Until #81, this script stripped every
# shape whose first fill was 65535, and read the static on frames 467 to 477
# of CS_CUT3 as an ffdec fault, so both clips lost art the original shows.
# find_broken_bitmap_fill_cids() now finds only a shape that paints with
# bitmap 65535. No shape does, and the extract stops if one ever does, because
# nothing shows how Flash Player draws a fill with no bitmap.
#
# Requires ffdec (~/.local/bin/ffdec) for the character-strip and video
# export, and an ffmpeg with libtheora and libvorbis (`brew install
# ffmpeg-full`) for the encode and the checks.
# Run: uv run extract_cutscenes [LABEL ...]
# With no label every clip in CUTSCENES is extracted. A full run encodes all of
# them again, and the encode does not reproduce the committed clips byte for
# byte, so name the label of a new clip to leave the others as they are.
from __future__ import annotations

import functools
import re
import shutil
import sys
import tempfile
import zlib
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF
from urchin_dev.run import run
from urchin_dev.swf import strip, timeline
from urchin_dev.swf.swf_index import (
    SHAPE_TAGS,
    SwfIndex,
    read_swf,
    shape_bounds,
    shape_styles,
    sound_stream,
)

OUT_DIR = REPO_ROOT / "assets" / "cutscenes"


_TOOL_HINTS = {
    "ffmpeg": "needs libtheora and libvorbis, e.g. `brew install ffmpeg-full`",
    "ffprobe": "used for post-generation verification",
}


@functools.cache
def tool(name: str) -> Path:
    """Resolve a tool on PATH instead of hardcoding a Homebrew-on-Apple-
    Silicon path - the previous version of this script fell back to a bare
    "/opt/homebrew/bin/ffmpeg2theora" string with no existence check, which
    breaks silently on Intel Homebrew (/usr/local) or Linux. Resolved on first
    use rather than at import, so the tests can read CUTSCENES on a machine
    without these tools.
    """
    found = shutil.which(name)
    if found is None:
        raise SystemExit(
            f"required tool '{name}' not found on PATH ({_TOOL_HINTS[name]})"
        )
    return Path(found)


# label -> (animation sprite chid, wrapper sprite chid, frame count,
# camera clip chid to strip). The frame count is the *animation* sprite's;
# the wrapper always declares 1 and gets patched up to this (see file header).
# CS_CUT1 and CS_CUT3 place the same camera clip, 3812.
CUTSCENES: dict[str, tuple[int, int, int, int]] = {
    "CS_INTRO2": (3643, 3644, 2084, 3478),
    "CS_CUT1": (3928, 3929, 621, 3812),
    "CS_CUT2": (3810, 3811, 1795, 3645),
    "CS_CUT3": (3960, 3961, 501, 3812),
    "CS_CUT4": (4038, 4039, 1237, 3962),
    "CS_CUT5": (4153, 4154, 2424, 4041),
}

# The wrapper's clip mask (DefineShape 2870) is a rectangle 10660x6000 twips
# from the wrapper's own origin, and there are 20 twips to a pixel.
MASK_W, MASK_H = 533, 300

# The SWF stage is 16000x11500 twips (800x575 px). Five wrappers sit on it at
# (2670, 2750) twips = (133.5, 137.5) px, which centers the 533x300 mask
# exactly, and CS_CUT5's sits at (2811, 2831). Godot's viewport is the same
# 800x575 (project.godot), so a clip with the mask box centered in an 800x575
# frame is the whole Stage, and cutscene_player.tscn's VideoStreamPlayer fills
# the viewport with it and does not scale it. stage_layers() moves every
# cutscene's root layers so the box lands on whole pixels at (133, 137), half
# a pixel up and left of the five centered wrappers.
OUT_W, OUT_H = 800, 575
CONTENT_X, CONTENT_Y = (OUT_W - MASK_W) // 2, (OUT_H - MASK_H) // 2

# Verification thresholds - see verify_output()'s and _frame_noise()'s
# docstrings. A frame has to clear both noise bars to be called static.
DURATION_TOLERANCE_S = 2.0
NOISE_RESIDUAL_THRESHOLD = 20.0
NOISE_RATIO_THRESHOLD = 0.35
NOISE_SAMPLE_INTERVAL_S = 1.0
# A clip may have up to this many sampled frames read as static before the
# export fails, so a short burst passes and a long run of static stops it.
# CS_CUT3 shows the original's own TV static on frames 467 to 477, and one
# sampled frame lands on it.
MAX_TOLERATED_NOISE_FRAMES = 2
# CS_INTRO2 (sprite 3643) ends on a motorcycle jumping a prison yard behind
# chain-link fence and razor wire. That fine detail reads as static, and three
# sampled frames in a row do, at 67.5, 68.5 and 69.4 s. Frames 2025, 2055 and
# 2083 of the stripped wrapper show real art and no noise, so this clip may
# have three.
#
# CS_CUT2 (sprite 3810) has a figure falling in front of dense white speed
# lines. Two sampled frames of them read as static, at 6.09 and 7.10 s of the
# encoded clip, and both show real art and no noise. That is the whole general
# limit, and a new encode can move a third sample onto the speed lines, so this
# clip may have three.
TOLERATED_NOISE_FRAMES = {"CS_INTRO2": 3, "CS_CUT2": 3}

MISSING_BITMAP = 65535

# SWF tag encoding, used by write_cutscene_swf().
DEFINE_SPRITE_TAG = 39
PLACE_OBJECT2_TAG = 26
SHOW_FRAME_CODE = 1
# The root tags that show, place, remove, label, script or stream a frame.
# write_cutscene_swf() drops them and keeps every definition.
ROOT_FRAME_TAGS = frozenset({0, 1, 4, 5, 12, 15, 18, 19, 26, 28, 43, 45, 70, 89})
SHOW_FRAME_TAG = b"\x40\x00"  # UI16 0x0040 - tag code 1, body length 0
END_TAG = b"\x00\x00"

Matrix = tuple[float, float, float, float, int, int]
IDENTITY_MATRIX: Matrix = (1.0, 0.0, 0.0, 1.0, 0, 0)
IDENTITY_COLOR = (256, 256, 256, 256, 0, 0, 0, 0)

# The view that camControl() in DefineSprite_3478/frame_1/DoAction.as fills
# with the camera's box: its cX, cY, sX and sY, in pixels. It is the wrapper's
# 533x300 clip mask.
VIEW_CENTER_X, VIEW_CENTER_Y, VIEW_W, VIEW_H = 266.5, 150, 533, 300
# The red box, crosshair and color bars that every camera clip places alone.
CAMERA_SHAPE = 3477


def _swf_body(path: Path) -> tuple[int, bytes]:
    """Split a SWF into its version byte and its decompressed body (the bytes
    after the 8-byte signature/version/length header).
    """
    raw = path.read_bytes()
    signature, version = raw[:3], raw[3]
    if signature == b"FWS":
        return version, raw[8:]
    if signature == b"CWS":
        return version, zlib.decompress(raw[8:])
    raise SystemExit(f"unsupported SWF signature {signature!r} in {path}")


def _walk_tags(body: bytes, start: int):
    """Yield (offset, tag code, header length, body length) for each tag from
    start onwards, stopping after the file's End tag.
    """
    pos = start
    while pos < len(body) - 1:
        code_and_length = int.from_bytes(body[pos : pos + 2], "little")
        code, length, header = code_and_length >> 6, code_and_length & 0x3F, 2
        if length == 0x3F:  # long-form header: the real length follows as UI32
            length = int.from_bytes(body[pos + 2 : pos + 6], "little")
            header = 6
        yield pos, code, header, length
        pos += header + length
        if code == 0:
            return


def camera_view(
    camera_matrix: Matrix,
    camera_color: tuple[int, ...] | None,
    camera_size: tuple[int, int],
) -> tuple[Matrix, tuple[int, ...]]:
    """The animation's placement in its wrapper, in twips, for one frame of
    its camera clip, as camControl() in DefineSprite_3478/frame_1/DoAction.as
    sets it.

    The script scales the animation by 533 over the camera's _width and 300
    over its _height. Its _x and _y become 266.5 and 150 minus the camera's
    position times those scales. The camera's color transform replaces the
    animation's own, and a camera with none gives the identity.
    camera_size is the camera clip's own width and height in twips.
    """
    scale_x, skew0, skew1, scale_y, tx, ty = camera_matrix
    if skew0 or skew1:
        raise ValueError(f"camera matrix {camera_matrix} rotates or skews")
    zoom_x = VIEW_W * 20 / (camera_size[0] * scale_x)
    zoom_y = VIEW_H * 20 / (camera_size[1] * scale_y)
    matrix = (
        zoom_x,
        0.0,
        0.0,
        zoom_y,
        round(VIEW_CENTER_X * 20 - tx * zoom_x),
        round(VIEW_CENTER_Y * 20 - ty * zoom_y),
    )
    return matrix, camera_color or IDENTITY_COLOR


def camera_views(
    index: SwfIndex, animation_id: int, camera_id: int
) -> list[tuple[Matrix, tuple[int, ...]]]:
    """The animation's placement for each of its frames, from the camera clip
    it places on that frame."""
    camera_places = [p for p in index.placements if p.owner == camera_id]
    if [p.character_id for p in camera_places] != [CAMERA_SHAPE] or camera_places[
        0
    ].matrix not in (None, IDENTITY_MATRIX):
        raise RuntimeError(
            f"camera {camera_id} does not place shape {CAMERA_SHAPE} alone at "
            "its origin, so its _width is not that shape's width"
        )
    x0, y0, x1, y1 = shape_bounds(index, CAMERA_SHAPE)
    camera_size = (x1 - x0, y1 - y0)
    views = []
    for number, shown in enumerate(timeline.frames(index, animation_id), 1):
        cameras = [layer for layer in shown.values() if layer.character_id == camera_id]
        if len(cameras) != 1:
            raise RuntimeError(
                f"sprite {animation_id} frame {number} shows camera {camera_id} "
                f"{len(cameras)} times"
            )
        views.append(
            camera_view(cameras[0].matrix, cameras[0].color_transform, camera_size)
        )
    return views


def stage_layers(
    index: SwfIndex, label: str, wrapper_id: int
) -> list[tuple[int, int, Matrix]]:
    """What the root timeline shows on the label's frame, from depth 1 up to
    the wrapper, as (depth, character id, matrix). Every layer moves by the
    same offset, so the wrapper's clip mask lands on whole pixels at
    (CONTENT_X, CONTENT_Y), where the encode crops it. Below the wrapper the
    game shows shape 3475, the dark backdrop."""
    shown = timeline.frames(index, 0)[timeline.frame_of(index, 0, label) - 1]
    wrapper_depth = next(
        depth for depth, layer in shown.items() if layer.character_id == wrapper_id
    )
    wrapper = shown[wrapper_depth]
    dx = CONTENT_X * 20 - wrapper.matrix[4]
    dy = CONTENT_Y * 20 - wrapper.matrix[5]
    layers = []
    for depth, layer in sorted(shown.items()):
        if depth > wrapper_depth:
            continue
        if (
            layer.matrix[:4] != IDENTITY_MATRIX[:4]
            or layer.color_transform
            or layer.clip_depth
        ):
            raise RuntimeError(
                f"{label}: root depth {depth} scales, tints or masks, which the "
                "cutscene export does not copy"
            )
        tx, ty = layer.matrix[4] + dx, layer.matrix[5] + dy
        layers.append((depth, layer.character_id, (1.0, 0.0, 0.0, 1.0, tx, ty)))
    return layers


def _signed_bits(*values: int) -> int:
    return max(1, *((v if v >= 0 else ~v).bit_length() + 1 for v in values))


def _pack_bits(fields: list[tuple[int, int]]) -> bytes:
    """Pack (value, width) fields big-endian into whole bytes, as the SWF bit
    records store them."""
    text = "".join(format(v & ((1 << w) - 1), f"0{w}b") for v, w in fields)
    text += "0" * (-len(text) % 8)
    return int(text, 2).to_bytes(len(text) // 8, "big")


def _matrix_record(matrix: Matrix) -> bytes:
    scale_x, _skew0, _skew1, scale_y, tx, ty = matrix
    fixed_x, fixed_y = round(scale_x * 65536), round(scale_y * 65536)
    scale_bits = _signed_bits(fixed_x, fixed_y)
    move_bits = _signed_bits(tx, ty)
    return _pack_bits(
        [(1, 1), (scale_bits, 5), (fixed_x, scale_bits), (fixed_y, scale_bits)]
        + [(0, 1), (move_bits, 5), (tx, move_bits), (ty, move_bits)]
    )


def _color_record(color: tuple[int, ...]) -> bytes:
    n = _signed_bits(*color)
    return _pack_bits([(1, 1), (1, 1), (n, 4)] + [(term, n) for term in color])


def _tag(code: int, body: bytes) -> bytes:
    return (
        ((code << 6) | 0x3F).to_bytes(2, "little")
        + len(body).to_bytes(4, "little")
        + body
    )


def _place(depth: int, flags: int, character_id: int | None, *records: bytes) -> bytes:
    body = bytes([flags]) + depth.to_bytes(2, "little")
    if character_id is not None:
        body += character_id.to_bytes(2, "little")
    return _tag(PLACE_OBJECT2_TAG, body + b"".join(records))


def _camera_wrapper(
    tag_body: bytes,
    animation_id: int,
    animation_depth: int,
    views: list[tuple[Matrix, tuple[int, ...]]],
) -> bytes:
    """The DefineSprite body of a wrapper, as long as views, that moves the
    animation by its camera on every frame.

    Frame 1 places the animation with the first view in place of the
    wrapper's own placement. Each later frame whose view differs from the one
    before gets a PlaceObject2 move, which ffdec draws as it draws any other
    keyframe.
    """
    wrapper_id = int.from_bytes(tag_body[:2], "little")
    inner = b""
    placed = False
    for pos, code, header, length in _walk_tags(tag_body, 4):
        fields = tag_body[pos + header : pos + header + length]
        if code in (SHOW_FRAME_CODE, 0):
            break
        if (
            code == PLACE_OBJECT2_TAG
            and int.from_bytes(fields[1:3], "little") == animation_depth
        ):
            if (
                fields[0] != 0x06
                or int.from_bytes(fields[3:5], "little") != animation_id
            ):
                raise RuntimeError(
                    f"wrapper {wrapper_id} depth {animation_depth} is not a plain "
                    f"placement of sprite {animation_id}"
                )
            matrix, color = views[0]
            inner += _place(
                animation_depth,
                0x0E,
                animation_id,
                _matrix_record(matrix),
                _color_record(color),
            )
            placed = True
        else:
            inner += tag_body[pos : pos + header + length]
    if not placed:
        raise RuntimeError(f"wrapper {wrapper_id} does not place sprite {animation_id}")
    inner += SHOW_FRAME_TAG
    for previous, (matrix, color) in zip(views, views[1:]):
        if (matrix, color) != previous:
            inner += _place(
                animation_depth,
                0x0D,
                None,
                _matrix_record(matrix),
                _color_record(color),
            )
        inner += SHOW_FRAME_TAG
    return tag_body[:2] + len(views).to_bytes(2, "little") + inner + END_TAG


def write_cutscene_swf(
    src: Path,
    dest: Path,
    wrapper_id: int,
    animation_id: int,
    animation_depth: int,
    views: list[tuple[Matrix, tuple[int, ...]]],
    stage: list[tuple[int, int, Matrix]],
) -> None:
    """Write src to dest as a movie that only plays one cutscene: its root
    timeline places the stage layers and runs as many frames as views, and
    the wrapper moves the animation by its camera on every frame.

    ffdec sizes a sprite's export to the union of every child's bounds and
    ignores the clip mask, so a camera that zooms in 4.3x made a 16695x8756
    px export of the CS_INTRO2 wrapper. It sizes the root timeline's export
    to the stage, which the header gives. ffdec renders as many root frames
    as the header declares and ticks nested sprites along with it, so the
    one-frame wrapper renders the whole animation. Every other root tag that
    shows, plays or labels a frame is dropped, and every definition is kept.
    dest is written uncompressed (FWS), which ffdec reads as well as the
    zlib-compressed original.
    """
    version, body = _swf_body(src)
    # The tag area starts after the frame-size RECT (5 bits of bit-width, then
    # 4 fields of that width), the frame rate and the frame count.
    rect_bytes = (5 + 4 * (body[0] >> 3) + 7) // 8
    out = body[: rect_bytes + 2] + len(views).to_bytes(2, "little")
    found = False
    for pos, code, header, length in _walk_tags(body, rect_bytes + 4):
        tag_body = body[pos + header : pos + header + length]
        if code in ROOT_FRAME_TAGS:
            continue
        if (
            code == DEFINE_SPRITE_TAG
            and int.from_bytes(tag_body[:2], "little") == wrapper_id
        ):
            out += _tag(
                DEFINE_SPRITE_TAG,
                _camera_wrapper(tag_body, animation_id, animation_depth, views),
            )
            found = True
        else:
            out += body[pos : pos + header + length]
    if not found:
        raise RuntimeError(f"DefineSprite {wrapper_id} not found in {src}")
    for depth, character_id, matrix in stage:
        out += _place(depth, 0x06, character_id, _matrix_record(matrix))
    out += SHOW_FRAME_TAG * len(views) + END_TAG
    dest.write_bytes(
        b"FWS" + bytes([version]) + (8 + len(out)).to_bytes(4, "little") + out
    )


def extract_mp3(index: SwfIndex, sprite_id: int, out_path: Path) -> int:
    """Reconstruct the sprite's dialogue/music track from its
    SoundStreamBlockTags and write it as a raw MP3 to out_path.

    Returns the number of blocks concatenated (0 means no audio stream).
    """
    blocks = sound_stream(index, sprite_id)
    with out_path.open("wb") as f:
        for raw in blocks:
            f.write(raw[4:])  # drop the 4-byte sample-count/seek-samples header
    return len(blocks)


def find_broken_bitmap_fill_cids(index: SwfIndex, sprite_id: int) -> set[int]:
    """Shapes placed directly in this cutscene sprite where an edge paints
    with a fill of bitmap 65535, which the SWF does not define, or strokes a
    DefineShape4 line that such a fill paints. A 65535 fill that no edge
    paints with draws nothing, so it does not count. The file
    header says why no shape in the game is on this list.
    """
    placed = {p.character_id for p in index.placements if p.owner == sprite_id}
    return {
        cid
        for cid in placed
        if cid is not None
        and index.characters[cid][0] in SHAPE_TAGS
        and any(
            MISSING_BITMAP
            in {styles.bitmaps[fill - 1] for fill in styles.used_fills}
            | {styles.line_bitmaps[line - 1] for line in styles.line_bounds}
            for styles in shape_styles(index, cid)
        )
    }


def _frame_noise(png_path: Path) -> tuple[float, float]:
    """How much high-frequency detail a frame has, as (residual spread,
    residual spread relative to the frame's own spread).

    The frame is blurred heavily and differenced against itself. Flat
    cel-shaded art and hard-edged vector shapes are low-frequency content
    with a few sharp edges, so almost all of their variance survives the blur
    and very little lands in the residual; true per-pixel random static has
    no low-frequency structure at all, so nearly all of its variance lands
    there.

    Both numbers are needed, because either one alone misreads these frames.
    Measured on sprite 3960's cropped 533x300 box: the TV static on frames
    467 to 477 reads (43.6, 0.48), and the same frames with the static shapes
    stripped, a nearly flat dark gradient, read (2.8, 0.50). The
    ratios are indistinguishable, because a frame with barely any variance to
    begin with hands almost all of what little it has to the residual. On the
    absolute number the two are 15x apart. The busiest genuine frame sampled
    from that cutscene reads (10.8, 0.24), so a frame has to clear both bars
    to be called static.
    """
    img = Image.open(png_path).convert("L")
    blurred = img.filter(ImageFilter.GaussianBlur(radius=4))
    residual = ImageChops.difference(img, blurred)
    frame_std = ImageStat.Stat(img).stddev[0]
    residual_std = ImageStat.Stat(residual).stddev[0]
    return residual_std, residual_std / (frame_std + 1e-6)


def verify_output(
    label: str, ogv_path: Path, expected_frames: int, has_audio: bool, work_dir: Path
) -> tuple[int, int]:
    """Fail loudly instead of shipping a silently-corrupt or mis-framed file -
    except for up to MAX_TOLERATED_NOISE_FRAMES isolated noise hits (a clip
    named in TOLERATED_NOISE_FRAMES gets its own count), which print a warning
    and pass rather than blocking the whole export. Returns the video stream's
    (width, height) so main() can cross-check that every cutscene came out the
    same shape.

    Checks: exactly the expected stream types are present (Theora video,
    Vorbis audio if the source sprite had one), the frame is exactly the
    OUT_W x OUT_H the wrapper's mask and the stage layout imply - the check
    that would have caught the whole first round of exports, which shipped
    four different aspect ratios, none of them the stage's - the container's
    reported duration is within tolerance of expected_frames/30fps, and a
    sweep of frames sampled roughly once per second across the FULL duration
    (not just a start/midpoint spot check) for high-frequency noise via
    _frame_noise(), which catches a render that comes out as static.

    The noise sweep crops back down to the cutscene box before measuring,
    since the surrounding letterbox is flat black and would otherwise dilute
    the measurement far enough to hide real static.
    """
    probe = run(
        [
            str(tool("ffprobe")),
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,codec_name,width,height:format=duration",
            "-of",
            "default=noprint_wrappers=0",
            str(ogv_path),
        ]
    ).stdout
    if "codec_name=theora" not in probe:
        raise RuntimeError(
            f"{label}: no theora video stream found in {ogv_path}\n{probe}"
        )
    if has_audio and "codec_name=vorbis" not in probe:
        raise RuntimeError(
            f"{label}: expected a vorbis audio stream, none found in {ogv_path}\n{probe}"
        )
    # Only the video stream reports a numeric size; an audio stream's width
    # and height come back as "N/A", so these two never match it.
    width_match = re.search(r"^width=(\d+)$", probe, re.MULTILINE)
    height_match = re.search(r"^height=(\d+)$", probe, re.MULTILINE)
    if width_match is None or height_match is None:
        raise RuntimeError(
            f"{label}: could not read frame size from {ogv_path}\n{probe}"
        )
    width, height = int(width_match.group(1)), int(height_match.group(1))
    if (width, height) != (OUT_W, OUT_H):
        raise RuntimeError(
            f"{label}: frame is {width}x{height}, expected {OUT_W}x{OUT_H} - "
            "the clip mask crop or the stage-centering pad is wrong"
        )
    dur_match = re.search(r"duration=([\d.]+)", probe)
    if dur_match is None:
        raise RuntimeError(f"{label}: could not read duration from {ogv_path}\n{probe}")
    duration = float(dur_match.group(1))
    expected_duration = expected_frames / 30.0
    if abs(duration - expected_duration) > DURATION_TOLERANCE_S:
        raise RuntimeError(
            f"{label}: duration {duration:.2f}s is too far from the "
            f"expected {expected_duration:.2f}s ({expected_frames} frames @ 30fps)"
        )

    sample_dir = work_dir / "verify_frames"
    sample_dir.mkdir(exist_ok=True)
    n_samples = max(2, min(90, int(duration / NOISE_SAMPLE_INTERVAL_S) + 1))
    timestamps = [duration * i / (n_samples - 1) for i in range(n_samples)]
    timestamps[-1] = max(0.0, duration - 0.05)  # stay inside the stream at the tail
    bad_frames = []
    for i, ts in enumerate(timestamps):
        frame_path = sample_dir / f"{i:03d}.png"
        run(
            [
                str(tool("ffmpeg")),
                "-y",
                "-v",
                "error",
                "-ss",
                f"{ts:.3f}",
                "-i",
                str(ogv_path),
                "-frames:v",
                "1",
                "-vf",
                f"crop={MASK_W}:{MASK_H}:{CONTENT_X}:{CONTENT_Y}",
                str(frame_path),
            ]
        )
        if not frame_path.exists():
            continue
        residual, ratio = _frame_noise(frame_path)
        if residual > NOISE_RESIDUAL_THRESHOLD and ratio > NOISE_RATIO_THRESHOLD:
            bad_frames.append((ts, residual, ratio))
    if bad_frames:
        detail = ", ".join(
            f"{ts:.2f}s (residual {d:.1f}, ratio {r:.2f})" for ts, d, r in bad_frames
        )
        tolerated = TOLERATED_NOISE_FRAMES.get(label, MAX_TOLERATED_NOISE_FRAMES)
        if len(bad_frames) > tolerated:
            raise RuntimeError(
                f"{label}: {len(bad_frames)}/{n_samples} sampled frame(s) look like "
                f"static noise: {detail}"
            )
        print(
            f"{label}: tolerating {len(bad_frames)}/{n_samples} sampled frame(s) "
            f"that look like static (within the {tolerated}-frame "
            f"tolerance): {detail}",
            file=sys.stderr,
        )
    return width, height


def process_cutscene(
    label: str,
    chid: int,
    wrapper_chid: int,
    frames: int,
    overlay_chid: int,
    index: SwfIndex,
) -> tuple[int, int]:
    # verify_output() holds the clip to this same count, so a wrong count in
    # the table would pass it. The SWF is where the count comes from.
    swf_frames = index.sprite_frames.get(chid)
    if swf_frames != frames:
        raise RuntimeError(
            f"{label}: the table gives sprite {chid} {frames} frames, "
            f"but the SWF declares {swf_frames}"
        )
    print(
        f"--- {label}: sprite {chid} in wrapper {wrapper_chid}, {frames} frames, "
        f"stripping overlay {overlay_chid} ---",
        file=sys.stderr,
    )
    work_dir = Path(tempfile.mkdtemp(prefix=f"cutscene_{label}_"))
    try:
        broken = sorted(find_broken_bitmap_fill_cids(index, chid))
        if broken:
            raise RuntimeError(
                f"{label}: shape(s) {broken} paint with bitmap 65535, which the "
                "SWF does not define. Check what the original game shows "
                "before you strip or keep them."
            )
        strip_ids = {overlay_chid: "the camera clip, which hides itself on frame 1"}

        views = camera_views(index, chid, overlay_chid)
        depth = next(
            p.depth
            for p in index.placements
            if p.owner == wrapper_chid and p.character_id == chid
        )
        stage = stage_layers(index, label, wrapper_chid)
        movie_swf = work_dir / "cutscene.swf"
        with strip.stripped_copy(WEB_SWF, strip_ids) as stripped:
            write_cutscene_swf(
                stripped, movie_swf, wrapper_chid, chid, depth, views, stage
            )

        avi_dir = work_dir / "avi"
        run(
            [
                str(FFDEC),
                # ffdec narrows a filter's blur box until boxX * boxY * width *
                # height fits under this limit times 100000, so a large filtered
                # object comes out with a thinner blur than the SWF asks for. The
                # largest int means no frame reaches the limit, and ffdec only
                # saves a -config to its own configuration when nothing follows
                # it on the command line.
                "-config",
                "boxBlurPixelsLimit=2147483647",
                "-format",
                "frame:avi",
                "-export",
                "frame",
                str(avi_dir),
                str(movie_swf),
            ]
        )
        avi_path = avi_dir / "frames.avi"
        if not avi_path.exists():
            raise RuntimeError(f"{label}: expected AVI not found at {avi_path}")

        mp3_path = work_dir / "audio.mp3"
        n_blocks = extract_mp3(index, chid, mp3_path)
        print(
            f"{label}: {n_blocks} sound blocks -> {mp3_path.stat().st_size} bytes",
            file=sys.stderr,
        )

        ogv_path = work_dir / f"{label}.ogv"
        encode_cmd = [str(tool("ffmpeg")), "-y", "-v", "error", "-i", str(avi_path)]
        if n_blocks:
            encode_cmd += ["-i", str(mp3_path), "-map", "0:v", "-map", "1:a"]
        encode_cmd += [
            # Crop to the wrapper's clip mask, then re-center that box in an
            # OUT_W x OUT_H frame the way the original centers it on the
            # stage.
            "-vf",
            f"crop={MASK_W}:{MASK_H}:{CONTENT_X}:{CONTENT_Y},pad={OUT_W}:{OUT_H}:{CONTENT_X}:{CONTENT_Y}:black",
            "-pix_fmt",
            "yuv420p",
            "-c:v",
            "libtheora",
            # libtheora's quality is q * 6.3 truncated to an integer, so 6.1
            # gives the 38 the replaced clips carry, where 6 would give 37.
            "-q:v",
            "6.1",
            "-g",
            "64",
        ]
        encode_cmd += ["-c:a", "libvorbis", "-q:a", "1"] if n_blocks else ["-an"]
        encode_cmd += [str(ogv_path)]
        run(encode_cmd)
        print(
            f"{label}: wrote {ogv_path} ({ogv_path.stat().st_size} bytes) - verifying...",
            file=sys.stderr,
        )

        # Verified in scratch first, so a failed encode or check leaves the
        # committed clip in assets/ untouched.
        resolution = verify_output(label, ogv_path, frames, bool(n_blocks), work_dir)
        shutil.copyfile(ogv_path, OUT_DIR / ogv_path.name)
        print(f"{label}: verified OK, copied to {OUT_DIR}", file=sys.stderr)
        return resolution
    finally:
        # Never hold more than one cutscene's raw AVI/stripped-SWF copy/
        # extracted MP3 in scratch space at once - each is several hundred
        # MB (the 2084-frame sprite 3643 alone: ~412MB for the raw AVI).
        shutil.rmtree(work_dir, ignore_errors=True)


def main():
    labels = sys.argv[1:] or list(CUTSCENES)
    unknown = [label for label in labels if label not in CUTSCENES]
    if unknown:
        raise SystemExit(
            f"unknown cutscene label(s) {unknown}, CUTSCENES has {list(CUTSCENES)}"
        )
    for name in _TOOL_HINTS:
        tool(name)
    encoders = run([str(tool("ffmpeg")), "-hide_banner", "-encoders"]).stdout
    for encoder in ("libtheora", "libvorbis"):
        if encoder not in encoders:
            raise SystemExit(
                f"ffmpeg has no {encoder} encoder ({_TOOL_HINTS['ffmpeg']})"
            )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    index = read_swf(WEB_SWF)

    resolutions: dict[str, tuple[int, int]] = {}
    for label in labels:
        chid, wrapper_chid, frames, overlay_chid = CUTSCENES[label]
        resolutions[label] = process_cutscene(
            label, chid, wrapper_chid, frames, overlay_chid, index
        )

    # Every cutscene is masked by the same 533x300 rectangle and centered on
    # the same stage, so they must all come out the same shape. The first
    # round of exports shipped four different aspect ratios; this is the
    # cross-file check that would have stopped it.
    if len(set(resolutions.values())) != 1:
        raise RuntimeError(f"cutscenes disagree on frame size: {resolutions}")
    print(
        f"all {len(resolutions)} cutscenes at {resolutions[next(iter(resolutions))]}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
