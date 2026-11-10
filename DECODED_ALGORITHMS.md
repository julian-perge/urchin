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

The Godot port fires a single bolt per `_play_move_event` call and has no multi-target path. `BattleRunner` ran a move on every living enemy when `Ability.hits_all_enemies` was set
until issue 47 deleted that branch, since no move sets `[20]`. **DONE (2026-08-19)**, see `.superpowers/sdd/2026-08-18-missile-projectile-art/`: distinct clip art per `projectileModel` name (e.g. `Krin.Firebolt`) is extracted and rendered untinted; `KrinTrail`'s real 33-frame fade-in/fade-out pulse (not a generic tinted circle+line) plays alongside it, tinted by the move's real `colortobe` value; and a miss now flies the bolt fully past the target off-screen instead of always resolving as a hit on arrival, matching `strikeSuccess`'s hit/miss branch (`Projectile.did_hit` gates whether `reached_target` frees the bolt immediately or lets it keep flying). Both the bolt and the trail come from a generated scene of their own under `scenes/battle/vfx/`, which `Projectile` instantiates by clip name - each one already carries that clip's frames and the registration point the source SWF drew it around, so nothing here positions or scales art at play time (**DONE (2026-08-20)**, see `.superpowers/sdd/2026-08-19-vfx-registration-scenes/`).

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

Implemented in `scripts/entities/character_visual.gd` (`enter_stun`/`exit_stun`/`_animate_stun`) and `scripts/battle/fighter_presenter.gd` (`_show_stun`).

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
- No numeric timing constants gate any of this (unlike `krinBoltTime`/`krinMeleeAttackCD`). It is a value comparison that runs on every `applyChangesKrin` call, for an active unit only
  (line 468). The port compares in `FighterPresenter._show_stun`, against the stun a `MoveResult` states (`stun_after`) at its impact and against the unit's own stun at the half-turn's end,
  and a dead doll keeps its death. It never compares at the redraws in between, because the runner resolves the whole half-turn before the replay, so the unit's own stun can already hold a
  stun from later in it. This note used to say those extra comparisons changed nothing. They started a later stun early, and the flinch at the hit that landed it then left the doll idle for
  the whole stun.

## Dispel order and timing (frame_217/PlaceObject2_3389_480 enterFrame, lines 22-103)

Ported: `BattleRunner._resolve_dispels` takes slots in `CombatUnit.buff_slots` order, `CombatUnit.apply_changes` sorts `buff_slots` the way `applyChangesKrin` sorts `BUFFARRAYK`
(`_sort_buff_slots`), and `BattleManager.execute_move` recomputes the target's stats after the hit.

- On a successful strike, before `executeMove`, the conductor walks the target's 40 `BUFFARRAYK` slots (`maxBuffLimit`, `frame_42/DoAction_10.as:538`) in array order. A slot is a
  candidate when its CD is above 0 and its buff's element is in the move's `[15]` list (line 30). While any of the move's `[16]` dispels are left, each candidate whose buff polarity `[20]`
  matches the move's `[19]` spends one, and then goes only if `Math.random() <= [22]` and `Math.random() >=` the buff's `[32]` (lines 32-46), so a failed roll still spends a dispel. A
  removal sets CD to 0 and calls `applyBuffKrin` with -1 (lines 43-44). 37 moves dispel, and none lists an element twice.
- The array order is what the unit's last `applyChangesKrin` left, because line 344 of `frame_42/DoAction_10.as` runs `BUFFARRAYK.sortOn("CD", Array.DESCENDING | Array.NUMERIC)` on every
  call. It runs after every hit on the unit (conductor line 103), at the end of the unit's own `buffTicker` (`frame_42/DoAction_10.as:135`) and at battle start for a unit with passive buffs
  (`frame_217/DoAction_4.as:13`). So the slots with the most turns left come first, and passives, at CD -1, sort after the empty slots. A new buff takes the first slot with CD 0
  (`frame_42/DoAction_10.as:152-166`).
- The sort doesn't keep tied slots in order. Ruffle's AVM1 `qsort` (`core/src/avm1/globals/array.rs` in ruffle-rs/ruffle) is a quicksort that splits each range on its first element, and it
  makes the same comparisons and gives the same result that Flash Player logged for `tests/tests/swfs/avm1/array_sort_random`, a sort with a random comparator (passing since Ruffle commit
  `763616d33b`). For `sortOn` with `DESCENDING`, Ruffle flips each comparison inside that quicksort (`sort_compare`), where for `sort` it reverses the sorted result. No Flash Player log in
  Ruffle's tests has tied keys under `sortOn` with `DESCENDING`, so that part rests on Ruffle's code. avmplus, Flash Player's AS3 engine, also flips the comparison for `DESCENDING`
  (`DescendingCompareFunc`, `core/ArrayClass.cpp:326` in adobe/avmplus). Dispelling slot 0 of three slots holding 5, 3 and 3 turns leaves the two 3s swapped, and Godot's `sort_custom`
  ordered the slots with turns left differently from this quicksort in 2,592 of 3,000 random 40-slot arrays.
- Sorting slots that are already in order moves nothing, so the port's `apply_changes` when it builds a unit, on empty slots, changes nothing. Sorting a copy at each dispel instead
  doesn't match: in 40,000 random runs of hits, self-buffs, ticks and dispels on one unit it removed different buffs from the original in 11,577.
- A move can land its status buff on its own caster (`[21]`, conductor lines 76-83), and line 103 still recomputes only the target, so a buff that lands on the caster of a move aimed at
  someone else waits for the caster's `buffTicker`, stats and sort both. That tick works out its DoT damage (`frame_42/DoAction_10.as:31`) before its own `applyChangesKrin` (135), so it
  reads the caster's stats from before the buff. `BattleManager._apply_status_effect` leaves `apply_changes` to the end of `execute_move` for the target and to `tick_buffs` for the caster.
