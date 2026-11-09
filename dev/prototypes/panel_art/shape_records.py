#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
# Full parser for a DefineShape's styles and edge records, so a shape can be
# classified as a plain rectangle a StyleBoxFlat could carry or something else.
from __future__ import annotations

import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

WORKTREE = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d"
)
sys.path.insert(0, str(WORKTREE / "dev"))

from urchin_dev.swf.swf_index import (
    _Bits,
    _read_matrix,
    _read_rect,
    _skip_rect,
    read_swf,
)

WEB_SWF = WORKTREE / "sonny-2-2900.swf"
STEAM_SWF = WORKTREE / "SONNY2.swf"


@dataclass
class Fill:
    kind: str
    color: tuple[int, int, int, int] | None = None
    stops: list[tuple[int, tuple[int, int, int, int]]] = field(default_factory=list)
    matrix: tuple | None = None
    bitmap: int | None = None

    def text(self) -> str:
        if self.kind == "solid":
            return "solid " + hexa(self.color)
        if self.kind == "bitmap":
            return f"bitmap {self.bitmap}"
        return self.kind + "(" + " ".join(f"{hexa(c)}:{r}" for r, c in self.stops) + ")"


@dataclass
class Line:
    width: float
    color: tuple[int, int, int, int] | None
    fill: Fill | None = None
    no_h: bool = False
    no_v: bool = False
    hinted: bool = False
    join: int = 0
    cap_start: int = 0

    def text(self) -> str:
        c = self.fill.text() if self.fill else hexa(self.color)
        flags = "".join(
            s
            for s, on in (
                (" noHScale", self.no_h),
                (" noVScale", self.no_v),
                (" hinted", self.hinted),
            )
            if on
        )
        return f"{self.width:.2f}px {c}{flags} join{self.join}"


def hexa(c):
    if c is None:
        return "?"
    r, g, b, a = c
    return f"#{r:02x}{g:02x}{b:02x}" + ("" if a == 255 else f"@{a}")


def _color(data, p, alpha):
    if alpha:
        return tuple(data[p : p + 4]), p + 4
    r, g, b = data[p : p + 3]
    return (r, g, b, 255), p + 3


def _fill(data, p, code) -> tuple[Fill, int]:
    alpha = code in (32, 83)
    kind = data[p]
    p += 1
    if kind == 0x00:
        c, p = _color(data, p, alpha)
        return Fill("solid", color=c), p
    if kind in (0x10, 0x12, 0x13):
        m, p = _read_matrix(data, p)
        n = data[p] & 0x0F
        p += 1
        stops = []
        for _ in range(n):
            ratio = data[p]
            p += 1
            c, p = _color(data, p, alpha)
            stops.append((ratio, c))
        if kind == 0x13:
            p += 2
        name = {0x10: "linear", 0x12: "radial", 0x13: "focal"}[kind]
        return Fill(name, stops=stops, matrix=m), p
    if kind in (0x40, 0x41, 0x42, 0x43):
        (bid,) = struct.unpack_from("<H", data, p)
        p += 2
        m, p = _read_matrix(data, p)
        return Fill("bitmap", bitmap=bid, matrix=m), p
    raise ValueError(f"fill type {kind:#x}")


def _style_arrays(data, p, code):
    count = data[p]
    p += 1
    if count == 0xFF and code != 2:
        (count,) = struct.unpack_from("<H", data, p)
        p += 2
    fills = []
    for _ in range(count):
        f, p = _fill(data, p, code)
        fills.append(f)
    count = data[p]
    p += 1
    if count == 0xFF:
        (count,) = struct.unpack_from("<H", data, p)
        p += 2
    lines = []
    for _ in range(count):
        (w,) = struct.unpack_from("<H", data, p)
        p += 2
        if code == 83:
            f1, f2 = data[p], data[p + 1]
            p += 2
            cap_start = f1 >> 6
            join = (f1 >> 4) & 3
            has_fill = bool(f1 & 0x08)
            no_h = bool(f1 & 0x04)
            no_v = bool(f1 & 0x02)
            hinted = bool(f1 & 0x01)
            if join == 2:
                p += 2
            if has_fill:
                f, p = _fill(data, p, code)
                lines.append(
                    Line(w / 20.0, None, f, no_h, no_v, hinted, join, cap_start)
                )
            else:
                c, p = _color(data, p, True)
                lines.append(
                    Line(w / 20.0, c, None, no_h, no_v, hinted, join, cap_start)
                )
        else:
            c, p = _color(data, p, code == 32)
            lines.append(Line(w / 20.0, c))
    return fills, lines, p


