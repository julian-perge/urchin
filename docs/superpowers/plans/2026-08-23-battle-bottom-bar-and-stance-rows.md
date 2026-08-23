# Battle bottom bar and stance rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** re-render the battle bottom bar without the two placeholder member
bars baked into it, extract the stance button art those bars are made of, and
give the port's existing `StanceRow` that art instead of the coloured
rectangles it draws today.

**Architecture:** `battle_screen.py` gains one more character in its
`-removeCharacter` strip, so the bar renders bare, and three new outputs: the
five stance icons, the two overlay states, and the member bar's backing. It
also records the bar's internal layout in `battle_layout.json` so the numbers
live where they were measured. On the Godot side `stance_row.tscn` swaps its
five plain `Button`s for `TextureButton`s with a cover child, and
`battle_scene.gd` stops building a `StyleBoxFlat` colour table.

**Tech Stack:** Python 3 with Pillow and the ffdec CLI for extraction, Godot
4.7.2 with GUT 9.7.1 for the port and its tests.

**Spec:** `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`

## Global Constraints

- ASCII only in every file touched. Regular hyphens, never em dashes. Regular
  spaces, never NBSP.
- `uv run ruff format --check <file>` and `uv run ruff check dev/` must pass.
  Re-run the check as the last thing before `git commit`: a Rider editor hook
  on this machine reformats Python on save and has reintroduced drift after a
  clean ruff run twice in this repo.
- Comments must pass three tests or be deleted: necessary (the code alone
  cannot say it), skimmable (a full plain sentence, no fragments, no jargon),
  complete (says what actually happens end to end).
- Render zoom stays `ZOOM = 4.0`, matching every other output in the file.
- Every render crops to its alpha bbox and raises `RuntimeError` on an empty
  render, matching `render_labels` and `render_chrome`.
- Never add a clip mask to any strip list. `3317` places two, `3288` at
  `clipDepth="57"` and `3314` at `clipDepth="4"`. Only `3312`, the content, is
  stripped. See the clip mask rule in `CLAUDE.md`.
