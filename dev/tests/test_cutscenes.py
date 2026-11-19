# Pins every cutscene to the wrapper the root timeline places on its own
# label's frame, as recorded in label_xref.json, so the mapping can no longer
# shift by one label. It also pins each committed clip to the frame count its
# table entry declares.
from __future__ import annotations

import json
import struct
from pathlib import Path

from PIL import Image
from test_swf_index import IDENTITY_MATRIX, bits, label as frame_label, place2, swf, tag
from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract.cutscenes import (
    CUTSCENES,
    IDENTITY_COLOR,
    MAX_ENCODE_DIFFERENCE,
    OUT_DIR,
    OUT_H,
    OUT_W,
    camera_view,
    find_broken_bitmap_fill_cids,
    mean_difference,
    stage_layers,
    write_cutscene_swf,
)
from urchin_dev.swf.label_xref import OUT
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE3,
    TAG_DEFINE_SHAPE4,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)
from urchin_dev.swf.timeline import frames as timeline_frames


def test_each_cutscene_uses_the_wrapper_on_its_own_label_frame():
    xref = json.loads(OUT.read_text())
    root = {r["label"]: r for r in xref["labels"] if r["sprite"] == 0}
    for label, (_animation, wrapper, _frames, _overlay) in CUTSCENES.items():
        assert root[label]["places"] == [wrapper], label


OGG_PAGE = struct.Struct("<4sBBqIIIB")
THEORA_HEADER = struct.Struct(">7sBBBHH3s3sBBII3s3sB3sH")


def ogv_frame_count(path: Path) -> int:
    """Count the frames of an Ogg Theora file from its container alone, so the
    test needs no ffprobe, which a fresh checkout may not have.

    The last page of the Theora stream holds the granule position of the last
    frame. Its low KFGSHIFT bits count the frames since the last keyframe, and
    the bits above them count the frames before that keyframe. A stream of
    version 3.2.1 or later stores a count and not an index, so the two parts
    add up to the frame count as they are. KFGSHIFT is in the header's first
    packet, as bits 5 to 9 of its last 16 bits.
    """
    data = path.read_bytes()
    theora_serial = None
    key_shift = 0
    last_granule = 0
    page = 0
    while page < len(data):
        capture, _version, _flags, granule, serial, _sequence, _crc, segments = (
            OGG_PAGE.unpack_from(data, page)
        )
        if capture != b"OggS":
            raise ValueError(f"{path.name}: no Ogg page at byte {page}")
        body = page + OGG_PAGE.size + segments
        if theora_serial is None and data[body : body + 7] == b"\x80theora":
            theora_serial = serial
            _signature, major, minor, revision, *_fields, last_16_bits = (
                THEORA_HEADER.unpack_from(data, body)
            )
            if (major, minor, revision) < (3, 2, 1):
                raise ValueError(f"{path.name}: Theora {major}.{minor}.{revision}")
            key_shift = (last_16_bits >> 5) & 0x1F
        if serial == theora_serial and granule >= 0:
            last_granule = granule
        page = body + sum(data[page + OGG_PAGE.size : body])
    if theora_serial is None:
        raise ValueError(f"{path.name}: no Theora stream")
    return (last_granule >> key_shift) + (last_granule & ((1 << key_shift) - 1))


def test_each_extracted_clip_is_as_long_as_its_table_entry():
    for label, (_animation, _wrapper, frames, _overlay) in CUTSCENES.items():
        assert ogv_frame_count(OUT_DIR / f"{label}.ogv") == frames, label


def ogv_picture_size(path: Path) -> tuple[int, int]:
    """Read the picture size of an Ogg Theora file from its first packet, so
    the test needs no ffprobe.

    The first page of the Theora stream is the first page of the file here,
    and its packet gives the picture's width and height as two 24-bit numbers.
    The coded frame is larger, because Theora rounds it up to whole 16 px
    blocks.
    """
    data = path.read_bytes()
    body = OGG_PAGE.size + data[OGG_PAGE.size - 1]
    if data[body : body + 7] != b"\x80theora":
        raise ValueError(f"{path.name}: the first Ogg page is not a Theora header")
    fields = THEORA_HEADER.unpack_from(data, body)
    return int.from_bytes(fields[6], "big"), int.from_bytes(fields[7], "big")


