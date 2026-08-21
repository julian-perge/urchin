# Item icon extraction

How `assets/ui/items/*.png` gets generated from the web SWF's item-icon sheet
(`DefineSprite 2064`), and how to run either the wrapped pipeline or the raw
`ffdec` step it wraps.

Note: this is a different asset tree from `assets/item_slot_icons/`. That
directory has no known SWF source - investigated and confirmed a dead end
(`KNOWN_GAPS.md`, "11 numeric-named asset stragglers are untraceable",
2026-07-18): no `ExportAssetsTag` linkage name, no frame-label timeline like
`DefineSprite 2064` has. It's legacy database-named fallback art, only still
used for the handful of items with no matching frame label in 2064.
`scripts/editor/items.gd`'s `SLOT_ICON_OVERRIDES` can still hand-pick one of
these for a specific item when regenerating `.tres` files from `items.json`
from scratch; `item_icons.py` itself no longer has an equivalent override
table (removed 2026-08-18 once the clip-mask fix below made the 2064
extraction agree with this fallback art for the two items that had needed
one).

## The wrapped command

```sh
uv run extract_item_icons
```

Runs `dev/urchin_dev/swf/extract/item_icons.py`. Exports every frame of
`DefineSprite 2064` (the game's own `itemSlot.inner.gotoAndStop(ITEMNAME[id])`
sheet) directly via ffdec's own sprite renderer, trims each labeled frame down
to its own opaque content at 2x into `assets/ui/items/<sanitized label>.png`,
then repoints every matching `resources/items/<id>_*.tres`'s `slot_image` at
the new icon.

Rendered directly rather than reassembled shape-by-shape (2026-08-18, same
fix as `faces.py`'s portrait rewrite) - a hand-rolled compositor that reads
only `characterId`/matrix off each `PlaceObject` tag has no way to carry a
colorTransform or filter set on that same tag, so any icon depending on one
silently lost it. Confirmed on item 592 "Ancient Cage": the old composited
icon was missing the glowing yellow ward markings the live game shows.

`DefineShape 1913` is a real clip mask, not the editor scaffolding it looks
like, and is left in place. Every frame places it at depth 2 with
`clipDepth="15"`. An earlier version of this script read it as scaffolding and
stripped it from a working copy via `-removeCharacter`, which let ffdec render
depths 2 through 15 unclipped and ballooned item 69 "A Broken Pipe" from a
correctly masked 63x63px to 101x140. Restoring the mask brought it straight
back. Before stripping any character to clean up an export, check whether its
placements carry a `clipDepth`.

Each frame is then trimmed to its own opaque bounds (`Image.getbbox()`), not
forced into a fixed 31x31 crop - a fixed crop was tried first and rejected:
ffdec sizes every frame's exported PNG to the *whole timeline's* union
bounding box (856 frames, most much bigger than any one icon), so several
items' real art is authored well outside a 31x31 square (item 592's
chest-armor art alone is ~50x62 design px) and a fixed crop was silently
cutting it off. Nothing in the decompiled ActionScript ever clips icon art
at runtime (`rg scrollRect` / `rg '\.mask ='` under `dev/source_files/
action_script` are both zero hits) and the live game does show it at full
size. `item_slot.tscn`'s icon `TextureRect` (`stretch_mode = 0`, `expand_mode
= 1`) scales whatever it's given to fill the 31x31 slot regardless of the
source image's own size, so trimming to content and letting Godot scale it
is enough - no per-item registration math needed, same as `faces.py`.

## Diagnosing one icon by hand

Same `sprite:png` export the script runs, scoped to one frame via `-select`,
so you can inspect a single item without waiting on the full ~330-frame
batch. `-zoom 2` matches the script's `ZOOM = 2.0`.

```sh
ffdec -zoom 2.0 -select 2064:592 -format sprite:png -selectid 2064 -export sprite ./test_cage sonny-2-2900.swf
```

Writes `./test_cage/DefineSprite_2064/592.png` - frame 592 is item 592
"Ancient Cage"; find another item's frame number the same way the script
does, via `snapshot_timeline`'s `labels` dict (see the lookup script below).
This is the full frame as ffdec renders it, `DefineShape 1913`'s backing
square included and the mostly-transparent full-timeline canvas untrimmed -
crop to the opaque bounds (`Image.open(...).getchannel("A").getbbox()`) to
see what actually ships.

**The worked precedent this generalizes from - the exact pair of commands
that found the ability-icon black-disc bug** (commit `ff6a028`; ability icons
live in `DefineSprite 2427`, not 2064):

```sh
# The real per-label art for the "ACIDIC" ability (frame 228, depth 5) -
# a clean, colorful icon on its own.
ffdec -zoom 2.0 -format shape:png -selectid 2296 -export shape ./test_acidic sonny-2-2900.swf

# The opaque black disc (frame 228, depth 11) that was sitting on top of it
# in every composited icon - present at the same depth on 103 of 104 labels.
ffdec -zoom 2.0 -format shape:png -selectid 2241 -export shape ./test_disc sonny-2-2900.swf
```

Comparing those two PNGs, real art against opaque disc, is what confirmed the
root cause. `ability_icons.py` skipped the disc during compositing for a while,
which removed it but could not carry the sheet's clip mask, glow filters, or
gradient fills. It renders through ffdec now, like this script does, and
`dev/urchin_dev/swf/prepare_extract_swf.py` deletes the disc from a prepared
copy of the SWF instead, along with the cooldown counter text beside it. Both
are opaque in the tag data but hidden by ActionScript at runtime, and no static
renderer can know that.

## Finding an item's frame number

```sh
uv run python3 -c '
from urchin_dev import WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

xml = WEB_SWF_XML.read_text()
_snaps, labels = snapshot_timeline(xml, 2064, set())
print(labels["A Broken Pipe"])  # exact frame label, case-sensitive
'
```
