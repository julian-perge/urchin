# Implementation Plan — Battle Screen Niceties

## Problem Statement
`NEXT_PHASES.md`'s "Battle screen niceties" bullet lists 5 independent polish items for the battle screen: a decision countdown, buff icons over units, a combat log panel, target highlighting, and wiring in the already-extracted hotbar-style battle art. None share code paths except `battle_scene.gd`/`unit_overlay.gd`/`unit_overlay.tscn`, so each is scoped and shipped as its own task, sequenced smallest/safest to largest.

## Requirements
- **Hotbar battle art**: `assets/ui/battle/*.png` (4 files, already extracted, currently zero references anywhere) replace the `BottomBar`'s `ColorRect`/`StyleBoxFlat` chrome and `unit_overlay.tscn`'s default-themed `ProgressBar`s. No new extraction, no behavior change.
- **Decision countdown**: a visible timer counts down from `BattleRunner.BATTLE_TIME_LIMIT` (120s) while the player is deciding their move. Display-only — does NOT force-pass the turn on expiry (see Background for why this deliberately diverges from the original).
- **Target highlighting**: the existing hover ring fades in/out via tween instead of an instant `visible` toggle. The radial menu's dismissal switches from "click elsewhere closes it" (this session's earlier fix, made without confirming original behavior) to "fades out when the mouse leaves the unit+fanned-orbs area" — matching the original, confirmed by the project owner directly against the live game.
- **Buff icons over units**: `unit_overlay.tscn` gains a small icon row showing each active buff in `CombatUnit.buff_slots`. A buff resolves to a real icon when its name matches one of the 15 talent-tree `buff_family` values already used by the abilities screen; everything else (the other ~455 of 470 buffs) falls back to a colored dot by polarity, with a tooltip carrying the buff's name and remaining duration.
- **Combat log panel**: a new toggleable hotbar button shows/hides a scrolling text panel (off by default) that narrates `BattleRunner` events live as they play — the first `RichTextLabel`/`ScrollContainer` panel in the project, no existing pattern to copy.
- Every item ships with GUT coverage matching what's actually testable (pure logic and structural pieces get direct tests; anything requiring real animation timing or literal pixel rendering is spot-checked manually instead, same restraint already established elsewhere in this codebase for `CharacterVisual` state).

## Background

### Sequencing
Smallest/safest to largest, since nothing here depends on anything else in this list:
1. Hotbar battle art (pure asset wiring)
2. Decision countdown (small, self-contained new UI + timer)
3. Target highlighting (touches existing, working code — do it early while that code is fresh, before buff icons/combat log add more surface area to `unit_overlay.tscn`/`battle_scene.gd`)
4. Buff icons over units (medium, touches `unit_overlay.tscn` which task 3 also touches — do after 3 lands)
5. Combat log panel (medium, biggest net-new surface, fully independent of 1-4)

### Task 1: Hotbar battle art
`assets/ui/battle/` holds `battle_pbar_full.png` (199K), `battle_progress_bar_inner.png` (3.5K), `hotbar_background.png` (3.4K), `hotbar_team_select.png` (120K) — confirmed via `grep -rl "assets/ui/battle"` to have zero references anywhere in `scenes/`/`scripts/`. Today's actual battle-screen chrome: `BottomBar/Backdrop` is a plain `ColorRect` (`Color(0.04, 0.05, 0.06, 1)`), `Panel1`/`Panel2`/`Panel3` use a *different* file (`assets/ui/hotbar/background.png`, a sibling directory — not one of these four), `PassButton`/`RetreatButton` are hand-authored `StyleBoxFlat`s with no texture, and `unit_overlay.tscn`'s `HealthBar`/`FocusBar` are stock Godot-themed `ProgressBar`s with no `StyleBoxTexture` override, despite `battle_pbar_full.png`/`battle_progress_bar_inner.png` being named exactly for that job.

Before wiring anything, open each of the 4 PNGs to confirm actual content/dimensions against its apparent name — `hotbar_team_select.png`'s name suggests it may belong to the stance-row/team-order UI rather than the literal bottom-bar backdrop, and that needs eyes-on confirmation, not a guess from the filename alone.

### Task 2: Decision countdown
`BattleRunner.BATTLE_TIME_LIMIT` (`battle_runner.gd:44`, `const BATTLE_TIME_LIMIT: float = 120.0`) is a dead constant today — referenced nowhere else in the repo, no ticking state, no UI. The file's own header comment already documents why: *"The original ran real-time with a 120-second decision countdown... this port is the turn-based flow... The countdown is a UI-layer concern (BATTLE_TIME_LIMIT is exposed for it)."*

