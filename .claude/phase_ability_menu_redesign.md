# Ability Menu Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the abilities screen (`scripts/ui/menu/abilities_window.gd` + `scenes/ui/menu/abilities_window.tscn`) in line with the original `DefineSprite 3142` frame 25: real icon art on every
talent-tree node, pool row, and wheel socket; SWF-faithful connector lines colored by prerequisite state; and a rich floating tooltip (icon + title + description + cost/cooldown + next-rank
preview) replacing Godot's built-in string-only tooltip. The screen's logic and three-region layout are already correct and already migrated to native Containers (this session's earlier UI
architecture phase) - this plan is purely about the missing art and richer tooltip content.

**Revision note:** this plan started from a draft at this same path written by an earlier pass. Every factual claim in that draft was independently re-verified against the live SWF (via `ffdec
-swf2xml`), the converted JSON data, and the current codebase before this rewrite - see the Global Constraints section for the two corrections that came out of that verification (rank-aware
tooltip resolution, and the true state of passive-node tooltip descriptions). Everything else in the draft checked out exactly as written and is carried forward here with exact code filled in.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`), Python 3 (`uv run python3`) for the one-off asset extraction script.

## Global Constraints

- **Icon sheet coverage is complete - independently re-verified, not assumed.** `DefineSprite 2427` (web-build id) has `frameCount="986"` and exactly 104 `FrameLabelTag`s (confirmed via
  `ffdec -swf2xml sonny-2-2900.swf` against the already-generated `source_files/swf_xml/sonny-2-2900.xml` - no need to regenerate that dump, it's 137MB and already on disk). Cross-checked
  programmatically against every move id and every buff family actually referenced in `TalentTree.TREES` (all 3 classes): **all 69 distinct active-node move ids** have a label matching their
  `display_name` exactly, and **all 14 distinct passive-node buff families** (`ACIDIC`, `CHARGEDBLOOD`, `COLDNEU`, `CRYSTALICE`, `EVOLUTION`, `HOTBLOOD`, `INTEGRITY`, `LASTINGPAIN`, `MARATHON`,
  `OVERDRIVE`, `SAVAGERY`, `STIFFUPPER`, `TENACITY`, `WARMNEU`) ALSO have a matching label. Zero missing in either category - this corrects the original draft, which treated passive nodes as
  icon-less by design and left "does the sheet cover every move" as an open question. Passive nodes get real icons too (Task 4), looked up by buff family name instead of move display name.
- **Rank-aware tooltip resolution is required, not optional.** Verified against the actual data: moves in the same family (e.g. ids 100-103, all "Vicious Strike") share `display_name` but have
  MEANINGFULLY DIFFERENT `17_tooltip_description` text per rank (100: "110%... 13% chance", 101: "120%... 25%", 102: "130%... 50%", 103: "140%... 100%" - the percentages scale with rank).
  `damage_element_type`/`cooldown_turns`/`focus_cost` are identical across a family (existing `_node_color()` logic is unaffected), but the tooltip's description/cost text is NOT - whichever
  specific move id is currently granted must be looked up, not always the tree node's base `move_id`. Concretely: for an active node at `rank > 0`, resolve
  `TalentTree.granted_move_id(node, rank)`; at `rank == 0` (not yet learned), resolve `TalentTree.granted_move_id(node, 1)` to preview what learning rank 1 would grant. Getting this wrong means
  a fully-upgraded ability shows its RANK 1 tooltip text forever, which is a real, visible bug, not a cosmetic nit.
- **Passive-node tooltip descriptions render blank today - this is a verified data fact, not a bug to fix here.** Checked every rank of every one of the 14 buff families actually used in
  `TalentTree.TREES` against `python_conversion_scripts/converted_json/buffs.json`'s `25_tooltip_description` field: **all 53 entries are empty** (AS3's `undefined` coerced to `0`/`""` by
  `Buff._text()`, per that file's own header comment - "55 buffs have 0 for display_name/tooltip"). Wire `Buff.tooltip_description` into the passive-node tooltip path anyway (Task 3) for
  architectural consistency and in case the source data is ever corrected upstream, but do NOT write a GUT test asserting non-empty description text for a passive node - assert it resolves to
  `""` cleanly instead, matching the real data. The tooltip still shows a real icon, title (buff family name, capitalized), cost ("Passive"), and next-rank preview for passives even with a blank
  description line.
- `test/integration/test_ui_scenes.gd`'s `test_abilities_window_edits_action_bar` must keep passing unchanged - it reads `window._pool_move_ids`, calls `window._on_socket_pressed(0)` and
  `window._on_pool_row_pressed(0)`, none of which this plan changes the signature or behavior of (Task 6 changes pool ROW CONSTRUCTION, not `_on_pool_row_pressed`'s logic).
  `test/integration/test_ui_scenes.gd`'s `test_hotbar_menu_toggle_is_exclusive_and_glows` only checks `game.get_node("AbilitiesWindow").visible` - unaffected. No test file needs modification
  except the new GUT tests this plan adds.
- This is additive work (new art, new tooltip, richer visuals) layered onto already-correct logic - existing behavior (learn validation, socket/pool click handling, attribute point spending)
  must not change. Every task ends with the full suite green at the same count it started.
- Godot enum literals used below (confirmed against this project's actual Godot 4.7.1 binary): `TextureRect.STRETCH_KEEP_ASPECT_CENTERED = 5`, `Control.MOUSE_FILTER_IGNORE = 2`,
  `Control.MOUSE_FILTER_STOP = 0`, `HORIZONTAL_ALIGNMENT_LEFT = 0`, `HORIZONTAL_ALIGNMENT_CENTER = 1`. `Button.icon`/`Button.expand_icon`/`Button.icon_alignment` are real Button properties
  (confirmed via a headless property-existence check against this Godot build) - Task 5 relies on them.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error). Any task that adds a new `class_name` needs a global-class-cache reimport first:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .` - this is per-checkout (worktree AND main both need it separately after a merge).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document.
- `--headless` cannot produce a real rendered image on this machine (verified this session - zero Vulkan/Metal/OpenGL initialization in the verbose log under `--headless`, vs. a real
  `Metal 4.0 - Apple M4 Pro` device without it). For any manual visual check in this plan, drop `--headless` from the command (compile-checks and GUT itself stay `--headless`, they don't render
  anything).

---

### Task 1: Extract ability icon assets

**Files:**
- Create: `python_conversion_scripts/swf_extraction/extract_ability_icons.py`
- Create: `assets/ui/abilities/*.png` (~104 files, generated by the script)

**Interfaces:**
- Consumes: nothing external.
- Produces: `assets/ui/abilities/<sanitized_label>.png` for every labeled frame of sprite 2427. Tasks 3/4/5 all load these paths at runtime via a shared sanitize function that must exactly mirror
  this script's `sanitize()` (see Task 3's `AbilityTooltipBuilder` note).

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS. Note the exact count - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Write `extract_ability_icons.py`**