@dataclass
class Edge:
    x0: int
    y0: int
    x1: int
    y1: int
    curve: bool
    fill0: tuple | None
    fill1: tuple | None
    line: tuple | None


@dataclass
class Shape:
    cid: int
    code: int
    bounds: tuple[float, float, float, float]
    fills: list[list[Fill]]
    lines: list[list[Line]]
    edges: list[Edge]

    def all_fills(self):
        used = []
        for e in self.edges:
            for key in (e.fill0, e.fill1):
                if key is not None and key not in used:
                    used.append(key)
        return used

    def all_lines(self):
        used = []
        for e in self.edges:
            if e.line is not None and e.line not in used:
                used.append(e.line)
        return used

    def fill_of(self, key):
        return self.fills[key[0]][key[1] - 1]

    def line_of(self, key):
        return self.lines[key[0]][key[1] - 1]


def parse(index, cid) -> Shape:
    code, body, _end = index.characters[cid]
    data = index.data
    rect = _read_rect(data, body + 2)
    p = _skip_rect(data, body + 2)
    if code == 83:
        p = _skip_rect(data, p)
        p += 1
    bounds = tuple(v / 20.0 for v in rect)
    fills, lines, p = _style_arrays(data, p, code)
    fill_sets = [fills]
    line_sets = [lines]
    bits = _Bits(data, p)
    nf = bits.ub(4)
    nl = bits.ub(4)
    x = y = 0
    fs0 = fs1 = ls = 0
    style_set = 0
    edges: list[Edge] = []
    while True:
        if bits.ub(1) == 0:
            flags = bits.ub(5)
            if flags == 0:
                break
            new_styles, line_style, fill1, fill0, moved = (
                bool(flags & 16),
                bool(flags & 8),
                bool(flags & 4),
                bool(flags & 2),
                bool(flags & 1),
            )
            if moved:
                n = bits.ub(5)
                x = bits.sb(n)
                y = bits.sb(n)
            if fill0:
                fs0 = bits.ub(nf)
            if fill1:
                fs1 = bits.ub(nf)
            if line_style:
                ls = bits.ub(nl)
            if new_styles:
                q = bits.align()
                f2, l2, q = _style_arrays(data, q, code)
                fill_sets.append(f2)
                line_sets.append(l2)
                style_set += 1
                bits = _Bits(data, q)
                nf = bits.ub(4)
                nl = bits.ub(4)
                fs0 = fs1 = ls = 0
        elif bits.ub(1) == 1:
            n = bits.ub(4) + 2
            if bits.ub(1):
                dx = bits.sb(n)
                dy = bits.sb(n)
            elif bits.ub(1):
                dx, dy = 0, bits.sb(n)
            else:
                dx, dy = bits.sb(n), 0
            edges.append(_edge(x, y, x + dx, y + dy, False, style_set, fs0, fs1, ls))
            x += dx
            y += dy
        else:
            n = bits.ub(4) + 2
            cx, cy, ax, ay = bits.sb(n), bits.sb(n), bits.sb(n), bits.sb(n)
            edges.append(
                _edge(x, y, x + cx + ax, y + cy + ay, True, style_set, fs0, fs1, ls)
            )
            x += cx + ax
            y += cy + ay
    return Shape(cid, code, bounds, fill_sets, line_sets, edges)


def _edge(x0, y0, x1, y1, curve, style_set, fs0, fs1, ls):
    return Edge(
        x0,
        y0,
        x1,
        y1,
        curve,
        (style_set, fs0) if fs0 else None,
        (style_set, fs1) if fs1 else None,
        (style_set, ls) if ls else None,
    )


