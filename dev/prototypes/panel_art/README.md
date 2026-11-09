# Panel art across every KRINMENU label

PROTOTYPE, throwaway. It lives on the branch `prototype/panel-art` and is never merged.

**Question** ([Should panels draw as StyleBoxFlats built from the SWF shapes, or as the extracted textures?](https://github.com/julian-perge/urchin/issues/114)): the 16 flat KRINMENU Panels can come from a StyleBoxFlat or from extracted art in a zero-margin StyleBoxTexture. Which lands closer to the original across every label and window size, once the inner shadow shader is on both?

`facts.md` holds every number and which capture it came from. `images/panel-art-2x-window.png` shows the difference at the game's 2x window and `images/panel-art-big-capture.png` at the big captures' stretch.

## Variants

Every variant carries the inner shadow shader, so only the fill and stroke differ.

- `flat_axis` is a StyleBoxFlat with per-axis rounded borders at the bounds x matrix rect, the way the victory prototype drew it.
- `flat_mean` is a StyleBoxFlat with one border width, the rounded mean scale, at the fill rect grown by half that border.
- `custom` is a GDScript StyleBox with the exact fractional stroke.
- `art2` and `art4` are the bare shapes rendered at zoom 2 and 4, stretched in a StyleBoxTexture. `art2` is pixel for pixel today's `panel_large.png`, `panel_bar.png` and `panel_center.png`.

## Files and how they were made

The scripts read and write under `~/tmp/2026-11-09-panel-art` and import `urchin_dev` from a worktree, so the paths at their tops need changing to rerun them. `render_refs.py` and `backdrop_bevel.py` run ffdec, so nothing else may be rendering.

```sh
uv run shape_records.py 2989 2991 2987   # one shape's styles and whether it is a plain rectangle
uv run walk_panels.py && uv run show2.py # every panel-like shape on every Screen, Window and the HUD
uv run make_labels.py                    # -> data/labels.json, each label's Panels with their true stroke
uv run render_refs.py                    # ffdec references and bare panel art
/Applications/Godot.app/Contents/MacOS/Godot -d --path godot/today --embedded --quit-after 900 -s ../driver.gd -- --out=<dir>   # add --resolution 800x600 for 1x
/Applications/Godot.app/Contents/MacOS/Godot -d --path godot/big --embedded --resolution 4112x2658 --quit-after 900 -s ../driver.gd -- --out=<dir>
uv run score.py && uv run agree.py       # -> data/scores.txt, and the stroke edges that land on Flash's pixels
uv run stroke_tab.py && uv run stroke_flash.py # stroke widths and positions in ffdec and real Flash
uv run backdrop_bevel.py && uv run backdrop_score.py # the backdrop with KRINMENU's own filters
```

`compare_today.py` is the inner shadow prototype's `compare_variants.py` pointed at a run with today's main settings, to recheck the numbers already on the ticket.
