# Decoded original algorithms

Ground-truth behavior decoded from the ActionScript in `source_files/action_script/`, kept here so reimplementation details never have to be re-derived. Converted values assume the original 30 fps
timeline.

## krinMelee - the melee run/strike/runback (frame_42/DoAction_4.as)

Implemented in `scripts/entities/character_visual.gd` (`play_melee`, `_animate_melee`).

Constants (frame 42 globals):

| Name | Value | Meaning |
|---|---|---|
| `krinBoltTime` | 60 | base step divisor: step = distance / 60 per frame |
| `krinBodyMove` | 10 | melee movement multiplier on that step |
| `krinMeleeAttackCD` | 15 | frames from strike start to impact (0.5 s) |
| `krinMeleeAttackEndCD` | 15 | frames from impact to the runback goto (total 1.0 s) |

Sequence:

1. **Dash out.** The doll's clip plays `run`; the body translates each frame by `spdXCoEFFER * (distance / 60) * 10` where `goRat` = fraction traveled and `spdXCoEFFER = min(1.5 - 1.45 * goRat, 1)`
   is an ease-out. The code only caps it at 1 (`frame_42/DoAction_4.as:102-111`). It has no lower clamp, which is harmless because `goRat` stays below 1 during the dash and keeps the value above
   0.05. `distance` is measured to the target's center, but the dash stops at the end point, the target's center minus both half-widths (`frame_42/DoAction_4.as:46-55`), so arrival time
   depends on the distance minus both half-widths. Simulating `frame_42/DoAction_4.as:99-131` gives 13 frames (0.43 s) with zero half-widths at any distance, 11 frames at 300 px with 60 px
   of half-widths, 9 at 300 px with 100 px, and 4 at 150 px with 100 px. The `run` label (46-77: wind-up 46-53, leap 54-62, glide hold 63-77, `stop()` on 77) is INTERRUPTED by arrival,
   mid-leap after a 9 to 13 frame dash and still in the wind-up after a 4 frame one, so it never finishes on normal hops.
