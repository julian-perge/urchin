# Project Context — urchin (updated 2026-08-17T08:26:37)

_Generated locally by Recall — TextRank (vendored, numpy-accelerated)._

## 🎯 Goal
recall 'where we last left off on this project for converting the flash game to godot'

## 🧭 Summary
- recall 'where we last left off on this project for converting the flash game to godot'

## ⏭️ Next steps / open threads
- **Finish the `dev/urchin_dev/` refactor** (in progress, unstaged). `conversion_scripts/` and `python_conversion_scripts/` are both gone from disk; `source_files/` and `converted_json/` now live under `dev/`. Two breakages were found and fixed on 2026-08-17; one is still open:
  - FIXED — stale data paths. Nine GDScript files plus `README.md` still pointed at `res://conversion_scripts/converted_json/`, now `res://dev/converted_json/`. GUT suite is green again: 17 scripts, 579 asserts.
  - FIXED — two dead `[project.scripts]` entry points. `convert_moves.py` and `convert_units.py` were renamed to `moves.py` and `units.py` to match the `urchin_dev.convert.moves` / `.units` targets in `pyproject.toml`; `battles.py`, `buffs.py`, and `items.py` had been renamed earlier but these two were missed. All 14 entry points import cleanly.
  - DONE — dumps restored (`git show ccf7375^:python_conversion_scripts/data_json/<file>`), all 6 files back in `dev/data_json/` (now git-tracked, `.gitignore` narrowed by the user). `require_data_json()` added to `dev/urchin_dev/__init__.py`; all five `convert/*.py` call it and fail with the restore command if a dump is missing.
  - INVESTIGATED (2026-08-17) — whether `data_json/` could instead be regenerated from the web SWF's ActionScript. Built a throwaway parser (not committed) that walks `dev/source_files/action_script/frame_42/`'s `addNewMove`/`addNewBuffKrin`/`createNewUnitKrin`/`createNewBattle`/`createNewItemKrin` blocks directly and compared the result field-by-field against `dev/converted_json/*.json`. **Zero content drift** across all five tables — 479/479 moves, 470/470 buffs, 75/75 units, 449/449 items match exactly (including item price/stat formulas requiring a `getStat`/`respecValue` reimplementation), all 99 battles match by creation-order position (battle `id` numbering itself follows a non-obvious rule - `battleCreationID = N;` jump lines retroactively relabel the *previous* battle, not the next one). Two things that looked like drift turned out to be genuine bugs in the original web build, faithfully preserved on both sides: buff id 416 references a nonexistent `AUX` lang table, and `createNewItemKrin`'s stat-list `for..in` loops enumerate in inconsistent order (5-slot list descending, 8-slot list ascending - a legacy AS2 quirk). Full writeup in `SWF_DIFFERENCES.md`'s "Confirmed identical" section. Given this, decided NOT to build a real AS-reparsing regenerator — the restored dumps are correct and sufficient, and the user chose to just document the finding rather than build one.
- **Missile projectile art** — plan written, zero code. `.claude/plan_missile_projectile_art.md`, 5 tasks: extract the 15 bolt clips plus `KrinTrail` and the `BOOM_*` impact clips into `assets/vfx/`, add `Ability.visual_effect_color`, build `impact_effect.tscn`, upgrade `Projectile` to an `AnimatedSprite2D`, and wire the three existing impact hook points.
- **Item click-n-drag** — plan written, zero code. `.claude/plan_item_drag_and_drop.md`, 5 tasks: add `GameData.swap_inventory_slots` and `unequip_to_slot`, add `_get_drag_data` to `ItemSlot`, add the drop targets, and give the sell button a hover price tooltip.
- Backlog from `NEXT_PHASES.md`: the MODEL4 (female) animation timeline, the enum conversion audit (`PlayerClass`, aggression stance, `MovePool`, and `Team` are the flagged clear wins), battle-screen niceties (120-second countdown display, buff icons, combat log, target highlighting), and the unbuilt screens (options, respec flow, team-select, appearance customization).

## 📂 Files touched
- /Users/sweetjp/Documents/godot/urchin/NEXT_PHASES.md

## 🔧 Commands run
- ls -la /Users/sweetjp/Documents/godot/urchin/.recall/ 2>/dev/null; echo "---"; wc -l /Users/sweetjp/Documents/godot/urchin/.recall/history.md 2>/dev/null
- git log --oneline -25 && echo "=== FILES ===" && ls -la
- find docs -type f | head -50 && echo "=== last commit detail ===" && git log -3 --stat --format='%h %s (%ad)' --date=short | head -60
- rg -n "^#|^\- \[ \]|^\- \[x\]|Status:|COMPLETE|IN PROGRESS|TODO" NEXT_PHASES.md | head -120
- ls -la .claude/ && echo "===" && ls -la .claude/*/ 2>/dev/null | head -40
- head -30 .claude/plan_item_drag_and_drop.md; echo "======="; head -30 .claude/plan_missile_projectile_art.md
- rg -n "^## |^### |\[x\]|\[ \]|DONE|COMPLETE" .claude/plan_item_drag_and_drop.md .claude/plan_missile_projectile_art.md | head -60
- git log -1 --format='%ad' --date=iso; echo "--- conversion_scripts ---"; ls conversion_scripts; echo "--- pyproject scripts ---"; rg -n -A20 "\[project.scripts\
- rg -l "_get_drag_data|impact_effect|ImpactEffect|visual_effect_color|swap_inventory_slots" scripts/ scenes/ 2>/dev/null; echo "--- vfx assets ---"; ls assets/vf
- rg -n "visual_effect_color|_get_drag_data|swap_inventory_slots" scripts/battle/ability.gd
- rg -n "impact_effect|ImpactEffect" scripts/battle/ability.gd

## ⏱ Where we left off
Where project stand (last commit 2026-07-24, tree clean, no `.recall` context saved yet): ## Done Whole revival roadmap complete. Full loop runs: zone orb, battle select, roster, playable battle, victory rewards, leveling, drops, achievements, autosave. 83 GUT tests / 553 asserts headless. Recent finished phases: - **Ability menu redesign** (2026-07-23) - icon art from `DefineSprite 2427`, `AbilityTooltip` + `AbilityTooltipBuilder`, prereq-colored connector lines, `ability_pool_row.tscn`. - **UI Container migration** (2026-07-23) - all of `scripts/ui/` plus `battle_scene.gd` moved to declarati…

## 🌿 Git ground-truth
```
Recent commits:
eb8d04f linting
ccf7375 more fixes
90c69e2 feat: uv run entry points for conversion_scripts
ff6a028 fix: exclude opaque black-disc chrome from ability icon extraction
1120956 chore: Add prek.toml for general linting
051b1f5 fix: ability menu tooltip z-order, black icons, and panel sizing
0071773 ability menu redesign
4f0f80d docs: mark the ability menu redesign phase complete
```
