# Original logic vs port: a source re-review

Date: 2026-11-07. This review checks the web build's ActionScript against the current port and audits the repo's notes. It is meant as the starting point for the overhaul. No code, scene or existing doc was changed.

## How to read this

- AS paths are relative to `dev/source_files/action_script/`, the full ffdec export of the web SWF `sonny-2-2900.swf` (dev/source_files/README.md:15). GD paths are relative to the repo root.
- `F42/X.as` means `frame_42/X.as`.
- `CONDUCTOR` means the per-frame battle loop, `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as`.
- `B3004 release:8` means line 8 of `DefineButton2_3004/BUTTONCONDACTION on(release).as`. `press` and `rollOver` work the same way.
- [E] marks evidence: read in source, or computed from repo data with the formula cited.
- [I] marks inference: reasoned from code, not read directly and not run.
- Nothing was run in Flash, Ruffle or Godot for this review. Where a consequence depends on a live run, the claim says so.
- The data the port loads comes from the Steam build's runtime capture (SWF_DIFFERENCES.md:6-11), but the AS is the web build. Facts below about roster unlocks and the ArmorGames upsell are web-build facts.

## Corrections (2026-11-07)

Drafting the overhaul issues re-checked this review against the source. The body below is left as written; these points in it are wrong or now answered.

- 2.14 and 4(a): the companion markers change the money of 50 playable story battles, not 51. The 51st is battle 1, which only the PvP arena's fight button launches (B3339 release:7, with `Krin.singlePlayer = false`), and the port leaves the arena out. Training fights change too: 1001 at player level 7 pays 25 in the original and 78 in the port.
- 2.9: Shatter is at F42/DoAction_6.as:852-892, not 852-890. Corruption spans 1607-1618, with fields `[23]` and `[24]` at 1613-1614. In the converted JSON those two live under `ability_two`, as `23_secondary_element_type` and `24_required_buff_count`.
- 4(d): Tie Dye (610) is in Flower Zombie's attack pool (`movesA`, F42/DoAction_13.as:553), not its ABS pool. The player can apply sswitch too, through the talent moves Subversion (173) and Retrograde (475 and 476).
- 2.24: only one speech line names Sonny as its speaker, in battle 100 (F42/DoAction_14.as:370), so a custom name sends that one line to the narrator.
- 2.11, divergence 2: the port already reproduces line 93. `restores_ally_focus` in `BattleAI.choose_move` raises `focus_move` for any ally-targetable move (scripts/battle/battle_ai.gd:93-99). Only the carry-over of these globals from one unit's decision to the next differs.
- 3.6: `progressLevelOn`'s readers are at F42/DoAction.as:59-70, not 59-67.
- 2.21 item 6: CS_CUT1 plays before every story attempt at 109, not only the first. B3188 press:18-24 plays it whenever `BattlePick` is 109 and `progressFight` is true.
- 2.21 item 6: CS_INTRO is not an animation. It is a gradient shape (3475) under four text fields that frame_263/DoAction.as:2-5 fills from `MENU[86]` to `MENU[89]`, timed by a silent 401-frame sprite (3470) whose last frame sets `cutSceneEnd`.
- Open question 3 is answered from source: both intro paths reach frame 180. With the tutorial on, the options button (B2770 release:2-6) goes through CS_INTRO and IntroSeq to battle 2, where frame_165 sets `cutsceneSequence` to "CS_INTRO2", and frame_219/DoAction.as:73-77 jumps to it after the battle. With the tutorial off, the button goes straight to CS_INTRO2 (7-11). Either way frame_293 sets `gotoSceneKrin` to "IntroSeq2", frame 166, and no script on root frames 166-179 or on the one sprite they show (321) stops the root before frame 180.
- Open question 5 is answered from source: `blacker5.play()` (CONDUCTOR:260) resumes DefineSprite 3355 from its `stop()` at frame 31. Its frame 85 routes the root to loseCombat, winCombat or drawCombat by `winCondition` 0, 1 or 2 (DefineSprite_3355/frame_85/DoAction.as:5-16). In arena mode it first jumps to arenaEnd (lines 1-4), and the `winCondition` checks after that are not in an else branch.

## 1. Summary

| # | System | Status | Main difference | Section |
|---|---|---|---|---|
| 1 | Battle ids in resources/battles | Diverges | AS battles 2, 55, 212, 308, 603 and 703 are stored as 49, 99, 299, 399, 699 and 999. The zone 2, 3, 6 and 7 bosses cannot load, so the story stops at zone 2 | 2.1 |
| 2 | Turn order and half-turns | Diverges | the port re-sorts execution and AI decision order every half-turn; the original fixes it once per full turn | 2.2 |
| 3 | Decision timer | Diverges | original: 120 frames (4 s), Heroic only, enforced. Port: 120 s, every difficulty, display only | 2.3 |
| 4 | Move execution and damage, heal, focus formulas | Matches, except the "Attack" category | the port drops Shatter Bolt's stun | 2.4 |
| 5 | Crits, misses, dodge | Matches | | 2.5 |
| 6 | Buffs, dispel, sswitch | Diverges | dispel order, stat recompute timing, sswitch display, no tick numbers | 2.6 |
| 7 | Focus and life costs | Diverges | the player can pick a move the original refuses for life; it fails at execution and wastes the turn | 2.7 |
| 8 | Cooldowns and silence | Matches | | 2.8 |
| 9 | Required target buffs | Not implemented | Corruption and Shatter can be used on any target | 2.9 |
| 10 | Stun | Rules match; presentation diverges | the port plays HIT on stunned targets | 2.10 |
| 11 | AI move choice | Matches, with two divergences | the player's heal is not added to healed_this_turn [E]; the original's stale-global quirks are not reproduced [I] | 2.11 |
| 12 | Aggression stances | Port-only persistence | the original resets companions to Tactical every battle | 2.12 |
| 13 | Enemy and guest creation | Diverges | no stat reduction for units below level 10 | 2.13 |
| 14 | Money reward | Diverges | the port leaves companion slots out of the average | 2.14 |
| 15 | XP reward | Player matches; companions diverge | the port gives companion XP in battles they did not fight | 2.15 |
| 16 | Drops | Matches | | 2.16 |
| 17 | Leveling, stat points, train caps, respec | Matches; the respec limit is port-only | | 2.17 |
| 18 | New-game stats | Diverges | the port keeps 19 class-split stat points that the original overwrites | 2.18 |
| 19 | Talent tree | Matches | | 2.19 |
| 20 | Equipment and team select | Player matches; companions not implemented | | 2.20 |
| 21 | Zone progression and cutscenes | Diverges | zone 7 gate, zone 4 boss replay, usedTraining on replays, routing after a boss, CS_CUT1 and intros | 2.21 |
| 22 | Battle outcome | Diverges | a defeat or a draw is game over in the original | 2.22 |
| 23 | Achievements | Diverges | 1, 3 and 9 unreachable; All Star never awarded; the Pacifist counter overcounts | 2.23 |
| 24 | Battle speeches | Diverges | unknown speakers shown as narrator; a custom name breaks "Sonny" lines; 4 s cap | 2.24 |
| 25 | Battle presentation | Diverges | shield, miss sounds, dead doll, melee end point, pacing | 2.25 |
| 26 | Combat log | Port-only | | 2.26 |

[I, judgment] For the overhaul, most damaging first:
1. 2.1, because the story is blocked.
2. 2.18 and 2.13, because balance is off from the first fight.
3. 2.14, the economy.
4. 2.4, Shatter Bolt.
5. 2.7 and 2.9, the player's move gates.
6. 2.21 and 2.22, the game flow.
7. Everything else.

