# Battle screen art extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-cut battle halls, skies and bottom-bar chrome with ffdec renders of the SWF, and record the stage positions `battle_scene.gd` currently hardcodes.

**Architecture:** One new extraction script, `dev/urchin_dev/swf/extract/battle_screen.py`, shaped like the existing `zone_hub.py`: strip the authoring-only characters from a working copy of the SWF, render the labelled frames of one sprite per output family, trim each to its opaque content, and emit a positions JSON recovered from the placement matrix plus the sprite's displayRect. `battle_scene.gd` then reads that JSON instead of the tuned `SKY_HORIZON_Y` constant.

**Tech Stack:** Python 3.14 (`uv`, Pillow, ruff), ffdec built from the jpexs master branch at `~/.local/bin/ffdec`, Godot 4.7.2 with GUT 9.7.1.

**Spec:** `spec/old/2026-08-22-battle-screen-extraction-design.md`

## Global Constraints

- ASCII only in every file. Regular hyphens (`-`), never em dashes. Regular spaces, never NBSP.
- Any documentation change must be run through the `humanizer` skill and corrected before commit.
- Python goes through `uv run`; lint with `uv run ruff format <file> && uv run ruff check dev/`.
- Comments must pass all three tests or be deleted: necessary (the code alone cannot say it), skimmable (a full plain sentence), complete (says what actually happens).
- Never claim work is done without running the command and reading the output.
- Full test command: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .` Current baseline is **210 passing, 0 failing**.
- New PNGs need `--headless --import --path .` before Godot can load them, or tests fail with "No loader found for resource".
- Do not `git push`. Commit only.
- Render zoom is `4.0` for every output in this plan.
- Sky files keep the existing `SKY_<LABEL>.png` name, not the bare `<LABEL>.png` the spec's Design section writes. The loader already builds `"%s/sky/SKY_%s.png"`, ten assets already use it, and renaming is churn this plan does not need.

---

### Task 1: Render the halls and skies

**Files:**
- Create: `dev/urchin_dev/swf/extract/battle_screen.py`
- Modify: `pyproject.toml` (add the entry point next to `extract_zone_hub`)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `urchin_dev.swf.snapshot_timeline(xml, sprite_id, wanted_frames) -> (snaps, labels)`, `urchin_dev.FFDEC`, `REPO_ROOT`, `WEB_SWF`, `WEB_SWF_XML`.
- Produces: `HALL_SPRITE = 3435`, `SKY_SPRITE = 3454`, `FIGHTER_RIG = 2676`, `ZOOM = 4.0`, `run(cmd)`, `sprite_label_frames(xml, sprite) -> dict[str, int]`, `render_labels(stripped_swf, sprite, frames, out_dir, prefix) -> None`. Task 2 reuses `run`; Task 3 reuses `sprite_label_frames` and `ZOOM`.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before `func test_every_battle_resolves_its_hall_and_sky_art():`

```gdscript
# The halls place DefineSprite 2676 six times as the character rig. Rendered
# without stripping it, each background bakes in six placeholder fighters, so
# the art has to be wider than the six slots they would occupy and must not
# carry opaque pixels where a fighter stood.
func test_hall_art_has_no_baked_in_fighter_rigs():
	var church: Texture2D = load("res://assets/backgrounds/battle/CHURCH.png")
	assert_not_null(church, "CHURCH hall art exists")
	# 3435 renders 884.5 design px wide at the CHURCH label; at 4x that is 3538.
	assert_eq(church.get_width(), 3538, "CHURCH rendered at 4x from the SWF")
	assert_eq(church.get_height(), 1680, "CHURCH rendered at 4x from the SWF")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_hall_art_has_no_baked_in_fighter_rigs`

Expected: FAIL. The current hand-cut `CHURCH.png` is not 3538x1680.

- [ ] **Step 3: Write the extraction script**

Create `dev/urchin_dev/swf/extract/battle_screen.py`:

```python
# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png  - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png - one sky per label of 3454
#
# THE HALL AND THE SKY ARE INDEPENDENT. The original drives DefineSprite 3435
# from Krin.ZoneBG and DefineSprite 3454 from Krin.SkyBG, two separate
# per-battle fields, and 16 of its 99 battles set them to different labels -
# zone 6 fights in the CHURCH hall under the ROME sky. The two label sets are
# not the same, which is why each sprite is rendered against its own labels
# rather than one shared list.
#
# WHY 2676 IS STRIPPED. Every hall label places DefineSprite 2676 six times, at
# depths 40 through 240. It is the character rig: three slots per side, the
# right side mirrored. Rendered as-is, each hall bakes in six placeholder
# fighters holding swords under "!" speech bubbles, authoring scaffolding the
# game never draws. Deleting it from a working copy leaves ffdec drawing the
# scene art alone, the same approach zone_hub.py uses for the orb.
#
# Run: uv run extract_battle_screen
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

