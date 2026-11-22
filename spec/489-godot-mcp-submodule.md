# Spec: godot-mcp-submodule, V1

Source issue: [#489](https://github.com/julian-perge/urchin/issues/489). It depends on [julian-perge/godot-mcp#12](https://github.com/julian-perge/godot-mcp/issues/12), whose spec is `spec/12-harness-node-tree.md` in godot-mcp. The confirmed intent is [docs/intent/godot-mcp-submodule.md](../docs/intent/godot-mcp-submodule.md).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md). The skill is [.claude/skills/verify-urchin/SKILL.md](../.claude/skills/verify-urchin/SKILL.md).

## Objective

verify-urchin loads the godot-mcp harness from a submodule at `vendor/godot-mcp`, and stops guessing where a clone is. The submodule pins the godot-mcp commit that the skill was proven against. You can also edit the harness inside urchin's tree, without switching to another checkout.

Today `HARNESS_CANDIDATES` in `urchin_verify.py` lists `~/code/godot-mcp/build/...` and `~/DEV/git_repos/godot-mcp/...`, and the second folder no longer exists. The script also writes `verify_harness.gd`, a wrapper that adds `node`, `tree` and the window title. godot-mcp#12 moves those three into the harness, so the wrapper goes away.

The user is Julian and any agent that runs verify-urchin on the Mac, on WSL or in a new worktree.

## Assumptions

- `git submodule` facts, checked in `~/tmp/2026-11-22-submodule-worktree` with git 2.53.0:
  - A new worktree gets an empty submodule folder.
  - `git submodule update --init` in that worktree makes a second clone under `.git/worktrees/<wt>/modules/`, with a detached HEAD.
- Godot loads a script given with `-s` by its absolute path from a folder that holds a `.gdignore`. The wrapper today loads the harness from `~/code/godot-mcp`, outside the project, so a path outside the import works. The build checks the `.gdignore` case before relying on it.
- The Mac path is not tested in this change. The proof runs on WSL.

## Changes

### Submodule

- `git submodule add https://github.com/julian-perge/godot-mcp.git vendor/godot-mcp`.
- `.gitmodules` sets `branch = main` for it.
- The pin is the head commit of the godot-mcp#12 pull request branch. When that PR merges, a follow-up commit moves the pin to the merge commit on `main`.
- `vendor/.gdignore` (empty) keeps Godot's import and the class cache out of `vendor/`. godot-mcp holds `.gd` files and a nested Godot project under `tests/fixtures/`, and urchin's import must not read them.

### `urchin_verify.py`

- The harness path is `URCHIN_VERIFY_HARNESS` when it is set. Otherwise it is `<repo root>/vendor/godot-mcp/src/scripts/mcp_harness.gd`. `<repo root>` comes from `repo_root()`, so each worktree uses its own submodule copy.
- When that file is missing, `launch` fails with: `vendor/godot-mcp is empty. Run just setup-worktree, or git submodule update --init vendor/godot-mcp`.
- Remove `HARNESS_CANDIDATES`, `WRAPPER` and every read or write of `verify_harness.gd`.
- `launch` passes the harness itself with `-s`, and sets `GODOT_MCP_HARNESS_TITLE` to `AGENT VERIFY - <run>`.
- `doctor` can no longer find its Godot process by the wrapper path, because every run now loads the same harness file. Its `godot_runs_our_harness` check reads `/proc/<pid>/environ` of each process in the run's group, and passes when a non-`just` process holds `GODOT_MCP_HARNESS_TOKEN=<this run's token>`. On macOS the check still passes by default, as it does now.
- `tree --all` sends `include_hidden`. `node --props` reads the values from the result's `props` dictionary. The CLI flags do not change.

### `setup_worktree.py`

- `main` runs `git submodule update --init vendor/godot-mcp` in `REPO_ROOT` before the Godot import.
- When that command fails, `main` prints its output and a note that verify-urchin needs the submodule. It goes on to the import, because the tests and extractors do not need godot-mcp.
- A new function, `submodule_command()`, returns that command, so `dev/tests/test_setup_worktree.py` can check it with no git repository.

### Docs

- `SKILL.md`: the requirements paragraph names `vendor/godot-mcp` and `URCHIN_VERIFY_HARNESS`, and drops both clone paths. The Isolation and Doctor sections say how `doctor` finds the run's Godot process now.
- `AGENTS.md`, under "Commands", gets one rule: `vendor/godot-mcp` is a submodule on a detached HEAD. Before you edit in it, run `git -C vendor/godot-mcp switch -c <branch>`. Push that branch, then commit the new pin in urchin. The MCP server runs from `~/code/godot-mcp`, so it does not see edits made in the submodule.

## Commands

- `just setup-worktree`, `just gut`, `just pytest` and `just import`, as AGENTS.md says.
- `git submodule update --init vendor/godot-mcp` in the main checkout, once, after the pin lands.
- The proof run, from the skill:

  ```bash
  V=.claude/skills/verify-urchin/urchin_verify.py
  $V launch proof --scene res://scenes/battle_scene.tscn -- --battle=109
  $V doctor proof
  $V tree proof --depth 2
  # the battle attack recipe in features/battle.md
  $V stop proof
  ```

## Testing strategy

- `just pytest`: `test_setup_worktree.py` checks `submodule_command()`.
- `uv run ruff check` and `uv run ruff format --check` on the two Python files. The commit hook runs both.
- `just gut` before each commit. It must still pass with `vendor/godot-mcp` filled in, which shows that `vendor/.gdignore` keeps godot-mcp's scripts out of the import.
- The proof run in a fresh worktree is the end-to-end check (see Success criteria).
- Prove the `doctor` check can fail: run `doctor` with a wrong token in `state.json`, and watch `godot_runs_our_harness` go false.

## Boundaries

- Always: run `just gut` before each commit. Copy each verify-urchin proof's evidence path into the PR.
- Ask first: moving the MCP server to the submodule, and any change to `~/code/godot-mcp` other than the godot-mcp#12 branch.
- Never: delete `~/code/godot-mcp`. Commit inside `vendor/godot-mcp` on a detached HEAD.

## Success criteria

- `rg -n "DEV/git_repos|HARNESS_CANDIDATES|verify_harness" .claude AGENTS.md` finds nothing.
- In a fresh worktree made with `git worktree add`, `just setup-worktree` fills `vendor/godot-mcp` at the pinned commit.
- In that worktree, the proof run passes: `launch` prints `"ready": true`, `doctor` prints `"healthy": true`, the window title is `AGENT VERIFY - proof`, `tree` lists the battle's controls, an attack lowers the target's HP, and `stop` keeps the evidence with `real_user_dir_unchanged` true.
- `just gut` and `just pytest` pass in the main checkout with the submodule filled in.
- `.gitmodules` names `vendor/godot-mcp` with `branch = main`, and the pin is the godot-mcp#12 branch head.

## Out of scope (deferred)

- Running the godot-mcp MCP server from the submodule. It stays on `~/code/godot-mcp/build/index.js` until a later decision, for example after the godot-ai research.
- Deleting `~/code/godot-mcp`. It stays, because the MCP server runs from it.
- A proof run on the Mac. The `HOME` isolation and the submodule path there stay unverified until a Mac run covers them.
- Moving the pin to the godot-mcp#12 merge commit. That is a follow-up commit after the merge.

## Open questions

- None. The deviation from the Build stage (the work goes on #488) is recorded in the decision comment on #489.
