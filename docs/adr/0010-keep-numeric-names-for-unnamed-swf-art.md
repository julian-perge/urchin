# Keep numeric names for art the SWF never names

Nine committed PNGs have a number for a name: `assets/backgrounds/battle/3423.png`, `3424.png`, `3438.png`, `3440.png`, `3450.png` and `3452.png`, and `assets/item_slot_icons/PANTS/356.png`, `SHOES/402.png` and `WEAPONS/797.png`. We keep those names. A name we make up could be confidently wrong, and the number is the only fact we have about each file. Leaving the item icons numeric was the project owner's call on 2026-07-18. Two more, `assets/backgrounds/3032.png` and `3034.png`, were in the same group and are gone.

## What the SWF gives

Audio came out with clean names because each sound has an `ExportAssets` linkage name in the SWF. Background and icon art has none. On 2026-07-18 every one of the 1343 named sprite symbols in `sonny-2-2900.swf` was exported and searched for zone names and item icon patterns, and nothing matched. One large unnamed sprite, DefineSprite 3229, was opened by hand and is real background art, a train interior. So the SWF embeds this art as anonymous numbered symbols, with no export name to recover.

- The six battle files carry real character ids. `ffdec -dumpSWF` shows a `DefineBits` or `DefineShape` tag at each of those ids, so the number names the art correctly. They are gradient and vignette overlay shapes, not zone backgrounds.
- The three item icons do not carry character ids. In the SWF, 356 and 402 are unrelated `DefineSound` tags and 797 is an unrelated `DefineShape2`. Their numbers come from some other index that nothing in the SWF explains.

## Consequences

- No scene, script or resource loads any of the nine files today. The battle halls and skies come from `extract_battle_screen`, and item icons come from DefineSprite 2064 by name (`docs/item-icon-extraction.md`).
- A file that comes back into use keeps its number. Rename it only when a script recovers a name from the SWF.
