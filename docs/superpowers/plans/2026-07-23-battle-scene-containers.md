# Battle Scene: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/battle/battle_scene.gd` off imperative runtime Control-building. This is the last item in the "UI architecture: native Godot Containers instead of code-built controls"
phase - every other named screen (`item_slot`, `store_window`, `inventory_panel`, `abilities_window`, `achievements_window`, `hotbar`, `inventory_window`, `main_menu`, `victory_screen`) is already
migrated.

**Architecture:** `scenes/battle_scene.tscn` is already partially declarative (root `BattleScene`, `Sky`/`Background` TextureRects, `Battlefield` Node2D, and the `UI` CanvasLayer with
`TurnLabel`/`SpeechLabel`/`ResultPanel`). Four things still get built at runtime, with four different right answers:

1. **The bottom bar** (`_build_bottom_bar()`) - backdrop, three chrome panels, the stance-row host, the Pass ring, the Pass button, and the Retreat button. Every one of these is fixed count and
   fixed position - all of it moves into the `.tscn`. Only the Pass ring's actual `_draw()` callback (color depends on live turn state) stays code.
2. **The sky-fill color patch** (`_load_background()`'s lazy `SkyFill` node) - a single node whose color/size depend on which zone background loaded. The NODE becomes static (declared once in the
   `.tscn`); only its color/size mutation stays code, replacing the current get-or-create-then-`move_child` dance.
3. **Per-unit overlays** (`_add_unit_overlay()`) - name label, health bar + value, focus bar, hover ring, and hit button, one set per battling unit (2-6 depending on the roster). This is a
   genuinely dynamic COUNT with a fixed STRUCTURE - exactly the case for a reusable `PackedScene` instanced per unit, the same pattern already used for `ItemSlot`/`talent_node.tscn`/
   `VictoryExperienceRow`. New `scenes/battle/unit_overlay.tscn` + `scripts/battle/unit_overlay.gd`.
4. **Per-companion stance rows** (`_populate_stance_rows()`) - a name label plus 5 stance-mode buttons, 0-2 rows depending on which companions are actually deployed. Same reusable-`PackedScene`
   case as (3). New `scenes/battle/stance_row.tscn` + `scripts/battle/stance_row.gd`.

Everything else stays exactly as-is, by design, matching this phase's established precedent for genuinely live-recomputed content with no reusable template: the **radial ability menu**
(`_on_unit_clicked`/`_style_orb`, orb count/position/color varies every click), **floating combat text** (`_float_text`, transient and tweened per event), and **projectile bolts**
(`_fire_projectile`, transient per event). None of these get touched by this plan.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_battle_scene.gd`'s `test_full_battle_scene_run` must keep passing unchanged. Confirmed via `rg` before writing this plan: it reads `scene._visuals` (size/indexing),
  `scene.units`, `scene._health_bars[1].max_value`, `scene.result_panel.visible`, `scene.get_node_or_null("VictoryScreen")`, `scene.runner`, and `scene.battle_finished` - nothing about the bottom
  bar, stance rows, sky fill, or per-unit overlay internals (`_overlays`/`_rings`/`_health_values`/`_focus_bars`/`_add_unit_overlay`/`_populate_stance_rows`/`_stance_rows`/`_pass_ring`/
  `_pass_button`/`BottomBar`/`StanceHost` all have ZERO test references anywhere in `test/`). No other test file references `battle_scene`/`BattleScene` at all. No test file needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere, except one incidental correctness fix noted in Task 2 (a redundant runtime
  `set_anchors_preset()` call that was overwriting the `.tscn`'s own declared anchor preset every single call - folding the final value into the `.tscn` directly and deleting the now-pointless
  runtime call).
- Godot enum literals used below (confirmed against this project's actual Godot 4.7.1 binary, not assumed from memory): `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`,
  `Control.MOUSE_FILTER_STOP = 0`, `Control.MOUSE_FILTER_IGNORE = 2`, `Control.PRESET_TOP_LEFT = 0`, `HORIZONTAL_ALIGNMENT_CENTER = 1`.
- `_pass_button: Button` is currently declared as an instance var but read ONLY inside its own construction (confirmed via `rg -n "_pass_button" scripts/battle/battle_scene.gd`) - it becomes fully
  local to the `.tscn`'s static `[connection]` block in Task 1, and the var declaration is deleted, not kept as a dead `@onready`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document. If a fresh worktree's first run shows unrelated parse errors or a much lower pass count than
  expected, force a full asset reimport first: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .`. This is ALSO required after any task that introduces a new
  `class_name` (Tasks 3 and 4 each add one) - the global script class cache is per-checkout and won't pick up a brand-new `class_name` without this step, which otherwise manifests as either a
  `Could not find type "X" in the current scope` parse error or, if skipped and the stale class ends up wired to the wrong script, a GUT failure like `Trying to assign value of type 'Control' to
  a variable of type '<script>.gd'` - both are cache-staleness artifacts, not real regressions, but re-run the reimport and re-verify rather than assuming that.
