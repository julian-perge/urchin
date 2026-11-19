# Decoded original algorithms

Ground-truth behavior decoded from the ActionScript in `source_files/action_script/`, kept here so reimplementation details never have to be re-derived. Converted values assume the original 30 fps
timeline.

## krinMelee - the melee run/strike/runback (frame_42/DoAction_4.as)

Implemented in `scripts/entities/character_visual.gd` (`play_melee`, `_animate_melee`). `FighterPresenter.melee` (`scripts/battle/fighter_presenter.gd`) gives the doll the target's
rig position on every frame and the target's half-width.

Constants (frame 42 globals):

| Name | Value | Meaning |
|---|---|---|
| `krinBoltTime` | 60 | base step divisor: step = distance / 60 per frame |
| `krinBodyMove` | 10 | melee movement multiplier on that step |
| `krinMeleeAttackCD` | 15 | frames from strike start to impact (0.5 s) |
| `krinMeleeAttackEndCD` | 15 | frames the end counter counts before the runback goto, the impact frame included, so the goto comes 14 frames after impact |

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
3. **Runback.** 14 frames after impact the code forces `gotoAndPlay("runback")` (168-188, ends in `gotoAndStop("stand")`) and reverses movement with an eased return:
   `spdXCoEFFER = min(1.45 * goRat, 1)` - fast leave, exponential settle home; position snaps to home once `relX` falls to 0.000001 or less. This note used to say 15 frames. The end counter
   runs on the impact frame itself, because lines 87-95 come after the block that raises the flag, so its count of 15 ends 14 frames later. That is 29 frames after strike start, the frame on
   which the last frame of `Attack_Upper` and of `Attack_Stab` jumps to `runback` by its own script (`DefineSprite_166_MODEL1/frame_107` and `frame_137`). `Attack` has no such script at
   frame 167 and would reach `runback` through `attack2` one frame later. The movement runs in the fighter clip's own `onEnterFrame` while `inner` plays the labels (lines 67-135), so a hit, a
   stun or a death on the doll during the runback doesn't stop it sliding home. The settle has no fixed length (this note used to say ~18 frames): the same four cases as the dash simulation, with the zero half-width case taken at 300 px, put the
   doll within 1 px of home after 4 to 22 frames of runback, and snap it home after 15 to 72.

Attack label selection: each move's `addNewMove` param 12 (`Ability.animation_label`). Shock moves play "cast" instead (param 12 is unused for them).

## krinBoltMake - the missile projectile (frame_42/DoAction_4.as, ~line 137)

Implemented in `scripts/battle/projectile.gd` (`Projectile`), fired from `scripts/battle/battle_scene.gd` (`_fire_projectile`).

Constants (frame 42 globals):

