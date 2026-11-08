# swf_index.py
# Reads frame labels, placements, export names and AS1/2 code blocks straight
# out of a SWF, with no ffdec and no XML dump. It walks every tag, recursing
# into DefineSprite, and parses only as much of each tag as it needs to reach
# the fields it records. Shape and morph geometry is not parsed, since art is
# rendered through ffdec and never composited in Python (CLAUDE.md).
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
TAG_PLACE_OBJECT = 4
TAG_DEFINE_BUTTON = 7
TAG_DO_ACTION = 12
TAG_PLACE_OBJECT2 = 26
TAG_DEFINE_BUTTON2 = 34
TAG_DEFINE_SPRITE = 39
TAG_FRAME_LABEL = 43
TAG_EXPORT_ASSETS = 56
TAG_DO_INIT_ACTION = 59
TAG_PLACE_OBJECT3 = 70

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
    owner: int
    frame: int
    depth: int
    character_id: int | None
    name: str | None
    clip_depth: int | None
    tag: int
    has_color_transform: bool = False
    filters: tuple[str, ...] = ()
    blend_mode: int | None = None


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
    version: int
    root_frames: int
    sprite_frames: dict[int, int] = field(default_factory=dict)
    labels: list[Label] = field(default_factory=list)
    placements: list[Placement] = field(default_factory=list)
    code: list[CodeBlock] = field(default_factory=list)
    exports: dict[str, int] = field(default_factory=dict)


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


def _skip_matrix(data: bytes, pos: int) -> int:
    bits = _Bits(data, pos)
    for _ in range(2):  # scale, then rotate/skew
        if bits.ub(1):
            bits.ub(2 * bits.ub(5))
    bits.ub(2 * bits.ub(5))  # translate
    return bits.align()


def _skip_cxform(data: bytes, pos: int, with_alpha: bool) -> int:
    bits = _Bits(data, pos)
    has_add, has_mult = bits.ub(1), bits.ub(1)
    n = bits.ub(4)
    channels = 4 if with_alpha else 3
    bits.ub(n * channels * (has_add + has_mult))
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
                self.index.placements.append(
                    Placement(owner, frame, depth, cid, None, None, code)
                )
            elif code in (TAG_PLACE_OBJECT2, TAG_PLACE_OBJECT3):
                self._place(body, after, owner, frame, code)

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
        cid = None
        if flags & 0x02:
            (cid,) = struct.unpack_from("<H", data, p)
            p += 2
        if flags & 0x04:
            p = _skip_matrix(data, p)
        if flags & 0x08:
            p = _skip_cxform(data, p, with_alpha=True)
        if flags & 0x10:
            p += 2  # ratio
        name = None
        if flags & 0x20:
            name, p = _cstring(data, p)
        clip_depth = None
        if flags & 0x40:
            (clip_depth,) = struct.unpack_from("<H", data, p)
            p += 2
        filters, blend_mode = [], None
        if code == TAG_PLACE_OBJECT3:
            if flags3 & 0x01:
                count = data[p]
                p += 1
                for _ in range(count):
                    filters.append(FILTER_NAMES[data[p]])
                    p += _filter_size(data, p)
            if flags3 & 0x02:
                blend_mode = data[p]
                p += 1
            if flags3 & 0x04:
                p += 1  # bitmap cache
            if flags3 & 0x20:
                p += 1  # visible
            if flags3 & 0x40:
                p += 4  # background color
        self.index.placements.append(
            Placement(
                owner,
                frame,
                depth,
                cid,
                name,
                clip_depth,
                code,
                has_color_transform=bool(flags & 0x08),
                filters=tuple(filters),
                blend_mode=blend_mode,
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
    index = SwfIndex(version=version, root_frames=root_frames)
    _Walker(data, index).walk(pos + 4, len(data), 0)
    return index


def read_swf(path: Path) -> SwfIndex:
    return parse_swf(Path(path).read_bytes())
