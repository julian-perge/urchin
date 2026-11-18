# One lookup for GDScript and ActionScript

## Problem Statement

How might we let an urchin session answer "where is this, who calls it, and which original code does it port" in one
lookup, for GDScript as well as ActionScript, instead of an `rg` and several partial reads?

## Measurements

Calls that read code in urchin transcripts from 2026-11-04 to 2026-11-18 (Read, and `rg`, `sed -n`, `cat` and similar in
Bash), counted by `~/tmp/2026-11-18-read-reduction/reads.py`. All Evidence.

| Target | Calls |
| --- | --- |
| GDScript `.gd`, its tests and `.tscn`/`.tres` | about 3,340 |
| ActionScript export | 729 |
| `just as-lookup` | 33 |

- Reads of the ActionScript export fell from about 200 a day (2026-11-08 to 11-10) to 10 to 30 a day after the AS
  index landed on 2026-11-11. That the index caused the fall is a Guess: the work also changed.
- `just as-lookup` use is rising: 22 calls on 2026-11-17, against 1 to 4 on the days before.
- The most read files are `scripts/battle/battle_scene.gd` (1,087 lines) and `test/integration/test_battle_scene.gd`
  (3,967 lines). Of 520 Read calls on these two files, 489 pass `offset` and `limit`. Sessions already read them in
  pages, so the cost is the search for the right lines, not the size of each read.
- In the 2026-11-18 benchmark on blender-addon, two code-graph MCP servers (codebase-memory-mcp, which supports
  GDScript, and graphify) used 21% and 16% more context than plain `rg`. Headless Claude Code defers every MCP tool
  behind ToolSearch, and without a hint the model never called them. See `~/obsidian/Tools/claude/04-measurement-results.md`.

## Recommended Direction

Extend the AS index to GDScript, so `just lookup <name>` answers for both languages. For a GDScript function it
prints the file and line range, the code lines (or the block outline over 120 lines), each caller, each function
it calls, the signals it connects and emits, and the AS range that its comments cite. For an AS function it already
prints `ports`; the same join now also works from the GDScript side.

Each answer also prints the decoded facts that cite the same range: the entries of `DECODED_ALGORITHMS.md`,
`KNOWN_GAPS.md` and `docs/research/` that name the file and lines. The original code and the tests stay the
authority, and the lookup stays a navigation aid, as `docs/agents/actionscript.md` already says for `as-lookup`.

A CLI comes first, because `as-lookup` shows that a doc rule plus a `just` recipe gets used, and the benchmark shows
that an MCP adds a ToolSearch step. Existing GDScript MCP servers are rows in the benchmark, not builds: if one of
them answers the same questions with fewer tokens, use it and do not build the GDScript half.

### MCP benchmark, 2026-11-18

All Evidence. Setup and how to rerun it:
[2026-11-18-gdscript-mcp-benchmark](../research/2026-11-18-gdscript-mcp-benchmark.md).
`claude -p` on two clones at `e6b9f34a`, 7 questions (U1 to U3 GDScript, U4 ActionScript, U5 and U6 both, U7 a
control with no answer), 2 runs each. Both MCP conditions got a hint that names their tools.

| Condition | Context, U1 to U6 | Change | Tool calls | MCP calls | ToolSearch calls | Cost, all 14 runs |
| --- | --- | --- | --- | --- | --- | --- |
| `rg` and `just as-lookup` | 1,374k | 0% | 48 | 0 | 0 | $2.51 |
| sunerpy/godot-mcp 0.8.0, `core` profile | 2,013k | +47% | 71 | 11 | 10 | $3.00 |
| godotlens-mcp, headless 4.7 editor | 1,464k | +7% | 61 | 10 | 6 | $2.29 |

- All 42 answers are correct against the reference. U7 said "no such function" in every run.
- No run read `.godot-mcp/`, `.godot/` or `.venv/`, so the clones' extra folders did not change the numbers.
- sunerpy returns long JSON, and sessions searched with `rg` after it anyway. It also writes a 64 MB `.godot-mcp/`
  folder into the project.
- godotlens won 3 questions (U2, U3, U5) and lost 3 (U1, U4, U6). With 2 runs per question, +7% is within the spread.
  It needs a running Godot editor with the language server on port 6005, and in one U3 run it showed a stale default
  value (`= null` where the file says `= {}`).
- `just as-lookup Angry_Dux` returned no match, because the index holds names and not string values. The session
  fell back to `rg`.

**Decision:** no GDScript MCP. Neither server beats `rg` on context, so build the `just lookup` CLI as planned and
rerun these 7 questions with it as a fourth condition. Recorded in
[ADR 0009](../adr/0009-build-just-lookup-not-a-gdscript-mcp.md).

## Key Assumptions to Validate

- [ ] A name-based caller list is good enough for GDScript. Signals, `call()` and duck typing are not resolved by
  name. Test: compare the lookup's callers of 10 battle functions against a hand search.
- [ ] Sessions run the lookup without a hint beyond the doc rule. Test: count `just lookup` calls against GDScript
  partial reads in the week after the rule lands, with `reads.py`.
- [x] The facts docs cite exact ranges, so the join finds them. Result: 32 of 35 sections of
  `DECODED_ALGORITHMS.md` cite a `.as` line, and 124 of 158 `.as` mentions carry a line.
- [ ] The lookup cuts tokens on real urchin questions, not only call counts. Test: rerun the 7 questions of the
  2026-11-18 MCP benchmark with `just lookup` as a fourth condition. The MCP rows are done (see above).

## MVP Scope

In:

- `just lookup <name>` over `.gd` files: function and class definitions, callers by name, `signal`, `connect` and
  `emit`, and the AS ranges that comments cite.
- The facts join for `DECODED_ALGORITHMS.md`.
- One line in `docs/agents/godot.md` that says to run the lookup before `rg`, as `actionscript.md` does.
- String values in the index (sound names, frame labels), so `just lookup Angry_Dux` finds the line.
- The benchmark rerun with the lookup as a fourth condition.

Out: `.tscn` node trees and node paths, typed call resolution, any edit tools.

## Not Doing (and Why)

- Splitting `test_battle_scene.gd` and `battle_scene.gd` now. Sessions already read them in pages, so a split
  removes little. Do it later only if the lookup data shows that the search step in these files still costs calls.
- Adding symbol tools to the `julian-perge/godot-mcp` fork, or adopting sunerpy/godot-mcp or godotlens-mcp. Both
  servers used more context than `rg` in the 2026-11-18 benchmark.
- Adopting `hi-godot/godot-ai` for this. It drives a live 4.7 editor and outlines scripts (`find_symbols`), but it
  documents no references, no definitions and no reads by line range. Whether it replaces the godot-mcp fork is a
  separate decision.
- A general code-graph MCP (codebase-memory-mcp, graphify). Both lost the 2026-11-18 benchmark.

## Open Questions

- Does the GDScript index live in `as_index.jsonl`, or in its own file with the same record shape?
- The 7 benchmark questions were written from the most read files, not taken from real sessions. Do 2 or 3 real
  questions from session transcripts belong in the lookup rerun?