## 2. Systems

### 2.1 Battle ids

Original:
- [E] `createNewBattle` increments `battleCreationID` before it creates `KBR<id>` (F42/DoAction_14.as:1-5).
- [E] The jump statements `battleCreationID = 49, 99, 199, 299, 399, 499, 599, 699, 999` (F42/DoAction_14.as:325, 365, 503, 750, 884, 1035, 1230, 1301, 1368) each come right after a fully populated battle. The next battle therefore gets jump + 1.
- [E] The resulting AS ids are 1, 2, 50-55, 100-109, 200-212, 300-308, 400-409, 500-513, 600-603, 700-703 and 1000-1026.
- [E] A story battle id is `sectionIn * 100 + questProgress[sectionIn]` (B3188 press:5), and each zone's boss sits at progressMax (frame_41/DoAction_2.as:43-67). The bosses are 109, 212, 308, 409, 513, 603 and 703.
- [E] The tutorial is battle 2 (frame_165/DoAction.as:2).

Port:
- [E] The capture labels the last battle before each jump with the jump value (SWF_DIFFERENCES.md:30-33).
- [E] `MISLABELED_BATTLE_IDS` corrects only 199, 499 and 599 (dev/urchin_dev/convert/battles.py:35-39).
- [E] `resources/battles/` holds 49, 99, 299, 399, 699 and 999, and has no 2, 55, 212, 308, 603 or 703 (directory listing).
- [E] Each mislabeled file matches its AS battle by players and levels:

  | AS battle | Players | Levels | Stored as |
  |---|---|---|---|
  | 2 | `[49,0,0,48,0]` (F42/DoAction_14.as:311) | | 49 |
  | 55 | | | 99 |
  | 212 | `[28,-2,26,-1,34]` | `[11,1,11,1,11]` | 299 |
  | 308 | `[47,-2,0,-1,0]` | `[15,1,1,1,1]` | 399 |
  | 603 | `[76,-2,0,-1,0]` | level 28 | 699 |
  | 703 | `[84,-2,82,-1,83]` | `[30,1,30,1,30]` | 999 |

- [E] `pick_story_battle` asks for `zone * 100 + progress` (scripts/zones/zone_progression.gd:94, 98).
- [E] `load_battle` returns null when the file is missing (scripts/battle/battle_setup.gd:22-27).
- [E] `start_battle` returns before building any units (scripts/battle/battle_scene.gd:198-201).

Status: Diverges.
- [E code, not run] The zone 2 boss, 212, cannot load. `quest_progress[2]` therefore never passes 12, and zone 3 never unlocks (zone_progression.gd:128-138). Zones 3 to 7 are unreachable. NEXT_PHASES.md:231-233 recorded this exact symptom for 109 before that id was fixed.
- [E] battle_runner.gd:403 checks `battle.id == 2` for the tutorial loss rule. The tutorial is stored as 49, so the check can never match. The port has no tutorial (KNOWN_GAPS.md:107), so the bug is latent.
- [E] The 55/99 mislabel has no player-facing effect:
  - AS 50-55 are launched only by B3273-B3278.
  - Hub sprite 3287 places those buttons in its `BETA` frame (dev/source_files/swf_xml/sonny-2-2900.xml:459383-459399).
  - BETA is zone 13 in `Krin.zoneName` (frame_41/DoAction_2.as:25).
  - The map only draws zones below `questHub.length`, which is 8 (frame_449/DoAction.as:4-18).
- [I] Fix shape: add 49:2, 99:55, 299:212, 399:308, 699:603 and 999:703 to `MISLABELED_BATTLE_IDS`, after re-confirming each pair by content as in the table above.

### 2.2 Turn order and half-turns

Original:
- [E] `TeamSelect` (frame_217/DoAction_2.as:68-172) works out who opens a full turn and in what order:
  - It averages SPEEDU over each team's active units (75-93).
  - `absoluteStart` forces the opener, and is cleared unless `timeLock` is set (94-108).
  - The higher average opens. Ties go to team 1 in single player (109-141).
  - It sets `TurnTime = 2` (142).
  - It then calls `TeamSpeedAdder` (284-310). That sorts each team by SPEEDU descending, then slot id descending, with inactive units included (290, 298). It writes `teamAdder`, the execution position, and `AITeamMoveOrder`, the decision order.
- [E] `TeamSelect` runs only when `TurnTime` reaches 0 (CONDUCTOR:147, 262-264). The other half-turn only flips `TeamMoveNow` (CONDUCTOR:283-311).
- [E] Each half-turn dispatches three slots (`Cycler = 3` at CONDUCTOR:791, decremented at 134).
- [E] Phase changes and `winDate` are checked at the end of each half-turn (CONDUCTOR:176-197), and win and lose right after (198-256).

Port:
- [E] `_team_select` (scripts/battle/battle_runner.gd:429-458) reproduces the opener rule (441-449). It writes `team_adder` (458), which nothing reads; the only other reference is its declaration (scripts/battle/combat_unit.gd:54).
- [E] The execution queue and the AI decision order both come from `_team_slots_in_order`, which re-sorts by live `speed_u` on every half-turn (battle_runner.gd:138, 171-182).

Status: Diverges.
- [E] If a speed change lands during the first half-turn of a full turn, the port uses it for the second half-turn's order. The original keeps the order it chose at the start of the full turn.
- [I] How often this changes an outcome has not been measured.
- [E] Win and lose counting matches, draw included (battle_runner.gd:395-423 vs CONDUCTOR:198-256).
- [E] Once the player dies, the original also forces `turnBasedKrin = true` (CONDUCTOR:200-202). That only matters for the Heroic timer (2.3).

### 2.3 Decision timer

Original:
- [E] `BattleTime = BattleTimeLimit = 120` (frame_217/DoAction.as:1-3).
- [E] `BattleTimeNow++` runs once per frame, and only when `!turnBasedKrin` and the player's team is moving (CONDUCTOR:593-596).
- [E] `turnBasedKrin` is true on difficulties 0 and 1 (frame_201/DoAction.as:65-79).
- [E] The SWF runs at 30 fps (`frameRate="30.0"` in the swf_xml header). The window is therefore 120 frames, 4 seconds, and only on Heroic.
- [E] At `BattleTimeLimit - 1` the AI allies decide (CONDUCTOR:674-698). At `BattleTimeLimit` the half-turn starts whether or not the player has picked (CONDUCTOR:769-792).
- [E] Picking a move jumps the clock to `BattleTimeLimit - 5` (F42/DoAction_11.as:98-101).

Port:
- [E] `BATTLE_TIME_LIMIT = 120.0` is used as seconds (battle_runner.gd:44). It counts down by frame delta while the player decides (battle_scene.gd:159-161, 185-186).
- [E] It runs on every difficulty and never forces a pass (NEXT_PHASES.md:100-102).
- [E] The comment at battle_runner.gd:18-21 calls it a "120-second" countdown.

Status: Diverges.
- [E] The unit differs: seconds in the port, frames in the original.
- [E] The scope differs: every difficulty in the port, Heroic only in the original.
- [E] The effect differs: cosmetic in the port, an automatic pass in the original.
- [E] The port has no real-time Heroic mode at all.

### 2.4 Move execution and formulas

Original:
- [E] The cost is paid at dispatch (CONDUCTOR:355-358). `executeMove` runs later, at impact (CONDUCTOR:54-69), so `focusCoEF` reads the caster's focus after the cost (F42/DoAction_8.as:22).
- [E] Full Damage is F42/DoAction_8.as:23-152:
  - the crit quartic with its +1.9 constant at 31;
  - the damage at 60, floored at 1 (61-64);
  - the shield at 65-76.
