# Working on urchin

A port of the Flash game Sonny 2 to Godot 4.7.2. Art and data come out of the
original SWF by script, not by hand.

Every entry below records something this project already got wrong once. Read
it before touching the SWF, the ActionScript, or an extraction script. Each
entry names its evidence so you can check it instead of trusting it.

## Where the authorities are

- `dev/source_files/action_script/` is the full ffdec script export and the
  authority for game logic. `action_script_curated/` holds commented excerpts.
- `dev/source_files/swf_xml/` is the authority for geometry: placement
  matrices, shape bounds, sprite timelines, export names. Matrices are in
  twips, so divide by 20 for design px. The web dump is about 143 MB.
- `dev/data_json/` is a runtime capture of the Steam build's live `_root`
  arrays, not an export. No script produces it and none can. See
  `SWF_DIFFERENCES.md`.
- `DECODED_ALGORITHMS.md` holds behavior already decoded from the AS so it
  never has to be re-derived. Check it before reading the AS yourself.
- `KNOWN_GAPS.md` is deliberate scoped-out gaps. `NEXT_PHASES.md` is what has
  not been built. Both carry DONE entries with what was found.

## Commands

- Extraction and conversion scripts are `[project.scripts]` entry points:
  `uv run extract_battle_screen`, `uv run convert_items`, and so on. Run
  `rg '^extract_|^convert_' pyproject.toml` for the list.
- Tests: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s
  res://addons/gut/gut_cmdln.gd --path .` Add `-gunit_test_name=<name>` for one
  test.