Copy `python_conversion_scripts/swf_extraction/extract_item_icons.py` to `python_conversion_scripts/swf_extraction/extract_ability_icons.py` and make exactly these changes:

1. Update the header comment to describe the ability icon sheet instead of the item sheet:

```python
# extract_ability_icons.py
# The original ability/move icon sheet: DefineSprite 2427, one labeled frame
# per move (equipped bar, unequipped pool, AND skill-tree nodes all draw
# from this one clip) PLUS one labeled frame per passive-node buff family
# (e.g. "SAVAGERY", "INTEGRITY") - the talent tree's passive nodes use the
# same sheet, keyed by buff family name instead of move display name.
# Composites every labeled frame at 2x into assets/ui/abilities/<label>.png.
# Confirmed 2026-07-23: all 69 active move ids and all 14 passive buff
# families actually used in TalentTree.TREES have a matching label - no
# fallback-art path is needed for anything currently in the trees.
#
# Requires ffdec for the shape exports.
# Run: uv run python3 python_conversion_scripts/swf_extraction/extract_ability_icons.py
```

2. Change these three constants:

```python
OUT_DIR = REPO / "assets" / "ui" / "abilities"
ICON_SPRITE = 2427
```

(Leave `ZOOM = 2.0`, `ICON_HALF = 15.5`, `FFDEC`, `SKIP_CIDS = {1913}` unchanged - same slot geometry and editor-backing shape as the item sheet.)

3. Change the frame-range scan from `set(range(1, 900))` to `set(range(1, 990))` - sprite 2427's `frameCount` is 986, so the item-sheet script's `900` upper bound would silently truncate the last
   ~86 frames (and therefore any labels only reachable near the end of the timeline). Verify after running that `labels: 104` is printed - if it's ever less than 104 after this change, the range
   still isn't wide enough and needs to go higher, not lower.

4. Delete `ICON_OVERRIDES` entirely (there are no known bad-frame overrides for the ability sheet - this dict existed only for one item's frame mismatch).

5. Delete the ENTIRE `.tres`-repointing section (everything from the `# --- repoint the item .tres slot_image ...` comment through the end of `main()`) - ability icons are looked up by
   sanitized display name / buff family name at runtime (Tasks 3/4/5), never baked into a `.tres` resource file. `main()` should end right after the `print("icons written:", ...)` line.

The final `main()` body should read:

```python
def main():
    xml = WEB_SWF_XML.read_text()
    shapes, sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    char_bounds = make_char_bounds(shapes, sprites)

    snaps, labels = snapshot_timeline(xml, ICON_SPRITE, set(range(1, 990)))
    print("icon frames:", len(snaps), "labels:", len(labels), file=sys.stderr)

    needed = set()

    def collect(cid):
        if cid in shapes:
            needed.add(cid)
        elif cid in sprites:
            for child, _mat in sprites[cid]:
                collect(child)

    label_frames = {}
    for label, frame in labels.items():
        snap = snaps.get(frame)
        if not snap:
            continue
        label_frames[label] = snap
        for entry in snap.values():
            collect(entry["cid"])
    print("shapes needed:", len(needed), file=sys.stderr)

    shape_dir = Path(tempfile.mkdtemp(prefix="ability_icon_shapes_"))
    ids = sorted(needed)
    for i in range(0, len(ids), 400):  # keep the CLI arg length sane
        subprocess.run(
            [str(FFDEC), "-zoom", str(ZOOM), "-format", "shape:png", "-selectid",
             ",".join(str(c) for c in ids[i:i + 400]), "-export", "shape",
             str(shape_dir), str(REPO / "sonny-2-2900.swf")],
            check=True, capture_output=True,
        )

    def paste_char(canvas, cid, mat, origin):
        if cid in SKIP_CIDS:
            return
        sx, r0, r1, sy, tx, ty = mat
        if cid in sprites:
            for child, child_mat in sprites[cid]:
                csx, _cr0, _cr1, csy, ctx, cty = child_mat
                combined = (sx * csx, 0.0, 0.0, sy * csy, tx + ctx * sx, ty + cty * sy)
                paste_char(canvas, child, combined, origin)
            return
        b = char_bounds(cid)
        path = shape_dir / ("%d.png" % cid)
        if b is None or not path.exists():
            return
        img = Image.open(path).convert("RGBA")
        if abs(sx) != 1.0 or abs(sy) != 1.0:
            img = img.resize((max(1, int(img.width * abs(sx))), max(1, int(img.height * abs(sy)))))
        px = (b[0] / 20.0 * sx + tx / 20.0 - origin[0]) * ZOOM
        py = (b[1] / 20.0 * sy + ty / 20.0 - origin[1]) * ZOOM
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    size = (int(ICON_HALF * 2 * ZOOM), int(ICON_HALF * 2 * ZOOM))
    written = {}
    for label, snap in label_frames.items():
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        for depth in sorted(snap):
            entry = snap[depth]
            paste_char(canvas, entry["cid"], entry.get("mat", (1, 0, 0, 1, 0, 0)), (-ICON_HALF, -ICON_HALF))
        file_name = sanitize(label) + ".png"
        canvas.save(OUT_DIR / file_name)
        written[label] = file_name
    print("icons written:", len(written), file=sys.stderr)


if __name__ == "__main__":
    main()
```

Keep `sanitize()` (the `re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")` function) exactly as-is - Task 3's GDScript-side lookup must reproduce this exact transformation on move display names /
buff family names.

- [ ] **Step 3: Run the extraction script and verify output**

Run: `uv run python3 python_conversion_scripts/swf_extraction/extract_ability_icons.py`
Expected stderr: `icon frames: 104 labels: 104`, `shapes needed: <some count>`, `icons written: 104`.
Then: `ls assets/ui/abilities/ | wc -l` - expect `104`. Spot-check a few filenames exist: `ls assets/ui/abilities/Vicious_Strike.png assets/ui/abilities/SAVAGERY.png` (sanitized from labels
"Vicious Strike" and "SAVAGERY" - note the buff-family labels have NO rank suffix, e.g. the label is just `"SAVAGERY"`, not `"SAVAGERY1"` - one icon per family covers all ranks of that passive).

- [ ] **Step 4: Confirm idempotency**

Run the script a second time: `uv run python3 python_conversion_scripts/swf_extraction/extract_ability_icons.py`. Confirm it exits 0 with the same `icons written: 104` count and no errors -
re-running must not depend on state left over from the first run (temp shape dirs are freshly created each time via `tempfile.mkdtemp`, so this should already hold).

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no GDScript changes and no new tests - pure asset extraction).

- [ ] **Step 6: Commit**

```bash
git add python_conversion_scripts/swf_extraction/extract_ability_icons.py assets/ui/abilities/
git commit -m "feat: extract ability icon art from DefineSprite 2427"
```

---

### Task 2: Add `tooltip_description` and `tooltip_cost` to `Ability`