- [E] Heal is 153-231: crit x1.5 at 157-166 and the amount at 167.
- [E] Focus is 232-249.
- [E] The crit roll is `perScript` (251-266).

Port:
- [E] The same pieces are in scripts/battle/battle_manager.gd: setup 36-64, crit roll 91-100, damage 102-132, shield and sswitch 134-162, heal 164-193, focus 195-198.
- [E] The port also pays the cost first (battle_runner.gd:232-233), before `execute_move` reads `focus_n` (battle_manager.gd:49).
- [E] The formulas match term by term.

The "Attack" category:
- [E] `executeMove` has no "Attack" branch. The status effect, though, is applied by the conductor after `executeMove`, whatever the category (CONDUCTOR:70-102).
- [E] Shatter Bolt (F42/DoAction_6.as:1716-1719) costs 10 focus, is a Missile, has category "Attack", status `SHATTERBOLT` and proc chance 2.4. A proc chance above 1 means it always procs on a hit.
- [E] `SHATTERBOLT` (F42/DoAction_10.as:1629-1636) is a unique Ice debuff with stun contribution 1 and duration 2.
- [E] Frost Terror uses Shatter Bolt (F42/DoAction_13.as:250-251, move 521 in `movesA`).
- [E] In the port, `execute_move` returns `{}` for an unhandled category before it reaches `_apply_status_effect` (battle_manager.gd:59-63). The stun never lands, and `_show_move_result` shows nothing for the empty result (battle_scene.gd:858).

Status: Matches, except Shatter Bolt. That move deals no damage in either game; in the original it stuns, in the port it does nothing.

### 2.5 Crits, misses, dodge

- [E] Original hit roll (CONDUCTOR:360-386):
  - Shock moves and stunned targets always hit.
  - Otherwise `s = target.SPEEDU / (caster.SPEEDU * move[9])`. The miss chance is `s * (3s + 3)`, capped at 75 and set to 0 below 1.
  - The move hits when the next KRS value exceeds the miss chance. KRS is a 100-entry table of `random(100)` values cycled by `KRRR` (F42/DoAction_5.as:1-9) and rebuilt for every unit spawn (F42/DoAction_14.as:27-34).
- [E] The port's `_accuracy_roll` (battle_runner.gd:280-294) uses the same formula with `randi_range(0, 99)`. Fresh RNG replaces the KRS table by design, so the table's period-100 replay is not reproduced. [I] No gameplay effect is expected from that.
- [E] Neither game checks teams in the roll, so friendly and self-targeted moves can miss in both.
- [E] For a non-positive denominator the port returns 75 (battle_runner.gd:285-286), where the original divides and gets Infinity, NaN or a negative ratio. With current data this never happens: Shock skips the roll, and no non-Shock move has a speed modifier <= 0 (479 records checked in dev/converted_json/moves_abilities.json).
- [E] Crits: `perScript` (F42/DoAction_8.as:251-266) matches `_crit_roll` (battle_manager.gd:91-100). Both pass a fixed defense of 1 for heals (F42/DoAction_8.as:157; battle_manager.gd:172-173).

Status: Matches.

### 2.6 Buffs, dispel, sswitch

Buff math:
- [E] `applyBuffKrin` (F42/DoAction_10.as:137-255), `buffTicker` (14-136) and `applyChangesKrin` (256-482) correspond to the port's `apply_buff`, `tick_buffs` and `apply_changes` (scripts/battle/combat_unit.gd:359-465, 479-528, 315-349). The stat math matches.
- [E] That includes the quirk where a FOCUSCHANGE buff resets focus to full (F42/DoAction_10.as:274-279). The quirk never fires in practice: the only focus-change buffs are COLDNEU and WARMNEU, which are passives with duration -1 (computed from the buff data).
- [E] Both games apply the player's passive talents at battle start (frame_201/DoAction.as:5-11 with frame_217/DoAction_4.as:1-18; battle_runner.gd:94-104).

Dispel:
- [E] Both use up the dispel budget on every polarity match, even when the chance or resist roll fails (CONDUCTOR:32-46; battle_runner.gd:314-317).
- [E] Order differs. `applyChangesKrin` re-sorts `BUFFARRAYK` by CD descending on every call (F42/DoAction_10.as:344), and the dispel walks the slots in array order (CONDUCTOR:26-52). The original therefore removes the buffs with the most turns left first. The port walks `buff_slots` in insertion order and never sorts (battle_runner.gd:305-320; combat_unit.gd:315-349).
- [E] Timing differs. The original recomputes the target's derived stats once, after `executeMove` (CONDUCTOR:103):
  - A dispelled buff's direct fields (STUN, SSWITCH, HEALMOD, IDOT, SILENCED; F42/DoAction_10.as:140-150, 171) drop before the hit.
  - Its stat deltas (`changeArray`, applied only in `applyChangesKrin`) still count for the hit that dispelled it.
  - The port calls `apply_changes` inside `_resolve_dispels`, before the hit (battle_runner.gd:321-322).

sswitch (TIEDYE, RETROGRADED, SUBVERSION, BUFF1):
- [E] The mechanics match. Damage becomes a capped heal (F42/DoAction_8.as:133-149; battle_manager.gd:151-154). A heal becomes damage that can kill (F42/DoAction_8.as:189-229; battle_manager.gd:187-193).
- [E] The display differs; see bug (d) in section 4.

Tick numbers:
- [E] `buffTicker` shows each DoT and HoT tick as a floating number (F42/DoAction_10.as:85-96), and the conductor waits another 25 frames for it (CONDUCTOR:118-127).
- [E] The port emits no tick event. `_execute_action` only logs a death caused by a DoT (battle_runner.gd:214-217). Not implemented.

Status: Diverges.

### 2.7 Focus and life costs

- [E] At execution both check focus >= cost and life > flat + round(LIFEU * percentage) (CONDUCTOR:355; battle_runner.gd:226-230). In the data no move has a flat life cost, and 16 have a percentage cost (computed from the move data).
- [E] For AI affordability both use strict > on life (F42/DoAction_9.as:52, 87, 128; scripts/battle/battle_ai.gd:270-275).
- [E] At player selection the original refuses the pick, with a message, when focus is short (F42/DoAction_11.as:65) or when `LIFEN <= cost` (80).
- [E] The port's UI checks focus (battle_scene.gd:456-459) but not life. The runner then rejects the move at execution as MOVE_FAILED (battle_runner.gd:227-230). The player loses the turn instead of being told to pick again.

Status: Diverges.

### 2.8 Cooldowns and silence

Player cooldowns:
- [E] Set when the move fires (CONDUCTOR:388-392), at the index taken from `moveCoolDownBreaker` (F42/DoAction_11.as:96).
- [E] Decremented on every dispatch of the player's slot (CONDUCTOR:338-349), and zeroed at the start of each battle (frame_201/DoAction.as:3).
- [E] The port does the same at battle_runner.gd:199-202 and 247-248.
- [E] In both, the decrement comes before the set inside a dispatch, so a cooldown of 1 skips one player turn.

AI cooldowns:
- [E] `LowerCD` runs before every decision (CONDUCTOR:609, 657, 685; F42/DoAction_9.as:445-464). The cooldown is set when the move fires (CONDUCTOR:401-404).
- [E] The port does the same at battle_runner.gd:145, 185-189 and 236-246.
- [E] In both, a cooldown of 1 never makes an AI unit skip a turn.

