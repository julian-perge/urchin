# Victory screen on containers (prototype for #108)

PROTOTYPE, throwaway. It lives on the branch `prototype/victory-containers` and is never merged.

**Question** (#108): can the victory screen be rebuilt on native containers whose separation, margins and minimum sizes come from the SWF, and still land where the original draws KRINMENU's (DefineSprite 3142) `win` frame? What can't containers express?

## Run it

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/battle/victory_screen_prototype.tscn
```

Left and Right (or the yellow bar's arrows) cycle the variants. O cycles the ffdec render over the screen: off, 50%, a difference view. M cycles the mode: `live` is a real-looking win, `ref` shows the SWF's own placeholder strings and empty slots, which is what ffdec draws, `chrome` hides all text, and `panels` shows only the backdrop and panels. Every switch prints each piece's rect against its SWF rect. The other arguments are listed at the top of `scripts/battle/victory_screen_prototype.gd`.

- **A** is `scenes/battle/victory_screen.tscn` as it is.
- **B** places the backdrop and the four panels as PanelContainers at their `win` frame rects, with StyleBoxFlats built from the shape records and content margins from the SWF. Inside are VBox and HBox columns, 5- and 6-column GridContainers, and slots. Every separation and minimum size is rounded to a whole pixel before a box gets it. The content margins stay floats, as StyleBox content margins are.
- **C** is the same tree with the extracted panel art in zero-margin StyleBoxTextures, and `FloatBox`, a small container in the script that places children at float positions, where B rounds.

Both B and C draw the backdrop and the experience rows from extracted art. Shape 3001 is an outline plus the XP bar's black frame, not a panel, and the backdrop is a radial gradient. The slots are `scenes/ui/item_slot.tscn` and the text is the port's font in every variant.

## Numbers

Rects, printed by the prototype in `live` mode. "Layout" is `get_global_rect()`, and "drawn" adds up each ancestor's offset rounded the way Godot snaps it (item 1 below):

| | Largest panel offset, layout / drawn | Largest other piece, layout / drawn |
|---|---|---|
| A | 54.50 / 54.10 px, left panel | 100.69 px, the third row's face |
| B | 0.60 / 1.10 px, money bar | 1.15 / 1.50 px, third row |
| C | 0.00 / 0.50 px, right panel | 0.00 / 1.35 px, inventory grid |

Pixels, from `compare.py`: p50 / p90 / p99 of the largest channel difference against the ffdec render, counted where the screen draws and the render is opaque, faces left out:

| | ref | chrome | panels | live |
|---|---|---|---|---|
| A | 4 / 64 / 196 | 4 / 42 / 149 | 2 / 27 / 105 | 4 / 64 / 195 |
| B | 4 / 28 / 185 | 3 / 14 / 56 | 2 / 4 / 37 | 4 / 31 / 187 |
| C | 4 / 22 / 181 | 3 / 11 / 53 | 2 / 4 / 21 | 4 / 26 / 186 |
| floor | 1 / 3 / 6 | 1 / 3 / 6 | 1 / 2 / 4 | |

`chrome` is the layout score. Text dominates p99 in `ref` and `live`, and `live` also carries data the render can't have. The floor is what the screenshots' 8-bit linear encoding alone costs (see Caveats). Per panel region, every capture and the diff images are in `scores.json` and `images/diff/`.

**The check can fail.** Moving B's left panel 20 px (`--shift=left:20`) takes `chrome` from 3 / 14 / 56 to 4 / 27 / 95, and the left region from 2 / 31 / 63 to 3 / 55 / 145. `compare.py --prove-fail` asserts it.

Rows in the 2x framebuffer (`--dump`), in window pixels, where each row's outline and the first inventory slot start:

| | SWF | ffdec | B | C | C, snapping off |
|---|---|---|---|---|---|
| player row | 262.1 | 262 | 261 | 261 | 262 |
| second row | 447.1 | 447 | 445 | 445 | 447 |
| third row | 632.1 | 632 | 629 | 631 | 632 |
| inventory slot 0 | 225.3 | 225 | 228 | 228 | 225 |

## What containers couldn't express

1. **A fraction on screen.** Godot draws each Control at its offset from its parent rounded to a whole design pixel, once for `gui/common/snap_controls_to_pixels` (`control.cpp:760-761` at 4.7.2-stable) and again for `rendering/2d/snap/snap_2d_transforms_to_pixel` (`renderer_canvas_cull.cpp:361-364`), which urchin turns on. Under the 2x stretch that is two window pixels, which settles the container note's open question in 3.6. So FloatBox keeps fractions in layout only, and every nesting level rounds again. Cost: the inventory grid sits three Controls deep and is drawn at y 114 against 112.65 in both B and C. With both snaps turned off at run time, C lands on ffdec's rows exactly and `chrome` drops from 3 / 11 / 53 to 2 / 6 / 40. Text at 800x600 looked no softer (`C_ref_nosnap` scores 3 / 14 / 183), but nothing else in the game was checked with snapping off.
2. **Whole-pixel boxes.** BoxContainer takes a whole-pixel separation, rounds each child's minimum size up and truncates its own size. Cost in B, which rounds first: the 92.50 row pitch becomes 83 + 9, so the rows drift 0.05, 0.45 and 0.95 px down the column in layout, and in the 2x framebuffer B's third row is drawn 1.5 px off where C's is 0.5. The rows are 196 wide against 196.80, and two panels grow when their rounded children no longer fit, the right panel 0.45 px taller and the money bar 0.60 px wider. Handing the box the raw floats (`--b-ceil`) is worse: the left panel grows 1.85 px, the centre 2.89 px, the bar 1.60 px, and Proceed lands 2.75 px low. Against FloatBox with shadowless panels too (`C_chrome_plainart`), rounding costs `chrome` p90 14 against 13, and 31 against 28 in the left panel.
3. **The panels' inner shadow.** Every panel placement carries an inner DropShadow, 45 degrees, blur and distance 5. StyleBoxFlat only draws an outer shadow. Cost: `panels` p99 37 for B against 21 for C. C with the same texture minus the filter scores 38, so the whole gap is the shadow, not flat against texture. C's texture stretches its 5 px shadow with the panel, to 4.5 by 6.1 px on the left panel, where ffdec keeps 5 px, and the left panel still scores p99 14 against B's 39.
4. **Gradient fills.** The backdrop 2993 is a radial gradient and StyleBoxFlat has no gradients, so B draws it from the texture too. A flat fill of its mean colour (`--flat-backdrop`) takes `panels` from 2 / 4 / 37 to 4 / 61 / 93. The slot art, the XP bar's gloss 2998 and the delete button 2859 are linear gradients, drawn from art in every variant.
5. **Overlap.** vb1's field runs 14 px into the drop grid, vb2's into the money row, the money row 1.45 px into the exp row, vb7's into Proceed, "No Items Found" sits on the grid and the percent sits on the XP bar. Box children can't overlap, so every column child is a plain Control slot as tall as the pitch to the next one, with its pieces at their SWF offsets. Cost: no pixels, because the slots carry the SWF numbers, but no column sizes itself from its content.
6. **A Label is as tall as its font.** A 12 px Label is 23 px with the 2 px gutter, against the field's 19.05, and the money row's pitch is 17.60. I'd expect labels as direct box children to push everything under them down, which is the other reason each sits in a slot. That part wasn't built.
7. **One separation per box.** The centre column's seven pitches all differ (40.75, 113.65, 42.40, 17.60, 22.40, 36.45, 30.86), so its box has separation 0 and each slot carries its own height. No cost beyond item 2.

## Caveats

- The godot-mcp screenshots hold linear values, because urchin sets `rendering/viewport/hdr_2d` and the harness writes the viewport's linear texture to an 8-bit PNG as is. #373737 comes back as 9. `compare.py` converts them back, and the darks lose precision on the way, which is the floor row above. `images/view/` holds the converted copies to look at.
- ffdec draws each row's face sheet as an empty frame inside the win frame's filtered row placement, while the row clip rendered on its own shows the face (`images/art/diag_row_alone.png`). That a filter over a clip mask causes it is a guess. The faces are left out of every mask.
- The render is pasted onto whole 2x pixels, 0.075 and 0.2 design px from its exact rect (`art.json`).
- `item_slot.tscn` draws `assets/ui/menu/slot.png`, not 2983 with its inner shadow. It costs every variant the same.

## Files and how they were made

Run from the repo root, in this order. `render_art.py` runs ffdec, so nothing else may be rendering.

```sh
uv run python dev/prototypes/victory_containers/win_layout.py   # SWF -> win_layout.json
uv run python dev/prototypes/victory_containers/render_art.py   # ffdec -> images/ref, images/art, art.json
# captures with the godot MCP, run_scene embedded, capture_screenshot -> images/shots/<variant>_<mode>.png
#   --clean for each mode, --sentinel --mode=ref for <variant>_sentinel.png, and the extra flags above
uv run python dev/prototypes/victory_containers/compare.py --prove-fail   # -> scores.json, images/diff, images/view
```

- `win_layout.json`: every piece's stage rect, the shape styles and filters, the text formats, and each panel's column spec, from `swf_index.py` and `timeline.py`.
- `images/ref/`: the `win` frame through `render.frames()` at 2x and Lanczos-shrunk to 1x, whole (`full`), with every edit text stripped (`chrome`), and with everything but the backdrop and panels stripped (`panels`).
- `images/art/`: the pieces B and C draw, with their rects in `art.json`.
- `images/shots/`: the godot-mcp captures, linear. `<variant>_sentinel.png` is the same screen over magenta, and the pixels that match the capture over the hall are the mask.
- `images/framebuffer/`: 2x framebuffer dumps for the row table.
