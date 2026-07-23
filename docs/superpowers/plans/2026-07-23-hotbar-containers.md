# Hotbar: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/hotbar.gd` + `scenes/ui/hotbar.tscn` off imperative runtime Control-building, as the fifth increment of the "UI architecture: native Godot Containers instead of
code-built controls" phase in `NEXT_PHASES.md` (`item_slot.gd`/`store_window.gd`/`inventory_panel.gd`/`abilities_window.gd`/`achievements_window.gd` are already done - see the sibling plans in
`docs/superpowers/plans/` for the established conventions this plan follows).

**Architecture:** Unlike every prior increment, `hotbar.tscn` is ALREADY mostly declarative - it uses real `HBoxContainer`/`CenterContainer`/`VBoxContainer` layout, shared `StyleBoxFlat`
sub-resources, and `unique_name_in_owner` nodes for every button and label. Only two things in `hotbar.gd` still build nodes at runtime: (1) `_build_quit_button()`, which constructs the red X
"quit to save-select" button entirely in code with no scene presence at all, and (2) `_setup_icon_glow()`, which relocates each of the 6 `HOVER_COLORS` buttons' existing `icon` property into two
new runtime-constructed `TextureRect` children (a hidden green "Glow" copy and a visible "Icon" copy) so the icon can tint on hover/active. Both move into the `.tscn` as static children with baked
textures - reusing the exact same `ExtResource` ids the buttons' own now-removable `icon` property already references. Only the per-instance `mouse_entered`/`mouse_exited` hover-tint wiring stays
in code, since it needs a closure over live node references plus a bound `Color` - not expressible as a static scene connection. While touching this file, three more static-content simplifications
land too: `BUTTON_TOOLTIPS` (a compile-time-fixed dict overriding 4 buttons' `tooltip_text`) and the `OptionsButton`/`RespecButton` "Coming soon" dimming loop are both 100% static and get baked
directly as node properties instead of applied by a runtime loop; and the `SaveButton`/3 `MENU_BUTTON_GROUPS` buttons' `pressed` connections (fixed string binds) become scene `[connection]` blocks
instead of runtime `.connect()` calls.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_ui_scenes.gd` must keep passing unchanged: `test_hotbar_shows_progress_from_save` reads `hotbar.zone_title`/`zone_subtitle`/`progress_bar`/`stage_label` (already `@onready`
  refs, untouched by this plan). `test_hotbar_menu_toggle_is_exclusive_and_glows` reads `hotbar._button_glows["AbilitiesButton"]["glow"].visible` and `hotbar._button_glows["InventoryButton"]["glow"].visible`
  directly and calls `hotbar.toggle_menu_screen(group)` - the `_button_glows` dict's shape (`{button_name: {"glow": TextureRect, "icon": TextureRect}}`) must not change. No test file needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere.
- `MENU_BUTTON_GROUPS` and `HOVER_COLORS` constants must both REMAIN in the script - `_wire_screen_visibility()`/`_update_glows()`/`_setup_icon_glow()` still read them at runtime. Only
  `BUTTON_TOOLTIPS` is fully eliminated (nothing reads it once its 4 values are baked into the scene).
- Autoload signal connections (`ZoneManager.zone_changed`, `ZoneManager.zone_unlocked`, `GameData.save_loaded`) CANNOT become scene `[connection]` blocks - those only wire signals between nodes
  inside the same scene, and autoloads are singletons outside it. These three lines stay in `_ready()` exactly as they are.
- Godot enum literals used below: `Control.MOUSE_FILTER_IGNORE = 2`, `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`, `Control.PRESET_CENTER = 8` (all four anchors set to 0.5,
  which is how `set_anchors_preset(Control.PRESET_CENTER)` + an explicit `position`/`size` translates into `anchor_left/top/right/bottom = 0.5` plus `offset_left/top/right/bottom`).
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `ZoneManager`/`GameData`/other-autoload "Identifier
  not found" line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the quit button, icon-glow overlays, and static button content into the scene file

**Files:**
- Modify: `scenes/ui/hotbar.tscn`
- Modify: `scripts/ui/hotbar.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `_button_glows["ButtonName"] = {"glow": TextureRect, "icon": TextureRect}` populated via `button.get_node("Glow")`/`get_node("Icon")` lookups instead of runtime construction - the dict
  shape callers rely on (tests included) is unchanged.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_ui_scenes.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after this task.

- [ ] **Step 2: Add two sub-resources, the QuitButton node, and Glow/Icon children on all 6 hover buttons to `scenes/ui/hotbar.tscn`**

Read the current file first (it already has 6 sub-resources: `btn_normal`, `btn_hover`, `btn_pressed`, `bar_bg`, `bar_fill`, `title_settings`, plus 10 `ext_resource` entries at the top - `load_steps`
is currently `17`; this task adds 2 more sub-resources so it becomes `19`).

Add these two sub-resources right after the existing `[sub_resource type="LabelSettings" id="title_settings"]` block (before the first `[node ...]` line):

```
[sub_resource type="StyleBoxFlat" id="quit_normal"]
bg_color = Color(0.55, 0.1, 0.08, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.8, 0.3, 0.25, 1)
corner_radius_top_left = 3
corner_radius_top_right = 3
corner_radius_bottom_right = 3
corner_radius_bottom_left = 3

[sub_resource type="StyleBoxFlat" id="quit_hover"]
bg_color = Color(0.75, 0.15, 0.1, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.8, 0.3, 0.25, 1)
corner_radius_top_left = 3
corner_radius_top_right = 3
corner_radius_bottom_right = 3
corner_radius_bottom_left = 3
```

(`quit_hover` matches the original code's `style.duplicate()` behavior - every property carries over from `quit_normal` except `bg_color`, which is the only one the original overrode.)

Change `load_steps=17` to `load_steps=19` in the file's first line.

Now replace each of the 6 hover-color button node blocks (`InventoryButton`, `AbilitiesButton`, `SaveButton`, `OptionsButton`, `RespecButton`, `AchievementsButton`, all under
`parent="LeftPanel/LeftButtons"`) with the versions below - each drops `theme_override_constants/icon_max_width`, `icon`, `icon_alignment`, and `expand_icon` (dead once the button's own built-in
icon is replaced by the new `Glow`/`Icon` children below it) and updates `tooltip_text` to the richer static string that used to come from the runtime `BUTTON_TOOLTIPS` dict (or, for
`OptionsButton`/`RespecButton`, adds the permanent `modulate` dimming that used to come from the runtime "Coming soon" loop):

```
[node name="InventoryButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
tooltip_text = "Inventory\nClick here to manage equipment."
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/InventoryButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("4_inv")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/InventoryButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("4_inv")
expand_mode = 1
stretch_mode = 0

[node name="AbilitiesButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
tooltip_text = "Abilities\nClick here to manage abilities and attributes."
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/AbilitiesButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("5_abil")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/AbilitiesButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("5_abil")
expand_mode = 1
stretch_mode = 0

[node name="SaveButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
tooltip_text = "Save Game\nClick here to save your progress."
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/SaveButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("6_save")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/SaveButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("6_save")
expand_mode = 1
stretch_mode = 0

[node name="OptionsButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
modulate = Color(1, 1, 1, 0.5)
tooltip_text = "Coming soon"
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/OptionsButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("7_opt")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/OptionsButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("7_opt")
expand_mode = 1
stretch_mode = 0

[node name="RespecButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
modulate = Color(1, 1, 1, 0.5)
tooltip_text = "Coming soon"
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/RespecButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("8_respec")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/RespecButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("8_respec")
expand_mode = 1
stretch_mode = 0

[node name="AchievementsButton" type="Button" parent="LeftPanel/LeftButtons"]
unique_name_in_owner = true
custom_minimum_size = Vector2(42, 42)
layout_mode = 2
size_flags_vertical = 4
tooltip_text = "Achievements\nClick here to view your achievements."
theme_override_styles/normal = SubResource("btn_normal")
theme_override_styles/hover = SubResource("btn_hover")
theme_override_styles/pressed = SubResource("btn_pressed")

[node name="Glow" type="TextureRect" parent="LeftPanel/LeftButtons/AchievementsButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -19.0
offset_top = -19.0
offset_right = 19.0
offset_bottom = 19.0
mouse_filter = 2
texture = ExtResource("9_ach")
expand_mode = 1
stretch_mode = 0
modulate = Color(0.45, 1.0, 0.35, 0.9)
visible = false

[node name="Icon" type="TextureRect" parent="LeftPanel/LeftButtons/AchievementsButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
mouse_filter = 2
texture = ExtResource("9_ach")
expand_mode = 1
stretch_mode = 0
```

Do NOT touch `ZoneMapButton` (under `MiddlePanel/MapCenter`) - it is not in `HOVER_COLORS`/`MENU_BUTTON_GROUPS`, keeps its own `icon = ExtResource("10_map")` and its own script
(`zone_map_toggle_button.gd`) exactly as it is, completely out of scope for this plan.

Finally, add the `QuitButton` as a direct child of the scene's root `Hotbar` node (a sibling of `Strip`/`LeftPanel`/`MiddlePanel`/`RightPanel`, added last, after the `[node name="RightPanel" ...]`
subtree's last line and before any `[connection]` blocks):

```
[node name="QuitButton" type="Button" parent="."]
layout_mode = 0
offset_left = 442.0
offset_top = 4.0
offset_right = 468.0
offset_bottom = 30.0
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("quit_normal")
theme_override_styles/hover = SubResource("quit_hover")
tooltip_text = "Quit\nClick here to return to the save select screen."
text = "x"
```

Then add these `[connection]` blocks at the very end of the file (after the last node):

```
[connection signal="pressed" from="LeftPanel/LeftButtons/InventoryButton" to="." method="_on_menu_button_pressed" binds=["inventory_window"]]
[connection signal="pressed" from="LeftPanel/LeftButtons/AbilitiesButton" to="." method="_on_menu_button_pressed" binds=["abilities_window"]]
[connection signal="pressed" from="LeftPanel/LeftButtons/AchievementsButton" to="." method="_on_menu_button_pressed" binds=["achievements_window"]]
[connection signal="pressed" from="LeftPanel/LeftButtons/SaveButton" to="." method="_on_save_pressed"]
[connection signal="pressed" from="QuitButton" to="." method="_on_quit_pressed"]
```

Notes on values: `QuitButton`'s rect is the original code's `position = Vector2(442, 4)`, `size = Vector2(26, 26)` (`offset_right = 442+26 = 468`, `offset_bottom = 4+26 = 30`). Every `Glow`
node's rect comes from `WHEEL_CENTER`-style math the original code already computed directly (`position = Vector2(-19, -19)`, `size = Vector2(38, 38)`, with `anchors_preset = PRESET_CENTER` making
those numbers relative to the button's own center point) - `offset_right = -19+38 = 19`, `offset_bottom = -19+38 = 19`; every `Icon` node is `position = Vector2(-14, -14)`, `size = Vector2(28, 28)`
-> `offset_right = -14+28 = 14`, `offset_bottom = 14`. Each button's `Glow`/`Icon` texture reuses the EXACT SAME `ExtResource` id that button's own (now-deleted) `icon` property used to reference -
do not introduce new `ext_resource` entries for these, the ids already exist in the file header (`4_inv`/`5_abil`/`6_save`/`7_opt`/`8_respec`/`9_ach`).

- [ ] **Step 3: Rewrite `scripts/ui/hotbar.gd`**

Replace the full file with:

```gdscript
# hotbar.gd
# The bottom hotbar (scenes/ui/hotbar.tscn), matching the original layout:
# left panel = menu buttons, middle = world-map toggle, right = zone name +
# story progress bar + stage counter. Zone info follows
# ZoneManager.zone_changed; progress reads the live save's quest progress
# (ZoneProgression) and refreshes after battles via GameData.save_loaded and
# ZoneManager.zone_unlocked.
#
# Menu buttons open the full-screen overlays (group "menu_screen"); while a
# screen is open, its button's white icon glows green like the original.
extends Control

# button unique name -> the menu-screen group it opens.
const MENU_BUTTON_GROUPS: Dictionary[String, String] = {
	"InventoryButton": "inventory_window",
	"AbilitiesButton": "abilities_window",
	"AchievementsButton": "achievements_window",
}
const GLOW_COLOR: Color = Color(0.45, 1.0, 0.35, 0.9)
const ACTIVE_ICON_COLOR: Color = Color(0.7, 1.0, 0.6)
# Every button hovers in its own color, per the live-game captures in
# references/hotbar/ (*_glow_with_tooltip.png).
const HOVER_COLORS: Dictionary[String, Color] = {
	"InventoryButton": Color(1.0, 0.4, 0.8),      # pink
	"AbilitiesButton": Color(0.45, 1.0, 0.35),    # green
	"SaveButton": Color(0.35, 0.6, 1.0),          # blue
	"OptionsButton": Color(1.0, 0.9, 0.3),        # yellow
	"RespecButton": Color(0.7, 0.4, 1.0),         # violet
	"AchievementsButton": Color(1.0, 0.55, 0.2),  # burnt orange
}

@onready var zone_title: Label = %ZoneTitle
@onready var zone_subtitle: Label = %ZoneSubtitle
@onready var progress_bar: ProgressBar = %ZoneProgress
@onready var stage_label: Label = %StageLabel

var _button_glows: Dictionary = {}  # button name -> {glow, icon}


func _ready():
	ZoneManager.zone_changed.connect(_on_zone_changed)
	ZoneManager.zone_unlocked.connect(func(_zone): _refresh(ZoneManager.current_zone))
	GameData.save_loaded.connect(func(_slot): _refresh(ZoneManager.current_zone))
	for button_name in HOVER_COLORS:
		_setup_icon_glow(get_node("%" + button_name))
	_wire_screen_visibility.call_deferred()
	_refresh(ZoneManager.current_zone)


func _on_quit_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Fetches the pre-built glow/icon overlay children (see hotbar.tscn) and
# wires the per-button hover tint - the active (menu-open) state always
# wins over hover, matching the original's single green-glow priority.
func _setup_icon_glow(button: Button) -> void:
	var glow: TextureRect = button.get_node("Glow")
	var icon: TextureRect = button.get_node("Icon")
	_button_glows[button.name] = {"glow": glow, "icon": icon}
	var hover_color: Color = HOVER_COLORS.get(button.name, Color.WHITE)
	button.mouse_entered.connect(func():
		if not glow.visible:
			icon.modulate = hover_color)
	button.mouse_exited.connect(func():
		if not glow.visible:
			icon.modulate = Color.WHITE)


# The screens can close themselves (their X button) - follow their
# visibility to keep the glows honest. Deferred: the screens live in the
# game scene, which finishes building after the hotbar.
func _wire_screen_visibility() -> void:
	for group in MENU_BUTTON_GROUPS.values():
		var screen: Node = get_tree().get_first_node_in_group(str(group))
		if screen != null:
			screen.visibility_changed.connect(_update_glows)
	_update_glows()


func _on_menu_button_pressed(group: String) -> void:
	toggle_menu_screen(group)


# Opens/closes one of the full-screen menu overlays (all in group
# "menu_screen"); opening one closes the others, like the original's single
# KRINMENU clip that could only show one frame at a time.
func toggle_menu_screen(group: String) -> void:
	var target: Node = get_tree().get_first_node_in_group(group)
	if target == null:
		return
	var opening: bool = not target.visible
	for screen in get_tree().get_nodes_in_group("menu_screen"):
		screen.visible = false
	target.visible = opening
	_update_glows()


func _update_glows() -> void:
	for button_name in MENU_BUTTON_GROUPS:
		var parts: Dictionary = _button_glows.get(button_name, {})
		if parts.is_empty():
			continue
		var screen: Node = get_tree().get_first_node_in_group(str(MENU_BUTTON_GROUPS[button_name]))
		var active: bool = screen != null and screen.visible
		parts["glow"].visible = active
		parts["icon"].modulate = ACTIVE_ICON_COLOR if active else Color.WHITE


func _on_zone_changed(zone_id: int) -> void:
	_refresh(zone_id)


func _refresh(zone_id: int) -> void:
	var zone: Dictionary = ZoneManager.ZONES.get(zone_id, {})
	zone_title.text = "Zone %d" % zone_id
	zone_subtitle.text = "%s: %s" % [zone.get("name", "?"), zone.get("subtitle", "?")]
	var progress: int = 0
	var progress_max: int = int(ZoneProgression.QUEST_HUB.get(zone_id, {}).get("progress_max", 1))
	if GameData.current_save != null:
		progress = ZoneProgression.quest_progress(GameData.current_save, zone_id)
	progress_bar.max_value = progress_max
	progress_bar.value = min(progress, progress_max)
	stage_label.text = "Stage %d" % (min(progress, progress_max) + 1)


func _on_save_pressed() -> void:
	if GameData.save_game():
		zone_subtitle.text = "Game saved."
		await get_tree().create_timer(1.2).timeout
		_refresh(ZoneManager.current_zone)
```

Removed: `BUTTON_TOOLTIPS` constant (its 4 values are now baked directly into the `.tscn`'s `tooltip_text` properties). `_build_quit_button()` function (fully replaced by the static `QuitButton`
node + `[connection]` block - `_on_quit_pressed()` itself is unchanged, just no longer connected from code). The `for button_name in MENU_BUTTON_GROUPS: ... .connect(...)` loop, the
`%SaveButton.pressed.connect(_on_save_pressed)` line, the `if BUTTON_TOOLTIPS.has(button_name): ...` line, and the `for button_name in ["OptionsButton", "RespecButton"]: ...` dimming loop - all five
replaced by static scene content (the 5 `[connection]` blocks plus the baked `tooltip_text`/`modulate` properties from Step 2).

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/hotbar.gd --path .`
Expected: only the known autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests, but `test_hotbar_menu_toggle_is_exclusive_and_glows` directly exercises the new `Glow`/`Icon` node wiring - a real functional
check, not just a compile check).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/hotbar.tscn scripts/ui/hotbar.gd
git commit -m "refactor: move Hotbar's quit button and icon-glow overlays into the scene file"
```

---

### Task 2: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly.

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/ui/hotbar.tscn` headlessly to a screenshot) and confirm by eye: the 6 left-panel buttons still show their correct icons, hovering each shows its own tint color
(pink/green/blue/yellow/violet/burnt orange per `HOVER_COLORS`), `OptionsButton`/`RespecButton` are still visibly dimmed with a "Coming soon" tooltip, opening the inventory/abilities/achievements
screens still makes the corresponding button's icon glow green and stay lit while the screen is open, the red X `QuitButton` still sits at its original spot near the world-map panel and returns to
the save-select screen when clicked, and the zone title/subtitle/progress bar/stage label still update correctly.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

In the "UI architecture: native Godot Containers instead of code-built controls" section, extend the existing `**DONE (2026-07-21):**` paragraph to also mention `hotbar.gd`, e.g. change the
sentence listing completed files/screens to read:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/menu/abilities_window.gd`,
`scripts/ui/menu/achievements_window.gd`, and `scripts/ui/hotbar.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, `store_window.tscn` now owns every static chrome
node plus a `GridContainer` for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar chrome plus a `GridContainer` for the 6x6 slot grid, `abilities_window.tscn` now owns its
static chrome/attribute panel plus a `VBoxContainer` for the 5-row ability pool (the 28-node talent tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code via a
reusable `talent_node.tscn`, the same instanced-`PackedScene` pattern as `ItemSlot`, and the 8-socket wheel stays entirely code-driven by design), `achievements_window.tscn` now owns its chrome
plus all 10 fixed-position achievement plates (only each plate's locked/unlocked `StyleBoxFlat` and label color stay code-driven), and `hotbar.tscn` - already the most declarative of the group,
built with real `HBoxContainer`/`CenterContainer`/`VBoxContainer` layout from the start - now also owns the quit button and every button's glow/icon overlay children, with only the per-instance
hover-tint wiring left in code. Everything else named in this phase (`battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark hotbar container migration done in NEXT_PHASES"
```
