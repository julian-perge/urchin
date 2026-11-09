# Texture filter facts for ticket 130

Gathered 2026-11-09, before the wayfinder run. Facts only, no decision, and the ticket is not claimed. Scripts, captures and crop sheets are in ~/tmp/2026-11-09-urchin-filter.

Every capture is a real framebuffer from an embedded run of main at 47cabebb, with both snaps off from the project settings, hdr_2d off, `--fixed-fps 30` and a seeded battle. Two runs of the same battle differ in 0 of 1,920,000 pixels. A LINEAR capture from the clone with mipmaps imported differs from the normal project in 0 of 1,920,000 pixels, so importing mipmaps does not change LINEAR by itself.

The font is today's emboldened Open Sans unless the row says Heros. Heros is the uncommitted theme and OTFs from the issue 127 session, copied at about 16:40, into a clone of main.

## Tools

- `snapdriver.gd`, `ab_report.py` and `montage.py` all run on today's main. Pass `--snap=project` to `snapdriver.gd`, because its default `on` turns both snaps back on.
- Launch line: `Godot -d --path . --embedded --fixed-fps 30 --quit-after 400 --resolution 1600x1200 -s <driver> -- --snap=project --filter=linear --out=<prefix> --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120`, through the slot script. `--resolution` sets the window size, and the "Embedded window can't be resized" line in the log is harmless.
- Scratch copies: `filterdriver.gd` is `snapdriver.gd` plus `--filter=nearest|linear|mip`, `--scan` and `--mode=halls`. `clone_mip` has all 3,003 texture sidecars set to `mipmaps/generate=true` and imported. `clone_proto` is main plus the victory prototype's scene and art. `clone_font` is main plus Heros.

## The reference

- `compare.py`'s `load_rgb` double-converts new captures. C_chrome at 2x reads p50/p90/p99 71/73/87 through it and 0/1/18 loaded as is. Load captures directly and drop the `floor_*` rows, which only measured the old linear round trip.
- `render_art.py` runs unchanged on today's main with the pinned ffdec. All 23 art files and `win_panels` are byte-identical to the ones on the prototype branch.
- `win_chrome` and `win_full` differ from the branch only around the three faces (x 58.5 to 110, y 142 to 209.5 and the same box 92.5 and 185 px lower). Today's render draws the faces where the committed one shows an empty frame, so the prototype's caveat about empty faces no longer holds. 5,718 of the 37,329 changed pixels at 2x are the faces' shadow, outside the rects `compare.py` leaves out. That `ClipPlacedTimeline` is what fixed the faces is inferred from the commit's description, not isolated.
- New baselines, today's main, NEAREST, snaps off, 2x framebuffer Lanczos-shrunk to 800x600 as the prototype did: C_chrome 0/2/17, C_ref 0/8/176, C_panels 0/0/6, B_chrome 0/8/42. The README's numbers carried the linear round trip, so they do not compare directly.
- The check can fail: C_chrome at 2x moved 1 window px scores 0/6/55 against 0/1/18.
- The prototype loads its art with `Image.load_from_file`, so it skips the importer's `fix_alpha_border`. Transparent edges in it behave differently under LINEAR from the imported art the game draws.

### The win frame barely tests this question

Its art is rendered at zoom 2 (the faces and a few small pieces at 4), so at a 2x window each piece maps about 1:1 and the filter only acts on fractions and stretch. p50/p90/p99 against the committed refs, common mask, text included only in `ref`:

| Capture | 2x NEAREST | 2x LINEAR | 1x NEAREST | 1x LINEAR |
|---|---|---|---|---|
| C_chrome | 0/1/18 | 0/3/21 | 0/6/29 | 0/6/27 |
| C_panels | 0/0/6 | 0/0/10 | 0/1/14 | 0/1/11 |
| C_ref | 0/8/200 | 0/9/191 | 0/16/179 | 0/13/165 |
| B_chrome | 0/6/49 | 0/7/49 | 0/10/48 | 0/9/47 |
| B_panels | 0/0/38 | 0/0/40 | 0/1/39 | 0/1/39 |

The 1x refs are Lanczos shrinks of the 2x render, so the 1x columns also carry that shrink.

## The test that does exercise 4x art: halls against ffdec

All 12 hall and sky pairs the battles use, drawn at their SWF rects from the imported PNGs, against ffdec at the window's own zoom through `verify_battle_screen.py`'s render path. Inside 333's box, on pixels the art covers opaquely. This is the SWF rect, not where the battle draws the hall today (see below).

Edge pixels only (ffdec gradient over 24), p50/p90/p99 and mean:

