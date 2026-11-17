# Spec: trace the original - V1

Source issue: [#5](https://github.com/julian-perge/urchin/issues/5).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md) and `docs/agents/actionscript.md`. Review standards are in [CODING_STANDARDS.md](../CODING_STANDARDS.md). The decision record is `docs/adr/0008-trace-the-original-with-probes.md`, and the terms are in `GLOSSARY.md` under "Tracing the original".

## Objective

Give the project a repeatable record of what the original does while it runs. A port check then compares against a committed Trace log. It does not depend on a person who watches the game.

The users are Julian, a build agent that plays a Traced run, and a later session that reads a Trace log or adds a Probe.

The work has five parts:

1. **The goto Probe.** `dev/probes/goto.as` logs every `gotoAndStop` and `gotoAndPlay` call that has a receiver.
2. **Three recipes.** `just trace-swf` builds a Traced copy. `just trace-run` builds it, plays it in one player and saves the Trace log. `just trace-diff` compares two Trace logs.
3. **Four Traced runs.** The web build and the Steam build, each under the Flash 14 debug player and under Ruffle, along one fixed route. The build agent plays them with computer use.
4. **One test.** `dev/tests/test_trace.py` checks the hub, hall and sky lines of each committed Trace log.
5. **Reports on the issue.** The `trace-diff` output for builds and for players, the result of the Ruffle Debug view check, and one new issue for each logic Probe.

## Assumptions

- The goto Probe works in all four cases. The idea session of #5 measured it: each case logged `HOOK installed true` and the GOTO lines of a self-test clip. No run went past the first screen.
- `ffdec -replace <in.swf> <out.swf> "/frame_1/DoAction" <file.as>` replaces the first frame script. The research ran it in 2.3 s (`docs/research/2026-11-07-swf-export-and-labels.md`, section 7).
- The Steam build's first frame script is not in the repo. Its export has 825 scripts, and the web export has 869. So the recipe exports each build's own `/frame_1/DoAction` before it adds the Probes.
- The Flash debug player writes `trace()` lines to `~/Library/Preferences/Macromedia/Flash Player/Logs/flashlog.txt` when `~/mm.cfg` has `TraceOutputFileEnable=1`. The file starts empty at each player launch. `~/mm.cfg` exists on Julian's machine.
- Ruffle writes `trace()` lines as `INFO avm_trace: ...` with its default log filter. They go to stdout, not to stderr as this spec first said: #304 measured it with Ruffle 0.7.1. Each line starts with ANSI colour codes. The sandboxed `/Applications/Ruffle.app` (0.7.1) opens a SWF only inside `~/Library/Containers/rs.ruffle.ruffle/Data/`.
- The players are at `~/Games/Flashpoint_14/FPSoftware/Flash/Flash 14.app/Contents/MacOS/Flash Player Debugger` and `/Applications/Ruffle.app/Contents/MacOS/ruffle`. Both exist today.
- The hub clip is `_level0.KrinScreen` (sprite 3287) and the hall clip is `_level0.BATTLESCREEN` (sprite 3435). The sky clip (sprite 3454) has no instance name, so its path is `_level0.instanceN`. `label_xref.json` has only one goto on each of these three clips: the load handlers, records with `via` of `zone_name`, `zone_background` and `sky_background`.
- A Flash log line has the form `GOTO<tab>stop<tab>_level0.__t<tab>1<tab>0<tab>1<tab>0` (read from the `flashlog.txt` of the idea session). The fields after `GOTO` are kind, clip path, total frames, frame before, target and frame after.
- Names and paths marked "proposed" are this spec's choice.

Guesses, which the first Traced runs test:

- Ruffle puts a prefix before `GOTO` on each line and keeps the tabs. The parser reads from the first `GOTO<tab>` of a line, so the prefix does not matter.
- No other unnamed clip on the root goes to a label of sprite 3454.
- The Steam build uses the same hall, sky and hub labels as the web build for battle 2, battle 100 and zone 1. `battles.json` and `label_xref.json` come from the web build.
- The trace volume in a battle does not change the pacing.
- `instanceN` parts of a clip path are the same in two runs of one build.

## The goto Probe

`dev/probes/goto.as` holds the Probe of the idea comment on #5, unchanged. It replaces `docs/research/2026-11-07-swf-export-and-labels/hook.as`, which logged no frame after the goto and no `_totalframes`.

- It wraps `MovieClip.prototype.gotoAndStop` and `gotoAndPlay`, calls the original, then traces one `GOTO` line.
- It traces `HOOK<tab>installed<tab>true` once when it is in place.
- It does not see the 122 calls with no receiver. They compile to GotoLabel and GotoFrame opcodes, and all have literal targets.

A Probe must not change what the game does. A Probe file is plain ActionScript 1/2 that `ffdec -replace` compiles.

## The Traced copy

`just trace-swf <web|steam>` (entry point `trace_swf`, proposed):

1. Exports the scripts of the build's SWF from `URCHIN_SWF_DIR` to a temporary folder with ffdec, and reads its `frame_1/DoAction.as`.
2. Puts the text of each file in `dev/probes/`, in name order, in front of that script.
3. Runs `ffdec -replace` and writes `$URCHIN_SWF_DIR/traced/sonny-2-2900.swf` or `$URCHIN_SWF_DIR/traced/SONNY2.swf`.
4. Prints the path of the Traced copy.

The Traced copy differs from the build only by the Probes. The recipe does not remove line 4513 (`Stage.showMenu = false();`).

## The Traced run

`just trace-run <web|steam> <flash|ruffle>` (entry point `trace_run`, proposed):

1. Builds the Traced copy as `trace-swf` does.
2. **Flash.** Stops with a message when `~/mm.cfg` does not have `TraceOutputFileEnable=1`. Launches the debug player binary with the path of the Traced copy.
3. **Ruffle.** Copies the Traced copy to `~/Library/Containers/rs.ruffle.ruffle/Data/urchin_traced/` (proposed) and launches Ruffle with that path. It captures Ruffle's stdout and stderr together.
4. Waits until the player quits.
5. Saves the raw player log as `references/traced_runs/<build>_<player>.txt`. For Flash this is a copy of `flashlog.txt`. An existing file is replaced.
6. Prints the number of GOTO lines. It exits 1 when the log has no `HOOK<tab>installed<tab>true` line.

The recipe takes no `--tutorial` flag. The player picks the Tutorial in the game, and the run name says which runs have it.

The player paths come from `FLASH_DEBUG_PLAYER` and `RUFFLE_BIN` (both proposed), with the paths of the Assumptions as defaults. `.env.example` lists them. The recipe stops with a message on an OS other than macOS, and when a player binary is missing.

### The route

Every Traced run starts a new game and presses SKIP on each Cutscene as soon as it shows.

| Traced run | Tutorial | Route | Battles |
| --- | --- | --- | --- |
| `web_flash`, `steam_flash` | on | CS_INTRO, battle 2, CS_INTRO2, battle 100, the zone 1 hub | 2, 100 |
| `web_ruffle`, `steam_ruffle` | off | CS_INTRO2, battle 100, the zone 1 hub | 100 |

`battles.json` gives battle 2 the `WHITE NOVEMBER` hall under the `SEA` sky, and battle 100 the `JAIL` hall under the `JAIL` sky. `Krin.zoneName[1]` is `PRISON`.

The build agent plays each run with computer use. It takes a screenshot in each battle and at the hub, and saves them next to the log as `<run>_battle2.png`, `<run>_battle100.png` and `<run>_hub.png` (proposed). In each Ruffle run it opens the Debug view on `BATTLESCREEN` during battle 100 and records the current label.

A lost fight ends the run, and the agent starts the run again. When the agent cannot finish a run, it records on #5 where the run stopped and what blocked it, and Julian plays that run with the same recipe.

## The Trace log

A Trace log is the raw player log. `trace.py` reads only its `HOOK` and `GOTO` lines. Every other line stays in the saved file.

`parse(text)` returns one record for each GOTO line: `kind` (`stop` or `play`), `clip`, `total_frames`, `before`, `target` and `after`. It reads from the first `GOTO<tab>` of the line. A line with `GOTO<tab>` and the wrong number of fields raises an error that names the line number.

## The diff

`just trace-diff <log a> <log b>` (entry point `trace_diff`, proposed) prints the distinct diff records that one log has and the other lacks, in two sorted groups.

A diff record is (kind, clip, total frames, target, moved). `moved` is true when at least one occurrence of that (kind, clip, total frames, target) in the log changed the frame. It is false when the label is missing or the clip was already on that frame each time. The log alone gives `moved`, so the diff needs no label data and works for the Steam build.

Order and count are ignored, because fights roll dice and the picks differ. No test pins the output of a diff between real logs. #5 posts it:

- `web_flash` against `steam_flash`, and `web_ruffle` against `steam_ruffle` (builds).
- `web_flash` against `web_ruffle`, and `steam_flash` against `steam_ruffle` (players). These pairs differ by the Tutorial too, so the report says which records belong to CS_INTRO and battle 2.

Flash reports `_currentframe` 0 for an empty clip and Ruffle reports 1. `moved` hides that difference when the frame does not change.

## The test

`dev/tests/test_trace.py` reads `references/traced_runs/*.txt`. It reads no SWF and no XML dump.

**Which logs.** The test expects the four logs. A missing log passes only when the test file lists its run name in `MISSING` with the URL of the #5 comment that records where the run stopped. `MISSING` starts empty.

**For each log:**

1. The log has a `HOOK<tab>installed<tab>true` line.
2. **Hall.** The targets of the GOTO lines on `_level0.BATTLESCREEN`, in order, equal the `zone_background` of the run's battles in `battles.json`.
3. **Sky.** The targets of the `stop` lines on a `_level0.instanceN` clip whose target is a label of sprite 3454, in order, equal the `sky_background` of the run's battles.
4. **Hub.** The log has at least one GOTO line on `_level0.KrinScreen`, and every one has the target `Krin.zoneName[1]`. The test reads the name with `load_value_sets` of `label_xref.py`.
5. Each of these targets is in the `selects` of the `label_xref.json` goto record with the matching `via`: `zone_background`, `sky_background` or `zone_name`. The test finds the record by `via`, not by a typed id.
6. **Frame, web logs only.** The frame after each of these gotos equals the label's frame in the `labels` of `label_xref.json`, on the sprite that the value set names.

Labels compare without case, as the players do.

The run's battles (2 and 100, or 100) and the zone index 1 are the route. The test file holds them once, next to the run names. Every label and frame comes from `battles.json`, `label_xref.json` or the tracked export.

**Where the frame check is weak.** `WHITE NOVEMBER`, `SEA` and `PRISON` are frame 1 of their sprites, so a goto to a missing label would also leave the clip on frame 1. `JAIL` is frame 15 of the hall and frame 14 of the sky. Battle 100 is in all four runs, so each web log has one frame check that can fail.

## Commands

```
just trace-swf web                    builds $URCHIN_SWF_DIR/traced/sonny-2-2900.swf
just trace-run web flash              plays it, saves references/traced_runs/web_flash.txt
just trace-diff references/traced_runs/web_flash.txt references/traced_runs/steam_flash.txt
just pytest dev/tests/test_trace.py
just pytest
just gut
```

## Project structure

Follows `AGENTS.md`. New or changed locations (names proposed where the design comment does not give them):

```
dev/probes/goto.as                         the goto Probe, moved from docs/research/2026-11-07-swf-export-and-labels/hook.as
dev/urchin_dev/swf/trace.py                builds, runs, parses and diffs
dev/tests/test_trace.py                    unit tests of trace.py and the checks of the committed logs
references/traced_runs/<run>.txt           the four Trace logs
references/traced_runs/<run>_<place>.png   the screenshots
pyproject.toml                             trace_swf, trace_run, trace_diff
justfile                                   trace-swf, trace-run, trace-diff in a `trace` group, which require ffdec and java
.env.example                               FLASH_DEBUG_PLAYER, RUFFLE_BIN
docs/agents/actionscript.md                a "Tracing the original" section: the recipes, the route, how to add a Probe
AGENTS.md                                  one line under Commands, and the doc pointer names tracing
docs/research/2026-11-07-swf-export-and-labels.md   its three hook.as paths point at dev/probes/goto.as
GLOSSARY.md, docs/adr/0008-...             already in the working tree of main, not committed
```

`trace.py` uses `run()` of `urchin_dev/run.py` for ffdec, and `WEB_SWF`, `STEAM_SWF` and `SWF_DIR` of `urchin_dev`. It does not add a second ffdec wrapper.

## Code style

As in `label_xref.py`: a header comment that says what the file reads and writes, frozen dataclasses and stdlib only.

```python
@dataclass(frozen=True)
class Goto:
    kind: str
    clip: str
    total_frames: int
    before: int
    target: str
    after: int


def with_probes(frame_script: str, probes: Sequence[str]) -> str:
    return "".join(probe.rstrip("\n") + "\n" for probe in probes) + frame_script
```

The snippet shows style only.

## Testing strategy

Tests are pytest in `dev/tests/test_trace.py`. They pass on a checkout with no SWF, no ffdec and no player.

- **`with_probes`.** The result ends with the frame script unchanged, and the Probes come first in name order.
- **`parse`.** A fixture with Flash lines and Ruffle lines, lines of other kinds, and a GOTO line with a missing field, which must raise. The first Flash fixture lines are the ones in the Assumptions. The Ruffle fixture lines are replaced with real lines from the first Ruffle log.
- **The diff.** Fixture logs cover: the same gotos in another order and count give no difference, a goto in one log only shows on that side, and `moved` is true when one occurrence of several changed the frame.
- **`dev/probes/goto.as`.** The test reads the Probe file and checks that the field order of its `trace` call is the order `parse` reads. A changed Probe then fails a test before a run does.
- **The committed logs.** The checks of "The test" above.
- **Must-fail controls**, run once in the build and reported in the PR: change one hall target in a copy of a log, change the frame after the `JAIL` hall goto, delete a log without a `MISSING` entry, and delete the HOOK line. Each must fail. Run Python mutation checks with `PYTHONDONTWRITEBYTECODE=1`.
- **The recipes.** `trace-swf` and `trace-run` need the SWFs, ffdec and the players, so no test runs them. The build runs `just trace-swf` for both builds and reports that a fresh script export of each Traced copy differs from the build's export only in `frame_1/DoAction.as`.
- **Whole suite.** `just pytest` and `just gut` pass before each commit.

## Boundaries

- Always: Build a Traced copy by script from the SWF in `URCHIN_SWF_DIR`. Keep the raw player log as the Trace log. Read every label and frame in a test from `battles.json`, `label_xref.json` or the tracked export. Use the glossary terms. Record on #5 each run that stops, each diff and each guess that a run proves or disproves.
- Ask first: A change to `label_xref.py` or `label_xref.json`. A new dependency. An edit of a Trace log after the player wrote it. A route other than the table above. A change to the Probe's fields after the first log is committed. A Steam log whose hall, sky or hub target differs from `battles.json` or `Krin.zoneName`: report it on #5 and stop, and do not change the test to pass.
- Never: Commit a SWF or a Traced copy. Type a label or a frame number into the test. Put a Probe in the tree that changes what the game does. Change `/Applications/Ruffle.app` or its signature. Edit a file under `dev/source_files/action_script/`. Add a log to `MISSING` without the URL of its issue comment.

## Success criteria

1. `just trace-swf web` and `just trace-swf steam` each write a Traced copy to `$URCHIN_SWF_DIR/traced/`. A fresh script export of the copy differs from the build's export only in `frame_1/DoAction.as`.
2. `just trace-run <build> <player>` launches the player on the Traced copy and saves the log when the player quits. The log has the HOOK line and GOTO lines, for both builds and both players.
3. `references/traced_runs/` holds the four Trace logs and their screenshots, or `MISSING` names each absent log with its #5 comment.
4. `dev/tests/test_trace.py` passes. `web_flash` and `steam_flash` show `WHITE NOVEMBER` and `SEA` for battle 2. Every log shows `JAIL` and `JAIL` for battle 100 and `PRISON` for the hub.
5. Each must-fail control fails.
6. #5 has the four `trace-diff` outputs: two for builds and two for players.
7. #5 records that Ruffle's Debug view shows `BATTLESCREEN` on `JAIL` in battle 100, or where Ruffle stops.
8. One issue exists for each logic Probe: `for..in` order, the `AImoveAdder` stale values, and open questions 1 and 2 of `docs/research/2026-11-07-original-logic-vs-port.md`.
9. `docs/agents/actionscript.md` and `AGENTS.md` name the three recipes, and `check_doc_paths` passes.
10. `just pytest` and `just gut` pass.

QA, by Julian, after the build:

- Play the Traced copy next to the plain SWF for a few minutes and confirm that the Probe changes nothing on screen and that the pacing is the same.
- Compare the ability icons in Ruffle with the debug player.

The breakpoint AC and the save AC of the issue body stay optional. Nothing here depends on them.

## Out of scope (deferred)

- The ffdec debugger, its SOL sync, and a `SharedObject.getLocal(name, "/")` patch. ADR 0008 gives the reasons.
- The zone 6 route and a seeded save. The new game route reaches a hall and sky that differ.
- The GOTO lines of a Cutscene played to its end.
- Logic Probes. Each gets its own issue.
- A join of every clip path to a sprite, and a check of the 76 flagged goto records of `label_xref.json`. Julian chose the three lines for V1.
- A label extract for the Steam build. The frame check runs on the web logs only.
- Ruffle's exporter, its input test harness, and a Probe that jumps to a battle.
- A fix for Ruffle's sandbox, the 11.9 debug player and the Flash Player 32 projector.
- A cleanup of the idea session's files: `sonny-2-2900.debug.swf` at the repo root and `~/Library/Containers/rs.ruffle.ruffle/Data/sonny2/`.

## Settled on approval

Julian approved the spec as drafted on 2026-11-16. These points were open questions in the draft, and the approval accepts each one as written.

1. **Log size.** The size of a Trace log is not measured, because no run has gone past the title. The build commits a raw log under 5 MB. Over that, the build stops and asks.
2. **Home paths in a raw log.** Ruffle's log can hold paths under the home folder. The log is committed as the player wrote it.
3. **Whether the debug player caps `flashlog.txt`.** Not measured. The first `web_flash` run shows it: the hub line is the last check of the route, so a capped log fails the hub check.
4. **Computer use on the Flash 14 debug player under Rosetta** is not tested, and the agent must win battle 2 and battle 100. The fallback is in the route section: Julian plays the run.
5. **Names.** `trace_swf`, `trace_run`, `trace_diff`, `FLASH_DEBUG_PLAYER`, `RUFFLE_BIN`, the `urchin_traced` folder in Ruffle's container and the screenshot names are the names.
