# SWF art export and frame-label lookup: options for the overhaul

Date: 2026-11-07. Scope: two recurring pains in urchin's SWF pipeline.

- Pain 1, images: Flash draws vectors live with filters, clip masks and
  colorTransforms, so urchin exports PNGs through ffdec and fights filters,
  masks, AS-hidden characters, wrapper sprites and canvas recovery
  (CLAUDE.md:85-148).
- Pain 2, frame labels: which label, sprite and frame a piece of code selects
  is found by hand, by playing the Flash game beside the port.

Every claim carries a tag:

- **[measured]**: a command was run on this machine for this report. The
  command and its output are given, or the scratch file that holds them.
- **[source]**: read in source code or documentation. The file and line or the
  URL is given.
- **[guessed]**: reasoning that nothing here has checked.

Scratch work is in `~/tmp/2026-11-07-ffdec-research/`. Nothing in the repo was
changed except this file.

## Corrections (2026-11-07)

Drafting the overhaul issues re-checked this report against the source. The
body below is left as measured; these two points in it are wrong.

- Section 9, AS-hidden candidates: 13 load handlers set a `_visible` to
  false, but only 10 hide their own clip. The other 3 hide another instance:
  `blacker` and the `this["st" + krink]` children in sprite 3142, and
  `_root["p" + i + "BAR"]` in the battle conductor, 3389.
- Section 2, `-format sprite:svg`: the SVG is sized from the sprite's
  whole-timeline displayRect, not from the frame's own bounds
  (`FrameExporter.java:421-426` and `SVGExporter.java:199-205` at jpexs
  792d2c2).

The five working files that later issues start from are copied next to this
report, in `docs/research/2026-11-07-swf-export-and-labels/`: `swf_index.py`,
`index_web.json`, `Probe.java`, `montage.png` and `hook.as`. The paths below
point there. Everything else stays in the scratch folder.

## Summary

The SWF is small enough, and the AS1/2 bytecode regular enough, that most of
pain 2 can be automated. A 300-line stdlib Python parser reads every frame
label, placement, filter and code block straight from the SWF in 0.44 s, and
its tag counts match the ffdec XML dump exactly. ffdec's script export already
says which instance owns each script, so a label-to-sprite-to-frame-to-code
cross-reference can be generated and checked by tests. It does not need eyes.

For pain 1 the largest lever is ffdec's own Java library, not its CLI. A
40-line probe showed that the library exposes each placed instance's playhead
and visibility. Setting those reproduces what `gotoAndStop` and
`_visible = false` would have done, without editing the SWF and without running
ActionScript. It rendered the battle frame with the hall and sky on CHURCH and
on SNOW, where the CLI can only ever show WHITE NOVEMBER over SEA.

Ruffle runs AS2 (99% language and 82% API by its own tracking) and its desktop
build has a debug UI. The UI shows the character id, current frame label and
AVM1 path of any live clip. That makes it the best side-by-side tool to replace
the Flash game. It cannot be the asset renderer: it has no gradient glow,
gradient bevel or convolution filter, and its exporter renders only the root
timeline.

Godot's SVG import is ThorVG 1.0.3, and its only filter primitive is
`feGaussianBlur`. It draws filterless gradient-and-mask art close to ffdec, but
it drops or mangles every glow, bevel and drop shadow in ffdec's SVG output.

### Recommendation table

| # | Option | Pain 1 | Pain 2 | Cost | Confidence |
|---|--------|--------|--------|------|------------|
| 1 | Label cross-reference generated from the SWF binary, ffdec's AS export paths and data value sets (section 9) | Partial: also lists AS-hidden candidates and filter use per sheet | Yes | Low. Prototype exists; about 1-2 days to productionize | High (measured) |
| 2 | ffdec_lib Java driver: set `DepthState.isVisible` and `.time` instead of `-removeCharacter` copies and frame-1 renders | Yes | Partial: renders any label combination | Medium. Adds a small Java tool to the repo | Medium-high (measured on 1 frame, 3 label pairs) |
| 3 | Ruffle desktop debug UI as the side-by-side reference | Reference only | Yes, interactive | Low. One download | Medium (read in source, not run) |
| 4 | Runtime goto trace: ffdec `-replace` injects a `gotoAndStop` logging hook, run under Ruffle or the Flash debug projector | No | Yes, captures every dynamic target with its instance path | Low-medium | Medium. The injection is measured, the run is not |
| 5 | Ruffle `exporter` as an AS-correct ground-truth renderer | Verification only | Partial | Medium-high. Build from source; needs a harness SWF to pick a sprite | Low-medium (guessed workflow) |
| 6 | Adobe Flash Player 32 projector content debugger (trace to flashlog.txt) | Reference screenshots | Yes, with the hook from row 4 | Low download. Intel-only, needs Rosetta, which is reduced from macOS 28 | Medium |
| 7 | Godot SVG import (ThorVG) instead of PNG | Only for filterless art (buff icon sheet) | No | Low | High that filters fail (measured) |
| 8 | Unused ffdec CLI flags | Marginal (`useMsaaForExport`) | `-dumpSWF` is a fast text index; no label selection exists | Low | High (measured) |

