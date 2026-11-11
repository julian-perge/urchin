# Main Menu: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/main_menu.gd` + `scenes/main_menu.tscn` off imperative runtime Control-building, as the second of three files that still call `MenuTheme`'s runtime UI-construction
helpers (`add_texture_rect`/`add_label`) - after this, only `scripts/battle/victory_screen.gd` remains before those two helpers can be deleted from `menu_theme.gd` entirely (that migration is a
separate future plan since `victory_screen.gd` has no `.tscn` at all yet; do not touch `menu_theme.gd` itself in this plan).

**Architecture:** `scenes/main_menu.tscn` is already partially declarative (root `MainMenu` Control, a `BackgroundFill` TextureRect, and an empty `Layout` VBoxContainer) - this plan finishes the job.
Everything with a fixed count/position moves into the `.tscn`: the slot screen's title and its (empty) button-list container, the entire class-select screen's chrome including all 3 class cards
(fixed order: Psychological, Biological, Hydraulic) and the Cancel button, and the entire settings screen's chrome including the 3 difficulty buttons, the 3 toggle rows (Tutorial/Sound/Autosave),
and the Start/Back buttons. What stays code-driven: the save-slot buttons themselves (`_refresh_slot_buttons()` - count is `GameData.NUM_SLOTS` and each button's label text depends on live save
data, rebuilt every call) and the toggle rows' on/off text swap plus their state fields (still handled by named per-row methods, since each row's side effect differs - Sound's toggle also mutes an
audio bus).

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_ui_scenes.gd`'s `test_main_menu_builds_slot_buttons` must keep passing unchanged. It instantiates `scenes/main_menu.tscn`, waits one frame, then asserts:
  `menu.slot_buttons.get_children().size() == GameData.NUM_SLOTS`, `menu.new_game_panel.visible == false`, `menu.class_picker.get_child_count() == 3`, and
  `menu.difficulty_picker.get_child_count() == 3`. This means `slot_buttons`, `new_game_panel`, `class_picker`, and `difficulty_picker` must all remain accessible as public members with those exact
  names on the script (whether plain `var` or `@onready var` makes no difference to GUT - both are ordinary node properties at runtime). No test file needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere.
- Godot enum literals used below (confirmed against this project's actual Godot 4.7.1 binary, not assumed from memory): `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`,
  `TextureRect.STRETCH_KEEP_ASPECT_CENTERED = 5`, `TextureRect.STRETCH_KEEP_ASPECT_COVERED = 6`, `TextureButton.STRETCH_KEEP_ASPECT_CENTERED = 5`, `Control.MOUSE_FILTER_STOP = 0`,
  `Control.MOUSE_FILTER_IGNORE = 2`, `Control.PRESET_FULL_RECT = 15`, `Control.PRESET_CENTER = 8`, `TextServer.AUTOWRAP_WORD_SMART = 3`, `HORIZONTAL_ALIGNMENT_CENTER = 1`,
  `HORIZONTAL_ALIGNMENT_RIGHT = 2`, `VERTICAL_ALIGNMENT_CENTER = 1`.
- The root scene already has `BackgroundFill` (a `TextureRect` at `stretch_mode = 5`, i.e. `STRETCH_KEEP_ASPECT_CENTERED`) covering the whole menu at `z_index = -1`. The two new per-screen
  backgrounds this plan adds (`NewGamePanel/Background`, `OptionsPanel/Background`) intentionally use `stretch_mode = 6` (`STRETCH_KEEP_ASPECT_COVERED`) instead, matching the original code's
  `_make_screen()` exactly (`TextureRect.STRETCH_KEEP_ASPECT_COVERED`) - this is not a typo to "fix", the two stretch modes were already different before this refactor and must stay different.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document. If a fresh worktree's first run shows unrelated parse errors (`Identifier "Equipment"` etc.) or a
  much lower pass count than expected, that is a known stale-import-cache artifact - run
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .` once first to force a full asset reimport, then re-run the suite.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the title and slot-button container into the scene file

