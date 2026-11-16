# The compare tool (spec/107-ui-foundation.md, Part 5): scores a capture of a
# Screen or Window in the port against ffdec's render of the same SWF frame,
# with text hidden, so the score measures layout and art.
#
# It runs by hand and never in `just gut`, because it needs the gitignored SWF
# and a capture from a drawing window. docs/agents/art-extraction.md (Screen
# compare tool) gives the steps.
#
# dev/screen_compare/screens.json is the per-Screen config. Each Screen or
# Window build issue adds one entry: the scene, and one or both modes with a
# bar each.
#   "chrome" - the whole frame with every edit text stripped, against the scene
#              with every Label hidden.
#   "panels" - only the scene nodes in `nodes`, against only the frame depths
#              that place them.
# dev/screen_compare/capture.gd reads the same file and draws the scene for a
# capture. The scene's timeline, its frame label and the depth of each node
# come from SCENES in screen_rects.py, where the rect test already needs them,
# so the config types no SWF number.
#
# The method, generalized from the victory prototype's compare.py on the
# branch prototype/victory-containers:
#   - Each mode needs two captures of the same scene, one over magenta and one
#     over green. A pixel the scene covers completely is the same in both, so
#     the mask is every pixel that matches, shrunk by one pixel so that no
#     resampled edge counts.
#   - The faces of the scene in test/fixtures/screen_rects.json are left out
#     of the mask, because the game sets each face from its data and ffdec
#     runs no ActionScript, so the reference cannot hold the same face.
#   - The reference is rendered at zoom 2 on a Stage canvas and shrunk to the
#     Stage size with Lanczos, the way godot-mcp shrinks the 2x window to its
#     capture. Only pixels where the shrunk reference is opaque are scored.
#   - A pixel's difference is the largest of its three channel differences,
#     and the score is the 99th percentile, as verify_battle_screen.py reads.
#   - The must-fail control scores the same capture against the reference
#     moved 20 px to the right. A mode passes when its score is at or under
#     its bar and the control is over the bar.
#
# Run: just compare-screen <entry> [--mode chrome|panels] [--shots <folder>]
#      just compare-screen --list
from __future__ import annotations

import argparse
import json
import math
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.extract import screen_rects
from urchin_dev.swf.swf_index import SwfIndex, character_kind, read_swf

CONFIG = REPO_ROOT / "dev" / "screen_compare" / "screens.json"
CAPTURE_SCENE = "res://dev/screen_compare/capture.tscn"
SHOTS = REPO_ROOT / "tasks" / "screen_compare"
STAGE = (800, 575)
ZOOM = 2
MODES = ("chrome", "panels")
BACKGROUNDS = ("magenta", "green")
# Two captures of one opaque pixel can differ by this much on a channel.
SAME = 2
CONTROL_SHIFT = 20
DIFF_GAIN = 4


class CompareError(ValueError):
    pass


@dataclass(frozen=True)
class Mode:
    # The score has to be at or under the bar. None until the entry's first
    # passing run sets it.
    bar: float | None
    depths: tuple[int, ...] = ()
    nodes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Entry:
    scene: str
    timeline: int
    frame: str
    modes: dict[str, Mode]


@dataclass(frozen=True)
class Score:
    pixels: int
    p50: float
    p90: float
    p99: float


def panel_depths(
    scene: screen_rects.Scene, nodes: Iterable[str], where: str
) -> tuple[int, ...]:
    """-> the frame depth that places each of `nodes`, from the scene's pieces."""
    depths = []
    for node in nodes:
        piece = scene.pieces.get(node)
        if piece is None or piece.depth is None or piece.inner_depth is not None:
            raise CompareError(
                f"{where}: {node} is not a piece that SCENES of screen_rects.py"
                " places by a depth of the frame"
            )
        depths.append(piece.depth)
    return tuple(depths)


def load_config(
    path: Path, scenes: dict[str, screen_rects.Scene] = screen_rects.SCENES
) -> dict[str, Entry]:
    entries = {}
    for name, raw in json.loads(path.read_text()).items():
        absent = sorted({"scene", "modes"} - raw.keys())
        if absent:
            raise CompareError(f"{name}: no {' and no '.join(absent)}")
        if raw["scene"] not in scenes:
            raise CompareError(
                f"{name}: {raw['scene']} is not in SCENES of screen_rects.py, which"
                " holds its timeline and its frame"
            )
        scene = scenes[raw["scene"]]
        modes = {}
        for mode, fields in raw["modes"].items():
            where = f"{name}, mode {mode}"
            if mode not in MODES:
                raise CompareError(f"{where}: unknown mode, expected one of {MODES}")
            unknown = sorted(fields.keys() - {"bar", "nodes"})
            if unknown:
                raise CompareError(f"{where}: unknown fields {unknown}")
            if "bar" not in fields:
                raise CompareError(f"{where}: no bar. Write null until the first run")
            bar = fields["bar"]
            if bar is not None and (
                isinstance(bar, bool) or not isinstance(bar, (int, float))
            ):
                raise CompareError(f"{where}: the bar {bar!r} is not a number or null")
            nodes = tuple(fields.get("nodes", ()))
            if mode == "panels" and not nodes:
                raise CompareError(f"{where}: panels needs its nodes")
            if mode == "chrome" and nodes:
                raise CompareError(f"{where}: chrome takes no nodes")
            modes[mode] = Mode(bar, panel_depths(scene, nodes, where), nodes)
        if not modes:
            raise CompareError(f"{name}: no modes")
        entries[name] = Entry(raw["scene"], scene.timeline, scene.frame, modes)
    return entries


