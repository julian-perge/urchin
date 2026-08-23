# Battle bottom bar and stance rows

**Goal:** re-extract the battle bottom bar without the team member bars baked
into it, extract the stance button art the member bars are made of, and give
the port's existing `StanceRow` that art instead of the coloured rectangles it
draws today.

**Status:** design, not yet implemented.

## Why now

`assets/ui/battle/bottom_bar.png` came out of the battle screen extraction on
2026-08-22 and is wrong. It is a render of DefineSprite 3317, which places the
member bar container at depth 7, so the bar ships with two rows reading
"Thurman McPown" and ten aggression buttons burned into it. That text is the
SWF author's placeholder, filled at runtime from `playerKrin<n>.playerName`.

The port cannot use those rows anyway. `scenes/battle/stance_row.tscn` already
rebuilds them as Godot nodes, one Label plus five Buttons, and
`battle_scene.gd` instances one per deployed companion. The rows are drawn with
`StyleBoxFlat` in five hand-picked colours because the real icons had never
been extracted. `_refresh_stance_row()`'s own comment says so: "like the
original's five icons".

So the bar needs the rows taken out, and the rows need the art put in.

## What the source holds

The bottom bar is DefineSprite 3317, `UI_BAR`, placed at depth 1 on both the
`KRINBATTLESCENE` and `Navigation` frames.

| depth | cid | what it is |
|---|---|---|
| 7 | 3312 | `subAI_BAR`, the member bar container |
| 6 | 3313 | panel art |
| 5 | 3288 | **clip mask**, `clipDepth="57"` |
| 3 | 3314 | **clip mask**, `clipDepth="4"` |
| 1 | 3316 | panel art |

3288 masks depths 5 through 57, which is what keeps the member bars inside the
left panel. Neither mask may ever go in `STRIPPED_CHARACTERS`; see the clip
mask rule in `CLAUDE.md`. Deleting 3312, the content rather than the mask, is
what this work does.

### The member bar

3312 holds two copies of DefineSprite 3311, named `p3` and `p5`, at local
(142.65, 12.60) and (142.65, 50.10). 3312 itself has frame labels `SHOW` (1)
and `HIDE` (6).

3311 is one member bar, 285.00 x 31.50 design px, with labels `active` (1) and
`inactive` (9). On the active frame it places:

| depth | cid | name | local x | local y |
|---|---|---|---|---|
| 1 | 3309 | | 0.00 | 0.00 |
| 2 | 3308 | | -134.50 | -3.15 |
| 25 | 3306 | `b1` | -7.20 | 2.15 |
| 36 | 3306 | `b2` | 24.80 | 2.15 |
| 3 | 3306 | `b3` | 56.80 | 2.15 |
| 14 | 3306 | `b4` | 88.80 | 2.15 |
| 47 | 3306 | `b5` | 120.80 | 2.15 |

The five buttons sit on a 32.00 px pitch. 3309 is the dark rounded backing.
3308 is a DefineEditText, `initialText` "Thurman McPown", `variableName`
`nameText`, `fontId` 3307 at `fontHeight` 120 twips. The `inactive` frame
replaces it at depth 2 with 3310, `"< Team Member Inactive >"` at
`fontHeight` 180.

### The stance button

3306 is one button and places three things, all at (0.20, 0.25):

| depth | cid | name | what it is |
|---|---|---|---|
| 1 | 3305 | `PIC` | the stance icon |
| 7 | 3293 | `COVER` | the dim or glow overlay |
| 10 | 3289 | | the DefineButton2 hit area |

3305 carries one labelled frame per stance, and the labels are
`_root.agModeNames` verbatim:

```
Phalanx 1   Defensive 10   Tactical 20   Aggressive 30   Relentless 40
```

Each icon is 28.25 x 13.75 design px and carries its own thin dark outline, so
no border has to be rebuilt in Godot.

3293 has two labelled frames, `BLACK` (1) and `WHITE` (11). `BLACK` is a dim
wash 27.75 x 13.25, sitting just inside the icon. `WHITE` is a soft glow
33.25 x 18.50 that spills outside it. Neither has more than 2.5% fully opaque
pixels; they are overlays, not replacements.

### How the original drives it

`b<i>`'s own `onClipEvent(load)` picks its icon:

```actionscript
pN = 2;
PIC.gotoAndStop(_root.agModeNames[pN]);
```

Each `p3`/`p5` placement carries `setAG`, which binds a bar to a party slot:

```actionscript
function setAG(num)
{
   pN = num;
   nameText = _root["playerKrin" + pN].playerName;
   i = 1;
   while(i < 6)
   {
      this["b" + i].COVER.gotoAndStop("BLACK");
      i++;
   }
   if(_root["playerKrin" + pN].agMode >= 0)
   {
      this["b" + (_root["playerKrin" + pN].agMode + 1)].COVER.gotoAndStop("WHITE");
   }
}
```

