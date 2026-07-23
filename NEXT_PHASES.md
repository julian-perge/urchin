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

Everything under `scripts/ui/` originally built its Control tree imperatively at runtime (`Button.new()`, `StyleBoxFlat.new()`, manual `.position`/`.size` assignment). `item_slot.gd`,
`store_window.gd`, `inventory_panel.gd`, `abilities_window.gd`, `achievements_window.gd`, `hotbar.gd`, `inventory_window.gd`, `main_menu.gd`, and `victory_screen.gd` are all migrated now (see the
**DONE** note below) - `menu_theme.gd`'s `add_texture_rect`/`add_label` helpers that this phase called out as a symptom are deleted entirely. **Only `battle_scene.gd`'s own overlay-building code
(bottom bar, stance row, pass ring) is still imperative** - the last item left in this phase. The goal was to migrate toward declarative `.tscn` scenes with real Container
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
  type), use `theme_type_variation` for one-off panel styles that share most of a base style, and reserve `theme_override_*` for genuine per-instance exceptions. This project didn't go as far as a
  shared `theme.tres` - each migrated `.tscn` bakes its own `theme_override_*` properties per node instead - but `menu_theme.gd`'s `add_texture_rect`/`add_label` runtime-construction helpers, which
  existed only because nothing was theme-driven yet, are now deleted (zero remaining callers once `inventory_window.gd`/`main_menu.gd`/`victory_screen.gd` were migrated). `menu_theme.gd` itself
  stays - its remaining members (`ELEMENT_COLORS`, `STAT_LABELS`/`STAT_COLORS`, `bar_fill_fraction()`, `texture()`, `format_money()`, etc.) are genuinely reusable non-construction utilities.

Sequencing note: this is a large, cross-cutting change and nothing above blocks it from happening incrementally - `item_slot.gd`/`store_window.gd` are explicitly named as the smallest, most
self-contained starting point. Since the ability menu redesign above is new work rather than an existing screen, it's worth doing that phase in the NEW `.tscn`-plus-Container style directly, once
the pattern is proven on the store, rather than building it flat now and re-migrating it later.

**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/menu/abilities_window.gd`,
`scripts/ui/menu/achievements_window.gd`, and `scripts/ui/hotbar.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, `store_window.tscn` now owns every static chrome
node plus a `GridContainer` for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar chrome plus a `GridContainer` for the 6x6 slot grid, `abilities_window.tscn` now owns its
static chrome/attribute panel plus a `VBoxContainer` for the 5-row ability pool (the 28-node talent tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code via a
reusable `talent_node.tscn`, the same instanced-`PackedScene` pattern as `ItemSlot`, and the 8-socket wheel stays entirely code-driven by design), `achievements_window.tscn` now owns its chrome plus
all 10 fixed-position achievement plates (only each plate's locked/unlocked `StyleBoxFlat` and label color stay code-driven), and `hotbar.tscn` - already the most declarative of the group, built
with real `HBoxContainer`/`CenterContainer`/`VBoxContainer` layout from the start - now also owns the quit button and every button's glow/icon overlay children, with only the per-instance
hover-tint wiring left in code. `scripts/ui/menu/inventory_window.gd` is also migrated - `inventory_window.tscn` now owns its static chrome (backdrop, close button, status label, left/center panel
textures, name/level/experience-row content, all 5 stat rows, Piercing/Defense titles), all 16 element-bar tracks and fills (8 "per" + 8 "def"), the party bar background, and all 6 fixed portrait
frames (each an instance of `item_slot.tscn` with a static `Face` child) - only the bars' fill height/position (`_update_bar()`) and the portraits' tooltip/dimming (`_refresh_portraits()`) stay
code-driven, both genuinely live-save-dependent. `scripts/ui/main_menu.gd` is also migrated - `scenes/main_menu.tscn` (already partially declarative before this pass) now owns the title label, the
class-select screen's chrome and all 3 fixed-order class cards (Psychological/Biological/Hydraulic, each wired via a `[connection]` with the class id bound as a literal) plus its Cancel button,
and the settings screen's chrome, difficulty picker (3 buttons sharing one `ButtonGroup` sub-resource), and 3 toggle rows (Tutorial/Sound/Autosave, each with its own named handler method since
their side effects differ - Sound's also mutes an audio bus) plus its Start/Back buttons - only the save-slot button list stays code-driven (`_refresh_slot_buttons()`, count is `GameData.NUM_SLOTS`
and each label depends on live save data). `scripts/ui/menu/inventory_window.gd`, `scripts/ui/main_menu.gd`, and `scripts/battle/victory_screen.gd` are also migrated, completing the retirement of
`menu_theme.gd`'s runtime `add_texture_rect`/`add_label` helpers (both deleted - zero remaining callers). `victory_screen.gd` didn't have a `.tscn` at all before this - it now has
`scenes/battle/victory_screen.tscn` for its static chrome, plus a new reusable `scenes/battle/victory_experience_row.tscn` (instanced once per fighter, 1-3 depending on the deployed party) for
what used to be raw per-row `MenuTheme` calls, matching the same instanced-`PackedScene` pattern as `ItemSlot`/`talent_node.tscn`. Only the drop slots (`ItemSlotScene`, count varies per battle)
and the embedded `InventoryPanel` stay code-instanced, both already using the established `PackedScene` pattern from the start. `battle_scene.gd`'s instantiation call site was updated from
`.new()` to `preload(...).instantiate()` accordingly. Everything else named in this phase (`battle_scene.gd`'s own bottom-bar/stance-row/pass-ring construction, a separate piece of work from the
`MenuTheme` retirement) is still pending.

