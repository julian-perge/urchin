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
#              with every Label hidden. The characters at the depths the scene
#              leaves out (`left_out` in SCENES) are stripped too.
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
#   - A piece with a `steam` placement in SCENES is drawn where the Steam
#     build, SONNY2.swf, places it, because the port puts it there and the
#     rect test checks it against that build. The frame is rendered as runs of
#     consecutive depths, each run moved by its pieces' offset or not moved,
#     and the runs are drawn over each other in depth order, so the pieces
#     between them keep their stacking.
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
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import REPO_ROOT, STEAM_SWF, WEB_SWF
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.extract import screen_rects, window_chrome
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
    left_out: tuple[int, ...] = ()
    compare_strip: tuple[int, ...] = ()
    # (web, steam) for each piece the port puts where the Steam build places
    # it: the depth or instance name of its placement in each build.
    steam: tuple[tuple[int | str, int | str], ...] = ()


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


def steam_pairs(scene: screen_rects.Scene, where: str) -> tuple:
    """-> (web, steam) for each piece of `scene` with a Steam placement, once
    for each pair."""
    pairs = []
    for node, piece in scene.pieces.items():
        if piece.steam is None:
            continue
        if piece.inner_depth is not None or piece.via:
            raise CompareError(
                f"{where}: {node} has a Steam placement inside a sprite, and only"
                " a depth of the frame can be moved"
            )
        pair = (piece.depth if piece.instance is None else piece.instance, piece.steam)
        if pair not in pairs:
            pairs.append(pair)
    return tuple(pairs)


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
            unknown = sorted(fields.keys() - {"bar", "nodes", "hide_names"})
            if unknown:
                raise CompareError(f"{where}: unknown fields {unknown}")
            if "bar" not in fields:
                raise CompareError(f"{where}: no bar. Write null until the first run")
            bar = fields["bar"]
            if bar is not None and (
                isinstance(bar, bool) or not isinstance(bar, (int, float))
            ):
                raise CompareError(f"{where}: the bar {bar!r} is not a number or null")
            hide = fields.get("hide_names", [])
            if not isinstance(hide, list) or not all(isinstance(n, str) for n in hide):
                raise CompareError(f"{where}: hide_names is a list of node names")
            if hide and mode != "chrome":
                raise CompareError(f"{where}: only chrome mode takes hide_names")
            nodes = tuple(fields.get("nodes", ()))
            if mode == "panels" and not nodes:
                raise CompareError(f"{where}: panels needs its nodes")
            if mode == "chrome" and nodes:
                raise CompareError(f"{where}: chrome takes no nodes")
            modes[mode] = Mode(bar, panel_depths(scene, nodes, where), nodes)
        if not modes:
            raise CompareError(f"{name}: no modes")
        entries[name] = Entry(
            raw["scene"],
            scene.timeline,
            scene.frame,
            modes,
            scene.left_out,
            scene.compare_strip,
            steam_pairs(scene, name),
        )
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


# The pieces whose art the game sets from its data, and ffdec runs no
# ActionScript, so the reference cannot hold the same art.
MASKED_KINDS = ("face", "doll")


def masked_boxes(record: dict, scene: str) -> list[tuple[float, ...]]:
    """-> the rect of every face and doll the rect record holds for `scene`."""
    pieces = record["scenes"].get(scene, {}).get("pieces", {})
    return [tuple(p["rect"]) for p in pieces.values() if p["kind"] in MASKED_KINDS]


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


def left_out_ids(layers: dict[int, int], depths: Iterable[int], where: str) -> set[int]:
    """-> the character at each of `depths` in `layers`, a frame as
    {depth: character id}."""
    found = set()
    for depth in depths:
        if depth not in layers:
            raise CompareError(f"{where}: the frame places nothing at depth {depth}")
        found.add(layers[depth])
    return found


