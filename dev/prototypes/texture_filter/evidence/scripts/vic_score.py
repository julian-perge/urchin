#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Scores the victory prototype's captures on today's main against the ffdec win frame, under NEAREST and LINEAR.

Captures are plain sRGB now, so nothing here converts from linear. --old-loader shows what compare.py's unchanged
load_rgb would report on the same files."""
import importlib.util
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter"
P = T / "proto/dev/prototypes/victory_containers"
spec = importlib.util.spec_from_file_location("compare", P / "compare.py")
compare = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(compare)
layout = json.loads((P / "win_layout.json").read_text())
art = json.loads((P / "art.json").read_text())
REF_DIRS = {"committed": P / "images/ref", "today": T / "ref_today/images/ref"}
REGIONS = ("left", "centre", "right", "bar")
FRAME = 30


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def path_of(filter_name, tag, name):
    return T / "vic" / f"{filter_name}_{tag}" / f"{name}_f{FRAME:04d}.png"


def drawn_mask(filter_name, tag, variant):
    a = load(path_of(filter_name, tag, f"{variant}_ref"))
    b = load(path_of(filter_name, tag, f"{variant}_sentinel"))
    same = np.abs(a - b).max(axis=2) <= 2
    shrunk = same.copy()
    shrunk[1:, :] &= same[:-1, :]
    shrunk[:-1, :] &= same[1:, :]
    shrunk[:, 1:] &= same[:, :-1]
    shrunk[:, :-1] &= same[:, 1:]
    return shrunk


def face_mask(shape, scale):
    mask = np.ones(shape, dtype=bool)
    for x, y, w, h in compare.face_rects(layout, art):
        mask &= ~compare.box_mask(shape, (x * scale, y * scale, w * scale, h * scale), inward=False)
    return mask


def score(shot, reference, mask):
    ref = np.asarray(reference.convert("RGBA"), dtype=np.int16)
    use = mask & (ref[:, :, 3] == 255)
    d = np.abs(shot - ref[:, :, :3]).max(axis=2)
    v = d[use]
    return int(use.sum()), [float(np.percentile(v, q)) for q in (50, 90, 99)], float(v.mean()), d, use


REF_FOR = {"ref": "full", "chrome": "chrome", "panels": "panels", "live": "full"}


def table(ref_set):
    print(f"\n== against {ref_set} ffdec refs; p50/p90/p99 mean of the largest channel difference")
    print(f"{'capture':28} {'window':4} {'pixels':>8} {'NEAREST':>22} {'LINEAR':>22}")
    for variant in ("B", "C"):
        for tag, scale in (("2x", 2), ("1x", 1)):
            refs = {m: Image.open(REF_DIRS[ref_set] / f"win_{m}_{tag}.png") for m in set(REF_FOR.values())}
            shape = (refs["full"].height, refs["full"].width)
            faces = face_mask(shape, scale)
            common = drawn_mask("nearest", tag, variant) & drawn_mask("linear", tag, variant) & faces
            for mode in ("ref", "chrome", "panels", "live"):
                out = []
                for filter_name in ("nearest", "linear"):
                    n, q, mean, _d, _u = score(load(path_of(filter_name, tag, f"{variant}_{mode}")), refs[REF_FOR[mode]], common)
                    out.append(f"{q[0]:3.0f}/{q[1]:3.0f}/{q[2]:3.0f} {mean:6.2f}")
                print(f"{variant}_{mode:26} {tag:4} {n:8d} {out[0]:>22} {out[1]:>22}")


table("committed")
table("today")

print("\n== reproducing the prototype's published numbers: 2x NEAREST framebuffer, Lanczos to 800x600, against the 1x refs")
for name, mode in (("C_chrome", "chrome"), ("C_ref", "ref"), ("C_panels", "panels"), ("B_chrome", "chrome")):
    img = Image.open(path_of("nearest", "2x", name)).convert("RGB").resize((800, 600), Image.Resampling.LANCZOS)
    shot = np.asarray(img, dtype=np.int16)
    ref = Image.open(REF_DIRS["committed"] / f"win_{REF_FOR[mode]}_1x.png")
    mask = compare.drawn_mask  # unused
    a = Image.open(path_of("nearest", "2x", name[0] + "_ref")).convert("RGB").resize((800, 600), Image.Resampling.LANCZOS)
    b = Image.open(path_of("nearest", "2x", name[0] + "_sentinel")).convert("RGB").resize((800, 600), Image.Resampling.LANCZOS)
    same = np.abs(np.asarray(a, dtype=np.int16) - np.asarray(b, dtype=np.int16)).max(axis=2) <= 2
    shrunk = same.copy()
    shrunk[1:, :] &= same[:-1, :]; shrunk[:-1, :] &= same[1:, :]; shrunk[:, 1:] &= same[:, :-1]; shrunk[:, :-1] &= same[:, 1:]
    n, q, mean, _d, _u = score(shot, ref, shrunk & face_mask((600, 800), 1))
    print(f"  {name}: {q[0]:.0f} / {q[1]:.0f} / {q[2]:.0f}  ({n} px)")

print("\n== the old loader on a new capture (linear_to_srgb applied to values already in sRGB)")
shot = load(path_of("nearest", "2x", "C_chrome"))
ref = Image.open(REF_DIRS["committed"] / "win_chrome_2x.png")
mask = drawn_mask("nearest", "2x", "C") & face_mask((1200, 1600), 2)
n, q, mean, _d, _u = score(shot, ref, mask)
print(f"  sRGB-correct: {q[0]:.0f} / {q[1]:.0f} / {q[2]:.0f} mean {mean:.2f}")
n, q, mean, _d, _u = score(compare.linear_to_srgb(shot), ref, mask)
print(f"  old load_rgb: {q[0]:.0f} / {q[1]:.0f} / {q[2]:.0f} mean {mean:.2f}")

print("\n== the check can fail: C_chrome at 2x moved 1 window px right and 1 down")
shot2 = np.roll(np.roll(load(path_of("nearest", "2x", "C_chrome")), 1, axis=1), 1, axis=0)
n, q, mean, _d, _u = score(shot2, ref, mask)
print(f"  shifted: {q[0]:.0f} / {q[1]:.0f} / {q[2]:.0f} mean {mean:.2f}")