Silence:
- [E] Silence blocks moves that cost focus, and it is checked at selection only: for the player at F42/DoAction_11.as:70, for the AI at F42/DoAction_9.as:52, 87 and 128.
- [E] The port checks it at battle_scene.gd:447 and battle_ai.gd:271-272.
- [E] Neither game re-checks silence at execution (CONDUCTOR:350).

Status: Matches.

### 2.9 Required target buffs

- [E] The player cannot pick a move when the target has fewer than `KRINABILITYB[24]` active buffs of element `[23]` (F42/DoAction_11.as:60-64, using `checkBuffsOnUnit` at 129-146).
- [E] In the data, Shatter needs 3 Ice buffs (four variants, F42/DoAction_6.as:852-890) and Corruption needs 1 Shadow buff (1607-1609).
- [E] Corruption is the Psychological starting move (frame_41/DoAction_2.as:150-151; scripts/entities/talent_tree.gd:63).
- [E] The AI never checks the requirement. `checkBuffsOnUnit` exists only in F42/DoAction_11.as.
- [E] The port does not map fields 23 and 24 (scripts/battle/ability.gd:109-169), and nothing gates on them.

Status: Not implemented. A Psychological player can open with Corruption on a target that has no Shadow buff.

### 2.10 Stun

- [E] The rules match:
  - STUN is a running total (F42/DoAction_10.as:140; combat_unit.gd `apply_buff`).
  - A stunned caster does not act (CONDUCTOR:350; battle_runner.gd:206-208).
  - Stunned targets are always hit (CONDUCTOR:360; battle_runner.gd:281).
- [E] The original's animation trigger is in `applyChangesKrin`, which plays `stun` or `outofstun` when STUN differs from STUNP on an active unit (F42/DoAction_10.as:467-481). `applyChangesKrin` runs:
  - after every successful hit on the target (CONDUCTOR:103);
  - at the end of every `buffTicker` (F42/DoAction_10.as:135);
  - at battle start (frame_217/DoAction_4.as:13).

  So the stun animation starts at the impact that applied the stun.
- [I] The port makes the same comparison after every event (battle_scene.gd:957, 966-973), which lands at the same moment.
- [E] The hit reaction differs:
  - The original skips the `hit` label while STUN != 0 (F42/DoAction_8.as:100-103, 204-207).
  - The port sets HIT on every damage result (battle_scene.gd:879-880). That replaces the STUN state, and HIT returns to IDLE when its label ends (scripts/entities/character_visual.gd:296-299).
  - In the port, a stunned doll stands back up at its first hit while it is still stunned.

Status: The rules match; the presentation diverges.

### 2.11 AI move choice

- [E] The port follows `AImoveAdder` (F42/DoAction_9.as:1-444) section by section:

  | Step | AS (F42/DoAction_9.as) | Port (battle_ai.gd) |
  |---|---|---|
  | friends scan | 8-34 | 37-48 |
  | ABS pool with phase lock | 39-60 | 50-67 |
  | attack and defense pools | 76-162 | 84-122 |
  | heal target | inside targeting, ending at 398-399 | 124-151 |
  | mode | 168-271 | 153-164 |
  | pick | 272-344 | 166-210 |
  | targeting | 345-442 | 216-257 |

- [E] Divergence 1, the player's heals:
  - When the player picks a heal, the original adds its estimate to `healedThisTurn` (F42/DoAction_11.as:92-95) before the AI allies decide (CONDUCTOR:645-669).
  - The port never adds the player's heal; only battle_ai.gd:251 writes `healed_this_turn`.
  - [I] As a result, an AI ally can choose to heal a target the player is already healing.
- [I] Divergence 2: the original relies on stale globals, and the port does not reproduce them.
  - `focusCheck` and `playerFocusCheck` are globals written only when a teammate is active (F42/DoAction_9.as:8-34). A unit with no active teammate compares against the previous caller's values.
  - `focusMove` is reset only at lines 84 and 296. The override at 405-408 still retargets any chosen move at `playerFocusCheck`, ABS moves included. So an ABS move picked after a previous caller left `focusMove` true goes to that caller's focus target.
  - Line 93 raises `focusMove` for any ally-targetable move, not only for Focus moves.
  - `D_Array_*` is rebuilt only in the non-ABS branch (134-139), and `aliveEnemies` (413) carries over the same way.
  - Whether any of this changes a decision in real play needs a runtime trace (section 6).
- [I] The pool scans use `for..in` over arrays (39, 50, 76, 85). AS2's enumeration order cannot be settled from source, and it decides which index wins `focusSelectNum`, since the last match is kept.
- [E] 43 of the 75 units have ABS pools, and 25 have attack-pool moves that can raise `focusMove` (computed from the unit data).

Status: Matches by intent. Divergence 1 is [E]; divergence 2 is [I].

### 2.12 Aggression stances

- [E] The five presets match (F42/DoAction_12.as:1-6; scripts/entities/party.gd:29-35).
- [E] In the original, stances never carry over:
  - Every companion spawns in Tactical (F42/DoAction_14.as:208-213).
  - The stance button writes only the live battle unit (B3289 press:9-14).
  - `Krin.agMode` is seeded to 2 (F42/DoAction_17.as:42), and no unit creation code reads it.
- [E] In the port, the companion is built with the saved stance (party.gd:197), and the stance row saves the player's choice (battle_scene.gd:645, via party.gd:144).
- [E] Enemies match: they spawn with `agMode = 0` and their template's `agressionArray` (F42/DoAction_14.as:110, 129-133; port `from_character`, combat_unit.gd:222-228).

Status: Persistence is port-only.

### 2.13 Enemy and guest creation

- [E] `krinAddNewUnit` applies the difficulty multipliers (F42/DoAction_14.as:35-52). Then, for any unit below level 10, it multiplies strength, magic and speed by `0.7 + 0.03 * L` and life by `0.5 + 0.05 * L` (80-85).
- [E] This covers every positive template id, enemies and guests alike. Companions use their own formula, without these multipliers (216-220).
- [E] The port's `from_character` applies only the difficulty multipliers (combat_unit.gd:197-201).
- [E] Computed for Prison Guard (F42/DoAction_13.as:71, ratios 10/10/5/12) on Normal:

  | Level | Original life/strength/speed | Port life/strength/speed |
  |---|---|---|
  | 1 | 212/8/12 | 386/11/17 |
  | 5 | 484/16/23 | 645/18/28 |
  | 9 | 986/29/43 | 1038/30/44 |

- [E] Zone 1 story enemies are levels 1 to 7 (for example 105 at level 5 and 109 at level 7: resources/battles/105_KBR105.tres:28, 109_KBR109.tres:49). The whole first zone is therefore harder in the port.
- [E] Level resolution for X and Z matches (F42/DoAction_14.as:56-79; battle_setup.gd:58-68).

Status: Diverges.

### 2.14 Money reward

Bug (a) in section 4 has the full trace.
- [E] The original averages the battle-data level over every slot that passes the spawn gate (F42/DoAction_14.as:25, 86-92; DefineSprite_3142/frame_9/DoAction.as:39-43). That gate admits a companion marker whenever `friendArrayX` holds a roster index, even before that companion has joined.
- [E] The port averages the plevel of slots 2, 4 and 6 (battle_scene.gd:1010-1016; scripts/battle/battle_rewards.gd:54-61).
- [E] Computed over resources/battles, 51 non-training battles pay differently. The markers carry level 1, so the port overpays in every case checked:

  | Battle | Original | Port |
  |---|---|---|
  | 109 | 36 | 130 |
  | 105 | 25 | 78 |
  | 513 | 309 | 823 |
  | AS 703 (stored 999) | 552 | 1150 |

