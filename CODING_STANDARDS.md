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
  `spec/old/2026-08-23-battle-bottom-bar-and-stance-rows.md`.
- **Tests assert against source-derived values.** A test that pins a
  placeholder breaks when the real data lands, which is what happened to the
  store catalog test (`f435959`).
- **Read every value from the original out of extracted data.** A number the
  diff cites from the AS or the SWF, such as a frame count, a ratio, a
  coordinate or a limit, comes from an extractor's output, and the test reads
  the same output. When the AS computes a value, extract the inputs and the
  operation. Three of #150's six tickets typed such values in by hand, and
  only review caught them (`3f50df8a`). This includes amounts that
  `dev/converted_json` already holds: read a buff's base value from
  `buffs.json` instead of typing 666 (`c84c007a`).
- **A comment passes three tests or goes.** It is necessary, because the code
  alone can't say it: a reason, a link to another file, or an intentional
  absence. It is skimmable, as a full sentence that stands on its own, with no
  fragments. It is complete, because it says what actually happens and nothing
  else in the file contradicts it. #150's review rewrote or deleted a dozen
  fragment comments (`3053a675`).

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
  - A test that needs a new signal or method can't compile on the old code,
    so a compile error proves nothing. Commit the new API alone first, then
    show the test fail on behavior, then add the fix, as #146 did with
    `AudioManager.effect_played` (`2628f3e2`).
  - A test's pass signal has to be one that only the code under test can
    cause. #196's killing-tick test watched `displayed.life == 0.0`, which the
    BUFF_TICK event had already set, so it passed with the DEATH arm broken.
    Break the line a test claims to pin and watch it go red (`2a79eb9a`,
    `14a32db9`, `785aafef`).
  - Run Python mutation checks with `PYTHONDONTWRITEBYTECODE=1`. In #148, a
    restored file kept its size and landed in the same second as the mutated
    `.pyc`, so the next extractor run used the mutated bytecode and wrote red
    multipliers where alphas belonged.
- **Compare against an ffdec render**, masked to the pixels the
  recomposition actually draws and read at a percentile rather than a maximum.
  A whole-frame reference paints the stage behind everything, about 29% of the
  battle frame, and its exact matches dilute the edges that matter, so
  `verify_battle_screen.py` only counts pixels inside 333's box.
- **Withdraw a wrong claim rather than fixing it.** `dc4c5b2` withdrew a claim
  an earlier commit in this repo had reasoned instead of measured.
