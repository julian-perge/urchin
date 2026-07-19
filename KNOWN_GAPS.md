# Known gaps

Deliberate, scoped-out gaps in the battle system (phases 3a/3b). Paused here as of 2026-07-18 to
work on zones and the save system instead. Each entry has enough detail to pick back up without
re-reading the AS3 source from scratch.

## Dispel - RESOLVED (2026-07-18, battle turn-loop phase)

The consuming code turned out to live in the per-frame battle conductor
(`frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt`), not `executeMove()`. Now ported as
`BattleRunner._resolve_dispels()`: on a successful strike, before the damage/heal resolves, up to
`Ability.dispel_count` of the target's active buffs are removed if their element is in
`Ability.dispel_element_types` and their `Buff.polarity` matches `Ability.dispel_target_polarity`,
each attempt gated by `randf() <= dispel_chance` and resisted by the buff's
`dispel_resist_chance`. The formerly unknown buff fields 20/27/32 turned out to be
polarity/is-unique/dispel-resist (renamed in `convert_buffs.py` + `buff.gd`).

## "Attack" effect_category

One move in the entire dataset (479 total) has `effect_category == "Attack"`: **Shatter Bolt**
(has a status effect, `SHATTERBOLT`). The original AS3 `executeMove()` only branches on
`"Full Damage"`/`"Heal"`/`"Focus"` - it does **not** handle `"Attack"` either, so this move does
nothing via that function in the source game too. This is not a gap introduced by the port;
whatever `"Attack"` moves are supposed to do lives in code outside the extracted frames (or the
category is legacy/dead).

`BattleManager.execute_move()` currently `push_warning()`s and returns `{}` for any unhandled
category. Low priority - affects exactly one move.

## Stun / Silence / Reflect - ALL RESOLVED (2026-07-18)

- **Stun**: a unit with `stun != 0` can't act on its turn at all - gated in
  `BattleRunner._execute_action()` ("you are stunned this round", no partial effect). Attacks
  against stunned targets also always hit (`_accuracy_roll()`).
- **Silence**: blocks any move with a focus cost (`cost * SILENCED == 0`). Applied in
  `BattleAI._can_afford()` for AI units and `BattleRunner.get_player_usable_moves()` for the
  player - the player-side gate was confirmed from source via the full SWF script export
  (`frame_42/DoAction_11.as` uses the identical check in the move-pick UI).
- **Reflect is dead code in the original game - nothing to implement.** The full 869-script
  export contains exactly one `REFLECTDMG` reference (the initializer to 0 in frame 201), and
  none of the 470 buffs carries a nonzero reflect delta (checked). The stat exists on
  `CombatUnit` for completeness and does nothing, faithfully.

## Store UI scene - RESOLVED (2026-07-18, store repair phase)

The missing `%`-nodes lived inside the instanced `inventory.tscn`, where unique names can't
cross the scene boundary. Fixed by giving `inventory.tscn` its own script
(`scripts/ui/inventory_panel.gd` - grid population, selection, gold display, sell/delete
signals) and rewriting `store_window.gd` to drive that API plus its own `%StoreItems` grid
(buy on click, sell/delete wired to `GameData`). `item_slot.gd` rewritten: holds a `GameItem`,
shows `slot_image` (now populated by `scripts/editor/items.gd` from the readable
`assets/item_slot_icons/` files) with `sprite_image` fallback, emits `slot_clicked`.

Regenerate item .tres (`scripts/editor/items.gd`, File > Run) to pick up the new
`required_unit_id` field and the slot icons.

## 11 numeric-named asset stragglers are untraceable (investigated 2026-07-18, dead end)

The user asked to re-extract `assets/backgrounds/`, `assets/item_slot_icons/`, and root-level
`assets/` images from the SWF and match names exactly like was done for audio. That worked for
audio because sounds have clean `ExportAssets` linkage names in the SWF. Background/icon art does
not - verified by exporting all 1343+ named sprite symbols from `sonny-2-2900.swf` and searching
for anything matching zone names or item-icon patterns: nothing. Manually inspected one of the
large unnamed sprites (`DefineSprite_3229`, no linkage name) and confirmed it's real background
art (a train interior) - **the SWF's background/icon art is embedded as anonymous numbered
symbols with no export name to recover, full stop.**

Given that, the current naming schemes are already the best available:

- `assets/item_slot_icons/*.png` - item display names, pulled from the item database (not SWF
  symbols)
- `assets/backgrounds/**/*.png` - names derived from gameplay data (`battles.json`'s
  `zone_background` field), from the phase-2 zone work

11 files remain numeric-named and were investigated individually via the raw SWF tag dump
(`ffdec -dumpSWF`):