Status: Diverges.

### 2.15 XP reward

Player:
- [E] `EnemyXP` sums the plevel of active enemy-team units at battle start (frame_217/DoAction_2.as:202-204, 251-253) and is divided by their count (DefineSprite_3142/frame_9/DoAction.as:6).
- [E] The result feeds `expWorkOut` (F42/DoAction_2.as:1-13). The player bar clip caps the level at 30 (DefineSprite_3142/frame_9/PlaceObject3_3002_1197).
- [E] The port matches (battle_rewards.gd:66-69, 98-103; scripts/entities/leveling.gd:126-145).

Companions:
- [E] The companion bars (PlaceObject3_3002_1111 and _1154, in the same frame) iterate `Krin.friendlySlotsFFTT`. That list is filled only for companions that actually spawned (F42/DoAction_14.as:192).
- [E] The port grants XP to every deployed companion in the roster, whether or not the battle has their marker (battle_scene.gd:1011-1016; battle_rewards.gd:105-108). Battle 508 (`[69,71,72,0,0]`, no markers) is one such case.

Status: The player matches; companion eligibility diverges.

### 2.16 Drops

- [E] Both pre-roll drops at battle load: the item chance table plus three rare pools, in 15 slots (frame_201/DoAction.as:233-270; battle_rewards.gd:32-50). Matches.
- [I] B3012 (buying, and claiming drops) fills the last empty inventory slot in `for..in` order, which source cannot settle.

### 2.17 Leveling, stat points, train caps, respec

- [E] `getStat`, `givePoints` and the residue carry (F42/DoAction_15.as:1-56) match combat_unit.gd:165-189 and leveling.gd:50-72.
- [E] Menu stats are `StatSets + ceil(getStat(ratio, level, true))` (DefineSprite_3142/frame_1/DoAction.as:87-190), matching leveling.gd:78-85.
- [E] Both raise the same four stats: life, strength, magic and speed (B3068-B3071; scenes/ui/menu/abilities_window.tscn:463-466). The level cap of 30 matches.
- [E] Train caps and the X/Z clamps match (frame_41/DoAction_2.as:46-70; zone_progression.gd:42; battle_setup.gd:58-68).
- [E] Respec differs:
  - The original gates only on money (B3179 release:6).
  - `respecSet` is reset to 5 on a new day and decremented (9-14), but nothing reads it. Its only other reference is the save array (F42/DoAction_20.as:296).
  - The port refuses once `respec_set <= 0` (leveling.gd:160).

Status: Matches, except the respec limit, which is port-only.

### 2.18 New-game stats

What the original does:
- [E] The class buttons call `assignPointsStart` (B2735 release:4, B2736 release:5, B2737 release:4). It adds the 19 level-1 points, split by class ratio, onto `StatSets0` (F42/DoAction_15.as:57-78). `StatSets0` starts as `[5,6,5,3,0]` (F42/DoAction_17.as:51).
- [E] Before the first battle, `frame_180` sets `StatSets0 = [5,6,5,3,0]` and `equipArray0 = [0,11,0,4,8,5,0]` (frame_180/DoAction.as:7-8).
- [E] `[5,6,5,3,0]` is exactly the starting gear's bonuses: White T-shirt life 5, A Broken Pipe strength 6, Levo Jeans magic 5, Proverse All Stars speed 3 (resources/items/11_White_T-shirt.tres, 5_A_Broken_Pipe.tres, 4_Levo_Jeans.tres and 8_Proverse_All_Stars.tres, lines 23-29 of each).
- [E] `statPoints` is 0 (frame_41/DoAction_2.as:79).
- [E] The class split is thrown away, and the new character holds only its gear bonuses.

Every route from class select reaches frame 180:
- [E] The options button sends the player to CS_INTRO or CS_INTRO2 (B2770 release:2-11).
- [E] The cutscene clip then plays `gotoSceneKrin` (frame_263/PlaceObject2_3466_80/CLIPACTIONRECORD onClipEvent(enterFrame).as:33).
- [E] On the tutorial path, battle 2 queues CS_INTRO2 (frame_165/DoAction.as:8), and `frame_293` sets `gotoSceneKrin = "IntroSeq2"`.
- [I] The root then plays from IntroSeq2 (frame 166) to frame 180 without stopping. No root frame script exists between 166 and 180, but a nested clip could still stop the root, and this was not checked at runtime.

What the port does:
- [E] `new_game` zeroes `stat_allocated` and runs `assign_points_start` (scripts/entities/player_save.gd:131-132).
- [E] `GameData.new_game` then equips the same gear, which adds its attributes to `stat_allocated` (scripts/autoload/game_data.gd:54-57; scripts/entities/equipment.gd:159).
- [E] The port's level-1 character therefore has 19 more stat points than the original's. Computed: a Biological character gets +3 life, +7 strength, +1 magic and +8 speed. That is 19 * [7,14,4,15] / 40, rounded down, plus two residue points to the largest shares.
- [E] A respec makes the two games agree again: both reseed from the gear and grant the full points (B3179 release:15-16, 37-46; leveling.gd:166-177).

Status: Diverges.

### 2.19 Talent tree

- [E] All 84 nodes of `loadTalents` (frame_41/DoAction_2.as:112-220) match `TREES` in talent_tree.gd (compared node by node).
- [E] The learn rules match: every prerequisite required, 1 point per rank (B3096; `can_learn`/`learn` at talent_tree.gd:360-412).
- [E] The required level matches (`guessLevel`, DefineSprite_3142/frame_25/PlaceObject3_3100_153 onClipEvent(load):18; talent_tree.gd:181-182).
- [E] So do the 5 starting points plus 1 per level (frame_41/DoAction_2.as:77-78).

Status: Matches.

### 2.20 Equipment and team select

- [E] Equipping the player (B2981 press) matches scripts/entities/equipment.gd:112-168: class and level requirements, and stat, piercing and defense bonuses added and removed.
- [E] The original also equips companions, under the same rules:
  - B2981 acts on `Krin.MenuPlayerSelect`, and a plain click on a party member sets it (B2895 press:30-37).
  - A shift-click on the same button edits `friendArrayX`, the deployed pair (B2895 press:2-29).
- [E] The port gives companions a fixed gear list, documented as cosmetic (party.gd:40-43). Nothing writes `party_deployed` after `initialize_save` (party.gd:102).

Status: The player matches. Companion equipment and team select are not implemented.

### 2.21 Zone progression and cutscenes

These match [E]:
- questHub, trainFight and trainFightCap (frame_41/DoAction_2.as:41-70 vs zone_progression.gd:19-42);
- the unlock rule (frame_449/DoAction.as:29 vs zone_progression.gd:128-138);
- the cutscene battles (frame_219/DoAction.as:32-55 vs zone_progression.gd:60);
- the roster unlocks (frame_219/DoAction.as:57-64 vs party.gd:112-118);
- the shop ids per zone (B3187, B3212, B3219, B3238, B3203, B3241 and B3256 vs scripts/autoload/store_manager.gd:16).

These diverge:
1. [E] The zone 7 gate.
   - The map shows zone 7 on Heroic only when `achGet[4]` is set (frame_449/DoAction.as:4-16).
   - Achievement 4 is Legend, awarded for beating 513 on Heroic without training (DefineSprite_3142/frame_9/DoAction_2.as:24-36).
   - The port calls the flag all-star (zone_progression.gd:141-149), and `can_access_zone` never passes it (scripts/autoload/zone_manager.gd:29). Zone 7 can never open.