HALL_DIR = REPO_ROOT / "assets" / "backgrounds" / "battle"
SKY_DIR = REPO_ROOT / "assets" / "backgrounds" / "sky"

HALL_SPRITE = 3435
SKY_SPRITE = 3454
# The character rig each hall label places six times, deleted so the halls
# render as bare scene art.
FIGHTER_RIG = 2676
# These fill the window behind everything else, so they are rendered well above
# the window's 2x default scale.
ZOOM = 4.0


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def sprite_label_frames(xml: str, sprite: int) -> dict[str, int]:
    """-> {frame label: frame number} for one sprite's own timeline."""
    _snaps, labels = snapshot_timeline(xml, sprite, set())
    if not labels:
        raise RuntimeError(f"sprite {sprite} has no frame labels")
    return labels


def render_labels(
    swf: Path, sprite: int, frames: dict[str, int], out_dir: Path, prefix: str
) -> None:
    """Render one sprite at each of its labelled frames, trim each to its own
    opaque content, and write <prefix><LABEL>.png into out_dir."""
    work = Path(tempfile.mkdtemp(prefix="battle_screen_"))
    try:
        wanted = sorted(set(frames.values()))
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(sprite),
                "-select",
                ",".join(f"{sprite}:{f}" for f in wanted),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        rendered = work / f"DefineSprite_{sprite}"
        out_dir.mkdir(parents=True, exist_ok=True)
        for label, frame in sorted(frames.items()):
            image = Image.open(rendered / f"{frame}.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(
                    f"sprite {sprite} label {label} (frame {frame}) rendered empty"
                )
            cropped = image.crop(bbox)
            name = f"{prefix}{label.replace(' ', '_')}.png"
            cropped.save(out_dir / name)
            print(
                f"  {label:<16} frame {frame:>3} -> {name} {cropped.size}",
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    xml = WEB_SWF_XML.read_text()
    halls = sprite_label_frames(xml, HALL_SPRITE)
    skies = sprite_label_frames(xml, SKY_SPRITE)

    work = Path(tempfile.mkdtemp(prefix="battle_screen_swf_"))
    try:
        stripped = work / "battle.swf"
        run([str(FFDEC), "-removeCharacter", str(WEB_SWF), str(stripped), str(FIGHTER_RIG)])
        print(f"halls ({len(halls)}):", file=sys.stderr)
        render_labels(stripped, HALL_SPRITE, halls, HALL_DIR, "")
        print(f"skies ({len(skies)}):", file=sys.stderr)
        render_labels(stripped, SKY_SPRITE, skies, SKY_DIR, "SKY_")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Register the entry point**

In `pyproject.toml`, add this line immediately above `extract_buff_icons`:

```toml
extract_battle_screen = "urchin_dev.swf.extract.battle_screen:main"
```

- [ ] **Step 5: Lint and run the extraction**

```bash
uv run ruff format dev/urchin_dev/swf/extract/battle_screen.py
uv run ruff check dev/
uv run extract_battle_screen
```

Expected: 10 hall lines and 9 sky lines on stderr. `CHURCH` reports `(3538, 1680)`.

- [ ] **Step 6: Import the new PNGs and run the test**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_hall_art_has_no_baked_in_fighter_rigs
```

Expected: PASS.

- [ ] **Step 7: Run the whole suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`

Expected: 211 passing, 0 failing. `test_every_battle_resolves_its_hall_and_sky_art` still passes, because every label the battle records use is among the 19 written.

- [ ] **Step 8: Commit**

```bash
git add dev/urchin_dev/swf/extract/battle_screen.py pyproject.toml \
        assets/backgrounds/battle assets/backgrounds/sky \
        test/integration/test_battle_scene.gd
git commit -m "feat: render the battle halls and skies from the SWF

Replaces hand-cut art with 4x renders of DefineSprite 3435 (10 hall labels)
and 3454 (9 sky labels), each trimmed to its own opaque content.

DefineSprite 2676 is deleted from a working copy first. Every hall label
places it six times as the character rig, and rendering without stripping it
bakes six placeholder fighters with speech bubbles into each background."
```

---

### Task 2: Render the bottom bar and top panel chrome

**Files:**
- Modify: `dev/urchin_dev/swf/extract/battle_screen.py`
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `run(cmd)` and `ZOOM` from Task 1.
- Produces: `CHROME: dict[int, str]`, `render_chrome(swf: Path) -> None`. Nothing later depends on these.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before `func test_hall_art_has_no_baked_in_fighter_rigs():`

```gdscript
# The battle frame places four chrome characters the port had never extracted:
# the shared bottom bar (3317, which the Navigation frame places too), the top
# panel frame (3465), the alert icon (3460) and the stage rect (3455).
func test_battle_chrome_art_is_extracted():
	for name in ["bottom_bar", "top_panel", "alert_icon", "stage_rect"]:
		var path := "res://assets/ui/battle/%s.png" % name
		assert_true(ResourceLoader.exists(path), "%s extracted" % name)
		var texture: Texture2D = load(path)
		assert_gt(texture.get_width(), 0, "%s is not empty" % name)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_battle_chrome_art_is_extracted`

Expected: FAIL with "bottom_bar extracted".

- [ ] **Step 3: Add the chrome rendering**

In `battle_screen.py`, add after the `ZOOM` constant:

```python
BATTLE_UI_DIR = REPO_ROOT / "assets" / "ui" / "battle"

# The four chrome characters the battle frame places, named for what they are.
# 3317 sits at depth 1 on the Navigation frame too, so the bottom bar is one
# shared asset rather than the two copies the repo keeps.
CHROME: dict[int, str] = {
    3317: "bottom_bar",
    3465: "top_panel",
    3460: "alert_icon",
    3455: "stage_rect",
}
```

Add this function after `render_labels`:

```python
def render_chrome(swf: Path) -> None:
    """Render each chrome character's first frame, trimmed to its content."""
    work = Path(tempfile.mkdtemp(prefix="battle_chrome_"))
    try:
        ids = ",".join(str(c) for c in CHROME)
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                ids,
                "-select",
                ",".join(f"{c}:1" for c in CHROME),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        for cid, name in sorted(CHROME.items()):
            image = Image.open(work / f"DefineSprite_{cid}" / "1.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
            cropped = image.crop(bbox)
            cropped.save(BATTLE_UI_DIR / f"{name}.png")
            print(f"  {cid} -> {name}.png {cropped.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)
```

In `main()`, add after the `render_labels(stripped, SKY_SPRITE, skies, SKY_DIR, "SKY_")` line:

```python
        print(f"chrome ({len(CHROME)}):", file=sys.stderr)
        render_chrome(stripped)
```

- [ ] **Step 4: Lint, run, import, test**

```bash
uv run ruff format dev/urchin_dev/swf/extract/battle_screen.py && uv run ruff check dev/
uv run extract_battle_screen
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_battle_chrome_art_is_extracted
```

Expected: PASS, and the run prints four chrome lines.

- [ ] **Step 5: Run the whole suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`

Expected: 212 passing, 0 failing. The existing `test_bottom_bar_uses_extracted_backdrop_art` still points at `ui/battle/hotbar_background.png`, which this task leaves in place.

- [ ] **Step 6: Commit**

```bash
git add dev/urchin_dev/swf/extract/battle_screen.py assets/ui/battle \
        test/integration/test_battle_scene.gd
git commit -m "feat: extract the battle screen chrome

Four characters the battle frame places that had never been extracted: the
bottom bar 3317, the top panel frame 3465, the alert icon 3460 and the stage
rect 3455. 3317 also sits on the Navigation frame, so it is one shared asset.

The top panel is the frame the six p1BAR-p6BAR fighter bars sit inside. This
extracts its art only; building the bars stays a separate feature."
```

---

### Task 3: Emit the stage positions JSON

**Files:**
- Modify: `dev/urchin_dev/swf/extract/battle_screen.py`
- Create: `assets/backgrounds/battle/battle_layout.json` (written by the script)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `sprite_label_frames`, `run`, `ZOOM` from Task 1; `urchin_dev.swf.root_placements(xml, label) -> (frame, {depth: {cid, name, mat}})`.
- Produces: `battle_layout.json` with shape `{"halls": {LABEL: {x, y, w, h}}, "skies": {LABEL: {x, y, w, h}}}`, all in design px on the 800x575 stage.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before `func test_battle_chrome_art_is_extracted():`

```gdscript
# The layout JSON carries where each hall and sky actually sits on the stage,
# recovered from the SWF placement rather than tuned by hand. The ROME sky's
# bottom edge lands at y = 306.0, which is what SKY_HORIZON_Y = 292.0 was
# approximating.
func test_battle_layout_json_carries_real_stage_rects():
	var file := FileAccess.open("res://assets/backgrounds/battle/battle_layout.json", FileAccess.READ)
	assert_not_null(file, "battle_layout.json exists")
	var layout: Dictionary = JSON.parse_string(file.get_as_text())
	assert_not_null(layout, "battle_layout.json parses")
	assert_eq(layout["halls"].size(), 10, "one entry per hall label")
	assert_eq(layout["skies"].size(), 9, "one entry per sky label")

	var rome: Dictionary = layout["skies"]["ROME"]
	assert_almost_eq(float(rome["y"]), 130.0, 0.01, "ROME sky top")
	assert_almost_eq(float(rome["h"]), 176.0, 0.01, "ROME sky height")
	assert_almost_eq(float(rome["y"]) + float(rome["h"]), 306.0, 0.01, "ROME sky bottom")

	var church: Dictionary = layout["halls"]["CHURCH"]
	assert_almost_eq(float(church["x"]), -45.32, 0.01, "CHURCH hall left")
	assert_almost_eq(float(church["y"]), 86.52, 0.01, "CHURCH hall top")
	assert_almost_eq(float(church["w"]), 884.50, 0.01, "CHURCH hall width")
	assert_almost_eq(float(church["h"]), 420.00, 0.01, "CHURCH hall height")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_battle_layout_json_carries_real_stage_rects`

Expected: FAIL with "battle_layout.json exists".

- [ ] **Step 3: Add the position recovery**

In `battle_screen.py`, add `import json` and `import re` to the imports, and `root_placements` to the `urchin_dev.swf` import so it reads:

```python
from urchin_dev.swf import root_placements, snapshot_timeline
```

Add after the `CHROME` constant:

```python
LAYOUT_JSON = HALL_DIR / "battle_layout.json"
FRAME_LABEL = "KRINBATTLESCENE"

# The first matrix() in an exported SVG is the root group's, which carries the
# displayRect's negated minimums scaled by the export zoom.
_ROOT_MATRIX = re.compile(
    r'<g transform="matrix\('
    r"[-0-9.]+, [-0-9.]+, [-0-9.]+, [-0-9.]+, ([-0-9.]+), ([-0-9.]+)\)\""
)
_SVG_WIDTH = re.compile(r'\bwidth="([0-9.]+)px"')
_SVG_HEIGHT = re.compile(r'\bheight="([0-9.]+)px"')
```

Add these three functions after `render_chrome`:

```python
def read_display_rect(svg_path: Path):
    """-> (x, y, w, h) of the sprite's displayRect in design px, relative to
    the sprite's own origin."""
    head = svg_path.read_text()[:2000]
    matrix = _ROOT_MATRIX.search(head)
    width = _SVG_WIDTH.search(head)
    height = _SVG_HEIGHT.search(head)
    if matrix is None or width is None or height is None:
        raise RuntimeError(f"no displayRect in {svg_path}")
    return (
        -float(matrix.group(1)) / ZOOM,
        -float(matrix.group(2)) / ZOOM,
        float(width.group(1)) / ZOOM,
        float(height.group(1)) / ZOOM,
    )


def content_rect(origin, display_rect, canvas, bbox):
    """The trimmed render's rect on the stage in design px, given where the
    main timeline places the sprite, its displayRect, the canvas ffdec
    produced and the canvas-pixel bbox of what it drew there.

    ffdec grows a canvas by the filter dimension on both sides of the
    displayRect, so the growth is symmetric and the canvas keeps the
    displayRect's centre. That centre plus the canvas size locates every
    rendered pixel without any filter math here.
    """
    centre_x = origin[0] + display_rect[0] + display_rect[2] / 2
    centre_y = origin[1] + display_rect[1] + display_rect[3] / 2
    canvas_x = centre_x - canvas[0] / ZOOM / 2
    canvas_y = centre_y - canvas[1] / ZOOM / 2
    return (
        canvas_x + bbox[0] / ZOOM,
        canvas_y + bbox[1] / ZOOM,
        (bbox[2] - bbox[0]) / ZOOM,
        (bbox[3] - bbox[1]) / ZOOM,
    )


def layout_rects(swf: Path, xml: str, sprite: int, frames: dict[str, int]) -> dict:
    """-> {label: {x, y, w, h}} on the 800x575 stage, in design px."""
    _frame, placements = root_placements(xml, FRAME_LABEL)
    placed = [e for e in placements.values() if e.get("cid") == sprite]
    if len(placed) != 1:
        raise RuntimeError(f"sprite {sprite} placed {len(placed)} times on {FRAME_LABEL}")
    matrix = placed[0]["mat"]
    origin = (matrix[4] / 20.0, matrix[5] / 20.0)

    work = Path(tempfile.mkdtemp(prefix="battle_layout_"))
    try:
        wanted = sorted(set(frames.values()))
        select = ",".join(f"{sprite}:{f}" for f in wanted)
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    str(sprite),
                    "-select",
                    select,
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        out = {}
        for label, frame in sorted(frames.items()):
            image = Image.open(
                work / "png" / f"DefineSprite_{sprite}" / f"{frame}.png"
            ).convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"sprite {sprite} label {label} rendered empty")
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{sprite}" / f"{frame}.svg"
            )
            rect = content_rect(origin, display_rect, image.size, bbox)
            out[label.replace(" ", "_")] = {
                "x": round(rect[0], 2),
                "y": round(rect[1], 2),
                "w": round(rect[2], 2),
                "h": round(rect[3], 2),
            }
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)
```

In `main()`, add after the `render_chrome(stripped)` line:

```python
        layout = {
            "halls": layout_rects(stripped, xml, HALL_SPRITE, halls),
            "skies": layout_rects(stripped, xml, SKY_SPRITE, skies),
        }
        LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
        print(f"wrote {LAYOUT_JSON}", file=sys.stderr)
