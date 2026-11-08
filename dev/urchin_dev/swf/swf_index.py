# swf_index.py
# Reads frame labels, placements, removals, export names, AS1/2 code blocks
# and sound stream blocks straight out of a SWF, with no ffdec and no XML
# dump. It walks every tag, recursing into DefineSprite, and parses only as
# much of each tag as it needs to reach the fields it records. timeline.py
# folds the placements and removals into each frame's display list.
#
# Shapes are only read for their bounds and for the bitmap ids their fills
# use, on demand from the bytes the index keeps. Art is rendered through
# ffdec and never composited in Python (CLAUDE.md).
#
# Owner ids: 0 is the root timeline, any other id is the DefineSprite whose
# subtags hold the tag. Frames are 1-based and counted by ShowFrame tags, and
# a FrameLabel names the frame its ShowFrame closes.
#
# Code blocks are what ffdec's script export writes one file each for:
# DoAction, DoInitAction, each DefineButton2 condition action and each clip
# action record. Each block keeps the strings it pushes or pools and its
# GotoLabel and GotoFrame opcodes. A goto with a receiver, like
# `inner.gotoAndStop("GO")`, compiles to a method call instead, so for those
# the decompiled text is the only readable form (see label_xref.py).
#
# Formats are from the SWF spec v19:
# https://open-flash.github.io/mirrors/swf-spec-19.pdf
from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass, field
from pathlib import Path

TAG_END = 0
TAG_SHOW_FRAME = 1
TAG_DEFINE_SHAPE = 2
TAG_PLACE_OBJECT = 4
TAG_REMOVE_OBJECT = 5
TAG_DO_ACTION = 12
TAG_SOUND_STREAM_BLOCK = 19
TAG_DEFINE_SHAPE2 = 22
TAG_PLACE_OBJECT2 = 26
TAG_REMOVE_OBJECT2 = 28
TAG_DEFINE_SHAPE3 = 32
TAG_DEFINE_BUTTON2 = 34
TAG_DEFINE_SPRITE = 39
TAG_FRAME_LABEL = 43
TAG_EXPORT_ASSETS = 56
TAG_DO_INIT_ACTION = 59
TAG_PLACE_OBJECT3 = 70
TAG_DEFINE_SHAPE4 = 83

SHAPE_TAGS = (TAG_DEFINE_SHAPE, TAG_DEFINE_SHAPE2, TAG_DEFINE_SHAPE3, TAG_DEFINE_SHAPE4)

# Every tag that defines a character a PlaceObject can place. Each starts
# with the character id.
CHARACTER_KINDS = {
    2: "shape",
    22: "shape",
    32: "shape",
    83: "shape",
    46: "morph",
    84: "morph",
    39: "sprite",
    7: "button",
    34: "button",
    11: "text",
    33: "text",
    37: "edittext",
    6: "bitmap",
    20: "bitmap",
    21: "bitmap",
    35: "bitmap",
    36: "bitmap",
    90: "bitmap",
    60: "video",
}

# The four FILLSTYLE types that point at a bitmap character.
BITMAP_FILL_TYPES = (0x40, 0x41, 0x42, 0x43)

ACTION_GOTO_FRAME = 0x81
ACTION_CONSTANT_POOL = 0x88
ACTION_GOTO_LABEL = 0x8C
ACTION_PUSH = 0x96

# A clip action record carries one extra key code byte when it handles
# keyPress, which is bit 17 of the SWF 6+ event flags.
CLIP_EVENT_KEY_PRESS = 1 << 17

FILTER_FIXED_SIZES = {0: 23, 1: 9, 2: 15, 3: 27, 6: 80}
FILTER_NAMES = {
    0: "DropShadow",
    1: "Blur",
    2: "Glow",
    3: "Bevel",
    4: "GradientGlow",
    5: "Convolution",
    6: "ColorMatrix",
    7: "GradientBevel",
}


@dataclass(frozen=True)
class Label:
    owner: int
    frame: int
    name: str