The original (`dev/source_files/action_script_curated/frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt`) genuinely force-passed the turn at 120s — a real gameplay mechanic, not just visual pressure. This plan deliberately does NOT port that half: this project's turn-based flow already removed real-time pressure entirely (no other decision in the game is time-limited), and reintroducing a forced timeout now would be a meaningful gameplay-affecting change the project owner hasn't asked for. Ship the countdown as visual flavor only, and record the omission in `NEXT_PHASES.md`/`KNOWN_GAPS.md` the same way other deliberate simplifications already are.

`BattleRunner` is a `RefCounted`, not a `Node` — it has no `_process()` and can't drive a timer itself. The timer lives on `battle_scene.gd`, which already has a scene tree.

### Task 3: Target highlighting
Two independent, small changes to existing working code in `battle_scene.gd`:
- The hover ring (`_rings`, `RING_COLORS`, `_on_unit_hovered`, `_draw_ring`) currently toggles `Ring.visible` instantly on `mouse_entered`/`mouse_exited`. Replace with a tween fading `Ring.modulate.a` between 0 and 1.
- The radial menu (`_radial_menu`, opened by `_on_unit_clicked`) currently closes via `_unhandled_input()` on any click outside it (added this session, before the project owner had confirmed the original's actual behavior against the live game). The project owner has now confirmed directly against the original: it fades out when the mouse leaves the unit-plus-fanned-orbs area, not on a click elsewhere. Remove the `_unhandled_input()` click-away handler; replace with hover-leave detection that checks whether the mouse is still over the unit's own hit area OR any one of the radial menu's orb `Button`s (not just the unit alone — the orbs fan out well outside the unit's own clickable region, so a naive "left the unit" check would close the menu the instant the player moves toward an orb to click it).

### Task 4: Buff icons over units
`CombatUnit.buff_slots` (`combat_unit.gd:132`) already carries everything needed per active buff: `{"cd": int, "buff_id": int, "buff_value": float, "shield_buff_value": float}` — `cd` is remaining duration in turns, `buff_id` resolves through `buffs_by_id` to the `Buff` resource for its name/polarity.