Top three, in order: build #1 now, because it removes the manual label hunt and
its checks already catch known bugs. Prototype #2 for the asset classes that
fight AS-hidden characters or nested labels. Download Ruffle desktop (#3) and
use it with the trace hook (#4) as the ground truth for anything #1 cannot
resolve statically.

## 1. Facts about this SWF that decide the options

- **[measured]** Both SWFs are SWF version 9, ZLIB-compressed, 800x575 stage,
  449 root frames at 30 fps: `ffdec -header sonny-2-2900.swf` and
  `ffdec -header SONNY2.swf`.
- **[measured]** The game is AS1/2, not AS3. The dump's `FileAttributesTag` has
  `actionScript3="false"` (`dev/source_files/swf_xml/sonny-2-2900.xml`, line 7
  of the file). This matters for Ruffle, whose AVM1 is far more complete than
  its AVM2 API, and for frame labels, which AVM1 matches case-insensitively
  (section 5).
- **[measured]** The prototype parser `swf_index.py` reports 1571 sprites, 49
  sprites with labels, 1137 frame labels (1024 distinct names), 869 code blocks
  and 297 code blocks that call a goto. `rg -c FrameLabelTag` on the XML dump
  also gives 1137, and ffdec's script export has 869 files. Output:
  `docs/research/2026-11-07-swf-export-and-labels/index_web.json`.
- **[measured]** Filter placements, counted by the parser and cross-checked
  against `rg -c 'type="<NAME>"'` on the XML: Blur 20149 (XML 20149), Glow 2698
  (XML 2706; the gap of 8 is probably filters on DefineButton2 records, which
  the parser skips [guessed]), DropShadow 325, Bevel 127, ColorMatrix 127,
  GradientGlow 26. Clip masks: 62 placements (XML 62). ColorTransforms: 4805
  placements. Blend modes: 105 placements.
- **[measured]** Effects per labeled sheet, with each sprite's subtree walked
  recursively. Counts are placements summed over all frames, and the hall count
  includes the fighter rig 2676 that the extractor strips:

  | Sheet | Sprite | Filters | Masks | ColorTransforms | Blend |
  |-------|--------|---------|-------|-----------------|-------|
  | buff icons | 100 | none | 1 | 0 | 0 |
  | item icons | 2064 | Glow 170 | 1 | 22 | 0 |
  | ability icons | 2427 | Glow 115, DropShadow 1 | 2 | 0 | 0 |
  | faces | 2978 | Blur 17, Glow 6 | 1 | 77 | 60 |
  | zone hub | 3287 | Blur 24, Glow 23, ColorMatrix 42 | 1 | 17 | 0 |
  | battle hall | 3435 | Blur 5086, Glow 44 | 0 | 364 | 0 |
  | battle sky | 3454 | Blur 26 | 0 | 20 | 0 |
  | battle bottom bar | 3317 | DropShadow 17, Glow 2, Bevel 1 | 3 | 0 | 0 |

  1242 of the 1571 sprites have no filter or blend mode anywhere in their
  subtree.
- **[measured]** All 26 GradientGlow placements are in a single sprite, 3156
  (labels START, STOP). No extractor uses it today (`rg 3156 dev/urchin_dev`
  finds nothing).
- **[measured]** Goto calls in the bytecode: 119 `ActionGotoLabel` and 3
  `ActionGotoFrame` opcodes, and 0 `ActionGotoFrame2`
  (`count_gotos.py`). These 122 equal the 122 receiver-less `gotoAndStop(` and
  `gotoAndPlay(` calls in the decompiled AS. The other 316 calls have a
  receiver (`x.gotoAndStop(...)`), so they compile to method calls. The split
  matters for the runtime hook in section 7.

## 2. Option: better use of the ffdec CLI

Local ffdec is a master build from the clone at `~/DEV/git_repos/jpexs`
(commit 792d2c2, 2026-05-24), and reports itself as `v.0.0.0`. The XML dumps
in the repo were written by 26.2.1 (`_generator` attribute on line 5 of the
dump).

**There is no label-based selection. [measured]** `ffdec -help select` accepts
only numeric ranges with an optional `<characterId>:` prefix. Nothing takes a
label, so label-to-frame resolution stays on our side. The repo already does
it with `snapshot_timeline` (`dev/urchin_dev/swf/xml_lib.py`). Captured help:
`~/tmp/2026-11-07-ffdec-research/help_detail.txt`.

**ffdec never runs ActionScript during export. [source]** The only AS1/2
execution in ffdec is an experimental GUI-viewer feature,
`internalFlashViewer.execute.as12`, off by default (`ffdec -listconfigs`
prints `internalFlashViewer.execute.as12[false]`). It lives in the GUI's
`ImagePanel.executeFrame`
(`src/com/jpexs/decompiler/flash/gui/ImagePanel.java:5508-5531`). That method
runs only the current timeline frame's `DoAction` tags, not clip events and not
nested sprites. `rg internalFlashViewerExecuteAs12` finds no use in any
exporter. This confirms CLAUDE.md:91-107 at the source level.

**How nested sprites pick their frame. [source]** `Timeline.drawDrawable`
computes `dframe = time % drawableFrameCount`
(`libsrc/ffdec_lib/src/com/jpexs/decompiler/flash/timeline/Timeline.java:1161`),
where `time` is the placed instance's `DepthState.time` plus the parent's
time. A static render therefore shows each child at the number of frames since
it was placed, which is frame 1 for a child placed on the frame being drawn.
This is the mechanism behind "WHITE NOVEMBER over SEA"
(`dev/urchin_dev/swf/extract/verify_battle_screen.py:6-9`), and section 3 uses
it on purpose.

**Flags and configs that exist and are not used today:**

- `-dumpSWF` **[measured]**: prints the whole tag tree with nesting,
  `FrameLabel (name: "...")`, character ids and depths in 1.5 s, as 80534
  lines. That is a cheaper label index than the 143 MB `-swf2xml` dump if the
  repo wants to stay on ffdec output (`dumpswf.txt` in scratch).
- `-dumpAS2 -exportNames` **[measured]**: lists all 869 script names in the
  form `-replace` accepts (`/frame_1/DoAction`,
  `/DefineSprite_2427/frame_1/PlaceObject2_2241_11/CLIPACTIONRECORD onClipEvent(load)`).
  The path encodes the owning timeline, frame, placed character id and depth,
  which is what section 9 resolves `this` with.
- `-replace <in> <out> <scriptName> <file.as>` **[measured]**: recompiles AS1/2
  into a copy. It prints "Warning: This feature is EXPERIMENTAL" but
  round-trips (section 7).
- `-config useMsaaForExport=1` **[measured]**: changes 690 pixels of the Break
  ability icon at zoom 2 and smooths some edges. The aliased fringe on the
  clip-mask rim stays. A marginal gain.
- `-config svgExportGaussianBlur=1` **[source, measured]**: makes SVG blurs use
  `feGaussianBlur` instead of a `feConvolveMatrix` box blur
  (`AdvancedSettingsDialog.properties:676-677`). It matters only for the SVG
  route in section 8, where it does not rescue the result.
- `-format sprite:svg` **[measured]**: the SVG canvas is the frame's own bounds
  (57.85x48.7 px for Break). The PNG canvas is the timeline union (236x218 at
  zoom 2). The SVG output already carries `ffdec:characterId` on every `<use>`.
- `-export xfl` / `fla` **[guessed]**: writes a Flash Pro project whose symbol
  timelines name their layers and frame labels in readable XML. That is useful
  to browse, but it is another large derived artifact, and it carries nothing
  that the binary parser does not.
- `-enabledebugging -generateswd` **[source]**: writes an SWD so the Flash
  debug projector can step through AS1/2 (`ffdec -help enabledebugging`).
  ffdec's GUI acts as the debugger client (`debuggerPort[55556]`,
  `playerDebugLocation[]` in `-listconfigs`).
- `-removeCharacterWithDependencies` exists, but deleting dependencies is the
  opposite of what the mask rule in CLAUDE.md:99-103 needs.

Verdict: the CLI is close to exhausted for these pains. Its big gaps, no label
selection and no per-instance control, are filled by the library (section 3).

## 3. Option: ffdec's Java library driven directly

`dist/lib/ffdec_lib.jar` is the engine the CLI wraps. Java 25 (Temurin) is
installed, so a single-file program runs as `java -cp "dist/lib/*" Probe.java`
with no build step and no files written.

**API surface that matters. [source]**

- `new SWF(InputStream, boolean parallelRead)` (`SWF.java:2092`) and
  `swf.getCharacter(id)` (`SWF.java:1306`).
- `Timeline.getFrameWithLabel(String)` returns a 0-based frame
  (`timeline/Timeline.java:508`), and `Frame.labels` (`timeline/Frame.java:115`).
- `Frame.layers` is a `TreeMap<Integer, DepthState>` (`Frame.java:55`).
  `DepthState` has public mutable `characterId`, `instanceName`, `filters`,
  `isVisible` and `time` (`timeline/DepthState.java:54-134`).
- The renderer skips a layer whose `isVisible` is false
  (`Timeline.java:1678`), and `toImage` also takes an `ignoreDepths` list
  (`Timeline.java:1619`, `:1705`).
- `SWF.frameToImageGet(timeline, frame, time, ..., zoom, smoothing, aaScale)`
  renders one frame to an image (`SWF.java:5035`).

**Probe. [measured]** `docs/research/2026-11-07-swf-export-and-labels/Probe.java`
loads the web SWF and takes root frame 217 (label `KRINBATTLESCENE`). It hides
every root depth except 73 (sky, cid 3454) and 89 (hall, cid 3435, instance
`BATTLESCREEN`), and hides every nested placement of 2676 and 3312 (871
placements). Then it sets the hall's and the sky's `DepthState.time` to the
0-based frame of a chosen label. Output:

```
depth 89 cid 3435 name BATTLESCREEN label CHURCH -> frame 41 (time was 0)
depth 73 cid 3454 name null label CHURCH -> frame 28 (time was 0)
load 0.67s render 0.16s
```

`docs/research/2026-11-07-swf-export-and-labels/montage.png` shows three
correct-looking composites: the default (WHITE NOVEMBER over SEA), CHURCH over
CHURCH and SNOW over SNOW. That was a visual check only. The renders were not
diffed against `assets/backgrounds/battle/` or the layout JSON.

What this buys over the CLI:

- **AS-hidden characters per instance, not per character.** The repo now
  deletes 2241 and 2245 from a whole working SWF
  (`dev/urchin_dev/swf/prepare_extract_swf.py:38`) and hand-rolls another
  stripped copy per extractor (`zone_hub.py`, `battle_screen.py`). Setting
  `isVisible = false` on one placement hides exactly what the game's
  `onClipEvent(load)` hides, and leaves masks alone because a mask is a
  separate layer. **[source]**, with the mechanism measured on the battle
  frame.
- **`gotoAndStop` without ActionScript.** Setting `time` selects a child's
  frame by label, so composites at any label pair become available. The battle
  recomposition check could then cover all 10 hall and 9 sky labels instead of
  one pair. **[measured]** for 3 pairs.
- **One JVM for a whole run.** Each CLI call costs about 2 s of wall time
  (`-header` takes 1.4 s, a one-frame sprite export 2.0-2.4 s) **[measured]**.
  In the probe, loading took 0.7 s and each later render 0.15-0.9 s.

Caveats:

- **[source]** Setting `time` on an instance also shifts its descendants by
  the remainder (`dtime = time - dframe`, `Timeline.java:1163`). Setting it to
  exactly the label's 0-based frame gives remainder 0, so grandchildren render
  at their normal frame. Setting more than one level needs care.
- **[guessed]** The library API is not a stable public contract. The XML
  header itself warns that the structure "is not final", and the Java API
  carries no such promise at all. Pin the ffdec commit.
- It adds Java to a Python repo. The probe is about 70 lines. A driver that
  reads a JSON job list from Python (sprite, frame or label, hidden instances,
  zoom, output path) would keep the Python side as the orchestrator.

## 4. Option: parse the SWF directly in Python

**Prototype. [measured]** `docs/research/2026-11-07-swf-export-and-labels/swf_index.py` is a
PEP 723 script with no dependencies, about 330 lines. It decompresses the SWF,
walks tags recursively through DefineSprite, and records:

- FrameLabel (43), ShowFrame (1), ExportAssets (56).
- PlaceObject2 (26) and PlaceObject3 (70) with character id, depth, name,
  clipDepth, colorTransform, the filter list by type and the blend mode.
- DoAction (12), DoInitAction (59), DefineButton2 (34) condition actions and
  PlaceObject clip actions. Each is scanned for ConstantPool strings, Push
  strings, and GotoLabel and GotoFrame opcodes.

It runs in 0.44 s against 1.5 s for `-dumpSWF` and minutes of regex over the
143 MB XML. Every count checked against the XML matched (section 1).

Formats used, all **[source]** from the SWF spec v19
(https://open-flash.github.io/mirrors/swf-spec-19.pdf):

- FrameLabel is tag 43, "Label for frame" (PDF page 54).
- PlaceObject2's ClipActions are present if `PlaceFlagHasClipActions` is set
  (PDF page 38).
- ActionGotoFrame is 0x81 (PDF page 67) and ActionGoToLabel is 0x8C (PDF page
  69).
- ActionGotoFrame2 is 0x9F and stack based. If it is given a label that does
  not exist, "the action is ignored" (PDF page 85). This is why a mismatched
  label fails silently in the original instead of erroring.

Libraries considered:

- `pyswf` 1.5.4, last upload 2015-07-25 **[measured]** (PyPI JSON API).
  Unmaintained.
- `hsalf` 0.0.1, 2011. Dead.
- The Rust `swf` crate is maintained by Ruffle: 0.4.0, updated 2026-11-02
  **[measured]** (crates.io API). It parses everything, AVM1 included, but
  would need a Rust CLI or PyO3 binding.
- For the tags these two pains need, the stdlib parser is the cheaper
  dependency **[guessed]**.

Limits:

- It does not decompile. Resolving dynamic targets like
  `_root.Krin.zoneName[_root.Krin.sectionIn]` needs the decompiled text or
  data flow, so section 9 pairs the binary index with ffdec's AS export.
- Shape geometry is not parsed. That is fine because CLAUDE.md:85-90 says never
  to composite in Python anyway.

## 5. Option: Ruffle

**AS support. [source]** https://ruffle.rs/compatibility gives AVM1 at
"Language: 99%" and "API: 82%", and AVM2 at 90% and 82%. It does not say how
the percentages are computed. AVM1 frame labels are matched case-insensitively
("In AVM1, frame labels are case insensitive (ASCII).",
`core/src/display_object/movie_clip.rs:1230` at master 5701ce3223). Any label
cross-reference must lowercase labels and targets to match the game.

**Filters. [source]**

- Tracking issue https://github.com/ruffle-rs/ruffle/issues/15 (open, last
  updated 2025-05-09) checks Drop shadow, Blur, Glow, Bevel, Color matrix,
  Shader and Displacement Map. It leaves Gradient glow, Gradient bevel and
  Convolution unchecked.
- `render/wgpu/src/filters/` holds bevel, blur, color_matrix,
  displacement_map, drop_shadow, glow and shader, with nothing for the
  gradient filters (`gh api repos/ruffle-rs/ruffle/contents/render/wgpu/src/filters`).
- In this SWF that gap hits only sprite 3156 **[measured, section 1]**.

**Exporter. [source]** `exporter/` builds a `ruffle_core::Player` on an
offscreen wgpu `TextureTarget` (`exporter/src/exporter.rs:75-77`). It calls
`preload` and `run_frame` for each frame (`:108-118`), so ActionScript runs, and
captures with `capture_frame` (`:121-124`).

- Options (`exporter/src/cli.rs:68-100`): `--frames N|all`, `--skipframes`,
  `--scale`, `--width`, `--height`, `--force-play`, `--graphics`, `--power`.
- There is no option for a frame label, a character id or input injection.
- **[measured]** It is not shipped as a binary. The 2026-11-07 nightly and
  v0.7.1 (2026-10-07) release assets contain only desktop builds
  (`macos-universal.tar.gz`), web builds and the source zip
  (`gh api repos/ruffle-rs/ruffle/releases`).

**Scanner. [source]** `scanner/src/execute.rs` runs a renderer-less Player for
one frame and records parse and runtime errors. It is a compatibility smoke
test and does not render.

**Desktop debug UI. [source]** The Debug menu
(`desktop/src/gui/menu_bar.rs`) opens Stage, Root MovieClip, Movie, Movie List,
Domain List and "Search display objects". For a MovieClip, the tracking window
(`core/src/debug_ui/display_object.rs`) shows:

- Current Frame with its label, total frames, and a frame list with Scene and
  Label columns plus per-row Stop and Play (`goto_frame`).
- Character id with export name, instance name, AVM1 path, depth, clip depth,
  world and local matrix and bounds, the filter list and a Visible toggle.

That is the information the user now collects by watching the Flash game, on
live game state. Desktop CLI options (`desktop/src/cli.rs`) include `-P`
flashvars, `--frame-rate` and `--spoof-url`. There is no screenshot or record
flag.

**Trace output. [source]** `trace()` goes to the `tracing` crate at INFO with
target `avm_trace` (`core/src/backend/log.rs`). Running desktop with
`RUST_LOG=avm_trace=info` should therefore print traces to stderr
**[guessed: env-filter wiring in desktop not read]**.

**Automated input exists only in the test harness. [source]** The repo's test
framework drives SWFs with `input.json` events (`MouseMove`, `MouseDown`,
`KeyDown`, `Wait`, and others; `tests/input-format/src/format.rs`). It
captures images at given ticks via `test.toml` `[image_comparisons]` and
compares trace output with `output.txt` (`tests/README.md`). That could script
a fixed path through the game and capture ground-truth screens, but it means
building Ruffle and placing tests in its tree **[guessed]**.

**What to test after downloading** (source
https://github.com/ruffle-rs/ruffle/releases, asset
`ruffle-nightly-YYYY_MM_DD-macos-universal.tar.gz`; universal, so native on
arm64):

1. Does `sonny-2-2900.swf` reach the battle screen and the zone hub without
   AVM1 errors in the log?
2. In the debug UI, does the hall instance `BATTLESCREEN` (cid 3435) report
   the label the battle data says? This checks section 9's resolution rules.
3. Do the ability icons, which use Glow and a clip mask, look like Flash? This
   checks Ruffle as a visual reference.
4. Load the hooked SWF from section 7 and confirm that GOTO lines appear in the
   log.
5. Only if 1-3 pass, build `exporter` (`cargo build --release -p exporter`) and
   test it as a batch reference renderer with a harness frame script (section
   7) that sets `_root.Krin` state and jumps to a labeled root frame.

## 6. Option: Adobe Flash Player debug projector on macOS

**Still downloadable. [measured]**
`curl -sI https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flashplayer_32_sa_debug.dmg`
returns HTTP 200, 10169829 bytes, last-modified 2020-12-08 (HEAD only, nothing
downloaded). The URL list and the warning that Adobe may pull it at any time
come from https://gist.github.com/joshtynjala/633fbaca5733a889da31498bdbf45dd6,
which says "As of September 2026, these URLs were still active". Mirror:
https://archive.org/details/Adobe_Flash_Player_Complete_Collection.

**Platform.** This machine is arm64 on macOS 27.2 with Rosetta present (`oahd`
is running) **[measured]**. The projector is Intel-only
(https://doesitarm.com/app/flash-player) **[source]**. Reports say macOS 27 is
the last release with full Rosetta 2 and that macOS 28 keeps it only for
certain older games
(https://www.macrumors.com/2026/06/10/macos-golden-gate-last-to-support-intel-apps/,
https://www.papercut.com/kb/Main/macos-rosetta-transition-end-of-life/)
**[source, secondary]**. The projector is a working option for about one more
macOS cycle. Treat it as a way to capture a corpus now, not as a long-term
tool.

**Trace capture. [source, community docs]**

- Put `mm.cfg` in `~` with `TraceOutputFileEnable=1` and
  `ErrorReportingEnable=1`.
- Output goes to `~/Library/Preferences/Macromedia/Flash Player/Logs/flashlog.txt`.
- Only the debug player honors it.
- Sources: https://github.com/mozilla/shumway/wiki/Trace-Output-with-Flash-Player-Debugger
  and https://docs.unity3d.com/450/Documentation/Manual/flash-debugging.html.
  Adobe's own page is gone.

**What it gives.**

- Real Flash rendering, so gradient glow and every other filter is right.
  Screenshots via macOS `screencapture` are the ground truth for pain 1.
- With the section 7 hook, a goto log from the real player.
- ffdec's GUI can attach to it as an AS1/2 debugger with breakpoints after
  `-enabledebugging -generateswd`.

**What to test after downloading:** that the projector launches under Rosetta
on macOS 27.2 and that `flashlog.txt` fills from the hooked SWF. Nothing found
confirms the debug projector specifically on Apple silicon. Flashpoint reports
Intel projectors working through Rosetta
(https://flashpointarchive.org/datahub/Mac_Support).

## 7. Option: instrument the SWF to log every goto at runtime

This works with Ruffle or with the debug projector, and is the cheapest way to
see dynamic targets that static analysis cannot resolve.

**Injection. [measured]** `docs/research/2026-11-07-swf-export-and-labels/hook.as`
(14 lines) overrides `MovieClip.prototype.gotoAndStop` and `gotoAndPlay` with
wrappers. Each wrapper calls
`trace("GOTO\t" + kind + "\t" + this + "\t" + this._currentframe + "\t" + target)`
and then the original. The hook is prepended to `/frame_1/DoAction`:

```
ffdec -replace sonny-2-2900.swf instrument/sonny_traced.swf "/frame_1/DoAction" instrument/frame1.as
```

That took 2.3 s. A fresh `-export script` of the result against a same-version
export of the original differs only in `frame_1/DoAction.as`, and that file's
tail after the 17 injected lines is identical. The repo's committed
`action_script/` differs from a fresh export by CRLF line endings only
(`as_base/scripts/Border.as` checked).

**Coverage. [measured]** The wrapper sees the 316 receiver calls, which
compile to method calls. Ruffle declares both methods on `MovieClip.prototype`
as `DONT_ENUM | DONT_DELETE`, not read-only
(`core/src/avm1/globals/movie_clip.rs`, PROTO_DECLS) **[source]**, so the
override should take effect there. Overriding the prototype also works in
Flash Player AS2 **[guessed: widely used idiom, not verified here]**. The 122
receiver-less calls are `ActionGotoLabel` and `ActionGotoFrame` opcodes that
bypass the prototype. They all have literal targets on their own timeline, so
the static index resolves them without the hook.

**Output.** `this` stringifies to the AVM1 path (`_level0.combatScript.inner`).
Joining that path against the static placement-name tree turns each log line
into (sprite id, label, frame).

## 8. Option: render vectors in Godot instead of PNGs

**What Godot 4.7.2 bundles. [measured, source]**

- `Godot --version` prints `4.7.2.stable.official.ed1daf0bf`.
- Its `thirdparty/README.md` at tag `4.7.2-stable` lists ThorVG 1.0.3.
- `update-thorvg.sh` enables only the SVG and PNG loaders and the software
  rasterizer.
- The ThorVG 1.0.3 SVG loader registers `mask`, `clipPath`, `symbol`, `use`,
  `filter` and exactly one filter primitive, `feGaussianBlur`
  (`src/loaders/svg/tvgSvgLoader.cpp:2141-2168` at tag v1.0.3), plus linear and
  radial gradients (`:2457`, `:2741`).
- Godot's docs say SVGs are "rasterized at import-time", that text must be
  converted to paths, and that complex vectors may not render correctly
  (https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).
- `DPITexture` (experimental) re-rasterizes an SVG at runtime to match
  oversampling (https://docs.godotengine.org/en/stable/classes/class_dpitexture.html).

**What ffdec emits for filters. [source]**

- `SvgFiltering.java` builds Flash filters from `feFlood`, `feComposite`,
  `feOffset`, `feColorMatrix`, `feComponentTransfer`, `feConvolveMatrix` and,
  with the config above, `feGaussianBlur`.
- ThorVG supports only the last of these, so a Glow, Bevel or DropShadow
  cannot survive the trip.

**Experiment. [measured]** A minimal Godot project in scratch
(`godot_probe/probe.gd`) calls `Image.load_svg_from_string(svg, 2)` on ffdec's
SVG for two sprites and compares the result with ffdec's PNG of the same frame.
Both images were cropped to their alpha bbox and registered at the best offset
within plus or minus 2 px. Values are the max-channel difference over drawn
pixels.

| Asset | Effects | p50 | p90 | p99 | Visual |
|-------|---------|-----|-----|-----|--------|
| Break ability icon (2427 frame 46) | Glow, clip mask, radial gradients | 12 | 76 | 249 | Mask and gradients right; glow halo missing |
| Same, `svgExportGaussianBlur=1` | as above | 21 | 171 | 255 | Streak replaced by a blur that escapes the mask |
| Buff icon ADRENALINE4 (100 frame 34) | clip mask only | 0 | 26 | 73 | Same shapes; edges differ |

Montages: `svgtest/montage.png` and `svgtest/montage_buff.png`.

Verdict:

- SVG through Godot is viable only for filterless sheets. In this SWF that is
  the buff icon sheet. The tables in section 1 show glow, blur or a
  colorTransform on every other sheet the port uses.
- Even there, p99 73 is well above the repo's battle recomposition bar of p99 8
  (`verify_battle_screen.py` header). The gain is resolution independence, not
  fidelity.
- Runtime vector addons do not change this. FlashToGodotExport states that
  filter effects are not supported in its export
  (https://github.com/krys64/FlashToGodotExport), and the SVG addons sit on the
  same SVG feature set.

**[guessed]** If resolution independence is the goal, a 4x/5x PNG plus Godot's
mipmaps or a `DPITexture` for the few filterless sheets is the realistic
ceiling.

## 9. Proposal: automated label cross-reference

Goal: one generated file that answers, for every label, which sprite and frame
it is, which code can select it, and from what data, with tests that fail when
the port and the SWF disagree. It is built from three sources, all already on
disk or producible in seconds.

### Inputs

1. **SWF binary index** (section 4): `labels(sprite, export_name, label, frame)`,
   `placements(owner, frame, depth, cid, instance_name)`,
   `code_blocks(owner, frame, kind, placed_cid, depth, strings, goto_opcodes)`,
   plus per-sprite effect counts. 0.44 s.
2. **ffdec AS export paths** (`dev/source_files/action_script/`). The path
   carries the code's owner and, for clip actions, the placed character:
   `frame_217/PlaceObject2_3435_89/CLIPACTIONRECORD onClipEvent(load).as` is
   code running on cid 3435 at depth 89 of root frame 217. A regex over the
   decompiled text extracts each goto site as (receiver expression, target
   expression). **[measured]** 438 sites: 322 string literals, 56 numeric
   literals, 60 dynamic (`goto_calls.txt`).
3. **Value sets** for dynamic targets, joined from data the repo already has:
   - `converted_json/battles.json` `zone_background` and `sky_background`.
   - `KrinLang.ENGLISH.ITEMNAME`, ability and buff names.
   - `Krin.zoneName`.

   A small hand-kept table maps an expression to its value source, for example
   `_root.Krin.ZoneBG -> battles[].zone_background`. Only this mapping is hand
   written, and the tests check it.

### Resolution rules, in order

1. Receiver-less goto (a GotoLabel or GotoFrame opcode): the target is the
   code's own timeline (the owner).
2. `this.` in a clip action: the placed cid from the path.
3. `this.` in a frame script: the owner.
4. Named receiver (`inner.`, `_root.KrinToolTipper.inner.`): walk instance
   names through `placements` from the owner or from root. If a name appears on
   several frames with different cids, emit all of them and flag it.
5. Computed names (`this["thing" + i]`): match by prefix against instance
   names, and flag the result.
6. Anything left: list it as unresolved for manual review.

Compare labels case-insensitively, because AVM1 does (section 5).

### Outputs

- `dev/converted_json/label_xref.json` with one record per (sprite, label):
  frame, export name, referencing sites (file path, receiver, literal or
  value-set name) and whether the port consumes it.
- A generated Markdown table for reading, so the side-by-side hunt becomes a
  lookup.
- Optionally, generated GDScript constants for the labels the port uses, so no
  label string is typed by hand.

### Checks that become tests

Each check below was run once for this report, against data already in the
repo.

- **Value-set coverage**: every value a dynamic goto can take is a label of its
  target sprite. **[measured]** The hall and sky pass: all
  `zone_background` values are labels of 3435 and all `sky_background` values
  are labels of 3454, with no unused labels on either. For item names against
  2064, case-insensitive, 4 of 316 have no label: `Tool` (id 1) and
  `Golden Crowbar`, `Golden Pipe`, `Golden Axe` (681-683). The repo found this
  by hand (`KNOWN_GAPS.md:115`, `NEXT_PHASES.md:161`). A case-sensitive check
  wrongly adds `White T-shirt`, which the label `White T-Shirt` serves in AVM1.
- **Reachability**: labels no code string names and no value set covers.
  **[measured]** 40 labels are never named anywhere in the bytecode
  (case-insensitive). Among them is `3287:CASINO`, which matches the
  hand-derived note in `zone_hub.py:17` that no zone reaches it. Others, such
  as `2427:Electro Bolt` and buff labels on 100, are probably reached through
  `data_json` values rather than code **[guessed]**. That is why reachability
  must union code strings with value sets before it reports anything.
- **AS-hidden candidates**: clip-load handlers that set their own `_visible` to
  false. **[measured]** There are 13 such files. The list includes
  `DefineSprite_2427/.../PlaceObject2_2241_11` (the cooldown disc stripped in
  `prepare_extract_swf.py`) and `DefineSprite_3317/.../PlaceObject2_3312_7`
  (the member bar container behind the "Thurman McPown" bug, CLAUDE.md:113-118).
  Some hide conditionally, for example 3312 only when `Krin.BattlePick == 2`,
  so this is a review list, not an automatic strip list.
- **Runtime diff** (after section 7): every (instance path, target) the trace
  log records must resolve to a known (sprite, label). Anything else is a
  resolution gap.

### Effort

**[guessed]** One to two days. The parser exists. The work is the receiver
resolver, the value-set mapping and the tests. Keep it serial and
dependency-free like the rest of `dev/urchin_dev`.

## 10. Open questions

- Does Ruffle run this SWF to the battle and hub screens without AVM1 errors?
  Not run (download needed). This decides whether #3 and #4 rest on Ruffle or
  on the Intel-only projector.
- Does the library `time` trick hold for labels whose frames contain children
  that are themselves mid-animation (cutscenes, VFX)? Measured only on the hall
  and the sky.
- Should the overhaul still commit the 143 MB XML dumps once the binary index
  and the library driver exist? Nothing in this report needs them, but five
  extractors use `snapshot_timeline` today.
- Is 4x/5x PNG still the right target for the battle hall, whose subtree
  carries 5086 Blur placements? Many come from the stripped fighter rig; the
  split was not measured.
- Which sprite is 3156 (gradient glow, labels START and STOP), and does the
  port need it? It is the one place where both Ruffle and the ThorVG route
  would be wrong.
- Does the 26.2.1 `all:` selection NullPointerException noted in
  `ability_icons.py:94-97` still happen on the local master build? Not
  retested.

## 11. Side effect to report

Running `cargo --version` to check for a Rust toolchain triggered rustup's
auto-install. It downloaded and installed `stable-aarch64-apple-darwin` (rustc
1.99.1) into `~/.rustup/toolchains/`. This was unintended and breaks the
no-download rule of this task. Remove it with
`rustup toolchain uninstall stable` if it is not wanted, and set
`RUSTUP_AUTO_INSTALL=0` to stop it recurring.

## Appendix: scratch files

All under `~/tmp/2026-11-07-ffdec-research/`, except the five files copied into
`docs/research/2026-11-07-swf-export-and-labels/`, which are marked:

- `docs/research/2026-11-07-swf-export-and-labels/swf_index.py` and
  `docs/research/2026-11-07-swf-export-and-labels/index_web.json`: binary
  parser and its full output (labels per sprite, label references,
  unreferenced labels).
- `count_gotos.py`: goto opcode counts.
- `ffdec_help_plain.txt`, `help_detail.txt`, `listconfigs.txt`,
  `as2_names.txt`, `dumpswf.txt`: ffdec CLI captures.
- `goto_calls.txt`: every distinct goto call in the decompiled AS with its
  count.
- `docs/research/2026-11-07-swf-export-and-labels/Probe.java` and
  `docs/research/2026-11-07-swf-export-and-labels/montage.png`: ffdec_lib
  probe and the montage of its renders. The single renders stay in scratch as
  `javaprobe/*.png`.
- `instrument/`: goto hook, instrumented SWF and script round-trip exports.
  The hook is copied as
  `docs/research/2026-11-07-swf-export-and-labels/hook.as`.
- `svgtest/`, `godot_probe/`, `compare.py`: SVG versus PNG experiment.
- `thorvg_*.cpp|h`, `ruffle_*.rs`: upstream source snapshots read for this
  report.