def test_each_extracted_clip_is_the_size_of_the_stage():
    for label in CUTSCENES:
        assert ogv_picture_size(OUT_DIR / f"{label}.ogv") == (OUT_W, OUT_H), label


def test_a_missing_bitmap_fill_counts_only_when_an_edge_paints_with_it():
    # Shapes 3997 and 4018 of CS_CUT4 hold bitmap 65535 as fill 1 of their
    # second style set, and the edges of that set paint only with fill 2, a
    # real bitmap. Shape 5 is like them. Each other shape holds 65535 as fill 1
    # or fill 2 of its only style set, and its one edge paints either the 65535
    # fill or the real bitmap.
    missing = bytes([0x43]) + struct.pack("<H", 65535) + IDENTITY_MATRIX
    bitmap = bytes([0x43]) + struct.pack("<H", 7) + IDENTITY_MATRIX
    new_styles = 0b10000

    def styles(*fills: bytes) -> bytes:
        # The fills, no line styles, and 2 bits for each fill index.
        return bytes([len(fills)]) + b"".join(fills) + bytes([0]) + bytes([0x20])

    def paint(fill: int, then: int = 0) -> bytes:
        # A StyleChangeRecord that sets FillStyle1, one straight edge, and a
        # StyleChangeRecord with the `then` flags, which end the shape at 0.
        return bits(
            (0, 1), (0b00100, 5), (fill, 2),
            (1, 1), (1, 1), (0, 4), (0, 1), (0, 1), (1, 2),
            (0, 1), (then, 5),
        )  # fmt: skip

    def shape3(cid: int, body: bytes) -> bytes:
        return tag(TAG_DEFINE_SHAPE3, struct.pack("<H", cid) + b"\0" + body)

    shapes = [
        shape3(1, styles(missing, bitmap) + paint(2)),
        shape3(2, styles(missing, bitmap) + paint(1)),
        shape3(3, styles(bitmap, missing) + paint(1)),
        shape3(4, styles(bitmap, missing) + paint(2)),
        shape3(5, styles(bitmap) + paint(1, new_styles) + styles(missing, bitmap) + paint(2)),
        shape3(6, styles(bitmap) + paint(1, new_styles) + styles(missing, bitmap) + paint(1)),
    ]  # fmt: skip
    placed = b"".join(place2(cid, cid=cid) for cid in range(1, 7))
    sprite = tag(
        TAG_DEFINE_SPRITE,
        struct.pack("<HH", 9, 1) + placed + tag(TAG_SHOW_FRAME) + tag(TAG_END),
    )
    index = parse_swf(swf(*shapes, sprite, tag(TAG_SHOW_FRAME)))
    assert find_broken_bitmap_fill_cids(index, 9) == {2, 4, 6}


def test_a_line_that_bitmap_65535_paints_counts_only_when_an_edge_strokes_it():
    # A DefineShape4 line can carry a fill style in place of a colour. Shape 1
    # strokes its one edge with such a line, and shape 2 has the same line and
    # an edge that strokes nothing.
    missing = bytes([0x43]) + struct.pack("<H", 65535) + IDENTITY_MATRIX

    def shape4(cid: int, line: int) -> bytes:
        filled_line = struct.pack("<H", 20) + bytes([0x08, 0]) + missing
        # Two empty RECTs, the flags byte, no fills, the line, then 0 bits for
        # fill indices and 1 bit for line indices.
        styles = b"\0\0\0" + bytes([0]) + bytes([1]) + filled_line + bytes([0x01])
        records = bits(
            (0, 1), (0b01000, 5), (line, 1),
            (1, 1), (1, 1), (0, 4), (0, 1), (0, 1), (1, 2),
            (0, 1), (0, 5),
        )  # fmt: skip
        return tag(TAG_DEFINE_SHAPE4, struct.pack("<H", cid) + styles + records)

    placed = place2(1, cid=1) + place2(2, cid=2)
    sprite = tag(
        TAG_DEFINE_SPRITE,
        struct.pack("<HH", 9, 1) + placed + tag(TAG_SHOW_FRAME) + tag(TAG_END),
    )
    index = parse_swf(
        swf(shape4(1, line=1), shape4(2, line=0), sprite, tag(TAG_SHOW_FRAME))
    )
    assert find_broken_bitmap_fill_cids(index, 9) == {1}


