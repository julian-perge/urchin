# Spec: new-game-settings

Source issue: [#433](https://github.com/julian-perge/urchin/issues/433). Parent: [#1](https://github.com/julian-perge/urchin/issues/1). It depends on [ui-foundation](107-ui-foundation.md) (the rect test, its extractor, the compare tool and `strings.json`) and on [title-slots](107-title-slots.md) (the menu background, the Back caption and the `MenuCaption` look). It follows the in-game [options-window](379-options-window.md), which made the Sound row one setting with `AudioManager.sound_enabled`.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the new-game settings Screen, the original's `optionsMenu` (root frame 93), as its own scene at the SWF's rects. Class select opens it, and START begins the game. Until now it was a hand-placed `OptionsPanel` in `main_menu.tscn`: stock Buttons with typed text such as "Yeah, sure!", three difficulty buttons in place of one row that cycles, a help text cut short, and toggles that kept their state when the player went Back and returned.

Success is that every piece sits where the SWF puts it, checked to 0.5 px, every text comes from `strings.json`, and the rows start at the frame's defaults each time the Screen opens.

## Assumptions

- No user is in this session. Each open question is answered by the rule for this run: take what matches the original, and reuse an existing scene where matching the original would copy one.
- The way in: a class card on `classMenu` (root frame 84) goes to `optionsMenu`. The port's `_on_class_picked` shows the panel.
- The way out: Back, DefineButton2 2702, goes to `mainMenu`, as on every menu Screen. START, DefineButton2 2770, plays CS_INTRO with the Tutorial on and CS_INTRO2 with it off. The port's `_on_start_new_game` already does both.
- [ADR 0011](../docs/adr/0011-leave-out-the-effects-and-graphics-options.md) leaves out the Effects and Graphics rows here too. The rows below them keep their SWF places, so the Screen shows two empty bands.

## Pieces

All numbers are Stage px from `timeline.frames()` of the web build, read at the label `optionsMenu`. The rect record is the source the test reads. AS paths are relative to `dev/source_files/action_script/`.

| Depth | cid | Piece | Box | Look | Port |
| --- | --- | --- | --- | --- | --- |
| 1, 2, 5 | 2701, 307, 2700 | the menu background | the Stage | title-slots | the `Background` of `main_menu.tscn` |
| 10 | 2786 `TitLOL1` | `MENU[33]`, "Please configure your settings:" | (197.05, 72.20) 405.95x20.10 | `_sans` bold 16 #ffffff center | `Heading` |
| 17 | 2779 `t_dif` | `MENU[78]`, "Difficulty:" | (90.65, 116.95) 308.15x25.70 | bold 23 #ff9900 right | `DifficultyLabel` |
| 18 | 2778 `t_dif2` | `MENU[79 + difficulty]` | (410.00, 116.95) 301.35x25.70 | bold 23 #ffff33 left | `DifficultyValue` |
| 21 | 2775 | difficulty hit button | (162.65, 114.95) 439.60x30.00 | none | `DifficultyButton`, flat Button |
| 19 | 2777 `t_tut` | `MENU[82]`, "Tutorial Level:" | (98.85, 152.60) 300.15x26.85 | bold 23 #ff9900 right | `TutorialLabel` |
| 20 | 2776 `t_tut2` | `MENU[84]` "Yeah, sure!" or `MENU[83]` "No, thanks." | (410.00, 152.60) 301.70x25.70 | bold 23 #ffff33 left | `TutorialValue` |
| 33 | 2769 | Tutorial hit button | (162.65, 150.60) 439.60x30.00 | none | `TutorialButton` |
| 6 | 2790 `tit_1` | `MENU[27]`, "Sound:" | (238.90, 189.80) 160.10x26.85 | bold 16 #9dee66 right | `SoundLabel` |
| 8 | 2788 `tit_3` | `MENU[29]` "On" or `MENU[30]` "Off" | (410.00, 189.80) 115.00x26.85 | bold 16 #ffffff left | `SoundValue` |
| 23 | 2774 | Sound hit button | (275.86, 187.80) 229.18x30.00 | none | `SoundButton` |
| 11 | 2785 `tit_8` | `MENU[35]`, "Autosave:" | (238.90, 254.90) 160.10x26.85 | bold 16 #9dee66 right | `AutosaveLabel` |
| 12 | 2784 `tit_7` | `MENU[29]` or `MENU[30]` | (410.00, 254.90) 117.00x26.85 | bold 16 #ffffff left | `AutosaveValue` |
| 27 | 2772 | Autosave hit button | (273.61, 253.90) 229.18x30.00 | none | `AutosaveButton` |
| 13 | 2783 `TitLOL2` | `MENU[34]`, the help text | (121.45, 325.05) 555.15x105.75 | bold 14 #ffffff left, wraps, line pitch 16 | `HelpText` |
| 14 | 2782 `whatToSayY` | `MENU[36]`, "Click here to START!" | (161.55, 456.60) 476.95x26.85 | bold 24 #60ef21 center | `StartCaption` |
| 31 | 2770 | START hit button | (203.69, 456.80) 391.23x26.80 | none | `StartButton` |
| 7, 9, 25 | 2789, 2787, 2773 | the Effects row | | | left out, ADR 0011 |
| 15, 16, 29 | 2781, 2780, 2771 | the Graphics row | | | left out, ADR 0011 |
| 35, 36 | 2703, 2702 | Back caption and hit button | as in title-slots | | an instance of `menu_back.tscn` |
| 38, 39, 41 | 2689, 2688, 294 | the Armor Games line, its link and its logo | | | left out, ADR 0002 |

- The record turns each field's bounds into the rect Flash lays its text out in (`label_layout.text_rect`), and the scene types the record's numbers.
- Every text on the frame carries the caption Glow and DropShadow, so every Label uses `MenuCaption` and overrides the color where it is not white.
- Each hit button draws nothing and spans the caption and the value of its row. The port draws each as a flat Button, as the other menu Screens do. No hover look is added, because the original's buttons have no art.
- The help text is `MENU[34]` word for word. It still names Graphics and Effects, as the Options Window's help text does.
- The Screen's pieces sit at fixed Stage positions with no shared pitch, so the scene places each node by its own offsets, as `options_window.tscn` does, with no `FloatBox`.

## Behavior

- **Open.** `frame_93/DoAction.as` runs each time the frame plays. It sets `Krin.autoSaver`, `Krin.sound`, `Krin.graphics` and `Krin.tutorOn` to true, `Krin.qual` to "HIGH" and `Krin.difficulty` to 0. `frame_93/DoAction_2.as` then fills every field. So `OptionsPanel.open()` puts the four rows back to Easy, Tutorial on, Sound on and Autosave on, fills the values, and sets `AudioManager.sound_enabled` to true. A player who changes the rows, goes Back and comes again finds the defaults.
- **Difficulty** (`DefineButton2_2775` on(release)) steps Easy, Challenging, Heroic, then Easy again.
- **Tutorial** (`DefineButton2_2769` on(release)) flips `Krin.tutorOn` and shows `MENU[84]` or `MENU[83]`.
- **Sound** (`DefineButton2_2774` on(release)) flips `Krin.sound`. The port sets `AudioManager.sound_enabled` with it, as #379 decided, and START writes it to the new save.
- **Autosave** (`DefineButton2_2772` on(release)) flips `Krin.autoSaver`. START writes it to `PlayerSave.autosave`, the field Proceed reads.
- **START** emits `start_pressed`. `main_menu.gd` makes the new game with the panel's four values and picks the first fight from the Tutorial row.

## PlayerSave.auto_saver

`PlayerSave` had two fields for `Krin.autoSaver`: `auto_saver`, which nothing read, and `autosave`, which the settings, the Options Window and Proceed use. This spec removes `auto_saver`. A save file written before still holds the line, and Godot skips a property the script no longer has, so the save loads. A test checks this.

## Replacements

- `scenes/main_menu.tscn`: the `OptionsPanel` subtree, its Background copy, the difficulty `ButtonGroup` and the transparent StyleBox go. `OptionsPanel` becomes an instance of the new scene, with `Back` as before.
- `scripts/ui/main_menu.gd`: the four row variables and their toggle handlers go. `_on_class_picked` calls `options_panel.open()`, and `_on_start_new_game` reads the panel.
- `scripts/entities/player_save.gd`: `auto_saver` goes.

## Project structure

```
scenes/ui/menu/options_panel.tscn                  optionsMenu: the rows, the help text and START
scripts/ui/menu/options_panel.gd                   OptionsPanel: fills, resets and flips the rows
test/fixtures/screen_rects/settings_screen.tscn    background, settings and Back, for the compare tool
test/integration/test_options_panel.gd             texts, defaults and rows
```

- `dev/urchin_dev/swf/extract/screen_rects.py` gains `SETTINGS_FRAME`, `SETTINGS_ROWS`, `SETTINGS_PIECES` and `SCENES` entries for both scenes. `main_menu.tscn`'s entry keeps `OptionsPanel` in `port_only`, as it does the other later panels.
- `dev/screen_compare/screens.json` gains an entry `settings`.

## Testing strategy

- **Rect test.** `test/unit/test_screen_rects.gd` checks the 11 text fields and the 5 hit buttons to 0.5 px, with each Label's size, color, alignment and the help text's line pitch. A 20 px shift of one value Label fails it.
- **Texts and rows (GUT).** `test_options_panel.gd` compares every caption with its `MENU` entry, read from `strings.json` by the test itself, checks the frame's defaults, the reset in `open()`, each row's flip or cycle, and that the Screen has no Effects or Graphics button.
- **Flow (GUT).** `test_ui_scenes.gd`: START copies the rows into the new game, the rows reset when the player goes Back and comes again, and the Tutorial row picks the first fight.
- **Fonts (GUT).** `test_menu_font.gd` checks that every field uses font 65.
- **Old saves (GUT).** `test_game_data.gd` loads a save that holds `auto_saver`.
- **Compare tool.** The `settings` entry scores `settings_screen.tscn` against frame 93 in `chrome` mode, with the left-out depths stripped. The bar comes from the first passing run, and the 20 px control scores over it.
- **Whole suite.** `just gut` and `just pytest` pass before each commit.

## Boundaries

- Always: take a SWF number from the rect record and a string from `strings.json`.
- Never: add an Effects or Graphics row (ADR 0011). Keep a row's value when the Screen opens again.

## Out of scope

- The name and class panels of `main_menu.tscn`, which stay hand-placed.
- `PlayerSave.graphics` and `PlayerSave.qual`, which ADR 0011 keeps at their defaults.
