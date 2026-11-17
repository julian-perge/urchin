# Trace the original with injected Probes instead of the step debugger

To learn what the original does while it runs, the project puts Probes into a Traced copy of a build and reads the Trace log. It does not step through the game in ffdec's debugger. [#5](https://github.com/julian-perge/urchin/issues/5) adds the recipes, the first Probe and the first four Trace logs. A Probe is an ActionScript file that `ffdec -replace` puts in front of a build's own `/frame_1/DoAction`. It calls `trace()`, and the player writes each line to its log. The project owner chose this in the idea session of #5, and the design session settled the rest of this record.

## Why not the debugger

- ffdec's debugger never attached to the web build. `frame_1/DoAction.as:4513` runs `Stage.showMenu = false();`, which also hides the Debugger item (https://www.free-decompiler.com/flash/issues/2168-game-where-debugger-does-not-launch). A copy without that line plays from ffdec's Debug button, but no breakpoint has been tried.
- A breakpoint gives one person one look. A Trace log is a file, so a test can read it and a later session can read it again.
- The same Probe runs in two players and in both builds. The goto Probe logged its lines in all four cases: the web build and the Steam build, each under the Flash 14 debug player and under Ruffle 0.7.1 (measured in the idea session of #5).

The debugger and ffdec's SOL sync stay optional. Nothing in #5 depends on them.

## What follows from it

- **Trace logs are committed.** They go in `references/traced_runs/`, one raw player log for each Traced run, named for the build and the player, such as `web_flash.txt`. `dev/tests/test_trace.py` reads them, so the Python tests still pass on a checkout with no SWF.
- **A test checks each Trace log by itself.** It compares the hub, hall and sky targets with `dev/converted_json/battles.json` and with the flagged records of `dev/converted_json/label_xref.json`.
- **Two Trace logs are compared as sets.** Fights roll dice and the picks differ, so two Traced runs never log the same lines in the same order. `just trace-diff` prints the distinct GOTO records that one log has and the other lacks. Order and count are ignored. No test pins that output. #5 posts it on the issue.
- **A Traced run needs no save.** The route of #5 is a new game. The Tutorial, battle 2, has the `WHITE NOVEMBER` hall under the `SEA` sky in `battles.json`, so a new game reaches a battle whose hall and sky differ. The zone 6 route of the issue body needed a save in each player, and seeding one was never tested.
- **A Traced copy keeps a fixed path.** `just trace-swf` writes it to `$URCHIN_SWF_DIR/traced/` under the name of the SWF it came from, so every worktree shares it. For Ruffle, `just trace-run` copies it into Ruffle's sandbox container, because the sandboxed app cannot open a SWF anywhere else.
- **Each Probe is one file in `dev/probes/`.** A logic question, such as `for..in` order, gets its own issue that adds one Probe file.
- **A Probe must not change what the game does.** The QA step of #5 plays the Traced copy next to the plain SWF to check it. That the trace volume in a battle leaves the pacing alone is a guess until then.
- **The Flash debug player is Intel only** and runs under Rosetta. Capture Trace logs on macOS 27.

## Considered and left out

- A patch that passes `"/"` to `SharedObject.getLocal`, and a seeded save for each player. The new game route removes the need.
- Ruffle's exporter and its input test harness.
- A Probe that jumps straight to a battle. It would change what the game does.

AS paths are relative to `dev/source_files/action_script/`.