2. **Strike.** On arrival (`goRat >= 1`) the clip does `gotoAndPlay(attackType)` - one of `Attack` (138-152), `Attack_Upper` (78-107), `Attack_Stab` (108-137). The timeline then flows on its own:
   `Attack` runs through `attack2` (153-167, the downswing/follow-through - it is NOT a selectable variant, no move references it) and both 30-frame labels end in a scripted `gotoAndStop("runback")`.
   Impact (hit effect + damage application, `BAMBAMBAM`) fires exactly 15 frames (0.5 s) after strike start; `sfx_swing` cues sit at clip frames 88/118/146. The impact flag is raised on a
   miss too (`frame_42/DoAction_4.as:80`); only the BOOM clip waits on `strikeSuccess`. The conductor (`frame_217/PlaceObject2_3389_480` enterFrame) resets `AttackEndCounter` to 0 when it sees
   the flag and dispatches the next action once the counter has run past `AttackEndCounterLimit = 25` (lines 112-138, with the limit set at line 7 of the same clip's `onClipEvent(load)`). That
   is 26 frames after impact, so the next action starts in the middle of the runback.
3. **Runback.** 15 frames after impact (1.0 s after strike start - exactly the clip's own runback boundary for every label) the code forces `gotoAndPlay("runback")` (168-188, ends in
   `gotoAndStop("stand")`) and reverses movement with an eased return: `spdXCoEFFER = min(1.45 * goRat, 1)` - fast leave, exponential settle home; position snaps to home once `relX` falls to
   0.000001 or less. The settle has no fixed length (this note used to say ~18 frames): the same four cases as the dash simulation, with the zero half-width case taken at 300 px, put the
   doll within 1 px of home after 4 to 22 frames of runback, and snap it home after 15 to 72.

Attack label selection: each move's `addNewMove` param 12 (`Ability.animation_label`). Shock moves play "cast" instead (param 12 is unused for them); `play_strike()` exists for in-place strikes but is
not used by Shock.

## krinBoltMake - the missile projectile (frame_42/DoAction_4.as, ~line 137)

Implemented in `scripts/battle/projectile.gd` (`Projectile`), fired from `scripts/battle/battle_scene.gd` (`_fire_projectile`).

Constants (frame 42 globals):

| Name | Value | Meaning |
|---|---|---|
| `krinBoltTime` | 60 | step divisor: step = distance / 60, fixed at spawn (never recomputed against the bolt's live position) |
| `krinBoltSpeed` | 1 | initial `SpeedConst` |
| `krinBoltIncrease` | 1.15 | `SpeedConst *= 1.15` every original frame - the bolt ACCELERATES exponentially, it does not move at constant speed |

Sequence:

1. **Spawn.** The bolt clip attaches at `shooter.x, shooter.y - 15` with `_alpha = 0`, fading in `+10/frame` (opaque after 10 frames). `boltx`/`bolty` (the spawn position) are cached once and used as the
   fixed reference for the per-frame step - `xLPiece = (target.x - boltx) / 60` is NOT recomputed from the bolt's current position each frame.
2. **Flight.** Each frame: `_x += xLPiece * SpeedConst; _y += yLPiece * SpeedConst; SpeedConst *= 1.15`. A separate `"KrinTrail"` clip spawns on the first frame, tinted via `Color.setRGB(tColorKrin)` (the
   same `colortobe` value used for the caster's cast glow), rotated to face the shooter->target line, and stretched (`inner._xscale += 8.3 * step_magnitude`) every frame while the bolt flies - the
   trail gets longer/faster as the bolt accelerates.
3. **Arrival.** Tested as `(target.x - bolt.x) * checker <= 0` (checker = +-1 for flight direction) - a COORDINATE-CROSSING test, not a distance threshold or frame count. On a hit, the BOOM clip (param 13)
   attaches at the target and the bolt clip removes itself; `BAMBAMBAM` (the damage/impact-apply flag) is set true either way. On a miss the bolt keeps flying past the target and self-destructs once it
   clears the battlescreen bounds (`|x| > 500`), rather than stopping at the target. Because the missed bolt stays alive past the crossing, the crossing test stays true and `BAMBAMBAM` is raised
   again on every frame until the bolt leaves the screen (`frame_42/DoAction_4.as:188-205`). Each raise restarts the conductor's 26-frame wait (conductor lines 12-15), so after a miss the next
   action starts 26 frames after the bolt is gone.
4. **Multi-target.** `ability_two[20]` (`is_multi_target`) fires one independent bolt per living enemy on the opposing side, each targeting its own unit. This is dead content: no move sets
   `[20]`, which defaults to 0 (`frame_42/DoAction_6.as:48`), and nothing assigns `hackMove[20]`.

The Godot port fires a single bolt per `_play_move_event` call. Multi-target itself is handled: `BattleRunner._execute_move_action` runs the move on every living enemy when
`Ability.hits_all_enemies` is set and logs one move event per enemy, so only the presentation differs: read from the code (not run), the port would play one cast and one bolt per enemy where
the original casts once and fires the bolts together. With no move setting `[20]`, neither path ever runs. **DONE (2026-08-19)**, see `.superpowers/sdd/2026-08-18-missile-projectile-art/`: distinct clip art per `projectileModel` name (e.g. `Krin.Firebolt`) is extracted and rendered untinted; `KrinTrail`'s real 33-frame fade-in/fade-out pulse (not a generic tinted circle+line) plays alongside it, tinted by the move's real `colortobe` value; and a miss now flies the bolt fully past the target off-screen instead of always resolving as a hit on arrival, matching `strikeSuccess`'s hit/miss branch (`Projectile.did_hit` gates whether `reached_target` frees the bolt immediately or lets it keep flying). Both the bolt and the trail come from a generated scene of their own under `scenes/battle/vfx/`, which `Projectile` instantiates by clip name - each one already carries that clip's frames and the registration point the source SWF drew it around, so nothing here positions or scales art at play time (**DONE (2026-08-20)**, see `.superpowers/sdd/2026-08-19-vfx-registration-scenes/`).

## "cast" label dispatch and timing (frame_217/PlaceObject2_3389_480 enterFrame, ~line 400-469)

Implemented in `scripts/entities/character_visual.gd` (real MODEL1 label playback, frames 189-219) and `scripts/battle/battle_scene.gd` (`_play_move_event`).

- **Missile:** `colortobe = param 11` is set on `inner` immediately BEFORE `inner.gotoAndPlay("cast")` - the cast-glow tint is active for the whole animation from frame 1 of the label, not something
  faded in/out mid-clip by a script trigger. `sfx_cast` plays at cast start; the actual impact/damage timing is driven by the projectile's own arrival (see krinBoltMake above), NOT by the cast clip's
  elapsed time.
- **Shock:** same `colortobe`/`gotoAndPlay("cast")` call, but the move's own sound, the BOOM clip attach, the camera zoom/shake, and `BAMBAMBAM = true` (impact) ALL fire in the same tick as the
  `gotoAndPlay("cast")` call - the doll's cast animation is purely cosmetic follow-through for Shock; the hit lands instantly, no waiting on the clip.
- **How cast ends:** MODEL1 frame 219's own frame script is `gotoAndStop("stand"); play()` - cast is a one-shot that always runs to completion (189-219, ~1.03 s at 30 fps) and falls straight into the
  idle stand loop on its own; nothing in the engine interrupts it early or re-triggers it mid-flight.

## Stun family labels (frame_42/DoAction_10.as `applyChangesKrin`/`applyBuffKrin`, ~line 135-481)

Implemented in `scripts/entities/character_visual.gd` (`enter_stun`/`exit_stun`/`_animate_stun`) and `scripts/battle/battle_scene.gd` (`_update_stun_visual`).

- **`STUN` is a running total**, not a flag: `applyBuffKrin` does `ukcb2.STUN += iftbc * bffker[17]` where `bffker[17]` is the buff's stun contribution and `iftbc` is +1 on apply / -1 on the buff's own
  expiry (via `buffTicker`'s `autoDebuffer`, when a buff's `CD` hits 0). Multiple stacked stun buffs sum their contributions; the doll only fully un-stuns once every contributing buff has expired.
- **Trigger (in `applyChangesKrin`):** `applyChangesKrin` runs after every successful hit on the target (conductor line 103), at the end of each unit's own `buffTicker`
  (`frame_42/DoAction_10.as:135`) and at battle start for units with passive buffs (`frame_217/DoAction_4.as:13`), so the stun animation starts at the impact that applies the stun. This note
  used to say the trigger fires once per unit's own per-turn tick, which reads `buffTicker` alone. Each call compares the new `STUN` against `STUNP` (its value at the previous call, reset to 0
  alongside `STUN` at battle-unit init):
  ```as
  if(ukcb.STUN != ukcb.STUNP) {
     if(ukcb.STUN - ukcb.STUNP > 0) { inner.gotoAndPlay("stun"); }
     else { inner.gotoAndPlay("outofstun"); }
  }
  ukcb.STUNP = ukcb.STUN;
  ```
  Any INCREASE (including stacking further while already stunned) replays `"stun"` from its start; any DECREASE (even a partial one that leaves the unit still stunned by a shorter-remaining buff) plays
  `"outofstun"` - the check is purely value-based, never `STUN == 0`.
- **`"stun2"` is never explicitly triggered by this code.** MODEL1's own frame scripts flow straight from the end of `stun` (239, no script) into `stun2` (240) automatically, then frame 279 does
  `gotoAndStop("stun2"); play()` - an infinite self-loop baked into the clip, entered once and self-perpetuating with zero code involvement. It is the "still stunned, holding" idle loop.
- **One extra code-driven trigger:** `changeForm()` (model/skin swap mid-battle, e.g. transformation buffs) ends with `if (STUN) inner.gotoAndPlay("stun2")` - after a form change resets the doll's
  clip, a still-stunned unit is snapped straight back into the `stun2` loop instead of showing an idle pose. Not ported (form-changing buffs aren't implemented yet).
- **`outofstun` ends** via MODEL1 frame 295's own `gotoAndStop("stand"); play()` - a one-shot that always falls back to idle, same pattern as `cast`.
- No numeric timing constants gate any of this (unlike `krinBoltTime`/`krinMeleeAttackCD`) - it's a value-comparison state machine that runs on every `applyChangesKrin` call; the Godot port
  evaluates it in `_refresh_bars` (called after every event and at half-turn boundaries). This note used to call that finer-grained than the original, from the same misreading as the trigger
  above: the original also evaluates it at every successful hit, so both start the stun animation at the impact. The comparison only fires when the value has changed, so extra evaluations in
  between change nothing.

## Menu piercing/defense bars (DefineSprite_3142/frame_1)

Implemented in `scripts/ui/menu/menu_theme.gd` (`bar_fill_fraction`). Display value = allocation + ceil(100 + 15 * level); fill fraction = the crit-curve quartic `0.016666667 x^4 - 0.25 x^3 + 1.233333
x^2 - 1.9 x + 0.9` of `value / (100 + 15 * level) + 1`, clamped to the track (base allocation = 30%).

## Item looks and icons

- `looks` art keys: `gghhjjuu.looks = "X"` assignments in frame_42/DoAction_16.as after each `createNewItemKrin` (wearable default "NINJA"; id counter jumps at 99/299/499).
- Slot icons: the icon clip (DefineSprite 2064) has one labeled frame per item name; shape 1913 is a clip mask: its first placement, on frame 16 at depth 2, carries clipDepth 15, so stripping it unclips every icon under it (item 69 went from 63x63 to 101x140, see CLAUDE.md). It is placed once more later in the clip at depth 1 without a clip. `gotoAndStop(ITEMNAME[id])`.

## Companion aggression stances (agModeAr)

Implemented in `scripts/entities/party.gd` (`AGGRESSION_PRESETS`). Columns 0-4 = Phalanx/Defensive/Tactical/Aggressive/Relentless; rows = [Aggression, LifeBoundary1, LifeBoundary2, FocusAggression,
FocusRegenLimit]: `[0,30,50,70,90] / [95,90,75,40,2] / [0,65,35,15,1] / [0,30,70,15,100] / [30,30,30,5,5]` (read column-wise). Default stance 2 (Tactical).

The stance lasts one battle. The original spawns every companion in Tactical at the start of every battle (`frame_42/DoAction_14.as:208-213`), the stance button writes only the
live battle unit (`DefineButton2_3289` on(press), lines 9-14), and the stance row highlights that unit's `agMode` through `setAG` (lines 12-14 of both copies in `DefineSprite_3312`),
which runs when the row loads and again at each of the player's half-turns (`frame_217/PlaceObject2_3389_480` enterFrame, lines 725-726). The saved `Krin.agMode` (seeded to 2 at
`frame_42/DoAction_17.as:42`, saved through `frame_42/DoAction_20.as:297`) is never read. The port does the same: `Party.build_companion_unit` applies Tactical, the stance row starts
on Tactical, and `PlayerSave.ag_mode` stays in the save unread. The port used to save the pick there and build companions with it.

## New Game and Load Game (root frames 56 to 93, `Krin.dataMode`)

Ported: `main_menu.gd` opens on New Game and Load Game, asks for the name before the slot list, lets New Game use any slot with the hover warning, takes the name as typed, doesn't
save when the game starts, and sends every Back to its first screen. In the game the player is "Sonny" whatever the typed name is.

- `subMenu`, root frame 56, captions its buttons with `MENU[21]` "New Game", `MENU[22]` "Load Game" and `MENU[85]` "PvP Arena" (`frame_56/DoAction.as:1-3`). New Game (`DefineButton2_2707`
  on(release), lines 2-3) goes to `nameMenu` and sets `Krin.dataMode` to "save". Load Game (`DefineButton2_2706` on(release), lines 2-3) goes to `dataMenu` and sets it to "load". The port
  leaves PvP Arena out with the rest of the arena.
- `nameMenu`, root frame 64, sets `krinNameUser` to `SYSTEM[34]` "< Enter Name Here >" (`frame_64/DoAction.as:1`) each time it opens, and the editable text 2712 shows it. 2712 has no
  HasMaxLength flag and no script sets `maxChars`, so the name has no length limit. OK! (`DefineButton2_2710` on(release), line 2) goes to `dataMenu` without reading the name, and the slot
  button copies it unchanged into `Krin.nameUser` (line 5 of each slot's on(release)). An untouched field starts a game named "< Enter Name Here >" and an emptied one a game named "".
  Outside the PvP arena the name is only saved and shown on the slot list (`frame_74/DoAction.as:4`), and an empty one still counts as a save there, since "" is not undefined.
- In the game itself the player is always "Sonny", whatever the save is named. The battle unit is named "Sonny" outright (`frame_201/DoAction.as:201`), and the menus read
  `Krin.NameSets[0]`, seeded to "Sonny" (`frame_42/DoAction_17.as:45`) and in neither save array, so no save changes it. That covers the victory screen's player row
  (`DefineSprite_3142/frame_9/PlaceObject3_3002_1197` onClipEvent(load), `prx = 0` on line 2 and `namerI` on line 15), the abilities screen (`DefineSprite_3142/frame_25/DoAction.as:7` and
  16), the inventory screen (`DefineSprite_3142/frame_1/DoAction.as:250` and 89) and the title of the player's portrait tooltip there (`DefineButton2_2895` on(rollOver), line 13). The
  port uses `Party.PLAYER_NAME` in all five places, so battle 100's "Sonny" line finds the player as its speaker instead of falling back to the narrator's slot 0.
- Back is edit text 2703 over hit button 2702, at depths 35 and 36 of every frame from `subMenu` to `optionsMenu` (93). It goes to `mainMenu` from all of them (`DefineButton2_2702`
  on(release), line 2). The port has no `mainMenu`, so each Back goes to its New Game and Load Game screen.
- `dataMenu`, root frame 74, shows each slot's saved `nameUser`, or "< Empty Slot >" for an empty one (`frame_74/DoAction.as:1-11`). `DefineButton2_2722`, 2721, 2720 and 2719 are slots 1
  to 4. With `dataMode` "save" a slot copies `krinNameUser` into `Krin.nameUser` and goes to `classMenu`, used or empty and without asking (on(release), lines 3-11), and hovering it shows
  `MENU[21]` over `MENU[25]`, the warning that a new game removes the old data (on(rollOver), lines 2-8). Otherwise a slot loads only when its `data.nameUser` is defined (on(release), lines
  12-34), so an empty slot does nothing.
- Only `krinHandleData` in save mode writes a slot (`frame_42/DoAction_20.as:58-126`). The calls a player can reach are the Save button (`DefineButton2_3183` on(release), lines 6-7) and the
  victory screen's Proceed with `autoSaver` on (`DefineButton2_3004` on(release), lines 4-7), whose frame sets `dataMode` to "save" first (`DefineSprite_3142/frame_9/DoAction.as:3`). The
  class buttons and Start (`DefineButton2_2735` to 2737, `DefineButton2_2770`) only change `Krin` in memory. `DefineButton2_3182` saves too, always to slot 1, but `Navigation` places it off
  the stage at x -86 to -44, and the KRINMENU frame holding the last caller, `DefineButton2_3121`, is only opened by 3182.
- So a new game in a used slot leaves the old save on disk until its first save, and a game over before then reloads the old save, because Re-Load reads the slot back
  (`DefineButton2_2791` on(release), lines 2-7).

## Starting state (new game)

- Class-select buttons (DefineButton2_2735/2736/2737 = Bio/Hydro/Psycho) seed `moveMatrix[0..1]` and `moveMatrix2[0..1]` with the class starting moves.
- `equipArray0 = [0, 11, 0, 4, 8, 5, 0]` (frame_180): White T-Shirt, Levo Jeans, Proverse All Stars, A Broken Pipe.
- The same frame also resets `StatSets0 = [5, 6, 5, 3, 0]` (`frame_180/DoAction.as:8`), which is exactly that gear's bonuses (life 5, strength 6, magic 5, speed 3). The class buttons had already
  added the 19 level-1 points, split by class ratio, onto `StatSets0` through `assignPointsStart` (`frame_42/DoAction_15.as:57-78`), and `statPoints` stays 0 (`frame_41/DoAction_2.as:79`), so
  the class split is thrown away and a new character holds only its gear bonuses. Every route from class select passes through frame 180 before battle 100, and the tutorial route
  fights battle 2 on the way (`frame_165/DoAction.as`), still holding the class split because frame 180 has not run yet. The port's `PlayerSave.new_game` keeps only the split's rounding residue, and `GameData.new_game` equips the gear onto a zeroed
  allocation.
- Sell-back = `ceil(price * 0.15)` (DefineButton2_3015).

## Battle presentation per animation type (frame_217/PlaceObject2_3389_480 enterFrame, ~line 400)

The battle engine dispatches on `addNewMove` param 10:

- **Melee**: caster `gotoAndPlay("run")` + `krinMelee(...)` (see above). Param 12 = the attack label. The move's sound plays AT IMPACT (`soundToMake` in the BAMBAMBAM handler). A Melee miss is
  silent: the dispatch sets `missToMake` to undefined (conductor line 407), and the miss branch plays `missToMake` (conductor line 107).
- **Missile**: caster plays **"cast"** (param 12 is the PROJECTILE clip, not a caster label), `colortobe` = param 11 tints the cast glow, `sfx_cast` plays, `krinBoltMake` spawns the projectile (speed
  `krinBoltSpeed = 1`, stretching trail `_xscale += 8.3 * step`); impact/sound/boom land when the bolt arrives. A Missile miss plays `sfx_magicmiss` (conductor line 415).
  `ability_two[20]` (is_multi_target) fires one bolt per living enemy, but no move sets it (see krinBoltMake above), so this branch is dead content.
- **Shock**: caster plays **"cast"** with the `colortobe` tint; param 12 is UNUSED. The move's own sound plays immediately, the BOOM clip (param 13) attaches at the target at once, the camera zooms
  (`zoomPause = 1`), the screen shakes (`GridShaker`, when param 9 speed modifier >= 0), and impact (`BAMBAMBAM`) is instant. Shock also sets `missToMake` to undefined (conductor line
  447), so its miss would be silent too, but a Shock move never misses: the hit roll is skipped for Shock and `strikeSuccess` is set true (conductor lines 360 and 385).

Element colors (`elementColorArray`, frame_41/DoAction_2.as - menu bars AND damage numbers): Physical `C40000`, Magic `FB95C8`, Ice `68CBF4`, Fire `FF6600`, Lightning `FFCC00`, Earth `856B47`, Shadow
`664D80`, Poison `508349`; heals `66FF00`.

Damage numbers (`KrinNumberShow`, frame_42/DoAction_7.as): digit sprites (NumberFixer/NumberSetter clips) colored by the move's ELEMENT, `gotoAndPlay("critical")` variant on crits (`perKSuccess`),
special "miss"/"shield" frames. Crits also fire `GridShaker` (frame_42/DoAction_8.as). Every damage hit that gets past the shield draws its number twice: `executeMove` calls `KrinNumberShow` at
`frame_42/DoAction_8.as:80` and again at 84, or at 137 in heal green under sswitch. Each call attaches a new clip at the next depth (`frame_42/DoAction_7.as:37`, 75-79), so a normal hit shows two
identical numbers and an sswitch hit shows a green number over an element-colored one.

## Unit stats below level 10 (frame_42/DoAction_14.as `krinAddNewUnit`)

Implemented in `scripts/battle/combat_unit.gd` (`from_character`).

- Every unit built from a positive template id, enemies and guests alike, starts from the difficulty multipliers (lines 35-52): strength and magic x0.4 / 0.8 / 1, life x0.5 / 0.85 / 1 and
  speed x0.9 / 1 / 1 on Easy / Normal / Heroic.
- Below level 10, lines 80-85 shrink them further, with `L` the battle-data level after `"X"`/`"Z"` resolution (lines 56-79): strength, magic and speed by `0.7 + 0.03 * L`, life by
  `0.5 + 0.05 * L`. Lines 135-138 then apply them to `getStat(ratio, L)`, and life also takes `vitLifeFactor`.
- Companions (the -2/-1 markers) take the other branch and get neither multiplier (lines 216-220).
- Prison Guard (ratios 10/10/5/12, `frame_42/DoAction_13.as:71`) on Normal at level 1 has life/strength/speed 212/8/12, where the difficulty multipliers alone give 386/11/17.

## Victory money (frame_42/DoAction_14.as `krinAddNewUnit`, DefineSprite_3142/frame_9)

Implemented in `scripts/battle/battle_rewards.gd`: `money_levels` picks the slots and levels, and `battle_scene.gd`'s `_finish_battle` hands them to `money_gain`.

- `krinAddNewUnit` runs once per battle slot 2-6. A slot passes the spawn gate when its template id is positive, or when it is a companion marker whose deployment entry is set,
  `friendArrayX[players[a - 2] + 2] > 0` (line 25). The markers are -2 and -1, so with the default `friendArrayX = [1, 2]` (`frame_42/DoAction_17.as:18`) both pass even before that companion
  has joined.
- Every slot that passes the gate with a non-zero id and a non-zero level adds that level to `moneyConstGain` and 1 to `totalEnemyGain` (lines 86-92). It is the level the battle record gives
  the slot, after `"X"`/`"Z"` resolution, not the spawned unit's, and markers usually carry level 1.
- The victory screen pays `round(0.7 * respecValue(moneyConstGain / totalEnemyGain))` with `respecValue(L) = 10 * L^1.5` (`DefineSprite_3142/frame_9/DoAction.as:39-43`,
  `frame_42/DoAction_16.as:1-4`).
- Averaging only the enemy slots 2, 4 and 6 would change the pay of 50 story battles, for example 109 (36 instead of 130) and 513 (309 instead of 823), and of training fights too: 1001
  at player level 7 pays 25 instead of 78.

## Required target buffs (frame_42/DoAction_11.as)

Ported: `Ability.required_buff_element` and `required_buff_count` carry fields 23 and 24, and `battle_scene.gd`'s `_move_valid_for_target` darkens the orb when the target falls short.

- When the player picks a move, the original refuses it with "The target's status does not meet the requirements of this move." if the target has fewer than `KRINABILITYB[24]` active buffs
  of element `KRINABILITYB[23]` (lines 60-64, counted by `checkBuffsOnUnit` at 129-146).
- Only two moves set them: the four Shatter ranks need 3 Ice buffs (`frame_42/DoAction_6.as:852-892`), and Corruption, the Psychological starting move, needs 1 Shadow buff (1607-1618, with
  the fields at 1613-1614). In the converted JSON they are `ability_two`'s `23_secondary_element_type` and `24_required_buff_count`.
- The AI never checks them: `checkBuffsOnUnit` is only called from the player's pick.

## Heroic decision timer (frame_217/DoAction.as, the conductor)

Ported: on Heroic, `battle_scene.gd` gives the player `BattleRunner.BATTLE_TIME_LIMIT / 30.0` seconds of `_process` time and passes for them when it runs out. On Easy and Normal,
and on Heroic once a half-turn ends with the player's unit dead, it waits for the player and hides the countdown label.

- `BattleTime = BattleTimeLimit = 120` (`frame_217/DoAction.as:1-3`). The conductor adds 1 to `BattleTimeNow` once per frame, and only while `turnBasedKrin` is false and the player's team is
  moving (conductor lines 593-596), so the window is 120 frames, 4 s at 30 fps.
- `turnBasedKrin` is true on Easy and Normal (`frame_201/DoAction.as:65-79`), so only Heroic has the timer. On the other two the clock waits at `BattleTimeLimit - 0.000001` until the player
  picks (conductor lines 639-642).
- At `BattleTimeLimit - 1` the AI allies decide (conductor lines 674-698), and at `BattleTimeLimit` the half-turn starts whether or not the player has picked (conductor lines 769-792).
- Picking a move jumps the clock to `BattleTimeLimit - 5` (`frame_42/DoAction_11.as:98-101`), and once the player's unit dies the conductor sets `turnBasedKrin = true` (conductor lines
  200-202).
- Running out is a pass. Every slot starts the battle holding move 0 (`frame_217/DoAction_2.as:313-318`) and each dispatch writes move 0 back for its caster (conductor lines 470-473), so
  a player who never picked passes. The pass button, DefineButton2_3383 (`krinToMove2` on the root timeline), also jumps the clock to `BattleTimeLimit - 5` (release lines 9-12).
- The clock is `battleClocker` (DefineSprite 3389), placed at (400, 507.25) behind the pass button. Its two half-dials in DefineSprite 3386 turn with
  `BattleTimeNow / (BattleTimeLimit / 2)` (`DefineSprite_3386/frame_1/PlaceObject2_3385_2` and `PlaceObject2_3385_6`, line 2), and none of its sprites holds a text field, so it shows no number.

## Battle end and game over (DefineSprite 3355 `blacker5`, root frames 229-241 and 104)

Ported: `battle_scene.gd`'s `_finish_battle` opens `GameOverScreen` (`scripts/battle/game_over_screen.gd`) on a defeat or a draw. The port shows it, and the victory screen too, without the
original's fade to black.

- Once `winCondition` is set, the conductor plays `blacker5` (conductor lines 257-261). DefineSprite 3355 fades its black shape 333 in over frames 32-81, about 1.7 s at 30 fps, and its frame 85
  sends the root to `loseCombat`, `winCombat` or `drawCombat` for `winCondition` 0, 1 or 2 (`DefineSprite_3355/frame_85/DoAction.as:5-16`).
- `drawCombat` (root frame 240) plays into frame 241, which jumps to `loseCombat` (`frame_241/DoAction.as:1-2`), so a draw ends the game like a defeat. `loseCombat` (frame 229) plays into
  frame 230, which sets `gameoverKrin`, keeps `Krin.slotInUse` in `slotSaveGO` and jumps to `resetHere` (`frame_230/DoAction.as:1-5`).
- `resetHere` (frame 41) runs `stopAllSounds()` and recreates `Krin` (`frame_41/DoAction_2.as:7` and 13), so the game in memory is gone. Frame 43 then jumps to `gameOverMenu`, root frame 104
  (`frame_43/DoAction.as:21-25`).
- Frame 104 fills `whatToSay111` with `MENU[50]` "You're dead, Sonny...", `whatToSay222` with "< Click here to Re-Load >" and `tipTextGO` with `GOTIP[0]` (`frame_104/DoAction.as:1-3`). Its
  Back caption, DefineEditText 2703, shows `whatToSayX`, which `frame_46/DoAction.as:1` sets to `MENU[26]` "Back" whenever the main menu runs.
- Re-Load (`DefineButton2_2791` on(release), lines 2-12) loads `slotSaveGO` and goes to `Navigation` when that slot holds a save, or to `mainMenu` when it does not. Back
  (`DefineButton2_2702` on(release), line 2) goes to `mainMenu`. The menu music starts again at `Navigation` (`frame_181/DoAction.as:15`).
- The frame's backdrop is the three characters every menu screen places at depths 1, 2 and 5, which `assets/ui/menu/start_background.png` already is. Its Armor Games logo, copyright line and
  "Play MORE Games!" link are left out, see `docs/adr/0002-leave-out-the-armor-games-branding.md`.

## Approximation audit (2026-07-21) - port pieces NOT yet source-faithful

Everything below still stands in for original behavior, except the rows marked DONE; the ActionScript truth is already located, so no re-decoding is needed:

| Piece | Current stand-in | Original truth lives in |
|---|---|---|
| Camera zoom + shake | none | `GridZoomer` "KrinZoomGo" (zoom to target center * `-zoomRatioNEW` + 400/300; pause 2xCD melee / 5 missile / 1 shock), `GridShaker` (shock + crits) |
| Target hit flash | HIT recoil label only | `BATTLEFLASH` with `characterColorState/FilterState`: `frame_42/DoAction_8.as` ~line 199 |
| Damage number art | Labels with exact colors + bigger crit font | NumberFixer/NumberSetter digit clips, miss/shield variants: `frame_42/DoAction_7.as` |
| Top battle HP/focus bars | in-field bars with numbers | `lifeBarUpdate` + bar clips, layout in frame 217 placements |
| Doll ground shadow | none | player clip "shadower" (hidden on death, MODEL1 frame 360 script) |
| Melee end point | fixed 55 px short | target/shooter half-widths: `krinMelee` endPoint |
| Swing whoosh | impact sound only | `sfx_swing` cues baked at MODEL1 clip frames 88/118/146 |
| Stun/cast animations | **DONE (2026-07-21)**: the port plays the real labels (see the stun family section above), no longer a code-driven slump/raise | labels `cast` 189-219, `stun` 220-239 -> `stun2` 240-279 loop (frame 279 goto), `outofstun` 280-295 -> stand |
| Hover ring / radial menu / pass ring | modern inventions (kept by design) | original UX: `KrinSelector` clips + `KrinToolTipper` tooltip system |
| Victory screen layout | inventory-window geometry + reference screenshot | menu clip 3142 frame 9 placements (never dumped precisely) |
| Options screen | invented layout from reference | menu clip 3142 frame 39 |
| Abilities tutorial callout | skipped | texts 3063 + glow box sprite 3059 (frame 25) |
| Sky horizon | **DONE (2026-08-22)**: the strip position comes from `battle_layout.json` (`BATTLE_LAYOUT_PATH` in `battle_scene.gd`), no longer an empirical y = 292 | background clips' own art timelines (sky placement baked per zone) |
| Start-menu flow | slot -> name+class -> options | original: PLAY -> name entry (root ~65) -> slot select (~75) -> class (~85) -> options (~95) |
| Battle countdown | **DONE (2026-11-08)** for the timing: 4 s on Heroic only, running out passes the turn, and Easy and Normal wait with the label hidden. The display is still a number in the bottom bar's `Panel3` | 120 frames (4 s at 30 fps) on Heroic only, and the half-turn starts when it runs out: see "Heroic decision timer" above. The original shows no number: `battleClocker` (DefineSprite 3389) sits behind the pass button and fills the two half-dials of DefineSprite 3386 from `BattleTimeNow` |
