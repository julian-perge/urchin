# Urchin

Fan remake of an ArmorGames game.

## Python conversion scripts

`python_conversion_scripts/` holds the AS3-decompile-to-JSON converters (`convert_items.py`,
`convert_units.py`, `convert_moves.py`, `convert_buffs.py`, `convert_battles.py`) and the raw/converted
data they read and produce. There's no `pyproject.toml` here on purpose - these scripts have no
third-party dependencies, so there's nothing to lock. Run them directly with `uv`:

```sh
cd python_conversion_scripts
uv run python3 convert_items.py
```

`uv run python3 <file>` works fine standalone with no project manifest present - it just runs the
script with an ambient Python, no venv/lockfile needed.

## Tests

GUT tests live under `test/` (`unit/` for pure logic, `integration/` for full-stack runs against
the real converted data). Run headless:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Exits nonzero on failure. Also runnable from the GUT panel inside the Godot editor.

## Project layout

Standard Godot type-based split (`scenes/`, `scripts/`, `resources/`, `assets/`) - this section
describes what's actually there, not an aspirational target. See `KNOWN_GAPS.md` for defects in
what exists and `NEXT_PHASES.md` for what hasn't been built yet.

```text
res://
├── project.godot                  # Autoloads: StoreManager, UnitManagerAuto, ItemManagerAuto,
│                                  #   MoveManagerAuto, BuffManagerAuto, Inventory, ZoneManager, GameData
├── addons/gut/                    # GUT 9.6.1 test framework (vendored)
├── .gutconfig.json                # GUT config - test dirs, exit-on-finish
├── test/
│   ├── unit/                      # Pure-logic tests (talent tree rules, ...)
│   └── integration/               # Full-stack tests against real converted data (battle runner, ...)
├── scenes/
│   ├── main_menu.tscn             # Starting screen: save slots + new-game (name/class/difficulty)
│   ├── game.tscn                  # Zone-hub shell: hosts the current zone scene + hotbar/store/map
│   ├── zones/                     # One scene per zone (zone1_prison .. zone7_shotul) - hub art +
│   │                              #   the 3 orbs at positions extracted from the original SWF
│   ├── zone_map.tscn              # World map overlay (7 buttons at SWF-extracted positions)
│   ├── battle_scene.tscn          # Playable battle screen (dolls, input, audio, victory flow)
│   ├── character_visual.tscn      # Paper-doll character (plain Node2D parts, MODEL1 rest pose)
│   ├── orb.tscn                   # Base interactive zone orb visual
│   ├── button.gdshader, orb.gdshader
│   └── ui/
│       ├── hotbar.tscn            # Bottom bar: menu buttons / world-map toggle / zone progress
│       ├── inventory.tscn, item_slot.tscn, orb_tooltip.tscn
│       └── store/store_window.tscn
├── scripts/
│   ├── autoload/                  # One script per project.godot autoload entry
│   │   ├── game_data.gd           # GameData: save/load, gold, inventory economy, equip glue
│   │   ├── item_manager.gd, unit_manager.gd, move_manager.gd, buff_manager.gd
│   │   ├── store_manager.gd, zone_manager.gd
│   │   ├── audio_manager.gd       # AudioManagerAuto: SFX pool + crossfading music (AS3 addSound port)
│   ├── battle/                    # Battle system - not autoloaded, instanced per-scene
│   │   ├── ability.gd, buff.gd, battle_fight.gd   # Data classes (Resource), loaded from JSON
│   │   ├── combat_unit.gd, battle_manager.gd      # Runtime combat logic (stats, buffs, formulas)
│   │   ├── battle_runner.gd, battle_ai.gd         # Turn-loop orchestrator + enemy AI (headless)
│   │   ├── battle_rewards.gd                      # Post-battle drops/money/XP (player + companions)
│   │   ├── battle_setup.gd                        # Battle id -> runner-ready roster (player/party/enemies)
│   │   └── battle_scene.gd                        # The playable battle screen (scenes/battle_scene.tscn)
│   ├── entities/                  # Static game-data Resource classes + progression logic
│   │   ├── character.gd, game_item.gd, player_save.gd
│   │   ├── talent_tree.gd         # Skill/talent trees for the 3 classes + point-spending rules
│   │   ├── leveling.gd            # XP bar, stat-point grants/allocation, player stat model, respec
│   │   ├── party.gd               # Story companions: roster/joins/deployment, stats, XP
│   │   ├── equipment.gd           # Equip validation (slot/level/unit rules) + stat transfer
│   │   ├── achievements.gd        # Grant table, battle counters, global persistence
│   │   ├── character_visual.gd    # Paper-doll: MODEL1 rest pose, dressChar port, animation states
│   │   └── enemy.gd, player.gd    # still empty stubs
│   ├── zones/                     # Zone navigation (map panel, background sync) + zone_progression.gd
│   │                              #   (story/training battle selection, quest progress, zone unlocks)
│   ├── ui/                        # UI behavior (orbs, hotbar, store slots, buttons)
│   ├── editor/                    # @tool EditorScripts - regenerate resources/{items,units,battles}/*.tres
│   │                              #   from python_conversion_scripts/converted_json/*.json. Run from
│   │                              #   the Godot script editor (File > Run). Tests live in test/, not here.
│   └── inventory.gd                # Inventory autoload (27-slot UI grid, separate from PlayerSave.item_array)
├── resources/                      # Generated/authored game DATA + the art tied to it
│   ├── items/ (449 .tres), units/ (75 .tres), battles/ (99 .tres)   # Generated by scripts/editor/*.gd
│   ├── sprites/ (1578 files)       # Paper-doll body-part sprites, {M|F}_{PART}_{key}.png
│   ├── store/, svg/, toolbar/, zone_orbs/
│   └── example_save_file*.json     # Real captured AS3 save dumps - reference only, not loaded by anything
├── assets/                          # Hand/AI-sourced art not tied to a generated Resource
│   ├── audio/ (147 files)           # Extracted from the original SWF, named to match AS3 sound-cue keys
│   ├── backgrounds/
│   │   ├── hub/                     # Zone-hub art (764x414 stage space; upscale_variants/ = originals)
│   │   ├── battle/                  # Wide battle backdrops, keyed by BattleFight.zone_background
│   │   └── sky/                     # Battle sky layers (extracted, not yet rendered)
│   ├── fonts/, item_slot_icons/, references/  # (references/ = original-game screenshots)
│   └── ui/
│       ├── hotbar/, battle/, store/, zone_map/  # Grouped by which screen uses them
├── python_conversion_scripts/        # AS3-decompile -> JSON pipeline (Python, run via `uv`, see above)
│   ├── convert_items.py, convert_units.py, convert_moves.py, convert_buffs.py, convert_battles.py
│   ├── swf_models.py                 # msgspec models/loaders for the AMF-style runtime dumps
│   ├── swf_extraction/               # swf2xml/ActionScript analysis + asset extraction tooling
│   ├── data_json/                    # Raw JPEXS AVM2 dumps (converter input)
│   └── converted_json/               # Clean converter output (consumed by scripts/editor/*.gd)
├── source_files/                     # Decompiled SWF source material (see source_files/README.md)
│   ├── action_script/                # Full ffdec script export - game-logic ground truth
│   ├── action_script_curated/        # Hand-picked, commented excerpts (former action_script_files/)
│   └── swf_xml/                      # ffdec -swf2xml dumps of both SWFs - geometry ground truth
├── KNOWN_GAPS.md                     # Specific defects/scoped-out edges in work already done
├── NEXT_PHASES.md                    # Priority-ordered roadmap of what's left
└── SWF_DIFFERENCES.md                # Divergences found between the web SWF and the Steam rebundle
```