- `applyBuffKrin` changes a removed buff's STUN, REFLECT, HEALMOD_PLUS, HEALMOD_MINUS, HEALMOD, IDOT, IHOT, ODOT, FOCUSCHANGE and SILENCED at once (`frame_42/DoAction_10.as:140-149`), and
  its SSWITCH (171), SHIELD (205-222) and DoT and focus ticks (223, 243-251). Its stat changes only go into `changeArray` and `IDMGP` (172-191) and the per-element arrays (229-232), and
  only `applyChangesKrin` turns those into STRENGTHU, MAGICU, SPEEDU, LIFEU, DMG, DMG2, IDMG, IDMG2, IDMGP2, PERU and DEFU (259-339), the fields `executeMove` reads
  (`frame_42/DoAction_8.as:3-60`). The conductor runs `executeMove` (lines 54-69) and the status effect (70-102) before that `applyChangesKrin` (103). So the hit that removes a buff lands
  without the buff's direct fields but with its stat changes: a Shatter that dispels SHATTERBOLT hits a target that is no longer stunned but still takes half damage.
- The port used to walk `buff_slots` in the order the buffs landed, since nothing sorted it, and `_resolve_dispels` recomputed the target's stats before the hit.

## Buff icon row (frame_42/DoAction_10.as `applyChangesKrin`, lines 345-379)

Ported: `UnitOverlay.refresh_buffs` (`scripts/battle/unit_overlay.gd`).

- `applyChangesKrin` redraws a unit's row right after its sort. For each of slots 0 to 6 of `BUFFARRAYK` whose CD isn't 0, it attaches a `KrinBuffShower` (DefineSprite 104) to
  `p<playerID>BAR` at x = (110 + 17 * slot) times 1 for team 1 or -1 for team 2. It sets the clip's `buffCounter` text (edit text 66) to the CD, sends `buffIcon` to the frame named by
  the buff id and tints `buffColor` with the buff element's color. The tooltip title is the buff's `[0]` and its text the buff's `[25]` (the enterFrame handler on `buffColor` inside
  DefineSprite 104). Nothing sorts the row itself, so it shows the first 7 slots in the order the sort left them, and it only changes when `applyChangesKrin` runs for that unit.
- The port's row used to sort the slots with turns left again with `sort_custom`, which moved tied buffs once a unit held more than 16 of them and changed the 7 icons it showed in 212
  of 20,000 sorted states. The port's tooltip title also adds the turns left, which the original's doesn't.

## Menu piercing/defense bars (DefineSprite_3142/frame_1)

Implemented in `scripts/ui/menu/menu_theme.gd` (`bar_fill_fraction`). Display value = allocation + ceil(100 + 15 * level); fill fraction = the crit-curve quartic `0.016666667 x^4 - 0.25 x^3 + 1.233333
x^2 - 1.9 x + 0.9` of `value / (100 + 15 * level) + 1`, clamped to the track (base allocation = 30%).

## Item looks and icons

- `looks` art keys: `gghhjjuu.looks = "X"` assignments in frame_42/DoAction_16.as after each `createNewItemKrin` (wearable default "NINJA"; id counter jumps at 99/299/499).
- Slot icons: the icon clip (DefineSprite 2064) has one labeled frame per item name; shape 1913 is a clip mask: its first placement, on frame 16 at depth 2, carries clipDepth 15, so stripping it unclips every icon under it (item 69 went from 63x63 to 101x140, see docs/agents/art-extraction.md). It is placed once more later in the clip at depth 1 without a clip. `gotoAndStop(ITEMNAME[id])`.

## Companion aggression stances (agModeAr)

Implemented in `scripts/entities/party.gd` (`AGGRESSION_PRESETS`). Columns 0-4 = Phalanx/Defensive/Tactical/Aggressive/Relentless; rows = [Aggression, LifeBoundary1, LifeBoundary2, FocusAggression,
FocusRegenLimit]: `[0,30,50,70,90] / [95,90,75,40,2] / [0,65,35,15,1] / [0,30,70,15,100] / [30,30,30,5,5]` (read column-wise). Default stance 2 (Tactical).

The stance lasts one battle. The original spawns every companion in Tactical at the start of every battle (`frame_42/DoAction_14.as:208-213`), the stance button writes only the
live battle unit (`DefineButton2_3289` on(press), lines 9-14), and the stance row highlights that unit's `agMode` through `setAG` (lines 12-14 of both copies in `DefineSprite_3312`),
which runs when the row loads and again at each of the player's half-turns (`frame_217/PlaceObject2_3389_480` enterFrame, lines 725-726). The saved `Krin.agMode` (seeded to 2 at
`frame_42/DoAction_17.as:42`, saved through `frame_42/DoAction_20.as:297`) is never read. The port does the same: `Party.build_companion_unit` applies Tactical, the stance row starts
on Tactical, and `PlayerSave.ag_mode` stays in the save unread. The port used to save the pick there and build companions with it.

No guest ever shows a stance row, though nothing in the original checks where a unit came from. At each of the player's Decisions the conductor shows the bar and fills its two rows from
slots 3 and 5, by whether each unit is active (`frame_217/PlaceObject2_3389_480` enterFrame, lines 703-727), and a template unit carries `agMode` 0 (`frame_42/DoAction_14.as:110`), so a
guest's row would work. Only battles 2 and 508 put a guest on the player's team (measured over the 99 battles in `resources/battles`). Battle 2 hides the bar outright
(`DefineSprite_3317/frame_1/PlaceObject2_3312_7` onClipEvent(load), lines 5-8). Battle 508's only phase entry is flagged endGame, so it is won the moment its opening lines finish (lines
862-868), and the block at line 703 needs `speechDone` true with `winCondition` still below 0 (lines 589-591), so it never runs. The bar starts hidden (`gotoAndStop("HIDE")` in that same
onClipEvent). This is read from the AS, not seen in a live run of the SWF. The port gives a row only to a unit whose `origin` is COMPANION, so no guest gets one there either. When the rows
show still differs: the port keeps a companion's row up for the whole battle, while the original shows the bar only at Decisions, so it never appears in the four battles won during their
opening lines (210, 409, 504 and 508).

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
  port uses `Party.PLAYER_NAME` in all five places, so battle 100's "Sonny" line finds the player as its speaker instead of finding nobody and being skipped.
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

