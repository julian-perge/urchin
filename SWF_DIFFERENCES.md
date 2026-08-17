# Web SWF vs Steam SWF differences

Tracking file for divergences found between the original web release (`sonny-2-2900.swf`, repo root) and the Steam rebundle (`SONNY2.swf`, repo root). Both builds define game content the same way -
imperative AVM1 call sequences in frame 42 (`createNewUnitKrin(...)` / `createNewBattle()` / `addNewMove(...)`, etc.) - decompilable with `ffdec -export script`; neither embeds a structured data
format. The readable decompiled code in `source_files/action_script_curated/` is the web release's script (the full ffdec export lives at `source_files/action_script/`).

The raw dumps in `dev/data_json/` are a different thing entirely: a runtime capture of the Steam build's live `_root` arrays taken while the game was running, not anything ffdec or a script
extracts from the SWF itself - confirmed by local variables from inside `krinAddNewUnit` (e.g. `beubUBv`) turning up as object keys, and by top-level names (`UNITS`, `ITEMS`, etc.) that appear
nowhere in either SWF's AS. There is no repo script that produces them and, since they're a point-in-time capture rather than a deterministic export, there cannot be one - they're committed as-is
(restored 2026-08-17 from `git show ccf7375^:python_conversion_scripts/data_json/<file>` after being accidentally deleted alongside the old `python_conversion_scripts/` dir; `convert/*.py` now call
`require_data_json()` and fail with that same restore command if a dump is missing). The data pipeline consumes these Steam-shaped dumps; the web AS3 is the ground truth for semantics and is what
resolved the two bugs below.

## Confirmed identical

- **Game content counts match**: 480 moves, 471 buffs, 450 items, 75 units, ~100 battles in both. (Checked earlier in the revival, 2026-07-18.)
- **Battle definitions use the same unit id numbers** in both (verified via battle 200/202 rosters matching zone content in both id spaces).
- **Full field-by-field parity, verified 2026-08-17.** A throwaway parser (not committed - reconstructing it would mean re-deriving the `for..in` enumeration-order quirks below from scratch) walked
  the web AS3's `frame_42` data blocks directly - `addNewMove`/`addNewBuffKrin`/`createNewUnitKrin`/`createNewBattle`/`createNewItemKrin` calls plus every stateful follow-up line (`_root.hackMove[N] =`,
  `jesivie.field =`, `rengi.field.push(...)`, the `Krin.HealthUP`/`PIU`/`DIU` accumulators reset by `allClearKrinItem()`) - and compared the result field-by-field against `dev/converted_json/*.json`.
  Zero content drift across all five tables: 479/479 moves, 470/470 buffs, 75/75 units, and all 449 items match exactly, including the fully-derived stats (`createNewItemKrin`'s price formula,
  `getStat`/`respecValue`, and the piercing/defense stat-to-tooltip text). All 99 battles match content-for-content once compared by creation order rather than by the `id` field (see the next bullet).
  The only fields intentionally left uncompared: item `looks` (the dump captures it as `Undefined` for every item - `convert_items.py` already sources it from the separate
  `dev/urchin_dev/swf/extract/item_looks.py`, not from `data_json` at all) and battle `id`/`id_name` (see below).
  - Two things that looked like drift turned out to be genuine bugs in the *original web build itself*, faithfully carried through to both the Steam dump and `converted_json`: buff id 416
    references `_root.KrinLang[KLangChoosen].AUX[30]` (frame_42/DoAction_10.as:3154) - no `AUX` table exists, only `AUX1`/`AUX2`/`AUX3` - so its `25_tooltip_description` is `Undefined` on both sides.
    And `createNewItemKrin`'s "for" loop over the 5-slot `statUpdater` array (health/strength/magic/speed/focus) enumerates in *descending* index order, while the same loop over the 8-slot
    `statUpdaterP`/`statUpdaterD` (piercing/defense per element) enumerates *ascending* - a legacy AS2 `Array` `for..in` quirk, not a bug, but one that had to be matched exactly to get
    `tool_tip_alt`'s sentence order to agree.
  - **Battle `id` is not `battleCreationID`'s value at creation time.** `battleCreationID = N;` jump statements (nine of them, reserving per-zone id blocks: 49, 99, 199, 299, 399, 499, 599, 699, 999)
    retroactively relabel the *previous* battle - the one whose properties were just being set - rather than the next one; the following `createNewBattle()` then continues incrementing from the
    jumped value. Confirmed by comparing all 99 battles by creation-order position instead of by `id`: zero content mismatches. A real regenerator would need this rule; this investigation didn't need
    to fully pin it down since position-alignment already proved the underlying data has no drift.

## Bugs introduced by the Steam restructuring (fixed in the conversion pipeline)

- **Two units carry wrong ids in the Steam data** (fixed in `dev/urchin_dev/convert/units.py` `ID_CORRECTIONS`, 2026-07-18). The web SWF assigns unit ids from a sequential counter that is manually jumped twice
  (`createUnitKrinCount = 19` immediately after creating Doctor Hedger, `createUnitKrinCount = 39` immediately after ZPCI Sniper - `frame42/sonny2_createNewUnitKrin.txt`). The Steam data recorded the
  POST-jump counter value as those two units' `id` fields:
  - Doctor Hedger: Steam says 19, true id is **15** (battles 54/107 reference 15).
  - ZPCI Sniper: Steam says 39, true id is **34** (battle 299 references 34).

  No battle references 19 or 39 anywhere, so the correction is unambiguous. Ids 16-19 and 35-39 are genuinely unused in both releases.
- **Aggression scalars carry misleading labels in the Steam data.** The web SWF stores each unit's AI tuning as a positional `agressionArray` = `[Aggression, LifeBoundary1, LifeBoundary2,
  FocusAggression, FocusRegenLimit]` (consumed positionally by `krinAddNewUnit`, `frame42/sonny2_createNewBattle.txt`). The Steam data stores the same 5 values keyed by the five aggression MODE names
  (`Phalanx`/`Defensive`/`Tactical`/`Aggressive`/`Relentless`) - which are labels for something else entirely (the arena AI-mode presets in `sonny2_agression.txt`). The values are positionally
  identical to the web arrays (verified: Veradux web `[50,80,20,50,15]` == Steam key order reversed; `LifeBoundary2 <= LifeBoundary1` holds for all 75 units in this mapping and fails in the
  alternative). See `scripts/editor/units.gd` for the decode table.
- **Absolute-move phase locks renamed.** The web `movesABS` entries are `[move_id, phase]` pairs (phase 0 = usable in any battle phase); the Steam data calls the second element `turn`. Naming only -
  values match. Handled in `scripts/editor/units.gd` (`_absolute_moves()`).
- **Item class restrictions carry junk labels too** (fixed in `convert_items.py` `class_unit_id`, 2026-07-18). The raw `KRINITEM[3]` value is a required UNIT id (0 = anyone, 4 = Veradux's Medic/KLIMA
  gear - the only restricted items in the game); the Steam data labeled it with `krinClassArray` names by index, so every unrestricted item read "Dreadnaught" and Veradux's gear read "Phaser". No item
  restricts by player class at all.

## Dropped on purpose (not differences, but scoped out from both)

- The PvP share-code and anti-cheat system (deterministic `KRS`/`KRSO`/`KRRR()` RNG array, save-code checksums) exists in both releases and is deliberately not being ported (project decision,
  2026-07-18). Battle rolls use fresh `randi_range()`/`randf()` instead.
