# Re-renders every doll art sprite in resources/sprites/ at exactly 2x the
# design size (the window's default scale), and writes the render bounds each
# one needs to be placed with to resources/sprites/doll_offsets.json. The
# Steam SWF fills names the web SWF lacks (DOG/WOLF/... art).
#
# Each sprite is exported through ffdec's own sprite renderer, not reassembled
# shape-by-shape. A hand-rolled compositor reads only characterId and matrix
# off each PlaceObject tag, so anything else living on that tag is silently
# dropped: 159 of these 789 sprites carry a surface filter and 56 carry a
# colorTransform. Same root cause and fix as item_icons.py and faces.py.
#
# Positioning these needs care, because a filter makes ffdec's canvas bigger
# than the art's own bounds - F_SHEAD_FIR's shape bounds are 12.05x19.45
# design px but its exported canvas is 32.5x39.5, since the glow is drawn
# outside the shape. So the recorded rect has to describe what was rendered,
# not what the shape geometry says, or every filtered part would be scaled
# down and shifted by the width of its own glow.
#
# render.py works out where each part goes. The driver reports with every
# frame the rect ffdec sized the canvas from, filter margin included, and
# ffdec puts that rect's left and top edges on the canvas's (0, 0), so the
# rect needs no filter math of its own. Before
# julian-perge/urchin#43 this file read the displayRect off a second ffdec
# pass in SVG, and before that it walked the XML dump in Python, which took
# 28.2s against the SVG pass's 4.1s.
#
# Flash draws a filter's blur in stage px, whatever scale the art is drawn
# at, but ffdec bakes the blur into the PNG, so the port drew it scaled with
# the part. MODEL8 draws its parts at about 0.67, which drew the Hydra's glow
# about 4.7 px wide where Flash draws 7 (julian-perge/urchin#471). So each
# art with a filter also gets a render per scale the game can draw it at, with
# the blur divided by that scale, in glow_scales/. CharacterVisual picks the
# render nearest the scale each part is drawn at on every frame.
#
# The scales of an art come from every model that can wear it: the scales its
# parts take on the model's frames, times the model's own size in dressChar,
# up to the battle zoom's peak, and the scale of each menu doll that shows it.
# The renders sit GLOW_STEP apart, so a part is never drawn more than half a
# step from the scale its render was made for. Two scales whose blurs round
# to the same whole px in ffdec give the same image, so only the first is
# kept.
#
# Run: uv run extract_doll_art
from __future__ import annotations

import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, REPO_ROOT, STEAM_SWF, WEB_SWF, png
from urchin_dev.swf import render
from urchin_dev.swf.swf_index import SwfIndex, filter_of, read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
OFFSETS = SPRITES / "doll_offsets.json"
GLOW_DIR = SPRITES / "glow_scales"
GLOW_FILE = SPRITES / "glow_scales.json"
GLOW_STEP = 1.15
ZOOM = 2.0
DRESS_CHAR = ACTION_SCRIPT / "frame_217" / "DoAction_2.as"
BATTLE_MOTION = REPO_ROOT / "assets" / "ui" / "battle" / "battle_screen_motion.json"
CHARACTER_VISUAL = "res://scripts/entities/character_visual.gd"
# CharacterVisual plays MODEL1's clip for a model outside the ones it has a
# timeline for, so a unit of such a model wears its art at MODEL1's scales.
DEFAULT_MODEL = "MODEL1"
# ffdec rounds each canvas dimension up to a whole pixel, so a canvas can read
# as very slightly larger than its own displayRect with no filter involved.
# Anything past this much growth is a real filter.
ROUNDING_SLACK_PX = 0.75


def dress_rules(script: str) -> tuple[dict[str, list[str]], dict[str, float]]:
    """-> (the parts that draw each art code, the size dressChar gives each
    model's doll), from dressChar's dollPartsArray and dollPartsCores2 and its
    _xscale change for one model. A model with no size change is left out."""

    def array(name: str) -> list[str]:
        found = re.search(name + r" = \[([^\]]*)\]", script)
        if found is None:
            raise ValueError(f"dressChar has no {name}")
        return re.findall(r'"(\w+)"', found.group(1))

    parts: dict[str, list[str]] = defaultdict(list)
    for part, code in zip(
        array("dollPartsArray"), array("dollPartsCores2"), strict=True
    ):
        parts[code].append(part)
    sizes = {
        model: float(size)
        for model, size in re.findall(
            r'model_dress == "(\w+)"\)\s*\{[^}]*?inner\._xscale \*= ([\d.]+);', script
        )
    }
    if not sizes:
        raise ValueError("dressChar sizes no model")
    return dict(parts), sizes