| Window | NEAREST | LINEAR | LINEAR + mipmaps | ffdec 4x box-shrunk to this zoom |
|---|---|---|---|---|
| 1x | 3/34/103, 12.65 | 3/26/76, 9.89 | 6/29/63, 11.65 | 1/21/61, 6.27 |
| 1.5x | 1/33/63, 10.02 | 2/28/50, 8.16 | 6/28/52, 10.64 | |
| 2x | 3/26/91, 9.39 | 2/21/44, 7.40 | 7/25/60, 10.31 | 1/16/32, 4.80 |
| 3x | 2/27/77, 10.13 | 4/16/54, 7.42 | 6/18/55, 8.99 | |
| 4x | 2/23/73, 8.28 | 5/20/73, 8.32 | 5/20/73, 8.32 | |

NEAREST moved 3 window px scores p99 158 at 1x, 184 at 2x and 179 at 4x, so the check can fail. The whole box instead of the edges is p99 and mean 11/0.58, 9/0.52, 13/0.71 at 1x and 3/0.24, 2/0.21, 6/0.32 at 2x, with a floor of 4/0.43 and 2/0.20. Those numbers are mostly flat fill.

## What the filter touches

- No node, scene or script sets `texture_filter`. There is no SubViewport. The one project setting decides every pixel.
- All 3,003 textures import with `mipmaps/generate=false`, lossless, no size limit.
- CLAUDE.md's "export at 4x or 5x" holds only for part of the art. Export zooms in the extractors: halls, skies, hub art, battle chrome and store art 4; orbs, faces and class cards 5; dolls, VFX, item icons, buff icons, ability icons and the start screen backgrounds 2.
- `scenes/battle_scene.tscn` draws the hall with full-rect anchors and `stretch_mode = 6`, so JAIL is 1.417x its SWF rect (scale 0.3542 against 0.25). Issue 67's hall framing will change it. The sky is at its SWF rect.

Texels per window px at a 2x window, p50 and range across the visible nodes. A 1x window doubles every value.

| Family | Texels per window px | Rotated | Notes |
|---|---|---|---|
| Hub art, sky, stance row | 2.00 | no | |
| Battle chrome (`assets/ui/battle`) | 2.00 (0.42 to 9.09) | no | |
| Hall as drawn today | 1.41 | no | 2.00 at its SWF rect |
| Dolls (`resources/sprites`) | 1.00 (0.84 to 1.26) | 53 of 62 parts | all at fractional origins |
| Item icons | 1.02 | no | all at fractional origins |
| Menu art (`assets/ui/menu`) | 1.00 | no | fractional origins in every Window, whole on the title |
| Ability icons | 1.11 (0.50 to 1.11) | no | |
| Buff icon | 0.84 | no | |
| Store backdrop | 1.65 | no | |
| Toolbar icons | 2.67 by 2.95 (0.50 to 3.36) | no | |
| Hotbar | 3.04 by 1.47 (up to 8.11) | no | stretched unevenly |
| Portraits | 2.57 by 3.50 | no | |
| Orbs | 4.59 (2.69 to 4.59) | all 9 | |

Share of pixels each change moves:

| Screen | NEAREST vs LINEAR, 2x | 1x | LINEAR vs mipmaps, 2x | 1x |
|---|---|---|---|---|
| Battle 109 | 6.66% | 6.66% | 15.39% | 27.87% |
| Hub | 16.51% | 9.84% | 50.35% | 64.84% |
| Inventory | 6.42% | 7.77% | 11.32% | 22.01% |
| Store | 7.96% | 8.73% | 15.10% | 27.89% |
| Abilities | 6.98% | 7.97% | 12.42% | 21.79% |
| Title | 3.13% | 11.38% | 0.00% | 10.73% |

What the crops show (`sheets/*.png`, each NEAREST, LINEAR and LINEAR with mipmaps, the 2x window over the 1x window):

- **Hall, 2x:** NEAREST shows stairs on the roof line and the lamps. LINEAR removes them and mipmaps look the same as LINEAR. **1x:** LINEAR softens the stairs and mipmaps smooth them.
- **Dolls, 2x:** NEAREST leaves jagged gun, blade and armour outlines even at about 1:1, because the parts are rotated. LINEAR is smooth and mipmaps match it. **1x:** NEAREST breaks thin lines, LINEAR is better, and mipmaps are the cleanest and the blurriest.
- **Item icons, 2x:** NEAREST is crisp and LINEAR slightly soft. **1x:** NEAREST drops detail, LINEAR keeps more, and mipmaps blur and dim fine lines.
- **Hotbar and portraits, 2x:** LINEAR helps a little and mipmaps most. **1x:** NEAREST and LINEAR both break the head icon, and mipmaps stay whole but go greyer.
- **Text, 2x:** LINEAR is slightly softer. **1x:** visibly softer on lines at fractional positions. Mipmaps change 0 pixels of the Store's dialogue text at either window size, and all five font imports have `generate_mipmaps=false`.

