# Spec: options-window

Source issue: [#379](https://github.com/julian-perge/urchin/issues/379). Parent area: [#107](https://github.com/julian-perge/urchin/issues/107). It depends on [window-shell](107-window-shell.md) (`WindowShell` and `ShellPanel`) and [hub](107-hub.md) (the hotbar and the Hub that hosts the Window). Through them it uses the rect test, the compare tool and `strings.json` from [ui-foundation](107-ui-foundation.md).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the in-game Options Window as the original builds it: the `options` label (frame 39) of `KRINMENU`, which the hotbar's Options button opens over the Hub. It shows the Sound, Autosave and difficulty rows and a help text. [ADR 0011](../docs/adr/0011-leave-out-the-effects-and-graphics-options.md) leaves out the Effects and Graphics rows.

Success is that every piece sits where the SWF places it, every row reads its text from `strings.json`, and each row changes the same setting as the original's row.

## Assumptions

- The Window is a `menu_screen` like the other hotbar Windows. A second press of Options closes it, as a second press closes Inventory, Abilities and Achievements in the port. In the original a second press goes to the same label again, so the Window stays open.
- The original's guard against an item on the cursor (`MENU[66]`) does not apply, because the port has no item on the cursor. The hotbar's `set_inert` already stands in for `PauseForScreen`.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. `test/fixtures/screen_rects.json` is the source the rect test reads. The shell is window-shell's and is placed, not redefined.

| Depth, cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 2, 1431, 1434 | backdrop and close X | as in window-shell | | `WindowShell` |
| 5, 2990 | the Panel | (75.27, 81.97) 650.50x300.82 | `tall`, border 2 | `ShellPanel` |
| 15, 3130 `TitLOL1` | `MENU[33]`, "Please configure your settings:" | (197.55, 101.10) 405.95x20.10 | `_sans` bold 16 #ffffff center | Label |
| 7, 3135 `tit_1` | `MENU[27]`, "Sound:" | (232.40, 137.85) 160.10x26.85 | `_sans` bold 14 #d56666 right | Label |
| 9, 3133 `tit_3` | `MENU[29]` "On" or `MENU[30]` "Off" | (403.50, 137.85) 115.00x26.85 | `_sans` bold 14 #ffffff left | Label |
| 11, 3131 | Sound hit button | (305.94, 134.90) 160.51x21.81 | none | TextureButton with no texture |
| 16, 3129 `tit_8` | `MENU[35]`, "Autosave:" | (232.40, 194.85) 160.10x26.85 | as Sound | Label |
| 17, 3128 `tit_7` | `MENU[29]` or `MENU[30]` | (403.50, 194.85) 117.00x26.85 | as the Sound value | Label |
| 18, 2772 | Autosave hit button | (304.39, 192.65) 160.51x21.81 | none | TextureButton with no texture |
| 25, 3123 `t_dif` | `MENU[78]`, "Difficulty:" | (232.40, 252.85) 160.10x26.85 | `_sans` bold 14 #8d8061 right | Label |
| 26, 3122 `t_dif2` | `MENU[79 + difficulty]` | (403.50, 252.85) 117.00x26.85 | `_sans` bold 14 #aca086 left | Label |
| 20, 3127 `TitLOL2` | `MENU[34]`, the help text | (112.50, 291.80) 582.30x109.55 | `_sans` bold 12 #ffffff left, wraps, line pitch 14 | Label |

- The difficulty row has no button. `MENU[34]` says the difficulty cannot be changed in a game.
- Every text field carries a Glow and a DropShadow on its own placement. A Label can draw neither, so the record leaves both out and the port draws neither, as for the right column's euro sign and amount (window-shell).
- Left out by ADR 0011: Effects at depths 8 (`tit_2`), 10 (`tit_4`) and 13 (button 2773), and Graphics at depths 21 (`tit_9`), 22 (`tit_11`) and 23 (button 3124). The rows below them keep their SWF places, so the Window shows two empty bands where those rows were. The help text `MENU[34]` still names Graphics and Effects, because the port shows the original's string.
- The scene's SCENES entry names these six depths in `left_out`, so the compare tool strips them from its reference.

## Behavior

- **Open.** The hotbar's Options button calls `toggle_menu_screen("options_window")` (`DefineButton2_3180` on(release)). The Hub hides its art while the Window shows, as for every `menu_screen`.
- **Fill.** Each time the Window shows, it fills every text as the frame's script does (`DefineSprite_3142/frame_39/DoAction.as`): the labels from `MENU`, the Sound and Autosave values from the save, and the difficulty value from `PlayerSave.difficulty`.
- **Sound** (`DefineButton2_3131` on(release)) flips `Krin.sound`, which the port keeps in `PlayerSave.sound` and `AudioManager.sound_enabled`. Off stops every sound (`stopAllSounds`). On resets the music rotation (`soundModeKrin = 0`, `soundPlayCounter = 0`) and starts the menu music (`addSound("Music", 1)`).
- **Autosave** (`DefineButton2_2772` on(release)) flips `Krin.autoSaver`, which the port keeps in `PlayerSave.autosave`, the field Proceed reads.
- **Close.** The close X hides the Window.

### One sound setting

The original keeps `Krin.sound` in each save (`saveArray1`, `frame_42/DoAction_20.as:296`) and `addSound` plays nothing while it is false (`frame_42/DoAction.as:3`). The port had two separate switches: the new-game screen muted the audio bus, and `AudioManager.sound_enabled` was never set. This spec makes them one setting:

- The new-game screen's Sound row sets `AudioManager.sound_enabled`, as `DefineButton2_2774` sets `Krin.sound`, and START writes it to the new save.
- Loading a save sets `AudioManager.sound_enabled` from `PlayerSave.sound`.
- The Options Window's Sound row sets both.

## Project structure

```
scenes/ui/menu/options_window.tscn     the Window (proposed)
scripts/ui/menu/options_window.gd      fill, Sound and Autosave (proposed)
```

## Testing strategy

- **Rect test.** `options_window.tscn` is in SCENES with every piece in the table. Every piece passes under 0.5 px, and the Labels' sizes, colors and alignments match. A 20 px shift of one Label fails it.
- **Strings (GUT).** Every Label's text equals its `strings.json` entry, for both values of each switch and for each difficulty.
- **Rows (GUT).** Sound flips `PlayerSave.sound` and `AudioManager.sound_enabled`, stops the music when off and starts the menu music when on. Autosave flips `PlayerSave.autosave`. The Window has no Effects, Graphics or difficulty button.
- **Hotbar (GUT).** Options opens the Window, a second press closes it, and the close X hides it.
- **Sound setting (GUT).** Loading a save with sound off turns `AudioManager.sound_enabled` off. The new-game screen's Sound row reaches the new save.
- **Compare tool.** An `options` entry in `chrome` mode scores the shell and the Panel against the frame with the left-out depths stripped. The bar comes from the first passing run, and the 20 px control scores over it.
- **Whole suite.** `just gut` passes before each commit.

## Boundaries

- Always: take a SWF number from the rect record and a string from `strings.json`.
- Never: add an Effects or Graphics row (ADR 0011), or a way to change the difficulty in a game.

## Out of scope

- The new-game settings screen's own layout (root frame 93). It is hand-placed today and is not rebuilt here.
- The Re-Spec button ([#380](https://github.com/julian-perge/urchin/issues/380)).
