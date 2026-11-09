# UI pieces inventory: what the SWF draws on each screen, and what the port has

Date: 2026-11-09. Answers julian-perge/urchin#109 for the map julian-perge/urchin#107,
"UI overhaul: faithful screens on native Godot containers". For every Screen,
every Window, the battle HUD and the shared tooltip, it lists the SWF clips that
draw the UI, where their timelines place them, whether the port has extracted
them and where they live, and what is missing.

The map's terms are used as it defines them. A **Screen** is a full-window state
the player navigates to, a **Window** is a panel opened over the hub, and the
**HUD** is the battle screen's status elements over the hall.

Nothing in the repo was changed except this file. The scratch scripts are in
`~/tmp/2026-11-09-ui-pieces-inventory/`, and the appendix says what each does.

## How to read this

Every claim carries a tag:

- **[swf]**: read from the web build, `sonny-2-2900.swf`, through
  `dev/urchin_dev/swf/swf_index.py` and `timeline.frames()`. The scratch walkers
  compose each placement matrix down to the stage. They also parse the fields
  `swf_index.py` leaves alone: DefineEditText and DefineText records,
  DefineButton2 state records, the font tags, a shape's first fill and line
  styles, and Glow, DropShadow and Bevel parameters.
- **[as]**: read in the ffdec script export. Paths are relative to
  `dev/source_files/action_script/`, and `:N` is a line.
- **[port]**: read in a repo file.
- **[size]**: a PNG that no script regenerates, matched to a SWF shape because
  its pixel size is the shape's bounds at a whole zoom and its average colour
  agrees with the shape's fill. No pixel comparison was run.
- **[guess]**: reasoning that nothing here checked.

Conventions:

- Positions are design px (twips / 20) on the SWF's 800x575 stage.
  `(x, y) w x h` is the box a piece covers on the stage after every parent
  matrix is applied. `at (x, y)` is a placement origin.
- A shape placed at the identity sits where its own bounds put it. Many menu
  shapes are placed at (0, 0) and still land mid-screen, and their box is
  their bounds.
- The Look column gives a shape's first fill style and first line style. A
  shape that switches style arrays partway through its edges has more colours
  than listed. The menu splatter 2700 is one: it reads as black at alpha 90 here
  and renders blue and purple in `dev/source_files/exported_assets/frames/46.png`.
- Text fields: `var` is the field's variableName, the AS variable that fills it.
  `init` is the initialText stored in the SWF, the author's placeholder whenever
  the field has a `var`. "device" means the field has no UseOutlines flag, so
  Flash draws it with a system font instead of glyphs stored in the SWF.
- A "hit button" is a DefineButton2 whose only state record is its hit area, so
  it draws nothing.
- The Port column says **script** (an extractor regenerates it, named), **hand**
  (a PNG no script regenerates), **rebuilt** (Godot nodes draw it with no SWF
  art) or **none**.

## Summary

The original builds its UI out of very few kinds of piece: flat filled shapes
for panels, invisible hit buttons, and device-font text fields with Glow and
DropShadow filters. Icons, portraits, backgrounds and a handful of chrome clips
are the only real art. Every position below comes from a timeline matrix, so
later specs can place each piece without guessing.

Findings, most consequential first:

1. **Two shells draw almost everything.** [swf]
   - The menu Screens, root frames 46 to 134, all place one background (2701,
     307 and 2700 at depths 1, 2 and 5). Each caption is a `_sans` bold edit text
     with a hard black Glow (blur 3, strength 10) and a DropShadow (blur 8,
     distance 2), over a hit button made of shape 291 under a scaled matrix. No
     menu button has art of its own.
   - The Windows and the Victory screen are labels of one sprite, `KRINMENU`
     (3142), which the hub frame places at (400.50, 222.40). Its labels are
     `inventory` 1, `normal` 2, `win` 9, `shop` 16, `skills` 25, `data` 32,
     `options` 39, `ach` 45 and `hide` 52.
2. **The Window chrome is three flat panels, rescaled per label.** [swf] Panel
   2989 is solid #373737, 2991 is #404040 and 2987 is #1a1a1a, each with a 1 px
   black line, and each sprite that places one carries a black DropShadow (blur
   5, distance 5). They sit on the backdrop 2993, a radial gradient from #b03e3e
   to #211212. The Store, Victory and Abilities labels differ from Inventory
   mostly in which of the three panels they place and at what scale.
3. **Victory is not a Screen in the original.** [as] `winCombat` (root frame 218)
   plays into frame 219, which jumps to `Navigation`, and there `KRINMENU`'s load
   handler goes to `win` when `winCondition == 1`
   (`frame_181/PlaceObject3_3142_175/CLIPACTIONRECORD onClipEvent(load).as:3-7`).
   Game over is the menu Screen `gameOverMenu` (104), reached through
   `frame_230/DoAction.as:1-5` and `frame_43/DoAction.as:21-24`. The ending is
   `endMenu` (116), queued after CS_CUT5 by `frame_219/DoAction.as:51-55`.
