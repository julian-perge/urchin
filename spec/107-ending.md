# Spec: ending

Source issue: [#363](https://github.com/julian-perge/urchin/issues/363). Module `ending` of [the capability map](107-capability-map.md), under [#107](https://github.com/julian-perge/urchin/issues/107). It depends on [ui-foundation](107-ui-foundation.md) (the rect test and `strings.json`) and on [title-slots](107-title-slots.md) (the menu background and the caption look).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the Ending Screen, the original's root frame 116 (`endMenu`), on the pieces the menu Screens share. The Screen already works and sits at the SWF's rects, but the rects are typed by hand with no rect test, the `ENDING` text is typed into the `.tscn`, and the captions draw an outline of their own instead of the caption look.

Success is that the rect test checks every piece of the Screen against the SWF, the text comes from `strings.json`, both captions use `MenuCaption`, and the way in and out stays as it is.

## Assumptions

- No user is in this session. Each open question is answered by the rule for this run: take what matches the original, and reuse an existing scene where matching the original would copy one.
- The way in stays as it is. The first win of battle 513 sets `afterCut = "CS_CUT5"` and `gotoSceneKrin = "endMenu"` (`frame_219/DoAction.as:51-55`), and `game.gd` `_on_victory_proceed` opens the Screen when CS_CUT5 ends. The issue names `battle_scene.gd`, but the code is in `game.gd`.
- The way out stays as it is. OK! (`DefineButton2_2797/BUTTONCONDACTION on(release).as`) goes to `Navigation`, and the port's `ok_pressed` reloads the Hub. The frame has no Back.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()` of the web build. The rect record is the source the test reads. AS paths are relative to `dev/source_files/action_script/`.

`frame_116/DoAction.as` sets three variables and stops:

- `enderText` = `ENDING` (`frame_1/DoAction.as:2240`).
- `whatToSay1` = `MENU[18]`. No field on frame 116 reads `whatToSay1`, so it shows nothing. This is read from the frame's placements, which hold no edit text with that variable name.
- `whatToSay3` = `MENU[19]`, "Play MORE Games!", in 2798.

Frame 116 places these characters:

| Depth | cid | Piece | Box | Look | Port |
| --- | --- | --- | --- | --- | --- |
| 1, 2, 5 | 2701, 307, 2700 | the menu background | the Stage | title-slots | `Background`, an instance of `menu_background.tscn` |
| 6 | 2799 | "OK!", static text | (221.00, 410.10) 342.10x51.30 | `_sans` bold 36 #ffcc00 center | `OkLabel`, `MenuCaption` |
| 7 | 2798 | `whatToSay3`, "Play MORE Games!" | | | left out, ADR 0002 |
| 8 | 2688 | its link to the publisher | | | left out, ADR 0002 |
| 10 | 2797 | the OK! hit button | (340.43, 412.40) 104.04x40.00 | none | `OkButton`, a flat Button |
| 12 | 2796 | `enderText` | (195.30, 109.45) 418.05x275.20 | `_sans` bold 14 #ffffff left, multiline, word wrap, 8 px leading | `EndingLabel`, `MenuCaption` |
| 38, 39, 41 | 2689, 2688, 294 | the copyright line, its link and the logo | | | left out, ADR 0002 |

- `Background` replaces the scene's own TextureRect of `start_background.png`. `menu_background.tscn` is the same PNG at the same rect, so the Screen reuses it, as the choice and slot list Screens do.
- `OkLabel` keeps "OK!" in the `.tscn`, because 2799 is static text and the record holds its text. `MenuCaption` is white, so `OkLabel` overrides the colour to #ffcc00.
- `EndingLabel` reads `Strings.text("ENDING")` when the Screen is ready. The `.tscn` holds no text for it.
- The rect, size, colour, alignment and line pitch of each piece come from the record. The scene's numbers stay typed in the `.tscn`, which AGENTS.md allows once the rect test checks them.

### The `ENDING` wording

The text stays word for word, the PvP Arena sentence and the ArmorGames.com sentence included. [ADR 0002](../docs/adr/0002-leave-out-the-armor-games-branding.md) and [ADR 0006](../docs/adr/0006-leave-out-the-pvp-arena.md) already record this: each says the ending text keeps the sentence, because the sentence is the game's own text and not the branding or the arena caption. So this spec adds no ADR, and the test compares the Label with `strings.json`.

## Replacements

- `ending_screen.tscn`: the `outline_size = 4` and outline colour overrides on both Labels, the white colour override on `EndingLabel`, and the typed `ENDING` text.
- `test/integration/test_battle_assets.gd` `test_ending_screen_uses_the_frame_116_rects`, which types the same rects by hand. The rect test replaces it.
- The scene comment that says the outline stands for the glow filter.

## Project structure

- `scenes/battle/ending_screen.tscn` and `scripts/battle/ending_screen.gd` stay where they are.
- `dev/urchin_dev/swf/extract/screen_rects.py`: a new `SCENES` entry for `res://scenes/battle/ending_screen.tscn` on frame `endMenu` (proposed constant `ENDING_FRAME`), with `left_out=(38, 41)` as the other menu Screens have.
- `test/fixtures/screen_rects.json`: regenerated by `just extract-screen-rects`.

## Code style

As [AGENTS.md](../AGENTS.md) and `CODING_STANDARDS.md` say. Each `Piece` with a typed depth names its `character`, so a wrong depth fails on the character and not on a rect.

## Testing strategy

- **Rect test.** The new `SCENES` entry puts `Background`, `EndingLabel` (2796), `OkLabel` (2799) and `OkButton` (2797) in the record, and `test/unit/test_screen_rects.gd` checks each to 0.5 px, with the Labels' size, colour, alignment and line pitch.
- **Must-fail control.** Move `OkButton` 20 px in a working copy and watch the rect test name it. Do not commit the move.
- **Text (GUT).** A test opens the Screen and compares `EndingLabel.text` with `Strings.text("ENDING")` read from `strings.json`, and checks that both Labels use `MenuCaption`.
- **Flow (GUT).** `test_cs_cut5_ends_on_the_silent_ending_screen_and_ok_goes_to_the_hub` in `test/integration/test_victory_proceed.gd` still passes. The issue names it `test_the_first_513_win_ends_on_the_ending_screen_after_cs_cut5`, a name no test has.
- **Whole suite.** `just gut` and `just pytest` pass before each commit.

## Boundaries

- Always: take a SWF number from the rect record. Keep the way in and the way out.
- Ask first: a change to the `ENDING` wording. A hover look on OK!.
- Never: add the Armor Games logo, copyright line or "Play MORE Games!". Add a field for `whatToSay1`.

## Out of scope

- The Game over Screen, frame 104, which is in the same state. It gets its own issue.
- A compare tool entry for frame 116. The `left_out` depths make the scene ready for one.
- Music on the Screen. The original starts none, and the port already plays none.

## Success criteria

1. The rect test checks 2796, 2799 and 2797, to 0.5 px, and passes.
2. `EndingLabel` shows `ENDING` from `strings.json`, and a test compares the two.
3. Both Labels use `MenuCaption`, with no outline overrides of their own.
4. `test_cs_cut5_ends_on_the_silent_ending_screen_and_ok_goes_to_the_hub` still passes.
5. `just gut` passes.

## Open questions

All answered in this session by the rules for the run:

1. **The `ENDING` wording.** Word for word, as ADR 0002 and ADR 0006 already record. No new ADR.
2. **`whatToSay1`.** No field reads it on frame 116, so the port shows nothing for it.
3. **The background.** The Screen instances `menu_background.tscn` instead of keeping its own TextureRect of the same PNG.