## What executeMove does on each branch (frame_42/DoAction_8.as)

Ported: `BattleManager.execute_move` returns a `MoveResult` that states which branch ran and what it left, and `FighterPresenter`, `CombatLogPanel` and
`Achievements.collect_battle_counters` read that instead of working it out again.

- **Full Damage** works out the hit (lines 24-64) and compares it with the target's SHIELD (65-70).
  - A shield bigger than the hit takes all of it. SHIELD goes down by the hit, the target's `shield` clip and `sfx_shield` play, and `KrinNumberShow` draws its `shield` frame (70-76).
    Nothing after the shield check runs: no flash, no `hit` label, no hit voice, no life bar update and no AchVal1. A crit has already shaken the grid by then, and played `Angry_Dux` or
    `Angry_Roald` when Veradux or Roald is the caster (28-43). The result is HARM with amount 0 and `shield_took_all` set.
  - Otherwise the shield's value comes off the hit and the shield empties (79-81). A shield exactly as big as the hit soaks it this way, so the rest of the branch plays a hit for 0, and
    `KrinNumberShow` only draws a number above 0 (`frame_42/DoAction_7.as:8`).
  - With no SSWITCH (82-131) the hit comes off LIFEN, which stops at 0 with FOCUSN set to 0. The number is drawn twice (80 and 84). AchVal1 grows by the hit, which is what got past the
    shield, when the caster's playerName is "Sonny" (91-93). BATTLEFLASH plays `hit` (99), the target plays `hit` unless STUN is set (100-103), and at LIFEN 0 it plays `dead` and goes
    inactive (104-107), or else a hit voice plays (130). The `lifeBarUpdate` after either branch (150) plays the target's `voiceDie` when LIFEN is 0, unless its bar already read 0%
    (328, 344-347).
  - With SSWITCH (133-149) the hit is added to LIFEN, which stops at LIFEU. The second number is heal green and BATTLEFLASH plays `heal`. No `hit` label, voice or AchVal1.
- **Heal** works out the heal (153-171), shaking the grid on a crit (158-160), and does nothing more when it comes to 0 or less (172), before it looks at SSWITCH (174). So a heal of 0 is
  HEAL with amount 0 under SSWITCH too.
  With no SSWITCH, LIFEN rises to at most LIFEU with a heal-green number and the `heal` flash (174-187). With SSWITCH, LIFEN falls instead, with a Shadow-colored number (191), the `hit`
  flash (203), the `hit` label unless STUN is set (204-207) and `dead` at 0 (208-211). It plays no hit voice, but its `lifeBarUpdate` (198) plays the target's `voiceDie` when LIFEN
  reaches 0, as the one at 150 does.
- **Focus** adds `[9]` to FOCUSN, kept between 0 and FOCUSU, and plays the `focus` flash. It draws no number (232-249).
- Any other category does nothing in `executeMove`. Shatter Bolt is the only such move, and its status effect still lands after it (`KNOWN_GAPS.md`, the "Attack" entry).
- The life bar redraws in `executeMove` (150, 187, 198 and 248) and again in `applyChangesKrin` (`frame_42/DoAction_10.as:342`), which the conductor runs on the target after the
  move's status effect (conductor line 103). So a move leaves the bar on the life after that recompute, which is the life `MoveResult.life_after` holds. The recompute moves life when the
  move lands, or dispels, a buff that changes max life: Edge Of Death's EDGEOFDEATH takes 85% off.
- The STUN checks for the `hit` label read the target as the hit lands, before the move's own status effect, so `MoveResult.target_stunned` is read then too. Shatter Bolt's stun comes
  after its own hit. The stun pose changes in the recompute after the strike (`frame_42/DoAction_10.as:468-481`), so `MoveResult.stun_after` is read after that recompute, with the life.

## Unit stats below level 10 (frame_42/DoAction_14.as `krinAddNewUnit`)

Implemented in `scripts/battle/combat_unit.gd` (`from_character`).

- Every unit built from a positive template id, enemies and guests alike, starts from the difficulty multipliers (lines 35-52): strength and magic x0.4 / 0.8 / 1, life x0.5 / 0.85 / 1 and
  speed x0.9 / 1 / 1 on Easy / Normal / Heroic.
- Below level 10, lines 80-85 shrink them further, with `L` the battle-data level after `"X"`/`"Z"` resolution (lines 56-79): strength, magic and speed by `0.7 + 0.03 * L`, life by
  `0.5 + 0.05 * L`. Lines 135-138 then apply them to `getStat(ratio, L)`, and life also takes `vitLifeFactor`.
- Companions (the -2/-1 markers) take the other branch and get neither multiplier (lines 216-220).
- Prison Guard (ratios 10/10/5/12, `frame_42/DoAction_13.as:71`) on Normal at level 1 has life/strength/speed 212/8/12, where the difficulty multipliers alone give 386/11/17.

## Victory money (frame_42/DoAction_14.as `krinAddNewUnit`, DefineSprite_3142/frame_9)

Implemented in `scripts/battle/battle_rewards.gd`: `money_levels` picks the slots and levels, and `BattleSettlement.settle` (`scripts/battle/battle_settlement.gd`) hands them to
`money_gain` through `BattleRewards.apply_victory`.

- `krinAddNewUnit` runs once per battle slot 2-6. A slot passes the spawn gate when its template id is positive, or when it is a companion marker whose deployment entry is set,
  `friendArrayX[players[a - 2] + 2] > 0` (line 25). The markers are -2 and -1, so with the default `friendArrayX = [1, 2]` (`frame_42/DoAction_17.as:18`) both pass even before that companion
  has joined.