- `assets/backgrounds/3032.png`, `3034.png`, `assets/backgrounds/zone/3423.png`/`3424.png`/
  `3438.png`/`3440.png`/`3450.png`/`3452.png` - these numbers **are** the real SWF chid (confirmed:
  genuine `DefineBits`/`DefineShape` tags at those exact ids), just never given an export name.
  The numeric name is factually accurate here, not a placeholder - there's nothing better to
  recover. (The `zone/` ones were also visually confirmed back in phase 2 to be gradient/vignette
  overlay shapes, not full zone backgrounds.)
- `assets/item_slot_icons/PANTS/356.png`, `SHOES/402.png`, `WEAPONS/797.png` - these numbers are
  **not** chids at all (chid 356 is an unrelated `DefineSound`, 402 another unrelated
  `DefineSound`, 797 an unrelated `DefineShape2`) - some other, disconnected indexing scheme,
  genuinely untraceable. Per the user: leave these numeric rather than guess a name that could be
  confidently wrong (2026-07-18).

## Talent system assumptions - ALL RESOLVED (2026-07-18)

The two reconstructed rules from the talent phase were both confirmed the same day, when the full
SWF script export (869 scripts via `ffdec -export script`) surfaced the actual talent learn button
(`DefineSprite_3142`'s tree screen, `DefineButton2_3096`):

- **Multi-prerequisite nodes are ALL-required** - the button loops every `PRESKILL` entry and
  rejects if any has rank 0. `TalentTree.can_learn()` already did this.
- **Each rank costs exactly 1 skill point** (`skillPoints--` per learn), and the grant rate is
  **1 skill point per level-up** (victory-screen level-up code) plus the 5 starting points -
  which is why respec resets to `level - 1 + 5`.

The same button code showed `moveMatrix2` is REBUILT (starting moves + nonzero
`skillAdderMatrix` entries in node-index order) rather than maintained incrementally -
`TalentTree.learn()` was aligned to match.

## Character rig + battle scene - RESOLVED (2026-07-18, final phase)

The Skeleton2D + IK rig (`character.tscn`) and the old static `battle.tscn` were deleted and
replaced:

- `scripts/entities/character_visual.gd` + `scenes/character_visual.tscn` - a plain-Node2D paper
  doll. The 15 part transforms are the EXACT MODEL1 rest-pose matrices extracted from the SWF
  (`ffdec -swf2xml`, twips converted to px), texture layering is the `dressChar()` port
  (base skin / equipment / hair, skinSetter uniforms), and animation is a code-driven state
  machine (idle bob, melee swing, cast raise, stun wobble, hit recoil, death fall). No bones, no
  IK - the failure mode is gone by construction.
- `scripts/battle/battle_scene.gd` + `scenes/battle_scene.tscn` - the playable battle screen:
  dolls per slot with health/focus bars, click-to-target + move-bar input, event-log replay with
  floating combat text, speech lines, audio hookup, and the full victory pipeline (progression,
  rewards, drops, achievements, autosave). Orbs launch it via `ZoneManager.pending_battle`.

Future polish, not gaps: the SWF's MODEL1 timeline also contains the complete original keyframe
animations (371 frames, labels `stand/run/Attack_Stab/cast/stun/hit/dead/...`) - extractable
the same way the rest pose was, if the code-driven animations ever feel too plain. Female
characters currently reuse the MODEL1 (male) rest pose; MODEL4's matrices can be extracted the
same way. Player appearance customization (SkinSet/HairSet/GSet) isn't persisted - Sonny uses
his default look.

## Battle/menu UI rebuild (2026-07-18, second pass)

Scoped-out edges from the playtest-feedback batch:

- **Top battle bar panel**: the original shows every fighter's health/focus with numbers in a
  panel across the top of the battle screen (reference `9_inbattle_start...png`). Noted, not
  built - the in-field bars carry the health number instead.
- **Ability orb art**: radial-menu and abilities-screen orbs draw initials + element colors;
  the original's per-move orb icon art is not extracted yet.
- **Radial menu is click-to-cast**: the original picks up the ability with the cursor; here a
  usable orb casts on click directly. Unusable orbs darken, matching the source.
- **Class-select card art**: the three class cards are styled frames without the original
  sketch art (reference `6_start_screen...png`); the art lives in the class-select button
  up-states and could be exported like the other chrome.
- **Tutorial Level option**: stored on the options screen, but no tutorial system exists.
- **Wolfgang/Amber portraits**: the web SWF's face-clip frames for party ids 4/5 are empty at
  their labels; the extracted portraits are blank frames. Party data also names them
  Teco/Catelin (from the companion seeds) while the face-clip labels say Wolfgang(Rockstar)/
  Amber - naming not yet reconciled against the Steam build.
- **Effects/Graphics options**: deliberately skipped per project owner.