def _rect_of(edges) -> tuple[float, float, float, float] | None:
    """-> the rectangle these edges trace, or None when they trace anything else."""
    if not edges or any(e.curve for e in edges):
        return None
    if any(e.x0 != e.x1 and e.y0 != e.y1 for e in edges):
        return None
    xs = sorted({e.x0 for e in edges} | {e.x1 for e in edges})
    ys = sorted({e.y0 for e in edges} | {e.y1 for e in edges})
    if len(xs) != 2 or len(ys) != 2:
        return None
    left, right, top, bottom = xs[0], xs[1], ys[0], ys[1]
    covered = {"l": 0, "r": 0, "t": 0, "b": 0}
    for e in edges:
        if e.x0 == e.x1:
            covered["l" if e.x0 == left else "r"] += abs(e.y1 - e.y0)
        else:
            covered["t" if e.y0 == top else "b"] += abs(e.x1 - e.x0)
    if covered["l"] != bottom - top or covered["r"] != bottom - top:
        return None
    if covered["t"] != right - left or covered["b"] != right - left:
        return None
    return left / 20.0, top / 20.0, right / 20.0, bottom / 20.0


@dataclass
class Verdict:
    category: str
    detail: str
    fill_rect: tuple | None
    line_rect: tuple | None
    fill: Fill | None
    line: Line | None
    n_fills: int
    n_lines: int
    n_edges: int
    n_curves: int


def classify(shape: Shape) -> Verdict:
    fill_keys = shape.all_fills()
    line_keys = shape.all_lines()
    n_curves = sum(e.curve for e in shape.edges)
    fill = shape.fill_of(fill_keys[0]) if len(fill_keys) == 1 else None
    line = shape.line_of(line_keys[0]) if len(line_keys) == 1 else None
    fill_edges = [e for e in shape.edges if e.fill0 or e.fill1]
    line_edges = [e for e in shape.edges if e.line]
    fill_rect = _rect_of(fill_edges) if fill_edges else None
    line_rect = _rect_of(line_edges) if line_edges else None
    base = {
        "fill_rect": fill_rect,
        "line_rect": line_rect,
        "fill": fill,
        "line": line,
        "n_fills": len(fill_keys),
        "n_lines": len(line_keys),
        "n_edges": len(shape.edges),
        "n_curves": n_curves,
    }
    if not fill_keys and len(line_keys) == 1 and line_rect:
        return Verdict("outline", "no fill, one line around a rectangle", **base)
    if not fill_keys and line_keys:
        return Verdict(
            "lines", f"{len(line_keys)} line styles, not one rectangle", **base
        )
    if len(fill_keys) > 1:
        kinds = sorted({shape.fill_of(k).kind for k in fill_keys})
        return Verdict(
            "multi", f"{len(fill_keys)} fill styles: {'+'.join(kinds)}", **base
        )
    if fill is None:
        return Verdict("none", "no fill and no line", **base)
    if fill.kind == "bitmap":
        return Verdict("bitmap", "bitmap fill", **base)
    if fill_rect is None:
        return Verdict(
            "nonrect-" + ("solid" if fill.kind == "solid" else "gradient"),
            f"{len(shape.edges)} edges, {n_curves} curves, not one rectangle",
            **base,
        )
    if fill.kind != "solid":
        return Verdict("gradient-rect", fill.kind, **base)
    if line_keys and (len(line_keys) > 1 or not line_rect):
        return Verdict("rect-odd-line", f"{len(line_keys)} line styles", **base)
    return Verdict("flat-rect", "one solid fill on a rectangle", **base)


_CACHE: dict[Path, object] = {}


def load(path: Path = WEB_SWF):
    if path not in _CACHE:
        _CACHE[path] = read_swf(path)
    return _CACHE[path]


if __name__ == "__main__":
    idx = load()
    for arg in sys.argv[1:]:
        s = parse(idx, int(arg))
        v = classify(s)
        print(
            arg,
            v.category,
            v.detail,
            "bounds",
            s.bounds,
            "fill_rect",
            v.fill_rect,
            "line_rect",
            v.line_rect,
            "|",
            [shape_fill.text() for fs in s.fills for shape_fill in fs],
            [ln.text() for ls in s.lines for ln in ls],
        )
