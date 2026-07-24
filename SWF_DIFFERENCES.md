# Web SWF vs Steam SWF differences

Tracking file for divergences found between the original web release (`sonny-2-2900.swf`, repo root) and the Steam rebundle (`SONNY2.swf`, repo root). The Steam release repackaged the original and
modified the source layout; the raw dumps in `conversion_scripts/data_json/` come from the Steam structure, while the readable decompiled code in `source_files/action_script_curated/` is the
web release's inline AS3 (the full ffdec export lives at `source_files/action_script/`). Both matter: the data pipeline consumes Steam-shaped dumps, but the web AS3 is the ground truth for semantics.

## Confirmed identical

- **Game content counts match**: 480 moves, 471 buffs, 450 items, 75 units, ~100 battles in both. (Checked earlier in the revival, 2026-07-18.)
- **Battle definitions use the same unit id numbers** in both (verified via battle 200/202 rosters matching zone content in both id spaces).

## Structural differences

- **Data externalization.** The web SWF builds everything in imperative AS3 (`createNewUnitKrin(...)` / `createNewBattle()` / `addNewMove(...)` call sequences, frame42). The Steam rebundle carries the
  same content as structured data objects (the `UNITS`/battle AVM object dumps in `data_json/swf_*.json`).

## Bugs introduced by the Steam restructuring (fixed in the conversion pipeline)

- **Two units carry wrong ids in the Steam data** (fixed in `convert_units.py` `ID_CORRECTIONS`, 2026-07-18). The web SWF assigns unit ids from a sequential counter that is manually jumped twice
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