**Files:**
- Modify: `scenes/main_menu.tscn`
- Modify: `scripts/ui/main_menu.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `slot_buttons: VBoxContainer` as an `@onready $Layout/SlotButtons` reference instead of code-built. Tasks 2/3 touch entirely different node subtrees (`NewGamePanel`/`OptionsPanel`) and
  don't depend on anything from this task.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_ui_scenes.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Add the Title label and SlotButtons container to `scenes/main_menu.tscn`'s existing `Layout` node**

Read the current file first (root `MainMenu` Control with a `BackgroundFill` TextureRect and an empty `Layout` VBoxContainer, `anchors_preset = 8`). Add these two nodes as children of `Layout`
(after its existing `[node name="Layout" ...]` block, before anything else):

```
[node name="Title" type="Label" parent="Layout"]
layout_mode = 2
theme_override_font_sizes/font_size = 34
horizontal_alignment = 1
text = "Sonny 2"

[node name="SlotButtons" type="VBoxContainer" parent="Layout"]
layout_mode = 2
theme_override_constants/separation = 10
```

Notes: `layout_mode = 2` is the standard "managed by parent container" mode - `Layout` (a `VBoxContainer`) positions and sizes both children itself, so neither needs manual offsets. `SlotButtons`
stays empty in the scene file - `_refresh_slot_buttons()` (unchanged, still in the script) populates it every time with one button per save slot, since the count and each button's label text
depend on live save data.

- [ ] **Step 3: Simplify `scripts/ui/main_menu.gd`'s `_ready()` and delete `_build_slot_screen()`**

Replace the `var slot_buttons: VBoxContainer` declaration (in the `var` block near the top of the file) with:

```gdscript
@onready var slot_buttons: VBoxContainer = $Layout/SlotButtons
```

Delete `_build_slot_screen()` entirely (the whole function).

In `_ready()`, remove the `_build_slot_screen()` call. The function should now read:

```gdscript
func _ready():
	_build_class_screen()
	_build_options_screen()
	new_game_panel.hide()
	options_panel.hide()
	_refresh_slot_buttons()
	AudioManagerAuto.play_menu_music()
```

(`_build_class_screen()`/`_build_options_screen()` stay called here for now - Tasks 2 and 3 remove them in turn. `_refresh_slot_buttons()` is unchanged and still works correctly against the new
`@onready` `slot_buttons` reference, since `@onready` vars resolve before `_ready()`'s body runs.)

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/main_menu.gd --path .`
Expected: only the known autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests).

- [ ] **Step 6: Commit**

```bash
git add scenes/main_menu.tscn scripts/ui/main_menu.gd
git commit -m "refactor: move MainMenu's title and slot-button container into the scene file"
```

---

### Task 2: Move the class-select screen into the scene file

**Files:**
- Modify: `scenes/main_menu.tscn`
- Modify: `scripts/ui/main_menu.gd`

**Interfaces:**
- Consumes: nothing from Task 1 (disjoint node subtree - `NewGamePanel` is a new sibling of `Layout`/`BackgroundFill`, not nested under either).
- Produces: `new_game_panel: Control`, `name_input: LineEdit`, `class_picker: HBoxContainer` as `@onready $NewGamePanel...` references. Task 3 (`OptionsPanel`) is a separate sibling subtree and
  doesn't depend on anything from this task, though `_on_class_picked()` (unchanged, calls `options_panel.show()`) does read the `options_panel` var Task 3 introduces - that's fine, GDScript
  resolves member access at call time, not declaration order, and this task doesn't call `_on_class_picked()` itself.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Add the class cards' texture resources and the `NewGamePanel` subtree to `scenes/main_menu.tscn`**

