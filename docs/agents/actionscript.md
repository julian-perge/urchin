# ActionScript and game data

Where the original game's logic and data live, and the mistakes this project
has already made reading them.

## Where the authorities are

- `dev/source_files/action_script/` is the full ffdec script export and the
  authority for game logic. `action_script_curated/` holds commented excerpts.
- `dev/data_json/` is a runtime capture of the Steam build's live `_root`
  arrays, not an export. No script produces it and none can. See
  `SWF_DIFFERENCES.md`.
- The original's English text is in `dev/converted_json/strings.json`.
  `just convert-strings` (`uv run convert_strings`) writes it from the
  `KrinLang.ENGLISH` table in `frame_1/DoAction.as`, with each array index
  equal to the AS index. GDScript reads it through `Strings`, as in
  `Strings.system(17)`, and does not type the text as a literal.
- `DECODED_ALGORITHMS.md` holds behavior already decoded from the AS so it
  never has to be re-derived. Check it before reading the AS yourself.
- Open work is tracked in GitHub issues, not in a file. A deliberate departure
  from the original is an ADR in `docs/adr/`. What a finished task found about
  the original goes into `DECODED_ALGORITHMS.md`, or into `SWF_DIFFERENCES.md`
  when it is about the two builds.

## Find the place before you read it

Run `just lookup <query>` before `rg` on the export. `just as-lookup` is an
alias of it. One lookup gives what `rg 'function X'` and a `sed -n` of a line
range take several calls to find. It prints one answer for each kind of query:

- A function name, such as `executeMove`: the file and line range, the source
  lines (the outline of its blocks when the function has more than 120 lines),
  each caller, each function it calls with the place that defines it, and the
  globals it writes and reads.
- A global name, such as `perKSuccess`: each line that writes it and each
  function or script that reads it.
- An export path, or the unique end of one, such as `frame_42/DoAction_8.as`:
  the same answer for the script, with the functions it defines.
- A path with a line, such as `frame_42/DoAction_8.as:82`: the function that
  holds the line and the chain of blocks around the line.
- A string value, such as `Angry_Dux`: each line of the export and of the
  GDScript that holds that string.

A name that is a function in both languages prints one section for each. Each
answer ends with `ports`, the GDScript comments that cite that range, so it
shows where the port already implements the code. It then lists `facts`, the
sections of `DECODED_ALGORITHMS.md` that cite the range. A fact is a heading and
its line, so open the file at that line.

The lookup is for navigation only. Read the original lines before you port or
decide anything, because the index is not an authority on behavior. It matches
a caller by name, and it does not resolve which timeline a bare name such as
`AVGNUMC` lands on.

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
  got 10 of those 16 wrong (`8c293c8`).
- **A blank data field does not mean the game shows nothing.** Check whether
  the original reads that field at all. Every tree passive's
  `25_tooltip_description` is 0, which was recorded as a data fact and asserted
  in a test; the original never reads it, and takes the text from
  `KrinLang.ENGLISH.BUFFSAY` instead (`46d16da`).
- **Player-facing text comes from `KrinLang.ENGLISH.*`, not the item or buff
  record.** `ITEMNAME[id]` overwrites the item record's own name at load
  (`frame_42/DoAction_16.as`). `internal_name` disagrees with what the game shows
  and nothing in the icon path reads it; a reported collision between four item
  pairs was a read of that field and there was nothing to fix (`dc4c5b2`).
- **Check what an id means before treating it as an index.** `buffId` looks
  numeric and is a string name: buffs register as `_root["KRINBUFF" + name]`.
  Reading it as a frame number matches by chance for 9 of 410 buffs and sends
  every id past 400 to a placeholder (`cfaedb5`).
- **Watch off-by-one in rank tables.** `BUFFSAY` is 0-indexed for rank 1 and
  the original clamps its index up from -1, so rank 0 and rank 1 both show the
  first entry (`46d16da`, `f068f87`).
- **A name in a function body can be a parameter, not a global.** ADR 0005
  said `buffTicker` plays the Shield clip through `IDKT`, a global that
  `executeMove` last set. `IDKT` is a parameter of `executeMove` and is never
  assigned, so the original plays no clip. Before you write that a variable is
  a global, find its declaration and run `rg -uu 'NAME\s*=[^=]'` over
  `dev/source_files/action_script` for an assignment (`c8733b7f`).
