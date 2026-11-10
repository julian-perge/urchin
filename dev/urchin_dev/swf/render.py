# render.py
# Renders chosen frames of sprites or the root timeline through the ffdec_lib
# driver, one driver run per call, and says where each rendered pixel sits on
# the stage. Each extractor keeps its own ids, labels, zoom and crop rules,
# and only this shared mechanism lives here.
#
# frames() hands back every job's canvas with the two rects the driver
# reports: the rect the canvas was sized from, which is the timeline's
# displayRect grown by its filter margin, and that displayRect without the
# margin. crop(), trim() and trim_union() cut a canvas down and give the
# piece's rect on the stage in design px.
#
# The rect keeps the formula every extractor used before this module: the
# displayRect's centre plus the job's origin, minus half the canvas, plus the
# crop's offset. ffdec grows the canvas by the filter margin on both sides,
# so the canvas keeps the displayRect's centre. It also rounds the canvas up
# to whole pixels on the right and bottom only, so this formula sits half
# that rounding off the exact origin, which is julian-perge/urchin#72.
#
# Two checks guard every canvas: its size has to be the sized-from rect times
# the zoom, rounded up as ffdec rounds it, and it can't be smaller than the
# displayRect without the margin. A canvas that fails either doesn't match
# the rects the driver reported, so no rect computed from them can be trusted.
#
# ffdec runs no ActionScript, so it draws every frame of a clip, frames past a
# stop() included. It also draws a nested clip on its age modulo its frame
# count, which brings a nested clip that ran stop() round to its frame 1 again.
# BOOM_SPARK (DefineSprite 1712) drew its spark a second time on frames 21 to
# 24 that way, where the game holds sprite 884 inside it on its empty frame
# 20. played_frames() gives the frames to render of a clip the game plays
# once, and ends them before any frame ffdec draws that way.
from __future__ import annotations

import math
import tempfile
from collections.abc import Iterable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from urchin_dev.swf import ffdec_lib, timeline
from urchin_dev.swf.swf_index import (
    ACTION_DEFINE_FUNCTION,
    ACTION_DEFINE_FUNCTION2,
    ACTION_GOTO_FRAME2,
    ACTION_IF,
    ACTION_JUMP,
    ACTION_NEXT_FRAME,
    ACTION_PLAY,
    ACTION_PREVIOUS_FRAME,
    ACTION_SET_TARGET,
    ACTION_SET_TARGET2,
    ACTION_STOP,
    ACTION_WITH,
    Placement,
    SwfIndex,
)

TWIPS = 20
IDENTITY_LINEAR = (1.0, 0.0, 0.0, 1.0)

# The actions that move or start a playhead: nextFrame(), prevFrame(), play(),
# and a gotoAndPlay() or gotoAndStop() to a frame the script computes. A goto
# to a fixed frame or label is in a CodeBlock's goto_frames or goto_labels
# instead.
MOVING_ACTIONS = frozenset(
    {ACTION_NEXT_FRAME, ACTION_PREVIOUS_FRAME, ACTION_PLAY, ACTION_GOTO_FRAME2}
)
# The actions that leave a stop() in the same script in doubt: a branch or a
# jump that may skip it, a function that holds it, and a with or tellTarget
# block that may point it at another clip.
DOUBTFUL_STOP_ACTIONS = frozenset(
    {
        ACTION_IF,
        ACTION_JUMP,
        ACTION_DEFINE_FUNCTION,
        ACTION_DEFINE_FUNCTION2,
        ACTION_WITH,
        ACTION_SET_TARGET,
        ACTION_SET_TARGET2,
    }
)
# The playhead methods a script can call on a clip by name, as _parent.stop()
# does.
PLAYHEAD_METHODS = frozenset(
    {"stop", "play", "gotoAndPlay", "gotoAndStop", "nextFrame", "prevFrame"}
)