- Every slot that passes the gate with a non-zero id and a non-zero level adds that level to `moneyConstGain` and 1 to `totalEnemyGain` (lines 86-92). It is the level the battle record gives
  the slot, after `"X"`/`"Z"` resolution, not the spawned unit's, and markers usually carry level 1.
- The victory screen pays `round(0.7 * respecValue(moneyConstGain / totalEnemyGain))` with `respecValue(L) = 10 * L^1.5` (`DefineSprite_3142/frame_9/DoAction.as:39-43`,
  `frame_42/DoAction_16.as:1-4`).
- Averaging only the enemy slots 2, 4 and 6 would change the pay of 50 story battles, for example 109 (36 instead of 130) and 513 (309 instead of 823), and of training fights too: 1001
  at player level 7 pays 25 instead of 78.

## Companion XP (frame_42/DoAction_14.as `krinAddNewUnit`, DefineSprite_3142/frame_9)

Implemented in `scripts/battle/battle_settlement.gd`: `_fighting_party` lists the companions `BattleSetup.build_units` placed, in slot order, and `BattleRewards.apply_victory` pays
each of them.

- Frame 201 empties `Krin.friendlySlotsFFTT` at every battle load (`frame_201/DoAction.as:116`) and then spawns slots 1 to 6 in order (lines 125 and 206).
- `krinAddNewUnit`'s companion branch pushes the companion's party id onto that list when the marker's deployment entry names a companion who has joined (`frame_42/DoAction_14.as:187-192`).
  The same block sets `AchVal2` and adds 1 to `AchVal3`, the teammate counters. Nothing takes an entry back out, so a companion who dies in the fight stays on the list.
- The victory screen's two companion bars read `friendlySlotsFFTT[0]` and `[1]` and hide themselves when the entry is undefined (`DefineSprite_3142/frame_9/PlaceObject3_3002_1111` and
  `PlaceObject3_3002_1154`, `onClipEvent(load)` lines 2-6). Each runs `expWorkOut(EnemyXPFinal, LevelStats[prx])` against its companion's own level.
- So battles 2 and 508, which have no marker, pay no companion, and training fight 1000, whose only marker is -2, pays only the companion deployed first. A guest never counts, because it
  comes from the template branch.
- 95 of the 99 stored battles put the -2 marker in slot 3 and the -1 marker in slot 5. The only battle with markers in the other team's slots is battle 1, the PvP arena's
  (`DefineButton2_3339` on(release), line 7), which the port leaves out.

## Which moves can be picked (frame_42/DoAction_11.as, frame_42/DoAction_9.as)

Ported: `MoveLegality`. `refusal` is the player's rule and `can_afford` is the part the AI shares.

- The player's pick runs six checks in order: target buffs (line 60), focus (65), silence (70), bar cooldown (75), life (80) and target relation (85). Each failure overwrites one message
  and `KrinCombatText` plays after all six, so the last failure is the one shown. A bad target beats everything, and a missing target buff only shows when nothing else failed.
- The AI's filter (lines 52, 87 and 128 of `DoAction_9.as`) is `cost * SILENCED == 0 && FOCUSN >= cost && LIFEN > flat + round(LIFEU * percent)`. The player's focus, silence and life checks
  are those same three tests, including the strict `>` on life.
- The AI has no bar slot. Its cooldowns are per pool and filtered first, and its focus move picks from that cooldown-filtered list, so cooldown stays in `BattleAI`. It chooses its own target
  and never checks the target's buffs.
- Neither re-checks silence or cooldown when the move runs. The conductor re-checks only focus and life there (line 355).

## The orb ring's hover and fade (frame_217/PlaceObject3_3382_500 enterFrame)

Not ported: `RadialMenu` keeps the port's own numbers, 0.15 s of grace and a 0.67 s fade, tested against each orb and the unit's hit button.

- A click shows the clip at alpha 0 (`frame_217/DoAction_3.as:46-48`), and it gains 50 per frame (enterFrame lines 32-35).
- While `this.hitTest(_root._xmouse, _root._ymouse)` is false the clip loses 10 alpha per frame and hides at 0, so the fade takes 10 frames, 0.33 s at 30 fps, with no grace (lines 48-61).
  `hitTest` with no shape flag tests the clip's bounding box, so the gaps between orbs and the unit inside the ring count as over it.
- While it is true, alpha goes straight back to 100 (line 64).
- An orb darkens only for a bad target or a cooldown (lines 15-29). The buttons on the orbs, `DefineButton2_3374` to `3381`, call `addMoveForPlayer` with no gate of their own, so a darkened orb
  still answers a click with its refusal message.

## Required target buffs (frame_42/DoAction_11.as)

Ported: `Ability.required_buff_element` and `required_buff_count` carry fields 23 and 24, and `MoveLegality.refusal` returns `TARGET_STATUS` when the target falls short, which darkens the orb.

- When the player picks a move, the original refuses it with "The target's status does not meet the requirements of this move." if the target has fewer than `KRINABILITYB[24]` active buffs
  of element `KRINABILITYB[23]` (lines 60-64, counted by `checkBuffsOnUnit` at 129-146).
- Only two moves set them: the four Shatter ranks need 3 Ice buffs (`frame_42/DoAction_6.as:852-892`), and Corruption, the Psychological starting move, needs 1 Shadow buff (1607-1618, with
  the fields at 1613-1614). In the converted JSON they are `ability_two`'s `23_secondary_element_type` and `24_required_buff_count`.
- The AI never checks them: `checkBuffsOnUnit` is only called from the player's pick.

## The Combat text banner (DefineSprite 2852 `KrinCombatText`)

Ported: `CombatTextBanner` (`scripts/battle/combat_text_banner.gd`) plays it from `assets/ui/battle/combat_text.json`, which `extract_combat_text` writes, and `battle_scene.gd` shows the
player's own failed moves in it, and "You cannot move yet" for a click outside a Decision.