def steam_offsets(
    layers: dict[int, timeline.Layer],
    steam_layers: dict[int, timeline.Layer],
    pairs: Iterable[tuple[int | str, int | str]],
    where: str,
) -> dict[int, tuple[float, float]]:
    """-> the web depth of each piece in `pairs` and how far, in design px,
    the Steam build moves it. layers and steam_layers are the same frame of
    the web and the Steam build."""
    offsets: dict[int, tuple[float, float]] = {}
    for web, steam in pairs:
        try:
            layer = screen_rects.placed_layer(layers, web, str(web), where)
            steam_layer = screen_rects.placed_layer(
                steam_layers, steam, str(steam), f"{where} of the Steam build"
            )
            offset = screen_rects.steam_offset(layer.matrix, steam_layer.matrix)
        except ValueError as error:
            raise CompareError(str(error)) from error
        depth = next(d for d, placed in layers.items() if placed is layer)
        if offsets.setdefault(depth, offset) != offset:
            raise CompareError(
                f"{where}: depth {depth} moves by {offsets[depth]} and by {offset}"
            )
    return offsets


def depth_runs(
    layers: dict[int, timeline.Layer], offsets: dict[int, tuple[float, float]]
) -> list[tuple[tuple[int, ...], tuple[float, float]]]:
    """-> the depths of `layers` in order, cut into runs of consecutive depths
    that move by the same offset, each with its offset. Raises when a clip
    mask and a depth it clips fall in two runs, since a render of one run
    draws no mask from another."""
    runs: list[tuple[list[int], tuple[float, float]]] = []
    for depth in sorted(layers):
        offset = offsets.get(depth, (0.0, 0.0))
        if runs and runs[-1][1] == offset:
            runs[-1][0].append(depth)
        else:
            runs.append(([depth], offset))
    run_of = {depth: n for n, (depths, _) in enumerate(runs) for depth in depths}
    for depth, layer in layers.items():
        if layer.clip_depth is None:
            continue
        clipped = [d for d in layers if depth < d <= layer.clip_depth]
        if any(run_of[d] != run_of[depth] for d in clipped):
            raise CompareError(
                f"the clip mask at depth {depth} clips depths that move apart from it"
            )
    return [(tuple(depths), offset) for depths, offset in runs]


def through_hub(index: SwfIndex, frame: int, **job) -> render.Job:
    """-> a job that renders KRINMENU on `frame` inside the Hub frame. The
    backdrop's Bevel, Glow and DropShadow belong to KRINMENU's Stage placement,
    so a render of KRINMENU's own timeline loses them."""
    return render.Job(
        0,
        window_chrome.hub_frame(index),
        ZOOM,
        only_depths=(window_chrome.KRINMENU_ROOT_DEPTH,),
        goto=((window_chrome.KRINMENU_ROOT_DEPTH, frame),),
        **job,
    )


def reference_job(index: SwfIndex, entry: Entry, mode: str) -> render.Job:
    origin = screen_rects.origin_of(index, entry.timeline)
    frame = timeline.frame_of(index, entry.timeline, entry.frame)
    if mode == "panels":
        depths = entry.modes[mode].depths
        if (
            entry.timeline == window_chrome.KRINMENU
            and window_chrome.BACKDROP_DEPTH in depths
        ):
            all_depths = {
                depth
                for layers in timeline.frames(index, entry.timeline)
                for depth in layers
            }
            return through_hub(
                index,
                frame,
                hide_depths=tuple(
                    (entry.timeline, depth)
                    for depth in sorted(all_depths - set(depths))
                ),
            )
        return render.Job(entry.timeline, frame, ZOOM, origin, only_depths=depths)

    def characters(owner: int) -> list[dict[int, int]]:
        return [
            {depth: layer.character_id for depth, layer in layers.items()}
            for layers in timeline.frames(index, owner)
        ]

    texts = edit_text_ids(
        entry.timeline, frame, characters, lambda cid: character_kind(index, cid)
    )
    reasons = dict.fromkeys(texts, "an edit text, hidden in chrome mode")
    layers = characters(entry.timeline)[frame - 1]
    for cid in left_out_ids(layers, entry.left_out, entry.frame):
        reasons[cid] = "a character the port leaves out"
    for cid in entry.compare_strip:
        reasons[cid] = "outside the static chrome comparison"
    stripped = tuple(strip.strip_list(WEB_SWF, reasons)) if reasons else ()
    if entry.timeline == window_chrome.KRINMENU:
        return through_hub(index, frame, strip=stripped)
    return render.Job(entry.timeline, frame, ZOOM, origin, strip=stripped)


