# Spec: game-over

Source issue: [#362](https://github.com/julian-perge/urchin/issues/362). Module `game-over` of [the capability map](107-capability-map.md). It depends on [ui-foundation](107-ui-foundation.md) (the rect test, its extractor, the compare tool and the Theme) and on [title-slots](107-title-slots.md) (the menu background, the Back caption and the `MenuCaption` look).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the Game over Screen, the original's `gameOverMenu` (root frame 104), on the rect record and the shared menu pieces. The Screen already does what the original does since [#31](https://github.com/julian-perge/urchin/issues/31). It was built before the shared menu pieces existed, so:

- its rects are typed by hand and no rect test checks them;
- its three texts are typed into the `.tscn`;
- its captions use their own 4 px outline and not `MenuCaption`;
- Back is its own Label and Button, not `menu_back.tscn`.

Success is that every piece of frame 104 that the port keeps sits where the SWF puts it, checked to 0.5 px, the texts come from `strings.json`, and Re-Load and Back do what they do now.

## Assumptions

- Each open question was answered in the spec session by the rule "take what matches the original" (orchestrator rule for this run). No answer departs from the original, so this spec adds no ADR.
- The behavior stays as #31 built it. A defeat or a draw runs `frame_230/DoAction.as`, which sets `gameoverKrin`, keeps `slotSaveGO = Krin.slotInUse` and goes to `resetHere`. After the reset, `frame_43/DoAction.as:21-24` sees `gameoverKrin` and stops on `gameOverMenu`. The port's `battle_scene.gd` opens `game_over_screen.tscn` under `UI`, and its `_ready` stops every sound and starts the music rotation over.
- Re-Load (`DefineButton2_2791/BUTTONCONDACTION on(release).as`) loads `slotSaveGO` and goes to `Navigation` when that slot holds a save, and to `mainMenu` when not. The port's `reload_last_save()` does the same.
- Back (`DefineButton2_2702`) goes to `mainMenu`. The port opens `main_menu.tscn`, which opens on the title.

## Pieces

All numbers are Stage px from `timeline.frames()` of the web build. Frame 104 places these depths, read with `timeline.frames(index, 0)` at the label `gameOverMenu`:

| Depth | cid | Piece | Box (field bounds) | Look | Built as |
| --- | --- | --- | --- | --- | --- |
| 1, 2, 5 | 2701, 307, 2700 | the menu background | the Stage | | an instance of `menu_background.tscn` |
| 6 | 2795 | `whatToSay3`, "Play MORE Games!" (`MENU[19]`) | | | left out, ADR 0002 |
| 8 | 2688 | its link button to armorgames.com | | | left out, ADR 0002 |
| 10 | 2794 | `whatToSay111`, `MENU[50]` | (193.10, 93.75) 413.85x45.35 | `_sans` bold 30 #ffffff center | Label, `MenuCaption` |
| 11 | 2793 | `whatToSay222`, "< " + `MENU[51]` + " >" | (250.90, 172.40) 298.20x33.05 | `_sans` bold 14 #ffcc00 center | Label, `MenuCaption`, color override |
| 12 | 2792 | `tipTextGO`, `GOTIP[0]` | (114.15, 231.65) 570.80x115.35 | `_sans` bold 14 #ffffff left, wraps | Label, `MenuCaption` |
| 13 | 2791 | Re-Load hit button | its hit square through the matrix | none | flat Button |
| 35, 36 | 2703, 2702 | Back caption and hit button | as in title-slots | | an instance of `menu_back.tscn` |
| 38, 39, 41 | 2689, 2688, 294 | the Armor Games line, its link and its logo | | | left out, ADR 0002 |

- The record turns a field's bounds into the rect Flash lays its text out in (`label_layout.text_rect`). The scene types the record's numbers, not the field bounds above.
- Back is placed on frame 104. `label_xref.json` does not list 2702 and 2703 for the frame, because frame 104 keeps them from an earlier frame and does not place them again. The timeline read above shows depths 35 and 36 hold them on frame 104.
- Every caption of the frame has the black Glow (blur 3, strength 10) and DropShadow (blur 8, distance 2) of the menu captions. `MenuCaption` draws them as on the title.
- The tip keeps the line spacing that makes its line pitch match the record.

## Answers to the open questions

1. **Is Back on frame 104?** Yes. The timeline places 2703 at depth 35 and 2702 at depth 36 on `gameOverMenu`. `test/integration/test_menu_font.gd` names cid 2795 for the Back caption today. That is the cid of "Play MORE Games!", and the test changes to 2703.
2. **Does the `GOTIP[0]` text stay word for word?** Yes. It is the game's own text, and the original shows it as it is. ADR 0002 already says so ("What the port shows"): the tip still names "the ArmorGames or KrinLabs forums", because that sentence is not part of the branding and is not a link. No ADR changes.

## Replacements

- `scenes/battle/game_over_screen.tscn`: the `Background` TextureRect becomes an instance of `menu_background.tscn`. `BackLabel` and `BackButton` become one instance of `menu_back.tscn`, named `Back`. The three Labels lose their outline, color and font overrides except the font size and the Re-Load color, and use `MenuCaption`. Their `text` lines go. The comment block above `DeadLabel` goes.
- `scripts/battle/game_over_screen.gd`: `_ready` fills the three texts with `Strings`, and Back connects to `MenuBack.pressed`.
- `test/integration/test_battle_assets.gd`: `test_game_over_screen_uses_the_frame_104_rects` goes. Its rects were typed by hand, and the rect test checks the same pieces from the record.
- `test/integration/test_menu_font.gd` and `test/integration/test_battle_scene.gd` follow the new path of Back's caption.

## Code style

As in title-slots. The scene types its Stage numbers once, from the record. The script reads its texts by their AS index, as `title_panel.gd` does:

```gdscript
# frame_104/DoAction.as:1-3 fills the three texts.
const DEAD_CAPTION: int = 50
const RELOAD_CAPTION: int = 51
const TIP: int = 0
```

## Testing strategy

- **Rect test.** `SCENES` in `dev/urchin_dev/swf/extract/screen_rects.py` gains `game_over_screen.tscn`, frame `gameOverMenu`, with every piece in the table that the port keeps, and `left_out=(38, 41)`. `just extract-screen-rects` writes the record, and `test/unit/test_screen_rects.gd` checks every piece to 0.5 px.
- **Must-fail control.** Move the Re-Load hit button 20 px in the scene and expect the rect test to name it.
- **Texts.** A GUT test compares the three Labels with `MENU[50]`, `MENU[51]` and `GOTIP[0]` read from `dev/converted_json/strings.json` by the test itself.
- **Behavior.** The tests from #31 in `test/integration/test_battle_scene.gd` and `test/integration/test_ui_scenes.gd` still pass: a loss and a draw open the Screen, the sounds stop, the rotation starts over, and Re-Load opens the hub or the main menu. A test presses Back's hit button and expects the screen to ask for the main menu.
- **Compare tool.** An entry `game_over` in `dev/screen_compare/screens.json` scores the scene against frame 104 in `chrome` mode. The bar comes from the first passing run.
- **Whole suite.** `just gut` passes before each commit.

## Boundaries

- Always: Take a SWF number from the rect record. Keep Re-Load and Back as they behave now.
- Ask first: A change to the tip's wording. A hover look on Re-Load.
- Never: Add the Armor Games logo, line or "Play MORE Games!". Type a coordinate the record does not check.

## Out of scope

- The Ending Screen (root frame 116), which has its own spec session.
- The music and sound reset on open, which #31 built and this spec keeps.

## Success criteria

1. `test/unit/test_screen_rects.gd` checks every piece of frame 104 that the port keeps, to 0.5 px, and the 20 px control fails.
2. A test compares the three texts with `strings.json`.
3. Re-Load and Back keep their behavior, and the tests from #31 still pass.
4. The captions use `MenuCaption` and Back is `menu_back.tscn`.
5. `just gut` passes.
