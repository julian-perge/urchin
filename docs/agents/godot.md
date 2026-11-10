# Godot and GUT

Godot and GUT behavior this project has tripped on, and the QA save presets for
testing the game by hand.

## Godot specifics

- Base resolution is 800x600 with `canvas_items` stretch, so SWF coordinates
  drop in 1:1. The SWF's own stage is 800x575, and julian-perge/urchin#111
  decided the base resolution becomes 800x575 too. Build new layouts for the
  800x575 stage, because that change is the UI overhaul's first implementation
  issue and has not landed yet.
- Pixel snapping is off so a piece is drawn at its layout position and SWF
  fractions reach the screen. `gui/common/snap_controls_to_pixels` and
  `rendering/2d/snap/snap_2d_transforms_to_pixel` both have to stay off, because
  the 2D snap alone rounds every Control again. Art draws LINEAR and the
  `NearestText` autoload keeps text NEAREST, so text stays crisp at fractional
  positions and a filter change has to recheck it (julian-perge/urchin#128,
  julian-perge/urchin#130).
- `SpriteFrames.new()` ships with a `default` animation already registered, so
  guard `add_animation()` with `has_animation()`.
- Godot's texture importer silently caps width at 32768px and rescales the
  whole image, which desyncs every region of a packed spritesheet. Use
  per-frame folders (`cf81be7`).
- A Tween whose target node is freed keeps running; the property tweener stops
  applying but callbacks still fire. Kill it explicitly (`08dc6a7`).
- A Control never shrinks its own `.size` back down once grown. Resize to
  `get_combined_minimum_size()` (`cbc2257`).
- A CanvasGroup applies its ancestors' modulate twice. Its children carry the
  modulate into the screen texture, and its built-in shader multiplies by
  `COLOR`, which carries it again. So `scenes/doll_body.gdshader` leaves `COLOR`
  out. Measured on Godot 4.7.2 for julian-perge/urchin#152: with `COLOR` in, a
  cast-tinted doll drew as the plain doll times the tint again, and a doll faded
  to 0.55 drew at 0.56 of the plain doll's alpha.
- A CanvasGroup's `fit_margin` and `clear_margin` are in screen px, so they
  cover half as much of the stage in the 2x window, and `clear_margin` grows the
  rect that `fit_margin` already grew (Godot's renderer_canvas_cull.cpp).
- A headless run draws nothing, so a test cannot see what a shader draws. Check
  it with a SceneTree script run without `--headless` that saves
  `root.get_texture().get_image()`. That script has to `load()` the scenes it
  uses, because autoloads such as `GameTooltip` don't exist yet when it compiles.
- Test tweens with `pause()` plus `custom_step(delta)`. `wait_seconds()` races
  the tween in headless and overshoots.
- GDScript `==` throws on an int/String comparison rather than returning false,
  which is useful: it catches leftover string checks after an enum conversion
  (`02f61b1`).
- The suite's total assert count is stable. It used to drift because
  `test_battle_runner.gd::test_misses_are_move_events_not_a_separate_type` ran
  battle 51 with unseeded RNG and asserted once per miss, which also failed
  outright on a zero-miss run. That test calls `seed()` now and hands the
  global RNG back with `randomize()` when it finishes. A drifting assert count
  means a new test has reintroduced unseeded RNG, so track it down rather than
  ignoring it.
- GUT has no seeding support, so a test that needs a deterministic run seeds
  Godot's global RNG itself. `partial_double` plus `stub()` is the other option
  and its stubs do intercept calls an object makes on itself, but stubbing one
  roll leaves every other `randi_range` in the run free, so it settles a single
  branch rather than making a whole battle repeatable.

## QA save presets

- QA save presets are in `dev/save_presets/`, one `.tres` per known game state.
  Copy one into a slot before launching the game, because a running game keeps
  the slot it already loaded: `dev/save_presets/apply.sh zone3_boss 3`. `--list`
  names them. A preset that depends on Legend also replaces `achievements.cfg`
  and keeps the first original as `achievements.cfg.bak`, which
  `--restore-achievements` puts back. Level 99 presets carry set stats, and
  changing equipment recomputes them from a curve that is negative by level 55,
  so use `rich` for equip checks. Rebuild them after `PlayerSave` changes with
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s
  res://dev/save_presets/generate.gd --quit-after 30`, then check the output for
  `SCRIPT ERROR`, because a script error still exits 0.
