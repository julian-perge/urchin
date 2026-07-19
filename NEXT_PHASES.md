# Next phases

**Every phase of the revival roadmap is complete** (2026-07-18). The full game loop runs and is
tested end-to-end: zone orb -> battle selection from quest progression -> roster assembly (player
with talents/gear, companions, enemies) -> playable battle scene with paper-doll visuals, input,
and audio -> victory rewards, leveling, drops, achievements, autosave -> back to the zone with
progress advanced. 71 GUT tests / 436 asserts cover it headless.

Delivered, in order: data pipeline fixes, zones + shops, damage/heal/focus formulas, the buff
system, the save system, skill/talent trees, the battle turn-loop orchestrator + enemy AI,
post-battle rewards, leveling/respec, zone battle content wiring + the companion party system,
item equip validation, the store UI repair, the audio manager, achievements, and the character
paper doll + battle scene. See `KNOWN_GAPS.md` for the handful of deliberate approximations and
`SWF_DIFFERENCES.md` for web-vs-Steam data findings.

## Polish backlog (nothing blocks anything - pick by taste)

The UI/scene layer was rebuilt 2026-07-18: main menu (save slots + new-game flow), 7 per-zone
hub scenes with SWF-exact orb positions (`scenes/zones/`), the zone-hub shell (`game.tscn` +
`game.gd`), the hotbar (menu buttons / world-map / zone progress), the zone map with SWF-exact
button positions, and the asset tree reorganized (`assets/backgrounds/{hub,battle,sky}`,
`assets/ui/{hotbar,battle,store,zone_map}`). Base resolution is the original 800x600 stage
(canvas_items stretch), so every SWF-extracted coordinate drops in 1:1.

- **Timeline-accurate animations.** The SWF's MODEL1 clip holds the complete original keyframe
  set (371 frames; labels `stand/run/Attack_Upper/Attack_Stab/Attack/attack2/runback/cast/stun/
  stun2/outofstun/hit/dead`). The rest pose was extracted from it (`ffdec -swf2xml`, matrices in
  `character_visual.gd`); extracting the full timeline the same way would replace the code-driven
  animations with the originals. MODEL4 (female) rest pose too.
- **Battle screen niceties**: the 120-second decision countdown (`BattleRunner.BATTLE_TIME_LIMIT`
  is exposed, nothing displays it), melee run-to-target motion, buff icons over units, a combat
  log panel, target highlighting, the original hotbar-style battle UI art
  (`assets/ui/battle/*.png` is extracted and waiting).
- **Victory screen click-to-keep** - drops are currently auto-kept; the original let you choose
  (`VICTORY[1]` "CLICK on the items that you wish to keep!").
- **Menu screens built 2026-07-18** from the original menu clip (DefineSprite 3142, stage
  origin 400.5/222.4; frame 1 = inventory, 16 = store, 25 = abilities, 45 = achievements):
  `scenes/ui/menu/inventory_window.tscn`, `abilities_window.tscn`, `achievements_window.tscn`,
  plus the rebuilt `scenes/ui/store/store_window.tscn` - all wired to hotbar buttons with the
  green active-icon glow. Chrome art extracted at 2x into `assets/ui/menu/`. Still missing on
  these screens: party portrait faces (sprite 2979's frames - frames are placeholders), ability
  orb icons (original per-move icon art - orbs show initials + element colors), the abilities
  tutorial callout box, and drag-to-socket placement (click-to-place stands in).
- **Screens not yet built** (hotbar buttons dimmed): options, respec button flow (logic in
  `Leveling.respec`), team-select (`PlayerSave.party_deployed` is ready), character appearance
  customization (SkinSet/HairSet/GSet persistence). References in `assets/references/`.
- **Item icons**: 311 of 449 items carry `slot_image` art (`assets/item_slot_icons/`); the
  remaining 138 could be exported from the original 856-frame item icon sheet (sprite 2064,
  `gotoAndStop(ITEMNAME)` keyed by name).
- **Zone hub art for zones 6/7**: no dedicated hub art exists in the extracted assets - the
  scenes reuse the wide battle backdrops (`battle/CHURCH.png`, `battle/STREETS.png`),
  aspect-cropped. Zone 7's training orb position is also borrowed from zone 6 (the original
  Steam-only zone frame has no training orb placement).
- **Cutscenes**: `ZoneProgression.after_battle_won()` reports the cutscene id (`CS_CUT2` etc.);
  nothing plays them. The original cutscene frames would need art extraction.
- **Shatter Bolt**: the one `"Attack"`-category move - the original never handled it either.

## Testing: GUT

GUT 9.6.1 is vendored at `addons/gut/`, tests in `test/unit/` + `test/integration/`, config in
`.gutconfig.json`. Run headless (exits nonzero on failure):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Compile-check a script without GUT:
`Godot --headless --check-only -s <script.gd> --path .` (run `--headless --import` once after
adding new `class_name` scripts, or the class cache is stale and reports false "not declared"
errors).
