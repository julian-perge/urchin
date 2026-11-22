---
name: verify-urchin
description: Launch the urchin Godot game (the Sonny 2 port) in its own window with its own save folder, drive it with clicks and keys, and save screenshots and logs as proof. Use it to run the game, to see a change in the real game, or to prove that a fix works for a player in the menus, the hub, a battle, the store or the inventory. The GUT suite does not show these paths.
---

# Verify urchin in the real game

The user surface is the Godot game window: an 800x575 Stage, driven with the
mouse and a few keys. This skill drives it through one helper,
`urchin_verify.py`. The helper starts Godot through `just godot` with the
godot-mcp harness as the main loop, so it can click, type and take
screenshots. It adds two read-only commands, `node` and `tree`, that find
a control by its node name or path. Use those names, not typed coordinates.

Run every command from the repo root (or a worktree root). Each command is
shown with its full path once. Later lines write `$V` for it:

```bash
V=.claude/skills/verify-urchin/urchin_verify.py
```

The helper is a stdlib Python script that `uv run --script` runs. It
needs `just`, a working `GODOT_BIN` (see AGENTS.md), a display, and the
godot-mcp fork built at `~/code/godot-mcp/build/scripts/mcp_harness.gd`
(`~/DEV/git_repos/godot-mcp/...` on the Mac). Set
`URCHIN_VERIFY_HARNESS` to use another path.

## Isolation

- Each run has a name and a folder: `~/tmp/<date>-verify-urchin/<run>/`.
- The game's `user://` is `<run>/data/`, because the helper sets
  `XDG_DATA_HOME` (and `HOME` on macOS). The saves, `achievements.cfg`
  and `battle.log` of the user's own game stay untouched. `doctor` and
  `stop` prove this: they compare the size and mtime of each file in the
  real `user://` with the values at launch.
- Each run has its own harness port and token, so two runs can go at the
  same time. Each run opens a window on the user's desktop titled
  `AGENT VERIFY - <run>`. Audio is off unless you pass `--sound`.
- Do not use the godot-mcp `run_project` or `run_scene` tools for
  verification. They use the real `user://` and stop the previous game.
- Never drive a game that this skill did not start. `$V list` shows the runs.

## Launch

```bash
.claude/skills/verify-urchin/urchin_verify.py launch <run> [--preset NAME:SLOT ...] [--scene res://x.tscn] [--sound] [-- game args]
```

- No `--scene`: the main menu (`res://scenes/main_menu.tscn`).
- `--preset rich:1` copies the QA save preset `rich` into slot 1 of the
  run's own `user://` before the game starts. `just list-presets` names the
  presets. `docs/agents/godot.md` ("QA save presets") says what each holds.
- A battle with no save:
  `$V launch b109 --scene res://scenes/battle_scene.tscn -- --battle=109`.
  It uses a throwaway save in slot -1 that the game never writes.
- Ready: the harness prints its listening line, the window draws a frame
  (saved as `001-launch-1.png`), and the log has no `Parse Error`. The
  helper waits for all three and prints `"ready": true`. A launch takes
  about 15 s.
- A launch with a Parse Error fails on purpose. A stale class cache causes
  it: run `just import`, then `$V stop <run>` and launch again. On
  2026-11-21 the main checkout at `ce912cb4` failed this way with
  `Could not find type "TitlePanel"`, and the main menu showed two panels
  at once.
- An empty data folder is a new player: no saves, no achievements. The game
  needs no other setup.

## Doctor

Run it first whenever anything looks wrong. It changes nothing.

```bash
.claude/skills/verify-urchin/urchin_verify.py doctor <run>
```

It exits 1 unless all of these hold: the process group is up, a Godot
process in it runs this run's harness script, the harness answers with this
run's token, git HEAD is the commit from launch time, the run's own
`user://` exists, the real `user://` is unchanged, and the log has no Parse
Error. It also prints the last 10 `SCRIPT ERROR` lines, which do not fail
it.

## Drive

Coordinates are Stage coordinates, 800x575, the same as the screenshots.
The window size does not change them.