# The camera's own art, shape 3477, is 10660x6000 twips, the 533x300 view.
CAMERA_SIZE = (10660, 6000)


def test_the_camera_at_frame_240_of_cs_intro2_blows_its_region_up():
    # Sprite 3643 places camera 3478 with this matrix on frame 240. The
    # script sets the parent's scale to 533 / the camera's width, and its x to
    # 266.5 minus the camera's x times that scale.
    camera = (0.4281463623046875, 0.0, 0.0, 0.428131103515625, -2167, -1625)
    matrix, color = camera_view(camera, None, CAMERA_SIZE)
    scale_x, skew0, skew1, scale_y, tx, ty = matrix
    assert abs(scale_x - 2.3356) < 1e-4
    assert abs(scale_y - 2.3357) < 1e-4
    assert (skew0, skew1) == (0.0, 0.0)
    assert (tx, ty) == (
        5330 + round(2167 / 0.4281463623046875),
        3000 + round(1625 / 0.428131103515625),
    )
    assert color == IDENTITY_COLOR


def test_the_camera_size_sets_the_zoom():
    # A camera twice the view's size at scale 1 shows the animation at half size.
    matrix, _color = camera_view((1.0, 0.0, 0.0, 1.0, 0, 0), None, (21320, 12000))
    assert matrix == (0.5, 0.0, 0.0, 0.5, 5330, 3000)


def test_the_camera_color_transform_passes_to_the_animation_unchanged():
    # Five of the six animations open with their camera multiplying red, green
    # and blue by 0, so the cutscene fades in from black.
    black = (0, 0, 0, 256, 0, 0, 0, 0)
    _matrix, color = camera_view((1.0, 0.0, 0.0, 1.0, 0, 0), black, CAMERA_SIZE)
    assert color == black


def test_a_rotated_camera_is_refused():
    try:
        camera_view((1.0, 0.5, -0.5, 1.0, 0, 0), None, CAMERA_SIZE)
    except ValueError:
        return
    raise AssertionError("a rotated camera passed")


def test_the_cutscene_movie_plays_the_wrapper_and_moves_its_animation(tmp_path):
    # Wrapper 9 has the layout of the game's wrappers: a mask at depth 1 that
    # clips to 72, animation 7 at depth 2 and an outline at depth 73. The root
    # timeline plays two frames of something else, which the movie drops.
    mask = (
        bytes([0x46])
        + struct.pack("<HH", 1, 5)
        + IDENTITY_MATRIX
        + struct.pack("<H", 72)
    )
    animation_matrix = bits((0, 1), (0, 1), (14, 5), (5395, 14), (3049, 14))
    wrapper = tag(
        TAG_DEFINE_SPRITE,
        struct.pack("<HH", 9, 1)
        + tag(26, mask)
        + place2(2, cid=7, matrix=animation_matrix)
        + place2(73, cid=6, matrix=IDENTITY_MATRIX)
        + tag(TAG_SHOW_FRAME)
        + tag(TAG_END),
    )
    src = tmp_path / "src.swf"
    src.write_bytes(
        swf(
            wrapper,
            place2(5, cid=8),
            tag(TAG_SHOW_FRAME),
            tag(TAG_SHOW_FRAME),
            frames=2,
        )
    )
    dark = (128, 64, 32, 256, 10, -20, 30, 0)
    views = [
        ((2.5, 0.0, 0.0, 2.25, -1000, 2000), (0, 0, 0, 256, 0, 0, 0, 0)),
        ((2.5, 0.0, 0.0, 2.25, -1000, 2000), (0, 0, 0, 256, 0, 0, 0, 0)),
        ((0.75, 0.0, 0.0, 0.75, 5330, 3000), dark),
    ]
    stage = [
        (1, 4, (1.0, 0.0, 0.0, 1.0, -10, -10)),
        (2, 9, (1.0, 0.0, 0.0, 1.0, 2660, 2740)),
    ]
    dest = tmp_path / "dest.swf"

    write_cutscene_swf(src, dest, 9, 7, 2, views, stage)

    index = parse_swf(dest.read_bytes())
    assert index.root_frames == 3
    root = timeline_frames(index, 0)
    assert len(root) == 3
    for frame in root:
        assert [
            (d, layer.character_id, layer.matrix) for d, layer in frame.items()
        ] == stage
    assert index.sprite_frames[9] == 3
    shown = timeline_frames(index, 9)
    assert len(shown) == 3
    for frame, (matrix, color) in zip(shown, views, strict=True):
        assert sorted(frame) == [1, 2, 73]
        assert frame[1].clip_depth == 72
        assert frame[2].character_id == 7
        assert frame[2].matrix == matrix
        assert frame[2].color_transform == color
    # Frame 2 repeats frame 1, so the wrapper writes no move for it.
    moves = [p for p in index.placements if p.owner == 9 and p.move]
    assert [p.frame for p in moves] == [3]


