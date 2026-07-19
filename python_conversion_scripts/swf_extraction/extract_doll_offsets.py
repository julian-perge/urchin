# extract_doll_offsets.py
# Per-art-clip render bounds (px) for every doll sprite PNG in
# resources/sprites/, from the swf2xml dumps in source_files/swf_xml/.
#
# Each PNG was exported from the library sprite named in ExportAssets,
# cropped to the sprite's rendered bounds, so placing it in Godot needs:
# position = bounds min (px), scale = natural_size / png_size (the export
# ran at ~10x zoom, but not uniformly - the per-axis ratio handles it).
# Writes resources/sprites/doll_offsets.json (consumed by
# scripts/entities/character_visual.gd).
#
# Run: uv run python3 python_conversion_scripts/swf_extraction/extract_doll_offsets.py
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from swf_xml_lib import (  # noqa: E402
    STEAM_SWF_XML, WEB_SWF_XML, make_char_bounds, parse_swf_xml,
)

REPO = Path(__file__).resolve().parent.parent.parent
SPRITES = REPO / "resources" / "sprites"
OUT = SPRITES / "doll_offsets.json"


def png_size(path: Path):
    head = path.open("rb").read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def main():
    resolvers = []
    for xml_path in (WEB_SWF_XML, STEAM_SWF_XML):
        shapes, sprites, exports = parse_swf_xml(xml_path)
        resolvers.append((exports, make_char_bounds(shapes, sprites)))

    result = {}
    missing = []
    for png in sorted(SPRITES.glob("*.png")):
        name = png.stem
        bounds = None
        for exports, char_bounds in resolvers:
            cid = exports.get(name)
            if cid is not None:
                bounds = char_bounds(cid)
                if bounds is not None:
                    break
        if bounds is None:
            missing.append(name)
            continue
        w_px = (bounds[2] - bounds[0]) / 20.0
        h_px = (bounds[3] - bounds[1]) / 20.0
        size = png_size(png)
        if size is None or size[0] <= 1 or w_px <= 0 or h_px <= 0:
            continue  # 1x1 placeholder art (deliberately empty part)
        result[name] = {
            "x": round(bounds[0] / 20.0, 2),
            "y": round(bounds[1] / 20.0, 2),
            "w": round(w_px, 2),
            "h": round(h_px, 2),
        }

    print(f"resolved: {len(result)}, missing: {len(missing)}", file=sys.stderr)
    if missing:
        print("missing (1x1 placeholders expected):", missing, file=sys.stderr)
    OUT.write_text(json.dumps(result, indent=1, sort_keys=True))
    print(f"wrote {OUT} ({len(result)} entries)", file=sys.stderr)


if __name__ == "__main__":
    main()
