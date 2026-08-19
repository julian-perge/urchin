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

1. **Dash out.** The doll's clip plays `run`; the body translates each frame by `spdXCoEFFER * (distance / 60) * 10` where `goRat` = fraction traveled and `spdXCoEFFER = clamp(1.5 - 1.45 * goRat, 0,
   1)` - an ease-out. Because the step is proportional to distance, arrival always takes ~14 frames (~0.47 s) REGARDLESS of distance (speed scales with range). The `run` label (46-77: wind-up 46-53,
   leap 54-62, glide hold 63-77, `stop()` on 77) is INTERRUPTED mid-leap by arrival - it never finishes on normal hops. End point = target edge minus both half-widths.
2. **Strike.** On arrival (`goRat >= 1`) the clip does `gotoAndPlay(attackType)` - one of `Attack` (138-152), `Attack_Upper` (78-107), `Attack_Stab` (108-137). The timeline then flows on its own:
   `Attack` runs through `attack2` (153-167, the downswing/follow-through - it is NOT a selectable variant, no move references it) and both 30-frame labels end in a scripted `gotoAndStop("runback")`.
   Impact (hit effect + damage application, `BAMBAMBAM`) fires exactly 15 frames (0.5 s) after strike start; `sfx_swing` cues sit at clip frames 88/118/146.
3. **Runback.** 15 frames after impact (1.0 s after strike start - exactly the clip's own runback boundary for every label) the code forces `gotoAndPlay("runback")` (168-188, ends in
   `gotoAndStop("stand")`) and reverses movement with an eased return: `spdXCoEFFER = min(1.45 * goRat, 1)` - fast leave, exponential settle home (~18 frames); position snaps to home when `relX`
   crosses zero.

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
   clears the battlescreen bounds (`|x| > 500`), rather than stopping at the target.
4. **Multi-target.** `ability_two[20]` (`is_multi_target`) fires one independent bolt per living enemy on the opposing side, each targeting its own unit.

The Godot port fires a single bolt per `_play_move_event` call (multi-target per `ability_two[20]` isn't ported - see the audit table below). **DONE (2026-08-19)**, see `.superpowers/sdd/2026-08-18-missile-projectile-art/`: distinct clip art per `projectileModel` name (e.g. `Krin.Firebolt`) is extracted and rendered untinted via `Projectile`'s `Bolt` `AnimatedSprite2D`; `KrinTrail`'s real 33-frame fade-in/fade-out pulse (not a generic tinted circle+line) plays via a second `AnimatedSprite2D`, tinted by the move's real `colortobe` value; and a miss now flies the bolt fully past the target off-screen instead of always resolving as a hit on arrival, matching `strikeSuccess`'s hit/miss branch (`Projectile.did_hit` gates whether `reached_target` frees the bolt immediately or lets it keep flying).

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
- **Trigger (once per unit's own per-turn tick, in `applyChangesKrin`):** compares the new `STUN` against `STUNP` (the previous tick's value, reset to 0 alongside `STUN` at battle-unit init):
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
- No numeric timing constants gate any of this (unlike `krinBoltTime`/`krinMeleeAttackCD`) - it's a per-tick value-comparison state machine; the Godot port evaluates it in `_refresh_bars` (called after
  every event and at half-turn boundaries - finer-grained than the original's once-per-unit-tick cadence, but the comparison is idempotent between real value changes so this is safe).

## Menu piercing/defense bars (DefineSprite_3142/frame_1)

Implemented in `scripts/ui/menu/menu_theme.gd` (`bar_fill_fraction`). Display value = allocation + ceil(100 + 15 * level); fill fraction = the crit-curve quartic `0.016666667 x^4 - 0.25 x^3 + 1.233333
x^2 - 1.9 x + 0.9` of `value / (100 + 15 * level) + 1`, clamped to the track (base allocation = 30%).

## Item looks and icons

- `looks` art keys: `gghhjjuu.looks = "X"` assignments in frame_42/DoAction_16.as after each `createNewItemKrin` (wearable default "NINJA"; id counter jumps at 99/299/499).
- Slot icons: the icon clip (DefineSprite 2064) has one labeled frame per item name; shape 1913 is an editor-only green backing. `gotoAndStop(ITEMNAME[id])`.

## Companion aggression stances (agModeAr)

Implemented in `scripts/entities/party.gd` (`AGGRESSION_PRESETS`). Columns 0-4 = Phalanx/Defensive/Tactical/Aggressive/Relentless; rows = [Aggression, LifeBoundary1, LifeBoundary2, FocusAggression,
FocusRegenLimit]: `[0,30,50,70,90] / [95,90,75,40,2] / [0,65,35,15,1] / [0,30,70,15,100] / [30,30,30,5,5]` (read column-wise). Default stance 2 (Tactical), persisted as `PlayerSave.ag_mode`.

## Starting state (new game)

- Class-select buttons (DefineButton2_2735/2736/2737 = Bio/Hydro/Psycho) seed `moveMatrix[0..1]` and `moveMatrix2[0..1]` with the class starting moves.
- `equipArray0 = [0, 11, 0, 4, 8, 5, 0]` (frame_180): White T-Shirt, Levo Jeans, Proverse All Stars, A Broken Pipe.
- Sell-back = `ceil(price * 0.15)` (DefineButton2_3015).

## Battle presentation per animation type (frame_217/PlaceObject2_3389_480 enterFrame, ~line 400)

The battle engine dispatches on `addNewMove` param 10:

- **Melee**: caster `gotoAndPlay("run")` + `krinMelee(...)` (see above). Param 12 = the attack label. The move's sound plays AT IMPACT (`soundToMake` in the BAMBAMBAM handler).
- **Missile**: caster plays **"cast"** (param 12 is the PROJECTILE clip, not a caster label), `colortobe` = param 11 tints the cast glow, `sfx_cast` plays, `krinBoltMake` spawns the projectile (speed
  `krinBoltSpeed = 1`, stretching trail `_xscale += 8.3 * step`); impact/sound/boom land when the bolt arrives. `ability_two[20]` (is_multi_target) fires one bolt per living enemy.
- **Shock**: caster plays **"cast"** with the `colortobe` tint; param 12 is UNUSED. The move's own sound plays immediately, the BOOM clip (param 13) attaches at the target at once, the camera zooms
  (`zoomPause = 1`), the screen shakes (`GridShaker`, when param 9 speed modifier >= 0), and impact (`BAMBAMBAM`) is instant.

Element colors (`elementColorArray`, frame_41/DoAction_2.as - menu bars AND damage numbers): Physical `C40000`, Magic `FB95C8`, Ice `68CBF4`, Fire `FF6600`, Lightning `FFCC00`, Earth `856B47`, Shadow
`664D80`, Poison `508349`; heals `66FF00`.

Damage numbers (`KrinNumberShow`, frame_42/DoAction_7.as): digit sprites (NumberFixer/NumberSetter clips) colored by the move's ELEMENT, `gotoAndPlay("critical")` variant on crits (`perKSuccess`),
special "miss"/"shield" frames. Crits also fire `GridShaker` (frame_42/DoAction_8.as).

## Approximation audit (2026-07-21) - port pieces NOT yet source-faithful

Everything below still stands in for original behavior; the ActionScript truth is already located, so no re-decoding is needed:

| Piece | Current stand-in | Original truth lives in |
|---|---|---|
| Camera zoom + shake | none | `GridZoomer` "KrinZoomGo" (zoom to target center * `-zoomRatioNEW` + 400/300; pause 2xCD melee / 5 missile / 1 shock), `GridShaker` (shock + crits) |
| Target hit flash | HIT recoil label only | `BATTLEFLASH` with `characterColorState/FilterState`: `frame_42/DoAction_8.as` ~line 199 |
| Damage number art | Labels with exact colors + bigger crit font | NumberFixer/NumberSetter digit clips, miss/shield variants: `frame_42/DoAction_7.as` |
| Top battle HP/focus bars | in-field bars with numbers | `lifeBarUpdate` + bar clips, layout in frame 217 placements |
| Doll ground shadow | none | player clip "shadower" (hidden on death, MODEL1 frame 360 script) |
| Melee end point | fixed 55 px short | target/shooter half-widths: `krinMelee` endPoint |
| Swing whoosh | impact sound only | `sfx_swing` cues baked at MODEL1 clip frames 88/118/146 |
| Stun/cast animations | code-driven slump/raise | labels `cast` 189-219, `stun` 220-239 -> `stun2` 240-279 loop (frame 279 goto), `outofstun` 280-295 -> stand |
| Hover ring / radial menu / pass ring | modern inventions (kept by design) | original UX: `KrinSelector` clips + `KrinToolTipper` tooltip system |
| Victory screen layout | inventory-window geometry + reference screenshot | menu clip 3142 frame 9 placements (never dumped precisely) |
| Options screen | invented layout from reference | menu clip 3142 frame 39 |
| Abilities tutorial callout | skipped | texts 3063 + glow box sprite 3059 (frame 25) |
| Sky horizon | empirical y = 292 | background clips' own art timelines (sky placement baked per zone) |
| Start-menu flow | slot -> name+class -> options | original: PLAY -> name entry (root ~65) -> slot select (~75) -> class (~85) -> options (~95) |
| Battle countdown | not displayed | 120 s decision timer UI, frame 217 |
