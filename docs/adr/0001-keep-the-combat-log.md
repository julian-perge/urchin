# Keep the combat log the original never had

The original Sonny 2 has no combat log, and the port's battle screen has one: `CombatLogPanel` (`scripts/battle/combat_log_panel.gd`), added in `e5e0b06`. We keep it as a deliberate departure, because it makes a fight easy to follow and to debug, so a fidelity pass should not remove it. That is safe because it only narrates. It starts hidden, nothing but the player's own press opens it, it changes no battle rule, and every line reports an event the battle screen already plays. The one condition is that each line says what a move or a Buff tick did to its target, not what kind of move it was.

AS paths below are relative to `dev/source_files/action_script/`, and character ids are the web build's, from `dev/source_files/swf_xml/sonny-2-2900.xml`. The research behind this is sections 2.26 and 4(d) of `docs/research/2026-11-07-original-logic-vs-port.md`.

## What the original shows

`rg -i 'combatlog|battlelog|combat_log|battle_log' dev/source_files/action_script` finds nothing. That export is the web build's ActionScript. Run over `dev/source_files/swf_xml/`, the same pattern finds nothing in either build's XML dump, and those dumps hold every instance name, export name, frame label and text field definition.

Every piece of text the original puts on the battle screen clears itself:

- `KrinNumberShow` (`frame_42/DoAction_7.as`) draws each number, miss and shield mark over its target. The clip it attaches, DefineSprite 53 `NumberFixer`, removes itself when its animation ends (its frames 68, 130, 182 and 234).
- `KrinCombatText` (DefineSprite 2852) is the closest thing to a log, and it is a one-line popup. Its text field, DefineEditText 2849, is single-line, the sprite shows one message at a time, and its frame 125 clears the message 123 frames after it appears, about four seconds at 30 fps. In battle it says why the player's pick was refused (`frame_42/DoAction_11.as:60-89`, played at line 125), why the player's own move failed when its turn came (the conductor, `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:477-489` and `536-543`, both only when the caster is the player), and to wait for the ring when the player clicks too early (`frame_217/DoAction.as:18-27`).
- The speech box, `combatScript` (DefineSprite 3367), holds one line of dialogue at a time, fades out when that line's time is up, and the next line replaces it (`frame_217/PlaceObject2_3367_634`).

The web build's only `UIScrollBar` sits in DefineSprite 3332, the PvP arena's Character Code box on root frame 200, so nothing in the original scrolls back through a battle.

## What the log adds

- A record that stays. The log keeps the last 200 lines of the fight (`MAX_LINES`), one for each hit, heal, focus gain, miss, stun, failed move, dispel, Buff tick that did something, death and speech line.
- Text for every unit. In battle, `KrinCombatText` only ever tells the player about their own picks and moves. The log writes the same kind of line for an enemy's stun or failed move.
- The whole fight so far. `battle_scene.gd`'s `_play_events` hands each event to the log just before playing it, whether the panel is open or not, so opening the log mid-fight shows everything since the fight began, up to the 200-line cap.

The log reads nothing but the event and the units' names. The phase change, the end of the battle and a pass get no line. The runner logs an event for every Buff tick, and `BuffTick.did_something` marks the ones that did something. Those are the ticks whose total is not 0 and the ticks whose total a shield soaked whole. The original draws a Floating number for each of them (`frame_42/DoAction_10.as:64-98`). A tick that only moved Focus or ran a buff out did nothing, because the original draws nothing for it. A total under 1 gets no line either, because the original draws its number with no digits.

## Off until the player opens it

`scenes/battle/combat_log_panel.tscn` sets `visible = false`, and the instance in `scenes/battle_scene.tscn` does not override it. The only thing that shows it is the Log button, `LogToggleButton` in `BottomBar/Panel3`, whose `_on_log_toggle_pressed` in `battle_scene.gd` flips the panel's visibility on each press. `ZoneManager._launch_battle` loads `battle_scene.tscn` fresh for every fight, so the log starts hidden and empty each time, and `test_combat_log_toggle_and_live_narration` in `test/integration/test_battle_scene.gd` pins the hidden default. A player who never presses the button never sees a line, and the button is the only part of the log that is always on screen. Off by default was the project owner's call when the log came in (`e5e0b06`).

## Each line says what the move did

The original reports a move by its outcome. Under an sswitch buff a damage move heals its target: the original draws the number a second time in heal green, raises the target's life and plays the heal flash (`frame_42/DoAction_8.as:137-148`). A heal hurts its target instead: its number is drawn in the Shadow color, the hit flash plays, and the target can die (191-228). The log has nothing in the original to be checked against, so the only way it stays faithful is by reporting the outcome the original shows. Each line has to be worded from what happened to the target, not from the move's effect category or the result's type.

When this ADR was written, on 2026-11-07, the log broke that rule. `BattleManager._apply_damage` and `_execute_heal` swap the life math under sswitch but still return `DAMAGE` and `HEAL`, so `CombatLogPanel._format_move_line` prints "hits" for damage that healed and "heals" for a heal that hurt, even one that killed. [#24](https://github.com/julian-perge/urchin/issues/24) fixes the wording, and [#47](https://github.com/julian-perge/urchin/issues/47) makes each result state its effect so the log stops working it out.

A Buff tick's line follows the same rule. It says what the tick did to its unit: the damage that got through the shield, the healing, or that the shield soaked the whole tick. A line for damage names the element that dealt it. A tick that hurts its unit only because sswitch turned its healing around has no such element, so its line names none. A line never says which buff dealt the tick. The original draws the same three things for a tick (`frame_42/DoAction_10.as:68-96`). Under sswitch the original flips the total's sign before it draws anything (`frame_42/DoAction_10.as:59-62`). So a tick of damage that heals the unit reads as healing, and a tick of healing that hurts it reads as damage.

Every claim about the original here comes from reading the ActionScript and the XML dumps, not from running the game.