## Enum conversion audit

Prompted by the project owner adding static typings across the codebase: several hardcoded `Array`/`Dictionary` constants represent a small, CLOSED set of named categories (not open-ended game
data like item/move/zone names) and would read more safely as real GDScript `enum`s - both because a typo in a magic int/string currently fails silently, and because two of them are already
duplicated verbatim across multiple files. No helper/wrapper class is warranted for this - the codebase already has an established, working convention (see below), and adding an abstraction layer
on top of plain GDScript enums would be over-engineering for what's fundamentally a naming/typing problem, not a structural one.

**Existing convention to match** (already used in 8+ places, don't invent a new style): `enum Name { A, B, C }` declared single-line for small sets (`BattleRunner.Outcome`, `CombatUnit.Difficulty`,
`AudioManagerAuto.MusicMode`, `CharacterVisual.State`, `Leveling.Stat`) or one-value-per-line for bigger ones (`GameItem.ItemType`/`Rarity`/`ClassType`, `TalentTree.LearnResult`,
`Equipment.EquipResult`), paired with an enum-keyed `Dictionary[EnumType, ValueType]` for lookup/message tables (`Equipment.EQUIP_RESULT_MESSAGES`, `TalentTree.LEARN_RESULT_MESSAGES`,
`CombatUnit.DIFFICULTY_MODIFIERS`) or an `Array[EnumType]` for enum-typed ordered lists (`Equipment.EQUIP_SLOT_TYPES`). Persisted/exported fields stay plain `int` even when enum-valued
(`PlayerSave.difficulty`, `BattleRunner.win_condition`) to keep `.tres`/save serialization simple; only function parameters/locals take the enum type directly. New enum work should follow this
exact split, not introduce a different pattern.

- **`PlayerClass` (Biological/Psychological/Hydraulic) - clear win, bigger than it first looked.** `CLASS_NAMES: Array[String]` is duplicated verbatim in `scripts/ui/main_menu.gd:11`,
  `scripts/ui/menu/inventory_window.gd:16`, and `scripts/ui/menu/abilities_window.gd:36`. The same `0/1/2` domain is ALSO the raw dictionary key for `Leveling.CLASS_BASE_RATIOS`,
  `TalentTree.STARTING_MOVES`, `TalentTree.TREES`, `main_menu.gd`'s `CLASS_CARD_ORDER`/`CLASS_CARD_ART`, and `Achievements.classes_cleared[save.player_class]` - `PlayerSave.player_class: int` is
  the field threaded through all of them. Note `Equipment.required_unit_id != save.player_class + 1` (`equipment.gd:79`) - that `+1` offset to unit id must stay a documented offset, not get
  folded into the enum's own values.
- **Aggression stance (Phalanx/Defensive/Tactical/Aggressive/Relentless) - clear win**, exactly the case the project owner already flagged: `Party.AGGRESSION_NAMES`/`AGGRESSION_PRESETS`
  (`party.gd:25,32`) duplicate the same 5-name domain as `scripts/editor/units.gd:23`'s `AGGRESSION_ORDER`. `get_ag_mode`/`set_ag_mode`/`apply_aggression_mode` all take a raw `mode: int`,
  `clampi`'d against `AGGRESSION_PRESETS.size() - 1` in three places; the magic default `2` ("Tactical") is repeated in `party.gd`, `player_save.gd`, and `battle_scene.gd`.
- **`MovePool` ("attack"/"defense"/"absolute") - clear win.** Currently a stringly-typed dictionary key/`match` target threaded through `battle_ai.gd` (assigns `pool = "attack"` etc., 4 sites) and
  `battle_runner.gd`'s `match action["pool"]:` - mirrors `CombatUnit`'s already-parallel `move_pool_attack`/`_defense`/`_absolute` and `cooldowns_attack`/`_defense`/`_absolute` fields.