- `test_full_battle_scene_run`'s WIN-outcome assertions are gated behind a probabilistic AI-driven battle outcome and won't necessarily execute on every run - if useful, re-run
  `-gtest=test/integration/test_battle_scene.gd` a few times in a row to get real coverage of the WIN path (which is what exercises `_finish_battle()`, not this plan's changes directly, but a good
  sanity signal that nothing upstream broke).
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the bottom bar's static chrome into the scene file

**Files:**
- Modify: `scenes/battle_scene.tscn`
- Modify: `scripts/battle/battle_scene.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `@onready var _pass_ring: Control = $BottomBar/PassRing` and `@onready var stance_host: Control = $BottomBar/StanceHost`, both read by Task 4's `_populate_stance_rows()` rewrite (which
  touches a disjoint part of the same `.gd` file - no ordering dependency, just noting the shared reference point).

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_battle_scene.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Add the `BottomBar` subtree to `scenes/battle_scene.tscn`**

Read the current file first (root `BattleScene` Control, `Sky`/`Background` TextureRects, `Battlefield` Node2D, `UI` CanvasLayer with its own children). Add one new `ext_resource` (for the
hotbar background texture) and the full `BottomBar` subtree as a new child of the root (`parent="."`), placed after `Battlefield` and before `UI` (order doesn't matter functionally, but this
keeps 2D-space nodes grouped together before the CanvasLayer):

```
[ext_resource type="Texture2D" path="res://assets/ui/hotbar/background.png" id="2_hotbarbg"]

[node name="BottomBar" type="Control" parent="."]
layout_mode = 0
offset_left = 0.0
offset_top = 470.0
offset_right = 800.0
offset_bottom = 600.0
mouse_filter = 2

[node name="Backdrop" type="ColorRect" parent="BottomBar"]
layout_mode = 0
offset_left = 0.0
offset_top = 0.0
offset_right = 800.0
offset_bottom = 130.0
mouse_filter = 0
color = Color(0.04, 0.05, 0.06, 1)

[node name="Panel1" type="TextureRect" parent="BottomBar"]
layout_mode = 0
offset_left = 12.0
offset_top = 10.0
offset_right = 332.0
offset_bottom = 120.0
mouse_filter = 2
texture = ExtResource("2_hotbarbg")
expand_mode = 1
stretch_mode = 0

[node name="Panel2" type="TextureRect" parent="BottomBar"]
layout_mode = 0
offset_left = 340.0
offset_top = 10.0
offset_right = 460.0
offset_bottom = 120.0
mouse_filter = 2
texture = ExtResource("2_hotbarbg")
expand_mode = 1
stretch_mode = 0

[node name="Panel3" type="TextureRect" parent="BottomBar"]
layout_mode = 0
offset_left = 468.0
offset_top = 10.0
offset_right = 788.0
offset_bottom = 120.0
mouse_filter = 2
texture = ExtResource("2_hotbarbg")
expand_mode = 1
stretch_mode = 0

[node name="StanceHost" type="Control" parent="BottomBar"]
layout_mode = 0
offset_left = 24.0
offset_top = 18.0
offset_right = 400.0
offset_bottom = 130.0
mouse_filter = 2

[node name="PassRing" type="Control" parent="BottomBar"]
layout_mode = 0
offset_left = 400.0
offset_top = 65.0
offset_right = 400.0
offset_bottom = 65.0
mouse_filter = 2

