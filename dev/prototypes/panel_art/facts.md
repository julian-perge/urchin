# Panel art facts for "Should panels draw as StyleBoxFlats built from the SWF shapes, or as the extracted textures?" (ticket 114, 2026-11-09)

Facts only, gathered before the grilling. No decision and the ticket is not claimed. Scratch, scripts, captures and scores: ~/tmp/2026-11-09-panel-art (shape_records.py, walk_panels.py, labels.json, driver.gd, score.py, agree.py, stroke_tab.py). Comparison images: panel-art-2x-window.png and panel-art-big-capture.png, beside this file.

## The ticket's numbers, rechecked on today's main

Today's main is LINEAR by default, no [rendering] section at all, `gui/common/snap_controls_to_pixels=false`, stretch canvas_items. The inner shadow prototype's harness (`main.gd`, unchanged) run in a throwaway project with exactly those settings (`today/`), no `--no-snap` flag and no filter override, gives:

| Variant | 1x frame p99 vs ffdec | 2x Panel rects p99 vs ffdec | Shadow band p99 vs real Flash |
|---|---|---|---|
| StyleBoxFlat, no shadow | 30 | 43 | 50 |
| extracted art, no shadow | 35 | 40 | 50 |
| baked art | 12 | 6 | 13 |
| shader on StyleBoxFlat (the 115 decision) | 13 | 3 | 6 |
| shader on the extracted art | 12 | 3 | 6 |

All 7 variants run are pixel-identical to the texture-filter session's captures (`cmp` on the PNGs), so what the ticket says still holds: 30 / 43 / 50, 35 / 40 / 50, 12 / 6 / 13, and with the shader the two tie. Per-panel shadow band against real Flash, p99: shader on flat 3 / 2 / 6 / 7 (left, centre, right, bar), shader on art 3 / 2 / 6 / 14.

The three port PNGs are hand exports, and they are byte-identical to a fresh ffdec zoom 2 render of sprites 2990, 2992 and 2988 (`panel_large.png`, `panel_bar.png`, `panel_center.png`, 0 pixels differ). So "the extracted art" and today's assets are the same pixels.

## The stroke: the ticket's remaining worry

The comment on the ticket compares a whole-pixel StyleBoxFlat against "the SWF's 2.6 px on Options". The 2.6 is the panel's x scale, and neither Flash nor ffdec strokes per axis.

- Flash and ffdec draw one stroke width per shape: width * sqrt((sx^2 + sy^2) / 2). ffdec: `BitmapExporter.java:221` (`thicknessScale = p00.distanceTo(p11) / Math.sqrt(2)`). Measured, Options and Achievements (2.614 x 1.123, mean scale 2.012): real Flash at the capture's x 5.14, y 4.62 stretch draws 10.0 device px on the sides and 10.0 on top and bottom. The per-axis model predicts 13.4 and 5.2. ffdec at zoom 2: 2.01 design px, 1.99 design px.
- Flash also snaps the stroke to whole device pixels. In the real 2x victory capture and real 1x store capture every measured stroke is exactly 2 and 1 device px, sitting on whole pixels: 1.07 and 1.09 px strokes are 2 device px at 2x, and 0.87 and 0.91 px strokes are 1 device px at 1x.
- Corners: the SWF's line joins are round, but at a 2x window real Flash draws each outer corner as a square 2x2 black block, same as a sharp StyleBoxFlat (read at the four victory corners). The rounded join only shows at the big capture's stretch.

Per rect, mean-scale stroke (design px) and the border a StyleBoxFlat would use:

