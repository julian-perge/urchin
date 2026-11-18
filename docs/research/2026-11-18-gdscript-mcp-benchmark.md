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
| `questions.json` | U1 to U7. U1 to U3 are GDScript, U4 is ActionScript, U5 and U6 need both, U7 is a control with no answer. |
| `reference.md` | The graded answers at commit `e6b9f34a`. Check them again before a run on a later commit: line numbers move. |
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
