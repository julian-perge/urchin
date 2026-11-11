# Spec: victory

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `victory` of [the capability map](107-capability-map.md). It depends on [window-shell](107-window-shell.md) (`WindowShell`, `ShellPanel`, the `drop` slot and `RightColumn`), [hub](107-hub.md) (the Hub that hosts it, `set_inert`, `set_art_visible` and `show_battle_hint`) and [inventory](107-inventory.md) (the experience bar's pieces). Through them it uses `FloatBox`, the rect test, the compare tool and `strings.json` from ui-foundation.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

This spec follows the decision in [#122](https://github.com/julian-perge/urchin/issues/122): Victory becomes a Window on the Hub and is no longer a Screen.

## Objective

Rebuild Victory as the original builds it: the `win` label (frame 9) of `KRINMENU`, opened over the Hub after a win. It has three columns: the experience rows, the dropped items with the gain text and Proceed, and the right column.

Success is that every piece sits where the SWF places it, the experience rows animate as the original's do, Proceed follows the original's order of outcomes, and the battle no longer owns the Victory overlay.

## Assumptions

- Decided with you in this session: the experience rows animate and Proceed stays inert until the player's row finishes.
- Decided in #122: the Hub loads first and the Window opens over it. The fade ends on black and cuts to the Hub with the Window already open. The hotbar is inert until Proceed. No ADR. #122 did not watch the original play the cut, so the compare tool's build confirms it.
- Behavior of drops stays as it is: a click on a drop moves it into the first free inventory cell, and a full inventory leaves the drop claimable.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. The rect extractor from ui-foundation is the source the test reads. The shell and the right column are window-shell's and are placed, not redefined. This label has no close X, so the Window sets `close_visible` to false.

### Panels

| Panel | Variant | Placement | Box |
| --- | --- | --- | --- |
| left, experience | `tall` | 2990 scaled 0.894x1.225 | (36.12, 80.96) 222.70x327.24 |
| centre, drops | `centre` | 2988 scaled 1.164x1 | (274.90, 82.15) 213.15x326.50 |
| right column | window-shell | origin (503.50, 81.60), sell slot hidden | |

The port's panels are up to 54.50 px off the SWF today, because the Victory screen reuses the Inventory frame's rects ([#108](https://github.com/julian-perge/urchin/issues/108)).

### Left panel: the experience rows

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2996 `vbbc1` | `MENU[15]`, "Character Experience" | (41.30, 87.10) 213.15x19.00 | `_sans` bold 13 #5e5e5e center |
| 3002, three of them | experience rows, centred at (147.60, 172.65), (147.60, 265.15), (147.60, 357.65) | each 3001: 196.80x83.20 around its centre | solid black |

Each row holds the face 2978 (`avIn`, scaled 1.653), `namerI` 3000 and `levelI` 2999 (`_sans` bold 12 #cccccc), the bar 2867 over its track 2998, and the percent 2997 `exp2`. The rows' inner rects come from the record.

- The row pitch is 92.50 px. Each row is a fixed-height slot in a `FloatBox` column. The port's rows are 62 px apart with a 150 px bar today.
- A row is hidden when its fighter does not exist (`prx == undefined`). The first two rows are the fighting Companions, `friendlySlotsFFTT[0]` and `[1]`, and the third is the player (`prx = 0`).
- Faces are the existing `assets/ui/menu/portraits/` art. The compare tool masks them out.
- The black row backing 3001 and the XP gloss 2998 are new art or a StyleBoxFlat. The gloss is placed on the sprite's timeline at depth 41, and #161 renders it.

**The animation** (`DefineSprite_3142/frame_9/PlaceObject3_3002_*`, `onClipEvent(enterFrame)`):

- Each row starts from its fighter's old experience. For 30 frames it adds `totalXP / 30` per frame, shows `round(exp)` and "%", and sets the bar width to `exp / 100` of 95.10 px.
- A fighter at level 30 or above does not move (`LevelStats[prx] < 30`).
- When `exp` reaches 100, the row subtracts 100, shows "100%", adds one level, jumps the bar to its `level` frame at full width, and rewrites the level text (`MENU[0]` plus the level).
- The player's row also sets `playerLeveled`, adds a skill point and attribute points.
- The animation runs at the SWF's 30 fps. Its counts, 30 frames and 95.10 px, are read from the extractor output and not typed.
- The settlement carries what the animation needs: each fighter's experience and level before the win, and the total gained. The build issue adds those fields to `BattleSettlement`. The save already holds the final values and is not changed by the animation.
- The percent beside the gain, `vb6`, is `round(totalXP)` plus "%", set by the player's row on load.

### Centre panel: drops, gain and Proceed

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 3005 `vb1` | `VICTORY[0]`, "Victory! Items that dropped:" | (288.20, 90.40) 187.30x55.00 | `_sans` 12 #666666 |
| 3013 `dropSlot0` to `dropSlot14` | drops | first centre (305.10, 146.65), 5 columns on a 38 px pitch | `drop` slot |
| 3003 `vb99` | `MENU[12]`, "No Items Found." | (291.20, 163.80) 180.30x70.60 | `_sans` bold 19 #a53030 center |
| 3007 `vb2` | `VICTORY[1]`, "CLICK on the items that you wish to keep!" | (289.20, 244.80) 183.55x49.80 | `_sans` bold 12 #ffff33 |
| 3011 `vb3`, 3010 `vb5` | `VICTORY[2]` and the money, "€" plus the gain | (296.20, 287.20) and (362.70, 287.20) | `_sans` bold 12 #fad95a |
| 3009 `vb4`, 3008 `vb6` | `VICTORY[3]` and the experience, round(totalXP) plus "%" | (296.20, 304.80) and (362.70, 304.80) | `_sans` bold 12 #ffffff |
| 3006 `vb7` | `VICTORY[4]`, "Once you are finished, press below to proceed:" | (290.20, 327.20) 180.30x49.20 | `_sans` 12 #666666 |
| 3014 `vb8` | `MENU[13]`, "Proceed!" | (293.30, 363.65) 173.80x24.10 | `_sans` bold 18 #66ff00 center |
| 3004 | its hit button | (295.30, 368.89) 171.50x25.61 | none |

- The drops are three rows by five columns on a 38 px pitch, so a `FloatBox` column of rows with separation 7. The port draws four columns from (321, 130) today.
- An empty drop slot is hidden and keeps its place, as in Store, so a shorter list does not shift the others. With no drops, `vb99` shows and `vb2` is empty. With drops, `vb2` shows and `vb99` is empty.
- Every string reads from `strings.json`. The port's typed text, "€%d" and "%d%%" formats and hint labels go.
- Proceed is the hit button 3004 over the caption. It is inert until the player's experience row has run its 30 frames (`PauseForScreen2`, set false by the player's row once `sLmT2` counts down). The port's `$ProceedButton.disabled` guard against a second press stays, and the animation lock joins it.

### The right column

`RightColumn` with `show_sell_button(false)`, as the port has today. It shows the player's inventory, so a won item that was clicked lands there.

## The flow

The Victory Window opens when the Hub loads after a win. The battle no longer builds it.

1. The battle ends, fades to black (#86), and hands the Hub a pending result: the `BattleSettlement`, the pending cutscene id and the goto scene.
2. The Hub loads with the Window open and the hotbar inert (`set_inert(true)`). It hides the zone art (`set_art_visible(false)`), as for every Window.
3. Proceed, in the original's order (`DefineButton2_3004 on(release)`):
   1. Autosave when the option is on.
   2. If a cutscene is pending: stop all sound, play the cutscene, then go to the goto scene.
   3. Otherwise, if the win was a boss win that shows the map ([#50](https://github.com/julian-perge/urchin/issues/50)): open the World map.
   4. Otherwise, clear the inert state. If the player levelled up, switch this Window to Abilities. If not, close the Window, show the Hub art, and call `show_battle_hint(battle_id)`.

A boss win that also levels the player up opens only the map, as in the original. The player's level-up flag is the one the animation sets, and it equals `levels_gained` above 0 in the settlement. [#52](https://github.com/julian-perge/urchin/issues/52)'s ZoneManager flag is not needed.

## Replacements

- `scenes/battle/victory_screen.tscn` and `scripts/battle/victory_screen.gd` become the Window, `scenes/ui/menu/victory_window.tscn` (proposed). `victory_experience_row.tscn` and its script move to `scenes/ui/menu/` and become the animated row. The `VictoryScreen` class and its `proceed_pressed` signal go.
- `battle_scene.gd` loses `_pending_cutscene`, `_pending_goto_scene`, the Victory instancing in `_finish_battle`, and `_on_victory_proceed`. The Hub takes them. The battle keeps the fade and the hand-off.
- `GLOSSARY.md` moves **Victory** from the Screen examples to the Window examples, as #122 asked. Game over stays a Screen, because the original's `gameOverMenu` is a menu Screen.
- This module deletes no hand art, because Achievements still uses it.

## Project structure

Follows `AGENTS.md`. New or changed locations:

```
scenes/ui/menu/victory_window.tscn        the Window
scenes/ui/menu/victory_exp_row.tscn       the animated row
scripts/ui/menu/victory_window.gd         flow and Proceed
scripts/ui/menu/victory_exp_row.gd        the 30-frame animation
```

## Code style

As in ui-foundation. The row's animation steps by frame, so a test can drive it:

```gdscript
class_name VictoryExpRow
extends Control

const FRAMES := 30

var _frame := 0
var _exp := 0.0
var _per_frame := 0.0

func step() -> void:
	if _frame >= FRAMES:
		return
	_frame += 1
	_exp += _per_frame
	if _exp >= 100.0:
		_exp -= 100.0
		_level_up()
	_show(_exp)
```

The snippet shows style only. `FRAMES` and the bar width are read from extractor output in the real code. The row advances one step per 1/30 s, driven by a Timer or by `_process` with an accumulator, and a test calls `step()` directly.

## Testing strategy

- **Rect test.** Add `victory_window.tscn` and `victory_exp_row.tscn` to the record. Every piece in the tables passes under 0.5 px, and the Labels' sizes and colors match.
- **Animation (GUT).** Drive `step()`: after 30 steps the bar equals the final fraction. A row that overflows adds one level, shows "100%" once and keeps the remainder. A fighter at level 30 does not move. The total is the same whatever the step order.
- **Proceed order (GUT).** A table of cases: a pending cutscene, a boss win with a level-up, a boss win without one, a level-up without a boss win, and a plain win. Each checks the outcome in the order above.
- **Lock.** Proceed does nothing before the player's row finishes and works after.
- **Drops.** An empty slot is hidden and keeps its place. "No Items Found." shows with no drops. A click moves the drop into the first free cell, and a full inventory leaves it.
- **Hub.** The hotbar is inert while the Window shows and live after Proceed.
- **Strings.** A test compares every label with `strings.json`.
- **Must-fail controls.** Move one drop slot 20 px in a copy of the scene and expect the rect test to fail. Change the frame count in a copy of the extractor output and expect the animation test to fail.
- **Compare tool.** A `victory` entry in `chrome` mode, scoring the panels, the row backings and the slots inside their masks. It uses the win frame and the prototype's `win_chrome` and `win_panels` modes from `prototype/victory-containers`. Faces are masked out. The bar comes from the first passing run, and the reference shifted 20 px scores over it. The build confirms the fade-to-black-then-cut that #122 left unwatched.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number, color, frame count or string from the rect record, an extractor or `strings.json`. Keep the drop click behavior. Commit `.png.import` sidecars.
- Ask first: A change to `BattleSettlement`'s fields beyond the before-values. A change to the order of Proceed's outcomes. A change to the fade.
- Never: Build the Window inside the battle scene. Let the hotbar respond while the Window shows. Pay out or save before the fade has played. Type a string or a frame count.

## Out of scope

- The fade to black before the result screens ([#86](https://github.com/julian-perge/urchin/issues/86)).
- The cutscenes, the SKIP control, the World map and its trigger ([#49](https://github.com/julian-perge/urchin/issues/49), [#50](https://github.com/julian-perge/urchin/issues/50)). This spec places Proceed's order and leaves each branch's own build to them.
- The post-battle hint's content, which the hub spec owns.
- The original's order in which a drop picks its inventory cell. Whether it takes the first or the last free cell is [#38](https://github.com/julian-perge/urchin/issues/38).
- The Game over screen.

## Success criteria

1. `victory_window.tscn` places every piece within 0.5 px of the SWF, with the three experience rows at a 92.50 px pitch and the drops on five columns.
2. The experience rows animate over 30 frames, overflow into a new level, and Proceed stays inert until the player's row finishes.
3. Proceed follows the original's order for the five cases in the table.
4. The battle scene no longer builds a Victory overlay, and the Hub opens the Window.
5. Every label comes from `strings.json`.
6. The compare tool scores the `victory` entry under its bar, with the 20 px control over it.
7. `GLOSSARY.md` lists Victory as a Window.
8. `uv run gut` passes.

## Open questions

1. **Proceed's order is being extended right now.** [#49](https://github.com/julian-perge/urchin/issues/49), [#50](https://github.com/julian-perge/urchin/issues/50), [#52](https://github.com/julian-perge/urchin/issues/52) and [#53](https://github.com/julian-perge/urchin/issues/53) each change `_on_victory_proceed` in `battle_scene.gd`. This module moves that code. The plan stage should order the move after them, or fold them into it. Decide which.
2. **The pending result's home.** The Hub needs the settlement, the cutscene and the goto scene to survive the scene change from the battle. This spec proposes a field on `ZoneManager`, next to `open_zone_map_on_load`. The build issue may choose another home and says so.
3. **Level cap.** The original's rows stop at level 30, and the port's levels go higher. The spec copies the original's limit. Confirm that the port's higher levels are not meant to animate.
4. **The sell slot.** The Victory window shows no sell slot, as the port has it. The inventory note lists the sell slot for `shop` only, but the `win` label's list was not read for it. The build issue checks the label.