| Rect | Scale | Stroke | Border | Labels |
|---|---|---|---|---|
| 2989 (47.50, 86.60), (503.50, 81.60); 2991 (47.50, 358.20), (503.50, 358.20); 2987 (308.95, 82.15) | 1.000 x 1.000 | 1.000 | 1 | inventory, normal; the (503.50, ...) ones also win and shop |
| 2989 (36.12, 80.96) 222.70x327.24 | 0.894 x 1.225 | 1.072 | 1 | win, shop |
| 2987 (274.90, 82.15) 213.15x326.50 | 1.164 x 1.000 | 1.085 | 1 | win |
| 2989 (44.94, 73.43), (506.32, 73.43) 249.10x346.10 | 1.000 x 1.296 | 1.157 | 1 | skills |
| 2989 (135.77, 49.33), (415.77, 49.33) | 1.001 x 1.296 | 1.158 | 1 | data |
| 2987 (274.90, 81.83) 213.15x136.42 | 1.164 x 0.418 | 0.875 | 1 | shop |
| 2987 (274.90, 232.36) 213.15x175.50 | 1.164 x 0.537 | 0.907 | 1 | shop |
| 2987 (304.21, 74.15) 190.62x216.31 | 1.041 x 0.663 | 0.873 | 1 | skills |
| 2987 (304.21, 302.20) 190.62x116.56 | 1.041 x 0.357 | 0.778 | 1 | skills |
| 2989 (74.96, 82.41) 651.11x299.94 | 2.614 x 1.123 | 2.012 | 2 | options, ach |

So borders 1, 1, ..., 2 (one rect) reproduce Flash's stroke widths exactly at 1x and 2x windows. At 3x and 4x (computed from the formula, not measured), a few panels would be 1 device px off: 0.778 * 3 = 2.3 rounds to 2 where a 1 px border draws 3, and 1.157 * 4 = 4.6 rounds to 5 where a 1 px border draws 4.

A stretched texture does the opposite: the bare shape's 1 px stroke gets the panel's per-axis scale, 2.61 by 1.12 on Options and 1.04 by 0.36 on the Abilities centre bottom panel, against Flash's single width.

StyleBoxFlat itself (Godot 4.7.2 source, `style_box_flat.cpp`): border widths are `int` in the API (`set_border_width(Side, int)`, line 84, stored as `real_t` but only settable as whole numbers), and antialiasing is on only with rounded corners or skew (`aa_on`, line 474), so a sharp-cornered flat panel draws hard edges on device pixels. That matches Flash's snapped strokes. StyleBoxTexture is one stretched LINEAR quad with zero margins.

## Generalized across every label (with the 115 shader on every variant)

`flat_axis` is the ticket's flat: per-axis rounded borders at the bounds x matrix rect. `flat_mean` is one border width (the rounded mean scale) at the fill rect grown by half the border. `custom` is a StyleBox with the exact fractional stroke. `art2` and `art4` are the bare shapes rendered at zoom 2 and 4, stretched in a zero-margin StyleBoxTexture (art2 is today's PNGs). Lower is better. Ring = 2 design px outside to 4 inside each panel's outer edge. Numbers are p50 / p90 / p99 and mean of the largest channel difference.

| Reference | flat_axis | flat_mean | custom | art2 | art4 |
|---|---|---|---|---|---|
| ffdec zoom 2, 7 labels | 0/18/84 5.53 | 0/15/57 4.38 | 0/14/55 4.35 | 0/14/77 5.00 | 0/16/64 4.65 |
| real Flash, victory at 2x | 1/2/62 2.16 | 1/2/62 2.14 | 1/2/62 2.15 | 1/12/116 6.07 | 1/3/72 2.85 |
| real Flash, store at 1x | 1/4/140 5.01 | 1/4/143 6.42 | 1/4/140 5.16 | 1/26/140 9.18 | 1/6/140 6.49 |
| real Flash at x 5.14, y 4.62 stretch (inventory, skills, options, ach) | 1/39/122 9.81 | 1/24/85 6.14 | 1/22/76 5.77 | 1/40/123 11.61 | 1/36/126 10.05 |

On Options and Achievements against ffdec (the only rect where the rule matters): flat_axis 0/45/137 10.47, flat_mean 0/19/51 4.71, custom 0/19/51 4.71, art2 1/26/72 8.23, art4 0/29/137 10.40. A panel with border 2 left at the bounds x matrix rect scores 0/35/137 9.11, so the rect choice matters there (0.30 px on the sides and 0.44 px top and bottom; at most 0.23 px on every other rect, the bounds x matrix rect and the fill rect grown by half the stroke being the two candidates).