- Root frame 217 places it at depth 630, at (400, 148.5), above the orb ring at 500 and below the speech box at 634, with a red Glow filter (blur 10 by 5, strength 1) that turns its
  translucent white band pink and haloes its text. Root frame 181 places the same clip at (400, 48.95) for the hub, which the port does not show yet.
- Frame 1 runs `stop()` and shows nothing. `gotoAndPlay("GO")` jumps to frame 2, which copies `combatTexter` into the text field through `inner.combatText`
  (`DefineSprite_2852/frame_2/DoAction.as`). Frames 2 to 12 slide the inner clip up from 10 px below its place and fade it in from 0 to full, frames 13 to 125 hold it, frame 125 empties the
  text (`DefineSprite_2852/frame_125/DoAction.as`), and frames 126 to 136 slide it back down as it fades out. The clip then loops to frame 1 and stops, 4.5 s after the GO frame at 30 fps.
- A pick with a Refusal (`frame_42/DoAction_11.as:125`) and the player's own failed move call `gotoAndPlay("GO")`, which starts the banner over with the new text. The click listener's
  "You cannot move yet" calls a bare `play()` instead (`frame_217/DoAction.as:19-26`), which changes nothing while the clip is playing, because only frame 2 copies the text.
- The click listener is a `Mouse.onMouseDown` that the battle frame adds (`frame_217/DoAction.as:18-27`), so it hears every left-click, one that a button or a unit also answers
  included. It shows `MENU[37]` (`frame_1/DoAction.as:245`) unless `InBattle` is false, `timerWait` is 0, `winCondition` is below 0 and `speechDone` is true, the test the conductor's
  decision block makes (lines 589-591), so a click during the fight, the second before the first Decision or a spoken line shows it. The port reads the click in `battle_scene.gd`'s
  `_input`, before any control takes it.
- Not ported: the listener after the battle has ended. The original removes it only once blacker5's frame 85 has sent the root to the result, on `winCombat` (`frame_219/DoAction.as:72`),
  `loseCombat` (`frame_230/DoAction.as:4`) or the arena's end (`frame_253/DoAction.as:1`), so a click during the closing fade, after `winCondition` is set, still shows `MENU[37]`. The
  port shows nothing once the battle has ended, as julian-perge/urchin#170 asks.
- The conductor writes its failure strings only when `mCaster.playerID == Krin.playerNumber`: Focus and then Health, so Health wins when both fall short (lines 477-488), and the stun
  (lines 538-542). AI units and Companions never show one.
- The text field is edit text 2849, one line of 12 px black centered text in DefineFont3 65, the bold `_sans` Device font. Flash lays the line out 2 px inside the field's bounds, which the
  inner clip places at (-374.5, -9.8), so the line starts at (-372.5, -7.8) and runs 744.95 px.
- Not ported: the text's own share of the glow. A Label cannot blur one, and the outline other screens use in place of a glow reads far heavier than the faint halo around 12 px text, so the
  port draws the text plain. The band's share is baked into its art.

## Turn order and queued heals (frame_217/DoAction_2.as, frame_42/DoAction_4.as and DoAction_11.as, the conductor)

Ported: `BattleRunner._team_select` writes each unit's `team_adder` once per full turn, and `advance_half_turn` builds the queue and runs the AI in `team_adder` order. It also adds the
player's Heal estimate through `BattleAI.heal_guess` before any AI unit decides. `battle_scene.gd` calls `advance_half_turn` once the player picks, or with `{}` on a pass or when the Heroic
window runs out.

- `TeamSelect` runs once at battle start (`frame_217/DoAction_2.as:311`) and then only when `TurnTime` reaches 0 (conductor lines 147 and 262-264). It sets `TurnTime = 2` (line 142), so it
  runs once per full turn, and the other half-turn only flips `TeamMoveNow` (conductor lines 283-311). It averages SPEEDU over each team's active units (lines 70-93), lets `absoluteStart`
  force the opener (94-108), and opens with the higher average, team 1 on a tie in single player (109-141).
- `TeamSpeedAdder` (lines 284-310) pushes all three slots of each team whether or not they are active (287-289 and 295-297) and sorts them by SPEEDU, then slot id, both descending (290 and
  298). It writes `teamAdder` 0 to 2 in that order (291-293 and 299-301), and `AITeamMoveOrder` with the opener's three ids first (302-309, with `s1tm` and `s2tm` from 109-141). `TeamSelect`
  then sets `AIGoER` to 1 for the active units of the team moving and to 0 for the other active units (145-160), and `AIGoERSwitch` flips it for all six slots after each decision (268-283).
- `krinAddMove` (`frame_42/DoAction_4.as:1-35`) files a move at `MoveArrayFINAL[adder + teamAdder]` (lines 28 and 33). `adder` is 0 for the opener's team in its own half-turn, 6 for the
  opener's team otherwise or when the conductor files the move (`autoMoveK`), and 3 for the other team (3-27). The conductor dispatches `MoveArrayFINAL[PlayerToMove]` from 0 (conductor
  lines 324-329), three per half-turn (`Cycler = 3`, line 791), files move 0 in each caster's slot after its dispatch (470-473, 490-493 and 553-556), and moves slots 6-8, or 3-8, down at each
  full turn (265-281). So units act, and the AI decides, in the order `TeamSpeedAdder` picked when the full turn started.
- On the enemy's half-turn the AI decides at once, with the clock set to `BattleTimeLimit` (conductor lines 597-622).
- On Easy and Normal the clock waits just under `BattleTimeLimit` until the player picks or passes (639-642). The allies decide on the conductor's next frame, and the half-turn starts in the
  same frame (643-672 and 769-792).
- On Heroic the clock counts frames (593-596), and a pick or a pass jumps it to `BattleTimeLimit - 5` (`frame_42/DoAction_11.as:98-101`, `DefineButton2_3383` on(release), lines 9-12). The
  allies decide at `BattleTimeLimit - 1` (674-698), 4 frames after the pick, or on frame 119 when the player never picks.
