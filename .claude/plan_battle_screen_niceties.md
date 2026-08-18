# Implementation Plan — Battle Screen Niceties

## Problem Statement
`NEXT_PHASES.md`'s "Battle screen niceties" bullet lists 5 independent polish items for the battle screen: a decision countdown, buff icons over units, a combat log panel, target highlighting, and wiring in the already-extracted hotbar-style battle art. None share code paths except `battle_scene.gd`/`unit_overlay.gd`/`unit_overlay.tscn`, so each is scoped and shipped as its own task, sequenced smallest/safest to largest.

## Requirements
- **Hotbar battle art**: `assets/ui/battle/*.png` (4 files, already extracted, currently zero references anywhere) replace the `BottomBar`'s `ColorRect`/`StyleBoxFlat` chrome and `unit_overlay.tscn`'s default-themed `ProgressBar`s. No new extraction, no behavior change.
- **Decision countdown**: a visible timer counts down from `BattleRunner.BATTLE_TIME_LIMIT` (120s) while the player is deciding their move. Display-only — does NOT force-pass the turn on expiry (see Background for why this deliberately diverges from the original).
- **Target highlighting**: the existing hover ring fades in **fast** and out **slow** (matching the original's asymmetric `_alpha += 20`/`-= 5` per-frame rates) instead of an instant `visible` toggle, and only while it's actually the player's decision window (the original gates this on `InBattle == false`; the current port shows it on any hover regardless of turn - a real gap this fixes). The radial menu's dismissal switches from "click elsewhere closes it" (this session's earlier fix, made without confirming original behavior) to "fades out when the mouse leaves the unit+fanned-orbs area" — matching the original, confirmed by the project owner directly against the live game (the menu's own fade timing lives inside a shared symbol's internal timeline in the source, not reachable in the root-timeline AS export, so this half is taken as directly-verified fact rather than decompiled and cited).
- **Buff icons over units**: `unit_overlay.tscn` gains a small icon row (up to 7, sorted by remaining duration descending, matching the original) showing each active buff in `CombatUnit.buff_slots` - a real per-buff icon extracted from the original's own buff-icon sheet (`DefineSprite 100`, 400 frames, one per buff via frame-label lookup - see Background), tinted by the buff's element color, with the remaining-turns count and a name/description tooltip, all matching the original's `KrinBuffShower` mechanism exactly.
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
Verified directly against the decompiled source, `frame_217/PlaceObject3_3394_450/CLIPACTIONRECORD onClipEvent(enterFrame).as` and 5 sibling files (`_455`/`_460`/`_465`/`_470`/`_475` - one per battle slot):
```
onClipEvent(enterFrame){
   if(this.hitter.hitTest(_root._xmouse,_root._ymouse)) {
      if(_alpha < 100 && _root.InBattle == false) { _alpha = _alpha + 20; }
      _root.hitTarget[2] = 1; _root.HTX = _X; _root.HTY = _Y;
   } else {
      if(_alpha > 0) { _alpha = _alpha - 5; }
      _root.hitTarget[2] = 0;
   }
}
```
Each unit polls its own invisible `hitter` shape against the mouse position every frame (the era's usual technique - functionally the same thing Godot's `mouse_entered`/`mouse_exited` signals already give us more cheaply). Two concrete, previously-unknown facts this fixes:
- **The fade is asymmetric** - `+20`/frame fade-in (~5 frames to fully show), `-5`/frame fade-out (~20 frames to fully hide) - not a single symmetric tween duration.
- **The ring only fades in during the player's own decision window** (`_root.InBattle == false`) - `battle_scene.gd`'s current `_on_unit_hovered` shows the ring on ANY hover regardless of whose turn it is, a real behavioral gap from source, not just a missing-polish item.

`frame_217/DoAction_3.as`'s `onMouseDown` confirms the radial menu (`selector`) still opens on an actual click (matching `_on_unit_clicked`'s current design), gated on the same per-unit hit array (`hitTarget[i]`), and spawns at `_alpha = 0` before something fades it in - but that fade-in/out timing lives inside the shared `selector` symbol's OWN internal timeline (the same "selector" clip the abilities screen's wheel already reuses per `abilities_window.gd`'s header comment), not in any root-timeline AS file this investigation could reach. The project owner has directly verified against the live game that moving the mouse away from the unit-plus-fanned-orbs area fades both the ring and the menu out - taken as ground truth for that half, layered on top of the concretely-sourced ring-fade-rate/turn-gating facts above.

Two changes to `battle_scene.gd`:
- Replace `Ring.visible` instant toggling with a tween on `Ring.modulate.a`, asymmetric rates (fast in, slow out, matching the `+20`/`-5` ratio above), gated so it only plays while `_player_action_pending` is true.
- Remove the `_unhandled_input()` click-away handler (added this session before this investigation happened) entirely; replace with hover-leave detection that checks whether the mouse is still over the unit's own hit area OR any one of the radial menu's orb `Button`s (not just the unit alone - the orbs fan out well outside the unit's own clickable region, so a naive "left the unit" check would close the menu the instant the player moves toward an orb to click it), fading `_radial_menu` out the same way the ring does.

### Task 4: Buff icons over units
`CombatUnit.buff_slots` (`combat_unit.gd:132`) already carries everything needed per active buff: `{"cd": int, "buff_id": int, "buff_value": float, "shield_buff_value": float}` - `cd` is remaining duration in turns, `buff_id` resolves through `buffs_by_id` to the `Buff` resource.

Verified directly against `frame42/sonny2_addNewBuffKrin.txt` (lines ~355-374) - the original's real mechanism, not a fallback scheme:
```
ukcb.BUFFARRAYK.sortOn("CD", Array.DESCENDING | Array.NUMERIC);
h = 0;
while (h < 7) {
   if (ukcb.BUFFARRAYK[h].CD != 0) {
      _root["p"+ukcb.playerID+"BAR"].attachMovie("KrinBuffShower", "bshr"+h, h);
      ...["bshr"+h]._x = (buffOffsetGF + buffSpaceGF*h) * buffMultiGF;   // buffOffsetGF=110, buffSpaceGF=17, buffMultiGF = 1 or -1 by team side
      ...["bshr"+h].buffCounter = ukcb.BUFFARRAYK[h].CD;
      ...["bshr"+h].buffIcon.gotoAndStop(ukcb.BUFFARRAYK[h].buffId);
      // buffColor tinted via Color.setRGB() looked up by the buff's element against elementColorArray
      ...["bshr"+h].toolTipTitle = _root["KRINBUFF"+buffId][0];  // display name
      ...["bshr"+h].toolTip = _root["KRINBUFF"+buffId][25];       // tooltip_description
   }
   h++;
}
```
Up to 7 buff-icon slots per unit, sorted by remaining duration descending, positioned on a 17px pitch from a 110px offset (direction flipped by team side), each showing: a real per-buff icon (`buffIcon`, `DefineSprite 104`'s nested `characterId="100"` child), tinted by the buff's element color (the same `elementColorArray` lookup already ported as `MenuTheme.ELEMENT_COLORS`/`CombatUnit.ELEMENT_ORDER`), a remaining-turns counter, and a name+description tooltip.

`DefineSprite 100` is confirmed (`sprite_body()`) to be exactly the same class of asset as the item-icon sheet (2064) and ability-icon sheet (2427) already extracted this project: 400 `ShowFrameTag`s, **419 `FrameLabelTag`s named by the buff's own `internal_name`** (e.g. frame label `"FIRESAM"` matches buff id 1's `internal_name` in `buffs.json` exactly). This means extraction uses the identical label-lookup technique `item_icons.py`/`faces.py` already use (`ffdec` sprite:png export, trim to opaque bounds per frame) - not a numeric-offset guess, and not a fallback/generic-icon scheme. A new `dev/urchin_dev/swf/extract/buff_icons.py` (matching the shape of `item_icons.py`) writes `assets/ui/buffs/<internal_name>.png`; note 419 labels against 400 frames means some frames carry more than one label (aliases) - the existing `snapshot_timeline()` label-lookup helper already tolerates this, same as it does for the other icon sheets.

`unit_overlay.tscn` (`Ring`, `NameLabel`, `HealthBar`, `HealthValue`, `FocusBar`, `HitButton` today) gains a new small `HBoxContainer` row of up to 7 icon slots, refreshed from the owning `CombatUnit.buff_slots` alongside the existing bar updates, each icon `modulate`-tinted by element color (Godot can tint at runtime - no need to bake per-element-color variants into the extracted art), the remaining-turns count as a small overlaid label, and `tooltip_text` set from the buff's display name + description.

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
- Objective: match the original's confirmed hover/fade behavior exactly (asymmetric fade rate, turn-gated), correcting this session's earlier click-away guess.
- Replace `Ring.visible` toggling with a tween on `Ring.modulate.a` in `_on_unit_hovered`: fast fade-in (~0.15-0.2s), slower fade-out (~0.6-0.7s, matching the source's 4x ratio), only triggered while `_player_action_pending` is true.
- Remove `_unhandled_input()`'s click-away handler entirely.
- Add hover-leave detection for the radial menu: track whether the mouse is over the clicked unit's hit area or any radial-menu orb; when it's over none of them, fade `_radial_menu` out (tween) then free it, matching the ring's own fade treatment.
- Existing regression test `test_radial_menu_closes_on_click_away` gets rewritten to `test_radial_menu_fades_out_on_hover_leave` (or similar), asserting the new mechanic; the old click-away path is deliberately gone.
- GUT test: ring fade - assert modulate.a animates toward 1/0 across a few frames rather than snapping, and that hovering during an AI turn (`_player_action_pending == false`) does not fade it in. Radial menu - open it, simulate mouse position moving off both the unit and every orb, assert it fades out and is eventually freed; simulate hovering an orb (not the unit) and assert it stays open.
- Demo: hovering a unit fades its ring in fast, out slow, only during your own decision window; clicking opens the radial menu; moving toward one of its orbs keeps it open; moving away from the whole cluster fades both out together.

### Task 4: Buff icons over units
- Objective: every active buff on a unit shows its real icon (extracted from `DefineSprite 100`), tinted by element, with a duration counter and name+description tooltip - matching `KrinBuffShower` exactly.
- New `dev/urchin_dev/swf/extract/buff_icons.py` (mirrors `item_icons.py`): exports `DefineSprite 100` via `ffdec`'s sprite:png renderer, one PNG per `FrameLabelTag` (named by the buff's `internal_name`) into `assets/ui/buffs/<internal_name>.png`, trimmed to opaque bounds per frame. Verify frame-label-to-`buffs.json`-`internal_name` correspondence on a handful of buffs before running the full batch (same diligence as every prior icon-sheet extraction this project has done).
- New `BuffIcons.icon_for(buff: Buff) -> Texture2D` helper resolving `assets/ui/buffs/<internal_name>.png` (handling the family-of-ranked-buffs case the same way the existing extraction scripts already handle label variance).
- `unit_overlay.tscn`: new `HBoxContainer` row of up to 7 icon slots (17px pitch, matching `buffSpaceGF`); `unit_overlay.gd` refreshes it from the owning `CombatUnit.buff_slots`, sorted by `cd` descending, alongside the existing health/focus bar refresh - each icon `modulate`-tinted by `CombatUnit.ELEMENT_ORDER`/`MenuTheme.ELEMENT_COLORS` for the buff's element, an overlaid small label for `cd`, and `tooltip_text` from the buff's display name + description.
- GUT test: `BuffIcons.icon_for()` returns a real, non-null texture for a real buff id. `unit_overlay.gd`'s refresh populates the correct count/order of icon slots (sorted by `cd` descending, capped at 7) for a unit's current `buff_slots`, tints correctly by element, and clears a slot when its buff expires.
- Demo: applying a buff in battle shows its real icon over the unit immediately, tinted by element, with a tooltip naming the buff + remaining turns; it disappears when the buff expires; a unit with more than 7 active buffs shows only the 7 longest-remaining.

### Task 5: Combat log panel
- Objective: a togglable, live-narrated combat log, first of its kind in the project.
- New `CombatLogPanel` scene (`RichTextLabel` in a `ScrollContainer`), instanced into `battle_scene.tscn`, hidden by default.
- New hotbar-style toggle button (matching `hotbar.gd`'s existing button/glow convention) shows/hides it.
- New formatter (e.g. `_format_log_line(event: Dictionary) -> String` in `battle_scene.gd` or a small dedicated helper) mirrors `_play_events()`'s event-type `match`, called from the same place, appending a line to the panel and auto-scrolling to bottom.
- GUT test: feed a handful of representative synthetic events (a MOVE/DAMAGE, a MISS, a DEATH, a SPEECH) through the formatter directly and assert the produced strings name the right units/amounts; a scene-level test toggles the panel visible/hidden via the button and asserts panel content grows as `_play_events()` runs a real battle.
- Demo: opening the log panel during a real battle shows a scrolling, readable line-by-line narration of the fight so far; toggling it off hides it without losing state; toggling back on shows the same history.
