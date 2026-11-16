# Leave out PvP Arena

The original's choice screen, root frame 56 (`subMenu`), shows three captions: New Game, Load Game and PvP Arena. The port's choice, `scenes/ui/menu/mode_panel.tscn`, added for [#216](https://github.com/julian-perge/urchin/issues/216), shows the first two only, and a player of the original will notice that the third is gone. Leaving the arena out was the project owner's call in the triage of [#91](https://github.com/julian-perge/urchin/issues/91), and [spec/107-title-slots.md](../../spec/107-title-slots.md) keeps it.

AS paths below are relative to `dev/source_files/action_script/`, and character ids are the web build's, from `dev/source_files/swf_xml/sonny-2-2900.xml`.

## What the original shows

- "PvP Arena" is DefineEditText 2705, at depth 14 of frame 56, at y 410.10. `frame_56/DoAction.as:3` fills it with `MENU[85]` (`frame_1/DoAction.as:293`).
- DefineButton2 2704, at depth 15, covers it. Its release sets `arenaMode` to true and `currentArenaPlayer` to 1, sets `Krin.dataMode` to "load", builds the empty `arenaPlayer1` and `arenaPlayer2` objects, and goes to `dataMenu`, the slot list (`DefineButton2_2704/BUTTONCONDACTION on(release).as`).
- On the slot list, root frame 74, the pick text, DefineEditText 2718, reads `MENU[72]`, "[ Player 1 ] Select your character:", while `arenaMode` is set (`frame_74/DoAction.as:11-17`). A click on a used slot loads it as that player, changes the pick text to `MENU[73]` for player 2, and after the second pick goes to `ArenaNav` (`DefineButton2_2722/BUTTONCONDACTION on(release).as:15-27`). Outside the arena the pick text is empty (`frame_74/DoAction.as:20-23`).
- `frame_46/DoAction.as:2` sets `arenaMode` back to false each time the title opens.

## What the port shows

- The choice has no PvP Arena caption and no hit button for it. `arenaMode`, `currentArenaPlayer`, the two arena players and `ArenaNav` are not ported.
- The slot list has no pick text, because the port never shows it filled.
- New Game and Load Game keep their SWF positions, 60 px apart, as the port's title keeps its captions where the publisher links were ([ADR 0002](0002-leave-out-the-armor-games-branding.md)). The original's third caption sits one more 60 px step down. A player of the original will see that slot empty under Load Game. The two captions are not moved down to centre them in the space.
- The ending text still names the PvP Arena, because that sentence is the game's own text, `ENDING` (`frame_1/DoAction.as:2240`), as ADR 0002 records.

## Consequences

- The rect test checks the choice's pieces against frame 56 and has no entry for depths 14 and 15. The compare tool's reference for frame 56 needs no left-out depth for them, because its `chrome` mode strips every edit text and a hit button draws nothing.
- Adding the arena is a new decision that supersedes this ADR. It needs the arena's battle rules, `ArenaNav` and the pick text, not only the caption.

Every claim about the original here comes from the ActionScript and the XML dumps, not from running the game.
