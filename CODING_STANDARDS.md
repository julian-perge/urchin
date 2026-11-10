# Coding standards

What a reviewer checks a urchin diff against. Each standard records something
this project already got wrong once and names its evidence.

## Conventions

- **Extract the parts, rebuild the arrangement.** When reproducing a composed
  widget as one texture would need a render per state, or would bake in a
  string the game fills at runtime, take the pieces out of the SWF and lay them
  out with Godot nodes instead. The battle member bar is the worked example:
  one backing, one runtime name, and five buttons whose only states are which
  icon and which of two overlays, so a faithful texture would have meant twenty
  renders that still could not carry the name. Faithful art plus a Godot
  arrangement beats a heroic extraction. See
  `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`.
- **Tests assert against source-derived values.** A test that pins a
  placeholder breaks when the real data lands, which is what happened to the
  store catalog test (`f435959`).

## Verifying

- **Check that a spot check generalizes before trusting it.** Verifying the
  battle layout rects on CHURCH proved nothing, because CHURCH is one of five
  halls where the fighter rig happens not to poke above the art. The other five
  were wrong (`ecf28fd`).
- **Find an independent invariant and check it across everything.** For
  extracted art it is `rect * ZOOM == PNG pixel size`, which holds for all 19
  battle labels and is what caught the rect bug.
- **Prove a check can fail.** The recomposition verifier was only trusted after
  shifting a rect 20px and pointing it at the wrong label and watching both
  push p99 from 8 to 69 and 182.
- **Compare against an ffdec render**, masked to the pixels the
  recomposition actually draws and read at a percentile rather than a maximum.
  A whole-frame reference paints the stage behind everything, about 29% of the
  battle frame, and its exact matches dilute the edges that matter, so
  `verify_battle_screen.py` only counts pixels inside 333's box.
- **Withdraw a wrong claim rather than fixing it.** `dc4c5b2` withdrew a claim
  an earlier commit in this repo had reasoned instead of measured.
