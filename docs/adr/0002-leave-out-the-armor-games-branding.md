# Leave out the Armor Games branding and every link to the publisher's site

The original's game over screen, root frame 104 (`gameOverMenu`), and its ending screen, root frame 116 (`endMenu`), each show three pieces of its publisher's branding: the Armor Games logo, a "Developed and published by Armor Games" copyright line and a "Play MORE Games!" link. The port's game over screen, `scenes/battle/game_over_screen.tscn`, added for [#31](https://github.com/julian-perge/urchin/issues/31), and its ending screen, `scenes/battle/ending_screen.tscn`, added for [#18](https://github.com/julian-perge/urchin/issues/18), leave all three out, and a player of the original will notice that they are gone. The port's main menu already leaves all three out, so the three screens match. Leaving them out was the project owner's call when the game over screen came in, and it covers the ending screen too.

AS paths below are relative to `dev/source_files/action_script/`, and character ids are the web build's, from `dev/source_files/swf_xml/sonny-2-2900.xml`.

## What the original shows

- The logo is DefineSprite 294, at depth 41.
- The copyright line is DefineShape 2689, at depth 38. It reads "Developed and published by Armor Games" over "Copyright 2007-2008 Armor Games Inc.". DefineButton2 2688 sits over it at depth 39, and its release opens http://www.armorgames.com (`DefineButton2_2688/BUTTONCONDACTION on(release).as:2`).
- On frame 104, "Play MORE Games!" is DefineEditText 2795, at depth 6, which `frame_104/DoAction.as:8` fills with `MENU[19]` (`frame_1/DoAction.as:227`). A second copy of 2688, at depth 8, covers it and opens the same page.
- On frame 116, "Play MORE Games!" is DefineEditText 2798, at depth 7, which `frame_116/DoAction.as:3` fills with `MENU[19]`, and the copy of 2688 at depth 8 moves over it.

The main menu and every other menu screen from `mainMenu` to `endMenu` place 294, 2689 and 2688 at the same depths. ffdec's export of frame 104, `dev/source_files/exported_assets/frames/104.png`, shows the logo at the top left and the copyright line at the bottom left. ffdec does not run ActionScript, so the two "PLAY" captions at the bottom right of that export are the initial text of 2795 and of the Back caption, 2703, not what the game shows there. ffdec's export of frame 116, `dev/source_files/exported_assets/frames/116.png`, shows the logo and the copyright line in the same places, and its "PLAY" caption under OK! is the initial text of 2798.

The Steam build's frames 104 and 116 have no "Play MORE Games!" caption, and its copyright line, DefineEditText 2647, reads "Copyright 2007-2024 ArmorGames Inc.".

## What the port shows

The game over screen and the ending screen draw the main menu's backdrop, `assets/ui/menu/start_background.png`, which `extract_start_screens` renders with every character above depth 5 removed. Frames 104 and 116 place the same three characters at depths 1, 2 and 5 as the class-select frame that render comes from, with the same matrices and no color transform. Outside the areas the texts, the logo and the copyright line cover, the PNG matches the export of each frame with a 99th percentile channel difference of 0. Shifting the PNG by one pixel of the export's 2x zoom raises that to 17 on both.

Everything else frame 104 shows stays: "You're dead, Sonny...", "< Click here to Re-Load >", the tip and the Back link, each a Label at its edit text's own rect, with Re-Load and Back clickable over their buttons' rects. The tip still sends the player to "the ArmorGames or KrinLabs forums", because that sentence is the game's own text, `GOTIP[0]` (`frame_1/DoAction.as:2239`), not part of the branding.

Everything else frame 116 shows stays too: the `ENDING` text, PvP Arena line included, and OK!, each a Label at its text's own rect, with OK! clickable over button 2797's rect. The text still sends the player to www.ArmorGames.com, because that sentence is the game's own text, `ENDING` (`frame_1/DoAction.as:2240`), not part of the branding.

The Game Manual Screen, `scenes/ui/menu/manual_panel.tscn`, added for [#365](https://github.com/julian-perge/urchin/issues/365), shows the original's root frame 124 (`designMenu`) without the logo, the copyright line and its link, at depths 41, 38 and 39. Its last topic still sends the player to "the Sonny forums on ArmorGames for guides and walkthroughs", because that sentence is the game's own text, `MANUALEX[4]`, not part of the branding and not a link.

## Widened to the title and to every publisher link

This record first covered the branding on the game over and ending screens only. [#121](https://github.com/julian-perge/urchin/issues/121) widened it to the branding and every link to the publisher's site, on every Screen. The title Screen, `scenes/ui/menu/title_panel.tscn`, added for [#215](https://github.com/julian-perge/urchin/issues/215), is the first Screen built under the wider rule.

The original's title, root frame 46 (`mainMenu`), shows five captions. Two of them are links to the publisher's site:

- "Play MORE Games!" is DefineEditText 2697, at depth 10, which `frame_46/DoAction_3.as:4` fills with `MENU[19]`. DefineButton2 2688, at depth 16, covers it and opens http://www.armorgames.com.
- "Play the Original Sonny" is DefineEditText 2695, at depth 12, which `frame_46/DoAction_3.as:5` fills with `MENU[90]`. DefineButton2 2691, at depth 20, covers it and opens http://armorgames.com/play/505/sonny (`DefineButton2_2691/BUTTONCONDACTION on(release).as:2`).

The port's title leaves out both captions and both buttons, with the logo and the copyright line. The three captions that stay, `MENU[18]`, "Game Manual" and "Credits", keep their SWF positions. A player of the original will see a gap of 90 px between "Game Manual" and "Credits", where the two links were.

The Credits Screen, `scenes/ui/menu/credits_panel.tscn`, added for [#366](https://github.com/julian-perge/urchin/issues/366), shows David Orr's name as text and opens nothing, as #121 decided. The original places DefineButton2 2814 over that name, at depth 22 of root frame 134 (`creditMenu`), and its release opens http://davidorr.net/ (`DefineButton2_2814/BUTTONCONDACTION on(release).as:2`). The port places no button there.

The compare tool scores the port's title against ffdec's render of frame 46. `SCENES` in `dev/urchin_dev/swf/extract/screen_rects.py` names depths 38 and 41, the copyright line and the logo, as left out, so the tool takes them out of its reference.

Every claim about the original here comes from the ActionScript, the XML dumps and ffdec's frame exports, not from running the game.