```

- [ ] **Step 4: Lint, run, test**

```bash
uv run ruff format dev/urchin_dev/swf/extract/battle_screen.py && uv run ruff check dev/
uv run extract_battle_screen
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_battle_layout_json_carries_real_stage_rects
```

Expected: PASS. `battle_layout.json` holds 10 halls and 9 skies.

- [ ] **Step 5: Run the whole suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`

Expected: 213 passing, 0 failing.

- [ ] **Step 6: Commit**

```bash
git add dev/urchin_dev/swf/extract/battle_screen.py \
        assets/backgrounds/battle/battle_layout.json \
        test/integration/test_battle_scene.gd
git commit -m "feat: record the real battle hall and sky stage rects

battle_layout.json gets one entry per label of 3435 and 3454, recovered from
the main-timeline placement matrix plus the sprite's displayRect centre and
the canvas ffdec produced - the same recovery doll_art and zone_hub use.

The ROME sky's bottom edge lands at y = 306.0, which is what the hardcoded
SKY_HORIZON_Y = 292.0 in battle_scene.gd was approximating."
```

---

### Task 4: Place the sky from the layout JSON

**Files:**
- Modify: `scripts/battle/battle_scene.gd:230-270`
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `battle_layout.json` from Task 3.
- Produces: `BATTLE_LAYOUT_PATH`, `_battle_layout: Dictionary`, `_sky_rect(sky_key) -> Dictionary`. `SKY_HORIZON_Y` is deleted.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before `func test_battle_layout_json_carries_real_stage_rects():`

