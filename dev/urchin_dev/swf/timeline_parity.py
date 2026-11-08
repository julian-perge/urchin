# timeline_parity.py
# Runs every query the extractors make of the XML dump through both the XML
# helpers in xml_lib.py and the direct SWF parser (swf_index.py plus
# timeline.py), and prints every difference. It exits non-zero on any.
#
# Integers, names and twips compare exactly. Scale and rotate compare after
# rounding both sides to float32: ffdec's MATRIX stores them as Java floats,
# and every 16.16 value under 256 is exactly a float32, so the dump's
# shortest decimal reads back as the parser's value with no tolerance.
#
# This exists to prove the parser before the XML helpers go, and it goes with
# them (julian-perge/urchin#36).
#
# Run: uv run python -m urchin_dev.swf.timeline_parity
from __future__ import annotations

import re
import struct
import sys

from urchin_dev import STEAM_SWF, STEAM_SWF_XML, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import battle_screen, cutscenes, zone_hub
from urchin_dev.swf.swf_index import (
    SHAPE_TAGS,
    bitmap_fill_ids,
    first_fill_bitmap_id,
    read_swf,
    shape_bounds,
    sound_stream,
)
from urchin_dev.swf.xml_lib import (
    parse_swf_xml,
    root_placements,
    snapshot_timeline,
    sprite_body,
)

ROOT_LABELS = ("classMenu", "KRINBATTLESCENE")
# The bitmap id find_broken_bitmap_fill_cids looks for.
MISSING_BITMAP = 65535
_SPRITE_RE = re.compile(r'<item type="DefineSpriteTag"[^>]*spriteId="(\d+)"[^>]*>')
_SHAPE_RE = re.compile(r'<item type="DefineShape\d?Tag"[^>]*shapeId="(\d+)"[^>]*>')
_ITEM_TOKEN_RE = re.compile(r"<item\b[^>]*?(/?)>|</item>")


def f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


