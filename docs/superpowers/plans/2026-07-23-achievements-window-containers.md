# Achievements Window: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/menu/achievements_window.gd` + `scenes/ui/menu/achievements_window.tscn` off imperative runtime Control-building, as the fourth increment of the "UI architecture: native
Godot Containers instead of code-built controls" phase in `NEXT_PHASES.md` (`item_slot.gd`/`store_window.gd`/`inventory_panel.gd`/`abilities_window.gd` are already done - see the sibling plans in
`docs/superpowers/plans/` for the established conventions this plan follows).

**Architecture:** This screen is small and everything positional in it is genuinely static/fixed - backdrop, close button, panel texture, title label, and 10 achievement plates on a uniform
2-column x 5-row pixel grid. All of it moves into the `.tscn`. The ONLY thing that stays code-driven is each plate's `StyleBoxFlat` (locked vs. unlocked look) and its label's `font_color`, since
`refresh()` recomputes both every call from `Achievements.load_unlocked()` (live save data) - matching the same "structure is static, per-instance look is data-dependent" split used for the talent
tree nodes in the `abilities_window` increment. Unlike that increment, this one does NOT use a container for the plate grid: the achievement index `i` (0-9, used to look up
`Achievements.NAMES[i]`/`DESCRIPTIONS[i]`/`unlocked[i]`) maps to a COLUMN-MAJOR position (`col = floor(i/5)`, `row = i%5`), and a `GridContainer` lays out children ROW-major by tree order - forcing
that mapping through a `GridContainer` would mean reordering child nodes away from their achievement-index names for zero real benefit (nothing here needs container reflow, it's a fixed 10-item
screen). Instead, all 10 plates are declared as explicit fixed-position `PanelContainer` nodes, exactly like the talent tree nodes' fixed-position `Button`s in the prior increment.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_ui_scenes.gd`'s `test_achievements_window_builds_ten_plates` (`var window = ...instantiate(); assert_eq(window._plates.size(), Achievements.ACHIEVEMENT_COUNT)`) must keep
  passing unchanged - it only checks the count, not positions or content, so it does not constrain the internal node structure beyond `window._plates` still being a 10-element array. No test file
  needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere.
- `Achievements.NAMES`/`Achievements.DESCRIPTIONS` (`scripts/entities/achievements.gd:19-34`) are compile-time-fixed content (never changes at runtime) - safe to bake as literal `text`/`tooltip_text`
  values in the `.tscn` instead of reading them in code. `Achievements.ACHIEVEMENT_COUNT = 10` (`achievements.gd:17`) is the array length both there and in `_plates`/`_plate_labels`.
- Godot enum literals used below: `Control.MOUSE_FILTER_IGNORE = 2`, `Control.MOUSE_FILTER_STOP = 0`, `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`,
  `TextureButton.STRETCH_KEEP_ASPECT_CENTERED = 5`, `HORIZONTAL_ALIGNMENT_CENTER = 1`, `VERTICAL_ALIGNMENT_CENTER = 1`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the static chrome and 10 achievement plates into the scene file