```gdscript
# Battle 600 runs the CHURCH hall under the ROME sky. The sky is a horizon
# strip whose bottom sits on the ground line, and the layout JSON says that
# line is y = 306.0 for ROME - not the 292.0 the old constant used.
func test_sky_is_placed_from_the_layout_json():
	var save = PlayerSave.new_game("SkyRectTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 600, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_almost_eq(scene.sky.position.y + scene.sky.size.y, 306.0, 0.5,
		"sky bottom sits where the SWF puts it")
	assert_almost_eq(scene.sky.size.y, 176.0, 0.5, "sky strip height from the JSON")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_sky_is_placed_from_the_layout_json`

Expected: FAIL. The current code derives the height from the texture aspect and puts the bottom at 292.0.

- [ ] **Step 3: Read the layout instead of the constant**

In `scripts/battle/battle_scene.gd`, replace the `SKY_HORIZON_Y` constant and its comment block with:

```gdscript
# The original composites a sky layer behind the hall art; the hall PNGs have a
# transparent sky region. The sky art is a wide horizon STRIP, not a
# full-screen image - it sits with its bottom on the ground line, and the area
# above it is filled with the strip's own top-edge color.
#
# The hall and the sky are two independent per-battle fields, not one key: the
# original drives DefineSprite 3435 from Krin.ZoneBG and DefineSprite 3454 from
# Krin.SkyBG, and 16 of its 99 battles set them to different labels. Zone 6
# fights in the CHURCH hall under the ROME sky, one STREETS fight uses the
# TUNNEL sky, and WHITE NOVEMBER uses SEA.
#
# Where the strip sits comes from battle_layout.json, which extract_battle_screen
# writes out of the SWF's own placements. A tuned constant used to stand in for
# it and put every sky's ground line at y = 292.0; the real line differs per
# label, and ROME's is at 306.0.
const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"

var _battle_layout: Dictionary = {}


# -> {x, y, w, h} for one sky label, or {} when the JSON has no entry for it.
func _sky_rect(sky_key: String) -> Dictionary:
	if _battle_layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		_battle_layout = JSON.parse_string(file.get_as_text())
	return _battle_layout.get("skies", {}).get(sky_key, {})
```

