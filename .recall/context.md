# Project Context — urchin (updated 2026-08-17T08:26:37)

_Generated locally by Recall — TextRank (vendored, numpy-accelerated)._

## 🎯 Goal
recall 'where we last left off on this project for converting the flash game to godot'

## 🧭 Summary
- recall 'where we last left off on this project for converting the flash game to godot'

## ⏭️ Next steps / open threads
- Uncommitted changes to wrap up: .recall/

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