**Files:**
- Modify: `scenes/ui/menu/achievements_window.tscn`
- Modify: `scripts/ui/menu/achievements_window.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `_plates: Array[PanelContainer]` and `_plate_labels: Array[Label]`, now populated via `@onready $Path` lookups in achievement-index order (0-9) instead of a runtime-construction loop -
  Task 2 doesn't depend on anything from this task beyond the final file state.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_ui_scenes.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after this task.

- [ ] **Step 2: Rewrite `scenes/ui/menu/achievements_window.tscn`**

Read the current file first (currently just an empty `AchievementsWindow` root `Control` + script). Replace its contents with:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/menu/achievements_window.gd" id="1_achwin"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/menu_backdrop.png" id="2_backdrop"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/close_x.png" id="3_close"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="4_panellarge"]

[node name="AchievementsWindow" type="Control" groups=["achievements_window", "menu_screen"]]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1_achwin")

[node name="Backdrop" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 14.2
offset_top = 14.9
offset_right = 782.7
offset_bottom = 440.0
mouse_filter = 0
texture = ExtResource("2_backdrop")
expand_mode = 1
stretch_mode = 0

[node name="CloseButton" type="TextureButton" parent="."]
layout_mode = 0
offset_left = 734.5
offset_top = 29.8
offset_right = 771.2
offset_bottom = 66.2
texture_normal = ExtResource("3_close")
ignore_texture_size = true
stretch_mode = 5

[node name="PanelBackground" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 76.0
offset_top = 86.0
offset_right = 725.0
offset_bottom = 397.0
mouse_filter = 2
texture = ExtResource("4_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="TitleLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 76.0
offset_top = 105.0
offset_right = 725.0
offset_bottom = 133.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.94, 0.73, 0.23, 1)
theme_override_font_sizes/font_size = 19
horizontal_alignment = 1
text = "Achievements"

[node name="Plate0" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 248.0
offset_top = 145.0
offset_right = 388.0
offset_bottom = 177.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Retrieve the tape from Felicity."

[node name="NameLabel" type="Label" parent="Plate0"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "The Tape"

[node name="Plate1" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 248.0
offset_top = 191.0
offset_right = 388.0
offset_bottom = 223.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat Clemons for the first time, without using any team mates. This can only be done on Challenging or Heroic difficulty."

[node name="NameLabel" type="Label" parent="Plate1"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Black Magic"

[node name="Plate2" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 248.0
offset_top = 237.0
offset_right = 388.0
offset_bottom = 269.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat the Hydra for the first time, without dealing more than 2000 damage throughout the whole fight. This can only be done on Challenging or Heroic difficulty."

[node name="NameLabel" type="Label" parent="Plate2"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Pacifist"

[node name="Plate3" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 248.0
offset_top = 283.0
offset_right = 388.0
offset_bottom = 315.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat Captain Hunt without using any training fights, and without repeating any defeated bosses. This can only be done on Heroic difficulty."

[node name="NameLabel" type="Label" parent="Plate3"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Predator"

[node name="Plate4" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 248.0
offset_top = 329.0
offset_right = 388.0
offset_bottom = 361.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat the Mayor without using any training fights, and without repeating any defeated bosses. This can only be done on Heroic difficulty."

[node name="NameLabel" type="Label" parent="Plate4"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Legend"

[node name="Plate5" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 413.0
offset_top = 145.0
offset_right = 553.0
offset_bottom = 177.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat the Mayor on Heroic difficulty with all three classes"

[node name="NameLabel" type="Label" parent="Plate5"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "All Star"

[node name="Plate6" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 413.0
offset_top = 191.0
offset_right = 553.0
offset_bottom = 223.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat Metal Warden using only one team member."

[node name="NameLabel" type="Label" parent="Plate6"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Jail Break"

[node name="Plate7" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 413.0
offset_top = 237.0
offset_right = 553.0
offset_bottom = 269.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat the Time Bomb in less than 40 turns."

[node name="NameLabel" type="Label" parent="Plate7"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Doomsday"

[node name="Plate8" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 413.0
offset_top = 283.0
offset_right = 553.0
offset_bottom = 315.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat Nostalgia without using any team members."

[node name="NameLabel" type="Label" parent="Plate8"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Old Ghosts"

[node name="Plate9" type="PanelContainer" parent="."]
layout_mode = 0
offset_left = 413.0
offset_top = 329.0
offset_right = 553.0
offset_bottom = 361.0
custom_minimum_size = Vector2(140, 32)
tooltip_text = "Defeat the Corruptor in Zone 7."

[node name="NameLabel" type="Label" parent="Plate9"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "Over the Ashes"

[connection signal="pressed" from="CloseButton" to="." method="hide"]
```

Notes on values, all copied verbatim from the pre-change `achievements_window.gd`'s constants and `Achievements.NAMES`/`DESCRIPTIONS` (`scripts/entities/achievements.gd:19-34`): `Backdrop`/
`CloseButton` use the same `MenuTheme.BACKDROP_RECT`/`CLOSE_RECT` values as every other menu screen in this phase. `PanelBackground` is `PANEL = Rect2(76.0, 86.0, 649.0, 311.0)` verbatim
(`offset_right = 76.0+649.0 = 725.0`, `offset_bottom = 86.0+311.0 = 397.0`). `TitleLabel` is `Rect2(PANEL.position.x, 105, PANEL.size.x, 28)` (`offset_left/right` match `PanelBackground`'s,
`offset_top = 105`, `offset_bottom = 105+28 = 133`). Each `PlateN`'s offsets come from `center = (PLATE_COLUMNS_X[floor(i/5)], PLATE_ROWS_Y[i%5])`, `top_left = center - PLATE_SIZE/2` where
`PLATE_SIZE = (140, 32)`, `PLATE_COLUMNS_X = [318.0, 483.0]` (so column 0 top-left x = `318-70=248`, column 1 = `483-70=413`), `PLATE_ROWS_Y = [161.0, 207.0, 253.0, 299.0, 345.0]` (row top-left y
values `145, 191, 237, 283, 329` respectively, each `-16` from the row center) - `offset_right`/`offset_bottom` add `PLATE_SIZE` (140/32) to each. Every plate's `NameLabel` and `tooltip_text` is
static content from `Achievements.NAMES[i]`/`DESCRIPTIONS[i]` at that exact index - double-check each one against `achievements.gd:19-34` while transcribing, character-for-character, since these are
full English sentences and easy to transpose between adjacent plates.