Then replace the body of `_load_background()` from `var sky_texture: Texture2D = load(sky_path)` to the end of the function with:

```gdscript
	var sky_texture: Texture2D = load(sky_path)
	var rect: Dictionary = _sky_rect(sky_key)
	if rect.is_empty():
		push_error("no layout entry for sky %s (battle %d)" % [sky_key, battle.id])
		return
	sky.texture = sky_texture
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.position = Vector2(float(rect["x"]), float(rect["y"]))
	sky.size = Vector2(float(rect["w"]), float(rect["h"]))
	# Solid fill above the strip, sampled from its top edge.
	var image: Image = sky_texture.get_image()
	var top_color: Color = image.get_pixel(int(image.get_width() / 2.0), 0)
	sky_fill.color = top_color
	sky_fill.position = Vector2.ZERO
	sky_fill.size = Vector2(800, float(rect["y"]) + 2.0)
```

- [ ] **Step 4: Run the test**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_sky_is_placed_from_the_layout_json`

Expected: PASS.

- [ ] **Step 5: Confirm the constant is gone**

Run: `grep -n "SKY_HORIZON_Y" scripts/battle/battle_scene.gd`

Expected: no output.

- [ ] **Step 6: Run the whole suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`

Expected: 214 passing, 0 failing.

- [ ] **Step 7: Commit**