- **`for..in` over an array walks its keys newest first.** An array literal or a
  `push`-built list walks from the last index down, and a list built by walking
  another one with `for..in` walks the other way. Port each loop from the rule
  in DECODED_ALGORITHMS.md, "for..in order over arrays", which two players
  measured (#38).
- **Flash folds case in linkage lookups.** `KRIN.MAGICBOLT` and
  `Krin.Magicbolt` are the same clip; resolve export names case-insensitively
  (`4ccdb39`).
- **An export name can resolve to a wrapper.** "KrinTrail" is sprite 3, a
  one-frame wrapper whose only frame shows its child's alpha-0 keyframe, which
  is why that clip extracted fully blank. The real 33-frame content is sprite
  2, which has no export name and is only reachable by id (`4ddee5c`).
- **Battle ids in the raw dump are not all correct.** All nine
  `battleCreationID` resets relabel the battle just populated instead of the
  next one, so 2, 55, 109, 212, 308, 409, 513, 603 and 703 came through as
  49, 99, 199, 299, 399, 499, 599, 699 and 999. `battles.py`'s
  `MISLABELED_BATTLE_IDS` corrects all nine at conversion time. `c13cff0`
  corrected only 109, 409 and 513, which left the zone 2, 3, 6 and 7 bosses
  and the tutorial unable to load.
- **A control can sit on the root timeline, outside the clip it belongs with.**
  The cutscene plan read the four cutscene sprites, found no skip button in
  them and recorded that the original has none (`e7eff3a8`). Button 3468 is
  placed once on the root timeline, at frame 263, and every root frame to 448
  shows it, which covers all seven CS_ labels (`d3da2ff5`). When a screen seems
  to lack a control, read what the root frame places around the clip as well.

## Tracing the original

A Traced run records what the original does while it runs, so a port check
compares against a saved Trace log and not against a person who watches the
game. The terms are in `GLOSSARY.md` under "Tracing the original", and the
record is `docs/adr/0008-trace-the-original-with-probes.md`. The code is
`dev/urchin_dev/swf/trace.py`.

### The recipes

- `just trace-swf <web|steam>` builds a Traced copy. It reads the build's SWF
  in `URCHIN_SWF_DIR` and each Probe in `dev/probes/`. It exports the build's
  own `frame_1/DoAction.as` with ffdec, puts the Probes in front of it, and
  writes the result with `ffdec -replace` to
  `$URCHIN_SWF_DIR/traced/sonny-2-2900.swf` or
  `$URCHIN_SWF_DIR/traced/SONNY2.swf`. It prints that path. The recipe exports
  each build itself, because the repo holds only the web build's scripts.
- `just trace-run <web|steam> <flash|ruffle>` builds the Traced copy, plays it
  in one player and waits until you quit the player. It then saves the raw
  player log as `references/traced_runs/<build>_<player>.txt` and replaces an
  older file. It prints the number of GOTO lines and exits 1 when the log has
  no `HOOK<tab>installed<tab>true` line. The players come from
  `FLASH_DEBUG_PLAYER` and `RUFFLE_BIN`, with defaults in `trace.py` and
  `.env.example`. It needs macOS.
- `just trace-diff <log a> <log b>` reads two Trace logs and prints the
  distinct gotos that only one of them has, in two sorted groups. Each line
  is kind, clip, total frames, target, and `moved` or `stayed`. `moved` means
  that at least one call of that goto changed the frame. Order and count are
  ignored, because fights roll dice. It needs no SWF, no ffdec and no label
  data.

### The four Traced runs

Each run starts a new game and presses SKIP on each Cutscene as soon as it
shows. The run name is `<build>_<player>`.

| Traced run | Tutorial | Route | Battles |
| --- | --- | --- | --- |
| `web_flash`, `steam_flash` | on | CS_INTRO, battle 2, CS_INTRO2, battle 100, the zone 1 hub | 2, 100 |
| `web_ruffle`, `steam_ruffle` | off | CS_INTRO2, battle 100, the zone 1 hub | 100 |

`trace-run` takes no Tutorial flag. The player picks the Tutorial in the game.
A lost fight ends the run, so start it again.

The Trace logs go to `references/traced_runs/<run>.txt`. Take a screenshot in
each battle and at the hub, and save them next to the log as
`<run>_battle2.png`, `<run>_battle100.png` and `<run>_hub.png`. In each Ruffle
run, open the Debug view on `BATTLESCREEN` during battle 100 and record the
current label. The full plan is in `spec/5-trace-the-original.md`.

### Facts a run needs

The sessions of #5 and #304 measured these, except where a fact says
otherwise.

- **`flashlog.txt` starts empty at every launch of the Flash debug player.**
  `trace-run` copies it when the player quits. A second launch before that
  copy loses the first run's log. The player writes the file only when
  `~/mm.cfg` has `TraceOutputFileEnable=1`, and `trace-run` stops with a
  message when that line is missing.
- **Ruffle opens a SWF only inside its sandbox container.**
  `/Applications/Ruffle.app` has the app-sandbox entitlement. A SWF path
  outside `~/Library/Containers/rs.ruffle.ruffle/Data/` fails to open, and
  Ruffle 0.7.1 then panics in a folder picker. So `trace-run` first copies
  the Traced copy to
  `~/Library/Containers/rs.ruffle.ruffle/Data/urchin_traced/`. Ruffle writes
  the `trace()` lines to stdout as `INFO avm_trace: ...`, with colour codes
  in front. `trace-run` saves stdout and stderr together.
- **Only one Traced run can play at a time.** Two runs share the screen, and
  two Flash runs share `flashlog.txt`. This follows from the facts above. No
  session tried two runs at once. Before you start a run, check that no Flash
  player or Ruffle process is running.
- Flash reports `_currentframe` 0 for an empty clip and Ruffle reports 1.
- **`trace-run` overwrites the committed Trace log.** A run for a logic Probe
  still saves to `references/traced_runs/<build>_<player>.txt`. Copy its lines
  to a file of their own, such as `forin_web_flash.txt`, and restore the Trace
  log with `git checkout -- references/traced_runs/` (#38).
- **The game stops for a click before frame 42.** It waits on the language
  screen (root frame 1) and on CLICK TO PLAY (frames 4 and 5). The #38 runs
  used a throwaway Probe file that ran the English button's code
  (`DefineButton2_298`) and called `_root.play()` on those frames. It was not
  committed, because it changes what the game does.
- **A throwaway Probe can capture what the stage shows.** For #411 it jumped
  to a `CS_` label from `mainMenu`, stopped the animation on the target frame,
  waited 3 frames, drew the stage with
  `new flash.display.BitmapData(800, 575, false, 0).draw(_root)`, and traced 20
  rows of hex pixels a frame, so no frame ran long enough for the debug
  player's slow-script warning. Nine captures made a 25 MB `flashlog.txt`, and
  a short script turned the `ROW` lines back into PNGs. The SWF is version 9,
  so AS2's `BitmapData` is there. The capture needs no screen recording.
- **A throwaway Probe can start a battle with no clicks.** For #39 it waited for
  the main menu (root frame 45), ran the Knight button's code
  (`DefineButton2_2735`), went to `optionsMenu` (frame 93), set
  `Krin.difficulty = 2` and `Krin.tutorOn = false`, and went to root frame 180,
  which sets `BattlePick = 100` and loads the battle. That skips only CS_INTRO2.
  On Heroic the player's half-turn passes by itself after 4 seconds, so the
  battle plays on with no clicks. The Probe is
  `references/traced_runs/cost_failure_probe.as`.
- **ffmpeg's `select=eq(n,N)` picks the wrong frame of a Theora clip.** In
  #411 it returned a frame of another shot of CS_CUT4. To read frame N of a
  clip, decode the whole clip as a stream and count the frames.

### Add a Probe

1. Write one plain ActionScript 1/2 file in `dev/probes/`. `ffdec -replace`
   compiles it, so use only what the original's own scripts use.
2. Pick its file name for its place. `trace-swf` puts the Probes in front of
   the frame script in name order, so `goto.as` runs before a file whose name
   sorts after it. Use a lowercase name. The order is by code point, so an
   uppercase name sorts before every lowercase one.
3. Do not change what the game does. Wrap a function, call the original with
   `apply(this, arguments)`, and only add `trace()` calls, as
   `dev/probes/goto.as` does. A Probe runs once, before the rest of frame 1. It
   cannot put a `trace()` inside a loop of a later frame script.
4. Start each line it traces with its own mark, not `GOTO<tab>` or `HOOK`.
   The parser reads every line that has `GOTO<tab>` as a goto record.
5. Run `just trace-swf web` and `just trace-swf steam`, and check that a fresh
   script export of each Traced copy differs from the build's export only in
   `frame_1/DoAction.as`. For the web build, in a scratch folder:

   ```
   ffdec -export script plain "$URCHIN_SWF_DIR/sonny-2-2900.swf"
   ffdec -export script traced "$URCHIN_SWF_DIR/traced/sonny-2-2900.swf"
   diff -rq plain traced
   ```

   `diff` must print one line, for `frame_1/DoAction.as`. Do the same
   for `SONNY2.swf`.