- Each decision loop walks `AITeamMoveOrder` and runs `LowerCD` and `AImoveAdder` for every active AI unit with `AIGoER` set, and files move 0 for an inactive one (603-617, 648-664 and
  679-692).
- When a pick passes `addMoveForPlayer`'s checks (`frame_42/DoAction_11.as:56-90`) and the move's category (`KRINABILITY[14]`) is "Heal" or its animation type (`[10]`) is "DispelF", the
  original adds `KRINABILITYB[10] * ((STRENGTHU + [1]) * [2] + (MAGICU + [3]) * [4] + (SPEEDU + [5]) * [6] + FOCUSN * [11] + [9])`, read off the player, to `healedThisTurn[target]` (lines
  92-95). No move has the animation type "DispelF".
- `AImoveAdder` adds the same formula, read off its own caster, to its heal candidate when its move targets allies (`[4] == 1`) and its target is still 0 or itself
  (`frame_42/DoAction_9.as:393-400`).
- The heal candidate scan compares `LIFEN + healedThisTurn` (lines 181-247), but the life boundary check reads the candidate's plain `LIFEN / LIFEU` (248-271). So a queued heal changes
  which unit an ally heals, and changes whether it heals at all only through which unit that is.
- `healedThisTurn` starts at 0 for every slot (`frame_217/DoAction_2.as:195-201`) and is reset when each half-turn starts (conductor lines 769-776), after that half-turn's decisions. The pass
  button files move 0 and adds nothing (`DefineButton2_3383` on(release), line 4).
- Counted from `TalentTree.TREES` and `STARTING_MOVES` against the move data, 66 of the 231 move ids a player can learn or start with are Heals, and only Restore (228-230) has an estimate
  above 0: strength and magic times 1, 1.75 and 2.5 (`frame_42/DoAction_6.as:899-920`). Every term of the other 63 is 0, so they queue nothing.

Three Heroic cases, read from the code but not run, and not ported, since the port takes one action per unit per half-turn:

- Every pick that passes the checks adds its estimate, and nothing takes it back (`frame_42/DoAction_11.as:92-95`). After a pick the player has until the allies decide at
  `BattleTimeLimit - 1`, about 4 frames, to pick again or pass, and a heal picked first still counts when they decide. The port only sees the last pick.
- A pick or a pass that lands after the allies decided at `BattleTimeLimit - 1` but before the half-turn starts puts the clock back to `BattleTimeLimit - 5`, so the `BattleTimeLimit - 1`
  branch runs a second time. `AIGoERSwitch` already flipped `AIGoER` after the first run, so the second one runs `LowerCD` and `AImoveAdder` for the other team's AI units and flips `AIGoER`
  back. In the first half-turn of a full turn, the other team then skips its own decision in the second half-turn (conductor lines 597-622 only run units with `AIGoER` set) and acts on
  the moves it picked a half-turn early, while the player's AI allies decide in its place. `TeamSelect` resets `AIGoER` for active units at the next full turn
  (`frame_217/DoAction_2.as:145-160`).
- When the window runs out, nothing files the player's move, so the player's slot keeps what the full-turn shift left there (conductor lines 265-281). If `TeamSpeedAdder` moved the player
  to a new position at the start of that full turn, that is the move 0 a teammate left in that position, so the teammate's buffs tick a second time (the move 0 path, lines 534-584) and the
  player's buffs and bar cooldowns (338-349) don't tick that half-turn.

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

## Battle speeches (frame_217/PlaceObject2_3389_480 enterFrame, lines 794-870)

Ported: `BattleRunner._drain_speeches` picks the lines, names each speaker, with `BattleRunner.NARRATOR_NAME` for slot 0, and makes the endGame check after each batch.
`battle_scene.gd` waits `START_WAIT_SECONDS` before the opening lines, `_play_speech` shows each line for its `timeToSay` seconds, and `_input` handles Space through
`BattleRunner.hard_skip` and `AudioManager.stop_effects`. The port shows a plain label, without the box's placement or fade.

- Each battle record's `speeches` entries carry `player`, `phase`, `turnTime`, `turnTime2`, `say`, `timeToSay` and sometimes `voiceOver` (`frame_42/DoAction_14.as`, 149 lines in 50
  battles). Between half-turns the conductor shows the line at `speechOn` when its `phase` is the current one, its `turnTime` is the half-turns since that phase began (`turnTimeKKK2`) and
  its `turnTime2` is the number of lines shown since the half-turn ended (lines 809-813). That count is the conductor's own `turnTime`, reset at line 146 and stepped at 818.
- `getPNum` (`frame_42/DoAction_14.as:285-302`) turns `player` into a slot. A number under 7 is the slot, and anything else is a name, matched against `playerName` in slots 1 to 6 in
  order, alive or not. With no match it returns NaN. The only names in the records are Veradux (17 lines), Roald (10) and Sonny (1, in battle 100).
- A line shows only when that slot's `playerKrin` is active (line 815). The narrator, `playerKrin0`, is set up active and named "Information" in every battle
  (`frame_201/DoAction.as:113-115`), so its lines always show, and the box names the speaker by `playerName` (line 830). No `playerKrinNaN` exists, so a name nobody on the field has is
  skipped like a dead speaker. The `== NaN` test at line 805 is never true.
- A skipped line moves `speechOn` on without stepping `turnTime` (lines 852-856). All 71 conversations in the records number their lines from 0 with no gaps, so when the next line has
  the same `phase` and `turnTime`, its `turnTime2` is one too high, it never matches, and `speechOn` stays on it for the rest of the battle, so no later line plays.
- A shown line sets `timeSpeechKKKUP = timeToSay * 30` (line 841). The speech box, `combatScript` (character 3367 at depth 634, `PlaceObject2_3367_634`), adds `30 / frameRateNowKrin` to
  `timeX` every frame and lets the next line through once `timeX` reaches it (enterFrame lines 13-17), so a line stays up `timeToSay` seconds at any frame rate. 55 of the 149 lines run
  past 4 s, and the longest are 15 s, the opening lines of battles 104 and 105 (`frame_42/DoAction_14.as:423` and 443).