@dataclass(frozen=True)
class Job:
    """One frame to render. timeline is 0 for the root or a DefineSprite id,
    frame is 1-based, and origin is where that timeline's own (0, 0) sits on
    the stage in design px. strip holds ids for the driver to delete first,
    as strip.strip_list() returns them. only_depths, when set, hides every
    other depth of the rendered frame, and each (depth, frame) in goto shows
    the sprite at that depth on its own 1-based frame, the way a gotoAndStop
    would."""

    timeline: int
    frame: int
    zoom: float
    origin: tuple[float, float] = (0.0, 0.0)
    strip: tuple[int, ...] = ()
    background: bool = False
    only_depths: tuple[int, ...] = ()
    goto: tuple[tuple[int, int], ...] = ()


@dataclass(frozen=True)
class Frame:
    """One rendered canvas. canvas_rect and display_rect are (xmin, ymin,
    xmax, ymax) in twips, the first with the filter margin and the second
    without. path stays valid until frames() exits."""

    job: Job
    path: Path
    size: tuple[int, int]
    canvas_rect: tuple[int, int, int, int]
    display_rect: tuple[int, int, int, int]

    def image(self) -> Image.Image:
        with Image.open(self.path) as image:
            return image.convert("RGBA")


@dataclass(frozen=True)
class Trimmed:
    """A piece of a canvas: the image, the canvas-pixel box it was cut from,
    and its (x, y, w, h) on the stage in design px."""

    image: Image.Image
    bbox: tuple[int, int, int, int]
    rect: tuple[float, float, float, float]


class RenderError(ValueError):
    pass


@contextmanager
def frames(swf: Path, jobs: list[Job]) -> Iterator[list[Frame]]:
    """Render every job from `swf` in one driver run and yield the frames in
    the order of `jobs`. Their PNGs are deleted when the block exits."""
    with tempfile.TemporaryDirectory(prefix="render_") as tmp:
        requests = [_request(job, Path(tmp) / f"{n}.png") for n, job in enumerate(jobs)]
        results = ffdec_lib.render(swf, requests) if jobs else []
        rendered = []
        for job, result in zip(jobs, results, strict=True):
            frame = Frame(
                job=job,
                path=Path(result["out"]),
                size=(result["width"], result["height"]),
                canvas_rect=(
                    result["xmin"],
                    result["ymin"],
                    result["xmax"],
                    result["ymax"],
                ),
                display_rect=tuple(result["display"]),
            )
            check_canvas(frame)
            rendered.append(frame)
        yield rendered


def _request(job: Job, out: Path) -> dict:
    """-> the driver's job for `job`. Render.java reads any only_depths list
    as the depths to keep, an empty one included, so the key is left out
    unless the job keeps some."""
    request = {
        "timeline": job.timeline,
        "frame": job.frame,
        "zoom": job.zoom,
        "out": str(out),
        "background": "swf" if job.background else "none",
        "strip_characters": list(job.strip),
    }
    if job.only_depths:
        request["only_depths"] = list(job.only_depths)
    if job.goto:
        request["goto"] = [{"depth": d, "frame": f} for d, f in job.goto]
    return request


def check_canvas(frame: Frame) -> None:
    """Raise RenderError when the canvas isn't the size ffdec gives the rect
    it was sized from, or is smaller than the displayRect without the filter
    margin."""
    where = f"timeline {frame.job.timeline} frame {frame.job.frame}"
    x0, y0, x1, y1 = frame.canvas_rect
    zoom = frame.job.zoom
    if x1 - x0 == 0 or y1 - y0 == 0:
        expected = (1, 1)
    else:
        expected = (
            math.ceil((x1 - x0) * zoom / TWIPS),
            math.ceil((y1 - y0) * zoom / TWIPS),
        )
    if frame.size != expected:
        raise RenderError(
            f"{where}: canvas {frame.size[0]}x{frame.size[1]} isn't its rect"
            f" {frame.canvas_rect} at zoom {zoom}, which would be"
            f" {expected[0]}x{expected[1]}"
        )
    dx0, dy0, dx1, dy1 = frame.display_rect
    if (
        frame.size[0] / zoom < (dx1 - dx0) / TWIPS
        or frame.size[1] / zoom < (dy1 - dy0) / TWIPS
    ):
        raise RenderError(
            f"{where}: canvas {frame.size[0] / zoom:.2f}x{frame.size[1] / zoom:.2f}"
            f" design px is smaller than its displayRect"
            f" {(dx1 - dx0) / TWIPS:.2f}x{(dy1 - dy0) / TWIPS:.2f}"
        )


