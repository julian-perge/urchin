# Battle screen art extraction

**Goal:** replace the hand-made battle backgrounds and bottom-bar chrome with
renders from the SWF, and record the stage positions the layout code currently
guesses at.

**Status:** design, not yet implemented.

## Why now

Everything in `assets/backgrounds/battle/`, `assets/backgrounds/sky/`,
`assets/ui/battle/` and `assets/ui/hotbar/` was cut by hand in July, before the
project settled on rendering through ffdec. `NEXT_PHASES.md` deferred this at
the time. The class-select, zone-hub and store passes since then have built the
pieces it needs: `root_placements()` for main-timeline display lists,
`-removeCharacter` for stripping foreground off a background, and the
displayRect recovery that turns a filtered render back into a stage rect.

Two of those earlier passes also showed what happens when placement data is
guessed rather than read. The class cards were cropped from a composited frame
and carried the background inside their own drop shadow. The zone orb was drawn
at roughly twice its real size, and every zone scene carried `scale = 0.4` to
cancel it. The battle screen has the same shape of problem today, in
`battle_scene.gd::_load_background()`:

- `SKY_HORIZON_Y = 292.0`, a tuned constant. The SWF places the sky at
  y = 287.1 and the hall at y = 294.5.
- A trailing-digit fallback, `STREETS2` to `SKY_STREETS`, then a hardcoded
  `SKY_JAIL` default, because the two sprites' label sets do not match.
- "Fill the area above the strip with the strip's own top-edge color", which
  reconstructs by sampling what the source states outright.

## What the source holds

The battle screen is main-timeline frame label `KRINBATTLESCENE` (root frame
217), which places 38 characters. In scope:

| cid | name | depth | stage position | today |
|---|---|---|---|---|
| 3317 | `UI_BAR` | 1 | (400.0, 508.0) | `ui/hotbar/background.png`, hand-made |
| 3465 | top panel frame | 59 | (400.0, 73.3) | not extracted |
| 3460 | alert icon | 65 | (400.0, 507.9) | not extracted |
| 3455 | stage rect | 70 | (400.0, 287.0) | not extracted |
| 3454 | sky | 73 | (399.5, 287.1) | `backgrounds/sky/SKY_*.png`, hand-made |
| 3435 | `BATTLESCREEN` | 89 | (400.0, 294.5) | `backgrounds/battle/*.png`, hand-made |

`3317` also sits at depth 1 on the `Navigation` frame, so the bottom bar is one
shared asset rather than the two copies the repo keeps
(`ui/hotbar/background.png` and `ui/battle/hotbar_background.png`).

`3465` is the frame the six `p1BAR`..`p6BAR` fighter bars (`3414`) sit inside.
Those bars are the "top battle bar panel" `KNOWN_GAPS.md` scoped out. This work
extracts the frame's art and stops there; building the bars stays a separate
feature.

### The two label sets differ

`3435` (halls) carries 10 labels and `3454` (skies) carries 9, and they are not
the same set:

```
3435  CHURCH  CHURCH2  JAIL  SNOW  STREETS  STREETS2  STREETS3  TRAIN  TUNNEL  WHITE NOVEMBER
3454  CHURCH           JAIL  SNOW  STREETS            STREETS3  TRAIN  TUNNEL                  ROME  SEA
```

So `CHURCH2`, `STREETS2` and `WHITE NOVEMBER` genuinely have no sky of their
own, while `ROME` and `SEA` are skies with no hall. The current code hides that
by stripping digits and then defaulting to `SKY_JAIL`. The extraction names
files after the real labels and leaves the gap visible, so a missing sky is a
fact about the source rather than a silent substitution.

`assets/backgrounds/battle/` also holds six files named after raw character ids
(`3423`, `3424`, `3438`, `3440`, `3450`, `3452`) and two labels the sprite does
not have (`JAIL3`, `SEA`). Those are hand exports. Once the script runs, each
one either matches a label it can regenerate or has no source behind it and
goes.

## Design

One new script, `dev/urchin_dev/swf/extract/battle_screen.py`, entry point
`extract_battle_screen`. It follows `zone_hub.py`, which is the closest
existing shape: one screen, several outputs, positions printed alongside.

### Halls and skies

Render `3435` and `3454` at each of their own labelled
frames, trim to content, write `assets/backgrounds/battle/<LABEL>.png` and
`assets/backgrounds/sky/<LABEL>.png`. Labels keep the SWF's spelling with
spaces turned to underscores, matching what `battle.zone_background` already
carries.

### Chrome

Render `3317`, `3465`, `3460` and `3455` at frame 1 into
`assets/ui/battle/`. `3455` is a plain black rect that a `ColorRect` may well
replace, but the script exports it so that call can be made by looking at the
render.

### Positions

Write `assets/backgrounds/battle/battle_layout.json` holding one
entry per placement above: the stage rect in design px, recovered the way
`zone_hub.py` and `doll_art.py` do it, from the placement matrix plus the
sprite's displayRect centre and the canvas ffdec produced. This is what lets
`_load_background()` drop `SKY_HORIZON_Y` and place the sky where the source
places it.

### Zoom

4x, matching `zone_hub.py`. These are full-screen backgrounds.

### Consuming it

`_load_background()` changes to read `battle_layout.json` instead of computing
positions:

- Sky y comes from the JSON, not `SKY_HORIZON_Y`.
- A hall with no matching sky label leaves the sky node empty rather than
  falling back to `SKY_JAIL`. Whether that reads acceptably in game is the one
  thing this design cannot settle from the source, because the original never
  reaches those combinations.
- The fill above the strip stays, since it is a real behavior, but it samples
  a render that now starts in the right place.

## Verification

- Every label in `3435` and `3454` produces a non-empty PNG, asserted in the
  script rather than checked once by hand.
- The composited result (sky, then hall, at their JSON positions) matches a
  full `KRINBATTLESCENE` render of the same zone with the foreground stripped,
  the same way the class-select work was checked against a recomposition.
- The existing battle tests keep passing, and `test_all_zone_scenes_...` style
  coverage is extended to assert each battle key resolves to real art.

## Out of scope

- The six `p1BAR` fighter bars (`3414`). Unbuilt feature, not a re-extraction.
- `KrinSelector` (`3394`), `battleClocker` (`3389`), `selector` (`3382`),
  `moveSelectBoomer` (`3373`). Hand-built and working; re-extracting them is a
  separate pass with its own risk.
- The eight unexplained files in `assets/backgrounds/battle/`. The script will
  reveal whether each has a label behind it; deciding what to do with any that
  do not is a follow-up.

## Open question

Zones 6 and 7 currently point their battle art at `CHURCH` and `STREETS`. The
zone-hub pass showed that kind of reuse was sometimes a wrong assumption rather
than a real gap, so it is worth checking whether `ROME` and `SEA` (skies with
no hall today) indicate halls that exist somewhere else in the SWF before
accepting the reuse.