def capture_args(entry: str, mode: str, background: str) -> list[str]:
    """-> the arguments capture.gd takes for one capture."""
    return [f"--entry={entry}", f"--mode={mode}", f"--background={background}"]


def capture_path(shots: Path, entry: str, mode: str, background: str) -> Path:
    return shots / entry / f"{mode}_{background}.png"


def drawn_mask(over_magenta: np.ndarray, over_green: np.ndarray) -> np.ndarray:
    """-> the pixels the scene covers completely, shrunk by one pixel."""
    same = np.abs(over_magenta - over_green).max(axis=2) <= SAME
    shrunk = same.copy()
    shrunk[1:, :] &= same[:-1, :]
    shrunk[:-1, :] &= same[1:, :]
    shrunk[:, 1:] &= same[:, :-1]
    shrunk[:, :-1] &= same[:, 1:]
    shrunk[0, :] = shrunk[-1, :] = False
    shrunk[:, 0] = shrunk[:, -1] = False
    return shrunk


def box_mask(shape: tuple[int, int], rect: Iterable[float]) -> np.ndarray:
    """-> a mask of every pixel that `rect` (x, y, w, h in design px) touches."""
    x, y, w, h = rect
    mask = np.zeros(shape, dtype=bool)
    mask[
        max(math.floor(y), 0) : max(math.ceil(y + h), 0),
        max(math.floor(x), 0) : max(math.ceil(x + w), 0),
    ] = True
    return mask


def face_boxes(record: dict, scene: str) -> list[tuple[float, ...]]:
    """-> the rect of every face the rect record holds for `scene`."""
    pieces = record["scenes"].get(scene, {}).get("pieces", {})
    return [tuple(p["rect"]) for p in pieces.values() if p["kind"] == "face"]


def difference(shot: np.ndarray, reference: np.ndarray) -> np.ndarray:
    return np.abs(shot - reference[:, :, :3]).max(axis=2)


def scored(reference: np.ndarray, mask: np.ndarray) -> np.ndarray:
    return mask & (reference[:, :, 3] == 255)


def score(shot: np.ndarray, reference: np.ndarray, mask: np.ndarray) -> Score:
    """-> the score of an RGB capture against an RGBA reference inside `mask`."""
    use = scored(reference, mask)
    if not use.any():
        raise CompareError("no pixels to score: the mask and the reference are apart")
    values = difference(shot, reference)[use]
    p50, p90, p99 = (float(np.percentile(values, p)) for p in (50, 90, 99))
    return Score(int(use.sum()), p50, p90, p99)


def shifted(reference: np.ndarray) -> np.ndarray:
    """-> the reference moved CONTROL_SHIFT px to the right, for the control."""
    return np.roll(reference, CONTROL_SHIFT, axis=1)


def verdict(p99: float, control_p99: float, bar: float | None) -> str | None:
    """-> why the mode fails, or None when it passes."""
    if bar is None:
        return f"no bar yet. Set it from this run: p99 {p99:.0f}"
    if p99 > bar:
        return f"p99 {p99:.0f} is over the bar {bar:g}"
    if control_p99 <= bar:
        return (
            f"the control scores p99 {control_p99:.0f}, not over the bar {bar:g},"
            " so the check cannot fail"
        )
    return None


def edit_text_ids(
    owner: int,
    frame: int,
    frames_of: Callable[[int], list[dict[int, int]]],
    kind_of: Callable[[int], str],
) -> set[int]:
    """-> every edit text that `frame` of `owner` places, counted from 1, and
    every one inside the sprites it places, on any of their frames. frames_of
    gives a timeline's frames as {depth: character id}."""
    found: set[int] = set()
    seen: set[int] = set()
    pending = list(frames_of(owner)[frame - 1].values())
    while pending:
        cid = pending.pop()
        if cid in seen:
            continue
        seen.add(cid)
        kind = kind_of(cid)
        if kind == "edittext":
            found.add(cid)
        elif kind == "sprite":
            for layers in frames_of(cid):
                pending.extend(layers.values())
    return found