def crop(frame: Frame, bbox: tuple[int, int, int, int]) -> Trimmed:
    """Cut `bbox` (canvas pixels, left, top, right, bottom) out of the frame
    and work out where it sits on the stage."""
    return _crop(frame, frame.image(), bbox)


def _crop(frame: Frame, canvas: Image.Image, bbox) -> Trimmed:
    zoom = frame.job.zoom
    x0, y0, x1, y1 = frame.display_rect
    width, height = (x1 - x0) / TWIPS, (y1 - y0) / TWIPS
    centre_x = frame.job.origin[0] + x0 / TWIPS + width / 2
    centre_y = frame.job.origin[1] + y0 / TWIPS + height / 2
    canvas_x = centre_x - frame.size[0] / zoom / 2
    canvas_y = centre_y - frame.size[1] / zoom / 2
    rect = (
        canvas_x + bbox[0] / zoom,
        canvas_y + bbox[1] / zoom,
        (bbox[2] - bbox[0]) / zoom,
        (bbox[3] - bbox[1]) / zoom,
    )
    image = canvas.crop(bbox)
    if not (
        math.isclose(rect[2] * zoom, image.width)
        and math.isclose(rect[3] * zoom, image.height)
    ):
        raise RenderError(
            f"timeline {frame.job.timeline} frame {frame.job.frame}: rect"
            f" {rect[2]}x{rect[3]} at zoom {zoom} isn't the"
            f" {image.width}x{image.height} image cut for it"
        )
    return Trimmed(image, bbox, rect)


def trim(frame: Frame) -> Trimmed | None:
    """-> the frame cut to its own opaque pixels, or None when it drew none."""
    canvas = frame.image()
    bbox = canvas.getchannel("A").getbbox()
    return None if bbox is None else _crop(frame, canvas, bbox)


def trim_union(rendered: Iterable[Frame]) -> list[Trimmed] | None:
    """-> every frame cut to one box holding all of their opaque pixels, so
    they come out the same size, or None when none of them drew anything."""
    canvases = [(frame, frame.image()) for frame in rendered]
    box = None
    for _frame, canvas in canvases:
        found = canvas.getchannel("A").getbbox()
        if found is None:
            continue
        box = (
            found
            if box is None
            else (
                min(box[0], found[0]),
                min(box[1], found[1]),
                max(box[2], found[2]),
                max(box[3], found[3]),
            )
        )
    if box is None:
        return None
    return [_crop(frame, canvas, box) for frame, canvas in canvases]


def placement_origin(
    index: SwfIndex, owner: int, frame: int, character: int
) -> tuple[float, float]:
    """-> where `owner`'s `frame` places `character`, in design px. Raises
    unless it places it exactly once with a pure translate, since the rect
    formula only adds the origin and can't carry a scale or a rotation."""
    placed = [
        (depth, layer)
        for depth, layer in timeline.frames(index, owner)[frame - 1].items()
        if layer.character_id == character
    ]
    if len(placed) != 1:
        raise RenderError(
            f"timeline {owner} frame {frame} places {character} {len(placed)} times"
        )
    depth, layer = placed[0]
    if tuple(layer.matrix[:4]) != IDENTITY_LINEAR:
        raise RenderError(
            f"timeline {owner} frame {frame} depth {depth}: {character} is placed"
            f" with {layer.matrix[:4]}, not a pure translate"
        )
    return layer.matrix[4] / TWIPS, layer.matrix[5] / TWIPS


def runs_stop(index: SwfIndex, sprite: int, frame: int) -> bool:
    """-> whether `sprite`'s scripts on `frame` run stop(). Raises on a
    script that moves a playhead any other way, calls a playhead method by
    name, or holds a stop() with DOUBTFUL_STOP_ACTIONS, because then only its
    ActionScript says which frames the clip shows."""
    stops = False
    for block in index.code:
        if block.kind != "frame" or block.owner != sprite or block.frame != frame:
            continue
        where = f"timeline {sprite} frame {frame}"
        actions = set(block.actions)
        if block.goto_labels or block.goto_frames or actions & MOVING_ACTIONS:
            raise RenderError(f"{where} moves its playhead other than by stop()")
        names = sorted(PLAYHEAD_METHODS.intersection(block.strings))
        if names:
            raise RenderError(f"{where} calls {', '.join(names)} by name")
        if ACTION_STOP in actions:
            if actions & DOUBTFUL_STOP_ACTIONS:
                raise RenderError(
                    f"{where} may skip its stop() or run it on another clip"
                )
            stops = True
    return stops


