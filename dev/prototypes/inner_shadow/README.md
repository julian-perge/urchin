# Inner drop shadow on the menu Panels

PROTOTYPE, throwaway. It lives on the branch `prototype/inner-shadow` and is never merged.

**Question** ([How should the port draw the inner drop shadow on the original's panels?](https://github.com/julian-perge/urchin/issues/115)): all 16 KRINMENU panel placements carry an inner DropShadow (black, blur 5, distance 5, angle 45, strength 1). Which way of drawing it lands closest to the original, and what does each way cost?

## What the original draws

One box blur of a straight edge is a straight ramp, so on these solid rectangles the shadow is `fill * A(x) * A(y)`, with `A` a ramp centred `distance * cos(angle)`, 3.54 design px, in from the edge. At 45 degrees with the distance above blur / 2 it only reaches the top and left edges. The filter is in Stage px and ignores the placement's matrix, so a panel scaled 0.89 by 1.22 has the same ramp on both axes.

Going in from the left edge of the left panel, a real Flash capture at a 2x window (`references/2026_07_18_flashpoint/16_after_battle_victory_screen_...`) reads 0, 0, 0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 55, a box 9 device px wide. The 1x capture (`zone1_itemshop_menu_...`) reads 0, 5, 16, 27, 38, 49, 55, a box 5 px wide. ffdec at zoom 2 draws a box 10 device px wide. `profile.py` and `shop_1x.py` print these.

`inventory.py`, `inner_dropshadows.py` and `shapes.py` list every inner DropShadow in both SWFs. Only the 16 panels are flat rectangles.

## Scores

`godot/main.gd` builds the victory screen's backdrop and four panels at their SWF rects and saves the framebuffer for each variant, in a project with urchin's stretch and filter settings, hdr_2d off, and the victory prototype's art. `compare_variants.py` prints p99 of the largest channel difference. The shadow band is the 14 device px in from each panel's left and top edges, skipping the outer 3.

Pixel snapping on:

| Variant | Panels frame at 1x vs ffdec | Panel rects at 2x vs ffdec | Shadow band vs real Flash |
|---|---|---|---|
| `flat`, StyleBoxFlat, no shadow | 35 | 43 | 50 |
| `plainart`, extracted art, no shadow | 36 | 44 | 50 |
| `baked`, the prototype's stretched texture | 17 | 9 | 16 |
| `nine_raw`, 1x ffdec render, nearest / linear | 25 / 28 | 13 / 16 | 15 / 12 |
| `nine_aligned`, resampled to texel edges, nearest / linear | 16 / 16 | 12 / 10 | 11 / 9 |
| `shader5`, on a StyleBoxFlat | 16 | 5 | 8 |
| `shader_plainart`, over `plainart` | 16 | 5 | 8 |
| `stylebox`, a custom StyleBox | 16 | 5 | 8 |
| `shader45` and `stylebox45`, box 4.5 | 16 | 6 | 7 |
| `shader_wrong`, ramp 2 px too far in | 23 | 24 | 32 |
| ffdec's own render | | | 7 |

Pixel snapping off:

| Variant | Panels frame at 1x vs ffdec | Panel rects at 2x vs ffdec | Shadow band vs real Flash |
|---|---|---|---|
| `flat` | 30 | 43 | 50 |
| `baked` | 7 | 6 | 12 |
| `shader5` | 12 | 3 | 6 |
| `shader45` | 13 | 4 | 5 |

The nine-patches and the custom StyleBox weren't run with snapping off. `images/` has the top left corner of the left panel for each variant at a 2x window, and the nine-patches against the shader at a 4x window.

## Files and how they were made

The scripts read and write under `~/tmp/2026-11-09-inner-shadow`, with the victory prototype unpacked under `proto/`.

```sh
uv run python render_panels.py <path to sonny-2-2900.swf>   # ffdec, zoom 1 and 2
/Applications/Godot.app/Contents/MacOS/Godot -d --path godot --embedded -s main.gd   # add -- --no-snap --out=<dir> for snapping off
uv run python compare_variants.py [out dir]
uv run python sheet.py
```

`render_panels.py` stays at zoom 2 or below because ffdec lowers the blur radius on large objects above that (`Filtering.boxBlurSingleIterationTwoPass`). A 249x267 panel at zoom 4 gets a box 9 texels wide instead of 20.
