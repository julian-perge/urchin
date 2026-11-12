# Spec: ui-foundation

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `ui-foundation` of [the capability map](107-capability-map.md). It depends on no other module.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. This spec adds only what is new for this module.

## Objective

Give every later Screen and Window the same base to build on. Each decision below is already made in a closed ticket. This spec turns the decisions into buildable parts, and it does not reopen them.

The parts:

1. The viewport becomes the 800x575 Stage ([#111](https://github.com/julian-perge/urchin/issues/111)).
2. `FloatBox`, a container that places children at float positions ([#116](https://github.com/julian-perge/urchin/issues/116)).
3. The Panel recipe: a PanelContainer with a StyleBoxFlat and one shared inner shadow shader ([#114](https://github.com/julian-perge/urchin/issues/114), [#115](https://github.com/julian-perge/urchin/issues/115)).
4. The rect test: an extractor writes the Stage rect of every piece, and one generic GUT test checks where each scene lands ([#117](https://github.com/julian-perge/urchin/issues/117)).
5. The ffdec compare tool, one shared tool for layout and art ([#125](https://github.com/julian-perge/urchin/issues/125)).
6. The chrome extractor for art a StyleBoxFlat cannot draw ([#161](https://github.com/julian-perge/urchin/issues/161)).
7. The strings extractor, `convert_strings`, so no module types the original's text by hand.

Already landed and not part of this spec: the TeX Gyre Heros stand-in font ([#127](https://github.com/julian-perge/urchin/issues/127)), pixel snapping off ([#131](https://github.com/julian-perge/urchin/issues/131)), and LINEAR art with NEAREST text ([#141](https://github.com/julian-perge/urchin/issues/141)).

The users are the agents and the person who build the other seven modules. Success is that those modules need no layout, shadow, rect or compare decision of their own.

## Assumptions

- The Stage origin is the viewport origin after part 1, so a SWF coordinate is a viewport coordinate in every scene. KRINMENU's origin (400.50, 222.40) is added by the rect extractor and no scene carries it.
- Part 1 adds no ADR. [ADR 0004](../docs/adr/0004-keep-the-aspect-ratio-on-resize.md) already covers black bars in a window of another shape.
- Names and paths below marked "proposed" are this spec's choice. The closed tickets do not fix them.

## Part 1: The 800x575 viewport

Change `project.godot`, then fix what the 25 px change moves. All of these are in [#111](https://github.com/julian-perge/urchin/issues/111):

- `window/size/viewport_height` becomes 575, and the window override becomes 1600x1150.
- `BottomBar` in `scenes/battle_scene.tscn` moves up 25 px. It sits at y 470 to 600 today.
- `dev/urchin_dev/swf/extract/cutscenes.py` re-pads the four cutscene clips to 800x575. It centers the Stage in 600 today, and its comment at lines 171 to 174 names that. The comment changes with the code. The re-pad re-encodes the clips, and the extractor takes about 13 minutes per long clip.
- `BackgroundFill` in `scenes/game.tscn` becomes `#0e1215`. It is (0.05, 0.06, 0.07) today.
- `docs/agents/godot.md` stops saying the change has not landed.

## Part 2: FloatBox

A Container, `class_name FloatBox`, in `scripts/ui/float_box.gd` (proposed).

- It runs vertical or horizontal.
- It has a float `separation`.
- It sizes itself from each child's float minimum size, with no rounding.
- It has no expand flags, no alignment and no ratios, because the SWF fixes every position.
- A box whose pitches come from the SWF is a `FloatBox`, even when its pitches are whole numbers. Stock BoxContainer stays only where the SWF gives no source.
- There is no float grid. A grid becomes `FloatBox` rows inside a `FloatBox` column.
- A Label is taller than the SWF's field (23 px for a 12 px label, against 19.05). A Label sits in a fixed-height slot, a Control with a set minimum size, so the field's pitch holds.

## Part 3: The Panel recipe

The 16 flat KRINMENU Panels are PanelContainers. This part defines the recipe once. The scenes that use it come with the Window modules.

- Each Panel carries its own StyleBoxFlat sub-resource in its scene. The fill color, the border and the content margins are typed there, because a PanelContainer takes its insets only from its StyleBox and every Panel's insets differ.
- The border is one width on all four sides: the mean-scale stroke `sqrt((sx^2 + sy^2) / 2)` of the Panel's placement matrix, rounded to whole pixels. It is 1 px for most Panels and 2 px on Options and Achievements. The corners stay sharp, so the StyleBoxFlat rasterizes without anti-aliasing.
- The Panel's rect is the SWF fill rect grown by half the border. The fill rect is the rect of the shape's edges, through the centre of the stroke. A DefineShape's `ShapeBounds` includes the stroke, so the fill rect is `ShapeBounds` through the placement matrix, shrunk on each side by half the line width times that axis's scale. On the victory screen's left Panel (scale 0.89 by 1.22), passing `ShapeBounds` instead puts each side 0.45 px out on x and 0.61 px out on y, so the Panel is 0.89 px too wide and 1.22 px too tall.
- No PNG draws a flat Panel.
- One shared ShaderMaterial draws the inner shadow (proposed: `scenes/ui/panel_inner_shadow.gdshader` and `resources/ui/panel_inner_shadow.tres`). The shader multiplies the color by one linear ramp per axis, measured from the Panel's own top left in design px. It darkens only the top and left edges and does not need the Panel's size. The values are the SWF's own: blur 5, distance 5, angle 45. They are typed once, in the material.
- Every Panel references that material. A Theme cannot hold a material, so each PanelContainer sets it.
- Other inner shadows (speech panels, item slots, delete, sell, the close button, the member bars) stay baked into ffdec renders. The Abilities talent pool's overlay ([#190](https://github.com/julian-perge/urchin/issues/190)) belongs to the abilities spec and shares this shader's ramp.

## Part 4: The rect test

An extractor and one GUT test. They keep each Screen's and Window's numbers honest without a run-time lookup.

- Each Screen and Window types its numbers into its own `.tscn`, in Stage coordinates, with its root at the Stage origin. Pieces placed from code, such as the talent tree, the ability ring and the equip slots, keep their numbers in script.
- A new extractor (proposed: `uv run extract_screen_rects`) walks `timeline.frames()` and writes one JSON file under `test/fixtures/`. For every piece a scene draws, it records the Stage rect, keyed by scene path and node path. For every Panel it also records the fill color, the border width and the shader filter values, and its Stage rect is the fill rect grown by half the border (Part 3), not its `ShapeBounds`. For every text field it records the font height and the color, because #139 found eight text sizes 1 to 2 px off their edit texts' `fontHeight`. It adds KRINMENU's origin.
- One generic GUT test instantiates each scene in the record. It checks where each piece lands after the containers lay it out. It does not check the margins and pitches that put it there.
- A piece passes when it is under 0.5 px from its SWF position in Stage coordinates.
- The test fails a Panel that has a wrong fill color, a wrong stroke or no shadow material. It fails a Label whose font size or color differs from the record.
- Tooltips have no Stage rect, because they follow the mouse. They stay out of the record.
- The record starts with no scenes. Each Window or Screen build issue adds its scene to the record and its entries.
- `AGENTS.md` (`Every task`) gets an exception to "do not hand-place a coordinate": a number typed into a scene is fine when the rect test compares it with what the extractor wrote.

## Part 5: The compare tool

One shared tool, generalized from the victory prototype's `compare.py` on the branch `prototype/victory-containers` (`dev/prototypes/victory_containers/`). It lives in `dev/` (proposed: `dev/urchin_dev/checks/`) and runs by hand through the godot-mcp captures, outside `uv run gut`. It needs the SWF, which is gitignored and exists only in the main checkout, and it needs a drawing window.

- It scores layout and art with text hidden, in the prototype's `chrome` and `panels` modes. It scores inside the mask the Screen draws, and it reads a percentile, as `verify_battle_screen.py` does. Faces stay masked out, because ffdec draws them empty. Text stays with the rect test and the font ticket.
- It has a per-Screen config. Each build issue adds an entry.
- It loads captures as they are. The captures have been sRGB since 2026-11-09, so the prototype's linear conversion is removed.
- Each build issue's acceptance criteria hold two things: a bar set from the first passing run, and a must-fail control. The control shifts the reference by 20 px, and its score has to exceed the bar.
- Tooltips and the battle HUD's moving overlays are out. Their own specs can add entries.

## Part 6: The chrome extractor

Issue [#161](https://github.com/julian-perge/urchin/issues/161) is already specified in full, and this spec adopts it as written. Its scope, in short:

- A new entry point, `uv run extract_window_chrome`, renders through `dev/urchin_dev/swf/render.py` at zoom 4 into `assets/ui/window/`. Each piece's Stage rect comes from the same render. The `.png.import` sidecars are committed.
- The pieces are the backdrop (from root frame 181, KRINMENU's own filters drawn), the three item slots rendered separately, the close X, delete, sell and the XP gloss as placed on KRINMENU's timeline, the achievement plate on both frames with its text stripped, the hotbar squares, and the Hub's zone progress track and bar.
- It leaves out the speech box, the clock ring, the digits, the tooltip's title backer and the talent pool's frame.
- The scenes do not change. The hand exports stay until each Window's rebuild stops using them.
- The 4x list under "Extracting art" gets Window chrome. That list is in `docs/agents/art-extraction.md` now, not in CLAUDE.md, so the line goes there.

Acceptance criteria are in #161. The plan stage copies them into the task and fixes the CLAUDE.md path.

## Part 7: The strings extractor

No extractor holds the original's text today, so scripts type strings such as `MENU[21]` and `SYSTEM[17]`. That breaks the standard that a value from the original comes from extractor output. This part adds one extractor, and every module reads its strings from the output.

- A new entry point (proposed: `uv run convert_strings`, in `dev/urchin_dev/convert/strings.py`) reads the `KrinLang.ENGLISH` arrays in `frame_1/DoAction.as` (`dev/source_files/action_script/`). It writes `dev/converted_json/strings.json` with one array per name: `MENU`, `SYSTEM`, `VICTORY`, `NAVTITLE`, `NAVTEXT`, `NAVTITLE2`, `NAVTEXT2`, `ZONES`, `ZONES2` and the others a module needs. An index in the JSON is the index in the AS.
- The port reads the JSON through one small loader (proposed: `scripts/autoload/` or a static class), so a script names `Strings.system(17)` and no literal.
- A second run writes the same file.
- A `uv run pytest` test checks the parsing on a small AS sample. It does not read the SWF.
- Modules that cite a `MENU[n]` or `SYSTEM[n]` string in their specs read it from this file in their build issues. The two specs already approved cite indexes, so they need no change.
- Only English is extracted. The original's language switch is not in scope.

## Project structure

Follows `AGENTS.md`. New locations:

```
scripts/ui/float_box.gd                      FloatBox
scenes/ui/panel_inner_shadow.gdshader        the shadow ramp (proposed)
resources/ui/panel_inner_shadow.tres         the one shared ShaderMaterial (proposed)
assets/ui/window/                            zoom 4 chrome art, written by extract_window_chrome
dev/urchin_dev/swf/extract/window_chrome.py  the chrome extractor
dev/urchin_dev/swf/extract/screen_rects.py   the rect extractor (proposed)
dev/urchin_dev/checks/                       the compare tool (proposed)
dev/urchin_dev/convert/strings.py            the strings extractor (proposed)
dev/converted_json/strings.json              its output
test/fixtures/                               the rect record
test/unit/                                   FloatBox, Panel recipe and rect tests
```

## Code style

`FloatBox` follows the repo's GDScript conventions in `docs/agents/godot.md` and `CODING_STANDARDS.md`. A comment passes the three tests or is deleted. A number the diff takes from the SWF comes from an extractor's output, and the test reads the same output.

```gdscript
class_name FloatBox
extends Container

@export var vertical := true
@export var separation := 0.0

func _get_minimum_size() -> Vector2:
	var total := Vector2.ZERO
	var shown := 0
	for child in get_children():
		if child is Control and child.visible:
			var min_size: Vector2 = child.get_combined_minimum_size()
			if vertical:
				total.x = maxf(total.x, min_size.x)
				total.y += min_size.y
			else:
				total.x += min_size.x
				total.y = maxf(total.y, min_size.y)
			shown += 1
	if shown > 1:
		total += Vector2(0.0, separation * (shown - 1)) if vertical else Vector2(separation * (shown - 1), 0.0)
	return total
```

This snippet shows the style only. The build issue writes the real `_notification(NOTIFICATION_SORT_CHILDREN)` and tests it.

## Testing strategy

- **FloatBox**: GUT unit tests in `test/unit/`. Cases: fractional separation, fractional minimum sizes, nesting, vertical and horizontal, a hidden child. Each expected position is computed from numbers the test reads, not typed.
- **Panel recipe**: a GUT test that builds one Panel and checks its border width, its rect growth and its material. A second test breaks one of the three and expects a failure.
- **Rect test**: the generic test above. It runs in every `uv run gut`. Its must-fail control moves one piece 20 px in a copy of the scene and expects a failure.
- **Extractors**: `uv run pytest` tests under `dev/tests/` for the pure parts, and the byte-for-byte rerun rule from `docs/agents/art-extraction.md` for each PNG. The extractors read the SWF, so those runs happen in the main checkout.
- **Compare tool**: the must-fail control in Part 5. It runs by hand and is not a GUT test.
- **Viewport**: `test/unit/test_project_settings.gd` already reads both snap settings. Add a case there that expects the 800x575 viewport.

## Boundaries

- Always: Run `uv run gut` before each commit. Read the SWF through the extractors and never type a SWF number the rect record can supply. Commit `.png.import` sidecars with the art.
- Ask first: A new dependency. A change to ffdec's build or config. A change to a closed ticket's decision, such as the 0.5 px tolerance. Adding an ADR.
- Never: Draw a flat Panel from a PNG. Round a pitch in layout. Reopen the snap or filter settings. Run ffdec concurrently. Run a windowed render without the `AGENT RENDER` title.

## Success criteria

1. `project.godot` has an 800x575 viewport, and the battle bar, the cutscene clips and `BackgroundFill` match it. The full GUT run passes.
2. `FloatBox` places children at float positions, and its tests pass with fractional pitches.
3. One Panel built to the recipe scores p99 5 or better against ffdec on its rect and 8 or better on its shadow band against a real Flash capture. These are the numbers [#115](https://github.com/julian-perge/urchin/issues/115) measured for the shader.
4. The rect extractor runs twice and writes the same JSON. The generic test passes on a scene that follows the record and fails on a scene with one piece moved 20 px.
5. The compare tool scores one scene, and the same scene shifted 20 px scores over the bar.
6. `uv run extract_window_chrome` meets the acceptance criteria in #161.
7. `uv run convert_strings` writes `strings.json` twice with identical bytes, and its test passes without the SWF.
8. `AGENTS.md` and `docs/agents/` carry the new rules: the rect exception, the 4x Window chrome line and the viewport note.

## Open questions

1. The rect record's key format and file name. This spec proposes scene path plus node path, in one JSON under `test/fixtures/`. The plan stage can fix the names.
2. How the compare tool freezes a Screen's run-time state for a capture. [#125](https://github.com/julian-perge/urchin/issues/125) left this to the tool's build issue.
3. Whether to cut part 1 into its own issue. This spec keeps it as one part, and the plan stage can split it as the first task. [#111](https://github.com/julian-perge/urchin/issues/111) already calls it the first implementation issue.