4. **217 of the SWF's 227 text characters use a device font.** [swf] Font 65,
   `_sans` bold, alone covers 190. Five fonts are embedded, and three of them
   only draw Armor Games branding or the site lock screen. `assets/fonts/` holds
   exactly those five, and only Rockwell (2738, the class names) and copy 10_65
   (3307, the member bars and the speech box's skip hint) draw UI the port keeps.
5. **Every piece of Window chrome in the port is a hand export.** [port] [size]
   Every `assets/ui/menu/*.png` except the class cards, the start background and
   the portraits matches one of shapes 2993, 2989, 2991, 2987, 2982, 2857, 2854,
   2859, 3016, 2864, 2865 and 2868 at 2x, and no script writes them. The hotbar
   icons in `resources/toolbar/` are shapes 3169 to 3154 at 5x, and the world map
   PNGs are 4172 and 4156 to 4158. No script writes those either.
6. **Four battle chrome PNGs are extracted and unused.** [port]
   `extract_battle_screen` writes `bottom_bar.png`, `top_panel.png`,
   `alert_icon.png` and `stage_rect.png`, and only
   `test/integration/test_battle_assets.gd` and `battle_layout.json` name them.
   `scenes/battle_scene.tscn:4-6` still loads the July exports
   `hotbar/background.png`, `battle/hotbar_background.png` and
   `battle/battle_pbar_full.png`.
7. **The battle HUD is the least ported area.** [swf] [port] The six unit bars
   (3414) of the top status bar, the buff backing (103 and its frame 101), the
   speech box (3364, 3362), the hover selector's glow (3392), the timer ring's
   two states (3387) and the digit clips of the floating numbers (44, 53) have no
   port art.
8. **The port's turn label has no original.** [as] No string in the AS announces
   whose turn it is. The original says it through the timer ring's glow, blue
   (#0066ff) on the player's side's turn and orange (#ffcc00) otherwise, and by
   showing the member bars only on the player's side's turn
   (`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:704-754`).

| Area | Original | Port today | Section |
|---|---|---|---|
| Title and slots | root frames 46, 56, 74 | `scenes/main_menu.tscn` starts at frame 56. No title screen and no logo | 2.1 |
| New game flow | root frames 64, 84, 93, 151, 263, 293 | name, class and options rebuilt. Class cards and background by script. No intro frames | 2.2 |
| Hub and hotbar panel | root frame 181 | hub art and orbs by script. Hotbar chrome and icons by hand. No info popup | 2.3 |
| World map | root frame 449, `krinMapper` (4173) | hand PNGs of 4172 and 4156 to 4158 | 2.4 |
| Victory | `KRINMENU` label `win` on the hub | rebuilt on the hand Window chrome | 2.5 |
| Game over | root frame 104 | rebuilt at the source rects on the script background | 2.6 |
| Ending | root frame 116 | rebuilt at the source rects on the script background | 2.7 |
| Inventory, Store, Abilities | `KRINMENU` labels `inventory`, `shop`, `skills` | rebuilt on hand chrome. Icons, portraits and shop scenes by script | 3 |
| Battle HUD | root frame 217 | member bars by script. Top status bar, buff backing, speech box, selectors and timer missing | 4 |
| Shared tooltip | `KrinToolTipper` (2717) | rebuilt from its frame scripts. No field borders, no rarity tint | 5 |

## 1. Shared pieces

### 1.1 Fonts

Counted over all 227 DefineEditText and DefineText characters [swf]. A font with
0 glyphs is a device font: the SWF only names it, and Flash looks it up on the
player's machine.

| Font | Name | Glyphs | Text that uses it | Port |
|---|---|---|---|---|
| 65 | `_sans` bold | 0 | 190 edit texts: every caption and Window field | none |
| 295 | `_sans` | 0 | 23 edit texts: unit bar numbers and names, speech text, cutscene subtitles, Store and Victory descriptions, hub info text | none |
| 2838 | `_sans` bold italic | 0 | 2839 `navTitle`, the hub info title | none |
| 2666 | Hypatia Sans Pro Black | 0 | 2667 `stance`, on root frame 43, a load frame | none |
| 2830 | standard 07_55 | 0 | 2831 `ach_Say` in the achievement banner 2835 | none |
| 2832 | Hypatia Sans Pro bold | 0 | 2833 `ach_Say2` in 2835 | none |
| 2738 | Rockwell bold | 64 | 2739, 2747 and 2756, the class names, and static text 3785 "www.ArmorGames.com / presents" in 3786 | `assets/fonts/2738_Rockwell.ttf`, used by `scenes/main_menu.tscn:11` |
| 3307 | copy 10_65 | 114 | 3308 `nameText` (6 px) and 3310 `say` (9 px) in the member bar, 3357 `say` (9 px), the speech box's skip hint | `assets/fonts/3307_copy 10_65.ttf`, used by `scenes/battle/stance_row.tscn:10` |
| 3173 | standard 07_52 | 10 | static text 3174 "www.armorgames.com" in 3176 | `assets/fonts/3173_standard 07_52.ttf`, unused |
| 287 | Times_12pt_st | 9 | static text 288 "Armor Games" in 290, the site lock | `assets/fonts/287_Times_12pt_st.ttf`, unused |
| 335 | Tahoma bold | 4 | static text 336 "Sorry", root frame 7, the site lock | `assets/fonts/335_Tahoma.ttf`, unused |

The five font files arrived in the repo's first commit, `b9caadf`, and no script
writes them [port]. The project theme sets no base font, only an emboldened
`FontVariation` as the default and a plain one for `RegularLabel`
(`scenes/ui/project_theme.tres:3-13`), so port text draws in Godot's fallback
font where the original used `_sans`. `scripts/ui/tooltip_theme.gd:39-43`
records that the port's font sets the same words about 9% wider than Flash's
`_sans`, and that Arial at 12 px reproduces the original's line breaks.

### 1.2 The menu background and caption style

Every root frame from `mainMenu` (46) to `creditMenu` (134), `gameOverMenu` and
`endMenu` included, places these [swf]:

| Depth | cid | Piece | Box | Look | Port |
|---|---|---|---|---|---|
| 1 | 2701 | backdrop | (-6.55, -6.15) 809.40x584.30 | radial #374962 to #181c23 | script: `assets/ui/menu/start_background.png` (`extract_start_screens`, 2x) |
| 2 | 307, shape 306 | swirl, at (392.95, 286.80) | (-34.50, -27.05) 854.90x627.70 | black, alpha 64, placed with a black Glow (blur 12) | script, same PNG |
| 5 | 2700 | paint splatter | (-100.20, -70.70) 411.15x605.40 | see the Look caveat above | script, same PNG |
| 38 | 2689 | "Developed and published by Armor Games" line | (7.55, 534.35) 244.00x27.30 | #99ffff | none, ADR 0002 |
| 39 | 2688 | hit button over 2689, opens armorgames.com | (5.42, 532.59) 247.55x29.91 | | none, ADR 0002 |
| 41 | 294 (shape 293, hit button 292) | Armor Games logo, at (120.25, 38.15) | (16.85, 14.15) 172.45x46.10 | | none, ADR 0002 |

`start_screens.py:80-84` already records that depths 1, 2 and 5 are the
background on every menu screen. `docs/adr/0002-leave-out-the-armor-games-branding.md`
covers 2689, 2688 and 294.

A caption and its click area are separate pieces [swf]. The caption is a
`_sans` bold edit text placed with Glow #000000 (blur 3, strength 10) and
DropShadow #000000 (blur 8, distance 2), which draws white text with a hard
black rim. The click area is a hit button of shape 291, a 30x30 square centred
on its origin, under a matrix that stretches it to the caption's size. So the
clickable rect is its own number, not the text's rect. The Back caption below
is shared by `subMenu`, `nameMenu`, `dataMenu`, `classMenu`, `optionsMenu` and
`gameOverMenu`. `designMenu` and `creditMenu` place their own copies, 2805 and
2813, at the same spot, and `endMenu` has no Back.

| cid | Piece | Box | Look | Port |
|---|---|---|---|---|
| 2703 | `whatToSayX`, the Back caption, "Back" from `MENU[26]` (`frame_46/DoAction.as:1`) | (488.15, 532.15) 304.10x30.85 | `_sans` bold 24 #ffffff right | rebuilt, a Label per screen |
| 2702 | its hit button, to `mainMenu` | (604.44, 534.45) 188.12x26.80 | | rebuilt, a Button per screen |

### 1.3 KRINMENU, the Window shell

`KRINMENU` is DefineSprite 3142, 57 frames, placed on root frame 181 at depth
175, at (400.50, 222.40), with a Bevel (#ca6e6e and #100a0a), a 2 px black Glow
(strength 10) and a DropShadow (blur 5, distance 5) [swf]. Its load handler goes
to `win` or `hide` (section 2.5). The hotbar buttons send it to `inventory`,
`skills`, `options` and `ach`, the shop orbs to `shop`, and an off-stage debug
button to `data` [as] (`DefineButton2_3185`, `_3184`, `_3180`, `_3153`,
`_3187`, `_3182`, each `on(release).as`). Opening a Window also hides the hub
art, `KrinScreen._visible = false`, and leaves the bottom bar showing.

Pieces every label places [swf]:

| Depth | cid | Piece | Box | Look | Port |
|---|---|---|---|---|---|
| 1 | 2995 | a 1 px vertical line | (16.05, 15.00) 2.45x415.10 | line #000000 | none |
| 2 | 2994, shape 2993 | backdrop, at (398.35, 222.55) | (14.15, 15.00) 768.55x425.10 | radial #b03e3e to #211212, line #000000 | hand: `assets/ui/menu/menu_backdrop.png` 1538x851 [size, 2x] |
| 1431 | 2855, shape 2854 | close X | (734.55, 29.75) 36.70x36.40 | #000000, DropShadow (blur 7, distance 3) | hand: `assets/ui/menu/close_x.png` 74x73 [size, 2x] |
| 1434 | 2853 | its hit button | (738.60, 32.70) 30.00x30.00 | | rebuilt, `TextureButton` |

The `win` label is the one that drops the close X.

The three panels, placed through sprites 2990, 2992 and 2988 [swf]:

| Panel | Shape | Unscaled size | Look | Port |
|---|---|---|---|---|
| tall | 2989 (sprite 2990) | 249.05x267.15 | solid #373737, line #000000 | hand: `assets/ui/menu/panel_large.png` 499x535 [size, 2x] |
| bar | 2991 (sprite 2992) | 249.05x50.85 | solid #404040, line #000000 | hand: `assets/ui/menu/panel_bar.png` 499x102 [size, 2x] |
| centre | 2987 (sprite 2988) | 183.05x326.50 | solid #1a1a1a, line #000000 | hand: `assets/ui/menu/panel_center.png` 367x653 [size, 2x] |

Each placement of 2990, 2992 or 2988 carries DropShadow #000000 (blur 5,
distance 5, strength 1) [swf].

### 1.4 Slots, money and the delete and sell slots

| cid | Piece | Unscaled box around its origin | Look | Port |
|---|---|---|---|---|
| 2986 | inventory slot: 2983 (shape 2982), `inner` = item icons 2064, hit button 2985 | 31.00x31.00 | 2982: linear #090909 to #262626, line #000000. 2983 placed with DropShadow (blur 5, distance 5) | hand: `assets/ui/menu/slot.png` 62x62 [size, 2x]. Icons: script, `assets/ui/items/` |
| 2984 | equip slot, same parts, hit button 2981 | 31.00x31.00 | as 2986 | as 2986 |
| 3013 | drop or ware slot, same parts, hit button 3012 | 31.00x31.00 | as 2986 | as 2986 |
| 2857 | the over and down state of 2985, 2981, 2858 and 3015 | 32.00x32.00 | no fill, 2 px line #ffffff | hand: `assets/ui/menu/slot_highlight.png` 64x64 [size, 2x] |
| 2860, shape 2859 | delete slot, with hit button 2858 | 31.00x31.00 | linear #aa1111 to #350606, line #000000 | hand: `assets/ui/menu/button_delete.png` 62x62 [size, 2x] |
| 3017, shape 3016 | sell slot, with hit button 3015 | 31.00x31.00 | linear #ffcc00 to #a33507, line #000000 | hand: `assets/ui/menu/button_sell.png` 62x62 [size, 2x]. `assets/ui/store/sell.png`, 621x621, is the same shape at 20x [size] and nothing loads it |
| 2861 | the euro sign | (505.25, 364.90) 30.40x43.40 | `_sans` bold 31 #fad95a right | rebuilt |
| 2862 | `dumbEuro`, the money amount | (537.10, 371.55) 116.40x28.55 | `_sans` bold 22 #fad95a left | rebuilt |

The delete slot's tooltip is "Delete Item" over `MENU[2]`, and the sell slot's
is "Sell Item" over "Sell this item for" plus a price, from `MENU[1]` to
`MENU[5]` [as] (`DefineButton2_2858/BUTTONCONDACTION on(rollOver).as:5-6`,
`DefineButton2_3015/BUTTONCONDACTION on(rollOver).as:5-12`,
`frame_41/DoAction.as:209-213`).

## 2. Screens

### 2.1 Title and slots

The title is root frame `mainMenu` (46). PLAY goes to `subMenu` (56), which offers
New Game, Load Game and PvP Arena. New Game passes through the name screen
(2.2) to the slot list `dataMenu` (74), and Load Game goes straight to the slot
list [as] (`DefineButton2_2692`, `_2707`, `_2706` and `_2710`, each
`on(release).as`).

**`mainMenu` (46)**, on top of section 1.2's background [swf]:

| cid | Piece | Box | Look | Target [as] |
|---|---|---|---|---|
| 321, shape 320 | the "SONNY 2" logo, at (403.50, 180.20) | (123.20, 119.80) 549.55x97.70 | linear #68d9f4 to #ffffff, placed with Glow #33ffff (blur 17) | |
| 2699 and 2696 | `whatToSay1`, "PLAY" twice, the second with the filters | (241.95, 304.50) 304.10x45.60 | `_sans` bold 36 #ffffff center | |
| 2692 | hit button for PLAY | (242.01, 305.10) 302.27x40.00 | | `subMenu` |
| 2698 | `whatToSay2`, "Game Manual" | (313.15, 365.50) 304.10x24.10 | `_sans` bold 18 #ffffff left | |
| 2693 | its hit button | (313.93, 367.36) 230.33x20.78 | | `designMenu` (124) |
| 2697 | `whatToSay3`, "Play More Games!" | (313.15, 395.50) 304.10x24.10 | as 2698 | |
| 2688 | its hit button | (313.93, 397.81) 230.33x20.78 | | armorgames.com |
| 2695 | `whatToSay4`, "Play the Original Sonny" | (313.15, 425.50) 304.10x24.10 | as 2698 | |
| 2691 | its hit button | (313.93, 427.81) 230.33x20.78 | | armorgames.com/play/505/sonny |
| 2694 | `whatToSay5`, "Credits" | (313.15, 455.50) 304.10x24.10 | as 2698 | |
| 2690 | its hit button | (313.93, 457.81) 230.33x20.78 | | `creditMenu` (134) |

The five captions keep their initial text: `frame_46/DoAction.as` only sets
`whatToSayX`. `dev/source_files/exported_assets/frames/46.png` shows the logo
reading "SONNY 2".

**`subMenu` (56)** [swf]: the logo again, then three captions, all
`_sans` bold 36 #ffffff center, filled from `MENU[21]`, `MENU[22]` and
`MENU[85]` (`frame_56/DoAction.as:1-3`):

| cid | Caption | Box | Hit button and box |
|---|---|---|---|
| 2709 | `whatToSay1`, "New Game" | (241.00, 290.10) 304.10x45.60 | 2707, (241.06, 290.70) 302.27x40.00 |
| 2708 | `whatToSay2`, "Load Game" | (241.00, 350.10) 304.10x45.60 | 2706, (241.06, 350.70) 302.27x40.00 |
| 2705 | `whatToSay3`, "PvP Arena" | (241.00, 410.10) 304.10x45.60 | 2704, (241.06, 410.70) 302.27x40.00 |

**`dataMenu` (74)**, the slot list [swf]. Four rows, each three captions in
`_sans` bold 26 and a hit button over the "Slot N" label only:

| Row | "Slot" (white, right, `slotNamerText` = `MENU[23]`) | Number (white, left) | Save name (#9dee66, left, `nameSlotN`) | Hit button |
|---|---|---|---|---|
| 1 | 2734, (195.00, 192.05) 107.85x33.05 | 2726, (308.00, 192.05) 121.30x37.10 | 2733, (356.50, 192.05) 385.10x35.55 | 2722, (213.00, 193.20) 113.80x30.00 |
| 2 | 2729, (195.00, 246.05) | 2725, (308.00, 246.05) | 2732, (356.50, 246.05) | 2721, (213.00, 248.70) |
| 3 | 2728, (195.00, 303.05) | 2724, (308.00, 303.05) | 2731, (356.50, 303.05) | 2720, (213.00, 304.20) |
| 4 | 2727, (195.00, 357.05) | 2723, (308.00, 357.05) | 2730, (356.50, 357.05) | 2719, (213.00, 359.70) |

The frame also places 2718 `pickText`, `_sans` bold 32 #ffcc00 center,
(90.25, 102.95) 619.50x40.60, filled only in arena mode, and `KrinToolTipper`
(2717) for the slot hover text. An empty slot reads "< Empty Slot >"
(`frame_74/DoAction.as:8`).

Port [port]: `scenes/main_menu.tscn` begins at `subMenu`. Its `ModePanel` has
New Game and Load Game as Labels over Buttons, and leaves PvP Arena out
(`scripts/ui/main_menu.gd:4-5`). Its `SlotPanel` lays the slots out in a
`VBoxContainer`.

Missing:

- The title Screen itself, which julian-perge/urchin#91 asks for: the logo
  321 is not extracted, and neither Game Manual (`designMenu`, 124) nor Credits
  (`creditMenu`, 134) has a port screen.
- Two title captions open Armor Games pages. ADR 0002 only names the logo, the
  copyright line and "Play MORE Games!", so whether "Play More Games!" and "Play
  the Original Sonny" stay out needs a call.
- The slot list's three-column layout, at the rects above.

### 2.2 New game flow

New Game runs `nameMenu` (64), `dataMenu` (74), `classMenu` (84) and
`optionsMenu` (93). Start then plays the intro. With the tutorial on it goes
through `CS_INTRO` (263) and `IntroSeq` (151) to battle 2, and with it off it
goes to `CS_INTRO2` (293), as `docs/research/2026-11-07-original-logic-vs-port.md`
records in its Corrections.

**`nameMenu` (64)** [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2713 | the name box | (185.55, 252.20) 426.10x45.25 | solid black at alpha 77, 1 px line #cccccc |
| 2712 | `krinNameUser`, input, "< Enter Name Here >" from `SYSTEM[34]` (`frame_64/DoAction.as:1`) | (187.70, 258.10) 424.60x35.55 | `_sans` bold 26 #ffcc00 center |
| 2711 | "OK!" | (339.40, 330.10) 121.25x51.30 | `_sans` bold 36 #ffffff center |
| 2710 | its hit button, to `dataMenu` | (368.33, 336.60) 61.83x30.00 | |

**`classMenu` (84)** [swf]:

| cid | Piece | Box | Look | Port |
|---|---|---|---|---|
| 2768 | `whatToSay1`, "Please select a class:" (`MENU[24]`) | (175.20, 107.90) 449.60x33.05 | `_sans` bold 26 #cd8787 center | rebuilt, Label |
| 2746 (instance `hydroDis`) | psychological card, at (162.00, 309.55) | card 2740 masks the art to 186.05x299.05 | 26 frames, Bevel+Glow+DropShadow+ColorMatrix on 2745 | script: `assets/ui/menu/class_cards/psychological*.png` |
| 2766 (`bioDis`) | biological card, at (402.00, 309.55) | as above | as above | script: `biological*.png` |
| 2755 (`psychoDis`) | hydraulic card, at (642.00, 309.55) | as above | as above | script: `hydraulic*.png` |
| 2739, 2756, 2747 | class names, `CLASS[1]`, `CLASS[0]`, `CLASS[2]` (`frame_84/DoAction.as:2-4`) | (56.05, 420.65), (296.05, 420.65), (536.05, 420.65), each 218.05x26.00 | Rockwell bold 19 #ffffff center. Each has an inner and an outer Glow: #ff66ff and #6633ff, #66cc66 and #33ff00, #00ffff and #0099ff | rebuilt, Labels in Rockwell |
| 2737, 2735, 2736 | the cards' hit buttons | about 184.39x300.20 over each card | | rebuilt, `TextureButton`s |

`start_screens.py:14-21` records why the card instance names disagree with the
classes.

**`optionsMenu` (93)** [swf]: two captions per row, a label right-aligned
ending at x 401.00 and a value left-aligned from x 408.00, all `_sans` bold.

| Row | Label cid, var, size, colour | Value cid, var | Hit button and box |
|---|---|---|---|
| Difficulty (`MENU[78]`) | 2779 `t_dif`, 23, #ff9900, (88.65, 114.95) 312.15x29.70 | 2778 `t_dif2`, 23, #ffff33 | 2775, (162.65, 114.95) 439.60x30.00 |
| Tutorial Level (`MENU[82]`) | 2777 `t_tut`, 23, #ff9900, (96.85, 150.60) | 2776 `t_tut2`, 23, #ffff33 | 2769, (162.65, 150.60) 439.60x30.00 |
| Sound (`MENU[27]`) | 2790 `tit_1`, 16, #9dee66, (236.90, 187.80) | 2788 `tit_3`, 16, #ffffff | 2774, (275.86, 187.80) 229.18x30.00 |
| Effects (`MENU[28]`) | 2789 `tit_2`, (236.90, 220.35) | 2787 `tit_4` | 2773, (273.61, 221.35) |
| Autosave (`MENU[35]`) | 2785 `tit_8`, (236.90, 252.90) | 2784 `tit_7` | 2772, (273.61, 253.90) |
| Graphics (`MENU[38]`) | 2781 `tit_9`, (236.90, 285.45) | 2780 `tit_11` | 2771, (273.61, 286.45) |

Above them sits 2786 `TitLOL1`, "Please configure your settings:", `_sans` bold
16 center, (195.05, 70.20) 409.95x24.10. Below them 2783 `TitLOL2` (`MENU[34]`),
`_sans` bold 14, (119.45, 323.05) 559.15x109.75, and the start caption 2782
`whatToSayY`, "Click here to START!" (`MENU[36]`), `_sans` bold 24 #60ef21
center, (159.55, 454.60) 480.95x30.85, over hit button 2770, (203.69, 456.80)
391.23x26.80. Frame script: `frame_93/DoAction_2.as`.

**The intro frames** [swf]:

| Frame | Pieces |
|---|---|
| `IntroSeq` (151) and `IntroSeq2` (166) | black shape 333 scaled to the stage, and the logo 321 at (414.90, 294.65), placed at alpha 0 |
| `CS_INTRO` (263) | backdrop 3475, radial #1e2426 to #000000, (-6.00, -4.00) 810.20x588.15. Four lines 3474 to 3471, `introText1` to `introText4`, `_sans` bold 23, 17, 22, 17 in #ffffff, #b6e0fc, #5ebfff, #6c7dbd, the first at (-22.30, 214.80) 844.60x29.70. A 401-frame timer sprite 3470 |
| `CS_INTRO2` (293) and every `CS_CUT` frame | 3475, then the video window at (133.50, 137.50): mask 2870, 533.00x300.00, and a 1 px black frame 3476, (133.00, 137.00) 534.00x301.00. "SKIP" 3469, `_sans` bold 12 right, (660.15, 543.75) 120.65x21.40, over hit button 3468, (720.04, 541.55) 79.01x26.80. Subtitles 3467 `subText`, `_sans` 18 #ffffff center, (202.80, 380.70) 394.40x73.70. A fade sprite 3466 |

Port [port]: `scenes/main_menu.tscn` has `NamePanel`, `NewGamePanel` and
`OptionsPanel`, rebuilt with Labels, Buttons and the extracted cards on
`start_background.png`. Effects and Graphics are skipped on purpose
(`KNOWN_GAPS.md`, "Effects/Graphics options"). `scenes/cutscenes/cutscene_player.tscn`
plays the CS_CUT videos full screen with a fade and no frame, SKIP or subtitles
(`scripts/cutscenes/cutscene_player.gd:4-7`).

Missing: the name box 2713 as drawn, the `CS_INTRO` text screen and
`CS_INTRO2` (julian-perge/urchin#49), the cutscene frame (3475, 2870, 3476), the
SKIP control 3468 and 3469, and the subtitle field 3467.

### 2.3 Hub and its hotbar panel

The hub is root frame `Navigation` (181). It places [swf]:

| Depth | cid | Piece | Origin | Port |
|---|---|---|---|---|
| 1 | 3317 | the bottom bar (4.1), DropShadow (blur 5, distance 5) | (400.00, 508.00) | hand: `assets/ui/hotbar/background.png`, per `docs/superpowers/specs/2026-08-22-battle-screen-extraction-design.md:40` |
| 59 | 3287 `KrinScreen` | hub art, orbs and info spots, DropShadow | (400.00, 222.90) | script: `assets/backgrounds/hub/<LABEL>.png` and `assets/ui/orbs/` (`extract_zone_hub`) |
| 126 to 167 | the hotbar | table below | | |
| 169 to 174 | zone progress | table below | | |
| 175 | 3142 `KRINMENU` | the Window shell (1.3) | (400.50, 222.40) | |
| 1610 | 2852 `KrinCombatText` | notice banner (4.8) | (400.00, 48.95) | none |
| 1612 | 2717 `KrinToolTipper` | the tooltip (5) | (800.00, 600.00), dragged to the mouse | rebuilt |
| 1651 | 2848 `krinNavFadeSpeech` | the info popup, hidden on load | (393.85, 286.00) | none |
| 1658, 1659 | 2840 `navText`, 2839 `navTitle` | info popup text | | none |
| 1660 | 2837 | full-screen black that fades out 15 alpha a frame | (399.05, 284.75) | none |
| 1662 | 2836 `ach_Display` | the achievement banner, 70 frames | (400.00, 97.50) | none |

**The hotbar** [swf] [as]. Each button is a DefineButton2 whose four states all
draw shape 3119 (solid #1e1e1e) as a dark square, placed with a Bevel
(#666666 and #0c0c0c), a 2 px black Glow (strength 10) and a soft black Glow
(blur 12). A 27-frame icon sprite sits over it, with labels `START` 2 and
`STOP` 8. The icon is a white shape, and its hover is a tween of the Glow on the
icon's placement. The colours below are frame 7, the end of `START`.

| Button | Hit button and box | Icon sprite, shape and box | Hover Glow at frame 7 | Tooltip [as] | Port icon |
|---|---|---|---|---|---|
| Inventory | 3185, (31.52, 473.79) 40.25x40.25 | `ui_but1` 3171, 3169, (36.73, 479.26) 28.78x28.62 | #ff66ff | `SYSTEM[17]`, `[18]` | hand: `resources/toolbar/inventory.png` 175x174 [size, 3169 at 5x] |
| Abilities | 3184, (79.72, 473.79) | `ui_but2` 3168, 3166, (85.94, 478.44) 25.56x31.01 | inner #66ff66, outer #33ff00 | `SYSTEM[19]`, `[20]` | hand: `abilities.png` 155x188 [size, 3166] |
| Save | 3183, (129.02, 473.79) | `ui_but3` 3165, 3163, (139.13, 479.39) 20.23x28.70 | inner #00ccff, outer #0099ff | `SYSTEM[21]`, `[22]` | hand: `save.png` 123x174 [size, 3163] |
| Options | 3180, (177.52, 473.79) | `ui_but4` 3162, 3160, (183.33, 479.25) 29.15x29.61 | #ffcc00 | `SYSTEM[23]`, `[24]` | hand: `options.png` 177x180 [size, 3160] |
| Re-Spec | 3179, (226.22, 473.79) | `ui_but5` 3159, 3157, (233.76, 481.16) 24.78x24.78 | inner #ff66ff, outer #6633ff | `SYSTEM[32]` plus the price, `[33]` | hand: `respec.png` 150x150 [size, 3157] |
| Achievements | 3153, (275.32, 473.79) | `ui_but7` 3152, 3150, (283.06, 482.40) 24.57x25.73 | inner #ff9900, outer #ff3300 | `SYSTEM[42]`, `[43]` | hand: `achievements.png` 149x156 [size, 3150] |
| World Map | 3177, (376.32, 484.30) 48.73x48.73 | `ui_but6` 3156, 3154, (384.45, 492.75) 31.80x31.80, under a GradientGlow | not decoded | `SYSTEM[27]`, `[28]` | hand: `world_map.png` 159x159 [size, 3154] |
| Quit | 3178, (436.08, 464.91) 18.02x18.00, then shape 3172 over it, (436.10, 464.90) 18.00x18.00, linear #891818 to #c40000 | | | `SYSTEM[25]`, `[26]` | hand: `quit.png` 361x361 [size, 3172 at 20x] |

The tooltip strings are at `frame_41/DoAction.as:84-110`, and each button's
`on(rollOver).as` is where they are set. The `resources/toolbar/` files date
from the repo's first commit, `b9caadf`. Two more buttons, 3182 and 3181, sit
off stage at x -64.95 and are debug controls. Sprite 3176 is a "www.armorgames.com"
strip, (31.55, 522.00) 284.45x25.00, with static text 3174 and hit button 2688,
and is branding.

**Zone progress** [swf] [as]:

| cid | Piece | Box | Look | Filled by `frame_181/DoAction.as` |
|---|---|---|---|---|
| 3149 `krinXbarPro`, shape 3148 | track | (505.00, 515.25) 251.40x14.05 | linear black to #333333 to #373737 to black | |
| its `bar` 3147, shape 3146 | fill, width set by AS | (504.70, 515.25) 251.40x14.05 | linear #64f953 to #ffffff to #91fa63, Glow | :4, :11 |
| 3144 | `klt1`, "Zone " + zone (`SYSTEM[9]`) | (536.70, 466.90) 181.10x24.90 | `_sans` bold 17 #ffffff center | :12 |
| 3143 | `klt2`, zone name and subtitle | (480.00, 489.15) 292.00x19.05 | `_sans` bold 12 #90f984 center | :13 |
| 3145 | `klt3`, "Stage " + stage (`SYSTEM[10]`) | (643.25, 532.30) 113.70x32.65 | `_sans` bold 10 #ffffff right | :14 |

**Hub spots and the info popup** [swf] [as]. On the `PRISON` frame, `KrinScreen`
places the orb sprite 3196 three times, and buttons 3186 (training), 3187
(shop), 3188 (story) and 3190 to 3193 (info spots). The info spots call
`krinNavHideUI(n)`, which shows `krinNavFadeSpeech` and fills `navTitle` and
`navText` from `NAVTITLE[n]` and `NAVTEXT[n]` (`frame_42/DoAction_21.as:9-24`).
The popup's pieces:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2847, scaled 5.165x24.008 | screen dim | (-12.59, -2.05) 812.95x576.20 | black at alpha 179 |
| 2846, shape 2845 | frame | (156.60, 104.25) 474.50x248.20 | linear #32333d to #5e7377, line #000000 |
| 2844, shape 2843 | face | (169.60, 116.75) 448.50x223.25 | radial #e1e1e1 to #777777, DropShadow (blur 13, distance 5) |
| 2839 | `navTitle` | (190.55, 131.40) 408.70x21.55 | `_sans` bold italic 14 #666666 left |
| 2840 | `navText` | (190.50, 155.45) 408.75x148.35 | `_sans` 12 #000000 left, multiline |
| 2842 | `texter`, the close prompt | (282.85, 310.80) 222.00x19.05 | `_sans` bold 12 #666666 center |
| 2841 | its hit button | (273.20, 304.00) 241.30x30.00 | |

The popup boxes are 2848's local boxes moved by its placement at
(393.85, 286.00).

Port [port]: `scenes/ui/hotbar.tscn` draws the hotbar as a `LeftPanel`
`TextureRect` of `hotbar/background.png` with the buttons in an `HBoxContainer`,
each with `Glow` and `Icon` `TextureRect`s from `resources/toolbar/`. The hover
colours come from reference captures (`scripts/ui/hotbar.gd:22-31`), not from
the Glow values above. The right panel rebuilds the zone progress with a
`ProgressBar` and three Labels. `scenes/zones/zone*.tscn` place `scenes/orb.tscn`
over the extracted hub art.

Missing:

- The bottom bar as extracted art: `bottom_bar.png` exists and the hub does not
  use it (4.1).
- The icons and the dark button squares by script. The icon shapes are known,
  3169, 3166, 3163, 3160, 3157, 3150, 3154 and 3172.
- The info spots and popup, julian-perge/urchin#16: buttons 3190 to 3193, the
  pieces above and the strings at `NAVTITLE` and `NAVTEXT`.
- The notice banner `KrinCombatText` (4.8), the achievement banner 2836 and
  2835, and the fade-in 2837.

### 2.4 World map

Root frame `overMap` (449) places `krinMapper` (4173) at (400.45, 275.45) and
`KrinToolTipper` [swf]. The World Map button opens it
(`DefineButton2_3177/BUTTONCONDACTION on(release).as:8`), and so do the
cutscenes after battles 109 and 409 (`frame_219/DoAction.as:36-39, 46-49`).
Choosing a zone is the only way out
(`DefineButton2_4155/BUTTONCONDACTION on(release).as:1-6`), and the map has no
close button.

| cid | Piece | Box | Look | Port |
|---|---|---|---|---|
| 4172 | the map art: mask 4163, background 4171, terrain 4170, 4165 and 4167 under blend modes, highlight 4168 | 4163: (20.00, 23.00) 760.95x504.95 | 4171: radial #ffffff to #bcdcb4 | hand: `assets/ui/zone_map/zone_map_full.png` 1906x1266, about 2.5x |
| 4162 | the map's 1 px frame | (19.50, 22.50) 761.95x505.95 | line #000000 | in the same PNG |
| 4161 `lineMC` | the zone links, drawn at runtime | | 6 px black under each link, then 2 px #3189df if the zone is open or #333333 if not (`frame_449/DoAction.as:24, 35, 46`) | rebuilt: `scripts/zones/zone_map_connectors.gd` |
| 4160 `mb1` to `mb7` | zone buttons, DropShadow | centres (117.45, 455.70), (313.20, 355.80), (663.70, 443.10), (740.35, 350.30), (612.65, 215.40), (506.35, 138.95), (109.35, 185.40) | | rebuilt, `TextureButton`s |
| 4159 `underGF` | the button face, labels frame 1 and `blank` 2 | 30.00x30.00 | 4157: radial #4a62bd to #211870. 4158 (`blank`, a locked zone): radial #222222 to black | hand: `zone_map_button_active.png` 640x640 and `zone_map_button_inactive.png` 601x601 [size, 20x] |
| 4156 | the button frame | 32.00x32.00 | 2 px line #000000 | hand: `zone_map_button_outer.png` 641x641 [size, 20x], unused |
| 4155 | the hit button | 30.00x30.00 | | |

Port [port]: `scenes/zone_map.tscn` also loads `assets/ui/zone_map/exit_screen.png`,
184x182, whose size matches the Window close X 2854 at 5x [size]. The original
map has no exit.

Missing: a script for the map art and the button faces.

### 2.5 Victory

Victory is `KRINMENU` at `win` (frame 9) on the hub, shown when the hub loads
after a win (finding 3). The frame script sets the texts, hides empty drop
slots and adds the money (`DefineSprite_3142/frame_9/DoAction.as`). Pieces
beyond section 1.3's [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2990, scaled 0.894x1.225 | left panel | (36.12, 80.96) 222.70x327.24 | panel 2989 |
| 2996 | `vbbc1`, "Character Experience" (`MENU[15]`) | (41.30, 87.10) 213.15x19.00 | `_sans` bold 13 #5e5e5e center |
| 3002, three of them | XP rows, centred at (147.60, 172.65), (147.60, 265.15), (147.60, 357.65) | each 3001: 196.80x83.20 around the centre | 3001 solid black. The row holds face 2978 (`avIn`, scaled 1.653), `namerI` 3000 and `levelI` 2999 (`_sans` bold 12 #cccccc), the XP bar 2867, its track 2998 and `exp2` 2997 |
| 2988, scaled 1.164x1 | centre panel | (274.90, 82.15) 213.15x326.50 | panel 2987 |
| 3005 | `vb1`, "Victory! Items that dropped:" (`VICTORY[0]`) | (288.20, 90.40) 187.30x55.00 | `_sans` 12 #666666 |
| 3013 `dropSlot0` to `dropSlot14` | drops, 5 columns on a 38 px pitch | first centre (305.10, 146.65) | slot 3013 |
| 3003 | `vb99`, "No Items Found." (`MENU[12]`) | (291.20, 163.80) 180.30x70.60 | `_sans` bold 19 #a53030 center |
| 3007 | `vb2`, "CLICK on the items that you wish to keep!" (`VICTORY[1]`) | (289.20, 244.80) 183.55x49.80 | `_sans` bold 12 #ffff33 |
| 3011, 3010 | `vb3` "Money gained:" and `vb5` the amount | (296.20, 287.20) and (362.70, 287.20) | `_sans` bold 12 #fad95a |
| 3009, 3008 | `vb4` "Exp. gained:" and `vb6` the amount | (296.20, 304.80) and (362.70, 304.80) | `_sans` bold 12 #ffffff |
| 3006 | `vb7`, "Once you are finished, press below to proceed:" | (290.20, 327.20) 180.30x49.20 | `_sans` 12 #666666 |
| 3014 | `vb8`, "Proceed!" (`MENU[13]`) | (293.30, 363.65) 173.80x24.10 | `_sans` bold 18 #66ff00 center |
| 3004 | its hit button | (295.30, 368.89) 171.50x25.61 | |
| 2990, 2992 | right panels, the inventory grid and the money bar | as in 3.1 | |

Port [port]: `scenes/battle/victory_screen.tscn` rebuilds this on
`menu_backdrop.png`, `panel_large.png` and `panel_center.png`, with
`scenes/battle/victory_experience_row.tscn` (`exp_track.png`, `exp_fill.png`)
for the rows and `scenes/ui/inventory.tscn` on the right. It is its own scene,
which the battle scene instances over itself when the fight is won
(`scripts/battle/battle_scene.gd:1135`), not a state of the hub.

Missing: the XP row backing 3001 and the row layout above. The rest is hand
art (1.3, 1.4).

### 2.6 Game over

Root frame `gameOverMenu` (104), on section 1.2's background [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2794 | `whatToSay111`, "You're dead, Sonny..." (`MENU[50]`) | (193.10, 93.75) 413.85x45.35 | `_sans` bold 30 #ffffff center |
| 2793 | `whatToSay222`, "< Click here to Re-Load >" (`MENU[51]`) | (250.90, 172.40) 298.20x33.05 | `_sans` bold 14 #ffcc00 center |
| 2791 | its hit button | (255.54, 173.00) 288.93x30.00 | |
| 2792 | `tipTextGO`, `GOTIP[0]` | (114.15, 231.65) 570.80x115.35 | `_sans` bold 14 #ffffff left |
| 2795 | `whatToSay3`, "Play MORE Games!", over a copy of 2688 | (488.15, 489.90) 304.10x30.85 | branding, ADR 0002 |
| 2703, 2702 | Back | 1.2 | |

Port [port]: `scenes/battle/game_over_screen.tscn` places a Label or Button at
each of these rects, on `start_background.png`. Its offsets equal the boxes
above, for example `DeadLabel` at 193.1, 93.75 to 606.95, 139.1.

Missing: nothing beyond the caption style, which no Label reproduces yet: the
hard black Glow and the DropShadow of 1.2.

### 2.7 Ending

Root frame `endMenu` (116) [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2796 | `enderText`, `ENDING` | (195.30, 109.45) 418.05x275.20 | `_sans` bold 14 #ffffff left, multiline |
| 2799 | "OK!" | (221.00, 410.10) 342.10x51.30 | `_sans` bold 36 #ffcc00 center |
| 2797 | its hit button | (340.43, 412.40) 104.04x40.00 | |
| 2798 | `whatToSay3`, "Play MORE Games!", over 2688 | (240.85, 469.10) 304.10x30.85 | branding, ADR 0002 |

Port [port]: `scenes/battle/ending_screen.tscn`, Labels at these rects on
`start_background.png` (ADR 0002 says so). Missing: the caption style, as in
2.6.

## 3. Windows

All three are `KRINMENU` labels at (400.50, 222.40), so every box below is a
stage box with that origin applied [swf].

### 3.1 Inventory (`inventory`, frame 1)

Three columns.

| cid | Piece | Box | Look |
|---|---|---|---|
| 2990 | left panel | (47.50, 86.60) 249.05x267.15 | 2989 |
| 2891, 2890 | `yut_name`, `yut_info` | (92.00, 90.05) 166.95x20.20 and (92.00, 109.85) 166.95x19.60 | `_sans` bold 14 and 12, #cccccc center |
| 121 to 143 | the doll, 31 part placements named `arm2` to `hand1_f` | part origins between (163.75, 163.30) and (207.95, 260.45) | doll art, attached by `DefineSprite_3142/frame_1/DoAction.as:61-71` |
| 2984 `playerSlot0` to `playerSlot6` | equip slots | centres (82.20, 172.15), (263.10, 172.15), (82.20, 212.15), (263.10, 212.15), (263.10, 252.15), (122.20, 252.15), (82.20, 252.15) | slot 2984 |
| 2869 | `yut_info51`, "Experience:" (`MENU[17]`) | (30.20, 284.40) 103.55x19.05 | `_sans` bold 12 #cccccc right |
| 2868 | XP bar's left box | (138.45, 282.85) 34.30x18.80 | solid #111111 |
| 2867 `bar` | XP fill, 14 frames, label `level` 2 | shape 2865, (172.60, 283.30) 95.10x18.75 | solid #cccccc |
| 2864 | XP bar gloss over both | (138.50, 283.15) 129.25x19.10 | five-stop black and white alpha gradient |
| 2863 | `exp2`, the percent | (136.55, 284.40) 34.80x17.70 | `_sans` bold 10 #ffffff right |
| 2992 | party bar | (47.50, 358.20) 249.05x50.85 | 2991 |
| 2979 `fa0` to `fa5` | party faces | centres x 72.20 + 40n, y 384.90 | black backing 333 (29.50x39.50), face 2978 under mask 2898, hit button 2895, and frame 2893 with Glow #99ff00, shown only on the selected member (`DefineSprite_3142/frame_1/DoAction.as:79-83`) |
| 2988 | centre panel | (308.95, 82.15) 183.05x326.50 | 2987 |
| 2980 | a 1 px outline inside it | (321.75, 89.45) 158.35x313.20 | line #333333 |
| 2889 to 2885 | `yut_lif`, `yut_str`, `yut_mag`, `yut_spd`, `yut_foc` | x 329.95, y 97.10, 114.55, 132.70, 150.85, 168.30, each 85.35x21.90 | `_sans` bold 12, #679339, #993333, #c48c3c, #735588, #8da9e9 |
| 2884 to 2880 | the five values, `yut_lif2` and on | x 385.95, same rows, 85.35x19.60 | same colours, right |
| 2879, 2878 | `yut_per` "Piercing", `yut_def` "Defense" (`SYSTEM[5]`, `[6]`) | (329.80, 196.80) and (329.80, 303.20), 119.80x19.60 | `_sans` bold 12 #666666 |
| 2877 `perBarShow`, `defBarShow` | eight element bars each, at (400.50, 256.00) and (400.50, 360.50) | 2874: (332.00, 221.75) 137.00x68.00 for the first | eight 11x68 bars on an 18 px pitch, recoloured from `elementColorArray` |
| 2990 | right panel | (503.50, 81.60) 249.05x267.15 | 2989 |
| 2856 | `vbbc0`, "Your Inventory" (`MENU[14]`) | (512.30, 87.10) 233.75x21.90 | `_sans` bold 13 #5e5e5e center |
| 2986 `itemSlot0` to `itemSlot35` | 6x6 grid on a 38 px pitch | first centre (533.10, 128.15) | slot 2986 |
| 2992 | money bar | (503.50, 358.20) 249.05x50.85 | 2991 |
| 2861, 2862, 2860, 2858 | money and the delete slot | 1.4 | |

The element bar parts [swf]: each bar is sprite 2873 or 2872 around sprite 2871,
a white 11x68 shape 2870, in four stacked copies (`ybar` dimmed to 10%, `bar`
at 30%, then `gbar` and `xbar` brightened with a Glow) over a track 2876 per
element (shape 333 scaled to 13x70). `DefineSprite_3142/frame_1/DoAction.as:226-230`
sets their colours with `setRGB`.

The `normal` label (frame 2) repeats this without the XP bar pieces 2868,
2867, 2864 and 2863 [swf].

Port [port]: `scenes/ui/menu/inventory_window.tscn` places `TextureRect`s of the
hand panel PNGs and Labels at fixed offsets, builds the element bars from
`ColorRect`s (`PerTrack0` to `DefFill7`), and reuses `scenes/ui/item_slot.tscn`
for the equip slots and the party portraits. `scenes/ui/inventory.tscn` holds
the grid, the money and the sell and delete slots. `scripts/ui/menu/menu_theme.gd:13-24`
carries the backdrop, close and slot geometry, which agree with the boxes above.

Missing: no extractor for any chrome piece (1.3, 1.4), and the face frame 2893
with its green Glow on the selected member, where the port draws
`item_slot.tscn`'s slot art around every face.

### 3.2 Store (`shop`, frame 16)

| cid | Piece | Box | Look | Port |
|---|---|---|---|---|
| 2990, scaled 0.894x1.225 | left panel | (36.12, 80.96) 222.70x327.24 | 2989 | hand |
| 3036 | shop keeper scene, frame `shopId + 1` | at (148.25, 169.90). Mask 3021: (55.25, 99.90) 186.00x140.00 | bitmap fills, frame 3020 | script: `assets/ui/store/backdrops/shop<id>.png` (`extract_store_art`) |
| 3019 | `vb2`, the keeper's line | (54.20, 257.15) 194.40x138.10 | `_sans` 12 #ffffff, multiline | rebuilt |
| 2988, scaled 1.164x0.418 | centre top panel | (274.90, 81.83) 213.15x136.42 | 2987 | hand |
| 2984 x7, scaled 0.86 | equip slots around a small doll | centres (301.10, 117.55) to (456.75, 186.40) | slot 2984 | none |
| 2988, scaled 1.164x0.538 | centre bottom panel | (274.90, 232.36) 213.15x175.50 | 2987 | hand |
| 3018 | `vb1`, the ware description | (288.20, 235.60) 187.30x55.00 | `_sans` 12 #666666 | rebuilt |
| 3013 `dropSlot0` to `dropSlot14` | wares, 5 columns on a 38 px pitch | first centre (305.10, 291.85) | slot 3013 | rebuilt, `GridContainer` |
| 3017, 3015 | sell slot | centre (685.10, 384.20) | 1.4 | hand |
| right column, money, delete slot, title, close | as 3.1 | | | |

The store's `fa` faces and element bars are set up by the frame script
(`DefineSprite_3142/frame_16/DoAction.as`), but this label places none of them.

Port [port]: `scenes/ui/store/store_window.tscn`. It has no equip slots or doll.

Missing: the equip slots and the small doll in the centre top panel.

### 3.3 Abilities (`skills`, frame 25)

| cid | Piece | Box | Look |
|---|---|---|---|
| 2990, scaled 1x1.296, twice | left and right panels | (44.93, 73.43) 249.08x346.10 and (506.33, 73.43) 249.10x346.10 | 2989 |
| 3061 | `k_title1`, the tree title | (51.65, 78.10) 232.70x22.10 | `_sans` bold 13 #5e5e5e center |
| 3100 `talenttreefull` | the talent tree, 12 frames, DropShadow (blur 3) | origin (45.40, 74.15) | `lineMC` 3099 plus 28 nodes |
| 3097 `st0` to `st27` | talent nodes, 4 columns on a 52 px pitch and 7 rows on a 40 px pitch | centres x 86.80, 138.80, 190.80, 242.80, y 124.00 to 364.00 | icon 2427, hit button 3096 (states 2434, 2435, 2436), rank texts 3091 to 3094 in `_sans` bold 12 |
| 2988, scaled 1.041x0.663 | centre top panel | (304.21, 74.15) 190.62x216.31 | 2987 |
| 3079, 3078 | `yut_name`, `yut_info` | (315.25, 77.70) and (315.25, 97.50), 166.95 wide | as Inventory |
| 3081, 3077 | `skLoadKrin` and `skillPoints` | (312.30, 120.15) and (378.80, 120.15) | `_sans` bold 12 #ffffff |
| 3080, 3076 | `spLoadKrin` and `statPoints` | (312.30, 139.15) and (378.80, 139.15) | as above |
| 3059 | tree description `reader` 3037, 163 frames | (317.95, 169.70) 159.70x104.80 | `_sans` 12 #999999 |
| 2988, scaled 1.041x0.357 | centre bottom panel | (304.21, 302.20) 190.62x116.56 | 2987 |
| 3063 | `k_title2` | (311.00, 304.80) 164.45x21.90 | `_sans` bold 13 #333333 center |
| 3068 to 3071 | the four stat plus buttons, colour-tinted | at (332.60, 347.45), (332.60, 365.20), (332.60, 383.70), (332.75, 401.35) | 3075 `statColor` behind them |
| 3089 to 3082 | four stat names and values | names x 356.90, values x 393.90, rows y 338.45 to 392.20 | as Inventory |
| 3062 | `k_title3`, the action bar title | (514.30, 78.10) 233.75x21.90 | `_sans` bold 13 #5e5e5e center |
| 3109 `selector` | the action bar ring, scaled 1.038, DropShadow (blur 6, distance 4) | centre (630.60, 172.20) | 8 icons 2427 and 8 hit buttons 3101 to 3108 on a 49.5 px radius |
| 3060 | `k_title4`, "Ability Pool" (`MENU[16]`) | (514.30, 248.10) 233.75x21.90 | as `k_title3` |
| 3120 `talentPool` | the pool list | mask 3117: (523.60, 274.20) 217.35x133.05 | 3119 #1e1e1e, frame 3116 #262626, scroll buttons 3115 and 3114, rows 2441 `talenter` attached at runtime (`DefineSprite_3142/frame_25/DoAction.as:39`) |

A pool row 2441 is a 61.95x30.00 white shape 2438 behind an icon 2427 at
x 28.50 and a hit button 2437, with a black gradient tab 2439 at x 105.30 [swf].

Port [port]: `scenes/ui/menu/abilities_window.tscn` uses the hand panel PNGs,
`scenes/ui/menu/talent_node.tscn` and `scenes/ui/menu/ability_pool_row.tscn`,
draws the pool backing as a `ColorRect` and the stat plus buttons as plain
`Button`s. The icons are script art (`extract_ability_icons`).

Missing: the radial slot buttons 2434 and 2435, the stat plus buttons' state
shapes 3064 to 3067, the pool's frame 3116 and scroll buttons 3115 and 3114
(shapes 3110 to 3113), and the row tab 2439.

### 3.4 The other KRINMENU labels

- `ach` (45) [swf]: 2990 scaled 2.614x1.123, (74.96, 82.41) 651.11x299.94.
  Ten plates 3141 in two columns, centres x 318.05 and 483.05, y 154.95 to
  330.95 on a 44 px pitch. A plate shows 3139 on frame 1 (linear #11141a to
  #383e50) and 3140 on frame 2 (radial #55a3ee to #2e4085), 150.95x31.70, with
  `achTit` 3138 (`_sans` bold 14 #000000) and a hit button 3137, placed with a
  Bevel, a 2 px black Glow and a DropShadow. A plate goes to frame 2 when its
  achievement is earned (`DefineSprite_3142/frame_45/DoAction.as:6-9`). The
  title 3136, "Achievements", is `_sans` bold 20 #ffcc33 at (195.55, 99.10).
  Port: `scenes/ui/menu/achievements_window.tscn` on `panel_large.png`.
- `options` (39): the in-game settings, the same rows as `optionsMenu` in
  `_sans` bold 14 #d56666. The port's Options button says "Coming soon"
  (`scripts/ui/hotbar.gd:40`).
- `data` (32): two panels and a hit button 3121, reached only from the
  off-stage debug button 3182.
- `hide` (52): empty.

## 4. Battle HUD

The battle is root frame `KRINBATTLESCENE` (217) [swf]. Every box below is a
stage box.

### 4.1 Bottom bar and member bars

The bottom bar is 3317 (`UI_BAR` on this frame), at (400.00, 508.00) with a
DropShadow (blur 5, distance 5):

| Depth | cid | Piece | Box | Look |
|---|---|---|---|---|
| 1 | 3316, shape 3315 | body, with Bevel (#b8d7df and #141414) and a 2 px black Glow | (14.50, 453.30) 771.15x109.40 | linear #32333d to #5e7377, line #000000 |
| 3 | 3314 | clip mask over depth 4, which is empty | (15.00, 453.80) 770.15x108.40 | metal gradient |
| 5 | 3288 | clip mask over depths 6 to 57 | (21.30, 460.15) 757.60x94.00 | |
| 6 | 3313 | the inner well, shown only inside 3288 | (11.00, 440.70) 778.95x129.00 | black at alpha 26 |
| 7 | 3312 `subAI_BAR` | the member bars | at (31.05, 473.70) | |

The member bars are covered by `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`:
3311 `p5` and `p3` at (173.70, 486.30) and (173.70, 523.80), each a backing
3309, a name 3308 and five stance buttons 3306. The bar container goes to
`HIDE` on load and to `SHOW` only on the player's side's turn [as]
(`DefineSprite_3317/frame_1/PlaceObject2_3312_7/CLIPACTIONRECORD onClipEvent(load).as:2`,
`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:705, 754`).

The centre of the bar [swf]:

| Depth | cid | Piece | Box | Look |
|---|---|---|---|---|
| 65 | 3460 | the alert icon, a 48-frame "!" pulse | 3459: (385.00, 492.90) 30.00x30.00. "!" 3457: 5.10x18.20 | 3459 #2f2f2f. 3457 white with a Glow #ffcc00 whose blur cycles 0 to 17 |
| 480 | 3389 `battleClocker` | the turn timer: disc 3388 and ring `thingerClock` 3387 | 3388: (368.20, 475.45) 63.60x63.60 | 3388 black. 3387's two masked half rings 3384 under Glow #0066ff and #0066cc at `friend` (1), #ffcc00 and #ff6600 at `enemy` (12) |
| 484 | 2427 `krinToMove` | the selected move's icon, scaled 1.229 | centre (400.00, 507.50) | ability icon. Tooltip "You may click here to skip your turn." (`frame_217/PlaceObject2_2427_484/CLIPACTIONRECORD onClipEvent(load).as:13`) |
| 498 | 3383 `krinToMove2` | its button, scaled 1.43, states 2434, 2435 and 2436 | centre (400.00, 507.75) | |
| 628 | 3373 `moveSelectBoomer` | a 25-frame burst, 3372 and shape 3371 | 125.70x125.70 around (400.00, 508.10) | Glow |
| 644, 646 | 3356, 3172 | Quit: the dark button square and the red square over it. Its tooltip is `SYSTEM[25]`, "Quit", and its release goes to `resetHere` (`DefineButton2_3356/BUTTONCONDACTION on(release).as:7`) | 3172: (435.85, 464.15) 18.00x18.00 | 3172: linear #891818 to #c40000 |

Port [port]: `scenes/battle_scene.tscn:104-226` builds `BottomBar` from a
`Backdrop` of `hotbar_background.png` (3315 at 1x [size], 771x109), three
`Panel` `TextureRect`s of `hotbar/background.png`, a `CountdownRing` of
`battle_pbar_full.png` inside `Panel3` at (488, 500), a code-drawn `PassRing`
and a "!" `PassButton` at (372, 507) 56x56, and an "x" `RetreatButton` at
(442, 482) 26x26. `scenes/battle/stance_row.tscn` is the member bar, built from
script art.

Missing:

- `bottom_bar.png` is extracted (`battle_screen.py`, 4x, 3312 stripped) and
  unused. `NEXT_PHASES.md:208-209` already lists repointing `Backdrop` to it.
- The timer ring 3387 in its two glows, the disc 3388, the move icon in the
  centre and its burst 3373. The port's ring is a hand PNG whose source shape
  is unconfirmed, and it sits in the right panel instead of at the centre.
- The member bars' `SHOW` and `HIDE`, their `inactive` frame and the team 2
  binding, which the bottom bar spec left out of scope.

### 4.2 Top status bar

The panel is 3465 at (400.00, 73.30) with a DropShadow [swf]:

| Depth | cid | Piece | Box | Look |
|---|---|---|---|---|
| 1 | 3464, shape 3463 | body, Bevel (#b8d7df and #141414) and 2 px black Glow | (14.50, 7.30) 771.85x116.25 | linear #32333d to #5e7377, line #000000 |
| 3 | 3461 | clip mask over depths 4 and 5 | (15.00, 7.80) 770.85x115.25 | |
| 4 | 3462 | the inner well, shown only inside 3461 | (9.00, 2.00) 778.95x129.00 | black at alpha 26 |

The six unit bars are 3414 placed on the root, scaled 1.085x1.161, with a
DropShadow (blur 5, distance 3, strength 0.72). `p5BAR`, `p1BAR` and `p3BAR`
are centred at x 136.15 and `p6BAR`, `p2BAR` and `p4BAR` at x 664.90, at y
28.55, 63.60 and 98.40. A bar for an empty slot is hidden on load
(`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(load).as:27`).
One bar, `p5BAR` [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 2847 | backing | (27.62, 14.62) 170.83x27.85 | black at alpha 179 |
| 3410 `lB2`, `lB` | life bar, scaled 0.787 wide | top row, x from 27.62 | `LCC` (55), a 101-frame clip that picks the life colour by percent |
| 3412 `fB2`, `fB` | focus bar | bottom row | 3411, 200x12, #0099cc |
| 3409 `lB3`, `fB3` | hosts for `LifeBarSmoother` (57) and `LifeBarSmoother2` (56), attached at runtime | | `frame_42/DoAction_8.as:319, 337` |
| 333 | number backing | (198.57, 14.45) 45.97x28.20 | black |
| 3408 | gloss frame | (27.07, 13.52) 218.15x30.12 | two alpha gradients, line #000000 |
| 3395 | `playerName` | (29.73, 12.36) 108.75x18.57 | `_sans` 9 #ffffff left |
| 3398, 3399 | `lifeNow` (#ffffff, right) and `lifeMax` (#9d9d9d, left) | (151.83, 13.23) and (198.50, 13.23), 46.56x18.57 | `_sans` 9 |
| 3396, 3397 | `focusNow`, `focusMax` | (151.83, 27.16) and (198.50, 27.16) | as above |

The right column's text sprite 3407 goes to its `second` frame on load
(`frame_217/PlaceObject3_3414_396/CLIPACTIONRECORD onClipEvent(load).as:2`, and
the same for depths 414 and 432), which right-aligns the name at the bar's
right end and moves the numbers to its left. `frame_42/DoAction_8.as:274-278`
fills the fields.

Port [port]: none. `top_panel.png` is extracted and unused, and `KNOWN_GAPS.md`
("Battle top panel frame extracted, bars not built") scopes the bars out. The
port shows life and focus in `scenes/battle/unit_overlay.tscn` instead.

Missing: the bars 3414 and everything in them, the life colour clip 55, the
smoothers 56 and 57, and the panel itself in the scene (julian-perge/urchin#67).

### 4.3 Buff row

A unit's buffs are drawn in its top status bar, not over the unit [as]. After a
unit's stats are recomputed, `frame_42/DoAction_10.as:345-376` removes and
re-attaches up to seven `KrinBuffShower` clips (DefineSprite 104) to
`p<id>BAR`, at depth `h` and `_x = (110 + 17 * h)`, negated for team 2. It
sends `buffIcon` to the buff's name and sets `buffColor`'s colour with
`Color.setRGB` to the element's colour from `elementColorArray`
(`frame_41/DoAction_2.as:2`). Only `_x` is negated, so team 2's icons are not
flipped.

Inside the bar's scale, buff `h` of a left-column bar is centred at stage
x 255.50 + 18.445h, and of a right-column bar at 545.55 - 18.445h, at the bar's
y [swf, computed from the matrices above].

`KrinBuffShower` (104), local boxes around its origin [swf]:

| Depth | cid | Piece | Box | Look | Port |
|---|---|---|---|---|---|
| 1 | 103 `buffColor`, shape 102 | the element backing | (-7.50, -12.55) 14.75x25.15 | solid #00ff66, recoloured at runtime | none |
| 3 | 101 | the tile frame and gloss | (-8.00, -13.25) 15.75x26.35 | fills solid #00ff66 and a white to black gloss gradient, line #000000. Which edges use which fill is not decoded | none |
| 4 | 100 `buffIcon` | the icon, 400 frames under 419 labels | mask 67: (-5.95, -10.95) 11.90x21.90 | | script: `assets/ui/buffs/<label>.png` (`extract_buff_icons`, 2x, mostly 24x43) |
| 8 | 66 `buffCounter` | turns left, placed at (-10.30, -0.80) | (-12.30, -2.80) 24.55x16.35 | `_sans` bold 10 #ffffff center | rebuilt, a Label at the same offset (`scripts/battle/unit_overlay.gd:15-19`) |

The tile is about 17x31 px on the stage after the bar's scale. The icons the
port extracted are tall, 24x43 at 2x for 218 of 419, which matches the mask 67.

Port [port]: `scenes/battle/unit_overlay.tscn`'s `BuffRow` draws the icons in
16x16 boxes (`scripts/battle/unit_overlay.gd:14`), tinted with the element
colour (`:92`), with no backing, above the unit.

Missing, which are the map's wave 5 notes with the pieces named:

- buffColor 103 and frame 101, which `buff_icons.py` never extracted.
- The tile's portrait shape, about 17x31 against the port's 16x16.
- The row's place in the top status bar.
- The redraw only when the unit's stats are recomputed.

### 4.4 Unit overlays

The original has no bar over a fighter. What it draws over each unit [swf] [as]:

| cid | Piece | Where | Look |
|---|---|---|---|
| 3394 `KrinSelector1` to `KrinSelector6` | hover selector, parked at x -64.90 and moved onto each fighter at battle start (`frame_217/DoAction_2.as:208-262`), scaled 0.9, Glow #ffffff (blur 22x5) | centred on the fighter | hit shape 3392, 70x70, a white radial glow that fades in 20 alpha a frame on hover and out 5 (`frame_217/PlaceObject3_3394_475/CLIPACTIONRECORD onClipEvent(enterFrame).as:2-17`). Selectors 2, 4 and 6 are tinted with add (0, -138, -159), and 3 and 5 with (-102, 0, -189) |
| 3391 `TargetName` | the unit's name | 330.34x38.56, centred on x, from y + 43.6 | `_sans` bold 14 #ffffff center |
| 3390 `TargetLevel` | "Lvl. " + level (`MENU[0]`) | 329.85x18.18, centred on the unit | as above |
| 2674 `speech` | the "!" speech bubble in the fighter rig 2676, played when the unit speaks (`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:842`) | (-10.65, -64.30) from the fighter, mirrored | bubble 2669 (46.50x49.35, radial #555555 to black) and "!" 2671 |
| 2675 `shield` | the shield in the rig, 20 frames | on the fighter | |
| 53 `NumberFixer` | floating numbers, labels `normal` 1, `critical` 69, `miss` 131, `shield` 183, attached to `BATTLESCREEN` (`frame_42/DoAction_7.as:37`) | over the fighter | digits are `NumberSetter` (44), labels `One` to `Zero`, attached per digit (`:55`) |

Port [port]: `scenes/battle/unit_overlay.tscn` rebuilds a name Label, a health
`ProgressBar` with its value, a focus `ProgressBar`, a hit `Button`, a buff row
and a code-drawn ring, over each doll. Floating numbers are Labels
(`scripts/battle/battle_scene.gd:1080-1099`), and its comment notes the
original's digits are shapes.

Missing: the selector glow 3392 and its two tints, the level text, the speech
bubble 2674 (stripped with the rig by `battle_screen.py:18-26` and not
extracted on its own), and the digit art 44. Whether the port keeps bars over
the units at all is the HUD decision that waits on julian-perge/urchin#41 and
julian-perge/urchin#44.

### 4.5 Speech box

The speech box is `combatScript` (3367) at depth 634 [swf]. The conductor moves
it to (21.80, 460.70) when a team 1 unit speaks and to (473.30, 460.70) for
team 2, then fills it [as]
(`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:819-831`).
It fades in and out 5 alpha a frame
(`frame_217/PlaceObject2_3367_634/CLIPACTIONRECORD onClipEvent(enterFrame).as:1-27`).
Boxes at its default spot (473.05, 460.55) [swf]:

| cid | Piece | Box | Look |
|---|---|---|---|
| 3365, shape 3364 | outer frame | (466.60, 452.85) 317.55x108.40 | linear #32333d to #9aabb1 |
| 3363, shape 3362 | face, DropShadow | (472.55, 460.05) 306.50x95.00 | radial #ffffff to #a2a2a2, line #000000 |
| 333 | portrait backing | (481.68, 468.54) 60.00x80.00 | black |
| 2978 `inner2` | the speaker's face, scaled 1.97, sent to the speaker's name | centred (511.70, 508.75) | script: `assets/ui/menu/portraits/` (`extract_faces`) |
| 3360 | `combatTextName` | (546.05, 463.95) 226.70x19.05 | `_sans` bold 12 #666666 left |
| 3361 | `combatText`, scaled 1.038 | (546.07, 480.12) 227.72x70.62 | `_sans` 11 #000000, multiline |
| 3359, 3358, 3357 | `say`, "Press SPACEBAR to Skip" (`MENU[53]`, `DefineSprite_3358/frame_1/DoAction.as:1`), a 45-frame pulse | (476.45, 417.40) 300.20x22.00 | copy 10_65 9 #99ff00 center, embedded outlines |

The whole box is placed with a Glow on 3366 [swf].

Port [port]: `UI/SpeechLabel`, one Label at (80, 430) 640x36 showing
"speaker: line" (`scenes/battle_scene.tscn:236`,
`scripts/battle/battle_scene.gd:1013`).

Missing: all of it except the portrait art, which exists for the Windows.
julian-perge/urchin#9 covers the speech box's presentation.

### 4.6 Radial menu

The radial menu is `selector` (3382) at (400.65, 300.15), scaled 1.038, with a
DropShadow (blur 6, distance 4) [swf]. The AS moves it and hides it
(`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:784`
and `frame_217/PlaceObject3_3382_500/CLIPACTIONRECORD onClipEvent(enterFrame).as`).

| cid | Piece | Local position | Look |
|---|---|---|---|
| 2427 `thing0` to `thing7` | the eight move icons, clockwise from the top | (0, -49.20), (34.80, -34.90), (49.50, 0), (35.00, 35.30), (0, 49.80), (-35.20, 35.10), (-49.50, 0), (-35.00, -34.70) | ability icon, with its mask 2242 and the cooldown disc 2241 and counter 2245, hidden in `onLoad` unless `dontHide` |
| 3374 to 3381 `thingo0` to `thingo7` | one hit button over each icon, scaled 1.163 | the same ring | up: 2434, 21x21. Over and down: 2435, 22.5x22.5. Hit: 2436. All three solid fills |

The talent nodes (3097), the action bar ring (3109), the pool rows (2441) and
`krinToMove2` (3383) use the same three button shapes [swf].

Port [port]: the radial menu is built in `scripts/battle/battle_scene.gd` from
the script-extracted icons, with element-coloured rings (`KNOWN_GAPS.md`,
"Ability orb art - RESOLVED").

Missing: shapes 2434 and 2435 as the button states. What the ring looks like
belongs to julian-perge/urchin#41.

### 4.7 Turn label

There is no turn label in the original [as]. `rg -i` over the AS finds no
"your turn", "enemy turn", "ally turn" or "your move" string. The original
marks the side to move by `thingerClock`'s frame, `friend` or `enemy`, and by
the member bars' `SHOW` and `HIDE` (4.1).

Port [port]: `UI/TurnLabel` shows "Your move", "Enemy turn" or "Ally turn"
(`scripts/battle/battle_scene.gd:711, 719`). This is a departure a player can
notice, so the map's rule asks for an ADR or its removal.

### 4.8 Notices, the hall window and debug text

| cid | Piece | Box | Look | Port |
|---|---|---|---|---|
| 2852 `KrinCombatText` | notice banner, 136 frames: fades in and slides up 10 px from frame 2 (`GO`) to 12, holds, fades out from 126. At (400.00, 148.50) in battle and (400.00, 48.95) on the hub, with Glow #ff0000 | bar 2850 once in place: (25.00, 135.00) 749.95x27.00 in battle | 2850 radial white alpha, `combatText` 2849 `_sans` bold 12 #000000 center. Used for errors such as "This move is not ready yet." (`frame_42/DoAction_11.as:63-78`) | none |
| 3455 | the hall's black window, DropShadow | (15.01, 129.99) 770.00x314.05 | black | script: `stage_rect.png`, unused |
| 333 at depth 72 | clip mask over depths 73 to 340, so the sky and hall show only inside it | (15.01, 130.39) 770.00x314.05 | | none |
| 3415 | 1 px outline of the window | (14.50, 129.90) 771.00x315.05 | line #000000 | none |
| 3369, 3368 | "FPS:" and `frameRateNowKrin` | (18.30, 132.60) | `_sans` bold 9 | out of scope, debug |
| 3355 `blacker5` | the end-of-battle fade, 85 frames | full stage | black | none, julian-perge/urchin#86 |

The window 3455, the mask and the outline are the "hall framing" julian-perge/urchin#67
asks for. `NEXT_PHASES.md`, "Battle hall coordinate system - TO BE SPECCED",
explains why placing them waits on the 800x575 against 800x600 question.

## 5. Shared tooltip

The tooltip is `KrinToolTipper` (2717), placed at (800.00, 600.00) on root
frames 74, 84, 181, 217 and 449, and dragged to the mouse every frame
(`frame_181/PlaceObject2_2717_1612/CLIPACTIONRECORD onClipEvent(enterFrame).as:2`)
[swf] [as]. `docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md`
already decodes its layout. The pieces:

| cid | Piece | Where | Look |
|---|---|---|---|
| 2716 `fontBacker`, shape 68 | body backer, resized to the body field | frames `GO` (4), `GO2` (7), `GO3` (10), `GO4` (13), `GO7` (17) | 30x30, black at alpha 230 |
| 2715 `fontBacker2`, shape 2714 | title backer | the same five frames | linear white, #aaaaaa (alpha 217), white |
| 2715 `fontBacker3` | sub-header backer, at x 90 | `GO2`, `GO3`, `GO4`, `GO7` | add (-31, -6, 0) on `GO2` and `GO7`, (5, -41, 96) on `GO3`, none on `GO4` |
| 2716 `fontBacker4` | next-rank backer, add (50, 40, 53) | `GO7`, y 38 | |
| 2064 `inner`, 2427 `inner2` | the item or ability the mouse carries | frame 1 onward | item and ability icons |
| runtime text fields | `my_txt2` title, `my_txt` body, `my_txt3` sub-header, `MY_TX0` to `MY_TX9` stat lines, `ttt` flavour, `my_txt4` next rank | width 170 (`GO`), 150 (`GO2`, `GO3`, `GO7`) or 200 (`GO4`), at x 13 or a negative offset near the right edge | all `_sans` 12, each with `border = true` except the stat and flavour lines |

[as] `DefineSprite_2717/frame_4/DoAction.as:17-54`, `frame_13/DoAction.as:19-98`
and `frame_17/DoAction.as:15-83`. The title backer's colour comes from
`krinChangeColor(fontBacker2, colorChange)` (`frame_4/DoAction.as:8`,
`frame_13/DoAction.as:8`), whose add terms are Common (0, 0, 0), Uncommon
(-62, -51, 0), Rare (86, 0, -164), Orange (126, 15, -200) and Unique
(-67, 0, -159) (`frame_42/DoAction_3.as:49-93`). An item slot passes the item's
rarity, `KRINITEM<id>[2]` (`DefineButton2_2985/BUTTONCONDACTION on(rollOver).as:3`).

Port [port]: `scenes/ui/game_tooltip.tscn` and `scripts/ui/tooltip_theme.gd`
rebuild the backers as flat colours from the gradients' midpoints and the text
formats from the frame scripts.

Missing: the fields' borders (`border = true`), the rarity tint on the title
backer, and the title backer's gradient. These match the map's wave 5 notes.

## 6. What is missing, collected

Art the SWF has and the port does not, grouped by the work that would add it.
"Script" means a `render.py` job in an existing or new extractor.

| Piece | cid | Needed by | Kind |
|---|---|---|---|
| title logo | 321 (shape 320) | title Screen, julian-perge/urchin#91 | script |
| buff backing and tile frame | 103 (102), 101 | buff row | script, or a `StyleBoxFlat` for 102 since it is one solid fill recoloured at runtime |
| unit bar | 3414 and its parts 3408, 2847, 3410, 3412, 55, 56, 57 | top status bar, julian-perge/urchin#67 | extract the parts, rebuild the arrangement |
| speech box | 3364, 3362, 3357 | battle, julian-perge/urchin#9 | extract the parts, rebuild |
| speech bubble | 2674 | battle | script, rendered on its own since the rig 2676 is stripped |
| selector glow | 3392 | unit overlays | script |
| timer ring, two states | 3387 (3386, 3384), 3388 | bottom bar | script, two frames |
| alert icon | 3460 | bottom bar | already extracted as `alert_icon.png`, unused |
| floating number digits | 44, 53 | battle presentation, julian-perge/urchin#9 | script, one per label |
| radial button states | 2434, 2435 | radial menu, Abilities | script |
| notice banner | 2850 | hub and battle | script, since its fill is a radial gradient |
| hub info popup | 2845, 2843, 2847 | julian-perge/urchin#16 | rebuild. 2847 is one solid fill, 2845 and 2843 are gradients |
| achievement banner | 2835 (2836) | hub | script |
| achievement plates | 3139, 3140 | Achievements Window | script, since both fills are gradients |
| cutscene chrome | 3475, 2870, 3476, 3468, 3469, 3467 | new game flow, julian-perge/urchin#49 | rebuild |
| hall window and outline | 3455, 3415, mask 333 | battle, julian-perge/urchin#67 | `stage_rect.png` exists, unused |

Art the port has only as hand exports, with no script:

| PNG | SWF piece [size] |
|---|---|
| `assets/ui/menu/menu_backdrop.png` | 2993 at 2x |
| `assets/ui/menu/panel_large.png`, `panel_bar.png`, `panel_center.png` | 2989, 2991, 2987 at 2x |
| `assets/ui/menu/slot.png`, `slot_highlight.png` | 2982, 2857 at 2x |
| `assets/ui/menu/close_x.png`, `assets/ui/zone_map/exit_screen.png` | 2854 at 2x and 5x |
| `assets/ui/menu/button_delete.png`, `button_sell.png`, `assets/ui/store/sell.png` | 2859 at 2x, 3016 at 2x and 20x |
| `assets/ui/menu/exp_track.png`, `exp_fill.png`, `exp_zero_box.png` | 2864, 2865, 2868 at 2x |
| `resources/toolbar/*.png` | 3169, 3166, 3163, 3160, 3157, 3150, 3154 at 5x, 3172 at 20x |
| `assets/ui/zone_map/zone_map_full.png`, `zone_map_button_*.png` | 4172 at about 2.5x, 4157, 4158 and 4156 at 20x |
| `assets/ui/battle/hotbar_background.png` | 3315 at 1x |
| `assets/ui/hotbar/background.png` | 3317, per the 2026-08-22 spec |
| `assets/fonts/*.ttf` | fonts 287, 335, 2738, 3173, 3307 |

Three hand PNGs have no confirmed source [port]: `assets/ui/battle/battle_pbar_full.png`
(1273x1273, a dark ring, loaded by `battle_scene.tscn:6`),
`assets/ui/battle/battle_progress_bar_inner.png` (126x126, a ring, unused) and
`assets/ui/battle/hotbar_team_select.png` (5701x627, opaque dark grey, unused).

Port UI with no original: `UI/TurnLabel` (4.7), `CombatLogPanel` (kept by
`docs/adr/0001-keep-the-combat-log.md`), the Log button in `Panel3`, and the
world map's exit button (2.4).

## 7. Open questions

- What font stands in for `_sans`? 217 of 227 text characters need one, and
  `scripts/ui/tooltip_theme.gd:39-43` found Arial at 12 px reproduces the
  original's line breaks where the current fallback runs about 9% wide.
  Nothing here checked which fonts are free to ship with Arial's metrics.
- Should the Window chrome be extracted by script or drawn with `StyleBoxFlat`?
  Panels 2989, 2991 and 2987 are one solid fill and a 1 px line each, which a
  `StyleBoxFlat` draws exactly. The backdrop 2993 is a radial gradient, and the
  slots, the delete and sell slots and the XP gloss are linear gradients, which
  a single-colour `StyleBoxFlat` cannot draw [guess, Godot not checked].
- How should the captions' hard black Glow (blur 3, strength 10) and DropShadow
  be drawn? A Label outline plus a shadow offset of 2 is the obvious stand-in
  [guess], and no test compares it with the original yet.
- Where does the port's battle UI go on the y axis? Every HUD box above is on
  the 800x575 stage, and the port's viewport is 800x600 (`NEXT_PHASES.md`,
  "Battle hall coordinate system").
- Does `battle_pbar_full.png` come from 3386's ring? Its size, 1273, is 3388's
  63.60 at 20x, but it has a transparent centre, and 3388 is a solid disc.
- Which edges of shape 101 use its green fill and which its gloss? That decides
  whether the buff tile's border is green or follows the element colour.

## Appendix: scratch scripts

All in `~/tmp/2026-11-09-ui-pieces-inventory/`. Each is a PEP 723 script with
no dependencies that imports `urchin_dev.swf` from this worktree and reads the
main checkout's `sonny-2-2900.swf`, since the worktree has no SWF.

- `swfx.py`: shared helpers. Parses DefineEditText, DefineText, DefineButton2
  records and the font tags on top of `swf_index.py`.
- `swfx_styles.py`: a shape's first fill and line style arrays.
- `tree.py <owner> <frame or label> <levels> [matrix]`: walks one frame
  through `timeline.frames()`, composing matrices to stage boxes. Made the
  `t_<frame>.txt` and `k_<label>.txt` dumps.
- `dump_root.py`, `dump_frames.py`, `root_ranges.py`: root labels, exports,
  fonts, each label's display list, and the check that from root frame 46 on no
  label's display list changes before the next label, so one walk per label
  covers each Screen.
- `dump_sprite.py`, `dump_many.py`, `where.py`: a sprite's labelled frames, a
  set of characters, and every placement of a character.
- `filters.py`: Glow, DropShadow, Bevel, Blur and ColorMatrix parameters per
  PlaceObject3, for a sprite or the root.
- `font_use.py`: which text characters use which font.

Two cross-checks back the walkers. The font list matches the eleven
DefineFont3 tags in `dev/source_files/swf_xml/sonny-2-2900.xml`, and the edit
text boxes on `gameOverMenu` match the offsets the port took for
`scenes/battle/game_over_screen.tscn` to the second decimal.