2. [E] The zone 4 boss replay.
   - B3239 press:9 replays `progressMax - 1`, battle 408.
   - Line 14 compares against the undefined `progressMax1`, so the first fight against 409 is not flagged as a boss fight.
   - The port replays 409 and flags it (zone_progression.gd:96-100).
3. [E] `usedTraining` on boss replays.
   - The story orbs for zones 1 to 5 set it when the player replays a beaten boss (B3188 press:9; B3213, B3220 and B3204 press:12; B3239 press:12). The ROME/JAPAN orb, B3243, does not.
   - Training orb B3186 sets it (press:15); B3242 (ROME) does not.
   - The port sets it on every training fight and never on a replay (zone_manager.gd:53-64).
   - In the original, replaying a beaten boss therefore forfeits Predator and Legend.
4. [E] Proceed after a win (B3004 release:8-29) checks, in order:
   - a pending cutscene;
   - otherwise, the zone map after any boss fight (`bossJustPwned2`, frame_219/DoAction.as:9-16);
   - otherwise, the skills screen after a level-up;
   - otherwise, the hub.

   The port returns to the hub unless a cutscene opened the map (battle_scene.gd:1037-1067).
5. [E] After CS_CUT5 the original goes to `endMenu` (frame_219/DoAction.as:51-55); the port goes to the map (zone_progression.gd:67-73). This is a documented port choice.
6. [E] Not implemented, and none of these names occur under scripts/ or scenes/:
   - CS_CUT1, which plays before the first story attempt at 109 (B3188 press:18-24);
   - the intro cutscenes CS_INTRO and CS_INTRO2 (B2770 release:2-11);
   - the tutorial battle 2 (frame_165/DoAction.as:1-10).

### 2.22 Battle outcome

- [E] In the original, a defeat and a draw are both game over:
  - The end clip routes winCondition 0, 1 and 2 to loseCombat, winCombat and drawCombat (DefineSprite_3355/frame_85/DoAction.as:5-16).
  - drawCombat jumps to loseCombat (frame_241/DoAction.as:1).
  - loseCombat reaches frame 230, which sets `gameoverKrin` and plays `resetHere` (frame_230/DoAction.as:1-5).
  - frame_43/DoAction.as:21-25 then shows `gameOverMenu`.
- [E] The port shows a result label for a defeat or a draw (battle_scene.gd:1028-1033), then continues to the hub (1065-1067).

Status: Diverges.

### 2.23 Achievements

- [E] The ids and conditions match (DefineSprite_3142/frame_9/DoAction_2.as:1-67; scripts/entities/achievements.gd:41-64).
- [E] Achievements 1 (Black Magic, 308), 3 (Predator, 212) and 9 (Over the Ashes, 703) test ids that the port stores as 399, 299 and 999. They can never fire (2.1).
- [E] All Star (5) is never awarded in the port:
  - The original scans the four save slots (F42/DoAction_20.as:6-29). Its live-game branch reads `Krin.data.Class` (34-44), which is never assigned, so the current session only counts through a saved slot.
  - The port's `check_all_star` (achievements.gd:70-77) is called only from test/unit/test_achievements.gd.
- [E] The Pacifist counter (AchVal1, achievement 2: 408 under 2000) overcounts in the port:
  - The original adds the player's damage after the shield, and only when the target is not under sswitch (F42/DoAction_8.as:79-94).
  - The port adds amount plus shielded amount for every DAMAGE result from slot 1, sswitch heals included (achievements.gd:83-90).
- [E] The teammate counters differ but have no effect today:
  - The original counts spawned companions (F42/DoAction_14.as:190-191).
  - The port counts any unit in slots 3 and 5, guests included (achievements.gd:91-94).
  - None of the achievement battles has a guest (308, 600, 601 and 602 checked).

Status: Diverges.

### 2.24 Battle speeches

- [E] Unknown speakers:
  - Named speakers resolve through `getPNum` (F42/DoAction_14.as:285-302), which returns NaN for a name that is not on the field.
  - `_root["playerKrinNaN"].active` is undefined, so the original skips the line (CONDUCTOR:815, 852-856). The `== NaN` test at 805 can never be true.
  - The port maps an unknown name to slot 0, the narrator, and shows the line (battle_runner.gd:498-506, 480).
- [E] The player's battle unit is always named "Sonny" in the original (frame_201/DoAction.as:201). The port uses `save.name_user` (combat_unit.gd:269), so with a custom name every "Sonny" line falls back to the narrator.
- [E] A line runs for `timeToSay * 30` frames (CONDUCTOR:841). The port caps lines at 4 s (battle_scene.gd:927), which cuts, for example, battle 2's 6.5 s and 5.5 s lines (F42/DoAction_14.as:316-317).
- [E] Narrator lines show in both (`playerKrin0.active = true`, frame_201/DoAction.as:113-115).

Status: Diverges.

### 2.25 Battle presentation

All of these are [E] from code; none was run.
- Shield absorb:
  - The original shows the `shield` frame, plays the shield clip and `sfx_shield`, and skips the hit flash and hit animation (F42/DoAction_8.as:70-76).
  - The port returns DAMAGE with amount 0 (battle_manager.gd:138-140), then shows "0", plays HIT and plays a hit voice (battle_scene.gd:859-882).
- Miss sound:
  - Melee and Shock set `missToMake` to undefined (CONDUCTOR:407, 447), so their misses are silent. Missile misses play `sfx_magicmiss` (415).
  - The port plays `sfx_magicmiss` on every miss (battle_scene.gd:897).
- Damage numbers:
  - Every hit calls `KrinNumberShow` twice, at F42/DoAction_8.as:80 and again at 84 (or at 137 under sswitch).
  - Each call attaches a new clip at the next depth (F42/DoAction_7.as:37, 75-79). A normal hit draws two identical numbers; an sswitch hit draws a green number over an element-colored one.
  - The port draws one number.
- Dead units: MODEL1 frame 360 hides the shadow, and frame 371 removes the clip (DefineSprite_166_MODEL1/frame_360 and frame_371). The port fades the doll to 55% and keeps it (character_visual.gd:300-305).
- Melee end point: the original stops at the target's edge minus both half-widths (F42/DoAction_4.as:46-55). The port uses a fixed 55 px (battle_scene.gd:903-909).
- Pacing:
  - The next action dispatches 26 frames after impact (CONDUCTOR:112-138). A melee caster starts its runback 15 frames after impact (F42/DoAction_4.as:87-95). So the next action begins in the middle of the runback.
  - The port waits for `melee_finished` first (battle_scene.gd:773-777).
  - After a Missile miss, the original keeps raising the impact flag until the bolt leaves the screen (F42/DoAction_4.as:188-205), and each raise restarts the 26-frame wait (CONDUCTOR:12-15).
- DoT and HoT numbers: see 2.6.

### 2.26 Combat log

- [E] The AS has no combat log; searching the export for combatlog or battlelog finds nothing.
- [E] scripts/battle/combat_log_panel.gd is port-only.
- [E] Under sswitch it prints "hits ... for N" for what was actually a heal (combat_log_panel.gd:72-73).

## 3. Notes audit

### 3.1 DECODED_ALGORITHMS.md