def played_frames(index: SwfIndex, sprite: int, start: int = 1) -> list[int]:
    """-> the frames to render of a clip the game plays once from `start`:
    through the frame whose script runs stop(), or through its last frame
    when none does. A clip nested in it plays from its own frame 1 and holds
    the frame whose script runs stop(), where ffdec loops it on instead, so
    the frames end before the first frame ffdec draws that way. That needs
    the game to draw nothing from there on. Raises when it still draws
    something, and when a clip placed before `start` still plays on `start`,
    since no tag says how long that clip has played."""
    count = index.sprite_frames[sprite]
    end = next(
        (frame for frame in range(start, count + 1) if runs_stop(index, sprite, frame)),
        count,
    )
    frames = list(range(start, end + 1))
    for at, frame in enumerate(frames):
        for character, placed in _shown(index, sprite, frame):
            if placed < start and character in index.sprite_frames:
                raise RenderError(
                    f"timeline {sprite} frame {frame} shows {character}, placed on"
                    f" frame {placed}, before the frame {start} the clip resumes on"
                )
        if _misdrawn(index, sprite, frame, frame - 1):
            for later in frames[at:]:
                drawn = _draws(index, sprite, later, later - 1)
                if drawn:
                    raise RenderError(
                        f"timeline {sprite} frame {later} still draws {drawn} after"
                        f" a clip nested in it stops on frame {frame - 1}, which"
                        " ffdec draws looped round instead"
                    )
            return frames[:at]
    return frames


def _game_frame(index: SwfIndex, sprite: int, age: int) -> int:
    """-> the frame the game shows a clip on `age` frames after placing it.
    The clip plays from its frame 1, holds the first frame it reaches whose
    script runs stop(), and loops when it reaches none."""
    count = index.sprite_frames[sprite]
    for frame in range(1, min(age + 1, count) + 1):
        if runs_stop(index, sprite, frame):
            return frame
    return age % count + 1


def _shown(index: SwfIndex, owner: int, frame: int) -> list[tuple[int, int]]:
    """-> (character, the frame that placed it) for each depth `owner` shows
    on `frame`. A move keeps the character's place frame, and a place after a
    RemoveObject starts a new one."""
    placed: dict[int, int] = {}
    for event in index.display.get(owner, []):
        if event.frame > frame:
            break
        if isinstance(event, Placement) and not event.move:
            placed[event.depth] = event.frame
    return [
        (layer.character_id, placed[depth])
        for depth, layer in timeline.frames(index, owner)[frame - 1].items()
    ]


def _misdrawn(index: SwfIndex, owner: int, frame: int, age: int) -> bool:
    """-> whether ffdec draws a clip nested in `owner`'s `frame` on another
    frame than the game shows it on. `age` counts the frames since `owner`
    started on its frame 1. ffdec draws a nested clip on its age modulo its
    frame count (Timeline.drawDrawable at jpexs cde1cc21a), and passes that
    age on to the clips nested in it."""
    for character, placed in _shown(index, owner, frame):
        if character not in index.sprite_frames:
            continue
        child_age = age - (placed - 1)
        drawn = child_age % index.sprite_frames[character] + 1
        if drawn != _game_frame(index, character, child_age) or _misdrawn(
            index, character, drawn, child_age
        ):
            return True
    return False


def _draws(index: SwfIndex, owner: int, frame: int, age: int) -> list[int]:
    """-> every character other than a clip that the game draws for
    `owner`'s `frame`, the ones clips nested in it draw included. `age`
    counts the frames since `owner` started on its frame 1."""
    drawn = []
    for character, placed in _shown(index, owner, frame):
        if character not in index.sprite_frames:
            drawn.append(character)
            continue
        child_age = age - (placed - 1)
        drawn += _draws(
            index, character, _game_frame(index, character, child_age), child_age
        )
    return drawn