def art_key(name: str, codes: set[str]) -> tuple[str, str, bool] | None:
    """-> (code, key, is_skin) of a doll art name such as M_SFOOT_HYDRA2, or
    None for art dressChar does not attach by code, such as hair. key is the
    skin or the item looks the name ends in."""
    parts = name.split("_", 2)
    if len(parts) != 3:
        return None
    _, code, key = parts
    if code.startswith("S") and code[1:] in codes:
        return code[1:], key, True
    if code in codes:
        return code, key, False
    return None


def wearers(
    units: list[dict], items: dict[int, dict], forms: dict[str, dict], models: set[str]
) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """-> (models by skin, models by item looks): every model that wears the
    skin, or an item with the looks, as a unit, a skin setter or a buff form."""
    skins: dict[str, set[str]] = defaultdict(set)
    looks: dict[str, set[str]] = defaultdict(set)
    for unit in units:
        visuals = unit["visuals"]
        model = visuals["model"][0] if visuals["model"][0] in models else DEFAULT_MODEL
        if len(visuals["model"]) > 1:
            skins[visuals["model"][1]].add(model)
        if visuals["skin"] not in ("", "0"):
            looks[visuals["skin"]].add(model)
        for equipped in visuals["equipment"]:
            item = items.get(equipped["id"])
            if item is not None and item.get("looks"):
                looks[item["looks"]].add(model)
    for form in forms.values():
        skins[form["skin"]].add(form["model"])
        for weapon in (form["weapon1"], form["weapon2"]):
            if weapon:
                looks[weapon].add(form["model"])
    return skins, looks


def part_scales(animations: dict) -> dict[str, tuple[float, float]]:
    """-> each part's smallest and largest scale over a model's frames, as the
    square root of its matrix's determinant."""
    scales: dict[str, tuple[float, float]] = {}
    for frame in animations["frames"]:
        for part, matrix in (frame or {}).items():
            if not matrix:
                continue
            scale = math.sqrt(abs(matrix[0] * matrix[3] - matrix[1] * matrix[2]))
            low, high = scales.get(part, (scale, scale))
            scales[part] = (min(low, scale), max(high, scale))
    return scales


def zoom_peak(variables: dict) -> float:
    """-> the largest scale GridZoomer gives the battle screen. Each of its
    zoomTime steps adds scaleChange / zoomFactor times the steps left, in
    percent (battle_screen_clip.gd's GridZoomer)."""
    steps = int(variables["zoomTime"])
    grown = variables["scaleChange"] / variables["zoomFactor"] * steps * (steps + 1) / 2
    return 1.0 + grown / 100.0


def menu_dolls(scene: str) -> list[tuple[str, float]]:
    """-> (rest_model, scale) of each CharacterVisual node a .tscn places."""
    script_id = re.search(
        r'\[ext_resource type="Script" path="'
        + re.escape(CHARACTER_VISUAL)
        + r'" id="([^"]+)"\]',
        scene,
    )
    if script_id is None:
        return []
    dolls = []
    for block in re.split(r"\n(?=\[)", scene):
        if f'script = ExtResource("{script_id.group(1)}")' not in block:
            continue
        scale = re.search(r"scale = Vector2\(([-\d.]+), ([-\d.]+)\)", block)
        size = (
            math.sqrt(abs(float(scale.group(1)) * float(scale.group(2))))
            if scale
            else 1.0
        )
        model = re.search(r'rest_model = "(\w+)"', block)
        dolls.append((model.group(1) if model else DEFAULT_MODEL, size))
    return dolls


def grid(low: float, high: float) -> list[float]:
    """-> the powers of GLOW_STEP from the one at or below low to the one at
    or above high, 1.0 first."""
    first = math.floor(math.log(low) / math.log(GLOW_STEP) + 1e-9)
    last = math.ceil(math.log(high) / math.log(GLOW_STEP) - 1e-9)
    steps = sorted(range(first, last + 1), key=abs)
    if 0 not in steps:
        steps.insert(0, 0)
    return [GLOW_STEP**k for k in steps]


def distinct(scales: list[float], blurs: list[float]) -> list[float]:
    """-> scales without the ones whose blurs ffdec draws as wide as an earlier
    one's. ffdec draws a blur at Math.round(blur * zoom) px (GLOWFILTER.apply
    at jpexs cde1cc21a), and a render for scale s divides it by s."""
    kept: list[float] = []
    seen: set[tuple[int, ...]] = set()
    for scale in scales:
        widths = tuple(math.floor(blur * ZOOM / scale + 0.5) for blur in blurs)
        if widths not in seen:
            seen.add(widths)
            kept.append(scale)
    return kept