`PanelContainer` children default to `layout_mode = 2` when parented inside a Container - `NameLabel` is inside its `PlateN` `PanelContainer`, which auto-fits/centers it via the container's own
layout (matching the original `label.horizontal_alignment/vertical_alignment = CENTER` inside the plate's bounds); no manual `offset_*` needed on `NameLabel` itself. The `PlateN` nodes themselves
use `layout_mode = 0` (free positioning) since they're direct children of the plain `Control` root, not of another container.

- [ ] **Step 3: Rewrite `scripts/ui/menu/achievements_window.gd`**

Replace the full file with:

```gdscript
# achievements_window.gd
# The achievements screen, rebuilt from frame 45 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4): a heading, the center panel,
# and 10 achievement plates (achPlate0-9, sprite 3141: frame 1 = locked,
# frame 2 = unlocked) in two columns of five. Descriptions ride tooltips.
extends Control

@onready var _plates: Array[PanelContainer] = [
	$Plate0, $Plate1, $Plate2, $Plate3, $Plate4,
	$Plate5, $Plate6, $Plate7, $Plate8, $Plate9,
]
@onready var _plate_labels: Array[Label] = [
	$Plate0/NameLabel, $Plate1/NameLabel, $Plate2/NameLabel, $Plate3/NameLabel, $Plate4/NameLabel,
	$Plate5/NameLabel, $Plate6/NameLabel, $Plate7/NameLabel, $Plate8/NameLabel, $Plate9/NameLabel,
]


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func():
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	var unlocked: Array = Achievements.load_unlocked()
	for i in _plates.size():
		var got: bool = i < unlocked.size() and unlocked[i]
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		style.set_border_width_all(2)
		if got:
			style.bg_color = Color(0.2, 0.42, 0.8)  # the reference's blue plate
			style.border_color = Color(0.75, 0.85, 0.95)
		else:
			style.bg_color = Color(0.12, 0.14, 0.19)
			style.border_color = Color(0.55, 0.58, 0.62)
		_plates[i].add_theme_stylebox_override("panel", style)
		_plate_labels[i].add_theme_color_override(
			"font_color", Color.WHITE if got else Color(0.45, 0.45, 0.45)
		)
```

Removed: `PANEL`/`PLATE_SIZE`/`PLATE_COLUMNS_X`/`PLATE_ROWS_Y` constants (all now baked into the `.tscn`, nothing in code reads them anymore) and the entire node-construction loop in the old
`_ready()`. `refresh()` is completely unchanged - it was already correctly separating the data-dependent styling from construction, so this task only removes the construction half.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/achievements_window.gd --path .`
Expected: only the known autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/achievements_window.tscn scripts/ui/menu/achievements_window.gd
git commit -m "refactor: move AchievementsWindow's chrome and plates into the scene file"
```

---

### Task 2: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly.

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/ui/menu/achievements_window.tscn` headlessly to a screenshot) and confirm by eye: backdrop/close/panel/title are positioned identically to before, and all 10
plates sit at their original 2-column x 5-row grid positions with the correct name visible in each and the correct locked/unlocked coloring (compare against a save with a few achievements
unlocked if convenient - `Achievements.load_unlocked()` reads from the current save).

- [ ] **Step 3: Update `NEXT_PHASES.md`**

In the "UI architecture: native Godot Containers instead of code-built controls" section, extend the existing `**DONE (2026-07-21):**` paragraph to also mention `achievements_window.gd`, e.g.
change the sentence listing completed files/screens to read:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/menu/abilities_window.gd`, and
`scripts/ui/menu/achievements_window.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, `store_window.tscn` now owns every static chrome node plus a `GridContainer`
for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar chrome plus a `GridContainer` for the 6x6 slot grid, `abilities_window.tscn` now owns its static chrome/attribute panel
plus a `VBoxContainer` for the 5-row ability pool (the 28-node talent tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code via a reusable `talent_node.tscn`,
the same instanced-`PackedScene` pattern as `ItemSlot`, and the 8-socket wheel stays entirely code-driven by design), and `achievements_window.tscn` now owns its chrome plus all 10 fixed-position
achievement plates - only each plate's locked/unlocked `StyleBoxFlat` and label color stay code-driven, since `refresh()` recomputes them from live save data. Everything else named in this phase
(`hotbar.gd`, `battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark achievements_window container migration done in NEXT_PHASES"
```