| Command | What it does |
| --- | --- |
| `$V tree <run> [<node>] [--depth N] [--all] [--paths]` | Lists the visible nodes under a node, with rect and text. `--all` adds hidden nodes. `--paths` prints the path that `click` and `node` take. |
| `$V node <run> <node>... [--props a,b]` | Reads nodes: class, visible, rect, center, text, and any property you name. Read-only. |
| `$V click <run> <node> [--label L] [--wait MS]` | Clicks the center of a visible Control, waits (500 ms by default), and saves a screenshot. It refuses a hidden node. |
| `$V send <run> '<json>' [--label L] [--warp]` | Sends harness commands in one sequence: `click {x,y}`, `mouse_move`, `mouse_drag {from_x,from_y,to_x,to_y}`, `key {key}` (`"Space"`, `"Ctrl+A"`), `text {text}`, `wait {duration_ms}`, `screenshot`. `@file` reads the JSON from a file. |
| `$V shot <run> <label>` | Saves a screenshot. |
| `$V log <run> [-n N] [--grep TEXT]` | Prints the Godot log. Battle lines (`[battle ...]`) go here too. |
| `$V userdir <run>` | Prints the run's `user://` path, to read saves and `logs/battle.log`. |

A node argument is a path from the current scene's root, such as
`TitlePanel/Captions/PlaySlot/HitButton`, or a bare name, such as
`InventoryButton`. A bare name takes the first visible node with that name,
so use a path when names repeat (`HitButton`, `CloseButton`, `Slot0`).
`tree --paths` prints the paths.

Each shell call costs a few seconds in Claude Code. Put input that depends
on timing, such as a radial menu pick, in one `send`.

The feature recipes are in [features/README.md](features/README.md). Use the
recipe for the feature you verify.

## Evidence

Everything goes in `~/tmp/<date>-verify-urchin/<run>/evidence/`:

- `NNN-<label>[-i].png`: each screenshot, numbered in the order taken.
  `click` saves one after each click.
- `actions.jsonl`: each request, with its commands and the harness answer.
- `preset-<name>-<slot>.log`: the output of each preset copy.
- `godot.log` and `user_data/` (the run's `saves/`, `achievements.cfg`
  and `logs/battle.log`): copied by `stop`.

Proof standards:

- Drive the player's path: clicks and keys on the controls a player uses.
  `node` and `tree` only read state. Never call game methods or set
  properties to reach a state. A QA preset or `--battle=<id>` is a setup
  step. Name it as setup in the report.
- Save the action and the result: a screenshot before and after, not only
  the last screen.
- Check the side effect as well as the screen: the money label after a
  purchase, the HP in `[battle ...]` log lines after a hit, the slot file in
  `$V userdir <run>`/`saves/` after a save.
- Report the run folder, the screenshots by name, and each `log_errors`
  line from `launch` or `doctor`.

## Cleanup

```bash
.claude/skills/verify-urchin/urchin_verify.py stop <run>
```

`stop` sends SIGTERM to the process group that `launch` started, then
SIGKILL after 10 s. It copies the log and the run's `user://` into
`evidence/`, then deletes `data/` and the wrapper script. It keeps
`evidence/` and `state.json`. It prints `real_user_dir_unchanged` and
`left_running`, which must be `true` and `[]`. Run `stop` after every
failed attempt too. Never kill Godot by name: `pkill -f` in a Bash call can
kill the tool's own shell, and it can kill the user's game.

## Gotchas

- On Linux the window must stay visible. A minimized or fully covered
  window draws no frame, so screenshots fail with "the game window drew no
  frame".
- On Linux some controls read the real cursor, not the injected one. The
  radial menu closes 0.82 s after the real cursor is away from it, and hover
  tooltips follow the real cursor. `send --warp` moves the user's real
  cursor. Ask the user before you use it.
- On macOS the helper sets `HOME` to isolate `user://`. Nobody has run
  this skill on macOS yet, so run `doctor` and check
  `real_user_dir_unchanged` there first.
- In a battle, only the first fighter presenter has a fixed name,
  `FighterPresenter`. The others get generated names such as
  `@Node2D@126`, which change from run to run. Find a fighter by the rect of
  its `Overlay/HitButton` in `tree` output.