@dataclass(frozen=True)
class Placement:
    """One PlaceObject tag. A field the tag doesn't carry is None.

    matrix is (scaleX, rotateSkew0, rotateSkew1, scaleY, translateX,
    translateY), with the translation in integer twips. color_transform is
    the four multiply terms (256 is 1.0) followed by the four add terms, in
    RGBA order. move is PlaceFlagMove, so a move with a character is a
    replace."""

    owner: int
    frame: int
    depth: int
    character_id: int | None
    name: str | None
    clip_depth: int | None
    tag: int
    move: bool = False
    matrix: tuple[float, float, float, float, int, int] | None = None
    color_transform: tuple[int, ...] | None = None
    ratio: int | None = None
    filters: tuple[str, ...] | None = None
    blend_mode: int | None = None
    clip_actions: bool = False


@dataclass(frozen=True)
class Removal:
    """One RemoveObject or RemoveObject2 tag."""

    owner: int
    frame: int
    depth: int
    tag: int


@dataclass(frozen=True)
class CodeBlock:
    """kind is "frame" (DoAction), "init" (DoInitAction), "button" or
    "clip". owner is the timeline holding the tag, except for "init", whose
    owner is the sprite the init code belongs to, and "button", whose owner is
    the button. placed_id and depth are set for clip actions only."""

    kind: str
    owner: int
    frame: int
    strings: tuple[str, ...]
    goto_labels: tuple[str, ...]
    goto_frames: tuple[int, ...]
    placed_id: int | None = None
    depth: int | None = None
    events: int | None = None


@dataclass
class SwfIndex:
    """display holds each timeline's placements and removals in tag order,
    which is the order timeline.py applies them in. characters maps each
    character id to its defining tag's code and the start and end of that
    tag's body in data, so shape_bounds() and bitmap_fill_ids() can parse a
    shape later. sound_blocks holds the body spans of each timeline's
    SoundStreamBlock tags."""

    version: int
    root_frames: int
    sprite_frames: dict[int, int] = field(default_factory=dict)
    labels: list[Label] = field(default_factory=list)
    placements: list[Placement] = field(default_factory=list)
    code: list[CodeBlock] = field(default_factory=list)
    exports: dict[str, int] = field(default_factory=dict)
    display: dict[int, list[Placement | Removal]] = field(default_factory=dict)
    characters: dict[int, tuple[int, int, int]] = field(default_factory=dict)
    sound_blocks: dict[int, list[tuple[int, int]]] = field(default_factory=dict)
    data: bytes = field(default=b"", repr=False)


class _Bits:
    def __init__(self, data: bytes, pos: int):
        self.data, self.byte, self.bit = data, pos, 0

    def ub(self, n: int) -> int:
        value = 0
        for _ in range(n):
            value = (value << 1) | ((self.data[self.byte] >> (7 - self.bit)) & 1)
            self.bit += 1
            if self.bit == 8:
                self.bit, self.byte = 0, self.byte + 1
        return value

    def sb(self, n: int) -> int:
        value = self.ub(n)
        if n and value & (1 << (n - 1)):
            value -= 1 << n
        return value

    def align(self) -> int:
        if self.bit:
            self.bit, self.byte = 0, self.byte + 1
        return self.byte


def _skip_rect(data: bytes, pos: int) -> int:
    bits = _Bits(data, pos)
    n = bits.ub(5)
    bits.ub(4 * n)
    return bits.align()


def _read_rect(data: bytes, pos: int) -> tuple[int, int, int, int]:
    """-> (xmin, ymin, xmax, ymax) in twips. The RECT itself stores Xmin,
    Xmax, Ymin and Ymax in that order."""
    bits = _Bits(data, pos)
    n = bits.ub(5)
    xmin, xmax, ymin, ymax = (bits.sb(n) for _ in range(4))
    return xmin, ymin, xmax, ymax