[node name="PassButton" type="Button" parent="BottomBar"]
layout_mode = 0
offset_left = 372.0
offset_top = 37.0
offset_right = 428.0
offset_bottom = 93.0
theme_override_colors/font_color = Color(0.95, 0.75, 0.2, 1)
theme_override_font_sizes/font_size = 22
theme_override_styles/normal = SubResource("StyleBoxFlat_pass_normal")
theme_override_styles/hover = SubResource("StyleBoxFlat_pass_hover")
theme_override_styles/pressed = SubResource("StyleBoxFlat_pass_hover")
text = "!"
tooltip_text = "Pass your turn"

[node name="RetreatButton" type="Button" parent="BottomBar"]
layout_mode = 0
offset_left = 442.0
offset_top = 12.0
offset_right = 468.0
offset_bottom = 38.0
theme_override_styles/normal = SubResource("StyleBoxFlat_retreat_normal")
theme_override_styles/hover = SubResource("StyleBoxFlat_retreat_hover")
text = "x"
tooltip_text = "Retreat from battle"

[connection signal="draw" from="BottomBar/PassRing" to="." method="_draw_pass_ring"]
[connection signal="pressed" from="BottomBar/PassButton" to="." method="_on_pass_pressed"]
[connection signal="pressed" from="BottomBar/RetreatButton" to="." method="_on_retreat_pressed"]
```

Also add these four `sub_resource` blocks (anywhere before the `BottomBar` node block that references them, e.g. right after the `ext_resource` lines):

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_pass_normal"]
bg_color = Color(0.1, 0.1, 0.11, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.3, 0.3, 0.32, 1)
corner_radius_top_left = 99
corner_radius_top_right = 99
corner_radius_bottom_right = 99
corner_radius_bottom_left = 99

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_pass_hover"]
bg_color = Color(0.16, 0.16, 0.18, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.3, 0.3, 0.32, 1)
corner_radius_top_left = 99
corner_radius_top_right = 99
corner_radius_bottom_right = 99
corner_radius_bottom_left = 99

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_retreat_normal"]
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

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_retreat_hover"]
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

Notes on values: `BottomBar` is `Rect2(0, BOTTOM_BAR_TOP, 800, 600-BOTTOM_BAR_TOP)` = `Rect2(0, 470, 800, 130)`. `Backdrop` fills it exactly (`0,0,800,130` local). The 3 panels are the original's
`Rect2(12,10,320,110)`/`Rect2(340,10,120,110)`/`Rect2(468,10,320,110)` verbatim. `StanceHost` is an empty shell at local `(24,18)` - its `offset_right`/`offset_bottom` values are arbitrary (it's a
plain `Control`, not a container, so these don't constrain anything; Task 4's rows position themselves independently within it) but must be present for valid `.tscn` syntax. `PassRing` is a
zero-size `Control` at local `(400,65)` (`offset_right`/`bottom` equal to `offset_left`/`top` - it never sizes itself, only anchors the `_draw()` callback's coordinate origin, exactly like the
runtime version's bare `Control.new()` with only `.position` set). `PassButton` is local `(400-28, 65-28)` to `(400+28, 65+28)` = `(372,37)` to `(428,93)`, matching
`Vector2(400 - 28, 65 - 28)` + `custom_minimum_size (56,56)`. `RetreatButton` is local `(442,12)` to `(442+26,12+26)` = `(442,12)` to `(468,38)`. Only `PassButton`/`RetreatButton` get static
`theme_override_styles` here because their styling truly never changes at runtime (the original set it once at construction and never touched it again) - contrast this with the stance-row
buttons in Task 4, whose styling IS re-applied every refresh and so stays fully code-driven. The `draw` signal is an ordinary `CanvasItem` signal - it connects via a static `[connection]` block
exactly like `pressed` does, since `PassRing` is a single always-present node (not per-instance like the unit-overlay rings in Task 3, which DO need code-side connection because their `slot` bind
varies per instance).

- [ ] **Step 3: Delete `_build_bottom_bar()` and simplify related declarations in `scripts/battle/battle_scene.gd`**

Delete `_build_bottom_bar()` entirely (the whole function, from `func _build_bottom_bar() -> void:` through its closing before `_draw_pass_ring()`).

Replace the `var _pass_ring: Control = null` and `var _pass_button: Button = null` declarations with:

```gdscript
@onready var _pass_ring: Control = $BottomBar/PassRing
@onready var stance_host: Control = $BottomBar/StanceHost
```

(`_pass_button` had zero readers outside its own construction - deleted outright, not kept as a dead `@onready`. `stance_host` replaces the `get_node("BottomBar/StanceHost")` call currently at
the top of `_populate_stance_rows()` - Task 4 updates that function's body; for THIS task, just add the declaration, don't touch `_populate_stance_rows()` yet.)

In `_ready()`, remove the `_build_bottom_bar()` call. The function should now read:

```gdscript
func _ready():
	result_panel.hide()
	speech_label.text = ""
	continue_button.pressed.connect(_on_continue_pressed)
	if not ZoneManager.pending_battle.is_empty():
		start_battle(ZoneManager.pending_battle)
		ZoneManager.pending_battle = {}
