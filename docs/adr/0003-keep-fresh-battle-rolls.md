# Keep fresh battle rolls instead of the original's KRS table

The original takes its hit rolls, crit rolls and AI picks from `KRS`, a table of 100 `random(100)` values that `KRRR` hands out one at a time. The port rolls each one fresh with `randi_range(0, 99)`, and keeps doing that as a deliberate departure, because a player can't tell the two apart. The original refills the table every time a battle loads, so each value is a fresh `random(100)` roll made ahead of time, and the only thing the table adds is that one fight's values come back around after 100 draws. Keeping fresh rolls was the project owner's call when he triaged [#15](https://github.com/julian-perge/urchin/issues/15). What it costs is replay: no test can hand the port a table and check its rolls against the original's one for one.

AS paths below are relative to `dev/source_files/action_script/`. The conductor is the per-frame battle loop, `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as`. The research behind this is section 2.5 of `docs/research/2026-11-07-original-logic-vs-port.md`.

## What the original does

`KRRR` (`frame_42/DoAction_5.as:1-9`) copies `KRS[KRSC]` into `KRSO` and moves `KRSC` on by one, back to 0 after 99. Three places fill `KRS` with 100 new `random(100)` values and set `KRSC` back to 0, and all three run before a fight starts:

- The battle load frame, root frame 201 (`frame_201/DoAction.as:57-64`), for every battle.
- `krinAddNewUnit` (`frame_42/DoAction_14.as:27-34`), once for each slot it fills. Frame 201's slot loop is its only caller (`frame_201/DoAction.as:206, 221, 225`), so no unit joins mid-fight and this refill happens at battle load too.
- The PvP arena's Fight button (`DefineButton2_3339/BUTTONCONDACTION on(release).as:8-15`), just before it sends the game to frame 201, which refills the table again.

So one table serves a whole fight, and nothing carries over to the next one. Nothing saves or loads it either, since `KRS` is in neither save array (`frame_42/DoAction_20.as:296-297`).

The table feeds four things:

- The hit roll (conductor:373-381). The move hits when the next value is above the miss chance worked out at 362-372.
- The crit roll, `perScript` (`frame_42/DoAction_8.as:251-266`).
- The team tiebreak (`frame_217/DoAction_2.as:266-267`). It takes one value when the battle scene loads, and `TeamSelect` only reads it when the two teams' average speeds tie outside single player (line 129), which only happens in the arena. In single player a tie goes to team 1 (121-128), as it does in the port's `_team_select`.
- The AI's choices in `AImoveAdder` (`frame_42/DoAction_9.as`): the aggression check (260-261), the attack, defense and ABS move picks (284-285, 323-324, 336-337), the check that sends a move at the weakest enemy (376-377) and the pick of a random target (384-385).

Every other roll in a fight is fresh in the original too. The dispel chance and resist rolls (conductor:37, 40) and the status effect proc (72) call `Math.random()`, and the item drops at battle load call `random()` (`frame_201/DoAction.as:240, 250, 258, 266`).

## What the port does

`BattleRunner._accuracy_roll`, `BattleManager._crit_roll` and `BattleAI` (`choose_move` and `_uniform_pick`) call `randi_range(0, 99)` wherever the original reads `KRSO`, and each one compares it the way the original does. `random(100)` and `randi_range(0, 99)` both give a whole number from 0 to 99 with even odds. The dispel and proc rolls call `randf()` where the original calls `Math.random()`. The team tiebreak has no counterpart, because the port leaves out the arena (`scripts/ui/main_menu.gd:4-5`).

## Why fresh rolls

Every value in the table comes from its own `random(100)` call, so each roll has the same odds as the port's. The one difference is that inside a fight the 101st draw is the 1st again. Those draws are shared by the hit, crit and AI checks, each with its own threshold, and which check takes which draw depends on how the fight goes, so a repeated value only repeats an outcome when the same check with the same threshold happens to take it. That last part is read from the code, not measured.

The 2026-07-18 decision, as SWF_DIFFERENCES.md and `BattleManager`'s header comment recorded it, gave a second reason: the table belonged to the PvP share-code and anti-cheat system, which the port drops. That doesn't hold. The arena's character code, `exportPvPCode` and `loadPvPCode` (`frame_42/DoAction_20.as:127-289`), stores each numeric value a second time multiplied by 7 and refuses a code whose two copies disagree, and neither function reads `KRS`. The AS has no network code at all (no `XMLSocket`, `LoadVars`, `LocalConnection` or `NetConnection`), and the arena's fight runs on one machine with a table filled from unseeded `random(100)`, so no two games ever share a table. The PvP system gives no reason either way.

