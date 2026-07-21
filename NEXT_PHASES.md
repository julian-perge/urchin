# Next phases

**Every phase of the revival roadmap is complete** (2026-07-18). The full game loop runs and is tested end-to-end: zone orb -> battle selection from quest progression -> roster assembly (player with
talents/gear, companions, enemies) -> playable battle scene with paper-doll visuals, input, and audio -> victory rewards, leveling, drops, achievements, autosave -> back to the zone with progress
advanced. 83 GUT tests / 553 asserts cover it headless.

Delivered, in order: data pipeline fixes, zones + shops, damage/heal/focus formulas, the buff system, the save system, skill/talent trees, the battle turn-loop orchestrator + enemy AI, post-battle
rewards, leveling/respec, zone battle content wiring + the companion party system, item equip validation, the store UI repair, the audio manager, achievements, and the character paper doll + battle
scene. See `KNOWN_GAPS.md` for the handful of deliberate approximations and `SWF_DIFFERENCES.md` for web-vs-Steam data findings.

## Polish backlog (nothing blocks anything - pick by taste)

The UI/scene layer was rebuilt 2026-07-18: main menu (save slots + new-game flow), 7 per-zone hub scenes with SWF-exact orb positions (`scenes/zones/`), the zone-hub shell (`game.tscn` + `game.gd`),
the hotbar (menu buttons / world-map / zone progress), the zone map with SWF-exact button positions, and the asset tree reorganized (`assets/backgrounds/{hub,battle,sky}`,
`assets/ui/{hotbar,battle,store,zone_map}`). Base resolution is the original 800x600 stage (canvas_items stretch), so every SWF-extracted coordinate drops in 1:1.

