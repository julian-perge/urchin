# PROTOTYPE for julian-perge/urchin#108, throwaway.
#
# Scores each variant's in-game screenshot against ffdec's render of
# KRINMENU's win frame, the way verify_battle_screen.py scores the battle
# screen: the per-pixel difference is the largest of the three channel
# differences, counted only where the screen draws and the reference is
# opaque, and read at p50, p90 and p99.
#
# Where the screen draws comes from two captures of the same variant and
# mode: one over the battle hall and one with the hall hidden and the clear
# colour magenta (--sentinel). A pixel the screen covers fully is the same in
# both, so the mask is every pixel that matches, shrunk by one pixel so no
# resampled edge counts.
#
# The rows' faces are left out of every mask. ffdec draws the face sheet
# inside a row as an empty frame on the win frame, while the same row clip
# rendered on its own shows the face (images/art/diag_row_alone.png), so the
# reference is wrong there, not the screen.
#
# Each mode has its own reference: ref and live against the whole frame,
# chrome against the frame with every edit text stripped, panels against the
# backdrop and the four panels alone. ref, chrome and panels show what ffdec
# draws, so they measure layout. live shows real data the reference can't
# have, so its score carries that difference too.
#
# Run from the repo root, after the captures listed in README.md:
#   uv run python dev/prototypes/victory_containers/compare.py
#   --prove-fail scores the capture with the left panel moved 20 px against
#   the same variant unmoved, which has to come out worse.
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).parent
SHOTS = HERE / "images" / "shots"
DIFFS = HERE / "images" / "diff"
REFS = HERE / "images" / "ref"
REFERENCE_FOR = {"live": "full", "ref": "full", "chrome": "chrome", "panels": "panels"}
VARIANTS = ("A", "B", "C")
MODES = ("ref", "chrome", "panels", "live")
REGIONS = ("left", "centre", "right", "bar")
GAIN = 4


def linear_to_srgb(values: np.ndarray) -> np.ndarray:
    v = values / 255.0
    srgb = np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(v, 1 / 2.4) - 0.055)
    return np.rint(srgb * 255).astype(np.int16)


def srgb_to_linear(values: np.ndarray) -> np.ndarray:
    v = values / 255.0
    linear = np.where(v <= 0.04045, v / 12.92, np.power((v + 0.055) / 1.055, 2.4))
    return np.rint(linear * 255).astype(np.int16)


def load_rgb(path: Path) -> np.ndarray:
    """-> a screenshot in sRGB. urchin sets rendering/viewport/hdr_2d, so the
    root viewport's texture holds linear values, and the godot-mcp harness
    writes them to the PNG as they are: the #373737 panels come back as 9.
    Converting the 8-bit linear values back loses precision in the darks,
    which no_signal_floor() below measures."""
    return linear_to_srgb(np.asarray(Image.open(path).convert("RGB"), dtype=np.int16))


def face_rects(layout: dict, art: dict) -> list[tuple[float, float, float, float]]:
    face = layout["row_pieces"]["face"]
    a = art["face_Veradux"]["rect"]
    rects = []
    for row in layout["rows"].values():
        x = row["rect"][0] + face["offset"][0] + a[0] * face["scale"]
        y = row["rect"][1] + face["offset"][1] + a[1] * face["scale"]
        rects.append((x, y, a[2] * face["scale"], a[3] * face["scale"]))
    return rects


def drawn_mask(variant: str) -> np.ndarray:
    over_hall = load_rgb(SHOTS / f"{variant}_ref.png")
    over_magenta = load_rgb(SHOTS / f"{variant}_sentinel.png")
    same = np.abs(over_hall - over_magenta).max(axis=2) <= 2
    # Shrink by one pixel in every direction.
    shrunk = same.copy()
    shrunk[1:, :] &= same[:-1, :]
    shrunk[:-1, :] &= same[1:, :]
    shrunk[:, 1:] &= same[:, :-1]
    shrunk[:, :-1] &= same[:, 1:]
    return shrunk