Add 6 new `ext_resource` lines (after the existing `id="2_bg"` one) and the full `NewGamePanel` node tree (as a new child of the scene root, i.e. `parent="."`, added after the existing `Layout`
node):

```
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/psychological_gray.png" id="3_psychgray"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/psychological.png" id="4_psych"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/biological_gray.png" id="5_biogray"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/biological.png" id="6_bio"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/hydraulic_gray.png" id="7_hydrogray"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/class_cards/hydraulic.png" id="8_hydro"]

[node name="NewGamePanel" type="Control" parent="."]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Background" type="TextureRect" parent="NewGamePanel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 0
texture = ExtResource("2_bg")
expand_mode = 1
stretch_mode = 6

[node name="ClassLabel" type="Label" parent="NewGamePanel"]
layout_mode = 0
offset_left = 0.0
offset_top = 60.0
offset_right = 800.0
offset_bottom = 100.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.85, 0.5, 0.55, 1)
theme_override_font_sizes/font_size = 26
horizontal_alignment = 1
text = "Please select a class:"

[node name="NameLabel" type="Label" parent="NewGamePanel"]
layout_mode = 0
offset_left = 250.0
offset_top = 116.0
offset_right = 330.0
offset_bottom = 146.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 15
horizontal_alignment = 2
vertical_alignment = 1
text = "Name:"

[node name="NameInput" type="LineEdit" parent="NewGamePanel"]
layout_mode = 0
offset_left = 340.0
offset_top = 116.0
offset_right = 550.0
offset_bottom = 146.0
text = "Sonny"
max_length = 12

[node name="ClassPicker" type="HBoxContainer" parent="NewGamePanel"]
layout_mode = 0
offset_left = 85.0
offset_top = 170.0
offset_right = 715.0
offset_bottom = 500.0
theme_override_constants/separation = 45

[node name="Psychological" type="TextureButton" parent="NewGamePanel/ClassPicker"]
layout_mode = 2
custom_minimum_size = Vector2(180, 320)
texture_normal = ExtResource("3_psychgray")
texture_hover = ExtResource("4_psych")
texture_pressed = ExtResource("4_psych")
ignore_texture_size = true
stretch_mode = 5
tooltip_text = "Psychological"

[node name="Biological" type="TextureButton" parent="NewGamePanel/ClassPicker"]
layout_mode = 2
custom_minimum_size = Vector2(180, 320)
texture_normal = ExtResource("5_biogray")
texture_hover = ExtResource("6_bio")
texture_pressed = ExtResource("6_bio")
ignore_texture_size = true
stretch_mode = 5
tooltip_text = "Biological"

[node name="Hydraulic" type="TextureButton" parent="NewGamePanel/ClassPicker"]
layout_mode = 2
custom_minimum_size = Vector2(180, 320)
texture_normal = ExtResource("7_hydrogray")
texture_hover = ExtResource("8_hydro")
texture_pressed = ExtResource("8_hydro")
ignore_texture_size = true
stretch_mode = 5
tooltip_text = "Hydraulic"

[node name="CancelButton" type="Button" parent="NewGamePanel"]
layout_mode = 0
offset_left = 700.0
offset_top = 545.0
offset_right = 780.0
offset_bottom = 581.0
theme_override_font_sizes/font_size = 18
text = "Back"

[connection signal="pressed" from="NewGamePanel/ClassPicker/Psychological" to="." method="_on_class_picked" binds=[1]]
[connection signal="pressed" from="NewGamePanel/ClassPicker/Biological" to="." method="_on_class_picked" binds=[0]]
[connection signal="pressed" from="NewGamePanel/ClassPicker/Hydraulic" to="." method="_on_class_picked" binds=[2]]
[connection signal="pressed" from="NewGamePanel/CancelButton" to="." method="_on_cancel_new_game"]
```

