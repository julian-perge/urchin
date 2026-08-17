# Project Context — urchin (updated 2026-08-17T12:09:01)

_Generated locally by Recall — TextRank (vendored, numpy-accelerated)._

## 🎯 Goal
recall 'where we last left off on this project for converting the flash game to godot'

## 🧭 Summary
- `urchin_dev.DATA_JSON` -> `dev/data_json/`, not on disk.** Restore from ccf7375^ per above.
- **Cheap path if you just want it running:** `git show ccf7375^:python_conversion_scripts/data_json/swf_items.json > dev/data_json/swf_items.json` (6 files).
- **Restored** all 6 dumps to `dev/data_json/` (2.8MB): `swf_battles`, `swf_buffs`, `swf_items`, `swf_krin_units`, `swf_move_abilities`, `swf_units`.
- Converted 449 items to JSON
- Converted 479 moves to JSON
- Converted 75 units to JSON
- I updated .gitignore to allow data_json, but there should be a new script that will regenerate all the data_json files, and the convert/ scripts should error out if the data_json/ file does not exist
- Item `looks` - the dump captures it as `Undefined` for every item; `convert_items.py` already sources it from a separate script (`dev/urchin_dev/swf/extract/item_looks.py`), not from `data_json` at all, so it was out of scope here.

## ⏭️ Next steps / open threads
- **Missile projectile art** — plan written, zero code. `.claude/plan_missile_projectile_art.md`, 5 tasks: extract the 15 bolt clips plus `KrinTrail` and the `BOOM_*` impact clips into `assets/vfx/`, add `Ability.visual_effect_color`, build `impact_effect.tscn`, upgrade `Projectile` to an `AnimatedSprite2D`, and wire the three existing impact hook points.
- **Item click-n-drag** — plan written, zero code. `.claude/plan_item_drag_and_drop.md`, 5 tasks: add `GameData.swap_inventory_slots` and `unequip_to_slot`, add `_get_drag_data` to `ItemSlot`, add the drop targets, and give the sell button a hover price tooltip.
- Want me to start one, or run `/recall:save` first so next session picks up cleanly?
- The two unstarted plans (`plan_missile_projectile_art.md`, `plan_item_drag_and_drop.md`) did not land in "Next steps" - only the uncommitted `.recall/` did.
- Want me to hand-edit `context.md` to add them?
- yes, add both plans to next steps.
- I cant remember if the `convert/` scripts should have been removed since `data_json/` doesnt exist anymore (removed in commit ccf7375b5c6c94c15de5f0528bd29780099cd926`).
- Uncommitted changes to wrap up: recall/.capture.json, .recall/history.md

## 📂 Files touched
- /Users/sweetjp/Documents/godot/urchin/NEXT_PHASES.md
- /Users/sweetjp/Documents/godot/urchin/.recall/context.md
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/__init__.py
- /Users/sweetjp/Documents/godot/urchin/scripts/autoload/move_manager.gd
- /Users/sweetjp/Documents/godot/urchin/README.md
- /Users/sweetjp/Documents/godot/urchin/SWF_DIFFERENCES.md
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/swf/models.py
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/convert/units.py
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/convert/moves.py
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/convert/buffs.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/lang.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/expr_eval.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/parse_moves.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/parse_buffs.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/parse_units.py
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/convert/battles.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/parse_battles.py
- /Users/sweetjp/Documents/godot/urchin/dev/urchin_dev/convert/items.py
- /private/tmp/claude-501/-Users-sweetjp-Documents-godot-urchin/fda25f18-28d3-4ba7-bb76-86e3e63897f3/scratchpad/as_drift/parse_items.py

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
- git log --oneline -12; echo "=== STATUS ==="; git status --short
- git show --stat ccf7375b5c6c94c15de5f0528bd29780099cd926 -- . ':(exclude)assets' | head -60
- git status --short | rg -v "^R dev/source_files|^A dev/source_files|^AM dev/source_files" | head -60; echo "=== DEV TREE ==="; fd -t d -d 3 . dev 2>/dev/null | 
- fd -t f . dev/urchin_dev | head -40; echo "=== old conversion_scripts on disk? ==="; ls conversion_scripts 2>/dev/null || echo "GONE"; echo "=== python_conversi
- …and 147 more

## ⏱ Where we left off
Deleted and committed: `a59730e`.

## 🌿 Git ground-truth
```
Uncommitted changes (git diff --stat):
.recall/.capture.json |  2 +-
 .recall/history.md    | 61 +++++++++++++++++++++++++++++++++++++++++++++++++++
 2 files changed, 62 insertions(+), 1 deletion(-)

Recent commits:
a59730e chore: remove unused swf_krin_units.json dump
539401a refactor: move conversion pipeline under dev/, restore data_json
0323a5b additional exclusions
516781e lint rules, minor typing, imports
ec004b7 lockfile update, linefeed
9d9e434 docs: Adding basic makefile, updating .editorconfig, recall
eb8d04f linting
ccf7375 more fixes
```