def box_mask(shape, rect, inward: bool) -> np.ndarray:
    """-> a mask of `rect` (x, y, w, h in design px, which are screenshot
    px). inward rounds to the pixels the rect fully covers, otherwise to every
    pixel it touches."""
    x, y, w, h = rect
    if inward:
        x0, y0, x1, y1 = (
            int(np.ceil(x)),
            int(np.ceil(y)),
            int(np.floor(x + w)),
            int(np.floor(y + h)),
        )
    else:
        x0, y0, x1, y1 = (
            int(np.floor(x)),
            int(np.floor(y)),
            int(np.ceil(x + w)),
            int(np.ceil(y + h)),
        )
    mask = np.zeros(shape, dtype=bool)
    mask[max(y0, 0) : max(y1, 0), max(x0, 0) : max(x1, 0)] = True
    return mask


def score(shot: np.ndarray, reference: Image.Image, mask: np.ndarray):
    ref_rgba = np.asarray(reference.convert("RGBA"), dtype=np.int16)
    opaque = ref_rgba[:, :, 3] == 255
    use = mask & opaque
    difference = np.abs(shot - ref_rgba[:, :, :3]).max(axis=2)
    values = difference[use]
    stats = {
        "pixels": int(use.sum()),
        "p50": float(np.percentile(values, 50)),
        "p90": float(np.percentile(values, 90)),
        "p99": float(np.percentile(values, 99)),
        "mean": float(values.mean()),
    }
    return stats, difference, use


def save_diff(path: Path, difference: np.ndarray, use: np.ndarray) -> None:
    image = np.zeros(difference.shape + (3,), dtype=np.uint8)
    amplified = np.clip(difference * GAIN, 0, 255).astype(np.uint8)
    image[..., 0] = np.where(use, amplified, 40)
    image[..., 1] = np.where(use, amplified, 0)
    image[..., 2] = np.where(use, amplified, 40)
    Image.fromarray(image).save(path)


def first_bright_row(column: np.ndarray, start: int, threshold: int) -> int:
    for i, value in enumerate(column[start:]):
        if value >= threshold:
            return start + i
    return -1


def framebuffer_edges(layout: dict) -> None:
    """Prints where each experience row's outline and the first inventory
    slot start in the 2x framebuffers (--dump) against ffdec's 2x render, in
    window pixels. The screenshots are shrunk to 800x600, so a half design
    pixel only shows here."""
    fb_dir = HERE / "images" / "framebuffer"
    reference = np.asarray(
        Image.open(REFS / "win_chrome_2x.png").convert("RGB"), dtype=np.int16
    )[:, :, 0]
    images = {"ffdec": reference}
    for name in ("B_chrome", "C_chrome", "C_chrome_nosnap"):
        path = fb_dir / f"{name}_2x.png"
        if path.exists():
            images[name] = load_rgb(path)[:, :, 0]
    if len(images) == 1:
        return
    print("\nwindow-pixel rows in the 2x framebuffers (design px = row / 2):")
    # The outline is #666666 over the #373737 panel, so the first row
    # brighter than 80 is its top. The slot's top edge is the first row
    # darker than 30 under the #373737 panel.
    for role in ("player", "friend1", "friend2"):
        top = layout["rows"][role]["rect"][1]
        start = int(top * 2) - 6
        found = {
            name: first_bright_row(img[:, 300], start, 80)
            for name, img in images.items()
        }
        print(
            f"  row {role:<8} swf top {top:7.2f} (window {top * 2:7.1f}): "
            + ", ".join(f"{k} {v}" for k, v in found.items())
        )
    slot_top = layout["item_grid"]["rect"][1]
    start = int(slot_top * 2) - 6
    found = {}
    for name, img in images.items():
        column = img[:, 1066]
        found[name] = next(
            (start + i for i, v in enumerate(column[start:]) if v < 30), -1
        )
    print(
        f"  item slot 0 swf top {slot_top:7.2f} (window {slot_top * 2:7.1f}): "
        + ", ".join(f"{k} {v}" for k, v in found.items())
    )


