# Working on urchin

A port of the Flash game Sonny 2 to Godot 4.7.2, whose art and data come out of
the original SWF by script, not by hand.

## Commands

- In a new git worktree, run `uv run setup_worktree` first. It links the
  gitignored SWFs from the main checkout and runs Godot's import.
- Extraction and conversion scripts are `[project.scripts]` entry points:
  `uv run extract_battle_screen`, `uv run convert_items`, and so on. Run
  `rg '^extract_|^convert_' pyproject.toml` for the list.
- Tests: `uv run gut` runs the GUT suite. `uv run gut <path>` runs one test
  file, and `uv run gut -gunit_test_name=<name>` runs the tests whose names
  contain `<name>`. Trust its exit code. It also fails the runs that GUT exits 0
  on: a script or parse error, or no tests run. It takes a Godot slot from
  `~/tmp/2026-11-07-godot-slots/godot-slot.fish` itself, so run it bare.
- The Python package's tests are `uv run pytest`, under `dev/tests/`. They
  never read the SWF or the XML dump, so they pass on a fresh checkout.
- After writing anything under `assets/`, run
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .`
  or tests fail with "No loader found for resource". `uv run gut` runs this
  import by itself only in a checkout with no `.godot` folder.

## Every task

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

## Agent skills

### Issue tracker

Issues live in GitHub Issues for julian-perge/urchin, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each label string the same as its role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
