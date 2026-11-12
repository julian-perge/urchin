# Extracting art

How art comes out of the SWF: where its geometry is recorded, the ffdec build
every render depends on, and the mistakes this project has already made
extracting it.

## Where the geometry comes from

- The SWFs themselves are the authority for geometry, read through
  `dev/urchin_dev/swf/swf_index.py` and `timeline.py`: placement matrices,
  shape bounds, sprite timelines, export names. `timeline.frames()` is the one
  display list walk. Matrix translates are in twips, so divide by 20 for
  design px. The ffdec `-swf2xml` dumps in `dev/source_files/swf_xml/` stay in
  LFS for grepping, and nothing reads them anymore.
  `uv run export_swf_sources --xml` rewrites them, which adds ~284 MB to LFS.

## The ffdec build

- ffdec must be at `~/.local/bin/ffdec`, built from jpexs `cde1cc21a`. That
  build rendered the committed art on JDK 25.0.4, and
  `unzip -p ~/git/jindrapetrik/jpexs-decompiler/dist/lib/ffdec_lib.jar project.properties`
  prints the commit yours was built from. The render driver always passes
  `aaScale` 1, and CLI exports read `useMsaaForExport` from FFDec's
  config.toml, where it has to stay `false` and a GUI session can change it.
  That file is in ~/Library/Application Support/FFDec on macOS and in
  ~/.config/FFDec on Linux. Another build redraws art by itself,
  so change builds in a PR of their own that regenerates and measures every
  family: `e3cd93397` moved tiled bitmap fills, `afbe4fa33` moved clip mask rims
  and broke the class cards until `Render.java` corrected it (see Extracting
  art), and nightly 3544 mis-renders bevel-over-clip-mask, which silently shrank
  the biological class card from 191 to 136 design px (`fd755b3`).
- On that build every extractor that renders through ffdec, apart from
  `extract_cutscenes`, reproduces its committed files byte for byte, so the diff
  after a run is what the run changed. This holds on macOS and on Linux, because
  every PNG goes through `dev/urchin_dev/png.py`. One exception is expected and goes back
  with `git checkout`: `extract_battle_screen` rewrites `STREETS.png` and
  `STREETS3.png`, where 5 pixels are 1 level off and no build reproduces the
  committed file.

## Extracting art

- **Never composite shape by shape in Python. Render through ffdec.**
  Reassembling from each PlaceObject's characterId and matrix carries position
  and scale and drops everything else: clip masks, surface filters, gradient
  fills, colorTransforms. 159 of 789 doll sprites carry a filter and 56 carry a
  colorTransform, and ability icons visibly spilled outside their orb without
  the mask (`6928366`).
- **ffdec does not run ActionScript.** Four consequences, all of which have
  bitten:
  1. A character can be fully opaque in the tag data and never visible in the
     game because AS hides it. ffdec draws it and ruins the export. This is the
     black disc over the ability icons: DefineSprite 2241 "bfilter" hides
     itself in `onLoad`, with DefineEditText 2245 the "00" counter on top of
     it. `ability_icons.py` hands both to `render.py`, which deletes them in
     memory, and its `COOLDOWN_DISPLAY` carries the decoded bytecode.
  2. **Never strip or hide a clip mask.** A mask looks exactly like an
     unwanted shape on top of the art, and removing one unclips everything it
     covered. DefineShape 1913 was stripped on that assumption and item 69 "A
     Broken Pipe" went from a correct 63x63 to 101x140. `strip.py` refuses
     any id placed with a `clipDepth`, so go through it.
  3. `gotoAndStop` handlers never fire, so a CLI render shows every nested
     sprite at its own frame 1, not the label the game would select. That's
     why the battle check used to compare only WHITE NOVEMBER over SEA, frame
     1 of the hall and sky (`8785f25`). `verify_battle_screen.py` moves them
     through `ffdec_lib.py`'s `goto` now.
  4. A clip plays on past its `stop()`. ffdec draws every frame of a sprite
     and draws a nested clip on its age modulo its frame count, so a nested
     clip that ran `stop()` loops round. 18 impact clips replayed part of
     their effect that way: BOOM_SPARK drew its spark again on frames 21 to
     24, where the game holds sprite 884 on its empty frame 20 (`b3f2159`).
     Pick the frames of a clip the game plays through `render.py`'s
     `played_frames()`. When a `gotoAndPlay()` or a `play()` starts the clip
     past a `stop()`, as the Shield clip's `play()` does, pass that frame as
     `start`.