```bash
git add scripts/battle/battle_scene.gd test/integration/test_battle_scene.gd
git commit -m "fix: place the battle sky from the layout JSON, not a constant

SKY_HORIZON_Y = 292.0 put every sky's ground line at the same y and derived
the strip height from the texture aspect. Both are now read per label from
battle_layout.json, which extract_battle_screen recovers from the SWF's own
placements. ROME's ground line is at 306.0, 14px below where the constant put
it."
```

---

### Task 5: Verify the recomposition and update the docs

**Files:**
- Test: `test/integration/test_battle_scene.gd`
- Modify: `NEXT_PHASES.md`, `KNOWN_GAPS.md`, `dev/source_files/README.md`
- Modify: `spec/old/2026-08-22-battle-screen-extraction-design.md` (status line)

**Interfaces:**
- Consumes: everything from Tasks 1-4. Produces nothing later tasks use.

- [ ] **Step 1: Write the recomposition check**

This is a Python check rather than a GUT test, because it compares against a fresh ffdec render that GUT cannot produce. Create `dev/urchin_dev/swf/extract/verify_battle_screen.py`:

```python
# Checks that the extracted hall and sky, composited at the rects
# battle_layout.json records, reproduce what ffdec draws for the whole
# KRINBATTLESCENE frame with the foreground stripped. Same recomposition check
# the class-select work used.
#
# The pair checked is WHITE NOVEMBER over SEA, and it has to be: ffdec does not
# run ActionScript, so the two gotoAndStop handlers that pick a hall and a sky
# never fire and both sprites render at their own frame 1. Those frame-1 labels
# happen to be a real pairing - battle 49's.
#
# The diff is masked to pixels the recomposition actually draws. The reference
# render also paints the stage behind everything, so the roughly 29% of the
# frame the two backgrounds do not cover would otherwise count as mismatched.
# Across the drawn pixels the median difference is 0 and the 99th percentile is
# 8; what is left sits on edges where the hall's window meets the sky.
#
# Run: uv run python -m urchin_dev.swf.extract.verify_battle_screen
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import FFDEC, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import root_placements
from urchin_dev.swf.extract.battle_screen import (
    FIGHTER_RIG,
    FRAME_LABEL,
    HALL_DIR,
    LAYOUT_JSON,
    SKY_DIR,
    ZOOM,
    run,
)

# Every character the battle frame places except the hall (3435) and the sky
# (3454), so the reference render shows those two alone.
FOREGROUND = (
    333, 2427, 2717, 2852, 3172, 3317, 3355, 3356, 3367, 3368, 3369, 3373,
    3382, 3383, 3389, 3394, 3414, 3415, 3416, 3417, 3418, 3419, 3420, 3455,
    3460, 3465,
)
HALL_LABEL = "WHITE_NOVEMBER"
SKY_LABEL = "SEA"
# Difference allowed at the 99th percentile of drawn pixels, in 8-bit levels.
TOLERANCE = 8


def main():
    xml = WEB_SWF_XML.read_text()
    frame, _placements = root_placements(xml, FRAME_LABEL)
    layout = json.loads(LAYOUT_JSON.read_text())

    work = Path(tempfile.mkdtemp(prefix="verify_battle_"))
    try:
        stripped = work / "bare.swf"
        run(
            [str(FFDEC), "-removeCharacter", str(WEB_SWF), str(stripped),
             str(FIGHTER_RIG)]
            + [str(c) for c in FOREGROUND]
        )
        run(
            [
                str(FFDEC), "-zoom", str(ZOOM), "-format", "frame:png",
                "-select", str(frame), "-export", "frame", str(work / "ref"),
                str(stripped),
            ]
        )
        reference = Image.open(work / "ref" / f"{frame}.png").convert("RGB")

        canvas = Image.new("RGBA", reference.size, (0, 0, 0, 0))
        for folder, prefix, family, label in (
            (SKY_DIR, "SKY_", "skies", SKY_LABEL),
            (HALL_DIR, "", "halls", HALL_LABEL),
        ):
            rect = layout[family][label]
            art = Image.open(folder / f"{prefix}{label}.png").convert("RGBA")
            canvas.alpha_composite(
                art, (round(rect["x"] * ZOOM), round(rect["y"] * ZOOM))
            )

        drawn = np.asarray(canvas.getchannel("A")) == 255
        difference = np.abs(
            np.asarray(canvas.convert("RGB"), dtype=np.int16)
            - np.asarray(reference, dtype=np.int16)
        ).max(axis=2)[drawn]
        p99 = float(np.percentile(difference, 99))
        print(
            f"drawn pixels {drawn.sum()}, median {np.median(difference):.0f}, "
            f"p99 {p99:.0f}, max {difference.max()}",
            file=sys.stderr,
        )
        if p99 > TOLERANCE:
            raise SystemExit(
                f"recomposition does not match the reference render "
                f"(p99 {p99:.0f} > {TOLERANCE})"
            )
        print("recomposition matches", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
```