- `speechDone` stays false until the last line ends, and the whole decision block waits for it (conductor lines 591-793), so neither the clock nor the AI's picks nor the half-turn start
  move. Target clicks wait too (`frame_217/DoAction_3.as:18`), and the pass button queues the pass but only commits it once speech is done (`DefineButton2_3383` on(release), lines 4-7).
  A click meanwhile shows `MENU[37]`, "You cannot move yet..." (`frame_217/DoAction.as:19-26`). The block also waits for `timerWait`, which starts at 30 frames when the battle loads
  (onClipEvent(load), line 6), so the opening lines start a second in.
- A pass that shows nothing sets `speechDone` and checks the phase entry just passed, `phases[phase - 1]`, for `endGame`, taking its `winOrLose` (lines 862-870). That happens
  once the last line of each batch is done, or straight away when none plays. A battle with no lines at all never gets the check (lines 794-796), but every battle with an endGame
  entry has lines. 210, 409, 504 and 508 push their only phase entry, flagged endGame, as `phases[0]` (`frame_42/DoAction_14.as:1093` for 504), so each is won as soon as its
  opening lines are done, before anyone fights. 109, 201 and 212 flag `phases[3]`, `phases[1]` and `phases[3]`, so each is won once the next phase's opening lines are done.
- The box sits at x 473.3 for a team 2 speaker and at x 21.8 otherwise (lines 819-828), sends a child clip to the frame named after the speaker (831) and plays the speaker's own `speech`
  clip (842). It fades in and out by 5 alpha a frame (speech box enterFrame lines 5-12 and 19-22).
- Space ends the current line and sets `hardSkip` (`PlaceObject2_3367_634` onClipEvent(keyDown), lines 2-9). Line 815 then skips the next line too, which strands the line after it as
  above. `hardSkip` clears once the box has faded out (enterFrame line 25) or the decision starts (conductor line 701), so outside a line Space only does the rest of what the
  handler does: it stops `my_sound1` to `my_sound3` (lines 6-8), the three channels `addSound("Effects")` plays every cue on in turn (`frame_42/DoAction.as:5-15` and 119-121).

## Battle end and game over (DefineSprite 3355 `blacker5`, root frames 229-241 and 104)

Ported: `BattleSettlement.settle` reports a defeat or a draw as `game_over`, and `battle_scene.gd`'s `_finish_battle` then opens `GameOverScreen` (`scripts/battle/game_over_screen.gd`).
Every battle fades in from black, and a win, a loss and a draw all fade to black before their result screen, through `_play_fade`, from the frames `extract_battle_screen` writes into
`battle_layout.json`'s `fade` section.

- `blacker5` is DefineSprite 3355, which root frame 217 places on its top depth, 686, at (398.1, 287.05). It shows one shape, the solid black DefineShape2 333, which covers (-6.0, -4.0) to
  (802.2, 578.2), the whole 800x575 stage, on every frame that shows it, and its colour transform only ever scales the alpha. Its SoundStreamHead2 has no blocks and it has no StartSound, so it
  plays no sound.
- The battle frame opens on its frame 1 at full black, frames 2 to 28 fade the shape out from 239/256 to 1/256, and frames 29 and 30 show it at alpha 0. Frame 31 removes it and runs `stop()`
  (`DefineSprite_3355/frame_31/DoAction.as`), 1.0 s in at 30 fps, the same second the conductor's `timerWait` holds the battle for.
- Once `winCondition` is set, the conductor plays `blacker5` on (conductor lines 257-261), and so does a phase with `endGame` once its lines are done (lines 862-868). Frame 32 shows the shape at
  alpha 0, frames 33 to 82 fade it in from 10/256 to full black, frames 83 and 84 hold it, and frame 85 removes it and sends the root to `loseCombat`, `winCombat` or `drawCombat` for
  `winCondition` 0, 1 or 2 (`DefineSprite_3355/frame_85/DoAction.as:5-16`). That is 54 frames, 1.8 s, after the battle was decided.
- Nothing else happens during the fade. The conductor's decision and speech block waits for `winCondition < 0` (line 589), and so does Quit (`DefineButton2_3356` on(release), line 2), while the
  battle music plays on. The root frames a result passes through, 218 and 219, 229 and 230, 240 and 241, and 41, show shape 333 at full black over the stage until the result screen is up.
- The original pays a win after the fade, on `winCombat` (`frame_219/DoAction.as`) and on the victory screen's frame (`DefineSprite_3142/frame_9`), so `_finish_battle` settles after it too.
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

## End menu after CS_CUT5 (root frame 116, `endMenu`)

Ported: once CS_CUT5 ends, `battle_scene.gd`'s `_on_victory_proceed` opens `EndingScreen` (`scripts/battle/ending_screen.gd`), and its OK! goes to the hub through
`_on_continue_pressed`.

- The first win of 513 sets `afterCut = "CS_CUT5"` and `gotoSceneKrin = "endMenu"` (`frame_219/DoAction.as:51-55`). Proceed autosaves when autosave is on, stops every sound and plays the
  cutscene (`DefineButton2_3004` on(release), lines 4-11).
- When the cutscene ends, its fade clip sets `soundModeKrin` and `soundPlayCounter` to 0 and goes to `endMenu` without starting any music (`frame_263/PlaceObject2_3466_80` enterFrame, lines
  15-19 and 33). Only `overMap` and `Navigation` get `addSound("Music", 1)` there (lines 20-31). The port's `_on_victory_proceed` calls `AudioManager.reset_music_rotation()` when any
  cutscene ends, so the ending screen stays silent and the hub that OK! opens starts on `_music_menu1`, the same as the original.