Notes on values: every `offset_*` is copied verbatim from the `Rect2`/`position`+`size` pairs in the pre-migration code (`Rect2(0,60,800,40)` -> `ClassLabel`, `Rect2(250,116,80,30)` ->
`NameLabel`, `position (340,116) size (210,30)` -> `NameInput`, `position (85,170) size (630,330)` -> `ClassPicker`, `position (700,545) size (80,36)` -> `CancelButton`). The card order
(Psychological, Biological, Hydraulic) is the FIXED visual order from `CLASS_CARD_ORDER = [1, 0, 2]` combined with `CLASS_CARD_ART` - each card's `pressed` connection binds its own `class_id`
literal (`1`/`0`/`2` respectively) directly to `_on_class_picked(class_id)`, replacing the runtime `.bind(class_id)` closure. `NameInput`/`ClassPicker`/`CancelButton` get NO explicit `mouse_filter`
override (the original code built these as plain `LineEdit`/`HBoxContainer`/`Button` nodes directly, never through `MenuTheme.add_label`/`add_texture_rect` - only `ClassLabel`/`NameLabel`, which
WERE built via `MenuTheme.add_label`, get the `mouse_filter = 2` override that helper always applies). `Background`'s `mouse_filter = 0` matches the explicit `Control.MOUSE_FILTER_STOP` the
original `_make_screen()` set on every panel's own background texture.

- [ ] **Step 3: Rewrite `scripts/ui/main_menu.gd`'s constants, vars, and class-screen functions**

Delete these three now-fully-superseded constants entirely (all three are read ONLY inside the functions this step deletes, confirmed via `rg -n "CLASS_NAMES|CLASS_CARD_ORDER|CLASS_CARD_ART"
scripts/ui/main_menu.gd` before making this change - every hit is inside `_build_class_screen()`/`_make_class_card()`):

```gdscript
const CLASS_NAMES: Array[String] = ["Biological", "Psychological", "Hydraulic"]
# Card order matches the original screen: Psychological, Biological, Hydraulic.
const CLASS_CARD_ORDER: Array[int] = [1, 0, 2]
const CLASS_CARD_ART: Dictionary[int, String] = {
	1: "class_cards/psychological",
	0: "class_cards/biological",
	2: "class_cards/hydraulic",
}
```

Replace the `var new_game_panel: Control`, `var name_input: LineEdit`, and `var class_picker: HBoxContainer` declarations with:

```gdscript
@onready var new_game_panel: Control = $NewGamePanel
@onready var name_input: LineEdit = $NewGamePanel/NameInput
@onready var class_picker: HBoxContainer = $NewGamePanel/ClassPicker
```

Delete `_build_class_screen()` entirely (the whole function) and delete `_make_class_card()` entirely (the whole function) - both are fully superseded by the static `.tscn` nodes and
`[connection]` bindings added in Step 2.

In `_ready()`, remove the `_build_class_screen()` call. The function should now read:

```gdscript
func _ready():
	_build_options_screen()
	new_game_panel.hide()
	options_panel.hide()
	_refresh_slot_buttons()
	AudioManagerAuto.play_menu_music()
```