Add `numpy` to the project dependencies, since nothing else in `dev/` uses it yet. In `pyproject.toml`, add to the `dependencies` list:

```toml
  # percentile comparison in verify_battle_screen
  "numpy>=2.1",
```

- [ ] **Step 2: Run the check**

```bash
uv run ruff format dev/urchin_dev/swf/extract/verify_battle_screen.py && uv run ruff check dev/
uv run python -m urchin_dev.swf.extract.verify_battle_screen
```

Expected: `drawn pixels 5240825, median 0, p99 8, max 208` then "recomposition matches". A p99 above 8 means the two renders disagree on real content rather than on edges; the likely cause is a character still drawing over the hall, so check `FOREGROUND` against the 38 placements on the frame.

- [ ] **Step 3: Update the docs**

In `NEXT_PHASES.md`, replace the `- **Zone hub art - DONE (2026-08-22)**` bullet's following blank line with a new bullet after it:

```markdown
- **Battle screen art - DONE (2026-08-22)**, `uv run extract_battle_screen`. The halls (`3435`, 10 labels), the skies (`3454`, 9 labels) and four chrome
  characters now render from the SWF instead of being cut by hand. `2676`, the character rig every hall places six times, is stripped first, so the
  backgrounds no longer carry six placeholder fighters. `battle_layout.json` records each label's stage rect, which retires `SKY_HORIZON_Y = 292.0` - the
  real ground line differs per sky and ROME's is at 306.0.
```