```

Leave `_draw_pass_ring()`, `_on_pass_pressed()`, and `_on_retreat_pressed()` completely untouched - all three still work correctly against the new `@onready`/static-node setup.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/battle_scene.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests). `_populate_stance_rows()` still calls `get_node("BottomBar/StanceHost")` internally at this point (Task 4 hasn't touched it
yet) - that call still resolves correctly since the node now exists statically, so nothing breaks between tasks here.

- [ ] **Step 6: Commit**

```bash
git add scenes/battle_scene.tscn scripts/battle/battle_scene.gd
git commit -m "refactor: move BattleScene's bottom bar chrome into the scene file"
```

---

### Task 2: Make `SkyFill` a static node and drop the redundant Sky anchor reset

**Files:**
- Modify: `scenes/battle_scene.tscn`
- Modify: `scripts/battle/battle_scene.gd`

**Interfaces:**
- Consumes: nothing from Task 1 (disjoint nodes/functions).
- Produces: `@onready var sky_fill: ColorRect = $SkyFill`, read only within `_load_background()` itself - nothing else depends on it.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Add `SkyFill` to `scenes/battle_scene.tscn` and fix `Sky`'s anchor preset**

Add a `SkyFill` `ColorRect` as the FIRST child of the root (before `Sky`, so it draws behind everything without needing a runtime `move_child(fill, 0)` call):

```
[node name="SkyFill" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 0.0
offset_top = 0.0
offset_right = 800.0
offset_bottom = 292.0
mouse_filter = 2
```

(`offset_bottom` here is just a placeholder full-height value - `_load_background()` overwrites both `.size` and `.position` every call before anything is ever shown, so the exact number doesn't
matter, only that it's a valid `.tscn` entry. `color` is left at its Godot default - also always overwritten before display.)

Also change the existing `Sky` node's anchor properties from `anchors_preset = 15` / `anchor_right = 1.0` / `anchor_bottom = 1.0` / `grow_horizontal = 2` / `grow_vertical = 2` to just
`anchors_preset = 0` (delete the other four anchor/grow lines entirely) - this is `Control.PRESET_TOP_LEFT`, which is what `_load_background()` already force-sets on every call via
`sky.set_anchors_preset(Control.PRESET_TOP_LEFT)` before positioning it; baking the correct preset into the `.tscn` from the start means that runtime call becomes a no-op and gets deleted in
Step 3. `Sky`'s `layout_mode`/`mouse_filter`/`expand_mode`/`stretch_mode` lines stay exactly as they are.

- [ ] **Step 3: Update `_load_background()` in `scripts/battle/battle_scene.gd`**

Add `@onready var sky_fill: ColorRect = $SkyFill` to the existing `@onready` block (alongside `background`/`sky`/`battlefield`/etc).

Replace the function's tail - from `sky.set_anchors_preset(Control.PRESET_TOP_LEFT)` through the end of the function - with:

```gdscript
	sky.position = Vector2(0, SKY_HORIZON_Y - strip_height)
	sky.size = Vector2(800, strip_height)
	# Solid fill above the strip, sampled from its top edge.
	var image: Image = sky_texture.get_image()
	var top_color: Color = image.get_pixel(int(image.get_width() / 2.0), 0)
	sky_fill.color = top_color
	sky_fill.position = Vector2.ZERO
	sky_fill.size = Vector2(800, SKY_HORIZON_Y - strip_height + 2)
```

(The `sky.set_anchors_preset(Control.PRESET_TOP_LEFT)` line is gone - Step 2's `.tscn` change already establishes that anchor preset once, at scene load, instead of every single call. The
lazy-create-or-reuse `get_node_or_null("SkyFill")` / `ColorRect.new()` / `add_child` / `move_child` block is replaced by the single `sky_fill` reference, which already exists and is already first
in draw order.)

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/battle_scene.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 1's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/battle_scene.tscn scripts/battle/battle_scene.gd
git commit -m "refactor: make BattleScene's sky-fill color patch a static node"
```

---

### Task 3: Create the reusable `UnitOverlay` scene and rewrite `_add_unit_overlay()`

**Files:**
- Create: `scripts/battle/unit_overlay.gd`
- Create: `scenes/battle/unit_overlay.tscn`
- Modify: `scripts/battle/battle_scene.gd`

**Interfaces:**
- Consumes: nothing from Tasks 1/2 (disjoint files/nodes).
- Produces: `class_name UnitOverlay` with public `@onready` members `ring`/`name_label`/`health_bar`/`health_value`/`focus_bar`/`hit_button` and a `setup(unit_name: String) -> void` method. Task 4
  is a separate function (`_populate_stance_rows()`) and doesn't depend on this task's specifics.
- **New `class_name`** (`UnitOverlay`) - after this task's files are created, force a global-class-cache reimport (`--headless --editor --quit --path .`) before compile-checking or running tests,
  per the Global Constraints note above.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Write `scripts/battle/unit_overlay.gd`**

```gdscript
# unit_overlay.gd
# The unmirrored per-unit HUD overlay shown over each battling character's
# paper doll: name, health bar + value, focus bar, and a hover/click zone.
# battle_scene.gd instances one per unit slot, positions it at the unit's
# world position, and wires the hover/click signals itself (the slot each
# instance represents is only known at instance time, not authoring time).
# The hover ring's actual `_draw()` callback also stays in battle_scene.gd
# (its color depends on the unit's live relation to the player) - this
# script only exposes the ring node for that connection.
extends Control
class_name UnitOverlay

@onready var ring: Control = $Ring
@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_value: Label = $HealthValue
@onready var focus_bar: ProgressBar = $FocusBar
@onready var hit_button: Button = $HitButton


func setup(unit_name: String) -> void:
	name_label.text = unit_name
```

- [ ] **Step 3: Write `scenes/battle/unit_overlay.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/battle/unit_overlay.gd" id="1_overlay"]

[node name="UnitOverlay" type="Control"]
mouse_filter = 2
script = ExtResource("1_overlay")

[node name="Ring" type="Control" parent="."]
layout_mode = 0
mouse_filter = 2
visible = false

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
offset_left = -52.0
offset_top = -82.0
offset_right = 52.0
offset_bottom = -68.0
mouse_filter = 2
theme_override_font_sizes/font_size = 10
horizontal_alignment = 1

[node name="HealthBar" type="ProgressBar" parent="."]
layout_mode = 0
offset_left = -26.0
offset_top = -66.0
offset_right = 26.0
offset_bottom = -60.0
custom_minimum_size = Vector2(52, 6)
mouse_filter = 2
show_percentage = false

[node name="HealthValue" type="Label" parent="."]
layout_mode = 0
offset_left = 28.0
offset_top = -69.0
offset_right = 74.0
offset_bottom = -57.0
mouse_filter = 2
theme_override_font_sizes/font_size = 9

[node name="FocusBar" type="ProgressBar" parent="."]
layout_mode = 0
offset_left = -26.0
offset_top = -58.0
offset_right = 26.0
offset_bottom = -55.0
custom_minimum_size = Vector2(52, 3)
mouse_filter = 2
modulate = Color(0.5, 0.7, 1.0, 1)
show_percentage = false

[node name="HitButton" type="Button" parent="."]
layout_mode = 0
offset_left = -28.0
offset_top = -52.0
offset_right = 28.0
offset_bottom = 48.0
custom_minimum_size = Vector2(56, 100)
flat = true
```

Notes on values: every offset is copied verbatim from the pre-migration code's local `Rect2`/`position`+`size` pairs (`Ring` has no size, matching the original bare `Control.new()` with only
`.mouse_filter`/`.visible` set - it draws via `_draw()`, not layout). `HitButton` deliberately gets NO `mouse_filter` override, matching the original (a plain `Button.new()` never had one set,
relying on the default `MOUSE_FILTER_STOP` so it can actually receive hover/click events) - do not add `mouse_filter = 2` to it, that would break click detection entirely.

