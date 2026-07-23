**Implementation Plan - Ability Menu Redesign**

**Problem Statement:**
The abilities screen has correct logic and the right three-region layout, but is visually sparse: talent tree nodes are plain circle buttons with no icon art, pool rows show text only, wheel sockets show initials, and the tooltip is Godot's built-in string-only popup. The goal is to bring it in line with the original `DefineSprite 3142 frame 25`: real icon art on every node and pool row, SWF-faithful connector lines on the tree (colored by prerequisite state), and a rich floating `KrinToolTipper`-style tooltip (icon + title + description + cost/cooldown + next-rank preview).

**Requirements:**
- Extract `DefineSprite 2427` (104 labeled frames) → `assets/ui/abilities/<label>.png` at 2x using `extract_item_icons.py` as a template
- Add `tooltip_description` and `tooltip_cost` to `Ability` resource from `moves_abilities.json` fields `17_tooltip_description` / `18_tooltip_cost`
- Build a reusable floating `ability_tooltip.tscn` matching the `KrinToolTipper` field set: icon, title, description, cost/cooldown, next-rank preview
- Talent tree connector lines colored gold when prerequisite is learned, dim gray when not
- Tree node buttons show the ability icon (or colored circle for passives) plus rank label
- Pool rows show 20×20 icon thumbnail + ability name
- Wheel sockets show icon instead of text initials
- Hovering any of the above pops the rich floating tooltip
- All new scenes follow the `.tscn` + Container conventions established by `item_slot.tscn` / `store_window.tscn`
- GUT tests cover the pure data helpers (`AbilityTooltipBuilder`, icon-path resolution, new `TalentTree` helper, new `Ability` fields, `ability_pool_row.tscn` population)

**Background:**
- Icon sheet: `DefineSprite 2427` (web-build ID), 104 `FrameLabelTag`s. The `extract_item_icons.py` pipeline is a direct template — change `ICON_SPRITE`, change `OUT_DIR`, remove the `.tres`-repointing section. Slot geometry is the same 31×31 design-px viewport. Missing labels fall back to the existing colored-circle placeholder.
- Tooltip data: `moves_abilities.json` already carries `17_tooltip_description` and `18_tooltip_cost` — the original game's pre-formatted strings. For passive tree nodes, description comes from `Buff.tooltip_description` (already on `buff.gd`), cost is "Passive".
- Tree connector lines: `_draw_tree_lines()` already iterates prerequisites; it just needs a per-edge `TalentTree.get_rank(save, prereq) >= 1` check to color gold vs. gray.
- All three classes share the same 28-node grid topology — `TREE_COLUMNS_X`/`TREE_ROWS_Y` in `abilities_window.gd` already encode it correctly.
- `ability_two["17_tooltip_description"]` and `["18_tooltip_cost"]` live in the `ability_two` sub-dict of each move entry.

**Proposed Solution:**
Six sequential increments, each leaving the screen in a working, demonstrable state.

```
┌────────────────────────────────────────────────────────────────────────┐
│  abilities_window.tscn  (800 × 600, existing structure preserved)      │
│ ┌──────────────────┐ ┌────────────────┐ ┌──────────────────────────┐  │
│ │  Left: Tree      │ │ Mid: Stats     │ │  Right: Wheel + Pool     │  │
│ │  28 TalentNode   │ │  (unchanged)   │ │  8 code-built sockets    │  │
│ │  + connector     │ │                │ │  + VBox of pool rows     │  │
│ │  lines (colored) │ │                │ │  (ability_pool_row.tscn) │  │
│ └──────────────────┘ └────────────────┘ └──────────────────────────┘  │
│                                                                         │
│  ability_tooltip.tscn (floating Control, hidden by default, parented   │
│  to abilities_window root so it draws on top of everything)             │
└────────────────────────────────────────────────────────────────────────┘
```

**Task Breakdown:**

Task 1: Extract ability icon assets
- Objective: produce `assets/ui/abilities/<label>.png` for every labeled frame in `DefineSprite 2427`.
- Copy `python_conversion_scripts/swf_extraction/extract_item_icons.py` → `extract_ability_icons.py`. Change `ICON_SPRITE = 2064` → `2427`, `OUT_DIR` → `assets/ui/abilities/`. Remove the `.tres`-repointing section entirely — ability icons are looked up by display name at runtime, not baked into resource files. Keep `SKIP_CIDS`, `ZOOM = 2.0`, `ICON_HALF = 15.5`, and the `paste_char` composite logic unchanged (same slot geometry). Run the script and print the extracted label list to stderr. Note any move display names in `TalentTree.TREES` that don't appear in the label list in a comment at the top of the script — those fall back to the colored-circle placeholder.
- No GUT test needed for asset extraction, but running the script twice must be idempotent.
- Demo: `assets/ui/abilities/` exists with ~100 PNGs; the script exits cleanly with a label count printed to stderr.