- After writing anything under `assets/`, run
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .`
  or tests fail with "No loader found for resource".
- ffdec must be at `~/.local/bin/ffdec` and built from the jpexs **master**
  branch. Nightly build 3544 mis-renders bevel-over-clip-mask, which silently
  shrank the biological class card from 191 to 136 design px (`fd755b3`).

## Reading the ActionScript

- **An array can index by name rather than by order.** `Krin.zoneName`
  (`frame_41/DoAction_2.as`) maps a zone onto a frame label by name, so zone 5
  is CITY and zones 6 and 7 are ROME and JAPAN. Reading it positionally is how
  this repo recorded "zones 6 and 7 have no hub art" as an unclosable gap when
  both have real art (`8ef2139`).
- **Instance names in the SWF can be wrong.** Two of the three class-select
  card instance names disagree with the class they show. The authority is the
  button beside the card, because it sets `Krin.Class` (`fd755b3`).
- **Two fields that look like one usually are two.** The hall and the sky are
  `Krin.ZoneBG` and `Krin.SkyBG`, set independently per battle; 16 of 99
  battles differ. A digit-stripping heuristic derived one from the other and
  got 10 of 12 wrong (`8c293c8`).
- **A blank data field does not mean the game shows nothing.** Check whether
  the original reads that field at all. Every tree passive's
  `25_tooltip_description` is 0, which was recorded as a data fact and asserted
  in a test; the original never reads it, and takes the text from
  `KrinLang.ENGLISH.BUFFSAY` instead (`46d16da`).
- **Player-facing text comes from `KrinLang.ENGLISH.*`, not the item or buff
  record.** `ITEMNAME[id]` overwrites the item record's own name at load
  (`frame_42/DoAction_16`). `internal_name` disagrees with what the game shows
  and nothing in the icon path reads it; a reported collision between four item
  pairs was a read of that field and there was nothing to fix (`dc4c5b2`).
- **Check what an id means before treating it as an index.** `buffId` looks
  numeric and is a string name: buffs register as `_root["KRINBUFF" + name]`.
  Reading it as a frame number matches by chance for 9 of 410 buffs and sends
  every id past 400 to a placeholder (`cfaedb5`).
- **Watch off-by-one in rank tables.** `BUFFSAY` is 0-indexed for rank 1 and
  the original clamps its index up from -1, so rank 0 and rank 1 both show the
  first entry (`46d16da`, `f068f87`).
- **Flash folds case in linkage lookups.** `KRIN.MAGICBOLT` and
  `Krin.Magicbolt` are the same clip; resolve export names case-insensitively
  (`4ccdb39`).
- **An export name can resolve to a wrapper.** "KrinTrail" is sprite 3, a
  one-frame wrapper whose only frame shows its child's alpha-0 keyframe, which
  is why that clip extracted fully blank. The real 33-frame content is sprite
  2, which has no export name and is only reachable by id (`4ddee5c`).
- **Battle ids in the raw dump are not all correct.** Three of nine
  `battleCreationID` resets relabel the battle just populated instead of the
  next one, so 109, 409 and 513 were stored as 199, 499 and 599. Corrected at
  conversion time in `battles.py`'s `MISLABELED_BATTLE_IDS` (`c13cff0`).

## Extracting art

- **Never composite shape by shape in Python. Render through ffdec.**
  Reassembling from each PlaceObject's characterId and matrix carries position
  and scale and drops everything else: clip masks, surface filters, gradient
  fills, colorTransforms. 159 of 789 doll sprites carry a filter and 56 carry a
  colorTransform, and ability icons visibly spilled outside their orb without
  the mask (`6928366`).
- **ffdec does not run ActionScript.** Three consequences, all of which have
  bitten:
  1. A character can be fully opaque in the tag data and never visible in the
     game because AS hides it. ffdec draws it and ruins the export. This is the
     black disc over the ability icons: DefineSprite 2241 "bfilter" hides
     itself in `onLoad`, with DefineEditText 2245 the "00" counter on top of
     it. `prepare_extract_swf.py` deletes both from a working copy, and its
     header carries the decoded bytecode.
  2. **Never add a clip mask to `STRIPPED_CHARACTERS`.** A mask looks exactly
     like an unwanted shape on top of the art, and removing one unclips
     everything it covered. DefineShape 1913 was stripped on that assumption
     and item 69 "A Broken Pipe" went from a correct 63x63 to 101x140. Confirm
     an id's placements carry no `clipDepth` first.
  3. `gotoAndStop` handlers never fire, so a root-frame render shows every
     nested sprite at its own frame 1, not the label the game would select.
     The battle recomposition check has to compare WHITE NOVEMBER over SEA
     because those are frame 1 of the hall and sky sprites (`8785f25`).
- **Strip authoring-only characters from a working copy with
  `-removeCharacter`.** Every battle hall places DefineSprite 2676 six times as
  the character rig, so unstripped each background bakes in six placeholder
  fighters holding swords under "!" speech bubbles (`d80a9c4`). The zone hubs
  place the orb 3196 and buttons 3186-3193 the same way (`8ef2139`).
- **A render can carry the author's placeholder text.** A DefineEditText with
  an `initialText` and a `variableName` is filled at runtime, so its baked
  string is scaffolding. The battle bottom bar shipped with two rows reading
  "Thurman McPown" because DefineSprite 3317 places the member bar container at
  depth 7 and nothing stripped it. Before accepting a UI render, grep the
  sprite's descendants for `initialText`.
- **UI chrome is full of clip masks.** DefineSprite 3317 alone places two, at
  `clipDepth` 57 and 4, and the first is what keeps the member bars inside
  their panel. Strip the content, never the mask.
- **Recover positions, never invent them.** ffdec grows the export canvas by
  the filter dimension symmetrically around the timeline displayRect, so the
  canvas keeps the displayRect's centre and the stage rect follows from that
  centre plus the canvas size with no filter math. `doll_art.py`, `zone_hub.py`
  and `battle_screen.py` all do this. Inventing them instead drew the zone orb
  at twice its real size, which every zone scene then cancelled with
  `scale = 0.4` (`8ef2139`).
- **Read the displayRect from ffdec's own SVG pass, not a Python re-walk.** The
  SVG root element states it outright: `xmin` is `-tx/ZOOM` and `width`/
  `height` give the size. The Python recursion cost 28.2s of a 34s run and can
  drift from the render; the SVG cannot, because it is the same rect ffdec
  sizes the PNG canvas with (`94ae2b1`).
- **ffdec's canvas is the whole timeline's union bounds**, so a single frame
  lands in a mostly transparent canvas. Portraits were 56x76 of art inside
  247x237. Crop to the alpha bbox, and when several frames must share one size,
  crop to the union of all their bboxes rather than each frame's own
  (`5045c5c`, `8ef2139`).
- **Export at 4x or 5x and let Godot scale down.** Backgrounds go at 4x,
  small or spinning art at 5x.
- **Do not run ffdec concurrently.** It renders all 780 sprites in 2.64s
  serial against 2.79, 3.47 and 4.80s at 2, 4 and 6 processes (`94ae2b1`).
- **Leave the headless setting alone.** `dev/urchin_dev/__init__.py` sets
  `JAVA_TOOL_OPTIONS=-Djava.awt.headless=true` because ffdec's launcher adds
  `-Xdock` flags that register a macOS Dock app which can steal focus mid-run.
  It lives there rather than in the app bundle, which is not version controlled
  (`53e24ac`).

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
- **Compare against a full-frame ffdec render**, masked to the pixels the
  recomposition actually draws and read at a percentile rather than a maximum.
  The reference paints the stage behind everything, so about 29% of the frame
  is background the recomposition never covers.
- **Say whether you measured a causal claim or guessed it.** Withdraw a wrong
  claim rather than fixing it: `dc4c5b2` and `f068f87` are both corrections of
  earlier commits in this repo that had reasoned instead of measured.

## Godot specifics

- Base resolution is 800x600 with `canvas_items` stretch, so SWF coordinates
  drop in 1:1. The SWF's own stage is 800x575, and that 25px difference is
  still unresolved for the battle hall (see `NEXT_PHASES.md`).
- `.png.import` and `.uid` sidecars must be committed. Forgetting them has
  broken a fresh checkout at least six times (`54ff0b9`, `9e72d69`, `ec53f69`,
  `011cb96`, `18cf5c3`, `37de6ed`).
- `SpriteFrames.new()` ships with a `default` animation already registered, so
  guard `add_animation()` with `has_animation()`.
- Godot's texture importer silently caps width at 32768px and rescales the
  whole image, which desyncs every region of a packed spritesheet. Use
  per-frame folders (`cf81be7`).
- A Tween whose target node is freed keeps running; the property tweener stops
  applying but callbacks still fire. Kill it explicitly (`08dc6a7`).
- A Control never shrinks its own `.size` back down once grown. Resize to
  `get_combined_minimum_size()` (`cbc2257`).
- `top_level = true` stops a child inheriting its parent's transform every
  frame (`828e7d4`).
- Test tweens with `pause()` plus `custom_step(delta)`. `wait_seconds()` races
  the tween in headless and overshoots.
- GDScript `==` throws on an int/String comparison rather than returning false,
  which is useful: it catches leftover string checks after an enum conversion
  (`02f61b1`).
- The suite's total assert count drifts run to run because
  `test_battle_runner.gd::test_misses_are_move_events_not_a_separate_type` runs
  battle 51 with unseeded RNG and asserts once per miss. Pass and fail counts
  are stable; ignore the assert drift.

## Conventions

- Do not hand-cut art or hand-place a coordinate. If it exists in the SWF,
  script it.
- **Extract the parts, rebuild the arrangement.** When reproducing a composed
  widget as one texture would need a render per state, or would bake in a
  string the game fills at runtime, take the pieces out of the SWF and lay them
  out with Godot nodes instead. The battle member bar is the worked example:
  one backing, one runtime name, and five buttons whose only states are which
  icon and which of two overlays, so a faithful texture would have meant twenty
  renders that still could not carry the name. Faithful art plus a Godot
  arrangement beats a heroic extraction. See
  `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`.
- Tests assert against source-derived values. A test that pins a placeholder
  breaks when the real data lands, which is what happened to the store catalog
  test (`f435959`).
- A Rider editor hook on this machine reformats Python on save. Re-run
  `uv run ruff format --check <file>` as the last thing before committing.