def filter_blurs(index: SwfIndex, character: int) -> list[float]:
    """-> the blurX and blurY of every filter that any timeline under a
    sprite places, the sprite's own included."""
    by_owner = defaultdict(list)
    for placement in index.placements:
        by_owner[placement.owner].append(placement)
    blurs: list[float] = []
    stack, seen = [character], set()
    while stack:
        owner = stack.pop()
        if owner in seen:
            continue
        seen.add(owner)
        for placement in by_owner.get(owner, []):
            for record in placement.filter_records or ():
                found = filter_of(record)
                blurs += [found.blur_x, found.blur_y]
            if placement.character_id in index.sprite_frames:
                stack.append(placement.character_id)
    return blurs


def glow_scales(
    names: list[str],
    blurs: dict[str, list[float]],
    parts_by_code: dict[str, list[str]],
    skins: dict[str, set[str]],
    looks: dict[str, set[str]],
    scales: dict[str, dict[str, tuple[float, float]]],
    sizes: dict[str, float],
    peak: float,
    menus: list[tuple[str, float]],
) -> dict[str, list[float]]:
    """-> the scales to render each art with a filter at, 1.0 first. Every
    menu doll's rest model can wear any item, because the player can."""
    players = {model for model, _ in menus}
    found: dict[str, list[float]] = {}
    for name in names:
        if not blurs.get(name):
            continue
        key = art_key(name, set(parts_by_code))
        if key is None:
            continue
        code, worn, is_skin = key
        models = (
            set(skins.get(worn, ())) if is_skin else set(looks.get(worn, ())) | players
        )
        low, high = math.inf, 0.0
        for model in models:
            size = sizes.get(model, 1.0)
            for part in parts_by_code[code]:
                if part not in scales.get(model, {}):
                    continue
                least, most = scales[model][part]
                low = min(low, least * size)
                high = max(high, most * size * peak)
                for menu_model, menu_scale in menus:
                    if menu_model == model:
                        high = max(high, most * menu_scale)
        if high > 0.0:
            found[name] = distinct(grid(low, high), blurs[name])
    return found


def glow_name(name: str, scale: float) -> str:
    return f"{name}@{round(scale * 100)}"


def render_swf(swf_path: Path, names: list[str]):
    """-> (rects, unresolved, grown). rects maps name to its design-px rect."""
    index = read_swf(swf_path)

    wanted: dict[int, str] = {}
    unresolved: list[str] = []
    for name in names:
        cid = index.exports.get(name)
        if cid is None or not index.sprite_frames.get(cid):
            unresolved.append(name)
            continue
        wanted[cid] = name

    if not wanted:
        return {}, unresolved, []

    rects: dict[str, tuple[float, float, float, float]] = {}
    grown: list[str] = []
    jobs = [render.Job(cid, 1, ZOOM) for cid in sorted(wanted)]
    with render.frames(swf_path, jobs) as rendered:
        for frame in rendered:
            name = wanted[frame.job.timeline]
            trimmed = render.trim(frame)
            if trimmed is None or trimmed.image.width <= 1 or trimmed.image.height <= 1:
                # A deliberately empty part. Leave whatever placeholder PNG is
                # already on disk alone and record no rect, which is how
                # character_visual.gd's _add_layer() detects and skips one.
                unresolved.append(name)
                continue
            x0, y0, x1, y1 = frame.display_rect
            if (
                frame.size[0] / ZOOM - (x1 - x0) / 20 > ROUNDING_SLACK_PX
                or frame.size[1] / ZOOM - (y1 - y0) / 20 > ROUNDING_SLACK_PX
            ):
                grown.append(name)
            rects[name] = trimmed.rect
            png.save(trimmed.image, SPRITES / (name + ".png"))
    return rects, unresolved, grown


def render_glows(
    swf_path: Path, names: list[str], context: dict
) -> dict[str, list[dict]]:
    """Render every art of names that the SWF exports at each of its glow
    scales but 1.0, into GLOW_DIR. -> each art's renders, as glow_scales.json
    holds them, without the one at scale 1.0."""
    index = read_swf(swf_path)
    exported = {name: index.exports[name] for name in names if name in index.exports}
    blurs = {name: filter_blurs(index, cid) for name, cid in exported.items()}
    scales = glow_scales(sorted(exported), blurs, **context)
    wanted = [(name, scale) for name in sorted(scales) for scale in scales[name][1:]]
    jobs = [
        render.Job(exported[name], 1, ZOOM, filter_scale=1.0 / scale)
        for name, scale in wanted
    ]
    found: dict[str, list[dict]] = defaultdict(list)
    with render.frames(swf_path, jobs) as rendered:
        for frame, (name, scale) in zip(rendered, wanted, strict=True):
            trimmed = render.trim(frame)
            art = glow_name(name, scale)
            png.save(trimmed.image, GLOW_DIR / (art + ".png"))
            found[name].append(entry(scale, f"glow_scales/{art}", trimmed.rect))
    return found