def _read_matrix(data: bytes, pos: int):
    """-> ((scaleX, rotateSkew0, rotateSkew1, scaleY, tx, ty), next byte).
    Scale and rotate are 16.16 fixed point and the translation is in twips."""
    bits = _Bits(data, pos)
    scale_x = scale_y = 1.0
    skew0 = skew1 = 0.0
    if bits.ub(1):
        n = bits.ub(5)
        scale_x, scale_y = bits.sb(n) / 65536, bits.sb(n) / 65536
    if bits.ub(1):
        n = bits.ub(5)
        skew0, skew1 = bits.sb(n) / 65536, bits.sb(n) / 65536
    n = bits.ub(5)
    tx, ty = bits.sb(n), bits.sb(n)
    return (scale_x, skew0, skew1, scale_y, tx, ty), bits.align()


def _read_cxform_with_alpha(data: bytes, pos: int):
    """-> ((rm, gm, bm, am, ra, ga, ba, aa), next byte). The record holds the
    multiply terms before the add terms, and either set can be absent."""
    bits = _Bits(data, pos)
    has_add, has_mult = bits.ub(1), bits.ub(1)
    n = bits.ub(4)
    mult = tuple(bits.sb(n) for _ in range(4)) if has_mult else (256, 256, 256, 256)
    add = tuple(bits.sb(n) for _ in range(4)) if has_add else (0, 0, 0, 0)
    return mult + add, bits.align()


def _skip_matrix(data: bytes, pos: int) -> int:
    bits = _Bits(data, pos)
    for _ in range(2):  # scale, then rotate/skew
        if bits.ub(1):
            bits.ub(2 * bits.ub(5))
    bits.ub(2 * bits.ub(5))  # translate
    return bits.align()


def _cstring(data: bytes, pos: int) -> tuple[str, int]:
    end = data.index(0, pos)
    return data[pos:end].decode("utf-8", "replace"), end + 1


def _scan_actions(data: bytes, start: int, end: int):
    """-> (strings, goto labels, goto frames) of one action stream. Function
    bodies sit inline after their DefineFunction header, so a flat walk
    visits them too. GotoFrame's operand is 0-based and returned 1-based."""
    strings: set[str] = set()
    labels: list[str] = []
    frames: list[int] = []
    pool: list[str] = []
    pos = start
    while pos < end:
        code = data[pos]
        pos += 1
        if code < 0x80:
            continue
        (length,) = struct.unpack_from("<H", data, pos)
        body = data[pos + 2 : pos + 2 + length]
        pos += 2 + length
        if code == ACTION_CONSTANT_POOL:
            (count,) = struct.unpack_from("<H", body, 0)
            p, pool = 2, []
            for _ in range(count):
                text, p = _cstring(body, p)
                pool.append(text)
        elif code == ACTION_GOTO_LABEL:
            text, _ = _cstring(body, 0)
            labels.append(text)
            strings.add(text)
        elif code == ACTION_GOTO_FRAME:
            frames.append(struct.unpack_from("<H", body)[0] + 1)
        elif code == ACTION_PUSH:
            p = 0
            while p < len(body):
                kind = body[p]
                p += 1
                if kind == 0:
                    text, p = _cstring(body, p)
                    strings.add(text)
                elif kind in (1, 7):
                    p += 4
                elif kind == 6:
                    p += 8
                elif kind in (4, 5):
                    p += 1
                elif kind == 8:
                    if body[p] < len(pool):
                        strings.add(pool[body[p]])
                    p += 1
                elif kind == 9:
                    (i,) = struct.unpack_from("<H", body, p)
                    if i < len(pool):
                        strings.add(pool[i])
                    p += 2
    return tuple(sorted(strings)), tuple(labels), tuple(frames)


def _filter_size(data: bytes, pos: int) -> int:
    kind = data[pos]
    if kind in (4, 7):  # gradient glow, gradient bevel
        return 1 + 1 + 5 * data[pos + 1] + 19
    if kind == 5:  # convolution
        return 1 + 2 + 8 + 4 * data[pos + 1] * data[pos + 2] + 5
    return 1 + FILTER_FIXED_SIZES[kind]


