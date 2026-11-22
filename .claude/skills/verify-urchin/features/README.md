# urchin verification map

This folder is the maintained source for verifying what a player can do in
urchin. Read this index before you drive the game, then use the matching
feature file as the recipe. `$V` is
`.claude/skills/verify-urchin/urchin_verify.py`, run from the repo root.

## Baseline preconditions

- `just import` has run in this checkout since the last `class_name` or
  `assets/` change.
- Each recipe names its launch line. The run name in the recipes is `v`.
  Use a new name for each run.
- `$V doctor v` passes before the first input.
- Never drive a game that this verification run did not start.

## Driving conventions

- Click by node path with `$V click`. Get paths with `$V tree v <node> --paths`.
- Put input that depends on timing in one `$V send`.
- Give each action a `--label` that names the feature and the step.
- Run `$V stop v` at the end, and after each failed attempt.

## Proof and skip reporting

- Save a screenshot before and after each user action.
- Check one side effect away from the screen as well: a label value read
  with `$V node`, a `[battle ...]` line in `$V log`, or a file under
  `$V userdir v`.
- Name each setup step (a preset, `--battle=<id>`) as setup, not as part of
  the journey.
- Report a journey that cannot run with the command you tried and the
  precondition that failed. Do not report it as verified through another
  entry point.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph about what the
player sees. Then it has exactly four H2 sections in this order:
`Sub-features`, `How to get to it (user POV)`,
`Driving it with urchin_verify`, and `Gotchas`. A step that nobody has
driven yet says "Not yet driven".

## Features

- [Main menu](./main-menu.md): title, New Game (name, slot, class, settings), Load Game.
- [Zone hub](./hub.md): the hub art, its orbs and the hotbar.
- [Battle](./battle.md): speech skip, the radial menu attack, pass, stances, the battle log.
- [Store](./store.md): buy a ware, money and inventory change.
- [Inventory](./inventory.md): open and close the window, the equip slots and the item grid.