- **`Team` (side 1/2) - clear win.** `CombatUnit.team_side: int` is compared/assigned as raw `1`/`2` across `battle_runner.gd`, `battle_scene.gd`, `battle_ai.gd`; `BattleRunner.TEAM_SLOTS` is
  already keyed `{1: [...], 2: [...]}` - an `enum Team { ONE = 1, TWO = 2 }` matches those keys with zero renumbering. Smaller, single-file companion case: `battle_scene.gd`'s `RING_COLORS` dict
  keyed by raw strings `"player"/"ally"/"enemy"` (from `_relation_to_player()`) could become `enum Relation { PLAYER, ALLY, ENEMY }` - not duplicated elsewhere, lower priority.
- **Partial adoption to finish, not a duplication - `Difficulty` and `Leveling.Stat` already exist as enums but get bypassed with magic numbers/unlinked arrays elsewhere:**
  - `CombatUnit.Difficulty` (`combat_unit.gd:12`) is used correctly in `from_character()`/`DIFFICULTY_MODIFIERS`, but `main_menu.gd:19` has its own unlinked `DIFFICULTY_NAMES: Array[String] =
    ["Easy", "Challenging", "Heroic"]` (names don't even match the enum identifiers - `NORMAL` vs "Challenging"), and `PlayerSave.difficulty: int` gets raw-int-compared in
    `zone_progression.gd:115-120` (`if difficulty <= 0: ... if difficulty == 1:`) and `achievements.gd:46,51,75` (`if save.difficulty == 2`).
  - `Leveling.Stat` (`leveling.gd:25`) is used correctly by `Equipment.ATTRIBUTE_TO_STAT`, but `Leveling.spend_stat_point(save, stat_index: int)` takes a raw int (called with a raw loop var from
    `abilities_window.gd:251,255`), and `MenuTheme.STAT_LABELS`/`STAT_COLORS` are separate parallel arrays aligned to `Stat` by convention only, with no reference to the enum itself.
- **`ELEMENT_ORDER` (Physical/Magic/.../Poison) - borderline, bigger effort than it looks; dedupe the easy part now, defer the rest.** `scripts/editor/units.gd:24` duplicates
  `CombatUnit.ELEMENT_ORDER` verbatim (clean one-line fix: reference the constant instead of restating it, same as that file already does for other constants). Converting the underlying
  *concept* to an enum is a bigger lift: move/character data files carry the element as a bare string (`Ability.damage_element_type`), `CombatUnit.base_per`/`base_def` are `Dictionary` keyed by
  that element NAME STRING (not position) across `combat_unit.gd`/`player_save.gd`/`party.gd`/`equipment.gd`, so an enum would need a string<->enum translation layer at data-load time before
  touching any of those read/write sites. The existing `ELEMENT_ORDER` + `MenuTheme.ELEMENT_COLORS` parallel-array pattern is fine as-is in the meantime (Godot has no cheaper enum-to-typed-literal
  shorthand); if `Element` becomes a real enum later, `ELEMENT_COLORS` could upgrade to `Dictionary[Element, Color]` for free extra safety.
- **Equip slot index (0-6) - borderline, judgment call, don't convert the whole thing.** `Equipment.EQUIP_SLOT_TYPES`/`MAIN_HAND_SLOT`/`SECONDARY_SLOT` (`equipment.gd:44` and around) is where the
  slot index genuinely means a "kind" (which body slot) - an `EquipSlot` enum there would remove the magic `5`/`6`. But `inventory_window.gd`/`store_window.gd`'s `EQUIP_SLOT_CENTERS` and
  `equip_doll_view.gd`'s `equip_index` treat the same 0-6 range as purely structural/positional (never branch on "which kind of slot") - leave those as plain `int`, converting them adds no
  safety.
- **Trivial while touching this area:** `CharacterVisual.set_state(new_state: int)` (`character_visual.gd:174`) should take `State` instead of `int` - the enum already exists in the same file
  and every call site already passes `State.X` values; this is a signature tightening, not a duplication fix.
- **Explicitly NOT enum candidates** (open-ended/data-driven content, matches the project owner's own exclusion): zone/battle/shop/item id-keyed dictionaries (`ZoneManager.ZONES`,
  `StoreManager.ZONE_SHOP_IDS`/`SHOP_DIALOGUE`/`KRIN_SHOP_ITEMS`, `GameData.STARTING_EQUIPMENT`, `ZoneProgression`'s battle-cap tables), `Achievements.NAMES`/`DESCRIPTIONS` (text content), and
  `hotbar.gd`'s `MENU_BUTTON_GROUPS`/`HOVER_COLORS` (keyed by actual Godot scene-node names, not a portable "kind" concept).

## Testing: GUT

GUT 9.6.1 is vendored at `addons/gut/`, tests in `test/unit/` + `test/integration/`, config in `.gutconfig.json`. Run headless (exits nonzero on failure):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Compile-check a script without GUT: `Godot --headless --check-only -s <script.gd> --path .` (run `--headless --editor --quit --path .` once after adding new `class_name` scripts, or the class
cache is stale and reports false "not declared" errors - this is per-checkout, so re-run it in any other worktree or the main checkout after merging in new `class_name` classes, even if the
branch itself already verified green).