- **Strip authoring-only characters through `dev/urchin_dev/swf/strip.py`.**
  Each extractor keeps its own `{characterId: reason}` and renders and
  measures from the one copy or hide list it gets back. Every battle hall
  places DefineSprite 2676 six times as the character rig, so unstripped each
  background bakes in six placeholder fighters holding swords under "!"
  speech bubbles (`d80a9c4`). The zone hubs place the orb 3196 and buttons
  3186-3193 the same way (`8ef2139`).
- **A render can carry the author's placeholder text.** A DefineEditText with
  an `initialText` and a `variableName` is filled at runtime, so its baked
  string is scaffolding. The battle bottom bar shipped with two rows reading
  "Thurman McPown" because DefineSprite 3317 places the member bar container at
  depth 7 and nothing stripped it. Before accepting a UI render, grep the
  sprite's descendants for `initialText`.
- **A clip mask inside a sprite with a filter lands in the wrong place on ffdec
  since jpexs `afbe4fa33`.** ffdec draws that sprite into its own image and then
  positions the mask with a matrix that leaves out where that image sits, so the
  mask is off by that offset. Measured on the three class cards, it is 51, 12
  and 1 design px, which shrank the biological card to 159 px wide and moved the
  other two. `Render.java`'s `ClipPlacedTimeline` corrects it, pixel-identical to
  changing `absMat` to `mat` at that line of `Timeline.java`. Of the 3,893
  generated files only the six cards change, because every other extractor renders
  the filtered sprite itself rather than its parent. The ffdec CLI still has the
  bug. CS_CUT1 to CS_CUT5 reach no case it would change, because no sprite under
  their wrappers is placed with a filter or a blend mode and holds a clip mask.
  CS_INTRO2 reaches one, because sprite 3643 places the blurred sprite 3635, which
  holds clip masks, three times from frame 1851 to 2002. On sprite 3643's own
  frames, the CLI differs from the driver by at most 92 of 8.4 million pixels over
  19 frames sampled in that span. Those pixels sit in a box no larger than 43x41
  px, and no frame from 1915 on differs at all, so its export stays on the CLI.
- **Render PNG frames through `dev/urchin_dev/swf/render.py`.** It runs the
  ffdec_lib driver once per SWF per extractor, deletes each strip list in
  memory, and hands back every canvas with the rects it was sized from, so a
  crop and its stage rect always come from the same render. The CLI is left
  for the cutscene AVI and its probe frame, the two shape exports and
  `export_swf_sources.py`. Every external command goes through
  `dev/urchin_dev/run.py`.
- **Write every PNG through `dev/urchin_dev/png.py`, never `Image.save` or a
  copy of the driver's file.** Pillow and the driver's Java encoder compress
  with the zlib build of the machine they run on, so the same pixels came out
  as different bytes on Linux and on macOS. Every committed portrait and class
  card showed as changed after a Linux run, with 0 pixels changed. `png.save`
  encodes through oxipng, whose bytes depend only on the pixels and the
  `pyoxipng-ng` version. That version is pinned exactly, because a new one
  rewrites every PNG, so change it in a PR of its own that regenerates them.
  `dev/tests/test_png.py` fails when an extractor writes a PNG another way.
- **Recover positions, never invent them.** ffdec grows the export canvas by
  the filter dimension symmetrically around the timeline displayRect, so the
  canvas keeps the displayRect's centre and the stage rect follows from that
  centre plus the canvas size with no filter math. `render.py` does this for
  every extractor. Inventing them instead drew the zone orb at twice its real
  size, which every zone scene then cancelled with `scale = 0.4` (`8ef2139`).