- Frame 116 fills `enderText`, edit text 2796, with `ENDING` (`frame_116/DoAction.as:1`, the string at `frame_1/DoAction.as:2240`). It also sets `whatToSay1` to `MENU[18]` "Start!" (line 2),
  which no text field on the frame shows, and `whatToSay3` to `MENU[19]` "Play MORE Games!" (line 3), the caption of edit text 2798 under a copy of the Armor Games link 2688.
- OK! is static text 2799 with hit button 2797 over it, and the button's release goes to `Navigation` (`DefineButton2_2797` on(release), line 2). That frame starts the menu music
  (`frame_181/DoAction.as:15`) and shows the hub of `Krin.sectionIn`, still zone 5. Nothing from the win to the hub sets a flag, since the cutscene's own clip only sets `cutSceneEnd`
  (`DefineSprite_4153/frame_2424/DoAction.as:1`), so the world map opens zones 6 and 7 by its usual rule (`frame_449/DoAction.as:4-16` and 29).
- Depths 1, 2 and 5 hold the same three characters with the same matrices as frame 104 and the class-select frame that `assets/ui/menu/start_background.png` is rendered from, so the port
  reuses that PNG. Outside the texts, the logo and the copyright line, it matches ffdec's export of frame 116 at a 99th percentile channel difference of 0, and shifting it one pixel right
  at the export's 2x raises that to 17. The logo, the copyright line and the "Play MORE Games!" link are left out like the game over screen's, see
  `docs/adr/0002-leave-out-the-armor-games-branding.md`.

## Zone hub orbs (DefineSprite 3287)

Ported: `ZoneProgression.pick_story_battle` and `pick_training_battle` carry each orb's flags, and `scenes/zones/zone*.tscn` place the orbs.

- Zones 1 to 5 each have their own story orb, `DefineButton2_3188`, 3213, 3220, 3239 and 3204, and share one training orb, `DefineButton2_3186`. Zones 6 and 7 share the story orb
  `DefineButton2_3243`. ROME's training orb is `DefineButton2_3242`, at depth 56, and frame 86 (`CASINO`) removes it. Every frame under `JAPAN` (110-122) places only the story orb and the
  shop orb, `DefineButton2_3256`, so zone 7 has no training orb. The Steam build's hub, DefineSprite 2908, has the same layout under its own ids.
- Each story orb sets `bossFight` for the fight at its zone's `progressMax`, and for a replay once the zone is beaten. The TUNNELS orb compares against `progressMax1` instead (`DefineButton2_3239`
  on(press), line 14), a field no `questHub` entry has, in both builds' bytecode. So the first fight at 409 isn't a boss fight and plays the rotation's next track instead of `_music_boss`
  (`frame_42/DoAction.as:55-77`). The flag's only other effect goes through `bossJustPwned2` (`frame_219/DoAction.as:9-16`), which sends a won boss fight to the map (`DefineButton2_3004`
  on(release), line 13), and the first win at 409 queues CS_CUT4 ahead of that check, which goes to the map anyway.
- `usedTraining` is set by the zones 1 to 5 training orb (`DefineButton2_3186` on(press), line 15) and by the boss replays of the zones 1 to 5 story orbs (`DefineButton2_3188` line 9, the
  others line 12). The ROME training orb and the ROME and JAPAN story orb never set it. Predator and Legend are decided on the first wins of 212 and 513, before zone 6 opens, so neither
  award changes.

## Hub panel on the Navigation frame (root frame 181)

Ported: `scripts/ui/hotbar.gd`'s `_refresh` builds the right panel, and `scripts/game.gd`'s `_enter_tree` restores the save's zone before the hotbar's `_ready` first reads it.

- `frame_181/DoAction.as:5-14` is the only code that writes the panel (`klt1`, `klt2`, `klt3` and the `krinXbarPro` bar), and it runs each time the root enters `Navigation`. That is a
  slot load (`DefineButton2_2719` to `2722` on(release), lines 15 and 32), Re-Load (`DefineButton2_2791` on(release), lines 4-7), a zone picked on the world map, which sets `Krin.sectionIn`
  first (`DefineButton2_4155` on(release), lines 4-5), the return from a won battle with no cutscene queued (`frame_219/DoAction.as:73-81`), the end of a cutscene whose `gotoSceneKrin` is
  `Navigation` (`frame_263/PlaceObject2_3466_80` enterFrame, lines 26-33), and the end menu's button (`DefineButton2_2797` on(release), root frame 116). Every value comes from
  `Krin.sectionIn`, which a load restores from the slot (`frame_42/DoAction_20.as:93`, with `sectionIn` in `saveArray1` at line 296).
- Zone line: `klt1 = SYSTEM[9] + sectionIn`, and `SYSTEM[9]` is "Zone " (`frame_41/DoAction.as:76`), so zone 4 reads "Zone 4".
- Name line: `klt2 = ZONES[sectionIn] + ": " + ZONES2[sectionIn]`, with the strings at `frame_41/DoAction.as:123-136`. `ZONES[3]` is "Ivory Line " with a trailing space, so zone 3 reads
  "Ivory Line : The Train". The other six names and all seven subtitles match the port's `ZoneManager.ZONES` character for character.
- Bar: `levelMinProgress` is `questProgress[sectionIn]`, capped at `questHub[sectionIn].progressMax`, and the bar's width is `levelMinProgress / progressMax` of its full width (lines 5-11).
- Stage line: `klt3 = SYSTEM[10] + (questProgress[sectionIn] + 1)` with no cap, and `SYSTEM[10]` is "Stage " (`frame_41/DoAction.as:77`). So a beaten zone 1, at progress 10, shows a full bar
  and "Stage 11".
- The hub art picks its frame from the same variable on the same frame, through `Krin.zoneName[sectionIn]` (line 2 of `frame_181/PlaceObject3_3287_59`'s onClipEvent(load)), so the panel
  always names the hub on screen.
- The world map's zone buttons are the only other readers of these strings. They show `ZONES[sectionID]` and `ZONES2[sectionID]` as their tooltip's title and body (`DefineButton2_4155`
  on(rollOver), lines 3-4), and the port's map has no tooltips yet.

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