TRACED_CAMERA_LOG = (
    REPO_ROOT / "references/traced_runs/cutscene_camera/camera_web_flash.txt"
)


def traced_wrapper_positions() -> dict[str, tuple[int, int]]:
    """The root position of each cutscene wrapper, in twips, as the Flash debug
    player read it in the Traced run of #411. Columns 15 and 16 of a CAM line
    are the wrapper's _x and _y."""
    positions = {}
    for line in TRACED_CAMERA_LOG.read_text().splitlines():
        fields = line.split("\t")
        if fields[0] == "CAM":
            positions[fields[1]] = (
                round(float(fields[14]) * 20),
                round(float(fields[15]) * 20),
            )
    return positions


def test_the_traced_run_read_cs_cut5_off_the_centre_of_the_stage():
    positions = traced_wrapper_positions()
    assert positions["CS_CUT5"] == (2811, 2831)
    assert positions["CS_INTRO2"] == positions["CS_CUT4"] == (2670, 2750)


def test_each_root_layer_stays_where_the_game_places_it():
    # Each wrapper sits where the Traced run read it, over backdrop 3475 at
    # depth 1, with the fade clip 3466 above it. The movie keeps every layer
    # up to the wrapper where the root places it, so each clip shows its box
    # where the game does. The old code moved CS_CUT5's box to (133, 137).
    backdrop = bits((0, 1), (0, 1), (14, 5), (-120, 14), (-80, 14))
    for label, (x, y) in traced_wrapper_positions().items():
        wrapper = bits((0, 1), (0, 1), (14, 5), (x, 14), (y, 14))
        index = parse_swf(
            swf(
                tag(TAG_SHOW_FRAME),
                frame_label(label),
                place2(1, cid=3475, matrix=backdrop),
                place2(2, cid=4154, matrix=wrapper),
                place2(3, cid=3466, matrix=IDENTITY_MATRIX),
                tag(TAG_SHOW_FRAME),
                frames=2,
            )
        )

        assert stage_layers(index, label, 4154) == [
            (1, 3475, (1.0, 0.0, 0.0, 1.0, -120, -80)),
            (2, 4154, (1.0, 0.0, 0.0, 1.0, x, y)),
        ], label


def test_a_moved_encode_differs_from_the_render_past_the_limit():
    # A frame with a 533x300 box of stripes over a dark stage, and the same
    # frame moved 7 px left and 4 px up, as the old crop and pad moved CS_CUT5.
    render = Image.new("RGB", (OUT_W, OUT_H), (20, 24, 26))
    for x in range(141, 674, 6):
        render.paste((230, 200, 40), (x, 142, x + 3, 442))
    moved = Image.new("RGB", (OUT_W, OUT_H), (20, 24, 26))
    moved.paste(render.crop((140, 141, 673, 441)), (133, 137))

    assert mean_difference(render, render) == 0
    assert mean_difference(render, moved) > MAX_ENCODE_DIFFERENCE