- **Read the displayRect from the render, not a Python re-walk.** The driver
  reports the rect it sized each canvas from, with and without the filter
  margin. The Python recursion cost 28.2s of a 34s run and can drift from the
  render, and the driver's rect cannot, because it is the rect ffdec sizes
  the canvas with (`94ae2b1`).
- **ffdec's canvas is the whole timeline's union bounds**, so a single frame
  lands in a mostly transparent canvas. Portraits were 56x76 of art inside
  247x237. Crop to the alpha bbox, and when several frames must share one size,
  crop to the union of all their bboxes rather than each frame's own
  (`5045c5c`, `8ef2139`).
- **Export at 2x, 4x or 5x and let Godot scale down.** Halls, skies, hub art,
  battle chrome, store art and Window chrome (`window_chrome.py`) go at 4x, and
  orbs, faces and class cards at 5x.
  Dolls, VFX, the item, buff and ability icons and the start screen backgrounds
  go at 2x. The Floating numbers (`floating_numbers.py`) go at 4x, because the
  critical label starts at 2.84x and the other labels start at 1.78x. The
  rig's clips (`rig_clips.py`) go at 2x, the window's default scale, as the
  dolls do.
- **ffdec thins the blur on large filtered objects, at any zoom.**
  `Filtering.boxBlurSingleIterationTwoPass` shrinks both box widths until
  `boxX * boxY * width * height` fits `boxBlurPixelsLimit * 100000`, which cut
  a battle hall's glow box from 116 texels to 6. `Render.java` lifts the limit
  in memory for every driver render. `cutscenes.py` lifts it for the AVI export,
  which goes through the CLI, by passing `-config boxBlurPixelsLimit=2147483647`
  ahead of its other arguments. ffdec only saves a `-config` to its `config.bin`
  when nothing follows it.
- **Do not run ffdec concurrently.** It renders all 780 sprites in 2.64s
  serial against 2.79, 3.47 and 4.80s at 2, 4 and 6 processes (`94ae2b1`).
  A daemon that keeps the parsed SWF would save about 1.3s of a 34s run, so
  none was built. Two ffdec faults are known and left alone: `-select all:N`
  throws a NullPointerException at `CommandLineArgumentParser.java:1650`, and
  the launcher sets `-Xmx1024m` where one export runs in 192m.
- **Measure a backdrop colour from the SWF, never from the port's art.** The
  battle sky PNGs have a soft top edge, so the pixel at row 0 is transparent
  for 5 of the 9 skies, and a fill sampled there drew nothing. The colour under
  the sky is (0, 0, 0, 255): DefineShape 333, placed once inside DefineSprite
  3455 at depth 70 and once at depth 72. The SWF's SetBackgroundColorTag
  (14, 18, 21) never reaches the screen on that frame. A render with the whole
  `FOREGROUND` list stripped also strips 333, so it shows (14, 18, 21) and
  gives the wrong answer. Strip only the characters the frame places above the
  hall.
- **A strip needs a check on a label it changes.** Stripping the fighter rig
  moves the displayRect of 5 of the 10 halls. A check on CHURCH passed because
  CHURCH is one of the 5 it does not move. `-removeCharacter` on a container
  removes the container only, and the characters nested in it still render.
  It also shrinks the container's union bounds, so `content_rect` reports a new
  origin for art whose pixels did not move.
- **A shape with a bitmap fill of id 65535 renders as static.** The source SWF
  has no DefineBits for it, so this is an authoring fault, not a pipeline
  fault. It put about 1.1s of noise at the end of one cutscene and more in the
  middle of another. `cutscenes.py` finds these shapes with
  `find_broken_bitmap_fill_cids` and strips them, so a new cutscene needs no
  hand-made id list. Its header comment records the encoder settings.
- **Leave the headless setting alone.** `dev/urchin_dev/__init__.py` sets
  `JAVA_TOOL_OPTIONS=-Djava.awt.headless=true` because ffdec's launcher adds
  `-Xdock` flags that register a macOS Dock app which can steal focus mid-run.
  It lives there rather than in the app bundle, which is not version controlled
  (`53e24ac`).