Leave `_on_class_picked(class_id)` and `_on_cancel_new_game()` completely untouched - both still work correctly against the new `@onready` references.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/main_menu.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 1's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/main_menu.tscn scripts/ui/main_menu.gd
git commit -m "refactor: move MainMenu's class-select screen into the scene file"
```

---

### Task 3: Move the settings screen into the scene file and delete `_make_screen()`

**Files:**
- Modify: `scenes/main_menu.tscn`
- Modify: `scripts/ui/main_menu.gd`

**Interfaces:**
- Consumes: nothing from Task 2 (disjoint node subtree - `OptionsPanel` is a new sibling of `NewGamePanel`/`Layout`/`BackgroundFill`).
- Produces: nothing new consumed later - Task 4 is verification only.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Add a shared `ButtonGroup`/transparent `StyleBoxFlat` sub-resource and the `OptionsPanel` subtree to `scenes/main_menu.tscn`**

Add these two sub-resources (anywhere before the `[node name="OptionsPanel" ...]` block that references them) and the full `OptionsPanel` node tree (as a new sibling of `NewGamePanel`,
`parent="."`):

```
[sub_resource type="ButtonGroup" id="ButtonGroup_difficulty"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_transparent"]
bg_color = Color(0, 0, 0, 0)

[node name="OptionsPanel" type="Control" parent="."]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Background" type="TextureRect" parent="OptionsPanel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 0
texture = ExtResource("2_bg")
expand_mode = 1
stretch_mode = 6

[node name="SettingsLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 0.0
offset_top = 50.0
offset_right = 800.0
offset_bottom = 84.0
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 22
horizontal_alignment = 1
text = "Please configure your settings:"

[node name="DifficultyLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 140.0
offset_top = 120.0
offset_right = 390.0
offset_bottom = 150.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.6, 0.15, 1)
theme_override_font_sizes/font_size = 22
horizontal_alignment = 2
text = "Difficulty:"

[node name="DifficultyPicker" type="HBoxContainer" parent="OptionsPanel"]
layout_mode = 0
offset_left = 410.0
offset_top = 120.0
offset_right = 710.0
offset_bottom = 150.0
theme_override_constants/separation = 8

[node name="Easy" type="Button" parent="OptionsPanel/DifficultyPicker"]
layout_mode = 2
toggle_mode = true
button_pressed = true
button_group = SubResource("ButtonGroup_difficulty")
text = "Easy"

[node name="Challenging" type="Button" parent="OptionsPanel/DifficultyPicker"]
layout_mode = 2
toggle_mode = true
button_group = SubResource("ButtonGroup_difficulty")
text = "Challenging"

[node name="Heroic" type="Button" parent="OptionsPanel/DifficultyPicker"]
layout_mode = 2
toggle_mode = true
button_group = SubResource("ButtonGroup_difficulty")
text = "Heroic"

[node name="TutorialLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 140.0
offset_top = 170.0
offset_right = 390.0
offset_bottom = 196.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.4, 1)
theme_override_font_sizes/font_size = 17
horizontal_alignment = 2
text = "Tutorial Level:"

[node name="TutorialToggle" type="Button" parent="OptionsPanel"]
layout_mode = 0
offset_left = 410.0
offset_top = 170.0
offset_right = 550.0
offset_bottom = 198.0
toggle_mode = true
button_pressed = true
text = "Yeah, sure!"

[node name="SoundLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 140.0
offset_top = 220.0
offset_right = 390.0
offset_bottom = 246.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.4, 1)
theme_override_font_sizes/font_size = 17
horizontal_alignment = 2
text = "Sound:"

[node name="SoundToggle" type="Button" parent="OptionsPanel"]
layout_mode = 0
offset_left = 410.0
offset_top = 220.0
offset_right = 550.0
offset_bottom = 248.0
toggle_mode = true
button_pressed = true
text = "On"

[node name="AutosaveLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 140.0
offset_top = 270.0
offset_right = 390.0
offset_bottom = 296.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.4, 1)
theme_override_font_sizes/font_size = 17
horizontal_alignment = 2
text = "Autosave:"

[node name="AutosaveToggle" type="Button" parent="OptionsPanel"]
layout_mode = 0
offset_left = 410.0
offset_top = 270.0
offset_right = 550.0
offset_bottom = 298.0
toggle_mode = true
button_pressed = true
text = "On"

[node name="NoteLabel" type="Label" parent="OptionsPanel"]
layout_mode = 0
offset_left = 120.0
offset_top = 330.0
offset_right = 680.0
offset_bottom = 410.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.9, 0.9, 1)
theme_override_font_sizes/font_size = 13
autowrap_mode = 3
text = "If you turn Autosave on, your game will be saved when you press 'Proceed' after winning a battle. The difficulty level cannot be changed - you must start a new game if you wish to play on a different mode."

[node name="StartButton" type="Button" parent="OptionsPanel"]
layout_mode = 0
offset_left = 250.0
offset_top = 460.0
offset_right = 550.0
offset_bottom = 510.0
theme_override_colors/font_color = Color(0.35, 0.95, 0.25, 1)
theme_override_colors/font_hover_color = Color(0.6, 1.0, 0.5, 1)
theme_override_font_sizes/font_size = 24
theme_override_styles/normal = SubResource("StyleBoxFlat_transparent")
theme_override_styles/hover = SubResource("StyleBoxFlat_transparent")
theme_override_styles/pressed = SubResource("StyleBoxFlat_transparent")
text = "Click here to START!"

[node name="BackButton" type="Button" parent="OptionsPanel"]
layout_mode = 0
offset_left = 700.0
offset_top = 545.0
offset_right = 780.0
offset_bottom = 581.0
text = "Back"

[connection signal="pressed" from="OptionsPanel/DifficultyPicker/Easy" to="." method="_on_difficulty_selected" binds=[0]]
[connection signal="pressed" from="OptionsPanel/DifficultyPicker/Challenging" to="." method="_on_difficulty_selected" binds=[1]]
[connection signal="pressed" from="OptionsPanel/DifficultyPicker/Heroic" to="." method="_on_difficulty_selected" binds=[2]]
[connection signal="toggled" from="OptionsPanel/TutorialToggle" to="." method="_on_tutorial_toggled"]
[connection signal="toggled" from="OptionsPanel/SoundToggle" to="." method="_on_sound_toggled"]
[connection signal="toggled" from="OptionsPanel/AutosaveToggle" to="." method="_on_autosave_toggled"]
[connection signal="pressed" from="OptionsPanel/StartButton" to="." method="_on_start_new_game"]
[connection signal="pressed" from="OptionsPanel/BackButton" to="." method="_on_options_back_pressed"]
```

Notes on values: every label/button `offset_*` is copied verbatim from the corresponding `Rect2`/`position`+`size` pair in the pre-migration code (`Rect2(0,50,800,34)` -> `SettingsLabel`,
`Rect2(140,120,250,30)` -> `DifficultyLabel`, `position (410,120)` -> `DifficultyPicker` (no explicit size in the original either - a `HBoxContainer`'s own minimum-size logic determines its real
size regardless of what's written here, so `offset_right`/`offset_bottom` just need to be syntactically present, not pixel-exact), the three toggle rows' `Rect2(140,y,250,26)` label rects and
`position (410,y) size (140,28)` button rects at `y = 170/220/270`, `Rect2(120,330,560,80)` -> `NoteLabel` (`autowrap_mode = 3` matches the original's `wrap_text=true` ->
`TextServer.AUTOWRAP_WORD_SMART`), and `position (250,460) size (300,50)` -> `StartButton` / `position (700,545) size (80,36)` -> `BackButton` (coincidentally the same rect as `NewGamePanel`'s
`CancelButton` in the original code - not a mistake, both screens happen to put their "Back"-style button in the same spot). `DifficultyPicker`'s 3 buttons and the toggle buttons get NO explicit
`mouse_filter` override (built as plain `Button`s in the original, never through `MenuTheme`'s helpers); every `*Label` node DOES get `mouse_filter = 2` (all built via `MenuTheme.add_label`
originally). The three difficulty buttons' `pressed` connections each bind their own literal index (`0`/`1`/`2`) to a new `_on_difficulty_selected(index)` method, replacing the original's
per-button closure (`func(): _selected_difficulty = i`) - Godot signal `binds` can't capture a loop variable the way a GDScript closure can, so this needs a named method with the index bound as a
literal per connection, same pattern as the class cards in Task 2.

- [ ] **Step 3: Rewrite `scripts/ui/main_menu.gd`'s remaining vars and settings-screen functions; delete `_make_screen()`**

Delete the `var start_button: Button` and `var cancel_button: Button` declarations entirely - confirm first with `rg -n "start_button|cancel_button" scripts/ui/main_menu.gd` that every remaining
hit is inside `_build_options_screen()`/`_build_class_screen()` (both already deleted or about to be deleted in this step) - neither var is read anywhere else, including the test suite.

Replace the `var options_panel: Control` declaration with:

```gdscript
@onready var options_panel: Control = $OptionsPanel
@onready var difficulty_picker: HBoxContainer = $OptionsPanel/DifficultyPicker
```

Delete `_build_options_screen()` entirely, delete `_add_toggle_row()` entirely, and delete `_make_screen()` entirely (the whole function) - `_make_screen()` has no remaining callers once this
step's other deletions land, since both `_build_class_screen()` (Task 2) and `_build_options_screen()` (this step) were its only two call sites.

Add these five new methods (placed near `_on_class_picked`/`_on_cancel_new_game` is a reasonable spot, but exact placement doesn't matter):

```gdscript
func _on_difficulty_selected(index: int) -> void:
	_selected_difficulty = index


func _on_tutorial_toggled(pressed: bool) -> void:
	$OptionsPanel/TutorialToggle.text = "Yeah, sure!" if pressed else "No thanks"
	_tutorial_enabled = pressed


func _on_sound_toggled(pressed: bool) -> void:
	$OptionsPanel/SoundToggle.text = "On" if pressed else "Off"
	_sound_enabled = pressed
	AudioServer.set_bus_mute(0, not pressed)


func _on_autosave_toggled(pressed: bool) -> void:
	$OptionsPanel/AutosaveToggle.text = "On" if pressed else "Off"
	_autosave_enabled = pressed


func _on_options_back_pressed() -> void:
	options_panel.hide()
	new_game_panel.show()
```

In `_ready()`, remove the `_build_options_screen()` call. The function should now read:

```gdscript
func _ready():
	new_game_panel.hide()
	options_panel.hide()
	_refresh_slot_buttons()
	AudioManagerAuto.play_menu_music()
```

Leave `_on_start_new_game()` and `_enter_game()` completely untouched.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/main_menu.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 2's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/main_menu.tscn scripts/ui/main_menu.gd
git commit -m "refactor: move MainMenu's settings screen into the scene file"
```

---

### Task 4: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly (no new failures, no new tests - this whole plan is a pure refactor).

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/main_menu.tscn` headlessly to a screenshot, if the environment supports offscreen rendering - it may not, in which case say so rather than skip silently) and
confirm by eye: the slot-select screen shows the title and one button per save slot, clicking an empty slot shows the class-select screen with all 3 class cards in the correct order and gray/
colored hover states, picking a class shows the settings screen with all three difficulty buttons/three toggle rows/Start+Back buttons functioning, and the transparent Start button style still
lets the background show through.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

`main_menu.gd` is the second of three `MenuTheme`-helper callers being migrated. Add a bullet under the same "UI architecture: native Godot Containers instead of code-built controls" section's
existing "In progress" note (the one added when `inventory_window.gd` was migrated), extending it to also cover `main_menu.gd`, e.g.:

```markdown
**In progress (2026-07-23) - retiring `MenuTheme`'s runtime helpers:** `add_texture_rect`/`add_label` (`menu_theme.gd`) exist only because their remaining callers still build Controls at runtime;
`scripts/ui/menu/inventory_window.gd` and `scripts/ui/main_menu.gd` are both now migrated. Only `scripts/battle/victory_screen.gd` still calls these helpers - it has no `.tscn` yet at all, so
migrating it also means creating one and updating `battle_scene.gd`'s `.new()` instantiation call site. Once that's done, `add_texture_rect`/`add_label` can be deleted from `menu_theme.gd`
entirely.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: note MainMenu's progress retiring MenuTheme's runtime helpers"
```