def entry(scale: float, art: str, rect: tuple[float, float, float, float]) -> dict:
    return {
        "scale": round(scale, 4),
        "art": art,
        "x": round(rect[0], 2),
        "y": round(rect[1], 2),
        "w": round(rect[2], 2),
        "h": round(rect[3], 2),
    }


def glow_context() -> dict:
    """-> the inputs of glow_scales() that do not come from the SWF."""
    parts_by_code, sizes = dress_rules(DRESS_CHAR.read_text("utf-8"))
    scales = {
        path.name.split("_")[0].upper(): part_scales(json.loads(path.read_text()))
        for path in SPRITES.glob("model*_animations.json")
    }
    units = json.loads((CONVERTED_JSON / "units.json").read_text())["units"]
    items = {
        item["id"]: item
        for item in json.loads((CONVERTED_JSON / "items.json").read_text())["items"]
    }
    forms = json.loads((CONVERTED_JSON / "buff_looks.json").read_text())["forms"]
    skins, looks = wearers(units, items, forms, set(scales))
    variables = json.loads(BATTLE_MOTION.read_text())["zoomer"]["variables"]
    menus = [
        doll
        for scene in sorted((REPO_ROOT / "scenes").rglob("*.tscn"))
        for doll in menu_dolls(scene.read_text("utf-8"))
        if "battle" not in scene.parts
    ]
    return {
        "parts_by_code": parts_by_code,
        "skins": skins,
        "looks": looks,
        "scales": scales,
        "sizes": sizes,
        "peak": zoom_peak(variables),
        "menus": menus,
    }


def main():
    names = sorted(p.stem for p in SPRITES.glob("*.png"))
    print(f"doll sprites on disk: {len(names)}", file=sys.stderr)

    rects, unresolved, grown = render_swf(WEB_SWF, names)
    print(
        f"web SWF: {len(rects)} rendered, {len(grown)} grown by a filter",
        file=sys.stderr,
    )

    if unresolved:
        steam_rects, unresolved, steam_grown = render_swf(STEAM_SWF, sorted(unresolved))
        rects.update(steam_rects)
        grown.extend(steam_grown)
        print(
            f"steam SWF: {len(steam_rects)} rendered, "
            f"{len(steam_grown)} grown by a filter",
            file=sys.stderr,
        )

    OFFSETS.write_text(
        json.dumps(
            {
                name: {
                    "x": round(rect[0], 2),
                    "y": round(rect[1], 2),
                    "w": round(rect[2], 2),
                    "h": round(rect[3], 2),
                }
                for name, rect in sorted(rects.items())
            },
            indent=1,
            sort_keys=True,
        )
    )
    print(f"wrote {OFFSETS} ({len(rects)} entries)", file=sys.stderr)

    GLOW_DIR.mkdir(exist_ok=True)
    for stale in GLOW_DIR.glob("*.png"):
        stale.unlink()
    context = glow_context()
    web_names = [name for name in rects if name in read_swf(WEB_SWF).exports]
    glows = render_glows(WEB_SWF, web_names, context)
    glows.update(
        render_glows(
            STEAM_SWF, [name for name in rects if name not in web_names], context
        )
    )
    # The .import files of the PNGs written again stay, so their uids do not
    # change, and only those of PNGs no longer written go.
    for imported in GLOW_DIR.glob("*.png.import"):
        if not imported.with_suffix("").exists():
            imported.unlink()
    GLOW_FILE.write_text(
        json.dumps(
            {
                name: [entry(1.0, name, rects[name]), *glows[name]]
                for name in sorted(glows)
            },
            indent=1,
        )
    )
    print(
        f"wrote {GLOW_FILE}: {sum(len(v) for v in glows.values())} renders"
        f" for {len(glows)} arts",
        file=sys.stderr,
    )
    print(
        f"skipped (placeholders / not in either SWF): {len(unresolved)}",
        file=sys.stderr,
    )
    if unresolved:
        print(f"skipped: {sorted(unresolved)}", file=sys.stderr)


if __name__ == "__main__":
    main()