def same_matrix(xml_matrix, walk_matrix) -> bool:
    xml_matrix = xml_matrix or (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    return all(f32(a) == f32(b) for a, b in zip(xml_matrix[:4], walk_matrix[:4])) and (
        xml_matrix[4:] == tuple(float(v) for v in walk_matrix[4:])
    )


def same_entry(xml_entry: dict, layer: timeline.Layer) -> bool:
    return (
        xml_entry.get("cid") == layer.character_id
        and xml_entry.get("name") == layer.name
        and same_matrix(xml_entry.get("mat"), layer.matrix)
    )


def compare_display(where: str, xml_state: dict, walk_state: dict, out: list) -> None:
    for depth in sorted(set(xml_state) | set(walk_state)):
        xml_entry, layer = xml_state.get(depth), walk_state.get(depth)
        if xml_entry is None or layer is None or not same_entry(xml_entry, layer):
            out.append(f"{where} depth {depth}: xml {xml_entry} walk {layer}")


def sprite_slices(xml: str) -> dict[int, str]:
    """-> {sprite id: its own <item> through </subTags>}, so snapshot_timeline
    searches a few KB instead of the whole dump for each sprite."""
    slices = {}
    for m in _SPRITE_RE.finditer(xml):
        # An empty sprite writes <subTags/>, so xml_lib.sprite_body reads on
        # into the next sprite's tags. No extractor asks for an empty one.
        if xml[m.end() : m.end() + 40].lstrip().startswith("<subTags/>"):
            slices[int(m.group(1))] = m.group(0)
            continue
        end = xml.find("</subTags>", m.end())
        slices[int(m.group(1))] = xml[m.start() : end + len("</subTags>")]
    return slices


def shape_elements(xml: str) -> dict[int, str]:
    """-> {shape id: its whole <item> element}, closing tag included."""
    elements = {}
    for m in _SHAPE_RE.finditer(xml):
        depth = 1
        for token in _ITEM_TOKEN_RE.finditer(xml, m.end()):
            if token.group(0) == "</item>":
                depth -= 1
            elif not token.group(1):
                depth += 1
            if depth == 0:
                elements[int(m.group(1))] = xml[m.start() : token.end()]
                break
    return elements


def check_timelines(xml: str, index, out: list) -> int:
    slices = sprite_slices(xml)
    for sprite, count in sorted(index.sprite_frames.items()):
        walked = timeline.frames(index, sprite)
        snaps, labels = snapshot_timeline(
            slices[sprite], sprite, set(range(1, count + 1))
        )
        if labels != timeline.labels(index, sprite):
            out.append(
                f"sprite {sprite} labels: xml {labels} walk {timeline.labels(index, sprite)}"
            )
        for frame in range(1, count + 1):
            compare_display(
                f"sprite {sprite} frame {frame}",
                snaps.get(frame, {}),
                walked[frame - 1],
                out,
            )
    root = timeline.frames(index, 0)
    for label in ROOT_LABELS:
        frame, state = root_placements(xml, label)
        if frame != timeline.frame_of(index, 0, label):
            out.append(
                f"root {label}: xml frame {frame} walk {timeline.frame_of(index, 0, label)}"
            )
        compare_display(f"root {label} frame {frame}", state, root[frame - 1], out)
    return len(slices)


def check_first_frame_walks(xml: str, index, out: list) -> None:
    orb = timeline.frames(index, zone_hub.ORB_SPRITE)[0]
    walked = [(d, layer.character_id, layer.matrix) for d, layer in sorted(orb.items())]
    xml_layers = zone_hub.orb_layers(xml)
    if [(d, c) for d, c, _m in xml_layers] != [
        (d, c) for d, c, _m in walked
    ] or not all(
        same_matrix(xm, wm) for (_d, _c, xm), (_e, _f, wm) in zip(xml_layers, walked)
    ):
        out.append(f"orb_layers: xml {xml_layers} walk {walked}")
    for sprite in (
        battle_screen.MEMBER_BAR,
        battle_screen.STANCE_BUTTON,
        battle_screen.MEMBER_BARS,
    ):
        frame = timeline.frames(index, sprite)[0]
        walked = {
            d: (
                layer.character_id,
                layer.name or "",
                layer.matrix[4] / 20,
                layer.matrix[5] / 20,
            )
            for d, layer in frame.items()
        }
        xml_places = battle_screen.frame_one_placements(xml, sprite)
        if xml_places != walked:
            out.append(
                f"frame_one_placements({sprite}): xml {xml_places} walk {walked}"
            )


def check_definitions(xml_path, swf_path, index, out: list, shapes: bool) -> None:
    xml_bounds, sprites, exports = parse_swf_xml(xml_path)
    if exports != index.exports:
        out.append(f"{swf_path.name} exports differ")
    # doll_art.py asks whether an export name resolves to a sprite.
    for name in sorted(set(exports) | set(index.exports)):
        xml_sprite = exports.get(name) in sprites
        walk_sprite = index.exports.get(name) in index.sprite_frames
        if xml_sprite != walk_sprite:
            out.append(
                f"{swf_path.name} export {name!r} is a sprite: xml {xml_sprite} walk {walk_sprite}"
            )
    if shapes:
        ids = [
            c for c, (code, *_rest) in index.characters.items() if code in SHAPE_TAGS
        ]
        bounds = {c: shape_bounds(index, c) for c in ids}
        if {c: tuple(b) for c, b in xml_bounds.items()} != bounds:
            out.append(f"{swf_path.name} shape bounds differ")


def check_cutscenes(xml: str, index, out: list) -> None:
    elements = shape_elements(xml)
    for cid, element in elements.items():
        xml_ids = {int(b) for b in re.findall(r'bitmapId="(\d+)"', element)}
        if xml_ids != bitmap_fill_ids(index, cid):
            out.append(
                f"shape {cid} bitmap fill ids: xml {xml_ids} walk {bitmap_fill_ids(index, cid)}"
            )
    for name, (sprite, _wrapper, _frames, _camera) in cutscenes.CUTSCENES.items():
        body = sprite_body(xml, sprite)
        blocks = [
            bytes.fromhex(h)
            for h in re.findall(
                r'<item type="SoundStreamBlockTag"[^>]*streamSoundData="([0-9a-fA-F]*)"',
                body,
            )
        ]
        if blocks != sound_stream(index, sprite):
            out.append(f"{name} sound stream differs")
        xml_broken = cutscenes.find_broken_bitmap_fill_cids(xml, sprite)
        placed = {p.character_id for p in index.placements if p.owner == sprite}
        walk_broken = {
            c
            for c in placed
            if c is not None
            and index.characters[c][0] in SHAPE_TAGS
            and first_fill_bitmap_id(index, c) == MISSING_BITMAP
        }
        if xml_broken != walk_broken:
            out.append(f"{name} broken fills: xml {xml_broken} walk {walk_broken}")


def main() -> None:
    out: list[str] = []
    web = read_swf(WEB_SWF)
    xml = WEB_SWF_XML.read_text()
    sprites = check_timelines(xml, web, out)
    print(f"web timelines: {sprites} sprites and the root at {', '.join(ROOT_LABELS)}")
    check_first_frame_walks(xml, web, out)
    check_cutscenes(xml, web, out)
    check_definitions(WEB_SWF_XML, WEB_SWF, web, out, shapes=True)
    check_definitions(STEAM_SWF_XML, STEAM_SWF, read_swf(STEAM_SWF), out, shapes=False)
    for line in out[:50]:
        print(line)
    print(f"{len(out)} differences")
    sys.exit(1 if out else 0)


if __name__ == "__main__":
    main()