def main():
    layout = json.loads((HERE / "win_layout.json").read_text())
    art = json.loads((HERE / "art.json").read_text())
    DIFFS.mkdir(parents=True, exist_ok=True)
    references = {
        name: Image.open(REFS / f"win_{name}_1x.png")
        for name in set(REFERENCE_FOR.values())
    }
    shape = (references["full"].height, references["full"].width)
    no_faces = np.ones(shape, dtype=bool)
    for rect in face_rects(layout, art):
        no_faces &= ~box_mask(shape, rect, inward=False)
    regions = {
        name: box_mask(shape, layout["panels"][name]["rect"], inward=True)
        for name in REGIONS
    }

    results = {}
    masks = {}
    for variant in VARIANTS:
        masks[variant] = drawn_mask(variant) & no_faces
        for mode in MODES:
            path = SHOTS / f"{variant}_{mode}.png"
            if not path.exists():
                continue
            shot = load_rgb(path)
            stats, difference, use = score(
                shot, references[REFERENCE_FOR[mode]], masks[variant]
            )
            stats["regions"] = {}
            for name, region in regions.items():
                values = difference[use & region]
                stats["regions"][name] = {
                    "p50": float(np.percentile(values, 50)),
                    "p90": float(np.percentile(values, 90)),
                    "p99": float(np.percentile(values, 99)),
                }
            save_diff(DIFFS / f"{variant}_{mode}_diff.png", difference, use)
            results[f"{variant}_{mode}"] = stats

    extras = sorted(p.stem for p in SHOTS.glob("*_*_*.png"))
    for stem in extras:
        variant, mode = stem.split("_")[:2]
        if variant not in VARIANTS or mode not in MODES:
            continue
        shot = load_rgb(SHOTS / f"{stem}.png")
        stats, difference, use = score(
            shot, references[REFERENCE_FOR[mode]], masks[variant]
        )
        stats["regions"] = {}
        for name, region in regions.items():
            values = difference[use & region]
            stats["regions"][name] = {
                "p50": float(np.percentile(values, 50)),
                "p90": float(np.percentile(values, 90)),
                "p99": float(np.percentile(values, 99)),
            }
        save_diff(DIFFS / f"{stem}_diff.png", difference, use)
        results[stem] = stats

    # The floor the 8-bit linear screenshots put under every score: each
    # reference sent through the same round trip and scored against itself,
    # inside variant C's mask.
    for name in ("full", "chrome", "panels"):
        ref_rgb = np.asarray(references[name].convert("RGB"), dtype=np.int16)
        round_trip = linear_to_srgb(srgb_to_linear(ref_rgb))
        stats, _difference, _use = score(round_trip, references[name], masks["C"])
        stats["regions"] = {r: {"p50": 0.0, "p90": 0.0, "p99": 0.0} for r in REGIONS}
        results[f"floor_{name}"] = stats

    print(
        f"{'capture':<34} {'pixels':>7} {'p50':>5} {'p90':>5} {'p99':>5} {'mean':>6}   "
        + "  ".join(f"{r:>15}" for r in REGIONS)
    )
    for name, stats in results.items():
        region_text = "  ".join(
            f"{stats['regions'][r]['p50']:>3.0f}/{stats['regions'][r]['p90']:>3.0f}/{stats['regions'][r]['p99']:>3.0f}    "
            for r in REGIONS
        )
        print(
            f"{name:<34} {stats['pixels']:>7} {stats['p50']:>5.0f} {stats['p90']:>5.0f}"
            f" {stats['p99']:>5.0f} {stats['mean']:>6.2f}   {region_text}"
        )
    (HERE / "scores.json").write_text(json.dumps(results, indent=1) + "\n")

    view = HERE / "images" / "view"
    view.mkdir(parents=True, exist_ok=True)
    for path in sorted(SHOTS.glob("*.png")):
        Image.fromarray(load_rgb(path).astype(np.uint8)).save(view / path.name)

    framebuffer_edges(layout)

    if "--prove-fail" in sys.argv[1:]:
        base, moved = results.get("B_chrome"), results.get("B_chrome_shiftleft20")
        if base is None or moved is None:
            raise SystemExit(
                "--prove-fail needs B_chrome.png and B_chrome_shiftleft20.png"
            )
        print(
            f"B chrome p50/p90/p99 {base['p50']:.0f}/{base['p90']:.0f}/{base['p99']:.0f},"
            f" left panel moved 20 px {moved['p50']:.0f}/{moved['p90']:.0f}/{moved['p99']:.0f}"
        )
        if not (moved["p90"] > base["p90"] and moved["p99"] > base["p99"]):
            raise SystemExit(
                "moving a panel 20 px did not raise the score, so the check can't fail"
            )
        print("moving the left panel 20 px raises the score, so the check can fail")


if __name__ == "__main__":
    main()
