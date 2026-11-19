# Spec: game-manual

Source issue: [#365](https://github.com/julian-perge/urchin/issues/365). Module `game-manual` of [the capability map](107-capability-map.md). It depends on [ui-foundation](107-ui-foundation.md) (the rect test, its extractor, the compare tool and the Theme) and on [title-slots](107-title-slots.md) (the menu background, the Back caption, the `MenuCaption` look and the title's `game_manual_pressed` signal).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Build the Game Manual Screen, the original's `designMenu` (root frame 124), and open it from the title. The port has no Game Manual today: the title's Game Manual caption emits `game_manual_pressed`, and nothing connects to it.

The original's Screen has two outlined panels. The left one lists five topics, and the right one shows one text field. A click on a topic fills the field with that topic's help text. Back goes to the title.

Success is that Game Manual on the title opens the Screen, each topic shows its `MANUALEX` text, Back returns to the title, and every piece of frame 124 that the port keeps sits where the SWF puts it, checked to 0.5 px.

## Assumptions

- Each open question was answered in the spec session by the rule "take what matches the original" (orchestrator rule for this run). No answer departs from the original, so this spec adds no ADR.
- `frame_124/DoAction.as` runs each time the root timeline enters `designMenu`. It fills `xRx1` to `xRx5` from `MANUAL[0]` to `MANUAL[4]` and `xRx6` from `EXPLAINEXTRA`, "Please select a topic.", and stops. So the body reads "Please select a topic." on every open, not the last topic read.
- Each topic hit button sets `xRx6` on release (`DefineButton2_2800` to `DefineButton2_2804`, `BUTTONCONDACTION on(release).as`). Sorted from the top of the Stage, the buttons are 2800, 2804, 2803, 2802 and 2801, and they set `MANUALEX[0]` to `MANUALEX[4]` in that order. So topic n from the top shows `MANUALEX[n]`, under the caption `MANUAL[n]`.
- Back is hit button 2702, whose release goes to `mainMenu`. The port opens the title.
- The Screen is a panel of `scenes/main_menu.tscn`, as the choice and the slot list are. It is not its own scene in the tree, because the original's Back only moves the root timeline back to `mainMenu`.

## Pieces

All numbers are Stage px from `timeline.frames()` of the web build, at the label `designMenu`:

| Depth | cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- | --- |
| 1, 2, 5 | 2701, 307, 2700 | the menu background | the Stage | | an instance of `menu_background.tscn` |
| 6 | 2812 | the two panels: one shape with two closed rects | edges (76.05, 91.30) to (383.75, 470.45) and (412.05, 91.30) to (719.75, 470.45) | fill #000000 at alpha 100, 1 px #ffffff line | two Panels with a StyleBoxFlat, `LeftPanel` and `RightPanel` |
| 7 | 2811 | `xRx6`, the body | (425.20, 105.45) 278.60x344.30 | `_sans` 12 #ffffff left, wraps | Label, `MenuCaption` |
| 8 to 12 | 2810, 2809, 2808, 2807, 2806 | `xRx1` to `xRx5`, the five topics, top down | (119.40, 153.50) 225.75x37.40, then 52.5 px apart | `_sans` 12 #ffcc00 center, wraps | Label, `MenuCaption`, color override |
| 35, 27, 29, 31, 33 | 2800, 2804, 2803, 2802, 2801 | the topic hit buttons, top down | their hit squares through the matrix | none | flat Button |
| 13, 25 | 2805, 2702 | Back caption and hit button | as in title-slots | | an instance of `menu_back.tscn` |
| 38, 39, 41 | 2689, 2688, 294 | the Armor Games line, its link and its logo | | | left out, ADR 0002 |

- The record turns a field's bounds into the rect Flash lays its text out in (`label_layout.text_rect`). The scene types the record's numbers, not the field bounds above.
- Frame 124 places Back as edit text 2805 at depth 13 and hit button 2702 at depth 25. The other menu frames place 2703 and 2702 at depths 35 and 36. Edit text 2805 has the bounds, the font, the size and the color of 2703, and both are placed at (490.15, 534.15), so `menu_back.tscn` draws Back here too. The record checks it at depths 13 and 25.
- Every edit text on the frame has the menu captions' Glow and DropShadow. `MenuCaption` draws them, as on the title.
- The topics are a `FloatBox` column of five fixed-height slots, 52.5 px apart. Each slot holds its caption and its hit button at their SWF offsets, as the title's slots do.
- Shape 2812 needs no PNG. Each of its two rects is a solid fill with a 1 px line and square corners, which a StyleBoxFlat draws. The record's `outline` kind gains an optional fill for it (see Testing strategy).

## Answers to the open questions

1. **Does `MANUALEX[0]` still match how the port plays?** Yes. It says "Make sure that you have the tutorial level enabled". The port's new game settings have the Tutorial Level choice (`OptionsPanel/TutorialToggle` in `main_menu.tscn`), and START runs the tutorial fight when it is on (`main_menu.gd`, `_on_start_new_game`). The text stays word for word.
2. **Does `MANUALEX[4]` stay word for word?** Yes. It sends the player to "the Sonny forums on ArmorGames". It is the game's own text and not a link, as `GOTIP[0]` and `ENDING` are. ADR 0002 keeps that kind of sentence ("What the port shows"), so the text stays and ADR 0002 gains one sentence that names it. No new ADR.

## Replacements

- `scripts/ui/menu/title_panel.gd`: the header comment no longer says that nothing connects `game_manual_pressed`.
- `scripts/ui/main_menu.gd`: the header lists the Game Manual Screen, `_show_screen` knows the new panel, and `game_manual_pressed` opens it.
- `scenes/main_menu.tscn`: a `ManualPanel` instance with its own `Back`, as `ModePanel` has.
- `test/integration/test_ui_scenes.gd`: `test_game_manual_and_credits_leave_the_title_up` keeps its Credits half only. Game Manual now leaves the title.
- `SCENES` in `dev/urchin_dev/swf/extract/screen_rects.py`: the `main_menu.tscn` entry names `ManualPanel` as port-only, as it names the other panels.

## Project structure

```
scenes/ui/menu/manual_panel.tscn                 designMenu
scripts/ui/menu/manual_panel.gd                  fills the texts, shows a topic
test/fixtures/screen_rects/manual_screen.tscn    background, panel and Back, for the record and the compare tool
```

## Code style

As in title-slots. The scene types its Stage numbers once, from the record. The script reads its texts by their AS names:

```gdscript
class_name ManualPanel
extends Control

# frame_124/DoAction.as fills the five topics from MANUAL and the body from
# EXPLAINEXTRA each time the Screen opens.
const TOPIC_COUNT: int = 5


func open() -> void:
	$Body.text = Strings.text("EXPLAINEXTRA")


func show_topic(topic: int) -> void:
	$Body.text = Strings.text("MANUALEX", topic)
```

## Testing strategy

- **Record.** `outline_record` accepts a shape with one solid fill and records it as `fill`. A shape with any other fill still raises. The rect test checks that an outline with a `fill` draws its centre in that colour, and that one without draws no centre. `just pytest` covers the extractor change.
- **Rect test.** `SCENES` gains `manual_panel.tscn` and the fixture `manual_screen.tscn`, frame `designMenu`, with every piece in the table that the port keeps, and `left_out=(38, 41)` on the fixture. `just extract-screen-rects` writes the record, and `test/unit/test_screen_rects.gd` checks every piece to 0.5 px.
- **Must-fail controls.** Move a topic hit button 20 px and expect the rect test to name it. Give `LeftPanel` another fill and expect the outline check to fail.
- **Texts.** A GUT test reads `MANUAL`, `MANUALEX` and `EXPLAINEXTRA` from `dev/converted_json/strings.json` itself. It expects the five topic captions, "Please select a topic." on open, and `MANUALEX[n]` after a press on the hit button of topic n. It also expects every `MANUALEX` text to fit the body's rect, so the Label does not grow past the field.
- **Behavior.** Game Manual on the title shows the Screen and hides the title. Back shows the title. A second open shows "Please select a topic." again.
- **Compare tool.** An entry `game_manual` in `dev/screen_compare/screens.json` scores `manual_screen.tscn` against frame 124 in `chrome` mode. The bar comes from the first passing run.
- **Whole suite.** `just gut` passes before each commit.

## Boundaries

- Always: Take a SWF number from the rect record. Read every text from `strings.json`.
- Ask first: A change to the wording of a topic or its text. A hover look on a topic.
- Never: Add the Armor Games logo, line or link. Type a coordinate the record does not check.

## Out of scope

- The Credits Screen and the wiring of `credits_pressed`, which have their own spec session.
- A scroll bar for the body. The original's field has none, and every `MANUALEX` text fits it.

## Success criteria

1. Game Manual on the title opens the Screen, and Back returns to the title.
2. The body reads "Please select a topic." on each open, and each topic press shows its `MANUALEX` string, checked by a test against `strings.json`.
3. `test/unit/test_screen_rects.gd` checks every piece of frame 124 that the port keeps, to 0.5 px, and the 20 px control fails.
4. The panels are StyleBoxFlat Panels whose fill and line the record checks.
5. `just gut` and `just pytest` pass.