Stroke position, right and bottom edges only because they carry no shadow: a Godot variant's stroke counts as a match if it lands within half a device px of real Flash's (1 device px at the big capture's stretch). 36 edges total across the victory 2x, store 1x, Inventory, Abilities and Options captures, with the Abilities centre top panel's two edges excluded because something drawn over them makes the reading meaningless (20 device px "strokes"):

| | flat_mean | flat_axis | custom | art2 (today's PNGs) | art4 |
|---|---|---|---|---|---|
| Edges matching real Flash | 34 / 36 | 30 / 36 | 34 / 36 | 12 / 36 | 25 / 36 |

The two flat_mean misses are one device pixel each: the right tall panel's bottom edge at victory 2x (348.75 times 2 is an exact half, and Flash places that stroke one device row lower than Godot) and one store centre panel's bottom edge at 1x. flat_axis matches that store edge but misses on Abilities and both Options edges, so 30 / 36.

The visible difference at the game's 2x window is panel-art-2x-window.png: real Flash, both flat variants and art4 have crisp strokes, and art2 (today's PNGs) stretched and filtered LINEAR shows soft double edges.

Captures used: `references/2026_07_18_flashpoint/16_after_battle_victory...` (2x, 1600x1218 with a 64 px title bar), `zone1_itemshop_menu...` (1x, 798x603, aligned by search, title bar 27 px, dx -1), and the four `references/sonny2_*_screen.png` at 4112x2658. Those four are the Steam build (only SONNY2.swf holds "Gameplay Stats"), with the stage stretched to the whole window, x 5.14 and y 4.62. Their Options and Achievements panels show no inner shadow on that one panel while the Inventory and Abilities panels do; the cause is not established, so Options and Achievements only count for stroke, not for the shadow.

## Which panels are which (from the shape records, `shape_records.py`)

Walked every root menu frame, KRINMENU label, the hub frame, the battle frame, the tooltip and button states, skipping the art-only sprites (item, ability and buff icons, faces, shop scenes, hub art, the fighter rig and the world map art). Categories come from parsing the edge records and every fill and line style, not the first style array only.

**A. One solid fill on a plain rectangle, with or without one uniform stroke. A StyleBoxFlat carries these exactly.**

| Shape | Look | Where | Port today |
|---|---|---|---|
| 2989, 2991, 2987 (the three panels) | #373737, #404040, #1a1a1a, 1 px black | 27 label uses, 16 rects (table above), inner shadow decided by 115 | hand PNGs in TextureRects |
| 2713 name box | #000000 alpha 77, 1 px #cccccc, own placement has cyan outer Glow blur 17 | nameMenu | rebuilt |
| 68 | #000000 alpha 230 | tooltip body backer | rebuilt flat |
| 2847 | #000000 alpha 179 | hub info popup dim, top status bar backing | none |
| 333 | #000000 | number and face backings, element bar tracks, hall window 3455 | ColorRect, hand art, or none |
| 2868, 2865, 2866 | #111111, #cccccc, #ffcc55 | XP bar left box and fill | hand exp_*.png |
| 3119 | #1e1e1e | Abilities talent pool backing; also the hotbar squares, where the placement adds a Bevel and two Glows (not carried) | ColorRect; hotbar StyleBoxFlats without the bevel |
| 3411 | #0099cc | focus bar | none |
| 102 | #00ff66 | buff tile backing, recoloured at runtime | none |

**B. Outlines with no fill, also a StyleBoxFlat with draw_center off:** 2857 (2 px white, the slot hover highlight, hand `slot_highlight.png`), 3098 (1 px black, talent tree frame, none), 3415 (hall outline), 3476 (cutscene video frame), 4162 (world map frame). 2980 is three separate 1 px #333333 boxes inside the Inventory centre panel, none extracted.

**C. Not expressible as a StyleBoxFlat (gradient, multiple fills, non-rectangle geometry, or a filter on the placement).**

- Gradients and multiple fills: the backdrop 2993 (radial plus a solid black alpha 26 fill, 222 edges of scratch lines), the menu background 2701 + 306 + 2700 (`start_background.png`, script), slot 2982, delete 2859 and sell 3016 (linear plus a white alpha icon fill), XP gloss 2864 and 2998, the pool frame 3116, achievement plates 3139 and 3140 (with a Bevel on the parent), member bar backing 3309 (radial, script `member_bar_panel.png`), top panel 3463 (linear, Bevel, Glow, script `top_panel.png`, unused), bottom bar 3315 (three linear rectangles, Bevel, Glow, script `bottom_bar.png`, unused), speech frame 3364 and face 3362 (none), info popup 2845 and 2843 (none), zone progress 3148 and 3146, tooltip title backer 2714 (rebuilt flat today), cutscene backdrop 3475, world map faces.
- KRINMENU's own placement carries a Bevel, a 2 px black Glow and a DropShadow on the whole sprite. In the real 2x victory capture that shows as a band about 5 design px wide: R 202 (#ca6e6e) along the backdrop's top and left edges and R 16 (#100a0a) along its right and bottom, with the Glow and DropShadow outside it (read off rows and columns at mid-edge). No art in the port carries it, the ffdec references here render sprite 3142 alone and so don't either, and `menu_backdrop.png` is the shape with no filter. Whatever route the backdrop takes has to say whether that bevel comes with it.

Port status of the PNGs in A and C: hand exports (no script regenerates them) are `assets/ui/menu/` panel_large, panel_bar, panel_center, menu_backdrop, slot, slot_highlight, close_x, button_delete, button_sell, exp_track, exp_fill, exp_zero_box. Script-extracted and already on disk: `assets/ui/battle/` bottom_bar, top_panel, stage_rect, alert_icon, member_bar_panel.

## What the neighbouring decisions settle

- 115: the inner shadow is a shader on the 16 flat Panels through one shared ShaderMaterial, numbers typed once. It only darkens what the StyleBox draws, so it stays out of this ticket. Fill and stroke are this ticket.
- 130: art is LINEAR, text NEAREST, no mipmaps. A textured panel at a fractional rect is filtered, a StyleBoxFlat is geometry.
- 128: both snaps off, so a StyleBoxFlat at a fractional rect draws hard edges at the nearest device pixel (pixel-centre rule), which is what Flash's stroke snapping does at 1x and 2x.
- 110: panels are PanelContainers whose StyleBox content margins come from the SWF. Either StyleBox type carries content margins. PanelContainer takes margins only from the StyleBox, so per-panel margins mean per-panel StyleBox resources either way.
- 117: each Screen types its numbers into its own scene in Stage coordinates, and one GUT test checks them against a record an extractor writes from the SWF. Under the flat route that record has to carry each panel's fill, stroke width and fill rect, not only its rect, and the record can fail on any of them. Under the texture route the record is the rect plus the art's source shape and zoom.
- 111: 800x575 base resolution; panel coordinates are the same in either viewport since they are measured from the top left.
- CLAUDE.md "Conventions": "If it exists in the SWF, script it." The hand PNGs in A are the opposite of that, so keeping textures means writing their extractor.

## Options and what each costs

- **StyleBoxFlat on the 16 panels.** No PNGs. Three fills and two border widths (1 on 15 rects, 2 on the Options and Achievements rect), the rect being the fill rect grown by half the border. Deletes `panel_large.png`, `panel_bar.png`, `panel_center.png` once the scenes stop using them. No editor preview trouble. Fractional strokes aren't possible, which costs nothing at 1x and 2x.
- **Extracted art in a zero-margin StyleBoxTexture.** Keeps three PNGs (hand today, so an extractor is owed), and the stroke is stretched per axis. Filtered edges at every fractional rect under LINEAR. At zoom 4 the Options stroke is still wrong and the art only ties at 1:1.
- **A custom StyleBox with fractional strokes** (from ticket 115's comparison). Same pixels as the StyleBoxFlat at 1x and 2x in every capture, needs a script class plus `@tool` for the editor, and no measured gain.

## Not checked

- No real Flash capture of Options or Achievements at a normal window size, so nothing confirms the inner shadow or stroke there at 1x or 2x directly; ffdec draws both.
- 3x and 4x window scales (the stroke arithmetic above is computed).
- A real game scene with any of this; the harness draws only the backdrop and panels.
- Fringe artifacts on the art variant's transparent rim under LINEAR (the harness loads art without the importer's fix_alpha_border).
- Text over panels. None of these panels' fills or strokes interact with text.

## Follow-ups waiting on this ticket

- [Battle screen is missing the original's top status bar and hall framing](https://github.com/julian-perge/urchin/issues/67) overlaps where its panels are concerned: the top panel 3463 and bottom bar 3315 are group C, `top_panel.png` and `bottom_bar.png` are extracted and unused, and the hall window 3455 and outline 3415 are group A/B.
- R1 (issue 41, PR 133) and R2 (issue 44, PR 140) are both merged, so the map's "battle HUD waits on R1 and R2" line is stale.