Task 2: Add `tooltip_description` and `tooltip_cost` to `Ability`
- Objective: surface the original game's pre-formatted tooltip strings in the `Ability` resource so the UI can use them without re-deriving them.
- Add two `@export` fields to `scripts/battle/ability.gd`: `tooltip_description: String` and `tooltip_cost: String`. In `Ability.from_json`, map `ability_two.get("17_tooltip_description")` and `ability_two.get("18_tooltip_cost")` through `_text()`. Note: these fields live in the `ability_two` sub-dict, not the top-level dict.
- Add a GUT test that loads move id=1 ("Leading Strike") via `MoveManagerAuto` and asserts both fields are non-empty strings. No other file changes in this task.
- Demo: the GUT headless run passes. `MoveManagerAuto.get_move(1).tooltip_description` returns the original text string.

Task 3: Build `ability_tooltip.tscn` and `AbilityTooltipBuilder`
- Objective: a reusable floating tooltip scene that replaces Godot's built-in string tooltip for abilities, matching the `KrinToolTipper` field set (icon, title, description, cost/cooldown, next-rank preview).
- Create `scenes/ui/menu/ability_tooltip.tscn`: a `PanelContainer` (hidden by default, `mouse_filter = IGNORE`) containing a `MarginContainer` → `HBoxContainer`. Left child: a 32×32 `ColorRect` (element color) containing a `TextureRect` (icon, `STRETCH_KEEP_ASPECT_CENTERED`, `mouse_filter = IGNORE`). Right child: a `VBoxContainer` with four `Label` nodes named `TitleLabel`, `DescLabel`, `CostLabel`, `NextRankLabel`.
- Create `scripts/ui/menu/ability_tooltip.gd` attached to the scene. Expose `populate(node: Dictionary, save: PlayerSave, move: Ability)`:
  - `TitleLabel.text` ← move display name, or `node["buff_family"].capitalize()` for passives (when `move` is null).
  - `DescLabel.text` ← `move.tooltip_description` for active nodes; `Buff.tooltip_description` for passives (look up via `BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, rank + 1))`). Fall back to `""` if the buff isn't found.
  - `CostLabel.text` ← `move.tooltip_cost` for actives; `"Passive"` for passives.
  - `NextRankLabel.text` ← `"Next Tier (Lvl. %d)" % TalentTree.required_level(node, rank)` when `rank < node["max_rank"]`; `"MAX"` when at max rank. Hide `NextRankLabel` entirely when `node` is null (pool/wheel hover context where rank progress isn't relevant).
  - Icon: load `res://assets/ui/abilities/<sanitize(move.display_name)>.png` if it exists, else `null`. Set `ColorRect.color` from `MenuTheme.ELEMENT_COLORS` using `CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)`.
- Create `scripts/ui/menu/ability_tooltip_builder.gd` as a pure `static` `RefCounted` (no Node/scene dependency): `static func build_fields(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff) -> Dictionary` returns `{title, description, cost, next_rank_text, element_color}`. This is what the GUT tests target — no scene instantiation needed.
- GUT tests: assert `build_fields` output for a known active node (move_id=100, rank=0, level=1 save) and a known passive node (INTEGRITY, rank=1). Assert that `next_rank_text` is `"MAX"` when rank equals `max_rank`.
- Demo: the tooltip scene exists, GUT tests pass. Tooltip is not yet wired to the screen (it can be added as a hidden child of `abilities_window.tscn` and left invisible).

Task 4: Wire rich tooltips and colored connector lines on the talent tree
- Objective: hovering a tree node shows the rich floating tooltip; connector lines turn gold when the prerequisite node is learned.
- In `abilities_window.tscn`: add `ability_tooltip.tscn` as an instanced child (hidden, drawn last so it appears on top). In `abilities_window.gd`:
  - Add `@onready var _tooltip: AbilityTooltip = $AbilityTooltip`.
  - In `_build_tree_panel`, connect `mouse_entered` / `mouse_exited` on each `TalentNode` button (instead of assigning `tooltip_text`). On enter: resolve the `Ability` and call `_tooltip.populate(node, save, move)`, position the tooltip 36px to the right of the node's global rect, show it. On exit: hide it.
  - Remove the `tooltip_text =` assignment from `_refresh_tree`.
  - In `_draw_tree_lines`: per edge, check `TalentTree.get_rank(save, prereq_index) >= 1`. If true, draw with gold `Color(0.85, 0.72, 0.2)`; if false, keep dim gray `Color(0.16, 0.16, 0.17)`. Thickness stays 4.0.
- Update `talent_node.tscn`: add an `IconRect` (`TextureRect`, 28×28, centered within the 32×32 button, `STRETCH_KEEP_ASPECT_CENTERED`, `mouse_filter = IGNORE`) as a sibling of `RankLabel`. In `_refresh_tree`, set `IconRect.texture` from `assets/ui/abilities/<label>.png`; for passive nodes (no icon), leave texture null and rely on the colored `StyleBoxFlat` background circle.
- Add a `static func is_prerequisite_learned(save: PlayerSave, node_index: int, prereq_index: int) -> bool` to `talent_tree.gd` (one-liner: `return get_rank(save, prereq_index) >= 1`). Add a GUT test asserting this returns true after `learn()` and false before.
- Demo: open the abilities screen with a save that has a few nodes learned. Gold connector lines run to learned prerequisites, gray to unlearned. Hovering a node shows the floating tooltip with icon, title, description, cost, and next-rank text.

Task 5: Icon thumbnails on pool rows and wheel sockets
- Objective: the ability pool list and the 8-socket wheel show the ability's icon thumbnail instead of text initials/abbreviations.
- **Pool rows**: in `_build_pool_panel` (or wherever pool rows are constructed in `abilities_window.gd`), add a `TextureRect` (`IconRect`, 20×20, `STRETCH_KEEP_ASPECT_CENTERED`, `SHRINK_BEGIN` h-flag, `mouse_filter = IGNORE`) as the first child of each pool row `Button`. In `_refresh_pool`, set `IconRect.texture` from `assets/ui/abilities/<label>.png`. Wire `mouse_entered`/`mouse_exited` on each pool row to call `_tooltip.populate(null, save, move)` (null node dict → `NextRankLabel` hidden) and position/show/hide the tooltip.
- **Wheel sockets**: in `_refresh_wheel`, replace `socket.text = _move_initials(move)` with `socket.icon = load("res://assets/ui/abilities/<label>.png")` (graceful null on missing). Set `socket.expand_icon = true` and `socket.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER`. Keep `socket.text = ""`. Wire `mouse_entered`/`mouse_exited` on each socket to show the tooltip for the equipped move.
- No new scene files in this task.
- Demo: pool rows show the icon to the left of the move name. Wheel sockets show icons. Hovering any pool row or socket pops the rich tooltip.

Task 6: Pool row as reusable `ability_pool_row.tscn`
- Objective: migrate the 5 hardcoded `PoolRowN` buttons in `abilities_window.tscn` to a reusable instanced scene, following the `item_slot.tscn` pattern.
- Create `scenes/ui/menu/ability_pool_row.tscn`: a `Button` (`custom_minimum_size = Vector2(186, 22)`) containing an `HBoxContainer` with an `IconRect` (`TextureRect`, 20×20, `SIZE_SHRINK_BEGIN`) and a `NameLabel` (`Label`, `SIZE_EXPAND_FILL`, left-aligned, font size 11). The button's own `text` stays empty.
- Create `scripts/ui/menu/ability_pool_row.gd`: `@onready` refs to `IconRect` and `NameLabel`; `func populate(move: Ability)` sets icon texture and name label text; `func clear()` hides the row and clears both.
- In `abilities_window.tscn`: remove the 5 `PoolRowN` static nodes and their `StyleBoxFlat` sub-resources. In `abilities_window.gd`: replace `const ... PoolRowN` `@onready` array with `const AbilityPoolRowScene: PackedScene = preload("res://scenes/ui/menu/ability_pool_row.tscn")`. In `_ready`, instantiate 5 rows into the `PoolRows` VBoxContainer, wire `pressed` and `mouse_entered`/`mouse_exited` signals on each instance.
- GUT test: instantiate `ability_pool_row.tscn`, call `populate(move)`, assert `NameLabel.text == move.display_name`.
- Demo: the abilities screen looks and behaves identically to after Task 5. Pool rows are now proper reusable components — adding a 6th visible row is a one-line change. GUT suite still passes.