class _Walker:
    def __init__(self, data: bytes, index: SwfIndex):
        self.data = data
        self.index = index

    def walk(self, pos: int, end: int, owner: int) -> None:
        data = self.data
        frame = 1
        while pos < end:
            (header,) = struct.unpack_from("<H", data, pos)
            pos += 2
            code, length = header >> 6, header & 0x3F
            if length == 0x3F:
                (length,) = struct.unpack_from("<I", data, pos)
                pos += 4
            body, after = pos, pos + length
            pos = after
            if code == TAG_END:
                break
            if code in CHARACTER_KINDS:
                (cid,) = struct.unpack_from("<H", data, body)
                self.index.characters[cid] = (code, body, after)
            if code == TAG_SHOW_FRAME:
                frame += 1
            elif code == TAG_FRAME_LABEL:
                name, _ = _cstring(data, body)
                self.index.labels.append(Label(owner, frame, name))
            elif code == TAG_DEFINE_SPRITE:
                sprite, frames = struct.unpack_from("<HH", data, body)
                self.index.sprite_frames[sprite] = frames
                self.walk(body + 4, after, sprite)
            elif code == TAG_EXPORT_ASSETS:
                (count,) = struct.unpack_from("<H", data, body)
                p = body + 2
                for _ in range(count):
                    (cid,) = struct.unpack_from("<H", data, p)
                    name, p = _cstring(data, p + 2)
                    self.index.exports[name] = cid
            elif code == TAG_DO_ACTION:
                self._code("frame", owner, frame, body, after)
            elif code == TAG_DO_INIT_ACTION:
                (sprite,) = struct.unpack_from("<H", data, body)
                self._code("init", sprite, 0, body + 2, after)
            elif code == TAG_DEFINE_BUTTON2:
                self._button2(body, after)
            elif code == TAG_PLACE_OBJECT:
                cid, depth = struct.unpack_from("<HH", data, body)
                self._record(Placement(owner, frame, depth, cid, None, None, code))
            elif code in (TAG_PLACE_OBJECT2, TAG_PLACE_OBJECT3):
                self._place(body, after, owner, frame, code)
            elif code in (TAG_REMOVE_OBJECT, TAG_REMOVE_OBJECT2):
                at = body + 2 if code == TAG_REMOVE_OBJECT else body
                (depth,) = struct.unpack_from("<H", data, at)
                self.index.display.setdefault(owner, []).append(
                    Removal(owner, frame, depth, code)
                )
            elif code == TAG_SOUND_STREAM_BLOCK:
                self.index.sound_blocks.setdefault(owner, []).append((body, after))

    def _record(self, placement: Placement) -> None:
        self.index.placements.append(placement)
        self.index.display.setdefault(placement.owner, []).append(placement)

    def _code(self, kind, owner, frame, start, end, **extra) -> None:
        strings, labels, frames = _scan_actions(self.data, start, end)
        self.index.code.append(
            CodeBlock(kind, owner, frame, strings, labels, frames, **extra)
        )

    def _button2(self, body: int, end: int) -> None:
        button, _flags, offset = struct.unpack_from("<HBH", self.data, body)
        if not offset:
            return
        p = body + 3 + offset  # ActionOffset counts from its own field
        while p < end:
            (size,) = struct.unpack_from("<H", self.data, p)
            stop = p + size if size else end
            self._code("button", button, 0, p + 4, stop)
            if not size:
                break
            p = stop

    def _place(self, p: int, end: int, owner: int, frame: int, code: int) -> None:
        data = self.data
        flags = data[p]
        flags3 = data[p + 1] if code == TAG_PLACE_OBJECT3 else 0
        p += 2 if code == TAG_PLACE_OBJECT3 else 1
        (depth,) = struct.unpack_from("<H", data, p)
        p += 2
        if code == TAG_PLACE_OBJECT3 and (
            flags3 & 0x08 or (flags3 & 0x10 and flags & 0x02)
        ):
            _, p = _cstring(data, p)  # class name
        cid = matrix = color_transform = ratio = None
        if flags & 0x02:
            (cid,) = struct.unpack_from("<H", data, p)
            p += 2
        if flags & 0x04:
            matrix, p = _read_matrix(data, p)
        if flags & 0x08:
            color_transform, p = _read_cxform_with_alpha(data, p)
        if flags & 0x10:
            (ratio,) = struct.unpack_from("<H", data, p)
            p += 2
        name = None
        if flags & 0x20:
            name, p = _cstring(data, p)
        clip_depth = None
        if flags & 0x40:
            (clip_depth,) = struct.unpack_from("<H", data, p)
            p += 2
        filters, blend_mode = None, None
        if code == TAG_PLACE_OBJECT3:
            if flags3 & 0x01:
                count = data[p]
                p += 1
                filters = []
                for _ in range(count):
                    filters.append(FILTER_NAMES[data[p]])
                    p += _filter_size(data, p)
                filters = tuple(filters)
            if flags3 & 0x02:
                blend_mode = data[p]
                p += 1
            if flags3 & 0x04:
                p += 1  # bitmap cache
            if flags3 & 0x20:
                p += 1  # visible
            if flags3 & 0x40:
                p += 4  # background color
        self._record(
            Placement(
                owner,
                frame,
                depth,
                cid,
                name,
                clip_depth,
                code,
                move=bool(flags & 0x01),
                matrix=matrix,
                color_transform=color_transform,
                ratio=ratio,
                filters=filters,
                blend_mode=blend_mode,
                clip_actions=bool(flags & 0x80),
            )
        )
        if flags & 0x80:
            self._clip_actions(p, end, owner, frame, cid, depth)

    def _clip_actions(self, p, end, owner, frame, cid, depth) -> None:
        wide = self.index.version >= 6
        flag_format, flag_size = ("<I", 4) if wide else ("<H", 2)
        p += 2 + flag_size  # reserved, then the union of all event flags
        while p < end:
            (events,) = struct.unpack_from(flag_format, self.data, p)
            p += flag_size
            if events == 0:
                break
            (size,) = struct.unpack_from("<I", self.data, p)
            p += 4
            start = p + 1 if wide and events & CLIP_EVENT_KEY_PRESS else p
            self._code(
                "clip",
                owner,
                frame,
                start,
                p + size,
                placed_id=cid,
                depth=depth,
                events=events,
            )
            p += size