Icon coverage is the real gap. `assets/ui/abilities/*.png` (104 files) covers the abilities screen's talent-tree nodes via `abilities_window.gd`'s `_tree_node_icon_key()` → `_sanitize_icon_key(buff_family)` → `"%s%s.png"` lookup, but `buff_family` is a field on *talent-tree nodes* (`talent_tree.gd`), not on `Buff` itself, and only 15 distinct `buff_family` values exist against 470 total buffs in `dev/converted_json/buffs.json`. A buff applied by a move in combat (poison, a debuff, a shield) generally has no icon association today. New `BuffIcons.icon_for(buff: Buff) -> Texture2D`-style helper: strip a trailing rank digit off `buff.internal_name` and try the same `assets/ui/abilities/` lookup first (covers the 15 known families when they happen to apply); fall back to a small colored dot by `buff.polarity` (1 = beneficial = green, -1 = harmful = red, 0 = neutral = gray, reusing `MenuTheme`'s existing palette) with a tooltip carrying `buff.display_name`/`internal_name` and `cd`.

`unit_overlay.tscn` (`Ring`, `NameLabel`, `HealthBar`, `HealthValue`, `FocusBar`, `HitButton` today) gains a new small `HBoxContainer` row for these icons, refreshed alongside the existing bar updates.

Full icon extraction/art for all 470 buffs is out of scope here — same shape as the already-deferred missile-projectile-art backlog item, a separate follow-up if wanted later.

### Task 5: Combat log panel
`LogManagerAuto` (`scripts/autoload/log_manager.gd`) is confirmed file-only (`user://logs/<channel>.log`) — no in-memory buffer, no signal, purely a developer diagnostic `battle_scene.gd:_log()` already writes to. This task is a separate, new, player-facing panel, not a reuse of that logger.

No `RichTextLabel` or `ScrollContainer` exists anywhere in the project today — this is the first scrollable-text UI, built fresh rather than copied from an existing pattern.

`BattleRunner.events` already carries what's needed to narrate a battle: each entry is tagged with `EventType` (`MOVE, STUNNED, MOVE_FAILED, DISPEL, DEATH, SPEECH, PHASE_ADVANCED, BATTLE_ENDED`), a `MOVE` entry carries `caster_slot`/`target_slot`/`move_id`/`move_name`/a `result` dict (`ResultType.DAMAGE`/`HEAL`/`FOCUS`/`MISS`, `amount`, `did_crit`, `target_died`). Slots are raw ints; `battle_scene.gd` already has a `units` dict to resolve slot → unit name. A new formatter mirrors the exact `match` structure `_play_events()` already uses to drive animation/audio, producing one line per event (e.g. `"Veradux hits Grulnak with Acid Slash for 42"`), appended to the log panel live as each event plays, auto-scrolling to the bottom.

Toggleable via a new hotbar-style button, matching the existing menu-button convention (`hotbar.gd`'s green active-icon glow pattern) rather than inventing a new toggle style. Off by default.

## Task Breakdown

### Task 1: Wire in the extracted hotbar battle art
- Objective: replace programmer-art chrome with the 4 already-extracted PNGs, confirmed against their real content first.
- Open each PNG to confirm its actual intended slot before wiring (dimensions/visual content vs. filename).
- Swap `BottomBar/Backdrop`'s `ColorRect` for the confirmed backdrop texture; `unit_overlay.tscn`'s `HealthBar`/`FocusBar` get `StyleBoxTexture` overrides using `battle_pbar_full.png`/`battle_progress_bar_inner.png` (fill/background) instead of default theme.
- No behavior change - purely visual. Demo: battle screen renders with the original's real chrome instead of placeholder colors/default Godot bars.

### Task 2: Decision countdown display
- Objective: a visible, ticking-down timer during the player's decision window, no forced pass.
- `battle_scene.gd`: a `_decision_timer: float` reset to `BattleRunner.BATTLE_TIME_LIMIT` whenever `_player_action_pending` becomes true, ticking down via `_process(delta)` only while it's true, clamped at 0 (never negative, never forces anything).
- New Label/bar near the Pass ring in `BottomBar`, showing the remaining time.
- Document the no-force-pass divergence in `NEXT_PHASES.md`.
- GUT test: instantiate the battle scene, set `_player_action_pending = true`, advance several `_process(delta)` calls, assert the timer decreases and clamps at 0; assert it resets when a new decision window opens.
- Demo: starting your turn shows the timer counting down; letting it hit 0 does nothing but sit at 0 (no forced pass, no error).

### Task 3: Fade-based target highlighting + radial menu dismissal
- Objective: match the original's confirmed hover/fade behavior exactly, correcting this session's earlier click-away guess.
- Replace `Ring.visible` toggling with a tween on `Ring.modulate.a` (0 <-> 1) in `_on_unit_hovered`.
- Remove `_unhandled_input()`'s click-away handler entirely.
- Add hover-leave detection for the radial menu: track whether the mouse is over the clicked unit's hit area or any radial-menu orb; when it's over none of them, fade `_radial_menu` out (tween) then free it, matching the ring's own fade treatment.
- Existing regression test `test_radial_menu_closes_on_click_away` gets rewritten to `test_radial_menu_fades_out_on_hover_leave` (or similar), asserting the new mechanic; the old click-away path is deliberately gone.
- GUT test: ring fade - assert modulate.a animates toward 1/0 across a few frames rather than snapping. Radial menu - open it, simulate mouse position moving off both the unit and every orb, assert it fades out and is eventually freed; simulate hovering an orb (not the unit) and assert it stays open.
- Demo: hovering a unit fades its ring in smoothly; clicking opens the radial menu; moving toward one of its orbs keeps it open; moving away from the whole cluster fades both out together.

### Task 4: Buff icons over units
- Objective: every active buff on a unit shows an icon (real when available, a polarity-colored fallback otherwise) with a duration tooltip.
- New `BuffIcons.icon_for(buff: Buff) -> Texture2D` (or similar small helper/autoload-free class) implementing the strip-rank-digit-then-lookup-then-fallback logic described in Background.
- `unit_overlay.tscn`: new `HBoxContainer` row of small icon slots; `unit_overlay.gd` refreshes it from the owning `CombatUnit.buff_slots` alongside the existing health/focus bar refresh.
- GUT test: `BuffIcons.icon_for()` returns the real icon texture for a buff whose name matches one of the 15 known families, and a valid fallback (non-null, distinguishable by polarity) for one that doesn't. `unit_overlay.gd`'s refresh populates the correct count of icon slots for a unit's current `buff_slots`, clears them when a buff expires.
- Demo: applying a buff in battle shows its icon (or fallback dot) over the unit immediately, with a tooltip naming the buff and remaining turns; it disappears when the buff expires.

### Task 5: Combat log panel
- Objective: a togglable, live-narrated combat log, first of its kind in the project.
- New `CombatLogPanel` scene (`RichTextLabel` in a `ScrollContainer`), instanced into `battle_scene.tscn`, hidden by default.
- New hotbar-style toggle button (matching `hotbar.gd`'s existing button/glow convention) shows/hides it.
- New formatter (e.g. `_format_log_line(event: Dictionary) -> String` in `battle_scene.gd` or a small dedicated helper) mirrors `_play_events()`'s event-type `match`, called from the same place, appending a line to the panel and auto-scrolling to bottom.
- GUT test: feed a handful of representative synthetic events (a MOVE/DAMAGE, a MISS, a DEATH, a SPEECH) through the formatter directly and assert the produced strings name the right units/amounts; a scene-level test toggles the panel visible/hidden via the button and asserts panel content grows as `_play_events()` runs a real battle.
- Demo: opening the log panel during a real battle shows a scrolling, readable line-by-line narration of the fight so far; toggling it off hides it without losing state; toggling back on shows the same history.
