#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Prototype: index frame labels and the AS1/2 bytecode that names them,
straight from the SWF, with no ffdec and no XML dump.

Usage: uv run swf_index.py <file.swf> <out.json>
"""

from __future__ import annotations

import json
import struct
import sys
import time
import zlib
from collections import defaultdict


class Bits:
    def __init__(self, data: bytes, pos: int):
        self.data, self.byte, self.bit = data, pos, 0

    def ub(self, n: int) -> int:
        v = 0
        for _ in range(n):
            b = (self.data[self.byte] >> (7 - self.bit)) & 1
            v = (v << 1) | b
            self.bit += 1
            if self.bit == 8:
                self.bit, self.byte = 0, self.byte + 1
        return v

    def sb(self, n: int) -> int:
        v = self.ub(n)
        if n and v & (1 << (n - 1)):
            v -= 1 << n
        return v

    def align(self) -> int:
        if self.bit:
            self.bit, self.byte = 0, self.byte + 1
        return self.byte


def skip_rect(data, pos):
    b = Bits(data, pos)
    n = b.ub(5)
    vals = [b.sb(n) for _ in range(4)]
    return b.align(), vals


def skip_matrix(data, pos):
    b = Bits(data, pos)
    if b.ub(1):
        n = b.ub(5)
        b.sb(n), b.sb(n)
    if b.ub(1):
        n = b.ub(5)
        b.sb(n), b.sb(n)
    n = b.ub(5)
    b.sb(n), b.sb(n)
    return b.align()


def skip_cxform_alpha(data, pos):
    b = Bits(data, pos)
    has_add, has_mult = b.ub(1), b.ub(1)
    n = b.ub(4)
    if has_mult:
        [b.sb(n) for _ in range(4)]
    if has_add:
        [b.sb(n) for _ in range(4)]
    return b.align()


def cstring(data, pos):
    end = data.index(0, pos)
    return data[pos:end].decode("utf-8", "replace"), end + 1


def scan_actions(data, start, end):
    """Linear scan of an AS1/2 action stream. Function bodies follow their
    DefineFunction header inline, so a flat walk visits them too."""
    strings, gotos, pool = set(), [], []
    pos = start
    while pos < end:
        code = data[pos]
        pos += 1
        if code == 0:
            continue
        if code < 0x80:
            continue
        (length,) = struct.unpack_from("<H", data, pos)
        pos += 2
        body = data[pos : pos + length]
        pos += length
        if code == 0x88:  # ConstantPool
            (count,) = struct.unpack_from("<H", body, 0)
            p, pool = 2, []
            for _ in range(count):
                s, p = cstring(body, p)
                pool.append(s)
        elif code == 0x8C:  # GotoLabel
            s, _ = cstring(body, 0)
            gotos.append(("GotoLabel", s))
            strings.add(s)
        elif code == 0x81:  # GotoFrame (0-based)
            gotos.append(("GotoFrame", struct.unpack_from("<H", body)[0] + 1))
        elif code == 0x96:  # Push
            p = 0
            while p < len(body):
                t = body[p]
                p += 1
                if t == 0:
                    s, p = cstring(body, p)
                    strings.add(s)
                elif t in (1, 7):
                    p += 4
                elif t in (4, 5, 8):
                    if t == 8 and body[p] < len(pool):
                        strings.add(pool[body[p]])
                    p += 1
                elif t == 6:
                    p += 8
                elif t == 9:
                    (i,) = struct.unpack_from("<H", body, p)
                    if i < len(pool):
                        strings.add(pool[i])
                    p += 2
    if "gotoAndStop" in strings or "gotoAndPlay" in strings:
        gotos.append(("CallMethod", "gotoAndStop/gotoAndPlay"))
    return strings, gotos


def parse_clip_actions(data, pos, end, swf_version):
    pos += 2  # reserved
    pos += 4 if swf_version >= 6 else 2  # all event flags
    blocks = []
    while pos < end:
        flags = struct.unpack_from("<I" if swf_version >= 6 else "<H", data, pos)[0]
        pos += 4 if swf_version >= 6 else 2
        if flags == 0:
            break
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        blocks.append((pos, pos + size, flags))
        pos += size
    return blocks


FILTER_NAMES = {0: "DropShadow", 1: "Blur", 2: "Glow", 3: "Bevel", 4: "GradientGlow", 5: "Convolution", 6: "ColorMatrix", 7: "GradientBevel"}
FILTER_SIZES = {0: 23, 1: 9, 2: 15, 3: 27, 6: 80}


class Index:
    def __init__(self, version):
        self.version = version
        self.labels = defaultdict(dict)  # owner -> {label: frame}
        self.frames = {}
        self.exports = {}
        self.code = []  # {owner, frame, kind, strings, gotos}
        self.placements = defaultdict(list)
        self.stats = defaultdict(int)

    def walk(self, data, pos, end, owner):
        frame = 1
        while pos < end:
            (hdr,) = struct.unpack_from("<H", data, pos)
            pos += 2
            code, length = hdr >> 6, hdr & 0x3F
            if length == 0x3F:
                (length,) = struct.unpack_from("<I", data, pos)
                pos += 4
            body, nxt = pos, pos + length
            self.stats[f"tag_{code}"] += 1
            if code == 0:
                break
            if code == 1:
                frame += 1
            elif code == 43:
                s, _ = cstring(data, body)
                self.labels[owner][s] = frame
            elif code == 39:
                sid, fc = struct.unpack_from("<HH", data, body)
                self.frames[sid] = fc
                self.walk(data, body + 4, nxt, sid)
            elif code == 56:
                (n,) = struct.unpack_from("<H", data, body)
                p = body + 2
                for _ in range(n):
                    (cid,) = struct.unpack_from("<H", data, p)
                    name, p = cstring(data, p + 2)
                    self.exports[name] = cid
            elif code == 12:
                s, g = scan_actions(data, body, nxt)
                self.code.append(dict(owner=owner, frame=frame, kind="DoAction", strings=s, gotos=g))
            elif code == 59:
                (sid,) = struct.unpack_from("<H", data, body)
                s, g = scan_actions(data, body + 2, nxt)
                self.code.append(dict(owner=sid, frame=0, kind="DoInitAction", strings=s, gotos=g))
            elif code == 34:
                bid, _flags, off = struct.unpack_from("<HBH", data, body)
                if off:
                    p = body + 3 + off
                    while p < nxt:
                        size, _cond = struct.unpack_from("<HH", data, p)
                        stop = p + size if size else nxt
                        s, g = scan_actions(data, p + 4, stop)
                        self.code.append(dict(owner=bid, frame=0, kind="ButtonAction", strings=s, gotos=g))
                        if not size:
                            break
                        p = stop
            elif code in (26, 70):
                self.place(data, body, nxt, owner, frame, code)
            pos = nxt

    def place(self, data, p, end, owner, frame, code):
        f1 = data[p]
        f2 = data[p + 1] if code == 70 else 0
        p += 2 if code == 70 else 1
        (depth,) = struct.unpack_from("<H", data, p)
        p += 2
        if code == 70 and (f2 & 0x08 or (f2 & 0x10 and f1 & 0x02)):
            _, p = cstring(data, p)
        cid = None
        if f1 & 0x02:
            (cid,) = struct.unpack_from("<H", data, p)
            p += 2
        if f1 & 0x04:
            p = skip_matrix(data, p)
        if f1 & 0x08:
            p = skip_cxform_alpha(data, p)
            self.stats["placements_with_colortransform"] += 1
        if f1 & 0x10:
            p += 2
        name = None
        if f1 & 0x20:
            name, p = cstring(data, p)
        clip = None
        if f1 & 0x40:
            (clip,) = struct.unpack_from("<H", data, p)
            p += 2
            self.stats["placements_with_clipdepth"] += 1
        if code == 70:
            if f2 & 0x01:
                self.stats["placements_with_filters"] += 1
                n = data[p]
                p += 1
                for _ in range(n):
                    ft = data[p]
                    p += 1
                    self.stats[f"filter_{FILTER_NAMES[ft]}"] += 1
                    if ft in (4, 7):
                        p += 1 + 5 * data[p] + 19
                    elif ft == 5:
                        p += 2 + 8 + 4 * data[p] * data[p + 1] + 5
                    else:
                        p += FILTER_SIZES[ft]
            if f2 & 0x02:
                self.stats[f"blendmode_{data[p]}"] += 1
                p += 1
            if f2 & 0x04:
                p += 1
        if f1 & 0x80:
            for start, stop, ev in parse_clip_actions(data, p, end, self.version):
                s, g = scan_actions(data, start, stop)
                self.code.append(
                    dict(owner=owner, frame=frame, kind=f"ClipAction(depth={depth},cid={cid},ev=0x{ev:x})",
                         strings=s, gotos=g, placed_cid=cid, placed_name=name)
                )
        if cid is not None or name is not None:
            self.placements[owner].append((frame, depth, cid, name))


def main():
    src, out = sys.argv[1], sys.argv[2]
    t0 = time.perf_counter()
    raw = open(src, "rb").read()
    sig, version = raw[:3], raw[3]
    data = zlib.decompress(raw[8:]) if sig == b"CWS" else raw[8:]
    data = b"\0" * 8 + data
    pos, rect = skip_rect(data, 8)
    _rate, root_frames = struct.unpack_from("<HH", data, pos)
    idx = Index(version)
    idx.frames[0] = root_frames
    idx.walk(data, pos + 4, len(data), 0)
    t_parse = time.perf_counter() - t0

    all_labels = {(o, l): f for o, ls in idx.labels.items() for l, f in ls.items()}
    by_name = defaultdict(list)
    for (o, l), f in all_labels.items():
        by_name[l].append((o, f))
    refs = defaultdict(list)
    for i, c in enumerate(idx.code):
        for s in c["strings"]:
            if s in by_name:
                refs[s].append(i)
    referenced = {l for l in by_name if refs.get(l)}
    id_to_export = {v: k for k, v in idx.exports.items()}
    report = dict(
        swf=src,
        version=version,
        root_frames=root_frames,
        parse_seconds=round(t_parse, 3),
        sprites=len(idx.frames) - 1,
        sprites_with_labels=len([o for o in idx.labels if o != 0]),
        label_count=len(all_labels),
        distinct_label_names=len(by_name),
        code_blocks=len(idx.code),
        code_blocks_with_goto=sum(1 for c in idx.code if c["gotos"]),
        distinct_label_names_named_in_bytecode=len(referenced),
        stats=dict(sorted(idx.stats.items())),
        labels={
            f"{o}{'/' + id_to_export[o] if o in id_to_export else ''}": ls
            for o, ls in sorted(idx.labels.items())
        },
        label_refs={
            l: [
                dict(owner=idx.code[i]["owner"], frame=idx.code[i]["frame"], kind=idx.code[i]["kind"])
                for i in refs[l]
            ]
            for l in sorted(referenced)
        },
        unreferenced_labels=sorted(
            f"{o}:{l}@{f}" for (o, l), f in all_labels.items() if l not in referenced
        ),
    )
    with open(out, "w") as fh:
        json.dump(report, fh, indent=1)
    print(json.dumps({k: v for k, v in report.items() if k not in ("labels", "label_refs", "unreferenced_labels")}, indent=1))


if __name__ == "__main__":
    main()
