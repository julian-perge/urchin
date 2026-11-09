# Texture filter variants on the real game (prototype for #130)

PROTOTYPE, throwaway. It lives on the branch `prototype/texture-filter` and is never merged.

**Question** (#130): should the port keep NEAREST as its default texture filter, or draw scaled art with LINEAR?

**Answer:** C, LINEAR for art and NEAREST for text, with no mipmaps.

## Run it

Run `--import` once after checking the branch out, because every texture on it is imported with mipmaps so variant D can work.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .
/Applications/Godot.app/Contents/MacOS/Godot --path .
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/battle_scene.tscn -- --battle=109
```

`filter_switcher.gd` is an autoload that puts a yellow bar over the real game. Left and Right or 1 to 4 pick a variant, W cycles the window through 1x, 1.5x, 2x and 3x in framebuffer pixels, and H hides the bar.

| Variant | Art | Text |
|---|---|---|
| A | NEAREST (today) | NEAREST |
| B | LINEAR | LINEAR |
| C | LINEAR | NEAREST |
| D | LINEAR with mipmaps | NEAREST |

## Numbers

All from real framebuffers of main at 47cabebb in embedded runs, with both snaps off and hdr_2d off. Two runs of the same battle differ in 0 of 1,920,000 pixels.

The variants draw what they claim. A and B match captures made with the project filter flipped directly, and without mipmaps imported, in 0 of 1,920,000 pixels. C differs from B only around the text, and the Store's dialogue under C matches A in 0 of 76,800 pixels at 2x.

### Halls against ffdec

All 12 hall and sky pairs the battles use, drawn at their SWF rects from the imported PNGs, against ffdec at the window's own zoom. Inside 333's box, on pixels the art covers opaquely, edge pixels only (ffdec gradient over 24). p50/p90/p99 and mean.

| Window | NEAREST | LINEAR | LINEAR + mipmaps | ffdec 4x box-shrunk to this zoom |
|---|---|---|---|---|
| 1x | 3/34/103, 12.65 | 3/26/76, 9.89 | 6/29/63, 11.65 | 1/21/61, 6.27 |
| 1.5x | 1/33/63, 10.02 | 2/28/50, 8.16 | 6/28/52, 10.64 | |
| 2x | 3/26/91, 9.39 | 2/21/44, 7.40 | 7/25/60, 10.31 | 1/16/32, 4.80 |
| 3x | 2/27/77, 10.13 | 4/16/54, 7.42 | 6/18/55, 8.99 | |
| 4x | 2/23/73, 8.28 | 5/20/73, 8.32 | 5/20/73, 8.32 | |

NEAREST moved 3 window px scores p99 158 at 1x, 184 at 2x and 179 at 4x, so the check can fail.

### Text

12 px text at 8 fractional offsets, mean share of inked pixels that are mid-grey. Lower is crisper. Open Sans is today's emboldened `_sans`. Heros is the uncommitted theme and OTFs from the issue 127 session.

| Font | Window | NEAREST | LINEAR |
|---|---|---|---|
| Open Sans | 1x | 0.442 | 0.627 |
| Open Sans | 2x | 0.266 | 0.403 |
| Heros | 1x | 0.563 | 0.796 |
| Heros | 2x | 0.333 | 0.506 |

### The win frame barely separates them

Its art is rendered at zoom 2, so at a 2x window each piece is about 1:1. Variant C of the victory prototype, chrome mode, p99 against ffdec: NEAREST 18 and LINEAR 21 at 2x, 29 and 27 at 1x.

`evidence/facts.md` has the rest: what each family's texel ratio is, how much of each screen each filter moves, what it would reopen on the other tickets, and what wasn't checked.

## Files

The scripts read and write under `~/tmp/2026-11-09-urchin-filter`.

- `filter_switcher.gd`: the bar and the four variants.
- `evidence/scripts/filterdriver.gd`: the capture driver, a copy of the pixel snapping ticket's `snapdriver.gd` with a filter option, a texture scan and a hall mode.
- `evidence/scripts/run_*.sh`: every capture, through the slot script.
- `evidence/scripts/hall_refs*.py` and `hall_score*.py`: ffdec references and hall scores. `text_score.py`, `vic_score.py` and `verify_variants.py` score text, the win frame and the variants.
- `evidence/images/variants_2x.png` and `variants_1x.png`: A to D side by side. `evidence/images/sheets/`: NEAREST, LINEAR and mipmaps by feature.