So selection is one `WHITE` cover among five `BLACK` ones, and the name is a
runtime string. Pressing a button (`DefineButton2_3289`) writes `agMode` and
then five tuning values out of `agModeAr1` through `agModeAr5`, which is what
`Party.apply_aggression_mode()` already reimplements.

`frame_217`'s `enterFrame` handler decides when the bar is visible:

- `SHOW` only while the player's own team is the one to move, `HIDE` otherwise.
- On team 1 the bars bind to slots 3 and 5. On team 2 they bind to 4 and 6 and
  the container shifts from `save_x1` to `save_x2`. This port only ever plays
  team 1, so slots 3 and 5, which is what `_populate_stance_rows()` iterates.
- Each bar goes `active` or `inactive` on `playerKrin<n>.active`.

## What the port does today

`_populate_stance_rows()` walks slots 3 and 5, skips a slot whose unit is
missing, instances a `StanceRow`, and stacks rows 46 px apart.
`_refresh_stance_row()` builds a `StyleBoxFlat` per button, tinting green
through red and giving the selected one a white border.

Three differences from the source, all of them small:

- The buttons are flat colours rather than the five icons.
- The row pitch is 46 px and the button pitch is 40 px against the source's
  37.50 and 32.00.
- A missing companion drops the row entirely, where the original keeps the bar
  and shows `"< Team Member Inactive >"`.

## Design

### Extraction

`battle_screen.py` gains the member bar pieces and loses the baked-in rows.

- `bottom_bar.png` renders 3317 from a copy of the SWF with 3312 deleted, the
  same `-removeCharacter` approach the halls already use for the fighter rig.
  Measured: the bare render crops to 3091 x 445 against the current 3092 x 445,
  so the recorded rect barely moves.
- `assets/ui/battle/stance/<Label>.png`, five files, from 3305 at its own
  labelled frames. Labels keep the SWF's spelling, which is also
  `agModeNames` and also the port's `Party.AggressionStance` order.
- `assets/ui/battle/stance/cover_black.png` and `cover_white.png` from 3293 at
  its two labels.
- `assets/ui/battle/member_bar_panel.png` from 3309, the row backing.

Zoom stays 4.0, matching the rest of the file. Every output crops to its alpha
bbox and raises on an empty render, the same as the existing renders.

`battle_layout.json` gains the rects these need, recorded the same way as the
chrome: the member bar's own rect, the button pitch, and the name field's
offset. The Godot side should read positions from there rather than carry a
second copy of the numbers.

### Godot

`stance_row.tscn` keeps its shape, a Label on the left and five buttons on the
right, and gains the art:

- Each button becomes a `TextureButton` (or keeps `Button` with a texture
  stylebox, whichever reads cleaner against the existing theme) showing its
  stance icon, at the source's 32.00 px pitch.
- Selection swaps the cover texture between `cover_black` and `cover_white`
  rather than recolouring a border, matching `setAG`. That replaces the colour
  table in `_refresh_stance_row()`.
- The row sits on `member_bar_panel.png` and rows stack 37.50 px apart.

The name stays a Godot Label. Nothing is gained by rendering text through the
SWF font, and the string is a runtime value in the original too.

### Why the bar is rebuilt rather than extracted

The member bar is one static backing, one runtime string, and five buttons
whose only states are which icon and which of two overlays. Reproducing it as a
texture would mean rendering 3311 once per name, which is not possible, or
compositing per stance per selection state, which is twenty renders that still
would not carry the name. The parts are small and the composition is trivial in
Godot, so the port takes the art and rebuilds the arrangement. That is the
general rule this case is an instance of, recorded in `CLAUDE.md`.

## Verification

- Every label of 3305 and 3293 produces a non-empty PNG, asserted in the script
  rather than checked once by hand.
- The bare `bottom_bar.png` contains no text. The current file fails this and
  the new one passes, so the check is a real regression test.
- `w * 4 == PNG width` holds for every new rect in `battle_layout.json`, the
  same invariant the halls and skies are checked against.
- A GUT test asserts each of the five stance textures resolves and that a
  `StanceRow` shows the selected cover on exactly one button.
- The existing battle tests keep passing.

## Out of scope

- The `SHOW`/`HIDE` visibility rule. The port shows the rows for the whole
  battle. Making them appear only during the player's decision window is a
  behaviour change worth its own decision.
- The `inactive` bar state. Worth doing, but it needs a call on whether a dead
  or absent companion should hold its row.
- Team 2 binding to slots 4 and 6. The port never plays team 2.
- The six `p1BAR` to `p6BAR` fighter bars in the top panel, still unbuilt and
  already scoped out in `KNOWN_GAPS.md`.

## Open questions

- Whether the buttons become `TextureButton` or keep `Button` with a texture
  stylebox. The second keeps the existing hover and focus handling; the first
  is less code. Decide against the theme when implementing.
- Whether to extract 3309 at all, or draw the backing with a `StyleBoxFlat`. It
  is a plain dark rounded rectangle. Extracting it is nearly free and keeps the
  art source-true, which is why this spec proposes it, but it is the one output
  here that a Godot primitive could match closely.
