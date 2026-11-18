# Working on urchin

A port of the Flash game Sonny 2 to Godot 4.7.2, whose art and data come out of
the original SWF by script, not by hand.

## Commands

Run the project's tasks, such as tests, Godot, extraction and conversion,
through their `just` recipes. `just` lists the recipes. It picks Godot for the
OS, loads the per-machine settings from `.env`, and stops with a message when a
tool is missing. The Python scripts read `GODOT_BIN` from it and do not look
for Godot themselves, so `uv run gut` outside `just` fails. Run plain tools
such as `git`, `gh`, `rg`, `cat` and `agent-skills` directly, not through
`just --command`, because they do not read `.env`.

- In a new git worktree, run `just setup-worktree` first. It runs Godot's
  import and warns when `URCHIN_SWF_DIR` has no SWFs.
- Extraction and conversion scripts are `[project.scripts]` entry points with
  a recipe each: `just extract-battle-screen`, `just convert-items`, and so on.
  Arguments pass through. `just` lists them.
- `just lookup <query>` finds a function, a signal, a string value, a script
  or a line, in the GDScript and in the original ActionScript. It prints the
  callers, the calls, the signals, the ActionScript that a function ports, and
  the `DECODED_ALGORITHMS.md` sections that cite it. Run it before `rg` on
  `.gd` files and on the export. `just as-lookup` is an alias. The answer says
  where to look. It is not an authority on behavior.
- `just trace-swf`, `just trace-run` and `just trace-diff` build a Traced
  copy of the original, play it and save its Trace log, and compare two Trace
  logs. See "Tracing the original" in `docs/agents/actionscript.md`.
- Tests: `just gut` runs the GUT suite. `just gut <path>` runs one test file,
  and `just gut -gunit_test_name=<name>` runs the tests whose names contain
  `<name>`. Trust its exit code. It also fails the runs that GUT exits 0 on: a
  script or parse error, or no tests run. It takes a Godot slot itself.
- The Python package's tests are `just pytest`, under `dev/tests/`. They never
  read the SWF or the XML dump, so they pass on a fresh checkout.
- After writing anything under `assets/`, run `just import` or tests fail with
  "No loader found for resource". `just gut` runs this import by itself only in
  a checkout with no `.godot` folder.
- Any other Godot command: `just godot <arguments>`.
- In Codex, if a check cannot write its normal tool cache outside the
  workspace, rerun it with sandbox escalation. A blocked write to prek's
  `prek.log` stopped the #220 checks before any hook ran; the same checks
  passed with escalation. Do not treat that error as a failed code check.

## Setup

- Install `just`, `uv`, `prek`, Godot 4.7.2, and for the extractors a JDK and
  the ffdec build in `docs/agents/art-extraction.md`.
- `GODOT_BIN` is the app bundle on macOS and `godot` on `PATH` elsewhere. To
  change it, or to limit the Godot processes that run at once with
  `GODOT_SLOTS` (default `auto`, the number of CPU cores), copy `.env.example`
  to `.env`. `.env` is git-ignored. A variable set in the shell wins over it.
- The two SWFs are git-ignored. Put them in one folder outside the repo and
  set `URCHIN_SWF_DIR` to it in your shell profile, so every worktree reads
  the same copy. Do not set it in `.env`: a new worktree has no `.env`.
  Without the variable, the scripts look in the repo root.

## Every task

- Run `just gut` before each commit.
- Every lesson here and in the docs below records something this project
  already got wrong once. Each one names its evidence so you can check it
  instead of trusting it.
- Do not hand-cut art or hand-place a coordinate. If it exists in the SWF,
  script it. One exception: a Screen or Window may type its numbers into its
  `.tscn` when the rect test compares them with the SWF. Add the scene and its
  pieces to `SCENES` in `dev/urchin_dev/swf/extract/screen_rects.py`, run
  `just extract-screen-rects`, and `test/unit/test_screen_rects.gd` checks
  where each piece lands, to 0.5 px.

## Read the doc that matches the task

- Reading the ActionScript, porting the original's logic or data, or tracing
  the original in a Traced run: `docs/agents/actionscript.md`.
- Running or changing an extractor, or anything else that renders through
  ffdec, or scoring a Screen with `just compare-screen`:
  `docs/agents/art-extraction.md`.
- Writing GDScript, a scene or a GUT test, or loading a QA save preset:
  `docs/agents/godot.md`.
- Reviewing a diff, or calling a change verified: `CODING_STANDARDS.md`.
- Dispatching a Build or Bug task to a worker model, or working as one:
  `docs/agents/multi-model.md`.

## Workflow

- Tasks are tracked in GitHub Issues for julian-perge/urchin, with the `gh` CLI. `/agent-skills:plan` creates one sub-issue per task. `tasks/` is git-ignored scratch, except `tasks/old/`.
- Specs are files at `spec/<issue>-<slug>.md`, not `SPEC.md`. Specs from before this workflow are in `spec/old/`.
- ADRs go in `docs/adr/`. Read `GLOSSARY.md` and `docs/adr/` (those that exist) before design work.
- Start each `/agent-skills` stage with `agent-skills brief <stage> <n>`. It prints every rule of `docs/agents/workflow.md` that the stage needs, so do not read that file in a stage. Before other work in this repo, read all of `docs/agents/workflow.md`.