def reference_job(index: SwfIndex, entry: Entry, mode: str) -> render.Job:
    origin = screen_rects.origin_of(index, entry.timeline)
    frame = timeline.frame_of(index, entry.timeline, entry.frame)
    if mode == "panels":
        return render.Job(
            entry.timeline, frame, ZOOM, origin, only_depths=entry.modes[mode].depths
        )

    def characters(owner: int) -> list[dict[int, int]]:
        return [
            {depth: layer.character_id for depth, layer in layers.items()}
            for layers in timeline.frames(index, owner)
        ]

    texts = edit_text_ids(
        entry.timeline, frame, characters, lambda cid: character_kind(index, cid)
    )
    reasons = dict.fromkeys(texts, "an edit text, hidden in chrome mode")
    stripped = strip.strip_list(WEB_SWF, reasons) if reasons else []
    return render.Job(entry.timeline, frame, ZOOM, origin, strip=tuple(stripped))


def render_reference(index: SwfIndex, entry: Entry, mode: str) -> Image.Image:
    """-> ffdec's render of the entry's frame on a Stage canvas, at 1x."""
    with render.frames(WEB_SWF, [reference_job(index, entry, mode)]) as (frame,):
        cut = render.trim(frame)
        if cut is None:
            raise CompareError(f"{entry.frame}, mode {mode}: ffdec drew nothing")
        canvas = Image.new("RGBA", (STAGE[0] * ZOOM, STAGE[1] * ZOOM), (0, 0, 0, 0))
        at = (round(cut.rect[0] * ZOOM), round(cut.rect[1] * ZOOM))
        canvas.alpha_composite(cut.image, at)
    return canvas.resize(STAGE, Image.Resampling.LANCZOS)


def load_capture(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.size != STAGE:
            raise CompareError(f"{path}: {image.size}, expected the Stage size {STAGE}")
        return np.asarray(image.convert("RGB"), dtype=np.int16)


def save_diff(path: Path, values: np.ndarray, use: np.ndarray) -> None:
    amplified = np.clip(values * DIFF_GAIN, 0, 255).astype(np.uint8)
    image = np.zeros((*values.shape, 3), dtype=np.uint8)
    image[..., 0] = np.where(use, amplified, 40)
    image[..., 1] = np.where(use, amplified, 0)
    image[..., 2] = np.where(use, amplified, 40)
    Image.fromarray(image).save(path)


def missing_captures(shots: Path, name: str, modes: Iterable[str]) -> list[str]:
    lines = []
    for mode in modes:
        for background in BACKGROUNDS:
            path = capture_path(shots, name, mode, background)
            if not path.is_file():
                args = json.dumps(capture_args(name, mode, background))
                lines.append(f"  {path}\n    run_scene args: {args}")
    return lines


def compare(index: SwfIndex, name: str, entry: Entry, mode: str, shots: Path) -> bool:
    """Score one mode, print its line and save its reference and its diff.
    -> whether it passes."""
    magenta, green = (
        load_capture(capture_path(shots, name, mode, b)) for b in BACKGROUNDS
    )
    mask = drawn_mask(magenta, green)
    record = json.loads(screen_rects.RECORD.read_text())
    for rect in face_boxes(record, entry.scene):
        mask &= ~box_mask(mask.shape, rect)
    image = render_reference(index, entry, mode)
    image.save(shots / name / f"{mode}_reference.png")
    reference = np.asarray(image, dtype=np.int16)
    found = score(magenta, reference, mask)
    control = score(magenta, shifted(reference), mask)
    save_diff(
        shots / name / f"{mode}_diff.png",
        difference(magenta, reference),
        scored(reference, mask),
    )
    problem = verdict(found.p99, control.p99, entry.modes[mode].bar)
    print(
        f"{name} {mode}: {found.pixels} pixels,"
        f" p50/p90/p99 {found.p50:.0f}/{found.p90:.0f}/{found.p99:.0f},"
        f" control shifted {CONTROL_SHIFT} px p99 {control.p99:.0f},"
        f" bar {entry.modes[mode].bar}: {'pass' if problem is None else 'FAIL'}"
    )
    if problem is not None:
        print(f"  {problem}")
    return problem is None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry", nargs="?")
    parser.add_argument("--mode", choices=MODES)
    parser.add_argument("--shots", type=Path, default=SHOTS)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    entries = load_config(CONFIG)
    if args.list:
        for name, entry in entries.items():
            print(f"{name}: {entry.scene}, modes {', '.join(entry.modes)}")
        return
    if args.entry not in entries:
        raise SystemExit(
            f"no entry {args.entry!r} in {CONFIG}. Entries: {list(entries)}"
        )
    entry = entries[args.entry]
    modes = [args.mode] if args.mode else list(entry.modes)
    if args.mode and args.mode not in entry.modes:
        raise SystemExit(f"{args.entry} has no mode {args.mode}")
    missing = missing_captures(args.shots, args.entry, modes)
    if missing:
        raise SystemExit(
            f"Missing captures. For each one, run {CAPTURE_SCENE} with the godot-mcp"
            " run_scene tool and these arguments, then capture_screenshot with this"
            " savePath:\n" + "\n".join(missing)
        )
    index = read_swf(WEB_SWF)
    results = [compare(index, args.entry, entry, mode, args.shots) for mode in modes]
    if not all(results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
