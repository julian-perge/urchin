# Working on urchin

A port of the Flash game Sonny 2 to Godot 4.7.2, whose art and data come out of
the original SWF by script, not by hand.

## Commands

- In a new git worktree, run `uv run setup_worktree` first. It links the
  gitignored SWFs from the main checkout and runs Godot's import.
- Extraction and conversion scripts are `[project.scripts]` entry points:
  `uv run extract_battle_screen`, `uv run convert_items`, and so on. Run
  `rg '^extract_|^convert_' pyproject.toml` for the list.
- `uv run as_lookup <name>` finds a function, a global, a script or a line of
  the original ActionScript, with its callers and the GDScript that cites it.
  Run it before `rg` on the export.
- Tests: `uv run gut` runs the GUT suite. `uv run gut <path>` runs one test
  file, and `uv run gut -gunit_test_name=<name>` runs the tests whose names
  contain `<name>`. Trust its exit code. It also fails the runs that GUT exits 0
  on: a script or parse error, or no tests run. It takes a Godot slot
  itself, so run it bare.
- Godot is `$GODOT_BIN`, else `godot` on `PATH`, else the macOS app. The
  Python scripts use the same order. `GODOT_SLOTS` is the most Godot processes
  that run at once. The default, `auto`, is the number of CPU cores.
- The Python package's tests are `uv run pytest`, under `dev/tests/`. They
  never read the SWF or the XML dump, so they pass on a fresh checkout.
- After writing anything under `assets/`, run
  `"${GODOT_BIN:-godot}" --headless --import --path .`
  or tests fail with "No loader found for resource". `uv run gut` runs this
  import by itself only in a checkout with no `.godot` folder.

## Every task

- Run `uv run gut` before each commit.
- Every lesson here and in the docs below records something this project
  already got wrong once. Each one names its evidence so you can check it
  instead of trusting it.
- Do not hand-cut art or hand-place a coordinate. If it exists in the SWF,
  script it.

## Read the doc that matches the task

- Reading the ActionScript, or porting the original's logic or data:
  `docs/agents/actionscript.md`.
- Running or changing an extractor, or anything else that renders through
  ffdec: `docs/agents/art-extraction.md`.
- Writing GDScript, a scene or a GUT test, or loading a QA save preset:
  `docs/agents/godot.md`.
- Reviewing a diff, or calling a change verified: `CODING_STANDARDS.md`.

## Workflow

- Tasks are tracked in GitHub Issues for julian-perge/urchin, with the `gh` CLI. `/agent-skills:plan` creates one sub-issue per task. `tasks/` is git-ignored scratch, except `tasks/old/`.
- Specs are files at `spec/<issue>-<slug>.md`, not `SPEC.md`. Specs from before this workflow are in `spec/old/`.
- ADRs go in `docs/adr/`. Read `GLOSSARY.md` and `docs/adr/` (those that exist) before design work.
- Read `docs/agents/workflow.md` before any `/agent-skills` command.