| Lines | Entry | Verdict |
|---|---|---|
| 10-17 | krinMelee constants | Correct (F42/DoAction_4.as:213-218). |
| 21 | `spdXCoEFFER = clamp(1.5 - 1.45 * goRat, 0, 1)` | Incomplete. The code only caps at 1 (F42/DoAction_4.as:102-111). Harmless, because goRat stays below 1 during the dash, which keeps the value above 0.05. |
| 22-23 | arrival takes "~14 frames ... REGARDLESS of distance" | Wrong. Arrival time depends on (distance - half-widths) / distance. Simulating F42/DoAction_4.as:99-131 gives 13 frames with zero half-widths, 11 at 300 px with 60 px of half-widths, 9 at 300 px with 100 px, and 4 at 150 px with 100 px [E computed]. |
| 24-27 | impact 15 frames after the strike | Correct (F42/DoAction_4.as:73-84). Missing two things: the flag is raised on a miss too (80), and the next action starts 26 frames after impact, in the middle of the runback (CONDUCTOR:112-138). |
| 27-29 | runback takes "~18 frames" | Approximate. The same simulation puts the doll within 1 px of home after 4 to 22 frames, and snaps its position after 15 to 72. |
| 34-55 | krinBoltMake | Correct. Incomplete: on a miss the flag is raised on every frame after the crossing until the bolt leaves (F42/DoAction_4.as:188-205). |
| 56, 123 | multi-target bolts | Dead content. No move sets `[20]`: it defaults to 0 (F42/DoAction_6.as:48), and there is no `hackMove[20]` assignment. |
| 58 | "multi-target ... isn't ported" | Half stale. The runner handles `hits_all_enemies` (ability.gd:166; battle_runner.gd:265-271); only the projectile is single. |
| 60-70 | cast dispatch | Correct (CONDUCTOR:412-469). |
| 76-77, 80-89, 92 | stun as a running total, and its labels | Correct. |
| 78 | stun trigger fires "once per unit's own per-turn tick" | Wrong. `applyChangesKrin` also runs after every successful hit on the target (CONDUCTOR:103) and at battle start (frame_217/DoAction_4.as:13), so the stun animation starts at the impact. |
| 93-94 | port is "finer-grained than the original's once-per-unit-tick cadence" | Rests on the same wrong reading as line 78. |
| 96-104 | menu bars, item looks | Not re-checked in this review. |
| 109 | stances "persisted as PlayerSave.ag_mode" | Describes the port. The original resets companions to Tactical every battle (2.12). |
| 113 | class buttons 2735/2736/2737 = Bio/Hydro/Psycho | Correct (B2735 release:2, B2736 release:4, B2737 release:2). |
| 114 | equipArray0 | Correct. Missing: the same frame resets StatSets0 and throws away the class split (2.18). |
| 115 | sell-back | Correct (B3015 press). |
| 119-131 | presentation per animation type, colors, numbers | Correct. Missing: melee and Shock misses are silent, and every hit draws its number twice (2.25). |
| 146 | audit row "Stun/cast animations: code-driven slump/raise" | Stale. The port plays the real labels (line 74 of the same doc; character_visual.gd:247-267). |
| 151 | audit row "Sky horizon: empirical y = 292" | Stale. The strip position now comes from battle_layout.json (battle_scene.gd:242-246). |
| 153 | audit row "Battle countdown: not displayed, 120 s" | Stale and wrong. The port shows a countdown (battle_scene.gd:159-161), and the original's timer is 120 frames, on Heroic only (2.3). |

Entries worth adding:
- the stat reduction for units below level 10;
- the money accumulator;
- the frame_180 overwrite;
- the required-buff gate;
- the Heroic timer.

### 3.2 KNOWN_GAPS.md

| Lines | Entry | Verdict |
|---|---|---|
| 6-12 | Dispel, resolved | Correct as far as it goes. It misses the CD-descending order and the recompute timing (2.6). |
| 14-20 | "Attack" category: Shatter Bolt does nothing in the original either | Wrong. The conductor applies status effects for every category (CONDUCTOR:70-102), so the original Shatter Bolt stuns. Closable from source. |
| 24-25 | Stun | Correct. |
| 26-27 | Silence, via `BattleRunner.get_player_usable_moves()` | The rule is correct; the citation is stale. No such function exists. The player gate is battle_scene.gd:444-449. |
| 28-29 | Reflect is dead | Correct. `REFLECT` is written (F42/DoAction_10.as:141) and never read. `REFLECTDMG` is only initialized (frame_201/DoAction.as:181). |
| 64-74 | Talents, resolved | Correct. |
| 107 | No tutorial | Correct. Note that the tutorial battle is stored as 49 (2.1). |
| 108-109 | Wolfgang/Amber vs Teco/Catelin naming | Moot in the web build, because party ids 4 and 5 never join. The only roster writes are F42/DoAction_17.as:10 and frame_219/DoAction.as:59, 63. |
| 118 | progress bar | Correct. |

### 3.3 NEXT_PHASES.md

| Lines | Entry | Verdict |
|---|---|---|
| 100-102 | "The 120-second decision countdown ... deliberately does NOT force-pass the turn at 0 like the original did" | The units and the scope are wrong: the original's timer is 120 frames, on Heroic only (2.3). |
| 229-233 | the 109 mislabel is fixed | Correct for 109, 409 and 513. The same defect still hides 212, 308, 603 and 703 (2.1). |
| 241 | "Shatter Bolt: ... the original never handled it either" | Wrong (see KNOWN_GAPS.md:14-20 above). |
| (absent) | | Not mentioned anywhere: CS_CUT1, the intro cutscenes, the tutorial battle, the Heroic real-time mode, game over, companion equipment, team select. |

### 3.4 SWF_DIFFERENCES.md

- Lines 30-33, the relabel mechanism: correct.
- Lines 35-37 say "the other 6 reset points (49/99/299/399/699/999) don't land on a battle any current zone formula needs". That is wrong:
  - 299, 399, 699 and 999 are the zone 2, 3, 6 and 7 bosses under `zone * 100 + progress` (zone_progression.gd:94).
  - 49 is the tutorial battle, 2 (frame_165/DoAction.as:2).
  - Only 99 (AS 55) is unreachable (2.1).

### 3.5 CLAUDE.md

- The battle-id entry says three of nine `battleCreationID` resets relabel the battle just populated. That is wrong: all nine do. Three are corrected and six are not. Not edited, per the brief.

### 3.6 Code comments that reasoned instead of measured

| Location | Claim | What the source says |
|---|---|---|
| battle_runner.gd:18-21 | "120-second decision countdown" | 120 frames, Heroic only (2.3). |
| battle_scene.gd:440-443 | the runner re-validates cooldown and silence | The runner checks focus and life only (battle_runner.gd:226-230), as does the original (CONDUCTOR:350-355). |
| battle_rewards.gd:13-18 | money counts every unit spawned from a positive template id | It also counts companion markers (F42/DoAction_14.as:25, 86-92). |
| zone_progression.gd:66 | 210 is "zone 2's boss" | Zone 2's boss is 212 (progressMax 12, frame_41/DoAction_2.as:47). |
| zone_progression.gd:141-143 | zone 7 needs "the all-star achievement" | It needs achievement 4, Legend (frame_449/DoAction.as:5). |
| party.gd:40-43 | companion gear is "cosmetic until the equip system lands" | The original equips companions, stats included (B2895 press:30-37, B2981 press). |
| player_save.gd:20-21 | the upsell replaces "the Psychological text" | It replaces the Hydraulic text (B2736 rollOver:4-12). |
| player_save.gd:54, leveling.gd:8-10 | 5 respecs per day | Never enforced (B3179 release:6-14). |
| player_save.gd:60-61 | the consumer of progress_level_on "hasn't been located" | It is read by the music checks (F42/DoAction.as:59-67) and by the legacy story button (B3181 press:5-16). |
| battles.py:21-34 | three of the nine resets relabel a battle | All nine do (2.1). |

## 4. The five suspected bugs

### (a) Money inputs

Verdict: this is a bug, but not the one suspected. The guests in 49 and 508 make no difference; the companion markers do.

