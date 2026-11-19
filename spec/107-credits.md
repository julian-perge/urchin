# Spec: credits

Source issue: [#366](https://github.com/julian-perge/urchin/issues/366). Module `credits` of [the capability map](107-capability-map.md), under [#107](https://github.com/julian-perge/urchin/issues/107). It depends on [ui-foundation](107-ui-foundation.md) (the rect test, its extractor, the compare tool and `strings.json`) and on [title-slots](107-title-slots.md) (the title, the menu background, the logo, the Back caption and the `MenuCaption` look).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Build the Credits Screen, the original's `creditMenu` (root frame 134), and open it from the title. The title has a Credits caption since [#215](https://github.com/julian-perge/urchin/issues/215), but it opens nothing, because the port has no Credits Screen. [#120](https://github.com/julian-perge/urchin/issues/120) put the Screen in scope: it credits the people who made the game.

Success is that Credits on the title opens a Screen with the logo, the seven role and name pairs and Back, every piece sits where the SWF puts it, checked to 0.5 px, the roles come from `strings.json` and the names from the SWF, and Back returns to the title.

## Assumptions

- No user is in this session. Each open question is answered by the rule for this run: take what matches the original, and reuse an existing scene where matching the original would copy one.
- The way in: the title's Credits hit button, DefineButton2 2690, goes to `creditMenu`. The port's `TitlePanel` already emits `credits_pressed` from its `CreditsSlot/HitButton`.
- The way out: Back, DefineButton2 2702, goes to `mainMenu` (`on(release)`, line 2), as on every menu Screen. The port's `main_menu.gd` `_on_back_pressed` shows the title.
- [ADR 0002](../docs/adr/0002-leave-out-the-armor-games-branding.md) already decides the davidorr.net link: the name shows as text and opens nothing, as [#121](https://github.com/julian-perge/urchin/issues/121) decided. So this spec adds no ADR, and the ADR's last paragraph changes from "not built yet" to what the Screen does.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()` of the web build, read at the label `creditMenu`. The rect record is the source the test reads. AS paths are relative to `dev/source_files/action_script/`.

`frame_134/DoAction.as` fills `credit_1` to `credit_7` from `MENU[92]` to `MENU[98]` and does nothing else.

| Depth | cid | Piece | Box (field bounds) | Look | Port |
| --- | --- | --- | --- | --- | --- |
| 1, 2, 5 | 2701, 307, 2700 | the menu background | the Stage | title-slots | the `Background` of `main_menu.tscn` |
| 6 | 321 | the "SONNY 2" logo, at (403.50, 180.20), as on the title | title-slots | title-slots | `Logo`, a TextureRect of `logo.png` |
| 14 to 19, 21 | 2822 to 2817, 2815 | `credit_1` to `credit_7`, the roles | (79.10, 271.65 + 30 n) 304.10x24.10 | `_sans` bold 18 #a6f76f right | `Rows/RowN/Role`, Label, `MenuCaption`, color override |
| 8 to 13, 20 | 2828 to 2823, 2816 | the names, static text | (399.10, 271.65 + 30 n) 342.10x27.10 | `_sans` bold 18 #ffffff left | `Rows/RowN/Name`, Label, `MenuCaption` |
| 22 | 2814 | the link to http://davidorr.net/, over David Orr's name | | no art | left out, ADR 0002 |
| 24, 25 | 2813, 2702 | Back caption and hit button | as in title-slots | | an instance of `menu_back.tscn` |
| 38, 39, 41 | 2689, 2688, 294 | the Armor Games line, its link and its logo | | | left out, ADR 0002 |

The rows, read from the placements (n is 0 to 6, top down, and each row is 30 px under the one before):

| Row | Role field | Role (`MENU`) | Name field | Name |
| --- | --- | --- | --- | --- |
| 1 | 2822 | `MENU[92]`, Producer | 2828 | Jakrin Juangbhanich |
| 2 | 2821 | `MENU[93]`, Production Assistant | 2827 | Philipp Knothe |
| 3 | 2820 | `MENU[94]`, Sound and Music | 2826 | David Orr |
| 4 | 2819 | `MENU[95]`, Animation | 2825 | William Arbuckle |
| 5 | 2818 | `MENU[96]`, Graphics and Artwork | 2824 | Joan C.G. |
| 6 | 2817 | `MENU[97]`, Male Cast | 2823 | Andy Dennis |
| 7 | 2815 | `MENU[98]`, Female Cast | 2816 | Mandi N. |

- The record turns a field's bounds into the rect Flash lays its text out in (`label_layout.text_rect`). The scene types the record's numbers, not the field bounds above.
- Frame 134 places every text with the caption Glow (#000000, blur 3, strength 10) and DropShadow (#000000, blur 8, distance 2), so `MenuCaption` is their look. `MenuCaption` is white, so each role overrides the color to #a6f76f.
- Back on frame 134 is edit text 2813, not 2703. The two fields are the same: same bounds, font, size, color, alignment and variable `whatToSayX`, and frame 134 places 2813 where the other frames place 2703. So the Screen reuses `menu_back.tscn`, and the record checks its caption at depth 24 and its hit button at depth 25.
- The names are static text with no variable. The rect record already writes the text of one line of static text (`text_record`), and `test/unit/test_screen_rects.gd` compares each Label's text with it. So the names come from the SWF by script through the record, and no other JSON is needed. The `.tscn` types each name, as `ending_screen.tscn` types "OK!".
- The roles are filled while the game runs, so the script fills them from `Strings.menu(92)` to `Strings.menu(98)` and the `.tscn` holds no text for them.
- Button 2814 draws nothing and has no filter. The port places no node for it, as the title places no node for the two publisher links. A click on David Orr's name hits nothing.
- Layout: one `FloatBox` column of seven fixed-height row slots, 30 px apart, as the title's caption column. Each row is a plain Control holding the role and name Labels at their SWF offsets inside it.

## Answers to the open questions

1. **Which name goes with which role?** The row table above. Each role field and its name field share a y on the frame: 2822 and 2828 at 273.65, and so on 30 px apart.
2. **Which name does 2814 sit over?** David Orr's. 2814 is placed at (447.25, 344.35) with a scale of 3.33 by 0.69, which covers the third name row, 2826, and the link opens davidorr.net.
3. **Which Back does frame 134 use?** Caption 2813 at depth 24 and hit button 2702 at depth 25. The issue thought it kept 2702 from an earlier frame. The timeline shows frame 134 places it again, at a new depth.
4. **Where do the names come from?** The rect record, as above. No extractor change and no new JSON.

## Replacements

- `scripts/ui/menu/title_panel.gd`: the header comment that says nothing connects `credits_pressed` changes.
- `scripts/ui/main_menu.gd`: the header list gains the Credits Screen, and `_show_screen` knows the new panel.
- `docs/adr/0002-leave-out-the-armor-games-branding.md`: the paragraph "The Credits Screen is not built yet" says what the Screen does now.
- `test/integration/test_ui_scenes.gd` `test_game_manual_and_credits_leave_the_title_up`: Credits no longer leaves the title up. Game Manual still does, until its own Screen.

## Project structure

```
scenes/ui/menu/credits_panel.tscn                 creditMenu: the logo and the rows (proposed)
scripts/ui/menu/credits_panel.gd                  CreditsPanel, fills the roles (proposed)
test/fixtures/screen_rects/credits_screen.tscn    background, credits panel and Back, for the compare tool (proposed)
```

- `scenes/main_menu.tscn` gains `CreditsPanel`, an instance of the new scene, with `Back`, an instance of `menu_back.tscn`, as the other panels have.
- `dev/urchin_dev/swf/extract/screen_rects.py` gains `CREDITS_FRAME = "creditMenu"`, `CREDITS_PIECES`, and `SCENES` entries for `credits_panel.tscn` and `credits_screen.tscn`, with `left_out=(38, 41)` on the second. `main_menu.tscn`'s entry lists `CreditsPanel` in `port_only`, as it does the other later panels.
- `dev/screen_compare/screens.json` gains an entry `credits`.

## Code style

As in title-slots. The panel emits no signal of its own, because Back is `menu_back.tscn` and `main_menu.gd` connects it. The script reads the roles by their AS index:

```gdscript
# frame_134/DoAction.as fills credit_1 to credit_7 from MENU[92] to MENU[98].
const FIRST_ROLE: int = 92
```

Each `Piece` with a typed depth names its `character`, so a wrong depth fails on the character and not on a rect.

## Testing strategy

- **Rect test.** `test/unit/test_screen_rects.gd` checks the logo, the 14 text fields and Back to 0.5 px, with each Label's size, color, alignment and the names' text.
- **Must-fail control.** Move one name Label 20 px, and change one name's text, in a working copy, and watch the rect test name each. Do not commit them.
- **Texts (GUT).** A test opens the panel and compares each role Label with `MENU[92]` to `MENU[98]`, read from `dev/converted_json/strings.json` by the test itself. It also checks that every Label uses `MenuCaption`.
- **Flow (GUT).** On `main_menu.tscn`: pressing the title's Credits hit button shows the Credits panel and hides the title; pressing its Back shows the title; the Credits panel holds no Button or BaseButton other than Back's hit button, and no Control at the point of David Orr's name takes the click.
- **Compare tool.** An entry `credits` in `dev/screen_compare/screens.json` scores `credits_screen.tscn` against frame 134 in `chrome` mode. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Whole suite.** `just gut` and `just pytest` pass before each commit.

## Boundaries

- Always: take a SWF number from the rect record. Show the roles from `strings.json` and the names as the SWF types them.
- Ask first: a link on David Orr's name. A hover look on Back.
- Never: open davidorr.net. Add the Armor Games logo, line or link.

## Out of scope

- The Game Manual Screen, root frame 124 (`designMenu`), and its wiring, which get their own spec session.
- Music on the Screen. The original keeps the menu music playing, and the port does not stop it.

## Success criteria

1. Credits on the title opens the Screen, and Back returns to the title.
2. `test/unit/test_screen_rects.gd` checks the logo, the 14 text fields and Back to 0.5 px, and the 20 px control fails.
3. A test compares the roles with `strings.json`, and the rect test compares the names with the SWF's texts.
4. A click on David Orr's name opens nothing.
5. The compare tool scores the Screen under its bar, and the 20 px control over it.
6. `just gut` and `just pytest` pass.