## What it costs

- No test can replay the original's rolls. With `KRS` ported behind an injectable seed, the other option #15 offered, a test could load a table and get the hits, crits and AI choices the original makes from it. Seeding Godot's global RNG, as `test_misses_are_move_events_not_a_separate_type` in `test/integration/test_battle_runner.gd` does, only repeats the port's own run. Nothing has captured a table from the original to compare against either, and `dev/data_json/` holds none.
- A replay would also need the port to draw exactly when the original does, and it doesn't. The original spends a value on the team tiebreak in every battle, single player included, and draws for a move or target pick even when there is only one option (`frame_42/DoAction_9.as:283-285`, for example). `BattleAI._uniform_pick` skips the roll when there is one option, and `_accuracy_roll` returns a miss without rolling when both speeds are 0, where the original still draws (conductor:373). Each skipped draw would shift every value after it.
- Every roll comes out of one stream. The port's dispel and proc `randf()` calls share Godot's global RNG with the hit, crit and AI rolls, so adding or dropping one of them moves every later roll in a seeded test. In the original those come from `Math.random()` and leave the table's order alone.

## The zero-speed guard

`_accuracy_roll` has a guard for when `caster.speed_u * move.combat_speed_modifier` is 0 or less. The original has no such check and divides `target.SPEEDU / (caster.SPEEDU * move[9])` as it stands (conductor:362). A caster speed of 0 makes that Infinity, and the cap at 365-367 turns it into a miss chance of 75, which is what the guard uses. When the target's speed is 0 as well, the original divides 0 by 0, the result fails every comparison, and the move always misses, so the guard makes that case a miss too.

On 2026-11-08 a headless script ran the port's own `CombatUnit.from_character`, `Party.build_companion_unit`, `Leveling.compute_stats` and `CombatUnit.apply_buff` over all 479 moves, 470 buffs and 75 units, for every enemy slot of the 99 battles on all three difficulties with training levels resolved for player levels 1 to 30, every companion from its starting level to 30 and every class from level 1 to 30:

- No move gets there by itself. The lowest speed modifier among the 230 non-Shock moves a unit can cast is 0.5, on Exposure (117). Move 0, "None", reads as 0 because its fields are undefined, and nothing ever casts it. The 479 `addNewMove` calls in `frame_42/DoAction_6.as` give the same speed modifiers.
- No unit gets there by itself. The lowest starting speed is 4, for a level 1 Hydraulic player with no points or gear in speed. For an enemy it's 5, Metabii in battle 2 at level 1 on Easy after the below-level-10 reduction, and for a companion it's 14. `CombatUnit.apply_changes` never lets `speed_u` drop below 0, the same way `applyChangesKrin` clamps `SPEEDU` (`frame_42/DoAction_10.as:261, 270-273`).
- Buffs do. No buff changes speed by a flat amount, but 29 lower it by a percent, the furthest by 70% (PSURPRISESHOT, from Secret Police's Surprise Shot). Two Surprise Shots on one target add up to -140%, and The Real Hobo's own Clumsy (-40%) with a Biological player's Cripple rank 4 (-60%) adds up to -100%. Either one takes `speed_u` to 0. Battle 502 fields two Secret Police, and battle 305 fields The Real Hobo.

So the guard does fire in play, on any non-Shock move cast by a unit whose speed debuffs stack to 100% or more. The script ran battle 502 with a level 21 Biological player using Leading Strike, and battle 305 with a level 14 one using Cripple rank 4 whenever it was ready. Over 300 seeded runs of each, the guard fired 597 times, 7 over 6 runs of 502 and 590 over 227 runs of 305, and never with the target at 0 as well. Those runs swapped float arrays into `CombatUnit`, because on 2026-11-08 `CombatUnit._zero_array` still built `Array[int]`, as it had since `d9209749`. An int array truncates every fractional delta a buff writes into it, and a probe that added -0.7 to one read back 0, so no percent buff applied and without the swap the same runs never reached the guard. `test_accuracy_roll_always_misses_when_both_speeds_are_0` and `test_accuracy_roll_keeps_a_75_miss_chance_when_only_the_casters_speed_is_0` in `test/integration/test_battle_runner.gd` pin both cases by setting the speeds directly.

Every claim about the original here comes from reading the ActionScript, not from running the game.