How the original computes money:
- [E] The accumulator lives in `krinAddNewUnit`. For slots 2 to 6 it adds the battle-data level when two conditions hold:
  - the slot passes the spawn gate (F42/DoAction_14.as:25): a positive template id, or a marker with `friendArrayX[marker + 2] > 0`;
  - the template id and the level are both non-zero (86-92).
- [E] It adds the battle-data level, not the spawned plevel.
- [E] It runs before the companion branch checks whether the roster slot is filled (187-188), so a marker counts even before that companion has joined.
- [E] The default deployment, `friendArrayX = [1, 2]` (F42/DoAction_17.as:18), counts both markers.
- [E] Money is `round(0.7 * respecValue(sum / count))` (DefineSprite_3142/frame_9/DoAction.as:39-43; F42/DoAction_16.as:1-4).
- [E] XP has its own accumulator over active enemy-team units only (frame_217/DoAction_2.as:247-253). Using enemy levels for XP is right.

What the port does:
- [E] battle_scene.gd:1016 passes `enemy_levels` (slots 2, 4 and 6) as both inputs.

Effect:
- [E computed] The guests change nothing. Battle 49 (AS 2) has guest 48 at level 1 beside enemy 49 at level 1, and battle 508 has guest 71 at the enemies' level of 22.
- [E computed] The markers change 51 non-training battles; 2.14 has examples.

[I] Fix shape: build the money list from the battle definition. Take every non-zero entry with a non-zero level whose id is positive or whose `party_deployed` entry is non-zero, and use its battle-data level.

### (b) Submission checks

Verdict: not a bug in the runner. The gap is in selection.
- [E] At execution the original checks that the move id is not 0, the target is active and the caster is not stunned (CONDUCTOR:350), then checks focus and life (355).
- [E] It checks silence and cooldown only when a move is chosen: for the player at F42/DoAction_11.as:70 and 75, for the AI at F42/DoAction_9.as:41, 52, 78 and 87.
- [E] The runner matches this (battle_runner.gd:206-212, 226-230).
- [E] What the port lacks are two selection gates: life (F42/DoAction_11.as:80) and required target buffs (60-64).
- [E] The comment at battle_scene.gd:440-443, which says the runner re-validates, is wrong.

### (c) `_can_afford` uses strict >

Verdict: correct.
- [E] The original uses strict > for life everywhere: the AI at F42/DoAction_9.as:52, 87 and 128; the player at F42/DoAction_11.as:80, which rejects <=; execution at CONDUCTOR:355.

### (d) sswitch display

Verdict: yes, the original shows the swapped outcome, and the port does not.

The original:
- [E] Full Damage under sswitch: the number is drawn in the element color (F42/DoAction_8.as:80), then again in heal green on top (137). Life goes up (138-143), and the heal flash plays (148). There is no hit animation and no voice.
- [E] Heal under sswitch: the number is drawn in the Shadow color (191) and life goes down (192-197). The hit flash plays (203), the hit animation plays unless the target is stunned (204-207), and the target dies if life reaches 0 (208-228).

The port, damage under sswitch:
- [E] It still returns DAMAGE (battle_manager.gd:145-162). The scene therefore shows an element-colored number.
- [E] It lowers the displayed bar while real life rises (battle_scene.gd:867-871), until the next snap (939-949).
- [E] It plays HIT and the hit voice (879-882), and the log says "hits" (combat_log_panel.gd:72-73).

The port, a heal under sswitch:
- [E] It returns HEAL (battle_manager.gd:187-193). The scene shows "+N" in heal green and raises the displayed bar (battle_scene.gd:883-889).
- [E] If that heal kills, the doll never plays its death: the HEAL branch never calls it, and the DEATH event is skipped for MOVE causes (battle_scene.gd:729-737; battle_runner.gd:519-520).

Reachable in current content:
- [E computed] TIEDYE, RETROGRADED, SUBVERSION and BUFF1 are applied by moves 173, 475, 476, 559 and 610. These include ABS moves of Cult Leader (30), Mayor (69), Clemons (47) and Flower Zombie (57).

### (e) `hits_all_enemies`

Verdict: a dead path in both games.
- [E] The original animates the caster once and fires one bolt per living enemy (CONDUCTOR:432-443).
- [E] The first bolt to arrive executes the move on every target (CONDUCTOR:54-69). Later arrivals only restart the end counter (12-19).
- [E] The port would emit one MOVE event per enemy (battle_runner.gd:265-271).
- [I] Each MOVE event plays the caster's animation (battle_scene.gd:757-823), so the caster would animate once per enemy. Not run.
- [E] No move sets `[20]`: the default is 0 (F42/DoAction_6.as:48), and there is no `hackMove[20]` assignment. Nothing needs fixing unless content changes.

## 5. Other places the port reasoned instead of measured

These are the cases from sections 2 and 3 where a doc or comment reasoned its way to a claim that the source contradicts.
1. KNOWN_GAPS.md:14-20 and NEXT_PHASES.md:241 reasoned from `executeMove` alone that Shatter Bolt does nothing. The conductor applies its status effect (2.4).
2. SWF_DIFFERENCES.md:35-37, battles.py:21-34 and CLAUDE.md reasoned that only three relabels matter. Four story bosses and the tutorial are still hidden (2.1).
3. DECODED_ALGORITHMS.md:78 reasoned the stun trigger's cadence from `buffTicker` alone (3.1).
4. DECODED_ALGORITHMS.md:22-23 claims melee arrival does not depend on distance. That holds only with zero half-widths (3.1).
5. NEXT_PHASES.md:100-102 and battle_runner.gd:18-21 read 120 as seconds (2.3).
6. battle_rewards.gd:13-18 read the money gate as "positive template id" and missed the marker term of F42/DoAction_14.as:25 (2.14).
7. zone_progression.gd:141-149 named the zone 7 flag after All Star (2.21).
8. player_save.gd:131-132 ports `assignPointsStart` faithfully, but misses that frame_180 overwrites it (2.18).
9. battle_runner.gd:498-506 assumes unknown speakers are narrator lines. The original drops them (2.24).
10. battle_scene.gd:440-443 assumes the runner re-validates moves (bug (b) in section 4).

## 6. Open questions

1. AS2 `for..in` order over arrays. It decides the AI pool order and `focusSelectNum` (F42/DoAction_9.as:39-106), the order of the `moveMatrix2` rebuild, and which inventory slot B3012 picks. Settling it needs a Flash or Ruffle run.
2. Whether the stale `focusMove`, `focusCheck` and `D_Array_*` values change a decision in real play (2.11). Settling it needs a runtime trace of `AImoveAdder`.
3. A runtime confirmation that a new game reaches frame 180 on both intro paths (2.18).
4. The cost-failure path (CONDUCTOR:475-531). Unconfirmed:
   - The clip-local `moveBammer` is false there (set at 354).
   - If a buff tick re-raises the impact flag (511-521), the impact block (12-19) could run the failed move for free, using a stale `strikeSuccess`.
   - A cost failure at execution needs a teammate to drain the caster within the same half-turn, and no such case was found.
5. The chain from `blacker5.play()` (CONDUCTOR:260) to DefineSprite_3355 frame 85 was not traced.
6. Roster unlocks, the ArmorGames upsell and the other flow facts come from the web build. The Steam build's AS was not exported (2.20, 3.2).
7. Design calls for the overhaul, rather than source questions: whether to keep or drop the port's leniencies. They are saved stances, the respec limit, returning to the hub after a defeat, going to the map after CS_CUT5, the display-only timer, and fresh RNG in place of KRS.