def parse_swf(raw: bytes) -> SwfIndex:
    signature, version = raw[:3], raw[3]
    if signature == b"CWS":
        payload = zlib.decompress(raw[8:])
    elif signature == b"FWS":
        payload = raw[8:]
    else:
        raise ValueError(f"not an uncompressed or zlib SWF: {signature!r}")
    # Pad back the 8 header bytes so offsets match the file's own.
    data = b"\0" * 8 + payload
    pos = _skip_rect(data, 8)
    _rate, root_frames = struct.unpack_from("<HH", data, pos)
    index = SwfIndex(version=version, root_frames=root_frames, data=data)
    _Walker(data, index).walk(pos + 4, len(data), 0)
    return index


def read_swf(path: Path) -> SwfIndex:
    return parse_swf(Path(path).read_bytes())


def character_kind(index: SwfIndex, cid: int) -> str:
    """-> "shape", "morph", "sprite", "button", "text", "edittext", "bitmap"
    or "video"."""
    return CHARACTER_KINDS[index.characters[cid][0]]


def shape_bounds(index: SwfIndex, cid: int) -> tuple[int, int, int, int]:
    """-> a DefineShape's ShapeBounds as (xmin, ymin, xmax, ymax) in twips."""
    code, body, _end = index.characters[cid]
    if code not in SHAPE_TAGS:
        raise ValueError(f"character {cid} is not a DefineShape")
    return _read_rect(index.data, body + 2)


