# PROTOTYPE for julian-perge/urchin#108, throwaway.
#
# Renders the references the prototype is scored against and the art
# variants B and C draw, into images/ beside this file:
#
#   images/ref/win_<mode>_2x.png and _1x.png  KRINMENU's win frame on an
#       800x600 stage canvas, transparent where the frame draws nothing. full
#       is the frame as ffdec draws it, chrome strips every edit text, and
#       panels strips everything but the backdrop and the four panels. The 1x
#       copies are Lanczos downsamples, the way the godot-mcp harness shrinks
#       the game's framebuffer to its 800x600 screenshots.
#   images/art/<name>.png  one trimmed piece each, with art.json giving each
#       piece's rect and zoom.
#
# The references go through render.frames(). The pieces need only_depths
# and hide_depths, which render.Job doesn't carry, so they go through the
# ffdec_lib driver directly, as verify_battle_screen.py does, and each result
# is wrapped in a render.Frame so its rect still comes from render.py's
# formula. The two driver runs happen one after the other.
#
# Run from the repo root, with no other ffdec running:
#   uv run python dev/prototypes/victory_containers/render_art.py
from __future__ import annotations

import json
import math
import tempfile
from pathlib import Path

from PIL import Image
from urchin_dev import WEB_SWF
from urchin_dev.swf import ffdec_lib, render, strip, timeline
from urchin_dev.swf.swf_index import character_kind, read_swf, shape_bounds

HERE = Path(__file__).parent
REF_DIR = HERE / "images" / "ref"
ART_DIR = HERE / "images" / "art"
KRINMENU = 3142
STAGE = (800, 600)
REF_ZOOM = 2.0
ART_ZOOM = 2.0
SMALL_ZOOM = 4.0
ROW_SPRITE = 3002
FACE_SHEET = 2978
BAR_SPRITE = 2867
# Row depths that aren't the backing: the face, name, level, bar, overlay and
# percent (timeline.frames(3002)[0]).
ROW_NOT_BACKING = [3, 37, 38, 39, 41, 42]