- [ ] **Step 4: Force a global class cache reimport, then compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .` (required after adding the new `class_name UnitOverlay` - skipping this produces a `Could not find type
"UnitOverlay" in the current scope` parse error on the next step, or a hard-to-diagnose GUT failure if skipped past that point).
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/unit_overlay.gd --path .`
Expected: clean compile, no output at all (this script doesn't reference any autoload).

- [ ] **Step 5: Rewrite `_add_unit_overlay()` in `scripts/battle/battle_scene.gd`**

Add near the top of the file, alongside the other `const ...Scene: PackedScene = preload(...)` declarations:

```gdscript
const UnitOverlayScene: PackedScene = preload("res://scenes/battle/unit_overlay.tscn")
```

Replace `_add_unit_overlay()` with:

```gdscript
func _add_unit_overlay(slot: int, unit: CombatUnit, visual: CharacterVisual) -> void:
	_display_hp[slot] = unit.life_n
	_last_stun[slot] = unit.stun
	var overlay: UnitOverlay = UnitOverlayScene.instantiate()
	overlay.position = visual.position
	battlefield.add_child(overlay)
	overlay.setup(unit.player_name)
	_overlays[slot] = overlay
	_rings[slot] = overlay.ring
	overlay.ring.draw.connect(_draw_ring.bind(overlay.ring, slot))
	_health_bars[slot] = overlay.health_bar
	_health_values[slot] = overlay.health_value
	_focus_bars[slot] = overlay.focus_bar
	overlay.hit_button.mouse_entered.connect(_on_unit_hovered.bind(slot, true))
	overlay.hit_button.mouse_exited.connect(_on_unit_hovered.bind(slot, false))
	overlay.hit_button.pressed.connect(_on_unit_clicked.bind(slot))
```

Leave every other function completely untouched - `_draw_ring()`, `_on_unit_hovered()` (still calls `overlay.get_node_or_null("HoverInfo")`/`overlay.add_child(...)` on the `UnitOverlay` instance,
which works unchanged since `UnitOverlay extends Control`), `_relation_to_player()`, and everything in the radial-menu section are all unaffected by this task.

- [ ] **Step 6: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/battle_scene.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 7: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 2's ending count. This is the task most worth double-checking by eye if a visual/headless-screenshot check is available in the environment - re-run
`test_full_battle_scene_run` a couple of times (`-gtest=test/integration/test_battle_scene.gd`) since it directly exercises `_add_unit_overlay()` via `start_battle()` for every unit in the
roster (2-6 instances per run).

- [ ] **Step 8: Commit**

```bash
git add scripts/battle/unit_overlay.gd scenes/battle/unit_overlay.tscn scripts/battle/battle_scene.gd
git commit -m "refactor: move BattleScene's per-unit overlay into a reusable scene"
```

---

### Task 4: Create the reusable `StanceRow` scene and rewrite `_populate_stance_rows()`

**Files:**
- Create: `scripts/battle/stance_row.gd`
- Create: `scenes/battle/stance_row.tscn`
- Modify: `scripts/battle/battle_scene.gd`

**Interfaces:**
- Consumes: `stance_host: Control` (`@onready $BottomBar/StanceHost`, added in Task 1).
- Produces: `class_name StanceRow` with a public `@onready var buttons: Array[Button]` and a `setup(unit_name: String) -> void` method. Nothing later in this plan depends on it (Task 5 is
  verification only).
- **New `class_name`** (`StanceRow`) - after this task's files are created, force a global-class-cache reimport (`--headless --editor --quit --path .`) before compile-checking or running tests,
  same reasoning as Task 3.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 3's ending count exactly.

- [ ] **Step 2: Write `scripts/battle/stance_row.gd`**

```gdscript
# stance_row.gd
# One companion's stance-mode row in the battle bottom bar (name + 5
# aggression-preset buttons). battle_scene.gd instances one per deployed
# companion (0-2, only for those actually in the fight), positions it, and
# wires each button's press to that companion's party id + mode - both are
# only known at instance time. _refresh_stance_row() (still in
# battle_scene.gd) re-styles the buttons on every stance change; this
# script only exposes them.
extends Control
class_name StanceRow

@onready var name_label: Label = $NameLabel
@onready var buttons: Array[Button] = [$Mode0, $Mode1, $Mode2, $Mode3, $Mode4]


func setup(unit_name: String) -> void:
	name_label.text = unit_name
```

- [ ] **Step 3: Write `scenes/battle/stance_row.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/battle/stance_row.gd" id="1_row"]

[node name="StanceRow" type="Control"]
script = ExtResource("1_row")

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 0.0
offset_top = 4.0
offset_right = 90.0
offset_bottom = 24.0
theme_override_font_sizes/font_size = 12

[node name="Mode0" type="Button" parent="."]
layout_mode = 0
offset_left = 96.0
offset_top = 0.0
offset_right = 130.0
offset_bottom = 26.0
custom_minimum_size = Vector2(34, 26)
tooltip_text = "Phalanx"

[node name="Mode1" type="Button" parent="."]
layout_mode = 0
offset_left = 136.0
offset_top = 0.0
offset_right = 170.0
offset_bottom = 26.0
custom_minimum_size = Vector2(34, 26)
tooltip_text = "Defensive"

[node name="Mode2" type="Button" parent="."]
layout_mode = 0
offset_left = 176.0
offset_top = 0.0
offset_right = 210.0
offset_bottom = 26.0
custom_minimum_size = Vector2(34, 26)
tooltip_text = "Tactical"

[node name="Mode3" type="Button" parent="."]
layout_mode = 0
offset_left = 216.0
offset_top = 0.0
offset_right = 250.0
offset_bottom = 26.0
custom_minimum_size = Vector2(34, 26)
tooltip_text = "Aggressive"

[node name="Mode4" type="Button" parent="."]
layout_mode = 0
offset_left = 256.0
offset_top = 0.0
offset_right = 290.0
offset_bottom = 26.0
custom_minimum_size = Vector2(34, 26)
tooltip_text = "Relentless"
```

Notes on values: `NameLabel` was `Rect2(0, row_y+4, 90, 20)` -> local `(0,4)` size `(90,20)`. Each `ModeN` button's x is `96 + mode*40` for `mode=0..4` (`96,136,176,216,256`), local `y=0`, size
`(34,26)` - matches `position = Vector2(96 + mode * 40, row_y)` / `custom_minimum_size = Vector2(34, 26)` with `row_y` treated as this scene's own local origin (the row itself gets positioned at
`Vector2(0, row_y)` by the code that instances it, same convention as Task 3's `UnitOverlay` and the earlier `VictoryExperienceRow`). Tooltips are baked in directly from `Party.AGGRESSION_NAMES`
(`["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]`, a fixed constant - never varies per instance) rather than passed through `setup()`, since they're genuinely static. No
`theme_override_styles` on any `ModeN` button - the original constructs a fresh `StyleBoxFlat` in `_refresh_stance_row()` (which the current code calls immediately after building each row, before
ever showing it) and never relies on a Button's default appearance, so there's no "initial" static style worth baking in; `_refresh_stance_row()` (Step 5, unchanged) continues to fully own each
button's visual state on every call.

- [ ] **Step 4: Force a global class cache reimport, then compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .`
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/stance_row.gd --path .`
Expected: clean compile, no output at all.

- [ ] **Step 5: Rewrite `_populate_stance_rows()` in `scripts/battle/battle_scene.gd`**

Add near the top of the file, alongside `UnitOverlayScene`:

```gdscript
const StanceRowScene: PackedScene = preload("res://scenes/battle/stance_row.tscn")
```

Replace `_populate_stance_rows()` with:

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
		var buttons: Array = row.buttons
		for mode in buttons.size():
			buttons[mode].pressed.connect(_on_stance_pressed.bind(party_id, mode, slot))
		_stance_rows[party_id] = buttons
		_refresh_stance_row(party_id, Party.get_ag_mode(save, party_id) if save != null else 2)
		row_y += 46.0
```

(The old `var host: Control = get_node("BottomBar/StanceHost")` line is gone - replaced by the `stance_host` `@onready` var Task 1 added. Leave `_refresh_stance_row()`, `_party_id_for_unit()`, and
`_on_stance_pressed()` completely untouched - all three still work correctly against `_stance_rows[party_id]`'s `Array` of `Button` references, regardless of where those buttons came from.)

- [ ] **Step 6: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/battle_scene.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 7: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 3's ending count.

- [ ] **Step 8: Commit**

```bash
git add scripts/battle/stance_row.gd scenes/battle/stance_row.tscn scripts/battle/battle_scene.gd
git commit -m "refactor: move BattleScene's per-companion stance rows into a reusable scene"
```

---

### Task 5: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly (no new failures, no new tests - this whole plan is a pure refactor).

- [ ] **Step 2: Repeat runs for WIN-path coverage**

Run `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_battle_scene.gd` 3-5 times. Confirm at least one run hits a WIN
outcome and its victory-screen assertions pass (the AI-driven battle's outcome is probabilistic, so this isn't guaranteed on any single run, but the file's other tests - `test_battle_104_...`,
`test_battle_51_...` - deterministically exercise `_spawn_visuals()`/`_add_unit_overlay()`/`_populate_stance_rows()` on every run regardless of outcome, which is the real coverage this plan's
changes need).

- [ ] **Step 3: Manual visual check**

Launch the game (or render `scenes/battle_scene.tscn` headlessly to a screenshot, if the environment supports offscreen rendering - it may not, in which case say so rather than skip silently) and
confirm by eye: the bottom bar's chrome panels, Pass button, and Retreat button render and respond to clicks/hover in their original positions; per-unit health/focus bars and hover rings track
each doll correctly; stance rows appear for deployed companions with correct name/tooltip/highlight behavior on click.

- [ ] **Step 4: Update `NEXT_PHASES.md`**

Find the "UI architecture: native Godot Containers instead of code-built controls" section. Its intro paragraph currently reads (in part) "**Only `battle_scene.gd`'s own overlay-building code
(bottom bar, stance row, pass ring) is still imperative** - the last item left in this phase." Update this to reflect that the phase is now fully complete, e.g. replace that sentence and extend
the **DONE** paragraph with something like:

```markdown
**DONE (2026-07-23):** `scripts/battle/battle_scene.gd` is also migrated, completing this phase entirely. `scenes/battle_scene.tscn` now owns the bottom bar's static chrome (backdrop, three
panels, the Pass button, and the Retreat button - the Pass ring's `_draw()` callback stays code, its color depends on live turn state) and a static `SkyFill` node (only its color/size mutation,
sampled from whichever zone background loads, stays code). Two new reusable scenes cover the two genuinely-variable-count-but-fixed-structure pieces: `scenes/battle/unit_overlay.tscn` (name,
health/focus bars, hover ring, hit button - instanced once per battling unit, 2-6 depending on the roster) and `scenes/battle/stance_row.tscn` (name + 5 stance buttons - instanced once per
deployed companion, 0-2), both matching the same instanced-`PackedScene` pattern as `ItemSlot`/`talent_node.tscn`/`VictoryExperienceRow`. The radial ability menu, floating combat text, and
projectile bolts all stay fully code-driven, unchanged - each is transient, recomputed on every occurrence, with no reusable structure a static template would capture.
```

Remove or rewrite the now-stale "Only `battle_scene.gd`'s own overlay-building code... is still imperative" sentence from the intro paragraph accordingly, so the section doesn't contradict
itself.

- [ ] **Step 5: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark the UI architecture Container-migration phase complete"
```
