# Spec: title-slots

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `title-slots` of [the capability map](107-capability-map.md). It depends on [ui-foundation](107-ui-foundation.md): the viewport, `FloatBox`, the rect test, the compare tool and the Theme.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

This spec covers [#91](https://github.com/julian-perge/urchin/issues/91). It replaces #91's triage note about Game Manual and Credits, because [#120](https://github.com/julian-perge/urchin/issues/120) and [#121](https://github.com/julian-perge/urchin/issues/121) were decided a day later.

## Objective

Rebuild the first three menu Screens of the original as Godot scenes on containers, at the SWF's rects:

- the title, `mainMenu` (root frame 46), which the port does not have;
- the choice, `subMenu` (frame 56), which the port starts on today;
- the slot list, `dataMenu` (frame 74).

The module also owns the pieces every menu Screen shares: the background, the Back caption, and the caption look.

Success is that the game opens on the title, Play leads to New Game and Load Game, the slot list reads as the original's rows, and every piece sits where the SWF places it.

## Assumptions

- Decided with you in this session:
  - The slot list shows only the save's name, as the original does.
  - Captions use one shared Theme variation, with no shader.
  - The title places the Game Manual and Credits captions, and their wiring waits for those Screens.
  - Each Screen is its own scene.
- Decided in closed tickets: PvP Arena, "Play MORE Games!" and "Play the Original Sonny" are left out ([#91](https://github.com/julian-perge/urchin/issues/91) triage, [#121](https://github.com/julian-perge/urchin/issues/121)). The remaining captions keep their SWF positions, so a gap shows where those lines were.
- The name, class and options panels stay in `main_menu.tscn` as they are. The new game flow spec rebuilds them.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. The rect extractor from ui-foundation is the source the test reads.

### Shared by every menu Screen

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 2701, 307, 2700 | the background: backdrop, swirl, paint splatter, at depths 1, 2 and 5 | the union of their boxes | radial #374962 to #181c23, black swirl at alpha 64 with a Glow, splatter | One TextureRect of `start_background.png`, placed at its Stage rect. `extract_start_screens` already writes it, at 2x. |
| 2703 | `whatToSayX`, "Back" (`MENU[26]`) | (488.15, 532.15) 304.10x30.85 | `_sans` bold 24 #ffffff right, caption look | Label |
| 2702 | its hit button, to `mainMenu` | (604.44, 534.45) 188.12x26.80 | none | A flat Button |

- The background PNG is 1600x1150 today, which is the 800x575 Stage at 2x. It is stretched over the 800x600 viewport now, and after the viewport change in ui-foundation it lands 1:1. The scene sets its rect from the record.
- Back goes to the title from every menu Screen. The port's Back goes to the choice panel today, which the title replaces.
- The caption and its hit button are separate pieces. The hit button has its own rect and no art, because the original's menu buttons have none.
- `game_over_screen.tscn` and `ending_screen.tscn` load the same background. They keep their own copies until their spec moves them to `menu_background.tscn`.

### The caption look

The original draws each caption as `_sans` bold text with a Glow (#000000, blur 3, strength 10) and a DropShadow (#000000, blur 8, distance 2). The port draws a 4 px Label outline for both.

- One Theme type variation, `MenuCaption` (proposed), in `scenes/ui/project_theme.tres`: bold font, white, a black outline for the Glow, and a black shadow offset for the DropShadow. The shadow has no blur.
- Each Label sets its own font size, because sizes differ by caption (36, 18, 26 and 24).
- The build issue chooses the outline size and shadow offset by eye against `dev/source_files/exported_assets/frames/46.png`, and records both values in the Theme.
- The compare tool hides text, so it does not score this. The rect test checks size and color.

### The title, `mainMenu` (46)

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 321, shape 320 | the "SONNY 2" logo, at (403.50, 180.20) | (123.20, 119.80) 549.55x97.70 | linear #68d9f4 to #ffffff, Glow #33ffff (blur 17) | TextureRect of `logo.png` |
| 2699 and 2696 | `whatToSay1`, "PLAY" | (241.95, 304.50) 304.10x45.60 | `_sans` bold 36 #ffffff center | Label. The SWF draws it twice, once with the filters, so one Label with the caption look covers both. |
| 2692 | hit button for PLAY | (242.01, 305.10) 302.27x40.00 | none | flat Button, goes to the choice |
| 2698 | `whatToSay2`, "Game Manual" | (313.15, 365.50) 304.10x24.10 | `_sans` bold 18 #ffffff left | Label |
| 2693 | its hit button | (313.93, 367.36) 230.33x20.78 | none | flat Button, goes to Game Manual |
| 2694 | `whatToSay5`, "Credits" | (313.15, 455.50) 304.10x24.10 | as 2698 | Label |
| 2690 | its hit button | (313.93, 457.81) 230.33x20.78 | none | flat Button, goes to Credits |

- Left out: 2697 and 2688 ("Play More Games!", y 395.50), 2695 and 2691 ("Play the Original Sonny", y 425.50), and the Armor Games logo and copyright line. The gap under Game Manual stays.
- The logo is new art. `extract_start_screens` gains a logo render through `render.py` at zoom 4, written to `assets/ui/menu/logo.png` (proposed). The Glow is drawn, and the Stage rect comes from the same render. The logo is also placed on the choice, on Credits and on the intro frames, so this module owns it.
- Layout: one `FloatBox` column of fixed-height slots. The pitches are 61 px (Play to Game Manual) and 90 px (Game Manual to Credits), so each slot's height is set from the record. Each slot is a plain Control holding the Label and the hit Button at their SWF offsets inside it.
- Game Manual and Credits open Screens that a later spec adds. The buttons exist and emit a signal, and the wiring comes with those Screens.

### The choice, `subMenu` (56)

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 321 | the logo again | as the title | |
| 2709 | `whatToSay1`, "New Game" (`MENU[21]`) | (241.00, 290.10) 304.10x45.60 | `_sans` bold 36 #ffffff center |
| 2707 | its hit button | (241.06, 290.70) 302.27x40.00 | none, sets `dataMode` to save, goes to name |
| 2708 | `whatToSay2`, "Load Game" (`MENU[22]`) | (241.00, 350.10) 304.10x45.60 | as 2709 |
| 2706 | its hit button | (241.06, 350.70) 302.27x40.00 | none, sets `dataMode` to load, goes to the slot list |

- Left out: 2705 and 2704, "PvP Arena" (`MENU[85]`, y 410.10).
- Layout: a `FloatBox` column with a 60 px pitch, in the same style as the title.

### The slot list, `dataMenu` (74)

Four rows, each three captions in `_sans` bold 26 and one hit button.

| Row | "Slot" (white, right) | Number (white, left) | Save name (#9dee66, left) | Hit button |
| --- | --- | --- | --- | --- |
| 1 | 2734, (195.00, 192.05) 107.85x33.05 | 2726, (308.00, 192.05) 121.30x37.10 | 2733, (356.50, 192.05) 385.10x35.55 | 2722, (213.00, 193.20) 113.80x30.00 |
| 2 | 2729, (195.00, 246.05) | 2725, (308.00, 246.05) | 2732, (356.50, 246.05) | 2721, (213.00, 248.70) |
| 3 | 2728, (195.00, 303.05) | 2724, (308.00, 303.05) | 2731, (356.50, 303.05) | 2720, (213.00, 304.20) |
| 4 | 2727, (195.00, 357.05) | 2723, (308.00, 357.05) | 2730, (356.50, 357.05) | 2719, (213.00, 359.70) |

- "Slot" is `slotNamerText`, `MENU[23]`. The name is the save's `name_user`, or "< Empty Slot >" for an empty slot (`frame_74/DoAction.as:1-10`).
- The row shows only the name. The port's "Lv" and "Zone" text goes. That is a change a player can see, and it follows the original, so it needs no ADR.
- The hit button covers the "Slot" label and the number, not the name, as in the original. A click on the name does nothing.
- Row pitches are 54, 57 and 54 px. `FloatBox` has one separation, so each row is a fixed-height slot with its own height from the record, inside a `FloatBox` column with separation 0.
- Behavior stays as it is. New Game goes to class select from any slot. Load Game loads a slot only when it holds a save, and a click on an empty slot does nothing. Hover on a slot in New Game mode shows the overwrite warning (`MENU[21]` over `MENU[25]`), and in Load Game mode shows nothing.
- The pick text 2718 is left out with the arena.

## Decisions to record

- **ADR 0002 widens.** From "branding" to "branding and every link to the publisher's site", as #121 decided. The edit lands with this module's title task.
- **A new ADR, 0006 (proposed), leaves out PvP Arena.** The arena button, `arenaMode` and `pickText` stay out, which [#91](https://github.com/julian-perge/urchin/issues/91) triage already decided. The ADR also records the gap under the choice's second caption.

## Replacements

- `scenes/main_menu.tscn` keeps the name, class and options panels. Its `ModePanel` and `SlotPanel` become instances of the new scenes, and a title panel is added in front of them. The game opens on the title, so `project.godot`'s main scene does not change.
- `scripts/ui/main_menu.gd` changes `_show_screen`, `_on_back_pressed` and `_refresh_slot_buttons`. The slot buttons VBox goes.
- The "Sonny 2" Label (`ModePanel/Title`) goes, replaced by the logo.
- The hand-set offsets and the comment block above `ModePanel` in `main_menu.tscn` go with the panels they describe.

## Project structure

Follows `AGENTS.md`. New locations:

```
scenes/ui/menu/menu_background.tscn   the shared background
scenes/ui/menu/menu_back.tscn         Back caption and hit button
scenes/ui/menu/title_panel.tscn       mainMenu
scenes/ui/menu/mode_panel.tscn        subMenu
scenes/ui/menu/slot_panel.tscn        dataMenu
scripts/ui/menu/                      one small script per panel, signals only
assets/ui/menu/logo.png               from extract_start_screens
```

## Code style

As in ui-foundation. A panel scene types its Stage numbers once and emits signals that `main_menu.gd` connects. This is the shape of the title panel's script:

```gdscript
class_name TitlePanel
extends Control

signal play_pressed
signal game_manual_pressed
signal credits_pressed

func _on_play_button_pressed() -> void:
	play_pressed.emit()
```

## Testing strategy

- **Rect test.** Add the five new scenes to the record. Every piece in the tables above passes under 0.5 px, and the Label sizes and colors match.
- **Behavior (GUT).** The game starts on the title. Play shows the choice. Back from each panel shows the title. The slot rows show the name or "< Empty Slot >", with no level or zone. A click on an empty slot in Load Game does nothing. A click on the name column does nothing.
- **Must-fail controls.** Move one hit button 20 px in a copy of a scene and expect the rect test to fail. Break one Back target and expect the Back test to fail.
- **Logo extractor.** A second run leaves `logo.png` byte-identical. Its rect times 4 equals its pixel size. A `uv run pytest` test covers the pure parts.
- **Compare tool.** Entries for frames 46, 56 and 74 in `chrome` mode, scoring the background and the logo with text hidden. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number from the rect record or an extractor. Keep the slot behavior listed above. Commit `.png.import` sidecars.
- Ask first: A change to the name, class or options panels. A hover state on a menu caption. A shader on a caption.
- Never: Add an Armor Games link, caption or logo. Add PvP Arena. Wire Game Manual or Credits to a Screen that does not exist. Hand-place a coordinate the rect record can supply.

## Out of scope

- The name, class and options panels and the intro frames: the new game flow spec.
- The Game Manual and Credits Screens and their wiring.
- PvP Arena.
- The tooltip's look. The overwrite warning keeps the shared tooltip as it is.
- The Game over and Ending screens' use of the background.

## Success criteria

1. The game opens on the title. Play shows the choice. New Game and Load Game lead to the name panel and the slot list as before.
2. Every piece in the tables is under 0.5 px from its SWF position, and every Label's size and color match the record.
3. The slot list shows four rows with "Slot", the number and the save's name, and no level or zone.
4. Back returns to the title from the choice, the slot list, the name, class and options panels.
5. The title has no publisher link, no PvP Arena and no "Play More Games!" line. ADR 0002 and ADR 0006 are in `docs/adr/`.
6. `logo.png` is byte-identical on a second run, and the compare tool scores each entry under its bar with the 20 px control over it.
7. `uv run gut` passes.

## Open questions

1. **A corrupted slot.** The port shows "(corrupted)" for a save that fails to load. The original has no such case and shows "< Empty Slot >" when `nameUser` is undefined. This spec keeps "(corrupted)", a port-only state, and asks you to confirm.
2. **Wiring order.** The title's Game Manual and Credits buttons depend on Screens that no module in this map covers. The plan stage needs to block that one task on the later specs. Confirm that is the order you want.
3. **Hover on captions.** The original's hit buttons have no art ("No menu button has art of its own"), so this spec adds no hover look. The state records of the hit buttons were not read for this spec. The build issue checks them, and a hover look would need your approval.