def sound_stream(index: SwfIndex, owner: int) -> list[bytes]:
    """-> the bodies of a timeline's SoundStreamBlock tags, in tag order."""
    return [index.data[start:end] for start, end in index.sound_blocks.get(owner, [])]


def bitmap_fill_ids(index: SwfIndex, cid: int) -> set[int]:
    """-> every bitmap id a DefineShape's fill styles point at, including the
    fills of DefineShape4 line styles and the style arrays a StateNewStyles
    record brings in partway through the shape."""
    code, body, _end = index.characters[cid]
    if code not in SHAPE_TAGS:
        raise ValueError(f"character {cid} is not a DefineShape")
    data, ids = index.data, set()
    pos = _skip_rect(data, body + 2)
    if code == TAG_DEFINE_SHAPE4:
        pos = _skip_rect(data, pos) + 1  # EdgeBounds, then a byte of flags
    pos = _line_styles(data, _fill_styles(data, pos, code, ids), code, ids)
    bits = _Bits(data, pos)
    fill_bits, line_bits = bits.ub(4), bits.ub(4)
    while True:
        if bits.ub(1):  # an edge record
            straight = bits.ub(1)
            n = bits.ub(4) + 2
            if not straight:
                bits.ub(4 * n)
            elif bits.ub(1):  # a general line has both deltas
                bits.ub(2 * n)
            else:
                bits.ub(1 + n)  # VertLineFlag, then one delta
            continue
        flags = bits.ub(5)
        if flags == 0:
            return ids
        if flags & 0x01:  # StateMoveTo
            bits.ub(2 * bits.ub(5))
        bits.ub(fill_bits * (((flags >> 1) & 1) + ((flags >> 2) & 1)))
        bits.ub(line_bits * ((flags >> 3) & 1))
        if flags & 0x10:  # StateNewStyles, whose arrays start on a byte
            pos = _fill_styles(data, bits.align(), code, ids)
            pos = _line_styles(data, pos, code, ids)
            bits = _Bits(data, pos)
            fill_bits, line_bits = bits.ub(4), bits.ub(4)


def _fill_styles(data: bytes, pos: int, code: int, ids: set[int]) -> int:
    count = data[pos]
    pos += 1
    if count == 0xFF and code != TAG_DEFINE_SHAPE:
        (count,) = struct.unpack_from("<H", data, pos)
        pos += 2
    for _ in range(count):
        pos = _fill_style(data, pos, code, ids)
    return pos


def _fill_style(data: bytes, pos: int, code: int, ids: set[int]) -> int:
    kind = data[pos]
    pos += 1
    color = 4 if code in (TAG_DEFINE_SHAPE3, TAG_DEFINE_SHAPE4) else 3
    if kind == 0x00:
        return pos + color
    if kind in (0x10, 0x12, 0x13):
        pos = _skip_matrix(data, pos)
        records = data[pos] & 0x0F  # under SpreadMode and InterpolationMode
        pos += 1 + records * (1 + color)
        return pos + 2 if kind == 0x13 else pos  # the focal point
    if kind in BITMAP_FILL_TYPES:
        (bitmap,) = struct.unpack_from("<H", data, pos)
        ids.add(bitmap)
        return _skip_matrix(data, pos + 2)
    raise ValueError(f"unknown fill style type {kind:#x}")


def _line_styles(data: bytes, pos: int, code: int, ids: set[int]) -> int:
    count = data[pos]
    pos += 1
    if count == 0xFF:
        (count,) = struct.unpack_from("<H", data, pos)
        pos += 2
    for _ in range(count):
        if code != TAG_DEFINE_SHAPE4:
            pos += 2 + (4 if code == TAG_DEFINE_SHAPE3 else 3)
            continue
        # LINESTYLE2: the width, then two bytes of flags whose first holds
        # JoinStyle in bits 4-5 and HasFillFlag in bit 3.
        flags = data[pos + 2]
        pos += 4
        if (flags >> 4) & 3 == 2:
            pos += 2  # the miter limit
        pos = _fill_style(data, pos, code, ids) if flags & 0x08 else pos + 4
    return pos
