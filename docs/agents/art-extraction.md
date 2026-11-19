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
  orbs, faces, class cards and the hotbar icons (`hotbar_icons.py`) at 5x.
  Dolls, VFX, the item, buff and ability icons and the start screen backgrounds
  go at 2x. The Floating numbers (`floating_numbers.py`) go at 4x, because the
  critical label starts at 2.84x and the other labels start at 1.78x. The
  Shield clip (`shield_clip.py`) goes at 2x, the window's default scale, as the
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

## Screen compare tool

`just compare-screen <entry>` scores a capture of a Screen or Window in the
port against ffdec's render of the same SWF frame, with text hidden
(spec/107-ui-foundation.md, Part 5). The rect test checks where a piece lands.
This tool checks how it looks: the art, the fills and the shadows.

- **It never runs in `just gut`.** It needs the gitignored SWF, ffdec and a
  capture from a drawing window, so run it by hand. `just pytest` covers its
  arithmetic and its config rules without any of the three.
- **The config is `dev/screen_compare/screens.json`.** Each Screen or Window
  build issue adds one entry: the scene and one or both modes. `chrome` scores
  the whole frame with every edit text stripped against the scene with every
  Label hidden. A `chrome` mode may also name `hide_names`: the capture then
  hides every node with one of those names, and what is under it. `panels`
  scores only the scene nodes in `nodes` against only the frame depths that
  place them. The tool and the capture scene both read
  this file, so a new entry does not change the tool.
  `just compare-screen --list` prints the entries.
- **The config types no SWF number.** The tool reads the scene's timeline, its
  frame label and the depth of each `panels` node from `SCENES` in
  `dev/urchin_dev/swf/extract/screen_rects.py`, so the scene has to be there
  first, as the rect test already needs. A `panels` node has to be a piece
  that `SCENES` places by a depth of the frame, with no `instance` and no
  `inner_depth`.
- **How to run it.**
  1. Run `just compare-screen <entry>`. It lists each capture that is missing,
     with the arguments and the path for it.
  2. For each one, call the godot-mcp `run_scene` tool on
     `res://dev/screen_compare/capture.tscn` with `embedded` true and those
     arguments, then `capture_screenshot` with that `savePath`. Each mode needs
     two captures, one over magenta and one over green. The pixels that are
     the same in both are the pixels the scene covers, and only those are
     scored.
  3. Run `just compare-screen <entry>` again. It prints p50, p90 and p99 of the
     largest channel difference, and the control's p99. It writes
     `<mode>_reference.png` and `<mode>_diff.png` beside the captures, in
     `tasks/screen_compare/<entry>/`, which is git-ignored.
- **The bar and the control.** A mode passes when its p99 is at or under its
  `bar` and the control is over the bar. The control scores the same capture
  against the reference moved 20 px to the right, so a bar that a wrong layout
  can pass fails the run. Write `"bar": null` in a new entry, and set the bar
  to the p99 of the first run that looks right in the diff image. The first
  entry, `victory_left_panel` in `panels` mode, scored p99 2 with the control
  at 30.
- **How run-time state is frozen.** The capture scene never starts the game.
  It instantiates the entry's scene alone, with no save, no battle and no host
  scene, waits one frame for the containers, and turns the scene's processing
  off. The scene then shows what its `.tscn` holds. ffdec runs no ActionScript,
  so the reference shows the frame as the timeline places it: empty slots and
  no data. A Screen or Window therefore has to show that same state when it is
  instantiated with no data. Do not add a second way to set state for a
  capture. If the scene needs data to draw a piece, score that piece in a
  `panels` entry without it, or leave it to the rect test.
- **What the port leaves out is stripped.** When an ADR leaves a character
  of the frame out of the port, name its depth in the scene's `left_out` in
  `SCENES`. `chrome` mode strips those characters from the reference. The
  title leaves out the Armor Games logo and copyright line this way (ADR 0002).
- **Hidden nodes keep their place.** The capture scene hides a node by making
  its own drawing clear (`self_modulate`), not with `visible`, because a hidden
  child leaves a `FloatBox` and the pieces after it would move. A node whose
  shader ignores `COLOR` stays visible, so check the capture.
- **Faces and dolls are left out.** The tool reads the scene's `face` and
  `doll` pieces from `test/fixtures/screen_rects.json` and removes them from
  the mask. The game sets each face and each doll from its data, and ffdec
  runs no ActionScript, so the reference cannot hold the same art. The
  `chrome` render of KRINMENU's `win` frame shows one face in all three rows.
- **Captures load as they are.** The godot-mcp captures are sRGB at the Stage
  size, 800x575. The tool refuses any other size.
- **The Store score is p99 63, with the 20 px control at 127.** The `store`
  entry sets `hide_names` (`ItemIcon`, `Highlight`, `Body`), which hides the
  item icons and the doll that the game sets from its data. In the diff, the
  seven empty ware slots are the largest error: the original hides them with a
  script and ffdec draws them, and the port hides them. The reference also
  has the 36 inventory slots on a white item sheet, which `compare_strip`
  (2064) takes out.
- **The Hub score covers static chrome.** The `hub` entry uses
  `test/fixtures/screen_rects/hub_chrome.tscn`: Prison art and the hotbar.
  `SCENES.compare_strip` removes the fade (2837), Windows, card, banners,
  tooltip, animated orbs and member bars from frame 181. Orb positions,
  scales and button rects are checked in all seven zone records instead.
  The score is p99 74, with the 20 px control at 195. It was 37 until the six
  hotbar squares moved 13 px down to the Steam build's row. The reference is
  the web build, which holds them higher, so the six squares are the whole
  rise in the diff. The rect test checks their place against the Steam build.
  Two more things in the diff are not port faults to fix here. The port draws
  the Options and Re-Spec icons at half alpha, and their behavior stays with
  their own tasks. ffdec cuts the zone fill's Glow off at a hard box,
  (496, 506.5) 269.25x31.75, when it renders the fill inside sprite 3149,
  whose placement has a DropShadow.
  Flash Player draws a soft glow there, as `references/sonny2_zone1_prison.png`
  shows, and so does the port, from the fill rendered alone. Do not re-extract
  `zone_fill.png` from the root frame to lower this score.
- **The Abilities score covers the panels and the ability pool.** The
  `abilities` entry scores `abilities_window.tscn` alone, with `hide_names`
  hiding the tree lines and nodes, the eight sockets, the pool's rows, the plus
  buttons and the scroll buttons. `SCENES.compare_strip` takes the tree (3100),
  the ring (3109), the plus buttons (3068 to 3071), their plates (3075) and the
  scroll buttons (3114, 3115) out of the reference. The port draws those as
  native Buttons and code-drawn nodes (ADR 0007), so the rect test checks them.
  The score is p99 61, with the 20 px control at 109. The backdrop's outer rim
  is most of it, as in the Store. On the pool's rect, (523.6, 274.2)
  217.35x133.05, the backing, the frame's fades and the inner shadow overlay
  score p99 2, with the control at 90 (julian-perge/urchin#238).
- **The Battle score covers the frame, not the fighters.** The `battle` entry uses
  `battle_scene.tscn` alone. `SCENES.compare_strip` takes the hall and its
  placeholder rigs, the sky, the fade, the clock, the pass and retreat buttons, the
  member rows and the status bars out of the reference, and `hide_names` hides the
  same parts in the port. It scores the panels, the Hall window's edge and the pass
  icon: p99 6, with the 20 px control at 86. The status bars are out because ffdec
  runs no script. It draws every right-hand bar as a left-hand one and every fill in
  the color of frame 1, so the rect test checks the bars part by part instead.