| Name | Value | Meaning |
|---|---|---|
| `krinBoltTime` | 60 | step divisor: step = distance / 60, fixed at spawn (never recomputed against the bolt's live position) |
| `krinBoltSpeed` | 1 | initial `SpeedConst` |
| `krinBoltIncrease` | 1.15 | `SpeedConst *= 1.15` every original frame - the bolt ACCELERATES exponentially, it does not move at constant speed |

Sequence:

1. **Spawn.** The bolt clip attaches at `shooter.x, shooter.y - 15` with `_alpha = 0`, fading in `+10/frame`, which is opaque after 11 frames in Flash's 1/256 steps (see "A clip's `_alpha` in 1/256 steps"). `boltx`/`bolty` (the spawn position) are cached once and used as the
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
until issue 47 deleted that branch, since no move sets `[20]`. **DONE (2026-08-19)**, see `tasks/old/2026-08-18-missile-projectile-art.md`: distinct clip art per `projectileModel` name (e.g. `Krin.Firebolt`) is extracted and rendered untinted; `KrinTrail`'s real 33-frame fade-in/fade-out pulse (not a generic tinted circle+line) plays alongside it, tinted by the move's real `colortobe` value; and a miss now flies the bolt fully past the target off-screen instead of always resolving as a hit on arrival, matching `strikeSuccess`'s hit/miss branch (`Projectile.did_hit` gates whether `reached_target` frees the bolt immediately or lets it keep flying). Both the bolt and the trail come from a generated scene of their own under `scenes/battle/vfx/`, which `Projectile` instantiates by clip name - each one already carries that clip's frames and the registration point the source SWF drew it around, so nothing here positions or scales art at play time (**DONE (2026-08-20)**, see `.superpowers/sdd/2026-08-19-vfx-registration-scenes/`).

The original never removes the impact clips it attaches (`"bbb"+counter` in `krinBoltMake`). The port's `ImpactEffect` frees itself when its animation ends, which no player can see.

## "cast" label dispatch and timing (frame_217/PlaceObject2_3389_480 enterFrame, ~line 400-469)

Implemented in `scripts/entities/character_visual.gd` (real MODEL1 label playback, frames 189-219) and `scripts/battle/battle_scene.gd` (`_play_move_event`).

- **Missile:** `colortobe = param 11` is set on `inner` immediately BEFORE `inner.gotoAndPlay("cast")` - the cast-glow tint is active for the whole animation from frame 1 of the label, not something
  faded in/out mid-clip by a script trigger. `sfx_cast` plays at cast start; the actual impact/damage timing is driven by the projectile's own arrival (see krinBoltMake above), NOT by the cast clip's
  elapsed time.
- **Shock:** same `colortobe`/`gotoAndPlay("cast")` call, but the move's own sound, the BOOM clip attach, the camera zoom/shake, and `BAMBAMBAM = true` ALL fire in the same tick as the
  `gotoAndPlay("cast")` call - the doll's cast animation is purely cosmetic follow-through for Shock; the hit does not wait on the clip. The Impact itself comes 1 frame later: the conductor's
  Impact block (`if(_root.BAMBAMBAM)`, line 12) runs before its Dispatch block (line 468) in the same enterFrame handler, so it sees the flag on the next frame. With D as the Dispatch frame, the
  Move result applies at D+1, the Buff tick comes at D+26 and the next Dispatch at D+27, or at D+52 after a tick that did something.
- **Melee and Missile have no such lag.** They raise `BAMBAMBAM` from another clip's `onEnterFrame`: the caster's doll (`frame_42/DoAction_4.as:80`) or the bolt (line 190). AVM1 runs the
  enterFrame code of the newest clip first. Ruffle puts each new clip at the front of its run list (`add_to_exec_list` in `core/src/avm1/runtime.rs`). The dolls are children of `BATTLESCREEN`, which
  frame 217 places after the conductor (`battleClocker`, depth 480, then `BATTLESCREEN`, depth 89, in the main timeline's tag order). The conductor creates each bolt at line 430 by calling `krinBoltMake`, which attaches it with `attachMovie` at `frame_42/DoAction_4.as:140`.
  So both clips are newer than the conductor, their code runs first, and the conductor's Impact block sees the flag on the same frame. This order comes from the SWF's tag order and from Ruffle's
  model of Flash Player. It was not checked in Flash Player itself.
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
  clip, a still-stunned unit is snapped straight back into the `stun2` loop instead of showing an idle pose. Ported by #194 as `CharacterVisual.wear_form` and `wear_own_form` (see "Buff form swap" in the audit table).
- **`outofstun` ends** via MODEL1 frame 295's own `gotoAndStop("stand"); play()` - a one-shot that always falls back to idle, same pattern as `cast`.
- No numeric timing constants gate any of this (unlike `krinBoltTime`/`krinMeleeAttackCD`). It is a value comparison that runs on every `applyChangesKrin` call, for an active unit only
  (line 468). The port compares in `FighterPresenter._show_stun`, against the stun in the `UnitSnapshot` an event states (a `MoveResult`'s `target_after` at its impact, a MOVE event's
  `caster_after_dispatch` when it starts, a `BuffTick`'s `after` when it comes due) and against the unit's own stun at the half-turn's end, and a dead doll keeps its death. It never compares with the unit's own stun before then,
  because the runner resolves the whole half-turn before the replay, so the unit's own stun can already hold a stun from later in it. This note used to say those extra comparisons changed nothing. They started a later stun early, and the flinch at the hit that landed it then left the doll idle for
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
  someone else waits for the caster's `buffTicker`, stats and sort both. That Buff tick works out its damage over time (`frame_42/DoAction_10.as:31`) before its own `applyChangesKrin` (135), so it
  reads the caster's stats from before the buff. `BattleManager._apply_status_effect` leaves `apply_changes` to the end of `execute_move` for the target and to `tick_buffs` for the caster.
- `applyBuffKrin` changes a removed buff's STUN, REFLECT, HEALMOD_PLUS, HEALMOD_MINUS, HEALMOD, IDOT, IHOT, ODOT, FOCUSCHANGE and SILENCED at once (`frame_42/DoAction_10.as:140-149`), and
  its SSWITCH (171), SHIELD (205-222) and the damage, healing and Focus its Buff tick deals (223, 243-251). Its stat changes only go into `changeArray` and `IDMGP` (172-191) and the per-element arrays (229-232), and
  only `applyChangesKrin` turns those into STRENGTHU, MAGICU, SPEEDU, LIFEU, DMG, DMG2, IDMG, IDMG2, IDMGP2, PERU and DEFU (259-339), the fields `executeMove` reads
  (`frame_42/DoAction_8.as:3-60`). The conductor runs `executeMove` (lines 54-69) and the status effect (70-102) before that `applyChangesKrin` (103). So the hit that removes a buff lands
  without the buff's direct fields but with its stat changes: a Shatter that dispels SHATTERBOLT hits a target that is no longer stunned but still takes half damage.
- The port used to walk `buff_slots` in the order the buffs landed, since nothing sorted it, and `_resolve_dispels` recomputed the target's stats before the hit.

## Buff icon row (frame_42/DoAction_10.as `applyChangesKrin`, lines 345-379)

Ported: `StatusBar.refresh_buffs` (`scripts/battle/status_bar.gd`). The row used to be `UnitOverlay.refresh_buffs`, which julian-perge/urchin#67 deleted.

- `applyChangesKrin` redraws a unit's row right after its sort. For each of slots 0 to 6 of `BUFFARRAYK` whose CD isn't 0, it attaches a `KrinBuffShower` (DefineSprite 104) to
  `p<playerID>BAR` at x = (110 + 17 * slot) times 1 for team 1 or -1 for team 2. It sets the clip's `buffCounter` text (edit text 66) to the CD, sends `buffIcon` to the frame named by
  the buff id and tints `buffColor` with the buff element's color. The tooltip title is the buff's `[0]` and its text the buff's `[25]` (the enterFrame handler on `buffColor` inside
  DefineSprite 104). Nothing sorts the row itself, so it shows the first 7 slots in the order the sort left them, and it only changes when `applyChangesKrin` runs for that unit.
- The port draws the row from the `UnitSnapshot` of the last event shown on the unit, so it changes at the impact of each result on the unit, when the unit's own MOVE event starts, when its
  Buff tick comes due, and at the half-turn's end. A buff that a move lands on its own caster waits for the caster's `buffTicker` in the original (`frame_42/DoAction_10.as:135`), and the port
  shows it when that Buff tick comes due, because the `BuffTick`'s `after` is taken once the tick has recomputed the caster.
- The port's row used to sort the slots with turns left again with `sort_custom`, which moved tied buffs once a unit held more than 16 of them and changed the 7 icons it showed in 212
  of 20,000 sorted states. The port's tooltip title also adds the turns left, which the original's doesn't.

- The icon is a frame label, not a number. Each buff registers under its name (`addNewBuffKrin("TWINGUARDIANS", ...)`, `dev/source_files/action_script_curated/frame42/sonny2_addNewBuffKrin.txt:543`),
  and a move names the buff it applies as a string, so `buffIcon.gotoAndStop(buffId)` gets that name and Flash resolves it as a label of the buff icon sheet, DefineSprite 100. `buffs.json`'s
  numeric `id` is only the order of the 470 registration calls and never reaches the sheet. The sheet holds 33 drawings across 400 frames and labels several buffs onto each, so 8 of the 419
  extracted icons, FIRESAM and TWINGUARDIANS among them, share frame 1, a plain filled rounded rectangle. Buff id 0, TWINGUARDIANS, is a real buff. The empty slot is `buff_id: -1`.

## Menu piercing/defense bars (DefineSprite_3142/frame_1)

Implemented in `scripts/ui/menu/menu_math.gd` and `scripts/ui/menu/element_bar.gd`. The numbers are in `dev/converted_json/menu_math.json`, which `uv run convert_menu_math` writes. Value = allocation + ceil(100 + 15 * level), and x = value / (100 + 15 * level), where the average is not rounded.

- Each bar has four layers over a black 13x70 track, and the script sets three heights from the 68 px of the full bar: `bar` = 68 * the quartic `0.016666667 y^4 - 0.25 y^3 + 1.233333 y^2 - 1.9 y + 0.9` of y = x + 1, `gbar` = 0.68 * 15x, and `xbar` = 68 * 0.07 * (x - 1). `bar` and `gbar` are capped at 68 and `xbar` is not. `ybar` is never resized.
- The script colours the shape inside `ybar` and `bar` and the whole `gbar` clip with the element colour. It never colours `xbar`. The layers' own colour transforms then dim `ybar` to 26/256 and `bar` to 77/256, and brighten `xbar` by 100, which keeps its white shape white. A colour set on a clip replaces the clip's transform, so `gbar` is the plain element colour. `gbar` and `xbar` carry a white Glow, blur 9 by 9, strength 1.797, three passes, with the shape drawn over it.
- The Glow is part of the clip, so the clip's colour covers it. The glow of `gbar` is the element colour and the glow of `xbar` is white.
- When x is below 1 the `xbar` height is negative, and Flash flips the clip below its origin. The port draws no `xbar` then. This is a departure from the original that no player can see today: none of the 449 items has a negative piercing or defense, and `equipment.gd` is the only code that changes `save.per` and `save.def` from their start at 0. The tooltip still prints the negative percentage.

## Item looks and icons

- `looks` art keys: `gghhjjuu.looks = "X"` assignments in frame_42/DoAction_16.as after each `createNewItemKrin` (wearable default "NINJA"; id counter jumps at 99/299/499).
- Slot icons: the icon clip (DefineSprite 2064) has one labeled frame per item name; shape 1913 is a clip mask: its first placement, on frame 16 at depth 2, carries clipDepth 15, so stripping it unclips every icon under it (item 69 went from 63x63 to 101x140, see docs/agents/art-extraction.md). It is placed once more later in the clip at depth 1 without a clip. `gotoAndStop(ITEMNAME[id])`.
- The name the game shows, and the label the icon lookup uses, is `KrinLang.ENGLISH.ITEMNAME[id]` (`frame_1/DoAction.as`). `frame_42/DoAction_16.as:23` writes it over the item record's own name
  at load. All 316 entries are unique and no two sanitize to the same key. `swf_items.json`'s `internal_name` is a different, dev-facing field that the icon path never reads, and it disagrees
  with the real names (id 311 is "Punisher Gloves" in `ITEMNAME` and "Warden's Grasp" in `internal_name`). The 133 ids with no `ITEMNAME` get no icon in the original either.
- Four items have no label on 2064: Tool (id 1) and Golden Crowbar, Golden Pipe and Golden Axe (ids 681-683). Their `.tres` files have no `slot_image`, so `ItemSlot` draws the three Golden items' `sprite_image` and draws nothing for Tool. Item 0, `None`, has a label, a blank frame.

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
onClipEvent). This is read from the AS, not seen in a live run of the SWF. The port gives a row only to a unit whose `origin` is COMPANION, so no guest gets one there either, and `_populate_stance_rows` builds none in battle 2 whoever fights there, as the original's load handler hides the bar. When the rows
show still differs: the port keeps a companion's row up for the whole battle, while the original shows the bar only at Decisions, so it never appears in the four battles won during their
opening lines (210, 409, 504 and 508).

## New Game and Load Game (root frames 56 to 93, `Krin.dataMode`)

Ported: `main_menu.gd` opens on New Game and Load Game, asks for the name before the slot list, lets New Game use any slot with the hover warning, takes the name as typed, doesn't
save when the game starts, goes on to the first fight when it starts, and sends every Back to its first screen. In the game the player is "Sonny" whatever the typed name is.

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
- So no player sees button 3121 or its tooltip. 3182's hit shape 3119 spans x -86.1 to -43.9 px and y 487.6 to 529.8 px at root frame 181 (`Navigation`, depth 132), and the stage
  is 800 by 575 px with `Stage.scaleMode` "exactFit" (`frame_1/DoAction.as:4515`), so no off-stage area ever shows. 3182's on(release) is the only `gotoAndStop("data")` in the export.
  The `data` label is frame 32 of sprite 3142 (KRINMENU). It places 3121 at depth 9, scaled 4.37 by 3.75, and moves and scales the two side panels at depths 5 and 7. 3121 shows the
  Store's sell texts, but it is not the Store's sell slot 3015: its on(rollOver) shows `MENU[3]` over `MENU[4]` + " €" + `round(price / 3)` or `MENU[5]`, where 3015 shows
  `ceil(price * 0.15)`, and its on(press) calls `krinHandleData(1)` instead of selling. The port's save slot list is root frame 74 (`dataMenu`, buttons 2719 to 2722), a different
  screen, so it shows no sell tooltip. The Steam build matches: its button 2913 has 3182's script and place, and its button 3206 has 3121's script and place in frame 32 of sprite
  3239 (#432).
- So a new game in a used slot leaves the old save on disk until its first save, and a game over before then reloads the old save, because Re-Load reads the slot back
  (`DefineButton2_2791` on(release), lines 2-7).
- Start (`DefineButton2_2770` on(release)) sends the player to CS_INTRO when `Krin.tutorOn` is true and to CS_INTRO2 when it is false, and sets `gotoSceneKrin` to "IntroSeq" or
  "IntroSeq2" first. CS_INTRO2 is root frame 293 and sets `gotoSceneKrin` to "IntroSeq2" again (`frame_293/DoAction.as:1`). When the clip ends, the cutscene controller jumps to
  `gotoSceneKrin` (`frame_263/PlaceObject2_3466_80` enterFrame, line 33). IntroSeq2 is root frame 166. Frames 166 to 179 have no script, and frame 180 sets `Krin.BattlePick` to 100
  and `progressFight` on, then loads the battle (`frame_180/DoAction.as:2-3` and 9). So a new game with the Tutorial off plays CS_INTRO2 and then fights battle 100 as a Story fight.
  The port's `ZoneManager.request_new_game_fight` hands the Battle screen that pick, `ZoneProgression.FIRST_STORY_FIGHT`, with `cutscene_before` set to "CS_INTRO2". With the Tutorial on,
  `ZoneManager.request_tutorial_fight` hands it the pick below instead.
- With the Tutorial on, which it is by default (`frame_93/DoAction.as:7` sets `Krin.tutorOn` each time the settings frame opens, and `DefineButton2_2769` on(release) toggles it), Start plays
  CS_INTRO and the clip's end goes to IntroSeq, root frame 151. Frames 151 to 164 have no script. Frame 165 sets `Krin.BattlePick` to 2 and `progressFight` off, puts moves 21 and 22 on bar
  slots 0 and 1, sets `cutsceneSequence` to "CS_INTRO2" and loads the battle (`frame_165/DoAction.as:2-3` and 6-9). `ZoneManager.request_tutorial_fight` puts
  `ZoneProgression.TUTORIAL_MOVES` on the port's bar and hands the Battle screen `ZoneProgression.TUTORIAL_FIGHT`: battle 2, not a Story fight, with `cutscene_before` set to "CS_INTRO".
- A win over battle 2 runs `frame_219/DoAction.as` like any win. `progressFight` is off, so Quest progress stays 0. The frame puts `startSkill1` and `startSkill2` back on bar slots 0 and 1
  when `BattlePick` is 2 (lines 65-69). Then it stops every sound and jumps to `cutsceneSequence` instead of Navigation (lines 73-81). The clip's end sets `cutsceneSequence` back to 0
  (`frame_263/PlaceObject2_3466_80` enterFrame, line 32) and goes to IntroSeq2 as above. The victory screen only opens on Navigation's load (`frame_181/PlaceObject3_3142_175`
  onClipEvent(load), lines 3-7). Its frame holds the money (`DefineSprite_3142/frame_9/DoAction.as:43`), the XP (the `expWorkOut` calls in the three `PlaceObject3_3002` clips) and every
  `awardAch` call (`DefineSprite_3142/frame_9/DoAction_2.as`). Drops are rolled when the battle loads (`frame_201/DoAction.as:233-267`), and the player only takes them on that screen
  (`DefineButton2_3012` on(press)). So a Tutorial win pays and unlocks nothing. This is read from the AS, not seen in a live run. The port's `BattleSettlement.settle` returns early for
  battle 2 after it puts `TalentTree.STARTING_MOVES` back, and sets `next_fight` to `ZoneProgression.FIGHT_AFTER_TUTORIAL`, which is `FIRST_STORY_FIGHT`. The Battle screen opens no
  victory screen for such a win and requests that fight through `ZoneManager.request_fight`.
- Frame 180 also sets `soundPlayCounter` to 3, `soundModeKrin` to 0 and `bangStart` on (lines 4-6). So the first fight plays `_music_battle2`, entry 3 of `soundPlayArray`
  (`frame_41/DoAction_2.as:11`), and starts it at full volume at once, cutting off the track before it (`frame_42/DoAction.as:85-91`, `addSound` with "Music" and 2). The Tutorial's
  battle 2 sets `soundPlayCounter` to 1 and `bangStart` on the same way (`frame_165/DoAction.as:4-5`), so it plays `_music_battle1` at full volume, and battle 100 after it plays
  `_music_battle2` at full volume again. The port carries each counter as the `music_rotation` of `ZoneProgression.TUTORIAL_FIGHT` and `FIRST_STORY_FIGHT`. The Battle screen hands it
  to `AudioManager.set_first_fight_music()` when the Cutscene ends, and `AudioManager.bang_start` is `bangStart`: the next battle track that starts uses it up, and it waits while the
  sound is off, as frames 165 and 180 set it without `addSound`. Before this ([#384](https://github.com/julian-perge/urchin/issues/384)) a headless run on 2026-11-11 played
  `_music_menu1`, `_music_battle1` and `_music_menu2` for the menu, battle 2 and battle 100, all faded in. `test_battle_scene.gd` checks both paths.

## Starting state (new game)

- Class-select buttons (DefineButton2_2735/2736/2737 = Bio/Hydro/Psycho) seed `moveMatrix[0..1]` and `moveMatrix2[0..1]` with the class starting moves.
- `equipArray0 = [0, 11, 0, 4, 8, 5, 0]` (frame_180): White T-Shirt, Levo Jeans, Proverse All Stars, A Broken Pipe.
- The same frame also resets `StatSets0 = [5, 6, 5, 3, 0]` (`frame_180/DoAction.as:8`), which is exactly that gear's bonuses (life 5, strength 6, magic 5, speed 3). The class buttons had already
  added the 19 level-1 points, split by class ratio, onto `StatSets0` through `assignPointsStart` (`frame_42/DoAction_15.as:57-78`), and `statPoints` stays 0 (`frame_41/DoAction_2.as:79`), so
  the class split is thrown away and a new character holds only its gear bonuses. Every route from class select passes through frame 180 before battle 100, and the tutorial route
  fights battle 2 on the way (`frame_165/DoAction.as`), still holding the class split because frame 180 has not run yet. The port's `PlayerSave.new_game` keeps only the split's rounding residue, and `GameData.new_game` calls
  `PlayerSave.start_story`, which sets the frame 180 gear and allocation. `ZoneManager.request_tutorial_fight` calls `PlayerSave.enter_tutorial`, which sets the frame 42 gear
  (`frame_42/DoAction_17.as:50-51`: no White T-Shirt, `StatSets0 = [5, 6, 5, 3, 0]`) and adds the class split again. A Tutorial win calls `start_story` before battle 100. Both read the gear and allocation from
  `dev/converted_json/starting_state.json`, which `just convert-starting-state` reads out of the two frame scripts.
- Sell-back = `ceil(price * 0.15)` (DefineButton2_3015).
- Each party member's looks are fixed. `frame_42/DoAction_17.as:7-84` is top-level frame 42 code that sets `SkinSet`, `HairSet` and `GSet` for every character, and nothing else writes them, so the
  original has no appearance screen. The port keeps each character's looks in `Party`'s `model` entry.
- The class name under each class-select card is a text field that the original fills from `KrinLang` `CLASS[0]` to `CLASS[2]` at run time (`frame_84/DoAction.as:2-4`), so the port draws it as a Label.

## Battle presentation per animation type (frame_217/PlaceObject2_3389_480 enterFrame, ~line 400)

The battle engine dispatches on `addNewMove` param 10:

- **Melee**: caster `gotoAndPlay("run")` + `krinMelee(...)` (see above). Param 12 = the attack label. The move's sound plays AT IMPACT (`soundToMake` in the BAMBAMBAM handler). A Melee miss is
  silent: the dispatch sets `missToMake` to undefined (conductor line 407), and the miss branch plays `missToMake` (conductor line 107).
- **Missile**: caster plays **"cast"** (param 12 is the PROJECTILE clip, not a caster label), `colortobe` = param 11 tints the cast glow, `sfx_cast` plays, `krinBoltMake` spawns the projectile (speed
  `krinBoltSpeed = 1`, stretching trail `_xscale += 8.3 * step`); impact/sound/boom land when the bolt arrives. A Missile miss plays `sfx_magicmiss` (conductor line 415).
  `ability_two[20]` (is_multi_target) fires one bolt per living enemy, but no move sets it (see krinBoltMake above), so this branch is dead content.
- **Shock**: caster plays **"cast"** with the `colortobe` tint; param 12 is UNUSED. The move's own sound plays immediately, the BOOM clip (param 13) attaches at the target at once, the camera zooms
  (`zoomPause = 1`), the screen shakes (`GridShaker`, when param 9 speed modifier >= 0), and `BAMBAMBAM` is raised at once. The Impact
  that the flag triggers runs 1 frame after the Dispatch (see the Shock entry under the cast animation above). Shock also sets `missToMake` to undefined (conductor line
  447), so its miss would be silent too, but a Shock move never misses: the hit roll is skipped for Shock and `strikeSuccess` is set true (conductor lines 360 and 385).

Element colors (`elementColorArray`, frame_41/DoAction_2.as - menu bars AND Floating numbers): Physical `C40000`, Magic `FB95C8`, Ice `68CBF4`, Fire `FF6600`, Lightning `FFCC00`, Earth `856B47`, Shadow
`664D80`, Poison `508349`; heals `66FF00`.

Floating numbers (`KrinNumberShow`, frame_42/DoAction_7.as): digit sprites (NumberFixer/NumberSetter clips) colored by the move's ELEMENT, `gotoAndPlay("critical")` variant on crits (`perKSuccess`),
special "miss"/"shield" frames. Crits also fire `GridShaker` (frame_42/DoAction_8.as). Every damage hit that gets past the shield draws its number twice: `executeMove` calls `KrinNumberShow` at
`frame_42/DoAction_8.as:80` and again at 84, or at 137 in heal green under sswitch. Each call attaches a new clip at the next depth (`frame_42/DoAction_7.as:37`, 75-79), so a normal hit shows two
identical numbers and an sswitch hit shows a green number over an element-colored one.

Ported: `FloatingNumberLayer` is `KrinNumberShow` and `FloatingNumber` is one `NumberFixer`, played from what `extract_floating_numbers` writes.
It writes the count of the depths as `slots`, and the digit spacing and the first digit's offset under `digits`, to `assets/ui/battle/floating_number/floating_number.json`, and `FloatingNumberLayer` reads them from there.
The details the port keeps:

- The number sits on the target rig's `_x`/`_y` with no offset (lines 38-39). `dressChar` lowers only a MODEL5 unit's doll inside its rig, so its number stays on the rig.
- `KrinNumberShow` attaches the number to BATTLESCREEN (line 37), so it zooms and shakes with the fighters. The port's layer is a child of `BattleScreenClip`, next to `Battlefield`.
- The digits sit 19 apart in the holder's own units, the first at `-19 * (digits - 2) / 2 - 10` (lines 3, 34-35 and 56), which leaves them half a unit left of the rig's origin.
- Only the digits' and the MISS word's `KN` fill takes the color, through `setRGB` (58-59 and 66-67). SHIELDED has no `KN` child and is never tinted.
- A number of 0 or less draws nothing (line 8). The digit loop drops any fraction, so a number between 0 and 1 attaches a `NumberFixer` that plays its label with no digits.
- The depth cycles over 20 depths, 1620 to 1639, so a 21st number replaces the one still at its depth.
- The port draws one number per result, in the color the original leaves on top (ADR 0005).
- A Buff tick draws one number too, always in `normal`, which "The Buff tick" below has.

## What executeMove does on each branch (frame_42/DoAction_8.as)

Ported: `BattleManager.execute_move` returns a `MoveResult` that states which branch ran and what it left, and `FighterPresenter`, `CombatLogPanel` and
`Achievements.collect_battle_counters` read that instead of working it out again.

- **Full Damage** works out the hit (lines 24-64) and compares it with the target's SHIELD (65-70).
  - A shield bigger than the hit takes all of it, which is a Shield block. SHIELD goes down by the hit, the target's `shield` clip and `sfx_shield` play, and `KrinNumberShow` draws
    its `shield` frame (70-76). Nothing after the shield check runs: no flash, no `hit` label, no hit voice, no life bar update and no AchVal1. A crit has already shaken the grid by
    then, and played `Angry_Dux` or `Angry_Roald` when Veradux or Roald is the caster (28-43). The result is HARM with amount 0 and `shield_took_all` set, and
    `FighterPresenter.show_result` plays the clip and `sfx_shield` and draws SHIELDED for it (see "The Shield clip" below).
  - Otherwise the shield's value comes off the hit and the shield empties (79-81). A shield exactly as big as the hit soaks it this way, which is not a Shield block. The rest of
    the branch plays a hit that did nothing, with no number, because `KrinNumberShow` only draws a number above 0 (`frame_42/DoAction_7.as:8`).
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
- Any other category does nothing in `executeMove`. Shatter Bolt is the only such move, and its status effect still lands after it. The conductor applies a move's status effect after `executeMove()` whatever its category (conductor lines 70-102). Shatter Bolt's proc chance is 2.4, so every hit applies `SHATTERBOLT`, a unique Ice debuff with stun contribution 1 and duration 2 (`frame_42/DoAction_6.as:1716-1719`, `frame_42/DoAction_10.as:1629-1636`), and the move stuns its target. Frost Terror is the unit that uses it. The port's `BattleManager.execute_move()` returns a `STATUS_ONLY` result with no amount for such a category and applies the status after it (`test_shatter_bolt_stuns_its_target`).
- The life bar redraws in `executeMove` (150, 187, 198 and 248) and again in `applyChangesKrin` (`frame_42/DoAction_10.as:342`), which the conductor runs on the target after the
  move's status effect (conductor line 103). So a move leaves the bar on the life after that recompute, which is the life `MoveResult.target_after` holds. The recompute moves life when the
  move lands, or dispels, a buff that changes max life: Edge Of Death's EDGEOFDEATH takes 85% off.
- The STUN checks for the `hit` label read the target as the hit lands, before the move's own status effect, so `MoveResult.target_stunned` is read then too. Shatter Bolt's stun comes
  after its own hit. The stun pose changes in the recompute after the strike (`frame_42/DoAction_10.as:468-481`), so `MoveResult.target_after` is taken after that recompute, with the life.

## The Result flash (DefineSprite 3416 `BATTLEFLASH`)

Ported: each `FighterPresenter` plays its own `ResultFlash` (`scripts/battle/result_flash.gd`), and `scenes/doll_body.gdshader` draws its filter over the doll's CanvasGroup body.
`extract_result_flash` writes each label's color and frames and the glows' blurs and strengths to `assets/ui/battle/result_flash.json`, and both read them from there.

- The clip has 46 frames at 30 fps, places nothing and is all frame scripts. Its labels are `none` on frame 1, which stops, `hit` on 2, `heal` on 17 and `focus` on 32. Each label puts its
  filter on at its first frame and 4, 8 and 12 frames after it, takes it off 2 frames after each, and 14 frames after it takes it off and stops on `none`
  (`DefineSprite_3416/frame_2` to `frame_46`). So the filter shows on the impact's frame and the next, 4 times over 14 frames.
- On means `krinChangeColor(inner, "Hit")`, a color transform that changes nothing and so clears a buff tint such as Poison, and `inner.filters` set to the label's filter. Off puts back
  `DFTC` and `DFTF`, the unit's `characterColorState` and `characterFilterState` when the flash started. The last frame puts back the unit's color state at that moment instead. The port
  draws neither state, so off is the doll's plain look.
- Every label's filter is a white inner glow (blur 100, strength 10) and then an outer and an inner glow (blur 10, strength 1) in the label's color, all at quality 1: 16763904 (#FFCC00)
  for `hit`, 10092288 (#99FF00) for `heal` and 3407871 (#33FFFF) for `focus` (`frame_42/DoAction_3.as:117-130` and 162-168). The white glow covers a px fully wherever at most 90% of the
  100 px box around it is doll, which is every px of a doll, so the doll draws white with a rim and a halo in the label's color.
- Only `executeMove` calls it (see the branches above), so a Shield block, a heal of 0, a miss, a status-only move and a Buff tick never flash. Each call points the one clip at its own
  target, so a move that hits several units flashes only the last, an Original bug that ADR 0005 has the port fix.

## The Shield clip (DefineSprite 2675)

Ported: `extract_shield_clip` renders every frame of the clip into `assets/ui/battle/shield_clip/`, and each `FighterPresenter` plays its own `ShieldClip` (`scripts/battle/shield_clip.gd`)
through `play_shield_clip()`.

- The fighter rig, DefineSprite 2676, places the clip as `shield` at its origin. The clip's `onClipEvent(load)` runs `this.swapDepths(1000)`, which puts it over the `inner` doll
  that `dressChar` attaches at depth 0 (`frame_217/DoAction_2.as:18`). BATTLEFLASH filters `inner` alone, so a Result flash never covers the clip, and `dressChar` scales and lowers a
  MODEL5 `inner` alone (19-24), so the clip keeps the rig's size and origin. The halls place the right side's rigs with an x scale of -1, so the clip mirrors with them.
- The clip has 20 frames at 30 fps. Frame 1 runs `stop()` and shows nothing. Frame 2 places the bubble, sprite 1709, a circle of radius 50 px with a #66FFFF glow, at the rig's
  origin, and BOOM_SPARK, sprite 1712, at (40.55, 3.65). A color transform turns the bubble white on frames 3, 5 to 6 and 8 to 9, and its alpha falls from 230/256 on frame 11
  to 0 on frame 20, so frame 20 shows nothing. The spark draws on frames 2 to 18.
- `play()` leaves the playhead on frame 1 until the next frame, so the bubble shows one frame after the impact. That reads AVM1 as stepping every timeline before a frame's scripts
  run, and no player has measured it. After frame 20 the playhead wraps to frame 1, and its `stop()` holds it there. A `play()` while the clip plays changes nothing.
- `executeMove` plays it on a Shield block with `sfx_shield` (`frame_42/DoAction_8.as:73-74`). When a shield soaks a whole Buff tick, `buffTicker` calls `play()` on the clip of `IDKT`,
  with no sound (`frame_42/DoAction_10.as:72`). Only `executeMove` declares `IDKT`, as a parameter, and no script assigns it. In `buffTicker` it is undefined, so the call reaches no clip,
  and the original draws SHIELDED with no bubble. ADR 0005 counts that as an Original bug, and the port plays the clip on the unit that ticked, through `FighterPresenter.show_tick`.

## The Buff tick (`buffTicker`, frame_42/DoAction_10.as:14-136)

Ported: `CombatUnit.tick_buffs` returns a `BuffTick`, `BattleRunner._execute_action` logs it as a BUFF_TICK event, and `FighterPresenter.show_tick`, `battle_scene.gd` and `CombatLogPanel` show it.
Conductor lines below are in `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as`.

- **When it runs.** Once after each action of a caster that is alive when the action starts, which the conductor decides at the Dispatch with `usedBuff` (lines 330-337). A move's tick runs 25 frames
  after its Impact (112-128). A caster that was stunned, could not pay or passed ticks on its Dispatch frame (511-530 and 565-584). A caster that its own move killed has no tick (118). The port
  logs an event for every tick that runs, even one that changes nothing, because the `applyChangesKrin` that ends `buffTicker` (`frame_42/DoAction_10.as:135`) redraws the unit, and a buff can wear
  off there.
- **One total.** The tick adds the healing term, `DOTTICKERARRAY[8] * HEALMOD_PLUS * HEALMOD_MINUS * IHOT` held at 0 or below, to the damage of each element,
  `ceil((1 + IDMG2) * IDMGP2 * IDOT * (DOTTICKERARRAY[i] * (100 + plevel * 15) / DEFU[i]))` (17-40). So healing and damage net: 666 damage and 300 healing make a total of 366. Then each buff's `CD`
  counts down, and each buff that reaches 0 comes off (41-58). That is after the total is worked out, so the damage of a buff that runs out at this tick still counts. Then SSWITCH flips the sign
  of the total (59-62). A total above 0 hurts and a total below 0 heals.
- **The shield.** The shield only reads a total above 0. A shield strictly bigger than the total takes all of it: SHIELD falls by the total and SHIELDED draws (64-71). The call that would play
  the Shield clip (72) reaches no clip, so the original shows no bubble (see "The Shield clip" above). Otherwise the shield comes off the total and empties (76-84). A shield exactly as big as the
  total takes the second branch and leaves a total of 0, a Quirk that ADR 0005 keeps.
- **The number.** One Floating number for a total that is not 0 (85-96): the total in heal green when it is below 0, and otherwise in the color of the element with the strictly largest damage, which
  starts as Physical (25-40). A heal draws before `applyChangesKrin` caps life at its max (305-308), so a unit at full life still draws it. `buffTicker` resets `perKSuccess` first (24), so the label
  is always `normal`. A tick plays no flash and no sound.
- **The wait.** `buffTickChecker` ends as the total, a soaked total included (99). The conductor then raises `BAMBAMBAM` again and restarts its `AttackEndCounter` (lines 122-127), so the next Dispatch
  comes 26 frames after the tick, which is 51 after the Impact of a move, instead of 1 frame after it. A caster that did not move waits 26 frames after its Dispatch frame (511-521 and 565-575),
  unless the tick killed it, which sends the next action on at once. A tick that only moved Focus or only ran a buff out leaves `buffTickChecker` at 0 and holds nothing back. `BuffTick.did_something`
  is that test, and the port's wait and its line in the combat log use it.
- **Focus** moves by `DOTTICKERARRAY[9]` and stays between 0 and `FOCUSU` (100-108). It draws no number and does not count towards the wait, so a buff such as Re-Focusing ticks with no number.
- **A death** (109-134) sets LIFEN and FOCUSN to 0 and plays `dead`. The port logs a DEATH event after the tick's event, and the death plays on the tick's frame.
- **The unit afterwards.** `BuffTick.after` is taken after `applyChangesKrin`, so it states max life, life, Focus, stun and the buff slots once the buffs that ran out have come off. A buff that cuts
  max life, such as Judge's Hammer or Iricin, gives max life and life back together when it runs out (`frame_42/DoAction_10.as:280-296`). The bar keeps the max and the fill it had until the tick and
  takes both from it. That recompute also gives life back to a unit that the same tick killed, and the original leaves the unit that life. The port does the same, but a tick that killed states life 0.

## A death (MODEL1's `dead` label and LifeBarSmoother, DefineSprite 57)

Ported: `CharacterVisual._play_death` and `FighterPresenter.die`. Frame counts below start at the death, which is the Impact that kills or the Buff tick that kills.

- The doll plays MODEL1's `dead` label, frames 313 to 371 (`frame_42/DoAction_8.as:104-107` and 208-211 for a move, `frame_42/DoAction_10.as:113` for a Buff tick). Frames 313 to 360 draw at
  full alpha. On 361 to 371 the label's own colour transforms fade every part from 233/256 to 0, and frame 371's script removes the doll before that frame is drawn
  (`DefineSprite_166_MODEL1/frame_371/DoAction.as`), 58 frames after the death. Frame 360 runs `_parent.shadower._visible = false`, which hides nothing, so the Ground shadow goes with the doll on frame 371 (see "Doll ground shadow" in the audit table).
- `lifeBarUpdate` plays the death voice and attaches LifeBarSmoother to the unit's bar with `deadNow` set (`frame_42/DoAction_8.as:345-347`). The clip's frame 18, 17 frames after the
  death, removes the buff icons `bshr0` to `bshr9` and sends the bar's `inner` clip (DefineSprite 3407, the name and the life and focus numbers) to its empty `third` frame. From the next
  frame, its frame 38 takes 5 off the whole bar's `_alpha` every frame and jumps back to `dead` (frame 37). The jump lands in the same frame, so the step runs on every frame, not on every
  second frame. Flash keeps `_alpha` in 1/256 steps (see "A clip's `_alpha` in 1/256 steps"), so each step takes 13/256 off: 100, 94.921875, 89.84375, and so on to 3.515625 on frame 36 and
  -1.171875 on frame 37. Frame 38 finds the alpha not above 0 and hides `inner2`. So the fade takes 20 frames, the bar draws nothing from frame 37, and it is hidden on frame 38, 38
  frames after the death. Traced runs of the web build measured this frame by frame, with the same values in the Flash 14 debug player and in Ruffle 0.7.1
  (`references/traced_runs/death_fade_web_flash.txt` and `death_fade_web_ruffle.txt`, #383). The Steam build logged the same values in the Flash 14
  debug player. `StatusBar._advance_death` steps with `FlashAlpha`, and
  `test_the_bar_fades_and_hides_on_the_frames_the_traced_run_measured` checks every logged frame.
- `lifeBarUpdate` does none of that when the bar's rounded percent hasn't changed (295-298), so a unit killed from under 0.5% life dies with no voice and no fade. ADR 0005 counts that as
  an Original bug, and the port plays both on every death.

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

Ported: `RadialMenu` plays the enterFrame below once per SWF frame. It tests the mouse against the clip's box and builds each orb from its `thingo` button's up-state rect times the clip's scale, all of which `extract_battle_screen` writes to the `radial_menu` entry of `battle_layout.json`.

- Root frame 217 places the Radial menu clip, DefineSprite 3382, at 1.0383 scale, so every orb sits 1.0383 times further from the clicked unit and is 1.0383 times its button's 24.42 px. Nothing in the ActionScript sets the clip's scale.
- Each `thingo` button draws shape 2434, a thin black ring 21 px across, in its up state and shape 2435, 22.5 px across, on over and down, at depths 113 to 127 over the icons. The pass button 3383 draws the same three shapes, so `extract_pass_button` writes where each state's ring and each `thing` icon sit in the clip to the `orbs` entry of `pass_button.json`, and the orbs share the pass button's PNGs. The `thing` icon sits up to 0.35 px off its button's centre, and the port places the icon, its disc and its count on the `thing` placement, as the original does.
- The box is the union of `thingo0` to `thingo7` in their up state and `thing0` to `thing7` at frame 1, about 128 px square on the stage. It counts an empty slot's hidden `thingo` too, because Flash counts a hidden child in its parent's bounds. Once the ring shows a move's icon, an icon wider than its button widens the original's box at that slot, by up to 21 px in the clip's own px. The port keeps the frame 1 box.

- A click shows the clip at alpha 0 (`frame_217/DoAction_3.as:46-48`), and it gains 50 per frame (enterFrame lines 32-35).
- While `this.hitTest(_root._xmouse, _root._ymouse)` is false the clip loses 10 alpha per frame and hides at 0 or below, with no grace (lines 48-61). In Flash's 1/256 steps each loss is 26 steps (see "A clip's `_alpha` in 1/256 steps"), so the alpha reads 89.84375, 79.6875 and so on, and the clip hides on the 10th frame, 0.33 s at 30 fps.
  `hitTest` with no shape flag tests the clip's bounding box, so the gaps between orbs and the unit inside the ring count as over it.
- While it is true, alpha goes straight back to 100 (line 64).
- An orb darkens only for a bad target or a cooldown (lines 15-29). The buttons on the orbs, `DefineButton2_3374` to `3381`, call `addMoveForPlayer` with no gate of their own, so a darkened orb
  still answers a click with its refusal message.
- The darkening is the orb's `bfilter`, DefineSprite 2241, a black disc 23 px across. It is at 75 alpha on the two frames the ring fades in and 85 from then on (lines 16 and 42). Flash stores 85 as 217/256. A cooldown
  also writes its turns left to the orb's `ACD` field, edit text 2245, and an empty string once it is 0 (lines 23-28). Ported: `RadialMenu` draws the disc at 85 alpha and the count, both
  from `extract_ability_icons`, and a click on any refused orb shows `MoveLegality.message()` in the Combat text banner. Not ported: the ring also empties every `ACD` while the mouse is
  away (lines 52-56).

- A release on an orb casts at once. The orb buttons' on(release) calls `addMoveForPlayer` (`DefineButton2_3374`, for example), which takes its battle branch when `menuMode` is off. The
  cursor pick-up, `UITmouseHold`, is the Abilities window's alone (see "Talent tree, its tooltips and the respec" below). The port casts on click too.

## The ability icon's disc (DefineSprite 2427, `moveColor`, #439)

- From frame 15 on, the icon sheet, DefineSprite 2427, places DefineSprite 2244 (shape 2243, #262626) at depth 1 as `moveColor`, under the clip mask at depth 3. It places it once and
  keeps it to frame 985. Its load script runs `new Color(this).setRGB(_parent.KNcolor2)` (`DefineSprite_2427/frame_15/PlaceObject2_2244_1`), and setRGB replaces the colour and keeps the
  alpha. The "Empty" frames, 7 to 14, place the same sprite at depth 4 with no name and no script, so an empty socket's disc stays grey. "None" and "Empty2" show no disc.
- Each owner sets `KNcolor2` right after its `gotoAndStop`, to the `elementColorArray` entry of the move's element, `KRINABILITYB[id][0]`: the orbs
  (`frame_217/PlaceObject3_3382_500` load, line 15), the pool and the ring (`DefineSprite_3142/frame_25/DoAction.as:51-57` and 75-81), the tree
  (`DefineSprite_3142/frame_25/PlaceObject3_3100_153` load, lines 51-57), and the held icon (`DefineButton2_2437` on(press)). The pass button's icon also calls setRGB itself
  (`frame_42/DoAction_11.as:112-120`). A passive tree node's `ID` is 0, and move 0's element is Physical. Each of the 479 move rows names one of the eight elements.
- A throwaway Probe measured this in the Flash 14 debug player. A `KNcolor2` set in the same script as the `gotoAndStop` tints the new disc, because the load script runs after
  that script. A clip that goes from one move's frame straight to another, forward or back, keeps the same disc and its first colour. A clip that passes through "Empty" or "Empty2"
  gets a new disc in the new colour.
- So the orbs, the pool, the tree, the held icon and the pass button always show the current move's colour: the orbs are new each battle, the pool rows are attached again on each
  refresh, the held icon goes to "Empty2" or "None" on each drop, and the pass button sets its colour on each pick. A ring socket that takes an ability on top of another keeps the
  first colour until it empties or the menu clip enters "skills" again. The ring, DefineSprite 3109, is on KRINMENU frames 25 to 31 only. `AbilityIcon` draws the icons, and
  `abilities_window.gd` keeps each socket's colour.
- Most icons cover all of the disc but its anti-aliased rim. `extract_ability_icons` measures how much of the disc's alpha the art leaves showing: median 1.3%, from 0.9%
  (Superconductor) to 71.5% (Ghost State).

## Required target buffs (frame_42/DoAction_11.as)

Ported: `Ability.required_buff_element` and `required_buff_count` carry fields 23 and 24, and `MoveLegality.refusal` returns `TARGET_STATUS` when the target falls short, so a click on the orb says so in the Combat text banner.

- When the player picks a move, the original refuses it with "The target's status does not meet the requirements of this move." if the target has fewer than `KRINABILITYB[24]` active buffs
  of element `KRINABILITYB[23]` (lines 60-64, counted by `checkBuffsOnUnit` at 129-146).
- Only two moves set them: the four Shatter ranks need 3 Ice buffs (`frame_42/DoAction_6.as:852-892`), and Corruption, the Psychological starting move, needs 1 Shadow buff (1607-1618, with
  the fields at 1613-1614). In the converted JSON they are `ability_two`'s `23_secondary_element_type` and `24_required_buff_count`.
- The AI never checks them: `checkBuffsOnUnit` is only called from the player's pick.

## The Combat text banner (DefineSprite 2852 `KrinCombatText`)

Ported: `CombatTextBanner` (`scripts/battle/combat_text_banner.gd`) plays it from `assets/ui/battle/combat_text.json`, which `extract_combat_text` writes, and `battle_scene.gd` shows the
player's own failed moves in it, and "You cannot move yet" for a click outside a Decision.

- Root frame 217 places it at depth 630, at (400, 148.5), above the orb ring at 500 and below the speech box at 634, with a red Glow filter (blur 10 by 5, strength 1) that turns its
  translucent white band pink and haloes its text. Root frame 181, Navigation, places the same clip with the same Glow at (400, 48.95) and depth 1610, above `KRINMENU` at 175 and below
  the Info card at 1651. Ported: the Hub's `CombatTextBanner` in `scenes/game.tscn`, with `placement` set to `hub`. It shows the hotbar's messages, such as the respec button's.
- Frame 1 runs `stop()` and shows nothing. `gotoAndPlay("GO")` jumps to frame 2, which copies `combatTexter` into the text field through `inner.combatText`
  (`DefineSprite_2852/frame_2/DoAction.as`). Frames 2 to 12 slide the inner clip up from 10 px below its place and fade it in from 0 to full, frames 13 to 125 hold it, frame 125 empties the
  text (`DefineSprite_2852/frame_125/DoAction.as`), and frames 126 to 136 slide it back down as it fades out. The clip then loops to frame 1 and stops, 4.5 s after the GO frame at 30 fps.
- A pick with a Refusal (`frame_42/DoAction_11.as:125`) and the player's own failed move call `gotoAndPlay("GO")`, which starts the banner over with the new text. The click listener's
  "You cannot move yet" calls a bare `play()` instead (`frame_217/DoAction.as:19-26`), which changes nothing while the clip is playing, because only frame 2 copies the text.
- The click listener is a `Mouse.onMouseDown` that the battle frame adds (`frame_217/DoAction.as:18-27`), so it hears every left-click, one that a button or a unit also answers
  included. It shows `MENU[37]` (`frame_1/DoAction.as:245`) unless `InBattle` is false, `timerWait` is 0, `winCondition` is below 0 and `speechDone` is true, the test the conductor's
  decision block makes (lines 589-591), so a click during the fight, the second before the first Decision or a spoken line shows it. The port reads the click in `battle_scene.gd`'s
  `_input`, before any control takes it.
- Not ported: the listener once the battle is decided. Its test shows `MENU[37]` while `winCondition` is 0 or above (`frame_217/DoAction.as:21`), and the conductor sets `winCondition`
  as the deciding half-turn ends, after its moves have played (lines 194-261). The original removes the listener only once blacker5's frame 85 has sent the root to the result, on
  `winCombat` (`frame_219/DoAction.as:72`), `loseCombat` (`frame_230/DoAction.as:4`) or the arena's end (`frame_253/DoAction.as:1`), so a click during the closing fade still shows
  `MENU[37]`. The port's runner decides the battle before the half-turn that decided it is replayed, and from that moment a click shows nothing, through the replay and the fade
  (julian-perge/urchin#170).
- The conductor writes its failure strings only when `mCaster.playerID == Krin.playerNumber`: Focus and then Health, so Health wins when both fall short (lines 477-488), and the stun
  (lines 538-542). AI units and Companions never show one.
- The text field is edit text 2849, one line of 12 px black centered text in DefineFont3 65, the bold `_sans` Device font. Flash lays the line out 2 px inside the field's bounds, which the
  inner clip places at (-374.5, -9.8), so the line starts at (-372.5, -7.8) and runs 744.95 px.
- Not ported: the text's own share of the glow. A Label cannot blur one, and the outline other screens use in place of a glow reads far heavier than the faint halo around 12 px text, so the
  port draws the text plain. The band's share is baked into its art.

## Turn order and queued heals (frame_217/DoAction_2.as, frame_42/DoAction_4.as and DoAction_11.as, the conductor)

Ported: `BattleRunner._team_select` writes each unit's `team_adder` once per full turn, and `advance_half_turn` builds the queue and runs the AI in `team_adder` order. It also adds the
player's Heal estimate through `BattleAI.heal_guess` before any AI unit decides. `battle_scene.gd` calls `advance_half_turn` with the player's last pick, or with `{}` after a pass or when
the Heroic timer runs out with no pick. On Easy and Normal it calls it on the frame after the pick or pass, and on Heroic 5 frames after it (see "Heroic decision timer").

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

Ported: on Heroic, `battle_scene.gd` gives the player `BattleRunner.BATTLE_TIME_LIMIT / BattleScreenClip.fps()` seconds of `_process` time, and when it runs out it takes the player's last
pick, or a pass when there is none. A pick or a pass sets the time left to the clock's `pick_delay` in `battle_layout.json`, 5 frames, which `extract_battle_screen` reads from
`addMoveForPlayer` and the pass button, so a later pick or pass replaces it (#443). On Easy and Normal,
and on Heroic once a half-turn ends with the player's unit dead, it waits for the player and `BattleClock` shows the whole ring.

- `BattleTime = BattleTimeLimit = 120` (`frame_217/DoAction.as:1-3`). The conductor adds 1 to `BattleTimeNow` once per frame, and only while `turnBasedKrin` is false and the player's team is
  moving (conductor lines 593-596), so the window is 120 frames, 4 s at 30 fps.
- `turnBasedKrin` is true on Easy and Normal (`frame_201/DoAction.as:65-79`), so only Heroic has the timer. On the other two the clock waits at `BattleTimeLimit - 0.000001` until the player
  picks (conductor lines 639-642).
- At `BattleTimeLimit - 1` the AI allies decide (conductor lines 674-698), and at `BattleTimeLimit` the half-turn starts whether or not the player has picked (conductor lines 769-792).
- Picking a move jumps the clock to `BattleTimeLimit - 5` (`frame_42/DoAction_11.as:98-101`), and once the player's unit dies the conductor sets `turnBasedKrin = true` (conductor lines
  200-202).
- Until the half-turn starts, `InBattle` is false, so the player can pick again or pass. The target click that opens the menu checks `InBattle`, `timerWait`, `winCondition` and
  `speechDone`, not `moveChoosen` (`frame_217/DoAction_3.as:18`), and `krinAddMove` files a second pick or a pass in the same `MoveArrayFINAL` box as the first pick
  (`frame_42/DoAction_4.as:28-33`), so the last one replaces the others. Each one jumps the clock back to `BattleTimeLimit - 5`. The pass button's release does not touch
  `krinToMove`, so after a pass the button keeps the pick's icon and its "Click to cancel this ability." text until the fight swaps the text and the player's own action hides the icon.
- Running out is a pass. Every slot starts the battle holding move 0 (`frame_217/DoAction_2.as:313-318`) and each dispatch writes move 0 back for its caster (conductor lines 470-473), so
  a player who never picked passes. The pass button, DefineButton2_3383 (`krinToMove2` on the root timeline), also jumps the clock to `BattleTimeLimit - 5` (release lines 9-12).
- The clock is `battleClocker` (DefineSprite 3389), placed at (400, 507.25) behind the pass button. Its two half-dials in DefineSprite 3386 turn with
  `BattleTimeNow / (BattleTimeLimit / 2)` (`DefineSprite_3386/frame_1/PlaceObject2_3385_2` and `PlaceObject2_3385_6`, line 2), and none of its sprites holds a text field, so it shows no number. The port shows it as `BattleClock`, one render of the lit ring
  for each `BattleTimeNow` from 0 to `BattleTimeLimit`, which `extract_battle_screen` writes.

## Battle speeches (frame_217/PlaceObject2_3389_480 enterFrame, lines 794-870)

Ported: `BattleRunner._drain_speeches` picks the lines, names each speaker, with `BattleRunner.NARRATOR_NAME` for slot 0, and makes the endGame check after each batch.
`battle_scene.gd` waits `START_WAIT_FRAMES` before the opening lines, `_play_speech` shows each line for its `timeToSay` seconds, and `_input` handles Space through
`BattleRunner.hard_skip` and `AudioManager.stop_effects`. `_play_speech` drives the `SpeechBox` scene and the speaker's bubble, as the last bullet describes.

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
- The box places itself for each line: x 473.3 when the speaker's `teamSide` is 2 and x 21.8 otherwise, y 460.7 for both (lines 819-828). It writes the line into `inner.combatText` and the
  speaker's `playerName` into `inner.combatTextName`, and sends the face clip `inner.inner2`, DefineSprite 2978, to the frame labelled with that name (lines 829-831). 11 speakers of the
  records have no label in that clip: Metabii, Frost Terror, Frost Lord, Cult Leader, Tunnel Beast, Shunny, Bunny, Flower Zombie, Nostalgia, Doctor Klima and Versu the Corruptor.
  `gotoAndStop` with a missing label does nothing, so their lines show the last face. The port shows an empty face well instead, by the user's choice on #156. The speaker's own `speech` clip, 57 frames, plays over their head (line 842).
- The box fades at 5 alpha a frame, in Flash's 1/256 steps (see "A clip's `_alpha` in 1/256 steps"), so it passes 100 on its 22nd frame in and is clear on its 20th frame out. It sets the music to `100 - _alpha / 1.2` percent every frame, about 16.7 percent when it is fully up
  (`PlaceObject2_3367_634` enterFrame, lines 2-12 and 19-22). `nextSpeechKKK` turns true when `timeX` reaches `timeSpeechKKKUP`, which starts the fade out, and the next line only waits for
  that flag, so it starts while the box is still fading. A "Press SPACEBAR to Skip" hint, DefineSprite 3359 holding MENU[53], pulses above the box and fades with it.
- `speechDone` stays false until the last line ends, and the whole decision block waits for it (conductor lines 591-793), so neither the clock nor the AI's picks nor the half-turn start
  move. Target clicks wait too (`frame_217/DoAction_3.as:18`), and the pass button queues the pass but only commits it once speech is done (`DefineButton2_3383` on(release), lines 4-7).
  A click meanwhile shows `MENU[37]`, "You cannot move yet..." (`frame_217/DoAction.as:19-26`). The block also waits for `timerWait`, which starts at 30 frames when the battle loads
  (onClipEvent(load), line 6), so the opening lines start a second in.
- A pass that shows nothing sets `speechDone` and checks the phase entry just passed, `phases[phase - 1]`, for `endGame`, taking its `winOrLose` (lines 862-870). That happens
  once the last line of each batch is done, or straight away when none plays. A battle with no lines at all never gets the check (lines 794-796), but every battle with an endGame
  entry has lines. 210, 409, 504 and 508 push their only phase entry, flagged endGame, as `phases[0]` (`frame_42/DoAction_14.as:1093` for 504), so each is won as soon as its
  opening lines are done, before anyone fights. 109, 201 and 212 flag `phases[3]`, `phases[1]` and `phases[3]`, so each is won once the next phase's opening lines are done.
- The box sits at x 473.3 for a team 2 speaker and at x 21.8 otherwise (lines 819-828), sends a child clip to the frame named after the speaker (831) and plays the speaker's own `speech`
  clip (842). It fades in and out by 5 alpha a frame, as above (speech box enterFrame lines 5-12 and 19-22).
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

Ported: once CS_CUT5 ends, `game.gd`'s `_on_victory_proceed` opens `EndingScreen` (`scripts/battle/ending_screen.gd`), and its OK! builds a new hub through
`_reload_hub`.

- The first win of 513 sets `afterCut = "CS_CUT5"` and `gotoSceneKrin = "endMenu"` (`frame_219/DoAction.as:51-55`). Proceed autosaves when autosave is on, stops every sound and plays the
  cutscene (`DefineButton2_3004` on(release), lines 4-11).
- When the cutscene ends, its fade clip sets `soundModeKrin` and `soundPlayCounter` to 0 and goes to `endMenu` without starting any music (`frame_263/PlaceObject2_3466_80` enterFrame, lines
  15-19 and 33). Only `overMap` and `Navigation` get `addSound("Music", 1)` there (lines 20-31). The port's `_on_victory_proceed` (in `game.gd`) calls `AudioManager.reset_music_rotation()` when any
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

## CS_INTRO (root frame 263)

Ported: `CutscenePlayer.play("CS_INTRO")` shows `CsIntro` (`scripts/cutscenes/cs_intro.gd`) in place of a clip, with the same fade and `finished`. `extract_cs_intro` writes the gradient
and `assets/cutscenes/cs_intro.json` for it. The Tutorial plays it: the main menu's start button calls `ZoneManager.request_tutorial_fight` when the Tutorial option is on, `ZoneProgression.TUTORIAL_FIGHT` names it as
its `cutscene_before`, and the Battle screen plays it before the fight.

- The Start button opens the Tutorial on it (`DefineButton2_2770` on(release), lines 2-11). Root frame 263 places the gradient, DefineShape 3475, at depth 1 and the four edit texts 3474,
  3473, 3472 and 3471 at depths 2 to 5. The texts' variables are `introText1` to `introText4`. Each text has a Glow filter (blur 3, strength 10, black) and a `DropShadow` filter (blur 8,
  distance 2 at 45 degrees, strength 1, black). The frame also places the timer sprite 3470, the SKIP button 3468 and its text 3469, the subtitle text 3467 and the fade clip 3466.
- The frame's script runs `stop()` and sets `introText1` to `introText4` to `MENU[86]` to `MENU[89]` of `KrinLang[KLangChoosen]` (`frame_263/DoAction.as:2-5`). `KLangChoosen` is "ENGLISH"
  (`frame_1/DoAction.as:4512`). Frames 1 and 41 both build the English table, with the same four strings (lines 294-297 of each).
- The fields bake in text as their `initialText`, which the script replaces. Only the first differs from its MENU string: "One month ago, Sonny wakes up on the ship..." against "One month ago. Sonny
  wakes up on the ship." The other three bake in the same words as `MENU[87]` to `MENU[89]`. Edit text 3467 shows nothing, because no script sets its variable, `subText`.
- DefineSprite 3470 draws nothing and plays no sound. Its last frame, frame 401, runs `_root.cutSceneEnd = true` and `stop()` (`DefineSprite_3470/frame_401/DoAction.as`). The fade clip
  starts opaque and loses 5 alpha points a frame until `cutSceneEnd` is true. Then it gains 5 a frame, and at full alpha it goes to `gotoSceneKrin` (`frame_263/PlaceObject2_3466_80`
  enterFrame). In Flash's 1/256 steps (see "A clip's `_alpha` in 1/256 steps") the first fade is 20 frames and ends at -1.171875, and the fade to black from there is 22. The timer runs under the first fade, so the original leaves about 420 frames after it starts.
- The port holds the lines for the timer's 401 frames at 30 fps, which is 13.37 s, after its fade-in, as it plays a clip after the fade-in. So it runs about 20 frames longer than the original.
  A press of SKIP ends the hold at once, as it ends a clip, and a press during the fade-in skips the hold.
- The gradient is a radial gradient from (30, 36, 38) at its center to black. The shape is a little bigger than the Stage, from -6 to 804 px by -4 to 584 px, and the render keeps the part
  inside the Stage.
- The fields allow wrapping, but each MENU string fits on one line, so the port draws one Label for each. A Label cannot blur. The glow is an outline half as wide as its blur, and the
  shadow is one hard copy of the text moved by its distance along its angle. Their strength and the shadow's blur are not drawn.

## The SKIP button on every cutscene (button 3468)

Ported: `CutscenePlayer` places the button and its text from `assets/cutscenes/skip_button.json`, which `uv run extract_cutscene_skip` writes, and a press ends the cutscene.

- Root frame 263, the frame of CS_INTRO, places button 3468 at depth 77 and the "SKIP" text, edit text 3469, at depth 76. Frame 449 removes both. So every root frame from 263 to 448 shows them, which
  covers all seven CS_ labels, and all seven place them in the same spot: the text at (675.55, 545.75) and the button, scaled 2.63 across and 0.89 down, at (759.55, 554.95).
- The button has no art. Its one record draws shape 291, a 30 px square, in the hit-test state only. So its hit area is 79 by 27 px at the bottom right of the stage, and the player sees only the text. The
  text is white, 12 px and right-aligned in the bold `_sans` Device font, which the port draws as a Label.
- Release calls `stopAllSounds()` and sets `cutSceneEnd` (`DefineButton2_3468` on(release)). The fade clip 3466, placed at depth 80 above the button, then fades to black and jumps to `gotoSceneKrin`
  (`frame_263/PlaceObject2_3466_80` enterFrame, lines 9-33). That is the same place that the clip's own last frame sends it, because that frame sets `cutSceneEnd` too (`DefineSprite_4153/frame_2424/DoAction.as:1`
  for CS_CUT5). The port's press stops the clip and its audio, and then runs the fade out, `finished` and the free that the end of the clip runs.
- The fade clip has an enterFrame handler only, and nothing stops the button while the cutscene fades in, so a press in that first 0.67 s counts. The release handler stops no clip, so the original's picture plays on
  under the fade out and only its sound stops. Both are read from the AS and not confirmed in a live run. The port starts the clip with the fade-in, as the original does, stops it on an early press, and holds the last frame of a clip that it stopped (#51).
- The cutscene sprite plays from the frame that places it, under the fade clip's fade-in: the fade clip only lowers `_alpha` while `cutSceneEnd` is false, and the CS_CUT5 sprite has no script before
  frame 2424 (`DefineSprite_4153`). The port first faded in over an empty video, which showed the battle under it, or the Victory screen after Proceed, for 0.67 s before the clip started. A black rect
  under the video now stands in for the original's own root frame, which shows nothing of the battle.

## The Cutscene camera (DefineSprite 3478, and 3645, 3812, 3962 and 4041)

Ported: `extract_cutscenes` bakes it into each clip. `cutscenes.camera_view` computes the animation's placement, and `write_cutscene_swf` writes it as one PlaceObject2 move per frame into the wrapper.

- Each animation of CS_INTRO2 and CS_CUT1 to CS_CUT5 places one Cutscene camera on every frame. CS_CUT1 and CS_CUT3 share 3812. All five clips run the same script
  (`DefineSprite_3478/frame_1/DoAction.as`), which hides the clip and calls `camControl()` on its first frame and on every `onEnterFrame`.
- `camControl()` sets the animation's `_xscale` to 100 * 533 / the Cutscene camera's `_width`, and `_yscale` to 100 * 300 / its `_height`. The clip draws only shape 3477, whose bounds are
  10660x6000 twips, so the zoom is 1 / the Cutscene camera's scale on each axis. Then `_x` = 266.5 - the Cutscene camera's `_x` * x zoom and `_y` = 150 - its `_y` * y zoom. These are absolute, so
  they replace the wrapper's own (269.75, 152.45) offset of the animation. The point (266.5, 150) is the centre of the wrapper's 533x300 clip mask.
- `parentColor.setTransform(camColor.getTransform())` copies the Cutscene camera's color transform onto the animation every frame. A Cutscene camera with no color transform gives the identity. Five of the six
  animations open with their Cutscene camera multiplying red, green and blue by 0, so they fade in from black. CS_CUT5's Cutscene camera has no color transform on its frame 1.
- The Cutscene cameras never rotate. The zoom runs from 0.65 (CS_CUT5) to 4.32 (CS_INTRO2), and on frame 240 of CS_INTRO2 the Cutscene camera sits at scale 0.428 around (-108.35, -81.25), a 2.34x zoom.
- Under the wrapper, at root depth 1, every cutscene frame shows shape 3475, a dark full-stage shape. It shows around the 533x300 box and wherever the animation leaves the mask transparent. Each clip is the whole
  800x575 stage with every root layer where the root places it. Five wrappers sit at (133.5, 137.5) px, and CS_CUT5's wrapper 4154 sits at (140.55, 141.55), 7 px right and 4 px down (#411).
- Measured in a Traced run of the web build in the Flash debug player (#411), which logged the Cutscene camera and the animation on every frame up to CS_INTRO2 240, CS_CUT4 860 and CS_CUT5 1200
  (`references/traced_runs/cutscene_camera/camera_web_flash.txt`). On all 2297 frames, the Cutscene camera holds the placement of the animation's current frame when `camControl()` runs, so frame N shows the
  Cutscene camera of frame N, with no one-frame lag. The wrapper positions above are the ones the run read. Each `CAM` line holds, in order: the label, the animation's `_currentframe`, the Cutscene camera's `_x`, `_y`,
  `_width`, `_height`, `_xscale` and `_yscale`, the animation's `_x`, `_y`, `_xscale` and `_yscale`, its color transform as ra, rb, ga, gb, ba, bb, aa, ab, the wrapper's `_x` and `_y`, and the depths of the wrapper and the animation.
- Flash reads the Cutscene camera's `_width` and `_height` in whole twips, and `cutscenes.camera_view()` uses the exact scale. So the extractor's zoom differs from the game's by at most 0.13%, and its translation
  by at most 3 twips (0.15 px). That is under a pixel, so the extractor keeps the exact scale.
- The same run drew the stage with `BitmapData.draw(_root)` on CS_INTRO2 frame 240, CS_CUT4 frames 533, 590, 650, 761, 810 and 860, and CS_CUT5 frames 300 and 1200. Against frame N of the clips, outside the
  SKIP text, the mean difference is 1.7 to 2.5 of 255 and the 99th percentile 13 to 38, which is antialiased edges and Theora compression. Frames N-1 and N+1 score the same or worse. The captures, with the clip
  frame and the difference beside each one, are in `references/traced_runs/cutscene_camera/`.
- `resetStage()` on unload sets the parent back to identity. Nothing in the port needs it, because the clip ends with the cutscene.

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
- The PRISON orb plays CS_CUT1 before the fight when `BattlePick` is 109 and `progressFight` is on (`DefineButton2_3188` on(press), lines 18-24). It sets `afterCut` to "CS_CUT1" and
  `gotoSceneKrin` to "LOADBATTLESCENE", calls `stopAllSounds()` and goes to the CS_CUT1 label. The clip's last frame sets `cutSceneEnd` (`DefineSprite_3928/frame_621/DoAction.as:1`), and
  the fade clip then goes on to the battle without touching the music (`frame_263/PlaceObject2_3466_80` enterFrame, lines 15-33). `progressFight` is on for the first fight at 109 and off
  for a Boss replay (line 11), and a loss changes no progress, so every attempt at 109 plays the clip and a replay plays none. No other orb plays a cutscene. The port's
  `ZoneProgression.pick_story_battle` sets `cutscene_before` to "CS_CUT1" for a Story fight at 109 and leaves it out of a Boss replay, and the Battle screen plays it (#48). This is read
  from the AS and not confirmed in a live run.

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
  on(rollOver), lines 3-4). The port's `zone_map.gd` shows them through `GameTooltip.show_title_and_body`, for locked zones too, because the rollOver reads no `canUse`.

## Post-battle hint (`krinNavTutSpeech`, frame_42/DoAction_21.as:26-76)

Ported: `scripts/game.gd`'s `show_battle_hint` shows the card, and `convert_battle_hints` writes `dev/converted_json/battle_hints.json` from the table. The Victory Window's Proceed and the close X of the Inventory or the Store call `show_battle_hint`.

- `Krin.progressSpeech[battle]` holds `[NAVTITLE2[n], NAVTEXT2[n]]` for six battles, in order: 100 to 104 get n 0 to 4, 504 gets 5, and 33 gets 6 (lines 26-61). `NAVTITLE2` and `NAVTEXT2` have
  entries 0 to 5, so the entry for battle 33 holds two undefined values. No battle 33 exists in `battles.json`, and the port skips that entry.
- `krinNavTutSpeech` does nothing when `Krin.tutSpeecher` is true. Otherwise it sets the flag, and when `progressSpeech[previousBattleSp]` has two entries, it shows the card with those two
  texts, sets `PauseForScreen` and sets `previousBattleSp` to 0 (lines 62-76). It reads neither the Tutorial option nor the player's level.
- `tutSpeecher` goes false on every win, with `previousBattleSp` set to the battle's id (`frame_219/DoAction.as:70-71`). It goes true on the first call, and on every load of a save
  (`frame_42/DoAction_20.as:85`). So a win shows at most one hint, and a load drops a hint that a win left waiting.
- Two buttons call it. Proceed calls it when the win did not level the player up and no cutscene or map follows (`DefineButton2_3004` on(release), line 27). Button 2853 calls it on press,
  after it hides the menu and shows the hub art (`DefineButton2_2853` on(press), line 4). Sprite 3142 places 2853 at the `inventory` and `shop` labels only, which makes it the close button
  of those two Windows. After a win that levelled the player up, Proceed calls nothing, so the hint waits until the player next closes the Inventory or the Store with 2853. A new win or a
  load ends the wait. This is read from the AS and not confirmed in a live run.
- The port's `show_battle_hint(battle_id)` keeps `tutSpeecher` as `_hint_used`, a field of the Hub. The port builds a new Hub after every win and every load, so the field is false in each
  new Hub, which is the reset on a win. A load never calls the method, which is what the set-on-load does. After a level-up win, the Hub's Victory Proceed keeps the won battle's id, and the Hub calls `show_battle_hint` when the close X of the Inventory or the Store is pressed (#325). After a win with no level-up, Proceed calls it at once (#241). Only that close button calls it, as 2853 does: the hotbar buttons that toggle the Windows do not.

## Hub fade-in (clip 2837, frame_181/PlaceObject2_2837_1660)

Ported: `scripts/ui/hub_fade.gd` is the last child of `scenes/game.tscn`, and `extract_hub_fade` writes its numbers, colour and rect to `assets/ui/hub_fade.json` (#371).

- The Navigation frame places sprite 2837 at depth 1660, above KRINMENU (3142) at 175 and the Info card (2848) at 1651. The sprite is shape 333, black, scaled to cover the stage from
  (-3.77, -3.74) to (801.83, 573.31), so a strip of about 1.7 px at the bottom stays uncovered.
- `onClipEvent(load)` sets `_alpha = 99` and `frameGo = undefined`. `onClipEvent(enterFrame)` takes 15 off `_alpha` while it is above 0. In Flash's 1/256 steps (see "A clip's `_alpha` in 1/256 steps") the
  black shows at 98.828125, 83.59375, 68.359375, 53.125, 37.890625, 22.65625 and 7.421875, and clears on the 7th step. At 30 fps that is about 0.23 s. A win leaves the battle on full black and opens the Victory Window on Navigation's load, so the Hub and the Window fade in together.
- When `frameGo` is set, the handler adds 15 a frame up to 100 and then calls `_root.gotoAndStop(frameGo)`. No script in the web build writes `frameGo`, and the placement has no instance
  name to reach the clip by, so that branch never runs and the port has no fade-out (`label_xref.json` lists the jump as unresolved).
- A zone button on the World map jumps to Navigation (`DefineButton2_4155` on(release), lines 4-5), so the Hub fades in after each zone pick. The port keeps the Hub open under its
  map, so `zone_map.gd` emits `zone_picked` and the Hub calls `HubFade.restart()`. Every other jump to Navigation builds a new Hub in the port.

## Stun, Silence and Reflect

- A unit with `STUN` not 0 does nothing on its turn. The conductor runs a move only when `mCaster.STUN == 0` (conductor line 350). The port gates this in `BattleRunner._execute_action()`.
- A move that is a Shock, or any move at a stunned target, hits without a roll (conductor line 360, `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as`). The port's `_accuracy_roll()` does the same.
- Silence blocks any move with a focus cost, `cost * SILENCED == 0`. The AI's filter and the player's pick use the same test (see "Which moves can be picked" above).
- Reflect is dead code. The full script export has exactly one `REFLECTDMG` reference, the initializer to 0 in frame 201, and none of the 470 buffs has a reflect delta that is not 0. The stat
  exists on `CombatUnit` and does nothing, as in the original.

## Talent tree, its tooltips and the respec (DefineSprite_3142 frame 25)

Ported: `TalentTree`, `AbilityTooltipBuilder` and `Leveling.respec`.

- The learn button is `DefineButton2_3096` on the tree screen. It loops every `PRESKILL` entry of a node and refuses when any of them has rank 0, so a node with several prerequisites needs
  all of them. Each learn takes one skill point (`skillPoints--`).
- A level-up grants one skill point (`skillPoints++` in the victory frame's level-up code, `DefineSprite_3142/frame_9/PlaceObject3_3002_1197/CLIPACTIONRECORD onClipEvent(enterFrame).as:31`), and a new character starts with 5, `preStartSkill` (`frame_41/DoAction_2.as:77-78`). So a respec sets `skillPoints` to `Level - 1 + preStartSkill`.
- The learn button rebuilds `moveMatrix2` from the class's starting moves and every `skillAdderMatrix` entry that is not 0, from node 37 down (see "for..in order over arrays"). It does not keep a running list.
- `krinRemakeTree` builds each node's tooltip in four lines. The header is the rank over the maximum rank and the name, such as `"(2/4)  Vicious Strike"`. For a passive node
  (`CLASSIFY == 1`) the title and each rank's text come from `KrinLang.ENGLISH.BUFFSAY`, not from the buff record, and the cost line is `SKILLAURA`, "Passive Combat Effect". 9 of the 14 passive
  families have a title that is not their family name, for example Marathon is "Endurance". The bottom line names the next tier's level and what it grants, from `BUFFSAY[family + rank]` for a
  passive and `KRINABILITYB[id + rank][17]` for an active. A maxed node shows `SKILLTALENTTIP3`, "This ability is at its maximum tier.". A node with no rank shows `SKILLTALENTTIP2`, "You have no
  points in this ability yet.", and leaves rank 1's text to the bottom line.
- The next-rank text shows a few frames after the rest of the tooltip. The icon's enterFrame sends `KrinToolTipper` to its `GO7` label
  (`DefineSprite_2427/frame_1/PlaceObject2_2241_11/CLIPACTIONRECORD onClipEvent(enterFrame).as:22`). The port shows every line at once. #364 matches the tooltip to `KrinToolTipper`.
- In the Abilities window a press on a pool ability picks it up: `DefineButton2_2437` on(press) sets `UITmouseHold` to the ability and shows its icon on the cursor. A release over a ring
  socket calls `addMoveForPlayer` in its `menuMode` branch, which places the held ability in that socket, or shows `SKILLERROR` when the ring already holds the ability's limit
  (`KRINABILITY<id>[8]`) of copies (`frame_42/DoAction_11.as:1-32`). A release with nothing held empties the socket. `frame_181/DoAction_2.as:10-14` drops a held ability.
  `KrinCreateAbilityMatrix` lists every ability in `moveMatrix2` in the pool, the ones on the ring too. Ported: `abilities_window.gd`'s `_on_pool_row_held`, `_on_socket_pressed` and
  `_input` (#386). Flash runs `on(release)` only on the button that took the press, so the player presses a pool ability and then clicks a socket. The held icon sits where the tooltip clip
  places `inner2`, which `extract_tooltip_look` writes as `held_icon`.
- Ported: `hotbar.gd`'s `_on_respec_pressed`. The Respec button on the hotbar, `DefineButton2_3179`, refuses with `MENU[66]` while an item is on the cursor and does nothing while `PauseForScreen` is set. It costs
  `round(0.7 * respecValue(Level))` euros and refuses with `MENU[42]` when the player has less. Otherwise it sets the skill points as above and the stat points to `givePoints(Level, true)`,
  puts the class's two starting moves back as the only moves, clears the cooldowns, `skillAdderMatrix`, `buffAdderMatrix` and `talentMainArray`, rebuilds `StatSets0` from the equipped
  gear, shows `MENU[67]` in the Combat text banner and opens the `skills` frame of `KRINMENU`. It also counts `respecSet` down from 5 each day, but nothing reads that count, so the original
  never limits respecs (#32). Every message goes through a bare `play()`, so it shows only when the banner is not already up. The port's item on the cursor is an item
  drag, so a drag released on the button is the `MENU[66]` case. The port keeps cooldowns only on a battle's units, so the respec has none to clear. Its `KrinScreen._visible = false` hides the zone screen (DefineSprite 3287), which
  the port hides whenever a Window shows. Its tooltip is `SYSTEM[32]` + ": EUR" + the cost over `SYSTEM[33]`, with the euro sign where this line says EUR.
- Each hotbar button reads `Krin.mouseItem` in its own way (on(release) of each button). Respec (`DefineButton2_3179`), Options (3180), Save (3183), Abilities (3184) and
  Achievements (3153) show `MENU[66]` with a bare `play()` while an item is on the cursor, and check this before `PauseForScreen`. World Map (3177) checks for the item but has no
  `else`, so it does nothing. Inventory (3185) and Quit (3178) do not check. Every hotbar rollOver sets `thereIsASlotSelected`, so `onMouseDown` keeps the item on the cursor
  (`frame_181/DoAction_2.as:8-50`), and Inventory still goes to the `inventory` frame and Quit still quits. Ported: `hotbar.gd`'s `_ready` gives the five refusing buttons
  `_can_drop_item` and `_refuse_item_drop`, and gives Inventory and Quit `_release_with_item`, which opens the Inventory Window or presses Quit unless the hotbar is inert.
  World Map takes no drop. The port has no item on the cursor once the drag ends, so on every button the item goes back to its slot (#436, #437).

## The Abilities hint box and its tutorial steps (DefineSprite 3059, #387)

The hint box on the Abilities frame is DefineSprite 3059 at depth 675. Its
labels are `stable` (1), `level` (7), `part1` (12), `part2` (56), `part3`
(107) and `part4` (151). `extract_hint_steps` reads all of this from the SWF
into `assets/ui/menu/hint_steps/hint_steps.json`.

- **When the steps start.** The clip's onClipEvent(load) runs
  `gotoAndStop("level")` when `_root.Krin.skillPoints + _root.Krin.statPoints
  > 0` (DefineSprite_3142/frame_25/PlaceObject2_3059_675). Otherwise the clip
  stays on `stable`, whose frame 1 script sets `reader` to
  `MENU[43 + random(4)]`. The load runs each time the menu enters the
  Abilities frame, so the prompt shows again on every opening while points
  are left. A new game starts with ability points, so its first opening shows
  the prompt.
- **What each label shows.** `level` sets `reader` to MENU[7], `part1` to
  MENU[8], `part2` to MENU[9], `part3` to MENU[10] and `part4` to MENU[43].
  Each sets `clicker` to MENU[11], "< Click Here >".
- **How a click moves.** Each label places one button over the whole box.
  Buttons 3041, 3047 and 3050 run `gotoAndStop` to `part1`, `part2` and
  `part3` and then `play()`. Button 3053 goes to `part4`, and button 3056
  on `part4` goes back to `stable`, which runs frame 1 again and picks a new
  tip.
- **The glow.** Depth 5 holds the 40-frame box, sprite 3040. `level` places it
  once and every later label only moves and scales it, so it plays on across
  the labels. `part1` to `part3` also animate a bar and an arrow at depths 7
  and 9, with green (#99FF00) Glow filters, toward the tree, the attribute
  points and the action bar. Frames 55, 106 and 150 jump back to their label
  and play, so those labels loop on frames 12 to 54, 56 to 105 and 107 to 149.

## The menu clip's frames (DefineSprite 3142, `KRINMENU`)

- `KRINMENU` sits at stage origin (400.5, 222.4). Frame 1 is the inventory, 9 the victory screen, 16 the store, 25 the abilities window (`skills`), 39 the options (`options`) and 45 the
  achievements.
- The hotbar's Options button, `DefineButton2_3180`, sends `KRINMENU` to `options` unless an item is on the cursor (`MENU[66]`) or `PauseForScreen` is set. Frame 39's script fills the
  rows: Sound, Effects (`Krin.graphics`), Graphics (`Krin.qual`), Autosave, the difficulty and the help text `MENU[34]` (`DefineSprite_3142/frame_39/DoAction.as`). ADR 0011 leaves out
  Effects and Graphics. The difficulty row has no button. Ported: `OptionsWindow` (`scripts/ui/menu/options_window.gd`). Its Sound row
  writes `PlayerSave.sound` and `AudioManager.sound_enabled`, the port's `Krin.sound`.
- The face clip, DefineSprite 2978, holds 40 named portraits: the 5 companions, the player and every named story NPC, such as `Doctor Hedger`, `The Warden` and `Clemons The Deceiver`.

## Where a cutscene goes, and the zone map lines

- After CS_CUT2 and CS_CUT4, which each unlock a zone, `gotoSceneKrin` (frame_219) opens the zone map. After CS_CUT3 it stays on the hub. Ported: `ZoneProgression.CUTSCENE_GOTO_SCENE` and
  `ZoneManager.open_zone_map_on_load`.
- The zone map draws the lines between zones in code, `krinMapper.lineMC` on frame 449, colored by unlock state. Ported: `scripts/zones/zone_map_connectors.gd`. lineMC carries a DropShadow (distance 5 at 45 degrees, blur 2, strength 0.61), which `extract_zone_map` writes to `assets/ui/zone_map/zone_map.json`. The port draws it without the blur.

## A clip's `_alpha` in 1/256 steps (Flash 14 and Ruffle 0.7.1, #383 and #442)

Flash keeps a clip's `_alpha` as a whole number of 1/256 steps. A write stores the whole steps of the new percent, `int(percent * 256 / 100)`, and drops the rest toward 0. A read gives the steps back as `steps * 100 / 256`. So `_alpha = 99` reads back 98.828125, and `_alpha = 85` reads back 84.765625.

- `_alpha += 5` from 0 adds 12 steps a frame (4.6875, 9.375, ...), and `_alpha -= 5` from 100 takes 13 off (94.921875, 89.84375, ...). The same holds for every step that is not a whole number of 1/256 steps: +10 adds 25, +15 adds 38, +20 adds 51, -10 takes 26 off and -15 takes 39 off. Only a step of 25 or a multiple of it, such as +50, is exact. So a fade in from 0 takes more frames than the same fade out from 100.
- Below 0, the drop toward 0 takes one step less: `_alpha -= 5` from 3.515625 gives -1.171875, and `_alpha += 5` from -1.171875 gives 3.515625.
- Nothing holds the value between 0 and 100. `_alpha += 20` from 99.609375 gives 119.53125, and a fade that tests `_alpha < 100` stops there. Flash draws a value below 0 as clear.
- Evidence: a throwaway Probe stepped the `_alpha` of empty clips by +5, +10, +15, +20, +50, -5, -10, -15 and -20 for 80 frames, and replayed the enterFrame logic of each fade below on an empty clip. The web build logged the same 1300 values in the Flash 14 debug player and in Ruffle 0.7.1 (`references/traced_runs/alpha_steps_web_flash.txt` and `alpha_steps_web_ruffle.txt`). The Probe is `references/traced_runs/alpha_steps_probe.as`. It was not kept in `dev/probes`, because it adds clips to the stage and quits the player. The death fade's own runs (#383) agree.
- Ported: `FlashAlpha` (`scripts/flash_alpha.gd`) does this arithmetic, and `test_flash_alpha.gd` checks it against every ALPHA line of the log. Each fade keeps its alpha in steps and its test checks every frame against the FADE line of its own replay:

| Fade | Original | Port | Frames |
| --- | --- | --- | --- |
| Hover ring | `frame_217/PlaceObject3_3394_*`, +20 under 100 while hovered, -5 above 0 | `FighterPresenter.step_ring_frame` | in 6, to 119.53125; out 24 |
| Speech box | `frame_217/PlaceObject2_3367_634`, +5 under 100, else 100, while a line is up; -5 above 0 | `SpeechBox._step_alpha` | in 22, to 103.125, and 100 on the next frame; out 20 |
| Orb ring | `frame_217/PlaceObject3_3382_500`, +50 under 100; -10 off the clip | `RadialMenu._play_frame` | in 2; hides on the 10th frame out |
| Hub fade-in | `frame_181/PlaceObject2_2837_1660`, load 99, -15 above 0 | `HubFade.step_frame` | 7 |
| Cutscene fade | `frame_263/PlaceObject2_3466_80`, placed at 100, -5 above 0; +5 once `cutSceneEnd` is true, and away at 100 or above | `CutscenePlayer.step_fade` | out 20; in 22 from -1.171875 |
| Bolt | `frame_42/DoAction_4.as:161-164`, attached at 0, +10 under 100 | `Projectile._process` | 11, to 107.421875 |
| Death fade | `DefineSprite_57_LifeBarSmoother/frame_38`, -5 | `StatusBar._advance_death` | 20 (see "A death") |

## for..in order over arrays (Flash 14 and Ruffle 0.7.1, #38)

AS2 `for..in` walks an array's keys in the reverse of the order the keys were created. Index order does not matter. Writing to a key that already exists does not move it.

- An array literal, `new Array(a, b, c)`, `push`, and index writes from 0 up all create keys in ascending order, so they walk from the last index down.
- Index writes from the top down walk ascending. Writes in any other order walk in exactly the reverse write order (`2,0,4,1,3` walks `3,1,4,0,2`).
- `new Array(n)` creates no keys, so it walks nothing. `delete` removes a key, and a later write puts it first. On a literal, `splice`, `shift` and `sort` leave a descending walk. `reverse` walks `3,1,4,0,2` for 5 items, so do not assume an order after it.
- An array copied by `for..in` from a literal walks ascending, and a list pushed while walking that copy walks descending again. So each `for..in` and `push` step of a filter chain flips the order.
- That explains the `createNewItemKrin` case in SWF_DIFFERENCES.md: `statUpdater` gets indexes 0 to 4 written in order and walks `4..0`. `statUpdaterP` and `statUpdaterD` are written while walking the literal `Krin.PIU` (`frame_42/DoAction_16.as:14,41-45`), so they get keys 7 down to 0 and walk `0..7`.
- Save loading writes each saved value into the array that is already there (`frame_42/DoAction_20.as:109-115`). Where the key already exists, as in `skillAdderMatrix` and `itemArray`, a loaded game keeps the new-game order. An array that is empty before the load, such as `moveMatrix2` (`frame_41/DoAction_2.as:90`), gets its keys in the order the loop walks the saved copy. The save writes that copy by walking the live array (lines 74-80), so a push-built array gets keys from the last index down and its copy walks ascending. Both players read the copy back from disk in that same ascending order, so the load writes keys from 0 up and the loaded array walks from the last index down again, as in the new game (measured, see the evidence below). No run has loaded a real game save with the Probe. The Probe copies a pushed array through a SharedObject the same way. The arena (`DefineButton2_2704` on(release)) sets `itemArray`, `skillAdderMatrix` and `moveMatrix2` of each arena player to `new Array()` before the load fills them, so the results below are not shown for arena players either.

What it means for the port:

- `AImoveAdder` (`frame_42/DoAction_9.as`): `CDArrayA`, `CDArrayD` and `CDArrayABS` are copied from the unit's literal move lists by `for..in` (`frame_42/DoAction_14.as:113-127,193-206`), so they walk ascending and pool index `i` is the literal's index `i`. `moveFilterA2` and the plain `moveFilterD2` pass through two flips and end ascending, as in `BattleAI`. `moveFilterABS1` (line 50) and the heal-filtered `moveFilterD2` (line 305) pass through one flip and end descending. The focus scan at line 85 walks `moveFilterA0` descending, so `focusSelectNum` ends on the lowest matching index, and a move that restores the caster's own focus sets `playerFocusCheck` to the caster (line 105), which stops the teammate focus moves walked after it. `BattleAI.choose_move` walks all three in the same order (#391), and `test/unit/test_battle_ai.gd` checks each one with a pool of three moves.
- The `moveMatrix2` rebuild (`DefineButton2_3096` on(release), lines 48-58) walks the 38-zero literal `skillAdderMatrix` from node 37 down. `TalentTree._rebuild_known_moves` walks it the same way (#392).
- `KrinCreateAbilityMatrix` (`DefineSprite_3142/frame_25/DoAction.as:37`) draws the Abilities pool rows by walking the push-built `moveMatrix2`, so the rows come newest first: node 0 up to node 37, then `startSkill2`, then `startSkill1`. Ported: `AbilitiesWindow._refresh_pool` walks `move_matrix2` from the end (#395).
- `B3012` (`DefineButton2_3012` on(press), lines 3-9) walks `Krin.itemArray` from 36 down and keeps the last empty slot, which is the lowest empty index. That is `item_array.find(0)`, so the port's slot pick already matches.

Evidence: the Probe `dev/probes/forin.as` builds each kind of array before frame 1 runs, then waits until the root passes frame 42 and walks the game's own arrays. The web build was run under both players, and both logged the same lines. The Steam build was not run with the Probe. The game waits for a click on its language screen (root frame 1) and on CLICK TO PLAY (frames 4 and 5). For these runs a throwaway Probe file, not committed, ran the English button's code (`DefineButton2_298`) and called `_root.play()` on those frames. The FORIN lines of each log are in `references/traced_runs/forin_web_flash.txt` and `forin_web_ruffle.txt`. `literal38_built_by_index` sets `length = 38` and then writes indexes 0 to 37 in order. The Flash log:

```
FORIN	literal5	5	4,3,2,1,0
FORIN	literal8	8	7,6,5,4,3,2,1,0
FORIN	literal38_built_by_index	38	37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
FORIN	literal38	38	37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
FORIN	new_Array_3_args	3	2,1,0
FORIN	new_Array_5	5
FORIN	index_ascending	5	4,3,2,1,0
FORIN	index_descending	5	0,1,2,3,4
FORIN	index_2_0_4_1_3	5	3,1,4,0,2
FORIN	push5	5	4,3,2,1,0
FORIN	push5_then_overwrite_1	5	4,3,2,1,0
FORIN	push5_then_write_7	8	7,4,3,2,1,0
FORIN	literal5_delete_2	5	4,3,1,0
FORIN	literal5_delete_2_rewrite_2	5	2,4,3,1,0
FORIN	literal5_splice_1_1	4	3,2,1,0
FORIN	literal5_splice_insert_at_1	6	5,4,3,2,1,0
FORIN	literal5_shift	4	3,2,1,0
FORIN	literal5_reverse	5	3,1,4,0,2
FORIN	literal3_sort	3	2,1,0
FORIN	copy_of_literal3_by_for_in	3	0,1,2
FORIN	push_in_for_in_order_of_that_copy	3	2,1,0
FORIN	game_Krin.itemArray	37	36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
FORIN	game_Krin.skillAdderMatrix	38	37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
FORIN	game_Krin.PIU	8	7,6,5,4,3,2,1,0
FORIN	game_KRINITEM100.statUpdater	5	4,3,2,1,0
FORIN	game_KRINITEM100.statUpdaterP	8	0,1,2,3,4,5,6,7
FORIN	game_KRINITEM100.statUpdaterD	8	0,1,2,3,4,5,6,7
FORIN	game_KNU1.movesA	3	2,1,0
FORIN	game_KNU1.CDArrayA_built_as_DoAction_14	3	0,1,2
FORIN	game_KNU1.parallelFilterA_built_as_DoAction_9	3	2,1,0
FORIN	game_KNU6.movesA	3	2,1,0
FORIN	game_KNU6.CDArrayA_built_as_DoAction_14	3	0,1,2
FORIN	game_KNU6.parallelFilterA_built_as_DoAction_9	3	2,1,0
FORIN	game_KNU7.movesA	4	3,2,1,0
FORIN	game_KNU7.CDArrayA_built_as_DoAction_14	4	0,1,2,3
FORIN	game_KNU7.parallelFilterA_built_as_DoAction_9	4	3,2,1,0
FORIN	done
```

The save and load order: `__forinSharedObject` in the same Probe pushes 4 values and copies them into `SharedObject.getLocal("urchin_forin_probe").data.saved` by `for..in`, as the save does. It flushes the copy, then copies it back into a new Array by `for..in`, as the load does. Before the copy, it logs what the previous run left on disk and loads that too. The web build ran twice under each player, about 20 seconds per run, and no clicks were needed, because the Probe runs before frame 1. Both players logged the same lines. The second run shows that the copy read from disk walks `0,1,2,3` and the array loaded from it walks `3,2,1,0`. The lines are in `references/traced_runs/forin_saveload_web_flash.txt` and `forin_saveload_web_ruffle.txt`:

```
RUN	1
FORIN	so_disk_saved_copy	none
FORIN	so_source_push4	4	3,2,1,0
FORIN	so_memory_saved_copy	4	0,1,2,3
FORIN	so_memory_loaded_into_new_Array	4	3,2,1,0
RUN	2
FORIN	so_disk_saved_copy	4	0,1,2,3
FORIN	so_disk_loaded_into_new_Array	4	3,2,1,0
FORIN	so_source_push4	4	3,2,1,0
FORIN	so_memory_saved_copy	4	0,1,2,3
FORIN	so_memory_loaded_into_new_Array	4	3,2,1,0
```

## A cost failure at dispatch can still land the move (the conductor, lines 12-111 and 475-585, #39)

When a unit cannot pay for its move at dispatch, the move still lands when a buff ticks on the unit, and nothing is paid. Two players measured it (see the evidence below). Not ported yet: `BattleRunner._execute_move_action` logs MOVE_FAILED and stops (#469).

- At dispatch the conductor binds the move and the units (lines 324-329), and sets its own `moveBammer` to false (line 354) before the cost check (line 355).
- When the check fails (lines 475-531), the conductor files move 0 for the caster and runs `buffTicker` on it. When the tick does something (`buffTickChecker` is not 0) and the caster is alive, it raises `_root.BAMBAMBAM` and writes `_root.moveBammer = true` (lines 513-520). That write goes to `_root`, not to the conductor's own `moveBammer`, which stays false.
- On the next frame the impact block (lines 12-19) sees `BAMBAMBAM` and its own `moveBammer` false. It sets the flag to true and reads `_root.strikeSuccess`, which still holds the last hit roll of any unit (lines 376-385). When that is true, the move runs: the hit sound, the dispel, `executeMove` and the status effect (lines 21-103). When it is false, the target shows "miss" (lines 105-109). The move is not paid and no new hit roll is made.
- When the tick does nothing, the flag stays false. The next action that reaches the impact block through a buff tick, not through a dispatch, runs its own bound move in the same way. Only the stun path (lines 534-585) does that. A dispatch takes that path when its move is 0 (a pass), when the caster is stunned, or when the target is no longer active, because each of these fails the test at line 350. A pass binds move 0 ("None"), whose `executeMove` changed nothing in the runs. A stunned unit, or a unit whose target is no longer active, binds the move it picked, so that move would land, on the inactive target in the second case. Neither of these two cases was run. They are the same lines as the pass.
- `_root.moveBammer` is read nowhere, so the wrong write has no other effect.

How a unit can fail its cost at dispatch in normal play. Both the player's pick (`frame_42/DoAction_11.as:65, 80`) and `AImoveAdder` (`frame_42/DoAction_9.as:52, 87, 128`) check the same Focus and Health costs, so a teammate or the other side must change the unit between its decision and its dispatch:

- The player can learn Disrupt (110). It is a Shock move that costs 20 Focus, can target a Companion (`KRINABILITY110[4] = 1`) and takes 50 Focus (`KRINABILITYB110[9] = -50`, `executeMove` lines 232-242 of `frame_42/DoAction_8.as`). The Companions decide before the player's half-turn starts (conductor lines 643-698), and that side acts in speed order. So a player who is faster than a Companion can drain the Companion after it decided. A Shock always sets `strikeSuccess` to true (line 385), so the Companion's move then lands for free when a buff ticks on the Companion. Run D below measured this.
- In KBR701, North Guardian owns Disrupt (111) and can target South Guardian, and both have speed 10. Read from the code and data, not run. It also needs South to pick a Focus move from his absolute list.
- On Heroic, a late pick can make the other side decide a half-turn early (see "Turn order and queued heals"). The player's side then acts against those units before they dispatch, so a drain or damage below a percent life cost (for example Bloodshed, 8%) can make the picked move fail. Read from the code, not run.
- No move has a flat life cost (`KRINABILITY[6]` is 0 for all 479 moves), and a unit's own buffs tick only after its own action.

Evidence: a throwaway Probe, `references/traced_runs/cost_failure_probe.as`, starts battle 100 on Heroic with no clicks. It refills every unit's life at each AI decision and traces the conductor's own `moveBammer` (`_root.battleClocker.moveBammer`), `_root.moveBammer`, `_root.strikeSuccess` and each `executeMove`. It is not in `dev/probes`, because it changes what the game does. The web build ran under Flash 14 and Ruffle 0.7.1, and both logged the same outcome for each branch. Case C took a different branch in some attempts, as given below. The COST lines are in `references/traced_runs/cost_failure_web_flash.txt` and `cost_failure_web_ruffle.txt`. A `PAID` line comes from `lifeBarUpdate`, which `buffTicker` also calls, so a `PAID` line after `TICK_BEFORE` is not a payment. `moveId` is the move filed in the dispatch slot, which the failure branch has already set to 0, and `focusCost` is the bound move's cost.

- A: after an enemy decides, its Focus is set to -1 and it gets Digitalis. Every attempt landed the bound move for free (Flash 2 of 2, Ruffle 2 of 2, and 8 of 8 in an earlier Flash run whose log is not kept). In this case Gouge (15 Focus) hit the player for 31:

```
DRAIN_A unit=2 clipMoveBammer=true strikeSuccess=true FOCUSN=-1 LIFEN=250 moveId=523 focusCost=undefined frame=725
TICK_BEFORE unit=2 clipMoveBammer=false strikeSuccess=true FOCUSN=-1 LIFEN=250 moveId=0 focusCost=15 frame=726
PAID unit=2 clipMoveBammer=false strikeSuccess=true FOCUSN=0 LIFEN=238 moveId=0 focusCost=15 frame=726
TICK_AFTER unit=2 clipMoveBammer=false strikeSuccess=true FOCUSN=0 LIFEN=238 moveId=0 focusCost=15 buffTickChecker=12 frame=726
EXEC_BEFORE unit=2 clipMoveBammer=true strikeSuccess=true FOCUSN=0 LIFEN=238 moveId=0 focusCost=15 target=1 targetLife=297 targetFocus=100 frame=727
EXEC_AFTER unit=2 clipMoveBammer=true strikeSuccess=true FOCUSN=0 LIFEN=238 moveId=0 focusCost=15 target=1 targetLife=266 targetFocus=100 frame=727
```

- B: as A, with `_root.strikeSuccess` set to false, as a missed earlier roll leaves it. Each attempt showed "miss" and did not run `executeMove` (2 of 2 in each player). Another Flash run also showed this once with no forced value, because the roll before it had missed:

```
DRAIN_B_STALE_MISS unit=2 clipMoveBammer=true strikeSuccess=false FOCUSN=-1 LIFEN=250 moveId=15 focusCost=undefined frame=1176
TICK_BEFORE unit=2 clipMoveBammer=false strikeSuccess=false FOCUSN=-1 LIFEN=250 moveId=0 focusCost=0 frame=1177
PAID unit=2 clipMoveBammer=false strikeSuccess=false FOCUSN=7 LIFEN=238 moveId=0 focusCost=0 frame=1177
TICK_AFTER unit=2 clipMoveBammer=false strikeSuccess=false FOCUSN=7 LIFEN=238 moveId=0 focusCost=0 buffTickChecker=12 frame=1177
MISS unit=2 clipMoveBammer=true strikeSuccess=false FOCUSN=7 LIFEN=238 moveId=0 focusCost=0 frame=1178 who=player1
```

- C: the Companion's Focus is set to -1 and no buff ticks on it, so the conductor's `moveBammer` stays false. The player passes, Digitalis ticks on the player, and `executeMove` runs move 0 with the player as both the caster and the target. Life and Focus did not change (Flash 3 of 3, Ruffle 1 of 3). In the other 2 Ruffle attempts a buff did tick on the Companion, and the Companion's own move landed as in A.

```
DRAIN_C_ALLY unit=3 clipMoveBammer=true strikeSuccess=true FOCUSN=-1 LIFEN=627 moveId=9 focusCost=undefined frame=1554
TICK_BEFORE unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=-1 LIFEN=627 moveId=9 focusCost=0 frame=1556
PAID unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=0 LIFEN=627 moveId=9 focusCost=0 frame=1556
TICK_AFTER unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=0 LIFEN=627 moveId=9 focusCost=0 buffTickChecker=0 frame=1556
TICK_BEFORE unit=1 clipMoveBammer=false strikeSuccess=true FOCUSN=100 LIFEN=297 moveId=0 focusCost=undefined frame=1557
PAID unit=1 clipMoveBammer=false strikeSuccess=true FOCUSN=100 LIFEN=283 moveId=0 focusCost=undefined frame=1557
TICK_AFTER unit=1 clipMoveBammer=false strikeSuccess=true FOCUSN=100 LIFEN=283 moveId=0 focusCost=undefined buffTickChecker=14 frame=1557
EXEC_BEFORE unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=100 LIFEN=283 moveId=0 focusCost=undefined target=1 targetLife=283 targetFocus=100 frame=1558
EXEC_AFTER unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=100 LIFEN=283 moveId=0 focusCost=undefined target=1 targetLife=283 targetFocus=100 frame=1558
```

- D: the Companion's pick is refiled as Dux Electro (20 Focus) and its Focus is set to 60. The player casts Disrupt on it, and the two swap `teamAdder` so that the player acts first. Disrupt takes the Companion to 10 Focus, the Companion fails its cost, Digitalis ticks on it, and Dux Electro hits for 166 or 101 with 16 Focus left (Flash 2 of 3, Ruffle 3 of 3). In the second Flash attempt the player took the stun path, so Disrupt did not run and the Companion paid as usual.

```
SETUP_D_DISRUPT unit=3 clipMoveBammer=true strikeSuccess=true FOCUSN=60 LIFEN=627 moveId=110 focusCost=undefined frame=2169
PAID unit=1 clipMoveBammer=false strikeSuccess=true FOCUSN=80 LIFEN=297 moveId=110 focusCost=20 frame=2171
EXEC_BEFORE unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=80 LIFEN=297 moveId=110 focusCost=20 target=3 targetLife=627 targetFocus=60 frame=2172
EXEC_AFTER unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=80 LIFEN=297 moveId=110 focusCost=20 target=3 targetLife=627 targetFocus=10 frame=2172
TICK_BEFORE unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=80 LIFEN=297 moveId=110 focusCost=20 frame=2197
TICK_AFTER unit=1 clipMoveBammer=true strikeSuccess=true FOCUSN=80 LIFEN=279 moveId=110 focusCost=20 buffTickChecker=18 frame=2197
TICK_BEFORE unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=10 LIFEN=627 moveId=10 focusCost=20 frame=2223
PAID unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=16 LIFEN=615 moveId=10 focusCost=20 frame=2223
TICK_AFTER unit=3 clipMoveBammer=false strikeSuccess=true FOCUSN=16 LIFEN=615 moveId=10 focusCost=20 buffTickChecker=12 frame=2223
EXEC_BEFORE unit=3 clipMoveBammer=true strikeSuccess=true FOCUSN=16 LIFEN=615 moveId=10 focusCost=20 target=2 targetLife=250 targetFocus=16 frame=2224
EXEC_AFTER unit=3 clipMoveBammer=true strikeSuccess=true FOCUSN=16 LIFEN=615 moveId=10 focusCost=20 target=2 targetLife=84 targetFocus=16 frame=2224
```

## Left-behind globals in `AImoveAdder` (Flash 14 and Ruffle 0.7.1, #37)

`AImoveAdder` (`frame_42/DoAction_9.as`) keeps its scratch values in `_root` globals and resets only some of them, so a call can read what an earlier call left. Nothing else writes them, and they live until the SWF reloads, so the first call of a battle reads what the last battle left. `BattleAI.choose_move` starts each call fresh until #475 lands. These are the values a call can read before it writes them:

- `focusCheck`, `playerFocusCheck` and `numberLockKrin` are written only by the teammate scan (6-34), and only for a living teammate. A caster with no teammate keeps the last caller's values, and line 19 compares with the left `focusCheck` when slot `gMtYuIo` is empty or holds the caster. Lines 89-95 read them, line 403 sends a teammate-only move to `numberLockKrin`, and line 407 sends the move to `playerFocusCheck`.
- `focusMove` is reset only at 84 and 296, which are on the non-absolute path. Line 405 also reads it on the absolute path, so an absolute move after a call that left it true goes to `playerFocusCheck`.
- The `D_Array_*` lists are rebuilt only on the non-absolute path (134-139). On the absolute path the heal scan (197-247) reads the lists of the last non-absolute caller, and line 398 sends a self-and-teammate move to the unit that scan found and adds its heal guess to that slot's `healedThisTurn`.
- `aliveEnemies` and `counterFilter1` are rebuilt only for a move that hits enemies (352-391). Line 413 passes the turn on an empty list, and lines 437-439 fall back to `aliveEnemies[counterFilter1]` when the target is still 0.

What the runs showed. Each count is from `just aimove-report` on the logs below. A call is changed when its real move, target or heal-guess slot differs from a replay of the same call, with the same dice, in which every value above starts as `BattleAI` starts it. The fallback column counts the calls that reached lines 437-439.

| Battle | Player | Calls | Absolute | Changed | Fallback |
| --- | --- | --- | --- | --- | --- |
| 109 | Ruffle | 184 | 36 | 0 | 3, each onto the caster |
| 212 | Ruffle | 152 | 43 | 8 | 1, onto the caster |
| 212 | Flash | 144 | 35 | 8 | 1, onto slot 6 |
| 513 | Ruffle | 154 | 49 | 0 | 0 |
| 307 | Ruffle | 60 | 15 | 0 | 0 |
| 510 | Ruffle | 62 | 4 | 0 | 0 |
| 703 | Ruffle | 146 | 2 | 0 | 0 |
| 104 | Ruffle | 22 | 6 | 0 | 0 |

- All 16 changed calls are the same decision. In phase 2 of battle 212 the ZPCI Medic (slot 4) picks Med Buff 1 (550, self and teammate) from its absolute pool. In 15 of them the lists left by a non-absolute call of another unit make the heal scan pick Captain Hunt (slot 2) or the Sniper (slot 6), so the buff and its heal guess go there. In the other one (Flash call 64) the lists were empty, so the target stayed 0 and line 439 took slot 6 from the `[6 4 2]` list that a caster on the player's side built. `BattleAI` keeps the target on the Medic. The Medic cast Med Buff 1 17 times, and 16 of those went to a teammate.
- No absolute call started with `focusMove` true, so the line 405 retarget never ran. 28 calls started with it true, all in battle 703 and all on the non-absolute path, which resets it at line 84 before it reads it.
- The teammate-scan values and `numberLockKrin` changed no decision. The fallback ran in 5 calls, and the left list gave the caster in 4 of them, which is what `BattleAI` does.
- #475 ports the carry-over of every value above.

Evidence: the Probe `dev/probes/aimove.as` wraps `_root.AImoveAdder` once frame 42 defines it. The real call runs unchanged. The Probe then replays the call from the globals it started with, once with nothing reset (`none`), once with every value above reset (`all`), and once for each group (`focus`, `fmove`, `darr`, `alive`, `lock`). Each replay sets `KRSC` back, so `KRRR` gives it the same dice, and a stub `krinAddMove` records the move. Then the Probe puts back every global the function writes. `none` matched the real call in all 924 calls. A throwaway Probe, kept as `references/traced_runs/aimove_drive_probe.as`, set Heroic and a four-member party on the main menu and started each battle through `LOADBATTLESCENE`. On Heroic the player's half-turn passes by itself, so only AI units chose moves, and most battles ended in a loss after one to five minutes. The lines are in `references/traced_runs/aimove_web_ruffle.txt` (runs 2 to 4) and `aimove_web_flash.txt` (run 5). The Steam build was not run. Its `AImoveAdder` (in its `frame_42/DoAction_2.as`) is line for line the same as the web build's, and its `KRRR` and `krinAddMove` differ only in writing `x += 1` where the web build has `x = x + 1`.

## Approximation audit (2026-07-21) - port pieces NOT yet source-faithful

Everything below still stands in for original behavior, except the rows marked DONE; the ActionScript truth is already located, so no re-decoding is needed:

| Piece | Current stand-in | Original truth lives in |
|---|---|---|
| Battle screen zoom + shake | **DONE (2026-11-10)** for every move's zoom and a Shock's shake, and a crit's shake (2026-11-17): `BattleScreenClip` (`scripts/battle/battle_screen_clip.gd`) runs both clips' frame scripts from `assets/ui/battle/battle_screen_motion.json`. `BattleScene._play_crit` shakes on a damage or heal crit with no Graphics check, and plays `Angry_Dux` or `Angry_Roald` on a damage crit by Veradux or Roald | `GridZoomer` "KrinZoomGo" (zoom to target center * `-zoomRatioNEW`, or -0.3 for a Shock, + 400/300; pause 2xCD melee / 5 missile / 1 shock), `GridShaker` (shock + crits) |
| Result flash | **DONE (2026-11-10)**: each Fighter presenter pulses its own Result flash on the doll, no longer the HIT recoil label only. See "The Result flash" above | `BATTLEFLASH` with `characterColorState/FilterState`: `frame_42/DoAction_8.as` ~line 199 |
| Floating number art | **DONE (2026-11-10)**: `extract_floating_numbers` renders the digit, MISS and SHIELDED clips and NumberFixer's four labels, and `FloatingNumber` plays them | NumberFixer/NumberSetter digit clips, miss/shield variants: `frame_42/DoAction_7.as` |
| Top battle HP/focus bars | in-field bars with numbers | `lifeBarUpdate` + bar clips, layout in frame 217 placements |
| Buff form swap ([#194](https://github.com/julian-perge/urchin/issues/194)) | **DONE (2026-11-18)**: `convert_buff_looks` also reads the dressChar call of each form in `changeForm` and the form `if`s of `applyChangesKrin`. `FighterPresenter` dresses the doll with `CharacterVisual.wear_form` when the snapshot it shows holds a form buff and with `wear_own_form` when the buff goes, before it compares the stun, as `applyChangesKrin` does. A form wears its skin set and its weapons and no armor, because `changeForm` passes "" as the armor set and the clips `M_HEAD_` and the like do not exist in either SWF. A weapon of "" takes the unit's own weapon. The new clip starts on `stand`, and a stunned unit goes straight to `stun2`. HOUND and WEREWOLF are MODEL5 clips, so the doll stands 0.8x and 10 px lower for as long as it wears one, and plays MODEL5's clip ([#429](https://github.com/julian-perge/urchin/issues/429)). The last form `if` to run wins (BARON 4, then 9 to 17, then GHOSTBOSS2 19). A dead fighter is not redressed | `changeForm`: `frame_42/DoAction_10.as:483-537`; `dressChar`: `frame_217/DoAction_2.as:1-67` |
| Buff recolor and glow ([#193](https://github.com/julian-perge/urchin/issues/193)) | **DONE (2026-11-18)**: `convert_buff_looks` reads `krinChangeColor`, the six filter lists and the order of the `if`s of `applyChangesKrin` into `dev/converted_json/buff_looks.json`. `FighterPresenter` resolves the look from the buff slots of the snapshot it shows with `BuffLook.resolve`, so the look waits for the event that lands the buff and goes at the event that removes it. `CharacterVisual.show_buff_look` hands the color offsets and the glows to `doll_body.gdshader`, which draws up to two GlowFilters, inner or outer and with or without a knockout, and then the offsets. Of the indexes a unit holds, the last `if` to run wins: color Poison (1) then Enrage (7), filter FrostGreen (3), Red (18), Shadow (5), Icy (6), Orange (8), then Frost (2). The filter named Orange glows 0x33FFFF (cyan). A Result flash replaces the filter and the color while it is on, as the scripts of BATTLEFLASH do. The form swap of the same function is [#194](https://github.com/julian-perge/urchin/issues/194) | `applyChangesKrin`: `frame_42/DoAction_10.as:380-466`; `krinChangeColor` and the filter lists: `frame_42/DoAction_3.as` |
| Doll ground shadow ([#192](https://github.com/julian-perge/urchin/issues/192)) | **DONE (2026-11-18)**: `extract_doll_shadow` renders DefineSprite 144, which every model places at depth 1 as `shadower`, and writes each model's frame 1 matrix for it to `resources/sprites/doll_shadow.json`. `FighterPresenter.setup` calls `CharacterVisual.start_clip` with the unit's model, which calls `show_shadow`, which puts the shadow first in the doll's body. The shadow lasts until frame 371 removes the doll. The scripts on MODEL1 frame 360 and MODEL4 frame 295 run `_parent.shadower._visible = false`, but `_parent` is the rig (DefineSprite 2676), which has no `shadower`, so they hide nothing. This was read from the placements of both SWFs and the AS export, and it was not run in a Traced run. MODEL5, MODEL7 and MODEL8 move the shadow on later frames of their clips, and MODEL2 removes it after frame 65. `extract_model_animations` writes each frame's matrix for it, or null, and `CharacterVisual` moves or hides the shadow on each frame ([#429](https://github.com/julian-perge/urchin/issues/429)). `CharacterVisual.get_bounds` leaves the shadow out, where Flash's `_width` of the model clip includes it | player clip "shadower" (placed inside each model clip, `DefineSprite_166_MODEL1/frame_360/DoAction.as`) |
| Melee end point | **DONE (2026-11-10)**: `CharacterVisual.play_melee` stops the caster at the target's x less both half-widths, measured from the dolls' drawn bounds as the swing starts, and steps toward the target's live position on the original's dash and Runback steps. The part PNGs carry their filters' glow and Flash's bounds don't, so a half-width can come out a few px wider than the original's | target/shooter half-widths: `krinMelee` endPoint |
| Swing whoosh ([#191](https://github.com/julian-perge/urchin/issues/191)) | **DONE (2026-11-17)**: `convert_model_sound_cues` reads the `addSound` calls of the MODEL1 and MODEL4 frame scripts into `dev/converted_json/model1_sound_cues.json` and `model4_sound_cues.json`, and `CharacterVisual` emits `sound_cue` as the strike's playhead goes through each cue frame. `FighterPresenter` passes it on as `effect_cue`, so a swing plays `sfx_swing` once, on frame 88 (`Attack_Upper`), 118 (`Attack_Stab`) or 146 (`Attack`), before the Impact sound. A doll that is no longer in its swing state when the playhead would reach the cue (a hit on the caster) plays none. A MODEL4 doll plays it on MODEL4's frame 86 (`DefineSprite_2668_MODEL4/frame_86`), which all three of its swing labels share (#378). MODEL5 plays it on its frame 71 and MODEL6 and MODEL7 on their frame 69 (`DefineSprite_2664_MODEL5/frame_71`, `DefineSprite_2608_MODEL6/frame_69`, `DefineSprite_2631_MODEL7/frame_69`). MODEL2, MODEL8 and MODEL9 play no sound, and their cue files are empty ([#429](https://github.com/julian-perge/urchin/issues/429)) | `sfx_swing` cues baked at MODEL1 clip frames 88/118/146 |
| Female doll clip ([#378](https://github.com/julian-perge/urchin/issues/378)) | **DONE (2026-11-19)**: `extract_model_animations` writes MODEL1 (DefineSprite 166) and MODEL4 (DefineSprite 2668) to `resources/sprites/model1_animations.json` and `model4_animations.json`, each with its labels, every frame's part matrices and alphas, and each part's depth. `FighterPresenter.setup` and a form change call `CharacterVisual.start_clip` with the model, so a MODEL4 doll stands on MODEL4's frame 1, draws head over arm1 (depths 25 and 23, the other way round from MODEL1), plays MODEL4's labels and its swing cue on frame 86. MODEL4 starts `Attack_Stab`, `Attack_Upper` and `Attack` all on frame 78, so all three are frames 78 to 92, and its dead label ends on frame 306, whose script removes the doll. Every other model plays its own clip too ([#429](https://github.com/julian-perge/urchin/issues/429)). The menu doll keeps MODEL1's pose for every member, because the original menu places its own female part set ([#430](https://github.com/julian-perge/urchin/issues/430)) | `dressChar`: `frame_217/DoAction_2.as:17`; MODEL4 units: `frame_42/DoAction_13.as:144`, `frame_42/DoAction_14.as:224` |
| Creature doll clips ([#429](https://github.com/julian-perge/urchin/issues/429)) | **DONE (2026-11-19)**: `extract_model_animations` writes MODEL2 (DefineSprite 1795), MODEL5 (2664), MODEL6 (2608), MODEL7 (2631), MODEL8 (2542) and MODEL9 (2469) too, and `CharacterVisual.CLIP_MODELS` holds all eight models the SWF exports. MODEL5 and MODEL6 name 11 of the doll's 15 parts, MODEL7 7, MODEL8 6, and MODEL2 and MODEL9 none. dressChar still dresses all 15 names, and a part that the frame does not place is hidden. `extract_model_pieces` renders the clips a model places with no name: MODEL8's two body shapes at depths 9 and 10, MODEL2's orb (1768) and MODEL9's bomb (2468), which loop on their own clock because the clip's gotos keep a clip placed on frame 1, and the clips on the cast, hit and dead frames of MODEL2, MODEL7 and MODEL9, such as BOOM1. `CharacterVisual` draws them between the parts in depth order, with each frame's colour transform, and `get_bounds` counts them. The effect clips that every model places are drawn too, see the next row. Flash ignores a goto to a label the clip lacks, as Ruffle's `goto_frame` does (`core/src/avm1/globals/movie_clip.rs`), so a hit or a stun on an orb leaves it playing `stand`, and Gregor's Terrify (`Attack_Stab`) on MODEL7 holds the run's last frame, whose script runs `stop()`, until `runback`, with no swing sound | `dressChar`: `frame_217/DoAction_2.as:17-30`; `krinMelee`: `frame_42/DoAction_4.as:130` |
| Doll effect clips ([#456](https://github.com/julian-perge/urchin/issues/456)) | **DONE (2026-11-19)**: every model places unnamed effect clips over its parts. MODEL1 places the swing trails 149 on `Attack_Upper`, 153 on `Attack_Stab` and 158 on `attack2`, the cast glow 162 on `cast`, and the stun mark 165 on `stun2`, all at depth 33. MODEL4 and MODEL6 place 158, 162 and 165, and MODEL5, MODEL7 and MODEL8 place 162 and 165, at their own depths. `extract_model_pieces` draws them as clip pieces: each clip's own frames render around its origin, and each model frame gives its matrix and colour transform. A clip piece plays on its own clock from the frame that placed it, and a goto that lands on the same placement keeps it, so the stun mark (30 frames, no `stop()`) loops through `stun2`'s goto back to its first frame (`DefineSprite_166_MODEL1/frame_279`). A trail plays its 12 frames and holds frame 12, whose script runs `stop()` and which draws nothing. A part whose `onClipEvent(load)` runs `setRGB(colortobe)` (161 in the glow, and 146, 151 and 156 inside 147, 152 and 157 in the trails) renders alone, and `CharacterVisual` draws it behind the rest of its clip in the `colortobe` the doll held when the clip was placed. The conductor sets `colortobe` to the move's param 11 before `gotoAndPlay("cast")`, and `krinMelee` sets it to the same param after the swing's goto, so the trails take the move's colour too: each trail appears at least 15 frames after the goto. The doll itself is not tinted on a cast | `DefineSprite_162/frame_1/PlaceObject2_161_1`; `DefineSprite_147/frame_1/PlaceObject2_146_1`; conductor: `frame_217/PlaceObject2_3389_480` enterFrame, lines 417 and 450; `krinMelee`: `frame_42/DoAction_4.as:130-131` |
| Stun/cast animations | **DONE (2026-07-21)**: the port plays the real labels (see the stun family section above), no longer a code-driven slump/raise | labels `cast` 189-219, `stun` 220-239 -> `stun2` 240-279 loop (frame 279 goto), `outofstun` 280-295 -> stand |
| Hover ring / radial menu / pass ring | modern inventions (kept by design) | original UX: `KrinSelector` clips + `KrinToolTipper` tooltip system |
| Victory screen layout | inventory-window geometry + reference screenshot | menu clip 3142 frame 9 placements (never dumped precisely) |
| Options screen ([#379](https://github.com/julian-perge/urchin/issues/379)) | invented layout from reference | menu clip 3142 frame 39 |
| Abilities tutorial callout ([#387](https://github.com/julian-perge/urchin/issues/387)) | skipped | texts 3063 + glow box sprite 3059 (frame 25) |
| Sky horizon | **DONE (2026-08-22)**: the strip position comes from `battle_layout.json` (`BATTLE_LAYOUT_PATH` in `battle_scene.gd`), no longer an empirical y = 292 | background clips' own art timelines (sky placement baked per zone) |
| Start-menu flow | slot -> name+class -> options | original: PLAY -> name entry (root ~65) -> slot select (~75) -> class (~85) -> options (~95) |
| Music of a new game's first fight ([#384](https://github.com/julian-perge/urchin/issues/384)) | **DONE (2026-11-19)**: the Tutorial's battle 2 plays `_music_battle1` and battle 100 plays `_music_battle2`, both at full volume. See "New Game and Load Game" above | `frame_180/DoAction.as:4-6` sets `soundPlayCounter` 3 (`_music_battle2`) and `bangStart`, so it starts at full volume. See "New Game and Load Game" above |
| Battle countdown | **DONE (2026-11-08)** for the timing: 4 s on Heroic only, running out passes the turn, and Easy and Normal wait with the label hidden. The display is still a number in the bottom bar's `Panel3` | 120 frames (4 s at 30 fps) on Heroic only, and the half-turn starts when it runs out: see "Heroic decision timer" above. The original shows no number: `battleClocker` (DefineSprite 3389) sits behind the pass button and fills the two half-dials of DefineSprite 3386 from `BattleTimeNow` |