- After writing anything under `assets/`, run the Godot import pass:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .`
  Without it, tests fail with "No loader found for resource".
- Full suite before every commit:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
  The suite's total assert count drifts run to run because
  `test_battle_runner.gd::test_misses_are_move_events_not_a_separate_type`
  runs battle 51 with unseeded RNG. Pass and fail counts are stable; report
  those and ignore the assert drift.
- Commit `.png.import` and `.uid` sidecars alongside any new asset or script.
  Forgetting them has broken a fresh checkout at least six times.

---

## File Structure

| File | Responsibility |
|---|---|
| `dev/urchin_dev/swf/extract/battle_screen.py` | Modify. Strips `3312` for the bar; adds the stance art renders and the `stance_row` layout section. |
| `assets/ui/battle/bottom_bar.png` | Regenerated bare. |
| `assets/ui/battle/stance/*.png` | New. Five icons, two covers. |
| `assets/ui/battle/member_bar_panel.png` | New. The row backing. |
| `assets/backgrounds/battle/battle_layout.json` | Regenerated, gains `stance_row`. |
| `scenes/battle/stance_row.tscn` | Modify. `TextureButton`s with a cover child, on a panel. |
| `scripts/battle/stance_row.gd` | Modify. Reads the layout, places its children, owns selection. |
| `scripts/battle/battle_scene.gd:599-648` | Modify. Delegates selection to the row, drops the colour table. |
| `test/integration/test_battle_scene.gd` | Modify. Three new tests. |

---

### Task 1: Render the bottom bar without the member bars

**Files:**
- Modify: `dev/urchin_dev/swf/extract/battle_screen.py`
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `run(cmd)`, `FIGHTER_RIG`, `ZOOM`, `render_chrome(swf)`,
  `chrome_rects(swf, xml)` as they already exist.
- Produces: `MEMBER_BARS = 3312`. Nothing later depends on it.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before
`func test_battle_chrome_art_is_extracted():`

```gdscript
# The bottom bar is a render of DefineSprite 3317, which places the member bar
# container at depth 7. Each member bar carries the SWF author's placeholder
# name in a DefineEditText the game fills at runtime, so a bar rendered with
# them in has two rows of white "Thurman McPown" text burned into it. The port
# draws those rows itself with StanceRow, so the art must carry none. White
# text is the only thing on this bar brighter than 0.8 on every channel.
func test_bottom_bar_art_has_no_baked_in_member_bars():
	var texture: Texture2D = load("res://assets/ui/battle/bottom_bar.png")
	var image: Image = texture.get_image()
	var bright := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > 0.8 and pixel.g > 0.8 and pixel.b > 0.8:
				bright += 1
	assert_eq(bright, 0, "no placeholder text baked into the bottom bar")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_bottom_bar_art_has_no_baked_in_member_bars`

Expected: FAIL with `no placeholder text baked into the bottom bar: [727] expected to equal [0]`.

The count is 727 because `bottom_bar.png.import` sets `compress/mode=0`, so
`get_image()` returns the exact pixels rather than a lossy decode.

- [ ] **Step 3: Strip the member bar container**

In `battle_screen.py`, add after the `FIGHTER_RIG` constant and its comment:

```python
# The team member bar container, which 3317 places at depth 7. It holds two
# copies of one member bar, each carrying the SWF author's placeholder name
# "Thurman McPown" in a DefineEditText the game fills at runtime from
# playerKrin<n>.playerName. Rendered as-is the bar bakes in two dead rows. The
# port rebuilds them from scenes/battle/stance_row.tscn instead.
MEMBER_BARS = 3312
```

- [ ] **Step 4: Render the chrome from the stripped copy**

In `main()`, add `MEMBER_BARS` to the existing `-removeCharacter` call:

```python
        stripped = work / "battle.swf"
        run(
            [
                str(FFDEC),
                "-removeCharacter",
                str(WEB_SWF),
                str(stripped),
                str(FIGHTER_RIG),
                str(MEMBER_BARS),
            ]
        )
```

Then move the two chrome lines inside the same `try` block, immediately after
the `layout = {...}` assignment, and replace their comment. Delete the old
block that ran them after the `finally`. The chrome section becomes:

```python
        # The chrome renders from this same stripped copy. 2676 sits nowhere in
        # the four chrome characters' trees so it changes nothing for them, and
        # 3312 has to be gone or the bottom bar bakes in the member bars.
        print(f"chrome ({len(CHROME)}):", file=sys.stderr)
        render_chrome(stripped)
        layout["chrome"] = chrome_rects(stripped, xml)
```

- [ ] **Step 5: Regenerate and import**

```bash
uv run extract_battle_screen
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
```

Expected: `bottom_bar.png` becomes 3091x445, one pixel narrower than the
3092x445 it was, and `battle_layout.json`'s `chrome.bottom_bar.w` moves from
`773.0` to `772.75`. The other three chrome entries and every hall and sky
entry stay unchanged.

- [ ] **Step 6: Run the test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_bottom_bar_art_has_no_baked_in_member_bars`
Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: all pass, 0 failing.

- [ ] **Step 8: Verify formatting, then commit**

```bash
uv run ruff format --check dev/urchin_dev/swf/extract/battle_screen.py
uv run ruff check dev/
git add dev/urchin_dev/swf/extract/battle_screen.py test/integration/test_battle_scene.gd assets/ui/battle/bottom_bar.png assets/backgrounds/battle/battle_layout.json
git commit -m "fix: render the battle bottom bar without the member bars"
```

---

### Task 2: Extract the stance art and record the row layout

**Files:**
- Modify: `dev/urchin_dev/swf/extract/battle_screen.py`
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `run(cmd)`, `ZOOM`, `BATTLE_UI_DIR`, `sprite_label_frames(xml, sprite)`,
  `render_labels(swf, sprite, frames, out_dir, prefix)`, `read_display_rect(svg_path)`,
  `content_rect(origin, display_rect, canvas, bbox)` as they already exist.
- Produces: `STANCE_DIR`, `STANCE_ICONS = 3305`, `STANCE_COVER = 3293`,
  `STANCE_BUTTON = 3306`, `MEMBER_BAR = 3311`, `MEMBER_BAR_PANEL = 3309`,
  `frame_one_placements(xml, sprite) -> dict[int, tuple[int, str, float, float]]`,
  `local_content_rect(swf, sprite) -> tuple[float, float, float, float]`,
  `render_member_bar_panel(swf) -> None`,
  `stance_row_layout(swf, xml) -> dict`, and the `stance_row` section of
  `battle_layout.json`. Task 3 reads that section.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before
`func test_bottom_bar_art_has_no_baked_in_member_bars():`

```gdscript
# One stance button stacks an icon from DefineSprite 3305 under an overlay
# from 3293. 3305's frame labels are _root.agModeNames verbatim, which is also
# the order of Party.AggressionStance, so the file names and the enum line up
# without a translation table.
func test_stance_button_art_is_extracted():
	for label in ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]:
		var path := "res://assets/ui/battle/stance/%s.png" % label
		assert_true(ResourceLoader.exists(path), "%s icon extracted" % label)
		var texture: Texture2D = load(path)
		assert_eq(texture.get_width(), 113, "%s icon is 28.25 design px at 4x" % label)
	for state in ["BLACK", "WHITE"]:
		var path := "res://assets/ui/battle/stance/cover_%s.png" % state
		assert_true(ResourceLoader.exists(path), "cover_%s extracted" % state)
	assert_true(ResourceLoader.exists("res://assets/ui/battle/member_bar_panel.png"),
		"member bar backing extracted")


# The member bar's internal layout is measured off the SWF rather than typed
# into the scene by hand. Offsets are from the bar's own top-left corner.
func test_battle_layout_json_carries_the_stance_row_layout():
	var file := FileAccess.open("res://assets/backgrounds/battle/battle_layout.json", FileAccess.READ)
	assert_not_null(file, "battle_layout.json exists")
	var layout: Dictionary = JSON.parse_string(file.get_as_text())
	var row: Dictionary = layout["stance_row"]
	assert_almost_eq(float(row["bar_size"]["w"]), 285.0, 0.01, "member bar width")
	assert_almost_eq(float(row["bar_size"]["h"]), 31.5, 0.01, "member bar height")
	assert_almost_eq(float(row["button_pitch"]), 32.0, 0.01, "button pitch")
	assert_almost_eq(float(row["row_pitch"]), 37.5, 0.01, "row pitch")
	assert_almost_eq(float(row["button_size"]["w"]), 28.25, 0.01, "button width")
	assert_almost_eq(float(row["button_size"]["h"]), 13.75, 0.01, "button height")
	assert_almost_eq(float(row["first_button"]["x"]), 121.38, 0.01, "first button x")
	assert_almost_eq(float(row["first_button"]["y"]), 8.35, 0.01, "first button y")
	assert_almost_eq(float(row["name_offset"]["x"]), 8.0, 0.01, "name field x")
	assert_almost_eq(float(row["name_offset"]["y"]), 9.75, 0.01, "name field y")
	assert_almost_eq(float(row["art_zoom"]), 4.0, 0.01, "art zoom")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_stance_button_art_is_extracted`
Expected: FAIL with "Phalanx icon extracted".

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_battle_layout_json_carries_the_stance_row_layout`
Expected: FAIL with an invalid index error on `stance_row`.

- [ ] **Step 3: Add the constants**

In `battle_screen.py`, add after the `CHROME` dict:

```python
STANCE_DIR = BATTLE_UI_DIR / "stance"

# The pieces one team member bar is built from. The port draws the bar itself
# out of these rather than extracting it whole, because a faithful texture
# would need one render per stance per selection state and still could not
# carry the player-supplied name. See
# docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md.
#
# 3305 labels its five frames Phalanx, Defensive, Tactical, Aggressive and
# Relentless, which is _root.agModeNames verbatim and also the order of
# Party.AggressionStance in the port. 3293 labels its two BLACK, for a button
# the player has not picked, and WHITE for the one they have; setAG sets all
# five to BLACK and then one to WHITE.
MEMBER_BAR = 3311
STANCE_BUTTON = 3306
STANCE_ICONS = 3305
STANCE_COVER = 3293
MEMBER_BAR_PANEL = 3309

# Matches the whole tag or its closing partner, so a walk can tell a
# self-closing PlaceObject from one wrapping child elements.
_ITEM_TOKENS = re.compile(r"<item\b[^>]*?(/?)>|</item>")
```

Extend the existing import from `urchin_dev.swf` to bring in the two helpers
this task needs:

```python
from urchin_dev.swf import root_placements, snapshot_timeline
from urchin_dev.swf.xml_lib import find_matrix, sprite_body
```

- [ ] **Step 4: Add the placement walker**

Add after `sprite_label_frames`:

```python
def frame_one_placements(xml: str, sprite: int) -> dict[int, tuple[int, str, float, float]]:
    """-> {depth: (characterId, instance name, x, y)} for one sprite's first
    frame, with the translate converted from twips to design px.

    This is the same walk zone_hub.py's orb_layers does. It is written out
    again rather than shared, because the two want different things back and a
    little repetition reads better here than a parameterised helper.
    """
    body = sprite_body(xml, sprite)
    out: dict[int, tuple[int, str, float, float]] = {}
    depth = 0
    start = None
    for token in _ITEM_TOKENS.finditer(body):
        text = token.group(0)
        if text == "</item>":
            depth -= 1
            if depth == 0 and start is not None:
                element = body[start : token.end()]
                cid = re.search(r'characterId="(\d+)"', element)
                place_depth = re.search(r'depth="(\d+)"', element)
                if cid is not None and place_depth is not None:
                    name = re.search(r'name="([^"]*)"', element)
                    matrix = find_matrix(element)
                    out[int(place_depth.group(1))] = (
                        int(cid.group(1)),
                        name.group(1) if name else "",
                        matrix[4] / 20.0,
                        matrix[5] / 20.0,
                    )
                start = None
            continue
        self_closing = bool(token.group(1))
        if depth == 0:
            if 'type="ShowFrameTag"' in text:
                break
            if "PlaceObject" in text and not self_closing:
                start = token.start()
        if not self_closing:
            depth += 1
    return out
```

- [ ] **Step 5: Add the local rect helper**

Add after `content_rect`:

```python
def local_content_rect(swf: Path, sprite: int) -> tuple[float, float, float, float]:
    """-> (x, y, w, h) of a sprite's first frame in design px, relative to the
    sprite's own origin.

    Same recovery as content_rect with the placement origin left at zero,
    because these sprites are nested inside another sprite rather than placed
    on the main timeline, so there is no root placement to read.
    """
    work = Path(tempfile.mkdtemp(prefix="battle_local_rect_"))
    try:
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
                    f"{sprite}:1",
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        image = Image.open(work / "png" / f"DefineSprite_{sprite}" / "1.png").convert(
            "RGBA"
        )
        bbox = image.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"sprite {sprite} rendered empty")
        display_rect = read_display_rect(work / "svg" / f"DefineSprite_{sprite}" / "1.svg")
        return content_rect((0.0, 0.0), display_rect, image.size, bbox)
    finally:
        shutil.rmtree(work, ignore_errors=True)
```

- [ ] **Step 6: Add the panel render**

Add after `render_chrome`:

```python
def render_member_bar_panel(swf: Path) -> None:
    """Draw the dark rounded backing one member bar sits on, trimmed to its
    content. It is a DefineShape rather than a sprite, so this exports a shape
    the way zone_hub.py exports the orb's arcs."""
    work = Path(tempfile.mkdtemp(prefix="battle_member_panel_"))
    try:
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                str(MEMBER_BAR_PANEL),
                "-export",
                "shape",
                str(work),
                str(swf),
            ]
        )
        image = Image.open(work / f"{MEMBER_BAR_PANEL}.png").convert("RGBA")
        bbox = image.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"member bar panel {MEMBER_BAR_PANEL} rendered empty")
        cropped = image.crop(bbox)
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        cropped.save(BATTLE_UI_DIR / "member_bar_panel.png")
        print(
            f"  {MEMBER_BAR_PANEL} -> member_bar_panel.png {cropped.size}",
            file=sys.stderr,
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)
```

- [ ] **Step 7: Add the layout measurement**

Add after `chrome_rects`:

```python
def stance_row_layout(swf: Path, xml: str) -> dict:
    """-> one member bar's internal layout in design px, measured off the SWF.

    Offsets are from the bar's own top-left corner, which is what StanceRow
    needs to place its children. The bar's position on the stage is not
    recorded, because the port puts its rows in BottomBar/StanceHost rather
    than where the original puts them.
    """
    bar = local_content_rect(swf, MEMBER_BAR)
    icon = local_content_rect(swf, STANCE_ICONS)
    inside_bar = frame_one_placements(xml, MEMBER_BAR)
    inside_button = frame_one_placements(xml, STANCE_BUTTON)
    inside_container = frame_one_placements(xml, MEMBER_BARS)

    buttons = sorted(
        (x, y) for cid, _name, x, y in inside_bar.values() if cid == STANCE_BUTTON
    )
    if len(buttons) != 5:
        raise RuntimeError(f"{MEMBER_BAR} places {len(buttons)} stance buttons, want 5")
    names = [(x, y) for c, _n, x, y in inside_bar.values() if c == NAME_FIELD]
    if len(names) != 1:
        raise RuntimeError(f"{MEMBER_BAR} places {len(names)} name fields, want 1")
    pics = [(x, y) for c, _n, x, y in inside_button.values() if c == STANCE_ICONS]
    if len(pics) != 1:
        raise RuntimeError(f"{STANCE_BUTTON} places {len(pics)} icons, want 1")
    rows = sorted(y for c, _n, _x, y in inside_container.values() if c == MEMBER_BAR)
    if len(rows) != 2:
        raise RuntimeError(f"{MEMBER_BARS} places {len(rows)} member bars, want 2")

    return {
        "art_zoom": ZOOM,
        "bar_size": {"w": round(bar[2], 2), "h": round(bar[3], 2)},
        "button_pitch": round(buttons[1][0] - buttons[0][0], 2),
        "button_size": {"w": round(icon[2], 2), "h": round(icon[3], 2)},
        "first_button": {
            "x": round(buttons[0][0] + pics[0][0] + icon[0] - bar[0], 2),
            "y": round(buttons[0][1] + pics[0][1] + icon[1] - bar[1], 2),
        },
        "name_offset": {
            "x": round(names[0][0] - bar[0], 2),
            "y": round(names[0][1] - bar[1], 2),
        },
        "row_pitch": round(rows[1] - rows[0], 2),
    }
```

Add the name field's own id beside the other constants from Step 3:

```python
# The DefineEditText the bar shows the companion's name in. Its initialText is
# the author's placeholder, so only its position is wanted here.
NAME_FIELD = 3308
```

- [ ] **Step 8: Wire the new outputs into main()**

These render from the same `stripped` copy as everything else. Removing 3312
deletes the container, not the characters nested inside it, so 3305, 3293 and
3311 still render from that copy at exactly the sizes they do from the
original. This was checked rather than assumed before the plan was written.

In `main()`, after the existing `render_chrome` and `chrome_rects` lines added
in Task 1 and still inside the `try` block, add:

```python
        print("stance button art:", file=sys.stderr)
        render_labels(
            stripped, STANCE_ICONS, sprite_label_frames(xml, STANCE_ICONS),
            STANCE_DIR, "",
        )
        render_labels(
            stripped, STANCE_COVER, sprite_label_frames(xml, STANCE_COVER),
            STANCE_DIR, "cover_",
        )
        render_member_bar_panel(stripped)
        layout["stance_row"] = stance_row_layout(stripped, xml)
```

- [ ] **Step 9: Regenerate and import**

```bash
uv run extract_battle_screen
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
```

Expected: five icons at 113x55, `cover_BLACK.png` at 111x53, `cover_WHITE.png`
at 133x74, and `member_bar_panel.png` written. `battle_layout.json` gains
`stance_row` with the values Step 1's test asserts.

- [ ] **Step 10: Run the tests to verify they pass**

Run both `-gunit_test_name` commands from Step 2.
Expected: PASS.

- [ ] **Step 11: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: all pass, 0 failing.

- [ ] **Step 12: Verify formatting, then commit**

```bash
uv run ruff format --check dev/urchin_dev/swf/extract/battle_screen.py
uv run ruff check dev/
git add dev/urchin_dev/swf/extract/battle_screen.py test/integration/test_battle_scene.gd assets/ui/battle/stance assets/ui/battle/member_bar_panel.png assets/ui/battle/member_bar_panel.png.import assets/backgrounds/battle/battle_layout.json
git commit -m "feat: extract the stance button art and the member bar layout"
```

---

### Task 3: Draw the stance rows with the real art

**Files:**
- Modify: `scenes/battle/stance_row.tscn`
- Modify: `scripts/battle/stance_row.gd`
- Modify: `scripts/battle/battle_scene.gd:599-648`
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `battle_layout.json`'s `stance_row` section from Task 2, and the
  textures under `assets/ui/battle/stance/`.
- Produces: `StanceRow.setup(unit_name: String) -> void` (unchanged signature),
  `StanceRow.set_selected(mode: int) -> void`,
  `StanceRow.buttons: Array[TextureButton]`, `StanceRow.row_pitch() -> float`.
  `battle_scene.gd`'s `_stance_rows` changes from `party_id -> Array[Button]`
  to `party_id -> StanceRow`.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`, immediately before
`func test_stance_button_art_is_extracted():`

```gdscript
# One WHITE cover among five BLACK ones is how the original shows the picked
# stance: setAG sets every b<i>.COVER to BLACK and then one to WHITE.
func test_stance_row_marks_exactly_one_button_selected():
	var row = load("res://scenes/battle/stance_row.tscn").instantiate()
	add_child_autofree(row)
	row.setup("Veradux")
	row.set_selected(Party.AggressionStance.TACTICAL)

	var selected := 0
	for mode in row.buttons.size():
		var cover: TextureRect = row.buttons[mode].get_node("Cover")
		assert_not_null(cover.texture, "button %d has a cover" % mode)
		if cover.texture.resource_path.ends_with("cover_WHITE.png"):
			selected += 1
			assert_eq(mode, int(Party.AggressionStance.TACTICAL), "the picked one is white")
		else:
			assert_true(cover.texture.resource_path.ends_with("cover_BLACK.png"),
				"button %d is black" % mode)
	assert_eq(selected, 1, "exactly one button reads as selected")


# Each button carries its own stance icon, in Party.AggressionStance order.
func test_stance_row_buttons_carry_the_five_icons():
	var row = load("res://scenes/battle/stance_row.tscn").instantiate()
	add_child_autofree(row)
	row.setup("Veradux")

	var expected := ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
	assert_eq(row.buttons.size(), expected.size(), "five stance buttons")
	for mode in expected.size():
		var texture: Texture2D = row.buttons[mode].texture_normal
		assert_not_null(texture, "button %d has an icon" % mode)
		assert_true(texture.resource_path.ends_with("%s.png" % expected[mode]),
			"button %d shows %s" % [mode, expected[mode]])
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_stance_row_buttons_carry_the_five_icons`
Expected: FAIL. The buttons are plain `Button`s today, so `texture_normal` does
not exist and the call errors.

- [ ] **Step 3: Rewrite the scene**

Replace the whole of `scenes/battle/stance_row.tscn` with:

```
[gd_scene load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/battle/stance_row.gd" id="1_row"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/member_bar_panel.png" id="2_panel"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/stance/Phalanx.png" id="3_m0"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/stance/Defensive.png" id="4_m1"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/stance/Tactical.png" id="5_m2"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/stance/Aggressive.png" id="6_m3"]
[ext_resource type="Texture2D" path="res://assets/ui/battle/stance/Relentless.png" id="7_m4"]

[node name="StanceRow" type="Control"]
mouse_filter = 2
script = ExtResource("1_row")

[node name="Panel" type="TextureRect" parent="."]
layout_mode = 0
texture = ExtResource("2_panel")
expand_mode = 1
stretch_mode = 0
mouse_filter = 2

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
theme_override_font_sizes/font_size = 12
mouse_filter = 2

[node name="Mode0" type="TextureButton" parent="."]
layout_mode = 0
texture_normal = ExtResource("3_m0")
ignore_texture_size = true
stretch_mode = 0
tooltip_text = "Phalanx"

[node name="Cover" type="TextureRect" parent="Mode0"]
layout_mode = 0
expand_mode = 1
stretch_mode = 0
mouse_filter = 2

[node name="Mode1" type="TextureButton" parent="."]
layout_mode = 0
texture_normal = ExtResource("4_m1")
ignore_texture_size = true
stretch_mode = 0
tooltip_text = "Defensive"

[node name="Cover" type="TextureRect" parent="Mode1"]
layout_mode = 0
expand_mode = 1
stretch_mode = 0
mouse_filter = 2

[node name="Mode2" type="TextureButton" parent="."]
layout_mode = 0
texture_normal = ExtResource("5_m2")
ignore_texture_size = true
stretch_mode = 0
tooltip_text = "Tactical"

[node name="Cover" type="TextureRect" parent="Mode2"]
layout_mode = 0
expand_mode = 1
stretch_mode = 0
mouse_filter = 2

[node name="Mode3" type="TextureButton" parent="."]
layout_mode = 0
texture_normal = ExtResource("6_m3")
ignore_texture_size = true
stretch_mode = 0
tooltip_text = "Aggressive"

[node name="Cover" type="TextureRect" parent="Mode3"]
layout_mode = 0
expand_mode = 1
stretch_mode = 0
mouse_filter = 2

[node name="Mode4" type="TextureButton" parent="."]
layout_mode = 0
texture_normal = ExtResource("7_m4")
ignore_texture_size = true
stretch_mode = 0
tooltip_text = "Relentless"

[node name="Cover" type="TextureRect" parent="Mode4"]
layout_mode = 0
expand_mode = 1
stretch_mode = 0
mouse_filter = 2
```

- [ ] **Step 4: Rewrite the script**

Replace the whole of `scripts/battle/stance_row.gd` with:

```gdscript
# stance_row.gd
# One companion's stance-mode row in the battle bottom bar: a name and the
# five aggression-preset buttons. battle_scene.gd instances one per deployed
# companion, positions it, wires each button's press to that companion's party
# id and mode, and calls set_selected() when the stance changes.
#
# The art is the original's own, extracted by dev/urchin_dev/swf/extract/
# battle_screen.py. Every position comes from battle_layout.json's stance_row
# section rather than being typed in here, because the script that measured
# those numbers off the SWF is the only thing that should own them. The
# textures are rendered at art_zoom, so a size in design px is the texture's
# pixel size over that.
extends Control
class_name StanceRow

const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"
const COVER_UNSELECTED: String = "res://assets/ui/battle/stance/cover_BLACK.png"
const COVER_SELECTED: String = "res://assets/ui/battle/stance/cover_WHITE.png"

@onready var name_label: Label = $NameLabel
@onready var panel: TextureRect = $Panel
@onready var buttons: Array[TextureButton] = [$Mode0, $Mode1, $Mode2, $Mode3, $Mode4]

static var _layout: Dictionary = {}


# -> the stance_row section of battle_layout.json, read once per run.
static func layout() -> Dictionary:
	if _layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		var parsed: Dictionary = JSON.parse_string(file.get_as_text())
		_layout = parsed.get("stance_row", {})
	return _layout


# -> how far apart two rows sit, so battle_scene.gd does not carry its own copy.
static func row_pitch() -> float:
	return float(layout().get("row_pitch", 37.5))


func _ready() -> void:
	var rect: Dictionary = layout()
	if rect.is_empty():
		return
	var zoom: float = float(rect["art_zoom"])
	var bar := Vector2(float(rect["bar_size"]["w"]), float(rect["bar_size"]["h"]))
	custom_minimum_size = bar
	size = bar
	panel.size = bar

	name_label.position = Vector2(
		float(rect["name_offset"]["x"]), float(rect["name_offset"]["y"])
	)
	var button_size := Vector2(
		float(rect["button_size"]["w"]), float(rect["button_size"]["h"])
	)
	var first := Vector2(
		float(rect["first_button"]["x"]), float(rect["first_button"]["y"])
	)
	var pitch: float = float(rect["button_pitch"])
	for mode in buttons.size():
		var button: TextureButton = buttons[mode]
		button.position = Vector2(first.x + pitch * mode, first.y)
		button.size = button_size
		_place_cover(button, load(COVER_UNSELECTED), zoom)


func setup(unit_name: String) -> void:
	name_label.text = unit_name


# The original marks the picked stance by putting the WHITE cover on that one
# button and the BLACK cover on the other four (setAG, in DefineSprite 3312's
# own onClipEvent(load)).
func set_selected(mode: int) -> void:
	var zoom: float = float(layout().get("art_zoom", 4.0))
	for index in buttons.size():
		var path: String = COVER_SELECTED if index == mode else COVER_UNSELECTED
		_place_cover(buttons[index], load(path), zoom)


# The WHITE cover is a glow that spills outside the button and the BLACK one
# sits just inside it, so each is centred on the button at its own size rather
# than stretched to fit.
func _place_cover(button: TextureButton, cover: Texture2D, zoom: float) -> void:
	var rect: TextureRect = button.get_node("Cover")
	rect.texture = cover
	rect.size = Vector2(cover.get_width(), cover.get_height()) / zoom
	rect.position = (button.size - rect.size) / 2.0
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_stance_row_buttons_carry_the_five_icons`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gunit_test_name=test_stance_row_marks_exactly_one_button_selected`
Expected: both PASS.

- [ ] **Step 6: Point battle_scene.gd at the row's own selection**

In `scripts/battle/battle_scene.gd`, change the `_stance_rows` declaration
comment on line 94 to `# party_id -> StanceRow`, then replace
`_populate_stance_rows()` and `_refresh_stance_row()` with:

```gdscript
func _populate_stance_rows() -> void:
	for child in stance_host.get_children():
		child.queue_free()
	_stance_rows.clear()
	var save: PlayerSave = GameData.current_save
	var row_y: float = 0.0
	for slot in [3, 5]:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		var party_id: int = _party_id_for_unit(unit)
		if party_id <= 0:
			continue
		var row: StanceRow = StanceRowScene.instantiate()
		row.position = Vector2(0, row_y)
		stance_host.add_child(row)
		row.setup(unit.player_name)
		for mode in row.buttons.size():
			row.buttons[mode].pressed.connect(_on_stance_pressed.bind(party_id, mode, slot))
		_stance_rows[party_id] = row
		row.set_selected(Party.get_ag_mode(save, party_id) if save != null else Party.AggressionStance.TACTICAL)
		row_y += StanceRow.row_pitch()


func _refresh_stance_row(party_id: int, selected_mode: Party.AggressionStance) -> void:
	var row: StanceRow = _stance_rows.get(party_id)
	if row != null:
		row.set_selected(selected_mode)
```

- [ ] **Step 7: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: all pass, 0 failing. If a test reads `_stance_rows` expecting an
Array of Buttons, update it to call the row instead; do not reintroduce the
array.

- [ ] **Step 8: Commit**

```bash
git add scenes/battle/stance_row.tscn scripts/battle/stance_row.gd scripts/battle/battle_scene.gd test/integration/test_battle_scene.gd
git commit -m "feat: stance rows draw the original's own button art"
```

---

### Task 4: Bring the docs up to date

**Files:**
- Modify: `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`
- Modify: `NEXT_PHASES.md`
- Modify: `KNOWN_GAPS.md`
- Modify: `dev/source_files/README.md`

**Interfaces:**
- Consumes: everything from Tasks 1 to 3. Produces nothing later tasks use.

- [ ] **Step 1: Close out the spec**

Change the spec's status line from `**Status:** design, not yet implemented.`
to `**Status:** implemented 2026-08-23.` Then replace its "Open questions"
section with what was decided:

```markdown
## Settled

The buttons are `TextureButton`s, matching the class cards in
`main_menu.tscn` and the zone buttons in `zone_map.tscn`, which are the
project's existing art-backed buttons. 3309 is extracted rather than drawn
with a `StyleBoxFlat`, on the same rule as the rest of this work: if the SWF
has it, the script takes it.
```

- [ ] **Step 2: Add the NEXT_PHASES entry**

In `NEXT_PHASES.md`, immediately after the `Battle screen art - DONE
(2026-08-22)` bullet, add:

```markdown
- **Battle bottom bar and stance rows - DONE (2026-08-23)**, `uv run extract_battle_screen`. The bar had two placeholder member bars reading "Thurman
  McPown" baked into it, because DefineSprite 3317 places the container at depth 7 and nothing stripped it. It renders bare now, and the five aggression
  icons (`3305`), their two overlay states (`3293`) and the row backing (`3309`) come out as separate art that `StanceRow` arranges, replacing the five
  hand-picked `StyleBoxFlat` colours it drew before. `battle_layout.json` carries the bar's internal layout so the scene does not hold a second copy of
  the measurements.
```

- [ ] **Step 3: Correct the KNOWN_GAPS entry**

In `KNOWN_GAPS.md`, replace the `Battle top panel frame extracted, bars not
built` bullet's second sentence so it no longer implies the bottom bar's rows
are also unbuilt:

```markdown
- **Battle top panel frame extracted, bars not built**: `assets/ui/battle/top_panel.png` is the frame the original's six `p1BAR`-`p6BAR` fighter bars sit
  inside. The bars themselves (`3414`) are still unbuilt, so the frame is not placed in the scene yet. The bottom bar's own team member bars are a
  different thing and are built, as Godot nodes, in `scenes/battle/stance_row.tscn`.
```

- [ ] **Step 4: Note the new outputs**

In `dev/source_files/README.md`, change the `extract/battle_screen.py` line to:

```markdown
- `extract/battle_screen.py` - regenerates the battle halls, skies, chrome and stance button art, plus `battle_layout.json`
```

- [ ] **Step 5: Check the prose and the encoding**

```bash
rg -n "[^\x00-\x7F]" NEXT_PHASES.md KNOWN_GAPS.md dev/source_files/README.md docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md
```

Expected: no matches. Read each edit once for plain register: no marketing
language, no inflated claims, no em dashes, matching the tone of the file it
sits in.

- [ ] **Step 6: Run the full suite and commit**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
git add NEXT_PHASES.md KNOWN_GAPS.md dev/source_files/README.md docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md
git commit -m "docs: close out the battle bottom bar and stance row work"
```

---

## Self-Review

**Spec coverage.** Every design bullet has a task. The bare bar is Task 1. The
five icons, two covers, backing and the `battle_layout.json` section are
Task 2. The `TextureButton` swap, the cover-based selection and the row pitch
are Task 3. Both of the spec's verification items that are not already covered
by a task's own test, that every label produces a non-empty PNG and that the
bare bar carries no text, are asserted in the script and in Task 1's test
respectively. The spec's `w * 4 == PNG width` item is covered for the stance
icons by Task 2's `assert_eq(texture.get_width(), 113)` against a recorded
`button_size.w` of 28.25.

**Placeholder scan.** No TBDs. Every code step carries the actual code, every
run step names the command and the expected result, and the two numbers a
reader would otherwise have to guess, the 727 bright samples and the 113 pixel
icon width, were measured rather than estimated.

**Type consistency.** `StanceRow.buttons` is `Array[TextureButton]` in the
script, in Task 3's tests and in the `battle_scene.gd` rewrite.
`set_selected(mode: int)` takes the same `Party.AggressionStance` value
`_refresh_stance_row` already receives. `row_pitch()` and `layout()` are both
static, and `battle_scene.gd` calls `StanceRow.row_pitch()` on the class.
`MEMBER_BARS` is defined in Task 1 and read again in Task 2's
`stance_row_layout`, which is the only cross-task constant.

One gap found and fixed while reviewing: `stance_row_layout` needs the name
field's character id, which no earlier step defined, so `NAME_FIELD = 3308` is
declared in Task 2 Step 7 beside the code that uses it.