## Text numbers

12 and 16 px text at 8 fractional offsets, root filter flipped, snaps off. Mid is the share of inked pixels that are mid-grey and edge is gradient energy per unit of ink, both means over the 8 offsets. At 1x and 1.5x only offset 0.0 lands on a whole window px, and at 2x offsets 0.0 and 0.5 do.

| Font | Window | Size | NEAREST mid, edge | LINEAR mid, edge | Offsets on whole window px, NEAREST / LINEAR mid |
|---|---|---|---|---|---|
| Open Sans | 1x | 12 | 0.442, 1.028 | 0.627, 0.918 | 0.442 / 0.442 |
| Open Sans | 1x | 16 | 0.373, 0.794 | 0.519, 0.751 | 0.375 / 0.375 |
| Open Sans | 1.5x | 12 | 0.332, 0.714 | 0.494, 0.685 | 0.332 / 0.511 |
| Open Sans | 2x | 12 | 0.266, 0.555 | 0.403, 0.541 | 0.266 / 0.360 |
| Open Sans | 2x | 16 | 0.216, 0.419 | 0.327, 0.412 | 0.216 / 0.277 |
| Heros | 1x | 12 | 0.563, 1.418 | 0.796, 1.150 | 0.564 / 0.564 |
| Heros | 1x | 16 | 0.435, 1.137 | 0.640, 1.032 | 0.436 / 0.436 |
| Heros | 1.5x | 12 | 0.414, 1.021 | 0.618, 0.962 | 0.414 / 0.597 |
| Heros | 2x | 12 | 0.333, 0.783 | 0.506, 0.767 | 0.333 / 0.429 |
| Heros | 2x | 16 | 0.243, 0.593 | 0.407, 0.587 | 0.243 / 0.338 |

The ticket's "0.36 to 0.42 at 2x" compares LINEAR with itself, whole window px against the other offsets. NEAREST at 2x is 0.27. Its "0.44 to 0.73 at 1x" is NEAREST against LINEAR at the fractional offsets, and my mean over all 8 offsets is 0.627. LINEAR still adds softness at whole window px at 2x and 1.5x. The likely reason is Godot's subpixel glyph positioning, which is a guess I did not isolate.

## What a LINEAR answer would reopen

- **Ticket 128:** yes for text. The premise that text stays crisp with snapping off holds only under NEAREST, as the table above shows, and CLAUDE.md says so. Turning snapping back on would be the wrong fix, because the fractions are what ticket 128 decided to keep.
- **Ticket 115:** no. The shader on a StyleBoxFlat and the custom StyleBox have no texture, so their numbers do not move: panel rects at 2x p99 3 under both filters, shadow band against real Flash p99 6 under both, and the 1x frame moves from 12 to 13. The backdrop is the only texture in those variants, so it is the inferred source of that 1, not isolated.
- **Ticket 114:** no reorder. With snaps off, the 1x frame, 2x panel rects and band against Flash read 30/43/50 for `flat` under both filters. `plainart` goes from 33/44/50 to 35/40/50 and `baked` from 7/6/12 to 12/6/13.

## Costs

- **LINEAR for everything:** one line in `project.godot`. `M_SCHEST_ONE.png` and `M_SARM_ONE.png` are the two imported textures with `fix_alpha_border=false` and transparent edge texels, 153 and 50 of them pure black. A dark fringe on those two under LINEAR is expected and I did not look for it.
- **Mipmaps on top:** all 3,003 sidecars change and `.godot/imported` goes from 106 MB to 133 MB. On the halls they beat LINEAR only on p99 at 1x, 63 against 76, with a worse mean.
- **A mixed answer:** `texture_filter` is a CanvasItem property, so the Theme cannot carry it. There are 101 Label and RichTextLabel nodes in scenes plus 5 `Label.new()` calls, 83 TextureRect nodes, and the doll parts are created at `scripts/entities/character_visual.gd:461`. The filter inherits from the parent, so one node can cover a whole art subtree, but the unit overlay's names sit under `Battlefield` with the dolls.

## Not checked

- The hub, dolls, icons and hotbar have no ffdec comparison, only the crops.
- Text against real Flash. The fonts differ, and there is no metric yet that compares them fairly.
- The floor column for 1.5x and 3x.
- Cutscenes and VFX in motion.
- 800x575, which ticket 111 has not landed. The scale stays 2x at a 1600x1150 window.
