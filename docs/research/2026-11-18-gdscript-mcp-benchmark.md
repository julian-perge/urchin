# GDScript MCP benchmark, and how to rerun it

Date: 2026-11-18. Evidence for the decision in
[one-lookup-for-gdscript-and-actionscript](../ideas/one-lookup-for-gdscript-and-actionscript.md):
no GDScript MCP server, build `just lookup` instead. This note is the handoff
for the next run, which adds `just lookup` as a fourth condition.

## Where the scripts are

The scripts are shared with the blender-addon benchmark, so they live in the
owner's notes, not in this repo: `<vault>/Tools/claude/bench/`. The note
`<vault>/Tools/claude/05-benchmark-kit.md` explains each script and the run
steps. The files for this repo are in `<vault>/Tools/claude/bench/urchin/`:

| File | What it holds |
| --- | --- |
| `questions.json` | U1 to U10. U1 to U3 are GDScript, U4 is ActionScript, U5 and U6 need both, U7 is a control with no answer. U8 to U10 came from real sessions (see below). |
| `reference.md` | The graded answers. U1 to U7 were checked at commit `e6b9f34a` and U8 to U10 at `9b530ecf`. Check them again before a run on a later commit: line numbers move. |
| `keys.json` | The key words and line numbers per question, for `grade.py`. |
| `mcp-none.json`, `mcp-sunerpy.json`, `mcp-godotlens.json` | One MCP config per condition, with `<bench dir>` placeholders. |

## Setup that was used

- `claude -p`, Opus, `--strict-mcp-config`, `--permission-mode auto`, Edit and
  Write disallowed, settings `{"enableArtifact": false, "enableWorkflows": false}`.
  One fresh session per question and repetition, 2 repetitions.
- Two clones at `e6b9f34a`, each with `just import` run, so `.godot` exists.
  `baseline` and `godotlens-hint` used one clone. `sunerpy-hint` used its own,
  because sunerpy/godot-mcp writes a 64 MB `.godot-mcp/` index into the project.
- sunerpy/godot-mcp 0.8.0, the `aarch64-apple-darwin` release binary, run as
  `godot-mcp serve --project <clone> --profile core`.
- godotlens-mcp from `npx -y godotlens-mcp`. The run did not record its
  version. It needs a Godot 4.7 editor with the language server
  open on port 6005 for the whole run:
  `Godot --path <clone> --editor --headless --lsp-port 6005 --dap-port 6006`.
- Each MCP condition got a `--hint` that names its tools. Without a hint,
  headless Claude Code keeps MCP tools behind ToolSearch and does not call them
  (measured in the blender-addon benchmark).
- `contaminated.py` needles: `.godot-mcp/`, `.godot/`, `.venv/`. No run read them.

## Result

| Condition | Context, U1 to U6 | Change | Tool calls | MCP calls | ToolSearch calls | Cost, all 14 runs |
| --- | --- | --- | --- | --- | --- | --- |
| `rg` and `just as-lookup` | 1,374k | 0% | 48 | 0 | 0 | $2.51 |
| sunerpy/godot-mcp | 2,013k | +47% | 71 | 11 | 10 | $3.00 |
| godotlens-mcp | 1,464k | +7% | 61 | 10 | 6 | $2.29 |

All 42 answers were correct (7 questions, 2 runs, 3 conditions). The
[idea doc](../ideas/one-lookup-for-gdscript-and-actionscript.md) has the
per-question results and the other findings.

## Next run

1. Build `just lookup` and add its rule to `docs/agents/godot.md`. Then add a
   condition `lookup` with `mcp-none.json` and no hint, so it measures whether
   sessions find the recipe from the docs.
2. Check `reference.md` and `keys.json` against the new commit.
3. Run `baseline` again on the same commit, so both conditions see the same
   code. Do not compare against the 2026-11-18 numbers.
4. Add 2 or 3 questions from real session transcripts, the open question in
   the idea doc.

## Questions from real sessions (U8 to U10)

Added 2026-11-18 for spec #346, task #354. A scratch script listed runs of 5
or more read calls (Read, rg, sed, cat) on `.gd` or `.as` files in the urchin
transcripts from 2026-11-04 on, with the text before each run. Most user
prompts in this repo are slash commands, so the questions come from what a
session was trying to find, not from a prompt. Each reference answer is in
`reference.md`, checked at urchin commit `9b530ecf`.

| Question | Transcript | Why it was chosen |
| --- | --- | --- |
| U8: how a hub orb receives its click | `834f6522`, 2026-11-17 | The session spent 4 partial reads and rg calls to find `OrbBase._on_hit_box_input`. GDScript only, with a signal and an override chain. |
| U9: who writes and reads `Krin.tutSpeecher`, and where the port keeps the flag | `e282b9c3`, 2026-11-17 | The session read `DoAction_21.as` whole, then `DoAction_20.as` and `frame_219/DoAction.as` by line range. It needs both languages. |
| U10: which function advances the animation label, and where the frame rate comes from | `850557e3`, 2026-11-16 | The session used one rg for 7 names and 3 Read calls with an offset in `character_visual.gd`. GDScript only, and the answer sits in one file. |

U8 to U10 were not run yet. The run is task #355.

## Rerun with `just lookup` (2026-11-18)

Task #355 of spec #346. Conditions: `baseline` and `lookup`, both `mcp-none.json`, no hint, Opus, 10 questions (U1 to U10), 2 runs each, 40 runs. Setup as above, with these differences:

- The two clones hold the same game code. `baseline` is at `9b530ecf` (before the lookup). `lookup` is at `671e2dab` (the #346 branch). No `.gd`, `.as` or `.tscn` file differs between them. The docs differ: only `lookup` tells the session to run `just lookup`. `baseline` still has the rule for `just as-lookup`.
- `reference.md` and `keys.json` were checked at `9b530ecf`. Only the line numbers of U2 moved (the battle HUD merge changed `battle_scene.gd`).
- The runs were one after another, so there was one Godot import at a time.

| Condition | Runs | Context, U1 to U6 and U8 to U10 | Change | Tool calls (all 20 runs) | MCP calls | ToolSearch calls | Cost, all 20 runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `baseline` | 20 | 2,179k | 0% | 92 | 0 | 0 | $3.24 |
| `lookup` | 20 | 2,470k | +13% | 101 | 0 | 0 | $3.26 |

Control U7 context: `baseline` 458k, `lookup` 618k. Cost is the sum of `total_cost_usd` in `runs.jsonl`. The decision rests on context.

Per question, median context (median tool calls): U1 95k (3) against 89k (2), U2 97k (3) against 100k (4), U3 160k (6) against 136k (4), U4 81k (2) against 117k (3), U6 110k (4) against 157k (5), U8 140k (4) against 142k (5), U9 128k (4) against 127k (4), U10 141k (6) against 226k (8), the first value for `baseline`. The question that cost the most extra is U10 (+85k), then U6 (+47k) and U4 (+36k).

Grades: all 40 answers were graded by `grade.py` against `keys.json` with no missing key point. `contaminated.py` shows no read of `.godot/`, `.godot-mcp/` or `.venv/`.

Discovery without a hint: all 20 `lookup` runs called `just lookup`, `just as-lookup` or `uv run lookup`, so sessions found the recipe from `AGENTS.md`. 10 of the 20 `baseline` runs called `just as-lookup`.

Result: `lookup` used 13% more context than the new `baseline`, which is outside the 10% spread between runs. The target of spec #346 (at or below `baseline`) is not met. The cause is a guess: a lookup answer prints the whole source of a function of up to 120 lines, and a session that then reads the file again pays twice. Not tested.