def reference_jobs(
    index: SwfIndex, entry: Entry, mode: str, steam_index: SwfIndex | None
) -> list[tuple[render.Job, tuple[float, float]]]:
    """-> the jobs that render the entry's reference, each with how far, in
    design px, to move what it draws. An entry with no Steam piece is one job
    that is not moved."""
    job = reference_job(index, entry, mode)
    if not entry.steam:
        return [(job, (0.0, 0.0))]
    if entry.timeline == window_chrome.KRINMENU:
        raise CompareError(
            f"{entry.frame}: a KRINMENU reference renders through the Hub frame,"
            " and it cannot move a Steam piece"
        )
    frame = timeline.frame_of(index, entry.timeline, entry.frame)
    layers = timeline.frames(index, entry.timeline)[frame - 1]
    steam_frame = timeline.frame_of(steam_index, entry.timeline, entry.frame)
    steam_layers = timeline.frames(steam_index, entry.timeline)[steam_frame - 1]
    offsets = steam_offsets(layers, steam_layers, entry.steam, entry.frame)
    if job.only_depths:
        layers = {d: layer for d, layer in layers.items() if d in job.only_depths}
    return [
        (replace(job, only_depths=depths), offset)
        for depths, offset in depth_runs(layers, offsets)
    ]


def composite(
    cuts: Iterable[tuple[tuple[float, float], Image.Image, tuple[float, float]]],
    size: tuple[int, int],
    zoom: float,
) -> Image.Image:
    """-> each cut, given as (its x and y on the Stage, its image, its offset),
    drawn in order on a clear canvas of `size` pixels at `zoom`."""
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    for (x, y), image, (dx, dy) in cuts:
        canvas.alpha_composite(image, (round((x + dx) * zoom), round((y + dy) * zoom)))
    return canvas


def render_reference(
    index: SwfIndex, entry: Entry, mode: str, steam_index: SwfIndex | None = None
) -> Image.Image:
    """-> ffdec's render of the entry's frame on a Stage canvas, at 1x."""
    jobs = reference_jobs(index, entry, mode, steam_index)
    with render.frames(WEB_SWF, [job for job, _ in jobs]) as rendered:
        cuts = []
        for frame, (_job, offset) in zip(rendered, jobs, strict=True):
            cut = render.trim(frame)
            if cut is not None:
                cuts.append((cut.rect[:2], cut.image, offset))
        if not cuts:
            raise CompareError(f"{entry.frame}, mode {mode}: ffdec drew nothing")
        canvas = composite(cuts, (STAGE[0] * ZOOM, STAGE[1] * ZOOM), ZOOM)
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


def compare(
    index: SwfIndex,
    name: str,
    entry: Entry,
    mode: str,
    shots: Path,
    steam_index: SwfIndex | None = None,
) -> bool:
    """Score one mode, print its line and save its reference and its diff.
    -> whether it passes."""
    magenta, green = (
        load_capture(capture_path(shots, name, mode, b)) for b in BACKGROUNDS
    )
    mask = drawn_mask(magenta, green)
    record = json.loads(screen_rects.RECORD.read_text())
    for rect in masked_boxes(record, entry.scene):
        mask &= ~box_mask(mask.shape, rect)
    image = render_reference(index, entry, mode, steam_index)
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
    steam_index = read_swf(STEAM_SWF) if entry.steam else None
    results = [
        compare(index, args.entry, entry, mode, args.shots, steam_index)
        for mode in modes
    ]
    if not all(results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
