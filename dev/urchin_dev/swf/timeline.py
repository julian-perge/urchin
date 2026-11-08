# timeline.py
# Each frame's display list for a sprite or the root timeline, folded from
# the PlaceObject and RemoveObject tags swf_index.py records.
#
# It applies the four rules ffdec and Ruffle agree on:
#   - a place on an empty depth starts from the identity matrix with nothing
#     else set
#   - a move keeps every field it doesn't carry
#   - a replace (a move with a character) swaps the character and keeps
#     everything else
#   - a RemoveObject empties the depth
# Anything outside those raises, naming the timeline, frame and depth. No
# tag in either SWF this repo extracts from falls outside them: no place
# lands on an occupied depth, no move, replace or removal lands on an empty
# one, no move carries a name, clipDepth or clip actions, and every replace
# swaps a shape for a shape or a morph for a morph (julian-perge/urchin#36).
# The two players disagree on some of those cases, so this refuses to pick.
#
# ffdec does not run ActionScript, and neither does this. A clip that a
# gotoAndStop handler or onLoad would move or hide shows here as the tags
# leave it.
from __future__ import annotations

from dataclasses import dataclass, replace

from urchin_dev.swf.swf_index import (
    TAG_PLACE_OBJECT,
    Placement,
    Removal,
    SwfIndex,
    character_kind,
)

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0, 0)
SWAPPABLE_KINDS = {"shape", "morph"}


@dataclass(frozen=True)
class Layer:
    """What one depth shows on one frame. matrix is (scaleX, rotateSkew0,
    rotateSkew1, scaleY, tx, ty) with the translation in integer twips, as
    swf_index.Placement stores it."""

    character_id: int
    name: str | None = None
    matrix: tuple[float, float, float, float, int, int] = IDENTITY
    color_transform: tuple[int, ...] | None = None
    clip_depth: int | None = None
    ratio: int | None = None
    filters: tuple[str, ...] = ()
    blend_mode: int | None = None


class TimelineError(ValueError):
    pass


def frames(index: SwfIndex, owner: int) -> list[dict[int, Layer]]:
    """-> one {depth: Layer} per frame of the timeline, frame 1 first. owner
    is 0 for the root timeline or a DefineSprite id."""
    count = index.root_frames if owner == 0 else index.sprite_frames[owner]
    events = index.display.get(owner, [])
    state: dict[int, Layer] = {}
    result: list[dict[int, Layer]] = []
    i = 0
    for frame in range(1, count + 1):
        while i < len(events) and events[i].frame == frame:
            _apply(index, state, events[i])
            i += 1
        result.append(dict(state))
    if i < len(events):
        event = events[i]
        raise TimelineError(
            f"{_where(event)}: tag after the last of the timeline's {count} frames"
        )
    return result


def labels(index: SwfIndex, owner: int) -> dict[str, int]:
    """-> {label: frame} for one timeline, with each label as written."""
    result: dict[str, int] = {}
    seen: dict[str, str] = {}
    for label in index.labels:
        if label.owner != owner:
            continue
        key = label.name.casefold()
        if key in seen:
            raise TimelineError(
                f"timeline {owner} has both {seen[key]!r} and {label.name!r}, and"
                " AVM1 matches labels case-insensitively"
            )
        seen[key] = label.name
        result[label.name] = label.frame
    return result


def frame_of(index: SwfIndex, owner: int, label: str) -> int:
    """-> the frame carrying `label`, matched case-insensitively as AVM1 does."""
    key = label.casefold()
    for name, frame in labels(index, owner).items():
        if name.casefold() == key:
            return frame
    raise KeyError(f"timeline {owner} has no label {label!r}")


def _where(event: Placement | Removal) -> str:
    return f"timeline {event.owner} frame {event.frame} depth {event.depth}"


def _apply(index: SwfIndex, state: dict[int, Layer], event) -> None:
    where = _where(event)
    current = state.get(event.depth)
    if isinstance(event, Removal):
        if current is None:
            raise TimelineError(f"{where}: RemoveObject on an empty depth")
        del state[event.depth]
        return
    if event.tag == TAG_PLACE_OBJECT:
        raise TimelineError(f"{where}: PlaceObject version 1")
    if not event.move:
        if current is not None:
            raise TimelineError(f"{where}: place on an occupied depth")
        if event.character_id is None:
            raise TimelineError(f"{where}: place without a character")
        state[event.depth] = Layer(
            event.character_id,
            name=event.name,
            matrix=event.matrix or IDENTITY,
            color_transform=event.color_transform,
            clip_depth=event.clip_depth,
            ratio=event.ratio,
            filters=event.filters or (),
            blend_mode=event.blend_mode,
        )
        return
    if current is None:
        raise TimelineError(f"{where}: move on an empty depth")
    if event.name is not None or event.clip_depth is not None or event.clip_actions:
        raise TimelineError(f"{where}: move carrying a name, clipDepth or clip actions")
    character = current.character_id
    if event.character_id is not None:
        kinds = {
            character_kind(index, current.character_id),
            character_kind(index, event.character_id),
        }
        if not kinds <= SWAPPABLE_KINDS:
            raise TimelineError(
                f"{where}: replace of {current.character_id} with"
                f" {event.character_id} involves a {'/'.join(sorted(kinds))}"
            )
        character = event.character_id
    state[event.depth] = replace(
        current,
        character_id=character,
        matrix=current.matrix if event.matrix is None else event.matrix,
        color_transform=(
            current.color_transform
            if event.color_transform is None
            else event.color_transform
        ),
        ratio=current.ratio if event.ratio is None else event.ratio,
        filters=current.filters if event.filters is None else event.filters,
        blend_mode=current.blend_mode if event.blend_mode is None else event.blend_mode,
    )