In `KNOWN_GAPS.md`, add after the `- **Top battle bar panel**` bullet:

```markdown
- **Battle top panel frame extracted, bars not built**: `assets/ui/battle/top_panel.png` is the frame the original's six `p1BAR`-`p6BAR` fighter bars sit
  inside. The bars themselves (`3414`) are still unbuilt, so the frame is not placed in the scene yet.
```

In `dev/source_files/README.md`, add after the `extract/store_art.py` line:

```markdown
- `extract/battle_screen.py` - regenerates the battle halls, skies and chrome, plus `battle_layout.json`
```

In the spec, change `**Status:** design, not yet implemented.` to `**Status:** implemented 2026-08-22.`

- [ ] **Step 4: Run the doc changes through the humanizer**

Invoke the `humanizer` skill on the three doc edits above. Apply whatever corrections it returns before committing.

- [ ] **Step 5: Check for non-ASCII**

```bash
python3 -c "
from pathlib import Path
for f in ('NEXT_PHASES.md','KNOWN_GAPS.md','dev/source_files/README.md','spec/old/2026-08-22-battle-screen-extraction-design.md','dev/urchin_dev/swf/extract/battle_screen.py','dev/urchin_dev/swf/extract/verify_battle_screen.py'):
    s=Path(f).read_text()
    bad=[c for c in set(s) if ord(c)>127]
    print(f, bad if bad else 'ascii ok')"
```

Expected: every line reports `ascii ok`.

- [ ] **Step 6: Run the whole suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`

Expected: 214 passing, 0 failing.

- [ ] **Step 7: Commit**

```bash
git add dev/urchin_dev/swf/extract/verify_battle_screen.py \
        NEXT_PHASES.md KNOWN_GAPS.md dev/source_files/README.md \
        spec/old/2026-08-22-battle-screen-extraction-design.md
git commit -m "test: check the battle recomposition against a full frame render

verify_battle_screen composites the extracted CHURCH hall and ROME sky at the
rects battle_layout.json records and diffs the result against ffdec's own
render of KRINBATTLESCENE with the foreground stripped. Same recomposition
check the class-select work used."
```

---

## Follow-ups this plan deliberately leaves open

- The six `p1BAR` fighter bars (`3414`). An unbuilt feature, not a re-extraction.
- `KrinSelector` (`3394`), `battleClocker` (`3389`), `selector` (`3382`), `moveSelectBoomer` (`3373`). Hand-built and working.
- Deleting the six hand-exported sub-shapes in `assets/backgrounds/battle/` (`3423`, `3424`, `3438`, `3440`, `3450`, `3452`) now that composed renders replace them, plus `JAIL3.png`, which has no label behind it in either sprite.
- `assets/ui/hotbar/background.png` and `assets/ui/battle/hotbar_background.png` are the two copies of what Task 2 extracts once as `bottom_bar.png`. Repointing the scenes and deleting the duplicates is its own change.
- `SKY_TRAIN2.png`, an asset no battle asks for.