**Files:**
- Modify: `scripts/battle/ability.gd`
- Create: `test/unit/test_ability_tooltip_fields.gd`

**Interfaces:**
- Consumes: nothing from Task 1 (disjoint files).
- Produces: `Ability.tooltip_description: String` and `Ability.tooltip_cost: String`, both read by Task 3's `AbilityTooltipBuilder`.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Add the two fields to `scripts/battle/ability.gd`**

Add two `@export` fields, placed with the other `ability_two`-sourced fields (right after `@export var heal_percent_max_health: float`):

```gdscript
@export var heal_percent_max_health: float
# Pre-formatted tooltip strings from the original game (ability_two[17]/[18]).
# Read verbatim, no re-derivation - the source already bakes rank-specific
# percentages/chances into tooltip_description (verified: moves 100-103, all
# "Vicious Strike", have different tooltip_description text per rank even
# though damage_element_type/cooldown/focus_cost are identical across the
# family) - callers must resolve the SPECIFIC move id for the currently
# granted rank, not just the tree node's base move_id, or the tooltip will
# show stale rank-1 text forever. See TalentTree.granted_move_id().
@export var tooltip_description: String
@export var tooltip_cost: String
```

In `from_json()`, add these two lines right after the existing `ability.heal_percent_max_health = ...` line (both fields live in the `ability_two` sub-dict, confirmed against the actual JSON -
NOT top-level `data`, unlike most of `from_json`'s other `ability_two.get(...)` calls which is where they already are, just confirming placement):

```gdscript
	ability.tooltip_description = _text(ability_two.get("17_tooltip_description"))
	ability.tooltip_cost = _text(ability_two.get("18_tooltip_cost"))
```

- [ ] **Step 3: Write `test/unit/test_ability_tooltip_fields.gd`**

```gdscript
# test_ability_tooltip_fields.gd
# Ability.tooltip_description/tooltip_cost load the original game's
# pre-formatted tooltip strings from ability_two[17]/[18].
extends GutTest


func test_leading_strike_has_real_tooltip_text():
	var move: Ability = MoveManagerAuto.get_move(1)
	assert_not_null(move, "move id 1 (Leading Strike) exists")
	assert_eq(move.tooltip_description, "Attack the enemy for 170% of your Strength, and restores 50 Focus to you. ")
	assert_eq(move.tooltip_cost, "This move costs nothing")


func test_same_family_different_ranks_have_different_descriptions():
	# Vicious Strike (100-103): shared display_name, rank-scaled tooltip text.
	var rank1: Ability = MoveManagerAuto.get_move(100)
	var rank4: Ability = MoveManagerAuto.get_move(103)
	assert_eq(rank1.display_name, rank4.display_name, "same family shares a display name")
	assert_ne(rank1.tooltip_description, rank4.tooltip_description, "rank-scaled tooltip text differs")
```

(Exact expected strings above are copied verbatim from `python_conversion_scripts/converted_json/moves_abilities.json`, confirmed via direct inspection before writing this plan - do not
re-derive or paraphrase them if the assertion fails, re-check the JSON directly.)

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/ability.gd --path .`
Expected: clean compile, no output at all (this script doesn't reference any autoload).

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, Task 1's ending count + 2 new tests, both passing.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/ability.gd test/unit/test_ability_tooltip_fields.gd
git commit -m "feat: surface the original tooltip_description/tooltip_cost strings on Ability"
```

---

### Task 3: Build `ability_tooltip.tscn` and `AbilityTooltipBuilder`

**Files:**
- Create: `scripts/ui/menu/ability_tooltip_builder.gd`
- Create: `scripts/ui/menu/ability_tooltip.gd`
- Create: `scenes/ui/menu/ability_tooltip.tscn`
- Create: `test/unit/test_ability_tooltip_builder.gd`

**Interfaces:**
- Consumes: `Ability.tooltip_description`/`tooltip_cost` (Task 2), `Buff.tooltip_description` (already exists), icon files from Task 1 (consumed only by `ability_tooltip.gd`'s icon-loading path,
  not by the pure builder).
- Produces: `class_name AbilityTooltipBuilder` with `static func build_fields(...)`, and `class_name AbilityTooltip` (the scene's attached script) with `func populate(...)`. Task 4 instances
  `ability_tooltip.tscn` into `abilities_window.tscn` and calls `populate()` on hover.
- **New `class_name`s** (`AbilityTooltipBuilder`, `AbilityTooltip`) - force a global-class-cache reimport (`--headless --editor --quit --path .`) before compile-checking or running tests.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Write `scripts/ui/menu/ability_tooltip_builder.gd`**

A pure static helper with no Node/scene dependency - this is what the GUT tests target directly, no scene instantiation needed.

```gdscript
# ability_tooltip_builder.gd
# Pure data builder for the rich ability tooltip (KRINTOOLTIPPER-style: icon,
# title, description, cost/cooldown, next-rank preview). No Node/scene
# dependency on purpose - abilities_window.gd and ability_tooltip.gd both
# consume build_fields()'s output; GUT tests target this directly.
class_name AbilityTooltipBuilder
extends RefCounted


# node: a TalentTree node dict, or {} for a pool-row/wheel-socket hover
#   (no rank progress to show - NextRankLabel hidden in that case).
# save: used to read the node's current rank (ignored when node is {}).
# move: the resolved Ability for this hover - for a TREE node hover, the
#   CALLER must resolve the rank-specific move id first (see the
#   Global Constraints note on rank-aware resolution) - this builder does
#   not do that resolution itself, it only formats whatever move it's given.
# buff: the resolved Buff for a passive node hover, or null for an active
#   node / pool row / wheel socket hover.
static func build_fields(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff) -> Dictionary:
	var is_passive: bool = not node.is_empty() and TalentTree.is_passive(node)
	var title: String
	var description: String
	var cost: String
	if is_passive:
		title = str(node["buff_family"]).capitalize()
		description = buff.tooltip_description if buff != null else ""
		cost = "Passive"
	else:
		title = move.display_name if move != null else "?"
		description = move.tooltip_description if move != null else ""
		cost = move.tooltip_cost if move != null else ""
	var next_rank_text: String = ""
	if not node.is_empty():
		var rank: int = TalentTree.get_rank(save, node.get("_node_index", -1)) if save != null else 0
		var max_rank: int = int(node.get("max_rank", 0))
		if rank >= max_rank:
			next_rank_text = "MAX"
		else:
			next_rank_text = "Next Tier (Lvl. %d)" % TalentTree.required_level(node, rank)
	var element_index: int = -1
	if not is_passive and move != null:
		element_index = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
	var element_color: Color = MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.6, 0.6, 0.4)
	return {
		"title": title,
		"description": description,
		"cost": cost,
		"next_rank_text": next_rank_text,
		"element_color": element_color,
	}
```

Note on `node.get("_node_index", -1)`: `TalentTree`'s node dicts (from `TREES`) don't carry their own index - callers already track `node_index` separately (`abilities_window.gd`'s
`_refresh_tree`/`_build_tree_panel` loops both iterate `for node_index in ...`). Task 4's wiring passes the node dict WITH a synthetic `"_node_index"` key merged in right before calling this
builder (`node.duplicate()` + `node["_node_index"] = node_index`) - simpler than changing this function's signature to take an extra int parameter that's only needed for one lookup, and keeps
`build_fields`'s signature stable for the pool-row/wheel-socket callers (which pass `{}` and never need an index).

- [ ] **Step 3: Write `test/unit/test_ability_tooltip_builder.gd`**

```gdscript
# test_ability_tooltip_builder.gd
extends GutTest


func test_active_node_fields_at_rank_zero():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, 0).duplicate()
	node["_node_index"] = 0
	var move: Ability = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, 1))
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, move, null)
	assert_eq(fields["title"], move.display_name)
	assert_eq(fields["description"], move.tooltip_description)
	assert_eq(fields["cost"], move.tooltip_cost)
	assert_eq(fields["next_rank_text"], "Next Tier (Lvl. 1)")


func test_passive_node_at_max_rank_shows_max():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	# Node 1 in class 0's tree is the INTEGRITY passive, max_rank 4.
	var node: Dictionary = TalentTree.get_talent_node(0, 1).duplicate()
	node["_node_index"] = 1
	save.talent_main_array[1] = 4
	var buff: Buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, 4))
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, null, buff)
	assert_eq(fields["title"], "Integrity")
	assert_eq(fields["cost"], "Passive")
	assert_eq(fields["next_rank_text"], "MAX")
	# Verified fact, not a bug: every tree-passive buff's tooltip_description
	# is empty in the source data (AS3 undefined -> "" via Buff._text()).
	assert_eq(fields["description"], "", "source data has no tooltip text for tree-passive buffs")


func test_pool_row_hover_has_no_next_rank_text():
	var move: Ability = MoveManagerAuto.get_move(1)
	var fields: Dictionary = AbilityTooltipBuilder.build_fields({}, null, move, null)
	assert_eq(fields["next_rank_text"], "", "no rank progress to show outside a tree-node hover")
```

- [ ] **Step 4: Force a global class cache reimport, then compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .`
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/ability_tooltip_builder.gd --path .`
Expected: clean compile, no output at all.

- [ ] **Step 5: Write `scripts/ui/menu/ability_tooltip.gd`**

```gdscript
# ability_tooltip.gd
# The rich floating ability tooltip (KRINTOOLTIPPER-style), shown by
# abilities_window.gd on hover over a talent-tree node, pool row, or wheel
# socket. Hidden by default; the caller shows/hides and positions it.
extends PanelContainer
class_name AbilityTooltip

const ICON_DIR: String = "res://assets/ui/abilities/"

@onready var _icon_backing: ColorRect = $Margin/HBox/IconBacking
@onready var _icon: TextureRect = $Margin/HBox/IconBacking/Icon
@onready var _title_label: Label = $Margin/HBox/VBox/TitleLabel
@onready var _desc_label: Label = $Margin/HBox/VBox/DescLabel
@onready var _cost_label: Label = $Margin/HBox/VBox/CostLabel
@onready var _next_rank_label: Label = $Margin/HBox/VBox/NextRankLabel


# icon_key: the sanitized label to load from assets/ui/abilities/ (move
# display_name for actives, buff family name for passives) - callers build
# this with the same sanitize() transform the extraction script used.
func populate(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff, icon_key: String) -> void:
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, move, buff)
	_title_label.text = fields["title"]
	_desc_label.text = fields["description"]
	_desc_label.visible = not fields["description"].is_empty()
	_cost_label.text = fields["cost"]
	_next_rank_label.text = fields["next_rank_text"]
	_next_rank_label.visible = not fields["next_rank_text"].is_empty()
	_icon_backing.color = fields["element_color"]
	var icon_path: String = "%s%s.png" % [ICON_DIR, icon_key]
	_icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
```

- [ ] **Step 6: Write `scenes/ui/menu/ability_tooltip.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/menu/ability_tooltip.gd" id="1_tooltip"]

[node name="AbilityTooltip" type="PanelContainer"]
visible = false
custom_minimum_size = Vector2(220, 0)
mouse_filter = 2
script = ExtResource("1_tooltip")

[node name="Margin" type="MarginContainer" parent="."]
layout_mode = 2
mouse_filter = 2
theme_override_constants/margin_left = 8
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 8
theme_override_constants/margin_bottom = 8

[node name="HBox" type="HBoxContainer" parent="Margin"]
layout_mode = 2
mouse_filter = 2
theme_override_constants/separation = 8

[node name="IconBacking" type="ColorRect" parent="Margin/HBox"]
custom_minimum_size = Vector2(32, 32)
layout_mode = 2
mouse_filter = 2
color = Color(0.6, 0.6, 0.4, 1)

[node name="Icon" type="TextureRect" parent="Margin/HBox/IconBacking"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="VBox" type="VBoxContainer" parent="Margin/HBox"]
layout_mode = 2
size_flags_horizontal = 3
mouse_filter = 2
theme_override_constants/separation = 2

[node name="TitleLabel" type="Label" parent="Margin/HBox/VBox"]
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 13
autowrap_mode = 3

[node name="DescLabel" type="Label" parent="Margin/HBox/VBox"]
layout_mode = 2
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 11
autowrap_mode = 3

[node name="CostLabel" type="Label" parent="Margin/HBox/VBox"]
layout_mode = 2
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.75, 0.2, 1)
theme_override_font_sizes/font_size = 10
autowrap_mode = 3

[node name="NextRankLabel" type="Label" parent="Margin/HBox/VBox"]
layout_mode = 2
mouse_filter = 2
theme_override_colors/font_color = Color(0.6, 0.85, 0.95, 1)
theme_override_font_sizes/font_size = 10
autowrap_mode = 3
```

Notes: `stretch_mode = 5` on `Icon` is `TextureRect.STRETCH_KEEP_ASPECT_CENTERED`. `custom_minimum_size = Vector2(220, 0)` on the root gives the tooltip a stable width while letting height grow
with content (description/next-rank text can wrap). Every node gets `mouse_filter = 2` (`MOUSE_FILTER_IGNORE`) so the tooltip never itself intercepts hover/click - the node/row/socket underneath
keeps driving show/hide.

- [ ] **Step 7: Compile-check `ability_tooltip.gd`**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/ability_tooltip.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 8: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, Task 2's ending count + 4 new tests (3 from Step 3, run them explicitly first to confirm: `-gtest=test/unit/test_ability_tooltip_builder.gd`), all passing. The tooltip scene
exists but is not yet wired into `abilities_window.tscn` - that's Task 4.

- [ ] **Step 9: Commit**

```bash
git add scripts/ui/menu/ability_tooltip_builder.gd scripts/ui/menu/ability_tooltip.gd scenes/ui/menu/ability_tooltip.tscn test/unit/test_ability_tooltip_builder.gd
git commit -m "feat: add the reusable AbilityTooltip scene and its pure data builder"
```

---

### Task 4: Wire rich tooltips and colored connector lines on the talent tree

**Files:**
- Modify: `scenes/ui/menu/abilities_window.tscn`
- Modify: `scenes/ui/menu/talent_node.tscn`
- Modify: `scripts/ui/menu/abilities_window.gd`
- Modify: `scripts/entities/talent_tree.gd`
- Modify: `test/unit/test_talent_tree.gd`

**Interfaces:**
- Consumes: `AbilityTooltip`/`ability_tooltip.tscn` (Task 3), the icon assets (Task 1).
- Produces: `TalentTree.is_prerequisite_learned()`, consumed only within this task's own wiring - no later task depends on it.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 3's ending count exactly.

- [ ] **Step 2: Add `TalentTree.is_prerequisite_learned()` and its test**

In `scripts/entities/talent_tree.gd`, add this function right after `get_rank()`:

```gdscript
# Whether a specific prerequisite node has been learned at all (rank >= 1) -
# used to color the tree's connector lines (gold = learned, gray = not).
static func is_prerequisite_learned(save: PlayerSave, prereq_index: int) -> bool:
	return get_rank(save, prereq_index) >= 1
```

In `test/unit/test_talent_tree.gd`, add this test (near `test_prerequisite_gate`, matching that test's style):

```gdscript
func test_is_prerequisite_learned():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	assert_false(TalentTree.is_prerequisite_learned(save, 0), "not learned yet")
	TalentTree.learn(save, 0)
	assert_true(TalentTree.is_prerequisite_learned(save, 0), "learned after spending a point")
```

- [ ] **Step 3: Add `IconRect` to `scenes/ui/menu/talent_node.tscn`**

Add a `TextureRect` as a sibling of `RankLabel`, sized to sit centered within the 32x32 button with a 2px margin all around (28x28 visible icon area):

```
[node name="IconRect" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 2.0
offset_top = 2.0
offset_right = 30.0
offset_bottom = 30.0
mouse_filter = 2
expand_mode = 1
stretch_mode = 5
```

(`stretch_mode = 5` is `STRETCH_KEEP_ASPECT_CENTERED`, `mouse_filter = 2` is `MOUSE_FILTER_IGNORE` so hover/click still land on the parent `TalentNode` button underneath. No `texture` set here -
`_refresh_tree()` assigns it per-node, since which icon (or none) shows depends on the node's move/buff family, which the reusable scene has no way to know ahead of time.)

- [ ] **Step 4: Add `AbilityTooltip` to `scenes/ui/menu/abilities_window.tscn`**

Add an `ext_resource` for the tooltip scene and instance it as the LAST child of the root (so it draws on top of everything else, including the tree/pool/wheel):

```
[ext_resource type="PackedScene" path="res://scenes/ui/menu/ability_tooltip.tscn" id="6_tooltip"]

[node name="AbilityTooltip" parent="." instance=ExtResource("6_tooltip")]
layout_mode = 0
```

Add this as the LAST node in the file, after `TreeLines` and before the `[connection ...]` block (node order in a `.tscn` determines child/draw order - instancing it last means it's the
topmost sibling).

- [ ] **Step 5: Rewrite `_build_tree_panel()`, `_refresh_tree()`, `_node_tooltip()`, and `_draw_tree_lines()` in `scripts/ui/menu/abilities_window.gd`**

Add near the top of the file, alongside `TalentNodeScene`:

```gdscript
const ICON_DIR: String = "res://assets/ui/abilities/"
```

Add a shared sanitize helper (mirrors the Python extraction script's `sanitize()` exactly - same regex, same strip):

```gdscript
static func _sanitize_icon_key(label: String) -> String:
	var result: String = ""
	var last_was_sep: bool = false
	for c in label:
		if (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
			last_was_sep = false
		elif not last_was_sep:
			result += "_"
			last_was_sep = true
	return result.strip_edges().lstrip("_").rstrip("_")
```

Add `@onready var _tooltip: AbilityTooltip = $AbilityTooltip` to the `@onready` block.

Replace `_build_tree_panel()`'s body to also wire hover signals (keep the existing `pressed` connection and styling call exactly as they are, just add the two new lines):

```gdscript
func _build_tree_panel() -> void:
	var tree: Array = TalentTree.TREES.get(_player_class(), TalentTree.TREES[0])
	for node_index in tree.size():
		var node_button: Button = TalentNodeScene.instantiate()
		node_button.position = _node_center(node_index) - NODE_SIZE / 2.0
		node_button.pressed.connect(_on_tree_node_pressed.bind(node_index))
		node_button.mouse_entered.connect(_on_tree_node_hovered.bind(node_index))
		node_button.mouse_exited.connect(_tooltip.hide)
		_style_circle_button(node_button, Color(0.1, 0.1, 0.11), Color(0.3, 0.3, 0.32))
		add_child(node_button)
		_tree_buttons.append(node_button)
		_tree_rank_labels.append(node_button.get_node("RankLabel"))
```

Replace `_refresh_tree()` - it no longer sets `tooltip_text` (the rich floating tooltip replaces Godot's built-in one), and now also sets each node's `IconRect` texture:

```gdscript
func _refresh_tree(save: PlayerSave) -> void:
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[0])
	for node_index in _tree_buttons.size():
		if node_index >= tree.size():
			break
		var node: Dictionary = tree[node_index]
		var button: Button = _tree_buttons[node_index]
		var rank: int = TalentTree.get_rank(save, node_index)
		var color: Color = _node_color(save, node_index, node)
		var learned: bool = rank > 0
		_style_circle_button(
			button,
			color.darkened(0.55) if learned else Color(0.1, 0.1, 0.11),
			color if learned else Color(0.3, 0.3, 0.32)
		)
		_tree_rank_labels[node_index].text = "%d/%d" % [rank, int(node["max_rank"])]
		var icon_rect: TextureRect = button.get_node("IconRect")
		var icon_path: String = "%s%s.png" % [ICON_DIR, _tree_node_icon_key(node)]
		icon_rect.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
```

Delete `_node_tooltip()` entirely (fully replaced by the floating tooltip - `_style_circle_button`'s and `_refresh_tree`'s callers no longer need a plain-string tooltip).

Add these two new helper functions (near `_node_color`):

```gdscript
# Icon lookup key for a tree node: buff family name for passives (one icon
# covers every rank of that family), the granted move's display name for
# actives (shared across a move family's ranks - only the tooltip TEXT
# differs by rank, not the icon or display name).
func _tree_node_icon_key(node: Dictionary) -> String:
	if TalentTree.is_passive(node):
		return _sanitize_icon_key(str(node["buff_family"]))
	var move: Ability = MoveManagerAuto.get_move(int(node["move_id"]))
	return _sanitize_icon_key(move.display_name) if move != null else ""


func _on_tree_node_hovered(node_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[0])
	if node_index >= tree.size():
		return
	var node: Dictionary = tree[node_index].duplicate()
	node["_node_index"] = node_index
	var rank: int = TalentTree.get_rank(save, node_index)
	var move: Ability = null
	var buff: Buff = null
	if TalentTree.is_passive(node):
		if rank > 0:
			buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, rank))
	else:
		# Rank-aware: show the CURRENTLY GRANTED move's text once learned,
		# otherwise preview what learning rank 1 would grant.
		move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, max(rank, 1)))
	var button: Button = _tree_buttons[node_index]
	_tooltip.populate(node, save, move, buff, _tree_node_icon_key(node))
	_tooltip.position = button.global_position + Vector2(NODE_SIZE.x + 8.0, 0.0)
	_tooltip.show()
```

Update `_draw_tree_lines()` to color edges gold when the prerequisite is learned:

```gdscript
func _draw_tree_lines() -> void:
	var save: PlayerSave = GameData.current_save
	var player_class: int = save.player_class if save != null else 0
	var tree: Array = TalentTree.TREES.get(player_class, TalentTree.TREES[0])
	for node_index in tree.size():
		for prerequisite in tree[node_index]["prerequisites"]:
			var learned: bool = save != null and TalentTree.is_prerequisite_learned(save, int(prerequisite))
			var color: Color = Color(0.85, 0.72, 0.2) if learned else Color(0.16, 0.16, 0.17)
			_tree_lines.draw_line(
				_node_center(node_index), _node_center(int(prerequisite)),
				color, 4.0
			)
```

- [ ] **Step 6: Force a global class cache reimport, then compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .`
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .` and
`/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/entities/talent_tree.gd --path .`
Expected: only the known autoload false positive, if anything, on the first; clean compile (no autoload references) on the second.

- [ ] **Step 7: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, Task 3's ending count + 1 new test (`test_is_prerequisite_learned`), all passing.

- [ ] **Step 8: Manual visual check**

Without `--headless` (per the Global Constraints note), render or launch `scenes/ui/menu/abilities_window.tscn` with a save that has a few nodes learned. Confirm: gold connector lines run to
learned prerequisites, gray to unlearned; hovering a tree node shows the floating tooltip with icon, title, description (blank for passives - expected, see Global Constraints), cost, and
next-rank text; talent node buttons show icon art (move icon for actives, buff-family icon for passives).

- [ ] **Step 9: Commit**

```bash
git add scenes/ui/menu/abilities_window.tscn scenes/ui/menu/talent_node.tscn scripts/ui/menu/abilities_window.gd scripts/entities/talent_tree.gd test/unit/test_talent_tree.gd
git commit -m "feat: rich floating tooltips and prerequisite-colored connector lines on the talent tree"
```

---

### Task 5: Icon thumbnails on pool rows and wheel sockets

**Files:**
- Modify: `scripts/ui/menu/abilities_window.gd`

**Interfaces:**
- Consumes: `AbilityTooltip` (Task 3), icon assets (Task 1).
- Produces: nothing new - Task 6 replaces the pool row NODES but keeps this task's `_refresh_pool()` icon-setting logic conceptually the same (adapted to the new reusable row's `populate()`
  method in Task 6, not duplicated).

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 4's ending count exactly.

- [ ] **Step 2: Wheel sockets show icons and hover tooltips**

Replace `_refresh_wheel()` in `scripts/ui/menu/abilities_window.gd`:

```gdscript
func _refresh_wheel(save: PlayerSave) -> void:
	for i in _socket_buttons.size():
		var socket: Button = _socket_buttons[i]
		var move_id: int = int(save.move_matrix[i]) if i < save.move_matrix.size() else 0
		if move_id == 0:
			socket.icon = null
			socket.tooltip_text = "Empty slot"
			_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
			continue
		var move: Ability = MoveManagerAuto.get_move(move_id)
		var color: Color = _move_color(move)
		var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name if move != null else "")]
		socket.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
		socket.expand_icon = true
		socket.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		socket.tooltip_text = ""
		_style_circle_button(socket, color.darkened(0.45), color)
```

(`socket.tooltip_text = ""` for a filled socket - Step 4 below adds the rich hover tooltip via signals instead; the "Empty slot" plain tooltip stays for empty sockets, which have nothing rich to
show. `_move_initials()` is no longer called here - check whether anything else in the file still calls it: `rg -n "_move_initials" scripts/ui/menu/abilities_window.gd` - if this refresh was its
only caller, delete `_move_initials()` entirely as dead code.)

- [ ] **Step 3: Wire wheel socket hover to the rich tooltip**

In `_build_wheel_panel()`, add hover wiring alongside the existing `pressed` connection:

```gdscript
func _build_wheel_panel() -> void:
	for i in WHEEL_OFFSETS.size():
		var socket: Button = Button.new()
		socket.custom_minimum_size = SOCKET_SIZE
		socket.size = SOCKET_SIZE
		socket.position = WHEEL_CENTER + WHEEL_OFFSETS[i] - SOCKET_SIZE / 2.0
		socket.pressed.connect(_on_socket_pressed.bind(i))
		socket.mouse_entered.connect(_on_socket_hovered.bind(i))
		socket.mouse_exited.connect(_tooltip.hide)
		_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
		add_child(socket)
		_socket_buttons.append(socket)
```

Add `_on_socket_hovered()` near `_on_socket_pressed`:

```gdscript
func _on_socket_hovered(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var move_id: int = int(save.move_matrix[socket_index]) if socket_index < save.move_matrix.size() else 0
	if move_id == 0:
		return
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return
	var button: Button = _socket_buttons[socket_index]
	_tooltip.populate({}, save, move, null, _sanitize_icon_key(move.display_name))
	_tooltip.position = button.global_position + Vector2(SOCKET_SIZE.x + 8.0, 0.0)
	_tooltip.show()
```

- [ ] **Step 4: Pool rows show icons and hover tooltips**

Replace `_refresh_pool()`:

```gdscript
func _refresh_pool(save: PlayerSave) -> void:
	_pool_move_ids = []
	# JSON-loaded saves hold floats - compare as ints.
	var bar_ids: Array[Variant] = []
	for bar_move in save.move_matrix:
		bar_ids.append(int(bar_move))
	for move_id in save.move_matrix2:
		if int(move_id) != 0 and not bar_ids.has(int(move_id)):
			_pool_move_ids.append(int(move_id))
	_pool_scroll = clamp(_pool_scroll, 0, max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS))
	for i in _pool_rows.size():
		var row: Button = _pool_rows[i]
		var pool_index: int = _pool_scroll + i
		if pool_index >= _pool_move_ids.size():
			row.visible = false
			continue
		row.visible = true
		var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
		row.text = move.display_name if move != null else str(_pool_move_ids[pool_index])
		row.tooltip_text = ""
		var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(row.text)]
		row.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
		row.expand_icon = false
		row.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
```

In `_ready()`, wire hover for each of the 5 static pool row buttons (they're indexed 0-4 in `_pool_rows`, matching `_on_pool_row_pressed`'s existing `row_index` convention):

```gdscript
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tree_panel()
	_build_wheel_panel()
	for i in _pool_rows.size():
		_pool_rows[i].mouse_entered.connect(_on_pool_row_hovered.bind(i))
		_pool_rows[i].mouse_exited.connect(_tooltip.hide)
	visibility_changed.connect(func():
		if visible:
			refresh())
```

Add `_on_pool_row_hovered()` near `_on_pool_row_pressed`:

```gdscript
func _on_pool_row_hovered(row_index: int) -> void:
	var pool_index: int = _pool_scroll + row_index
	if pool_index >= _pool_move_ids.size():
		return
	var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
	if move == null:
		return
	var save: PlayerSave = GameData.current_save
	var row: Button = _pool_rows[row_index]
	_tooltip.populate({}, save, move, null, _sanitize_icon_key(move.display_name))
	_tooltip.position = row.global_position + Vector2(row.size.x + 8.0, 0.0)
	_tooltip.show()
```

Note this task does NOT add an `IconRect` child node to the pool row buttons - `Button.icon` (a built-in property, same as the wheel sockets above) is used directly on the plain `Button`, no
child `TextureRect` needed. Task 6 restructures the row into a proper `HBoxContainer` layout with a dedicated `IconRect` child instead - until then, `Button.icon` alongside `Button.text` renders
both together (icon left of text) using Godot's own default Button layout, which is a perfectly reasonable intermediate state.

- [ ] **Step 5: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 6: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 4's ending count (no new tests - this task is UI wiring against already-tested helpers).

- [ ] **Step 7: Manual visual check**

Without `--headless`, confirm pool rows show the icon to the left of the move name, wheel sockets show icons, and hovering either pops the rich tooltip with correct content.

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/menu/abilities_window.gd
git commit -m "feat: icon thumbnails and rich tooltips on the ability pool and action-bar wheel"
```

---

### Task 6: Pool row as reusable `ability_pool_row.tscn`

**Files:**
- Create: `scripts/ui/menu/ability_pool_row.gd`
- Create: `scenes/ui/menu/ability_pool_row.tscn`
- Modify: `scenes/ui/menu/abilities_window.tscn`
- Modify: `scripts/ui/menu/abilities_window.gd`
- Create: `test/unit/test_ability_pool_row.gd`

**Interfaces:**
- Consumes: icon assets (Task 1), `AbilityTooltip` (Task 3, for the hover wiring carried over from Task 5).
- Produces: nothing new - this is the final task in the plan besides its own verification.
- **New `class_name`** (`AbilityPoolRow`) - force a global-class-cache reimport (`--headless --editor --quit --path .`) before compile-checking or running tests.

- [x] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 5's ending count exactly.

- [x] **Step 2: Write `scripts/ui/menu/ability_pool_row.gd`**

```gdscript
# ability_pool_row.gd
# One row of the ability pool list (icon + move name). abilities_window.gd
# instances 5 of these into the PoolRows VBoxContainer and calls populate()/
# clear() as the visible window scrolls - the row itself has no move_id
# state, the parent tracks that via its own _pool_move_ids/_pool_scroll.
extends Button
class_name AbilityPoolRow

@onready var icon_rect: TextureRect = $HBox/IconRect
@onready var name_label: Label = $HBox/NameLabel


func populate(move: Ability, icon_path: String) -> void:
	visible = true
	name_label.text = move.display_name if move != null else ""
	icon_rect.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null


func clear() -> void:
	visible = false
	name_label.text = ""
	icon_rect.texture = null
```

- [x] **Step 3: Write `scenes/ui/menu/ability_pool_row.tscn`**

Reproduce the current `PoolRowN` buttons' exact styling (confirmed from the live `abilities_window.tscn` before writing this plan: `custom_minimum_size = Vector2(186, 22)`, font size 11, font
color `(0.08, 0.08, 0.08)`, `StyleBoxFlat` normal `bg_color = (0.5, 0.5, 0.52)` / hover `bg_color = (0.65, 0.65, 0.67)`, both `corner_radius_all = 9`, `content_margin_left = 10`), now on the
reusable row's own root button plus a nested `HBoxContainer` for the icon+label:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/ui/menu/ability_pool_row.gd" id="1_row"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_poolrow"]
bg_color = Color(0.5, 0.5, 0.52, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9
content_margin_left = 10.0

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_poolrow_hover"]
bg_color = Color(0.65, 0.65, 0.67, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9
content_margin_left = 10.0

[node name="AbilityPoolRow" type="Button"]
custom_minimum_size = Vector2(186, 22)
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0
script = ExtResource("1_row")

[node name="HBox" type="HBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
offset_left = 10.0
offset_top = 2.0
offset_right = -4.0
offset_bottom = -2.0
mouse_filter = 2
theme_override_constants/separation = 6

[node name="IconRect" type="TextureRect" parent="HBox"]
custom_minimum_size = Vector2(18, 18)
layout_mode = 2
size_flags_vertical = 4
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="NameLabel" type="Label" parent="HBox"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
mouse_filter = 2
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_font_sizes/font_size = 11
```

(The root button keeps `alignment = 0` and its own `text` empty always - the visible label is `NameLabel` inside `HBox`, not the button's own `.text` property, which is why Step 2's `populate()`
never touches `self.text`. `size_flags_vertical = 4` is `SIZE_SHRINK_CENTER` - keeps the 18x18 icon and the label vertically centered within the 22px-tall row without stretching.)

- [x] **Step 4: Force a global class cache reimport, then compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .`
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/ability_pool_row.gd --path .`
Expected: clean compile, no output at all.

- [x] **Step 5: Write `test/unit/test_ability_pool_row.gd`**

```gdscript
# test_ability_pool_row.gd
extends GutTest


func test_populate_sets_name_and_icon():
	var row: AbilityPoolRow = load("res://scenes/ui/menu/ability_pool_row.tscn").instantiate()
	add_child_autofree(row)
	var move: Ability = MoveManagerAuto.get_move(1)  # Leading Strike
	row.populate(move, "res://assets/ui/abilities/Leading_Strike.png")
	assert_eq(row.name_label.text, move.display_name)
	assert_not_null(row.icon_rect.texture)
	assert_true(row.visible)


func test_clear_hides_and_empties_the_row():
	var row: AbilityPoolRow = load("res://scenes/ui/menu/ability_pool_row.tscn").instantiate()
	add_child_autofree(row)
	var move: Ability = MoveManagerAuto.get_move(1)
	row.populate(move, "res://assets/ui/abilities/Leading_Strike.png")
	row.clear()
	assert_false(row.visible)
	assert_eq(row.name_label.text, "")
	assert_null(row.icon_rect.texture)
```

- [x] **Step 6: Remove the 5 static `PoolRowN` nodes from `scenes/ui/menu/abilities_window.tscn`**

Delete the 5 `[node name="PoolRowN" type="Button" parent="PoolRows"]` blocks entirely, delete the `StyleBoxFlat_poolrow`/`StyleBoxFlat_poolrow_hover` sub-resources (now owned by
`ability_pool_row.tscn` instead), and delete the 5 `[connection signal="pressed" from="PoolRows/PoolRowN" ...]` lines. Add an `ext_resource` for the new row scene and instance 5 rows as children
of the existing `PoolRows` `VBoxContainer` in their place:

```
[ext_resource type="PackedScene" path="res://scenes/ui/menu/ability_pool_row.tscn" id="7_poolrow"]

[node name="PoolRow0" parent="PoolRows" instance=ExtResource("7_poolrow")]
[node name="PoolRow1" parent="PoolRows" instance=ExtResource("7_poolrow")]
[node name="PoolRow2" parent="PoolRows" instance=ExtResource("7_poolrow")]
[node name="PoolRow3" parent="PoolRows" instance=ExtResource("7_poolrow")]
[node name="PoolRow4" parent="PoolRows" instance=ExtResource("7_poolrow")]
```

(Each instance line has no overridden properties - the reusable scene's own `custom_minimum_size`/styling/`layout_mode` apply as-is; `VBoxContainer` handles their vertical layout the same way it
already did for the plain buttons.) The `pressed` connections move from `.tscn` `[connection]` blocks to code in the next step, since `AbilityPoolRow`'s `populate()`/`clear()` pattern means the
row's identity (which pool index it currently shows) is entirely managed by `abilities_window.gd`, not fixed at authoring time - matching the wheel sockets' existing code-driven-connection
precedent, not the fixed-literal-bind pattern used for e.g. the class cards in `main_menu.tscn` (those never change WHICH thing a button represents; pool rows do, every scroll).

- [x] **Step 7: Update `abilities_window.gd`'s pool-row handling**

Replace the `@onready var _pool_rows: Array[Button] = [...]` declaration with:

```gdscript
@onready var _pool_rows: Array[AbilityPoolRow] = [
	$PoolRows/PoolRow0, $PoolRows/PoolRow1, $PoolRows/PoolRow2, $PoolRows/PoolRow3, $PoolRows/PoolRow4,
]
```

In `_ready()`, wire `pressed` alongside the existing `mouse_entered`/`mouse_exited` wiring (Task 5 added those to a plain `Array[Button]` - now typed `Array[AbilityPoolRow]`, the loop body
doesn't otherwise change):

```gdscript
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tree_panel()
	_build_wheel_panel()
	for i in _pool_rows.size():
		_pool_rows[i].pressed.connect(_on_pool_row_pressed.bind(i))
		_pool_rows[i].mouse_entered.connect(_on_pool_row_hovered.bind(i))
		_pool_rows[i].mouse_exited.connect(_tooltip.hide)
	visibility_changed.connect(func():
		if visible:
			refresh())
```

Replace `_refresh_pool()` to use `populate()`/`clear()` instead of setting `.text`/`.icon`/`.tooltip_text` directly:

```gdscript
func _refresh_pool(save: PlayerSave) -> void:
	_pool_move_ids = []
	# JSON-loaded saves hold floats - compare as ints.
	var bar_ids: Array[Variant] = []
	for bar_move in save.move_matrix:
		bar_ids.append(int(bar_move))
	for move_id in save.move_matrix2:
		if int(move_id) != 0 and not bar_ids.has(int(move_id)):
			_pool_move_ids.append(int(move_id))
	_pool_scroll = clamp(_pool_scroll, 0, max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS))
	for i in _pool_rows.size():
		var row: AbilityPoolRow = _pool_rows[i]
		var pool_index: int = _pool_scroll + i
		if pool_index >= _pool_move_ids.size():
			row.clear()
			continue
		var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
		var icon_key: String = _sanitize_icon_key(move.display_name if move != null else "")
		row.populate(move, "%s%s.png" % [ICON_DIR, icon_key])
```

`_on_pool_row_pressed()`/`_on_pool_row_hovered()` (both added/touched in Task 5) need no further changes - they already index into `_pool_rows` by position, which is unaffected by the row's node
type changing from `Button` to `AbilityPoolRow` (a `Button` subclass in every way that matters to those two functions).

- [x] **Step 8: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .`
Expected: only the known autoload false positive, if anything.

- [x] **Step 9: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, Task 5's ending count + 2 new tests (Step 5), all passing. In particular re-confirm `test_abilities_window_edits_action_bar` (from `test_ui_scenes.gd`) still passes - it's the
test most directly touching pool-row click behavior end to end.

- [x] **Step 10: Manual visual check**

Without `--headless`, confirm the abilities screen looks and behaves identically to after Task 5 - pool rows are now proper reusable components (adding a 6th visible row, if ever wanted, would
be a one-line change to `POOL_VISIBLE_ROWS` plus one more instanced node, not a new hand-built button).

- [x] **Step 11: Commit**

```bash
git add scripts/ui/menu/ability_pool_row.gd scenes/ui/menu/ability_pool_row.tscn scenes/ui/menu/abilities_window.tscn scripts/ui/menu/abilities_window.gd test/unit/test_ability_pool_row.gd
git commit -m "refactor: migrate the ability pool row to a reusable instanced scene"
```

---

### Task 7: Final verification and `NEXT_PHASES.md` update

**Files:**
- Modify: `NEXT_PHASES.md`

**Interfaces:** none - this task is verification and documentation only.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 6's ending count exactly.

- [ ] **Step 2: Full manual walkthrough**

Without `--headless`: open the abilities screen for each of the 3 classes, confirm tree icons/tooltip/connector-line colors, pool row icons/tooltips/scroll behavior, and wheel socket
icons/tooltips all render and behave correctly. Learn a few nodes across a couple of prerequisite chains to confirm connector-line coloring updates live.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

Find the "## Ability menu redesign" section. Replace its content with a `**DONE (<today's date>)**` note summarizing what landed: real icon art extracted from `DefineSprite 2427` (104 labels,
confirmed full coverage of every active move and passive buff family actually used in `TalentTree.TREES`), the rich floating `AbilityTooltip` (icon + title + description + cost/cooldown +
next-rank preview, backed by a pure `AbilityTooltipBuilder`), prerequisite-colored connector lines, icon thumbnails on pool rows and wheel sockets, and the pool row's migration to a reusable
`ability_pool_row.tscn`. Note the one known, deliberate gap: passive-node tooltip descriptions render blank because the source `buffs.json` has no tooltip text for any tree-passive buff
(verified, not a bug) - and the one deliberate simplification: the original's ~5-frame hover delay before showing the next-rank preview text (`GO7` frame label) was not reproduced, the rich
tooltip shows everything immediately on hover.

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark the ability menu redesign phase complete"
```