def main():
    layout = json.loads((HERE / "win_layout.json").read_text())
    index = read_swf(WEB_SWF)
    win = timeline.frame_of(index, KRINMENU, "win")
    inventory = timeline.frame_of(index, KRINMENU, "inventory")
    origin = tuple(layout["krinmenu_origin"])

    # Every edit text the win frame shows, its own and the row's, so the
    # chrome reference keeps only art.
    texts = {t["id"]: f"win frame text {name}" for name, t in layout["texts"].items()}
    for key in ("name", "level", "percent"):
        piece = layout["row_pieces"][key]
        texts[piece["id"]] = f"row text {piece['variable']}"
    text_strip = strip.strip_list(WEB_SWF, texts)
    # Everything the win frame places except the backdrop, its edge and the
    # panel sprites, so the panels reference shows only those.
    win_layers = timeline.frames(index, KRINMENU)[win - 1]
    keep = {
        win_layers[1].character_id,
        win_layers[layout["backdrop"]["depth"]].character_id,
    }
    keep |= {p["sprite"] for p in layout["panels"].values()}
    others = {
        layer.character_id: f"win frame depth {depth}, not a panel"
        for depth, layer in sorted(win_layers.items())
        if layer.character_id not in keep
    }
    references = {
        "full": render.Job(KRINMENU, win, REF_ZOOM, origin),
        "chrome": render.Job(KRINMENU, win, REF_ZOOM, origin, strip=tuple(text_strip)),
        "panels": render.Job(
            KRINMENU,
            win,
            REF_ZOOM,
            origin,
            strip=tuple(strip.strip_list(WEB_SWF, others)),
        ),
    }
    REF_DIR.mkdir(parents=True, exist_ok=True)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    art = {}
    with render.frames(WEB_SWF, list(references.values())) as rendered:
        for mode, frame in zip(references, rendered, strict=True):
            cut = render.trim(frame)
            canvas = Image.new(
                "RGBA",
                (STAGE[0] * int(REF_ZOOM), STAGE[1] * int(REF_ZOOM)),
                (0, 0, 0, 0),
            )
            at = (round(cut.rect[0] * REF_ZOOM), round(cut.rect[1] * REF_ZOOM))
            canvas.alpha_composite(cut.image, at)
            canvas.save(REF_DIR / f"win_{mode}_2x.png")
            canvas.resize(STAGE, Image.Resampling.LANCZOS).save(
                REF_DIR / f"win_{mode}_1x.png"
            )
            art[f"ref_{mode}"] = {
                "rect": [round(v, 3) for v in cut.rect],
                "pasted_at_px": list(at),
                "paste_error": [
                    round(at[0] / REF_ZOOM - cut.rect[0], 3),
                    round(at[1] / REF_ZOOM - cut.rect[1], 3),
                ],
                "zoom": REF_ZOOM,
            }

    jobs = {
        "backdrop": {
            "timeline": KRINMENU,
            "frame": win,
            "zoom": ART_ZOOM,
            "origin": origin,
            "only_depths": [layout["backdrop"]["depth"]],
        },
        "delete_art": {
            "timeline": KRINMENU,
            "frame": win,
            "zoom": ART_ZOOM,
            "origin": origin,
            "only_depths": [layout["delete"]["art"]["depth"]],
        },
        "row_backing_shadow": {
            "timeline": KRINMENU,
            "frame": win,
            "zoom": ART_ZOOM,
            "origin": origin,
            "only_depths": [layout["rows"]["player"]["depth"]],
            "hide_depths": [{"owner": ROW_SPRITE, "depth": d} for d in ROW_NOT_BACKING],
        },
        "row_backing_plain": {
            "timeline": ROW_SPRITE,
            "frame": 1,
            "zoom": ART_ZOOM,
            "only_depths": [2],
        },
        "bar_overlay": {
            "timeline": ROW_SPRITE,
            "frame": 1,
            "zoom": SMALL_ZOOM,
            "only_depths": [41],
        },
        "bar_fill": {"timeline": BAR_SPRITE, "frame": 1, "zoom": SMALL_ZOOM},
        "bar_level": {
            "timeline": BAR_SPRITE,
            "frame": timeline.frame_of(index, BAR_SPRITE, "level"),
            "zoom": SMALL_ZOOM,
        },
    }
    # The panel shapes unscaled. The inventory frame places every panel shape
    # at scale 1 with the same inner DropShadow the win frame carries, so the
    # _shadow art is the panel as the original draws it, and the _plain art is
    # the panel sprite on its own, which has no filter.
    inventory_layers = timeline.frames(index, KRINMENU)[inventory - 1]
    for name, panel in layout["panels"].items():
        sprite = panel["sprite"]
        unscaled = [
            d
            for d, layer in inventory_layers.items()
            if layer.character_id == sprite and layer.matrix[:4] == (1.0, 0.0, 0.0, 1.0)
        ]
        jobs[f"panel_{name}_shadow"] = {
            "timeline": KRINMENU,
            "frame": inventory,
            "zoom": ART_ZOOM,
            "origin": origin,
            "only_depths": [unscaled[0]],
        }
        jobs[f"panel_{name}_plain"] = {"timeline": sprite, "frame": 1, "zoom": ART_ZOOM}
    face_labels = {
        "Veradux": 1,
        "Roald": 2,
        "Felicity": 3,
        "Wolfgang": 4,
        "Amber": 5,
        "mainPlayer": 6,
    }
    for label in face_labels:
        jobs[f"face_{label}"] = {
            "timeline": FACE_SHEET,
            "frame": timeline.frame_of(index, FACE_SHEET, label),
            "zoom": SMALL_ZOOM,
        }
    # The win frame render shows an empty frame where each row's face sits.
    # These two say whether the row clip on its own draws the face, and what
    # the face sheet's frame 9 holds, in case the sheet plays along with
    # KRINMENU's own frame number.
    jobs["diag_row_alone"] = {"timeline": ROW_SPRITE, "frame": 1, "zoom": ART_ZOOM}
    jobs["diag_face_frame9"] = {"timeline": FACE_SHEET, "frame": 9, "zoom": SMALL_ZOOM}

    # The rect each piece of art stands for, in the same coordinates as the
    # rect its render comes back with, so the prototype can tell how far the
    # art's own pixels reach past the shape (anti-aliasing and filters).
    def placed(depth_frame, depth):
        layer = timeline.frames(index, KRINMENU)[depth_frame - 1][depth]
        inner = next(iter(timeline.frames(index, layer.character_id)[0].values()))
        b = [v / 20 for v in shape_bounds(index, inner.character_id)]
        x = origin[0] + layer.matrix[4] / 20 + inner.matrix[4] / 20
        y = origin[1] + layer.matrix[5] / 20 + inner.matrix[5] / 20
        return [
            round(x + b[0], 3),
            round(y + b[1], 3),
            round(b[2] - b[0], 3),
            round(b[3] - b[1], 3),
        ]

    def local_bounds(cid, dx=0.0, dy=0.0):
        b = [v / 20 for v in shape_bounds(index, cid)]
        return [
            round(b[0] + dx, 3),
            round(b[1] + dy, 3),
            round(b[2] - b[0], 3),
            round(b[3] - b[1], 3),
        ]

    row_layers = timeline.frames(index, ROW_SPRITE)[0]
    bar_shape = next(iter(timeline.frames(index, BAR_SPRITE)[0].values())).character_id
    shape_rects = {
        "backdrop": layout["backdrop"]["rect"],
        "delete_art": layout["delete"]["art"]["rect"],
        "row_backing_shadow": layout["rows"]["player"]["rect"],
        "row_backing_plain": local_bounds(row_layers[2].character_id),
        "bar_overlay": local_bounds(row_layers[41].character_id),
        "bar_fill": local_bounds(bar_shape),
        "bar_level": local_bounds(bar_shape),
    }
    for name, panel in layout["panels"].items():
        job = jobs[f"panel_{name}_shadow"]
        shape_rects[f"panel_{name}_shadow"] = placed(
            job["frame"], job["only_depths"][0]
        )
        inner = next(iter(timeline.frames(index, panel["sprite"])[0].values()))
        shape_rects[f"panel_{name}_plain"] = local_bounds(inner.character_id)

    with tempfile.TemporaryDirectory(prefix="victory_art_") as tmp:
        requests = []
        for n, (name, job) in enumerate(jobs.items()):
            request = {k: v for k, v in job.items() if k != "origin"}
            request["out"] = str(Path(tmp) / f"{n}_{name}.png")
            request["background"] = "none"
            requests.append(request)
        results = ffdec_lib.render(WEB_SWF, requests)
        frames = {}
        for (name, job), result in zip(jobs.items(), results, strict=True):
            frame = render.Frame(
                job=render.Job(
                    job["timeline"],
                    job["frame"],
                    job["zoom"],
                    job.get("origin", (0.0, 0.0)),
                ),
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
            render.check_canvas(frame)
            frames[name] = frame

        faces = [frames[f"face_{label}"] for label in face_labels]
        for label, cut in zip(face_labels, render.trim_union(faces), strict=True):
            cut.image.save(ART_DIR / f"face_{label}.png")
            art[f"face_{label}"] = {
                "rect": [round(v, 3) for v in cut.rect],
                "zoom": SMALL_ZOOM,
            }
        for name, frame in frames.items():
            if name.startswith("face_"):
                continue
            cut = render.trim(frame)
            if cut is None:
                raise SystemExit(f"{name} rendered nothing")
            cut.image.save(ART_DIR / f"{name}.png")
            art[name] = {
                "rect": [round(v, 3) for v in cut.rect],
                "zoom": frame.job.zoom,
            }
            if name in shape_rects:
                art[name]["shape_rect"] = shape_rects[name]
            if cut.image.width != math.ceil(cut.rect[2] * frame.job.zoom - 1e-6):
                raise SystemExit(
                    f"{name}: {cut.image.width} px for {cut.rect[2]} design px"
                )

    (HERE / "art.json").write_text(json.dumps(art, indent=1) + "\n")
    for name, entry in art.items():
        print(f"{name}: {entry}")
    print("kinds:", {cid: character_kind(index, cid) for cid in texts})


if __name__ == "__main__":
    main()