- **Timeline-accurate animations**

  - **DONE (2026-07-18) - first six labels.** The full MODEL1 timeline (371 frames at 30 fps, per-part affine matrices) lives in `resources/sprites/model1_animations.json` (regenerate:
    `swf_extraction/extract_model1_animations.py`). `character_visual.gd` plays `stand` (idle loop), `hit`, `dead`, and the melee sequence `run` -> `Attack` -> `runback` with run-to-target motion
    (`play_melee(offset)`, battle scene paces on `melee_finished`).
  - **DONE (2026-07-21) - attack variants.** Each move's `addNewMove` param 12 is its animation label (`Ability.animation_label`: Attack / Attack_Upper / Attack_Stab for Melee strikes;
    Krin.Firebolt-style projectile clip names for Missile moves; unused for Shock, which casts). Melee moves run to the target and damage lands at `attack_connected` (mid-swing), with runback after.
  - **DONE (2026-07-21) - movement/timing model.** The faithful krinMelee port (see `DECODED_ALGORITHMS.md`): eased ~0.47 s dash that interrupts the run label, impact at 0.5 s into the strike, the
    strike flowing through `attack2` (the downswing - not a variant), runback at 1.0 s with the eased return.
  - **DONE (2026-07-21) - cast, stun family, and Missile projectiles.** `cast` (189-219) now plays the real MODEL1 label for both Missile and Shock casters; Shock resolves its impact instantly
    (matches the source's same-tick `BAMBAMBAM`), Missile awaits a krinBoltMake-ported `Projectile` bolt's arrival before landing the hit. The stun family (`stun` 220-239 one-shot ->
    `stun2` 240-279 loop -> `outofstun` 280-295 one-shot) is a real value-comparison state machine (`CharacterVisual.enter_stun`/`exit_stun`) driven off the krinBuff `STUN` running total, not a
    fixed `!= 0` toggle - see `DECODED_ALGORITHMS.md`.
  - **Remaining:** the MODEL4 (female) timeline.

- **Missile projectile art** - `scripts/battle/projectile.gd` (`Projectile`) currently draws a generic tinted circle+line for every bolt (see `DECODED_ALGORITHMS.md`'s krinBoltMake section); the real
  clip art needs extracting and either rendered as sprites or reimplemented in GDScript to closely match the original per-element bolt animations. Asset pointers below are WEB-BUILD sprite IDs
  (`sonny-2-2900.xml`) - the Steam SWF's `SONNY2_steam.xml` assigns different IDs to the same export names (spot-checked: `KrinTrail` is web 3 / Steam 205, `Krin.Firebolt` is web 2448 / Steam 2198),
  so re-resolve from whichever SWF's own `swf_xml` dump is actually used for extraction, don't reuse these against the other build:

  - **15 distinct bolt clips**, one per element/move family - the `12_animation_model_name` value on every `moves_abilities.json` row where `10_attack_animation_type == "Missile"`: `Krin.Magicbolt`
    (2446), `Krin.Electrobolt` (2451), `Krin.Electrobolt2` (2450), `Krin.Poisonbolt` (2443), `KRIN.POISONBOLT2` (2442), `Krin.Iceball` (2449), `Krin.Iceblade` (2447), `Krin.Icebolt` (1373),
    `KRIN.SHADOWSHOCK` (2433), `KRIN.YELLOWBLADE` (1161), `KRIN.SHADOWBLADE` (1258), `Krin.Firebolt` (2448), `KRIN.BLADEWHITE` (1104), `KRIN.REDBLADE` (1065), `KRIN.REDBOLT` (1062) - all
    `ExportAssetsTag`-named `DefineSprite`s. None has an ffdec ActionScript export folder under `source_files/action_script/` (they're pure shape/tween content, no clip-events) - extract via
    `ffdec -export image/shape` against the sprite ID, not by grepping the AS export tree.
  - **`KrinTrail`** (the streak effect spawned alongside every bolt) - web sprite 3, Steam sprite 205. Spawned at `frame_42/DoAction_4.as:176`.
  - **BOOM_\* impact clips** (`13_impact_effect_name`, shared with Shock impacts - not projectile-exclusive) fire on bolt arrival: `BOOM1/2/3`, `BOOM_ANAS`, `BOOM_DARK`, `BOOM_RED`,
    `BOOM_SLASHBLUE/GREEN/ORANGE/PURPLE`, `BOOM_SPARK`, `BOOM_STAR_PURPLE`, `ex_SPRBLUE` (sample web IDs: `BOOM1` 1794, `BOOM2` 118, `BOOM3` 2428, `BOOM_ANAS` 1375, `BOOM_DARK` 1714, `BOOM_RED` 1711,
    `BOOM_SPARK` 1712, `BOOM_STAR_PURPLE` 1167, `ex_SPRBLUE` 1281 - the `BOOM_SLASH*` variants weren't individually resolved yet).
  - The cast-glow tint (`colortobe`) and the bolt-trail tint are TWO SEPARATE mechanisms that only share the same color VALUE, not code - don't conflate them when porting: cast glow runs through
    `DefineSprite_152`/`157`'s own `onClipEvent(load)` `Color.setRGB`, while the trail is tinted inline inside `krinBoltMake` itself (`frame_42/DoAction_4.as:177-178`) against the attached
    `KrinTrail` instance directly.

- **Battle screen niceties**

  - The 120-second decision countdown (`BattleRunner.BATTLE_TIME_LIMIT` is exposed, nothing displays it)
  - Buff icons over units
  - A combat log panel
  - Target highlighting
  - The original hotbar-style battle UI art (`assets/ui/battle/*.png` is extracted and waiting)

- **Item click-n-drag** (project owner request 2026-07-18): items should drag between slots; dragging an item over the sell button shows the sell price in the tooltip before dropping.
  Click-to-equip/click-to-keep stands in until then.

- **Menu screens**

  - **Built (2026-07-18)** from the original menu clip (DefineSprite 3142, stage origin 400.5/222.4; frame 1 = inventory, 16 = store, 25 = abilities, 45 = achievements):
    `scenes/ui/menu/inventory_window.tscn`, `abilities_window.tscn`, `achievements_window.tscn`, plus the rebuilt `scenes/ui/store/store_window.tscn` - all wired to hotbar buttons with the green
    active-icon glow. Chrome art extracted at 2x into `assets/ui/menu/`.
  - **Still missing on these screens:** party portrait faces (sprite 2979's frames - frames are placeholders), ability orb icons (original per-move icon art - orbs show initials + element colors), the
    abilities tutorial callout box, and drag-to-socket placement (click-to-place stands in).

- **Screens not yet built** (hotbar buttons dimmed): options, respec button flow (logic in `Leveling.respec`), team-select (`PlayerSave.party_deployed` is ready), character appearance customization
  (SkinSet/HairSet/GSet persistence). References in `assets/references/`.

- **Item icons**: 325 original icons extracted from the icon sheet (sprite 2064) into `assets/ui/items/` with 311 items repointed (2026-07-18); the ~135 items whose names have no icon-clip label still
  use `assets/item_slot_icons/` art.

- **Zone hub art for zones 6/7**: no dedicated hub art exists in the extracted assets - the scenes reuse the wide battle backdrops (`battle/CHURCH.png`, `battle/STREETS.png`), aspect-cropped. Zone 7's
  training orb position is also borrowed from zone 6 (the original Steam-only zone frame has no training orb placement).

- **Cutscenes**: `ZoneProgression.after_battle_won()` reports the cutscene id (`CS_CUT2` etc.); nothing plays them. The original cutscene frames would need art extraction.

- **Shatter Bolt**: the one `"Attack"`-category move - the original never handled it either.

## Ability menu redesign

`scripts/ui/menu/abilities_window.gd` currently shows a flat editable action bar (add/remove active moves) with no icon art and a bare-bones tooltip. The original abilities screen
(`DefineSprite_3142` frame 25) is a richer, three-region layout that this phase should bring the Godot UI in line with:

- **Icon sheet to extract.** Every move icon (equipped bar, unequipped pool, AND skill-tree nodes) draws from ONE shared clip, **`DefineSprite 2427`** (web-build ID; frameCount 986, 104
  `FrameLabelTag`s, one label per move display name plus utility labels `None`/`Empty`/`Empty2` to skip) - the exact same label-lookup shape as the item-icon sheet (sprite 2064) that
  `python_conversion_scripts/swf_extraction/extract_item_icons.py` already handles, so that script is the template to adapt. Open question: confirm whether the 104 labels cover every player-learnable
  move in `moves_abilities.json` or only a subset, before assuming every ability gets real art.
- **Tooltip is richer than name/cost/description.** The original tooltip clip is `DefineSprite 2717` (`KrinToolTipper`, frameCount 19). Fields it actually populates: `inner2` = the move's icon
  (sprite 2427, tinted per-element via `elementColorArray`), `tt` = title, `t` = description (rank-scaled for tree nodes), `t3` = cost/cooldown string, `tyut` = a NEXT-RANK PREVIEW string shown only
  for tree nodes after a ~5-frame hover delay (frame label `GO7`), and a `bfilter` dim overlay when the talent is still unlearned (rank 0). The current Godot tooltip should grow to match: icon +
  title + description + cost/cooldown + next-rank preview.
- **Layout is a branching tree, not a flat list** - three coexisting sub-regions to rebuild:
  1. `selector` (sprite 3109, `thing0..thing7`) - the flat 8-slot equipped-move loadout bar (already the closest match to what exists today).
  2. `talentPool.talentPool2` (sprite 3120) - a scrollable 2-column zigzag list of every unlocked-but-unequipped move (`x = Math.pow(-1,n)*-40+45` alternates column, `y` advances `35`px every 2
     entries) - the pool you drag from into the 8 hotbar slots.
  3. **The actual per-class talent tree** (`PlaceObject3_3100_153`, sprite 3100, one frame per class) - 40 fixed-position nodes (`st0..st39`, sprite 3097 each) with a `PRESKILL` prerequisite-ID
     array per node; `krinRemakeTree()` draws connector lines between each node and its prerequisites via the Drawing API, gold if the prerequisite is learned, dark gray/green if not. Nodes show
     rank progress (current/max tier) and dim when unlearned. `TalentTree` (the logic-layer class) already enforces the all-prerequisites-required rule (see `KNOWN_GAPS.md`) - this phase is purely
     about giving that existing logic a real node-and-edge graph visual instead of today's flat presentation. Open questions: exact `st0..st39` pixel coordinates per class weren't dumped (would
     need a targeted per-node PlaceObject matrix extraction), and whether all 12 classes share one node topology or differ was not confirmed.

## UI architecture: native Godot Containers instead of code-built controls

Everything under `scripts/ui/` currently builds its Control tree imperatively at runtime (`Button.new()`, `StyleBoxFlat.new()`, manual `.position`/`.size` assignment) - `scripts/ui/store/item_slot.gd`
and `scripts/ui/store/store_window.gd` are the two examples called out to start with, but the same pattern runs through `inventory_window.gd`, `abilities_window.gd`, `achievements_window.gd`,
`hotbar.gd`, `menu_theme.gd`'s `add_texture_rect`/`add_label` helpers, and `battle_scene.gd`'s overlay-building code. The goal is to migrate toward declarative `.tscn` scenes with real Container
nodes, matching how Godot's own demo projects are built - reference clone at `/Users/julianperge/DEVELOPER/git_repos/godotengine/godot-demo-projects/2d/` (`dodge_the_creeps`, `platformer/gui`, and
`role_playing_game/combat` were surveyed). Conventions worth adopting, in order of impact:

- **One small reusable `.tscn` per repeated element, instanced via `PackedScene`.** The RPG demo's `combat/interface/info.tscn` (a standalone "stat card": Name label + HP ProgressBar, no script of
  its own) is instantiated once per combatant by `ui.gd` (`@export var info_scene: PackedScene`, loop of `.instantiate()` + set a couple of child properties + `add_child()`), never built
  node-by-node in a loop. This is the direct template for `item_slot.gd`: make an `item_slot.tscn` (icon TextureRect + price Label + hover highlight, laid out in the editor) and have
  `store_window.gd`/`inventory_panel.gd` instance it per slot instead of constructing each slot's Controls from scratch in code.
- **Scripts hold `@onready` references and mutation methods, not tree-building.** Across every demo reviewed (`hud.gd`, `coins_counter.gd`, `pause_menu.gd`), the attached script's job is limited to
  `$Path/To/Node` lookups plus small functions that set `.text`/`.value`/`.visible` on nodes the editor already laid out - never constructing the nodes themselves at runtime.
- **Containers + size_flags for anything that reflows; anchors_preset + offsets only for fixed/pinned chrome.** `GridContainer`/`HBoxContainer`/`VBoxContainer`/`PanelContainer`/`CenterContainer`
  children use `size_flags_horizontal/vertical` (`EXPAND_FILL` / `SHRINK_CENTER`) and let the container solve layout; static HUD pieces that never reflow (score labels, pinned counters) just use an
  anchor preset plus manual offsets, no container needed.
  Store/inventory grids and the ability pool list are exactly the reflowing case containers are for.
- **Centralize styling in Theme `.tres` resources, not code.** The demos define `Button`/`Panel`/`ProgressBar` styles once in a shared `theme.tres` (`StyleBoxTexture` or `StyleBoxFlat` per control
  type), use `theme_type_variation` for one-off panel styles that share most of a base style, and reserve `theme_override_*` for genuine per-instance exceptions. `menu_theme.gd`'s current
  `add_texture_rect`/`add_label` helpers exist BECAUSE nothing is theme-driven yet - once real `.tscn` scenes with an assigned Theme resource take over, most of that helper file becomes unnecessary.

Sequencing note: this is a large, cross-cutting change and nothing above blocks it from happening incrementally - `item_slot.gd`/`store_window.gd` are explicitly named as the smallest, most
self-contained starting point. Since the ability menu redesign above is new work rather than an existing screen, it's worth doing that phase in the NEW `.tscn`-plus-Container style directly, once
the pattern is proven on the store, rather than building it flat now and re-migrating it later.

**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, and `scripts/ui/menu/abilities_window.gd` migrated - `item_slot.tscn` now owns
the hover highlight as a real child node, `store_window.tscn` now owns every static chrome node plus a `GridContainer` for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar
chrome plus a `GridContainer` for the 6x6 slot grid, and `abilities_window.tscn` now owns its static chrome/attribute panel plus a `VBoxContainer` for the 5-row ability pool - the 28-node talent
tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code (via a new reusable `talent_node.tscn`, the same instanced-`PackedScene` pattern as `ItemSlot`), and the
8-socket wheel stays entirely code-driven by design (no static content or reusable child structure to extract). Everything else named in this phase (`achievements_window.gd`, `hotbar.gd`,
`battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.

## Testing: GUT

GUT 9.6.1 is vendored at `addons/gut/`, tests in `test/unit/` + `test/integration/`, config in `.gutconfig.json`. Run headless (exits nonzero on failure):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Compile-check a script without GUT: `Godot --headless --check-only -s <script.gd> --path .` (run `--headless --import` once after adding new `class_name` scripts, or the class cache is stale and
reports false "not declared" errors).
