# Spec: battle-hud

Source issue: [#67](https://github.com/julian-perge/urchin/issues/67). Parent: [#1](https://github.com/julian-perge/urchin/issues/1). It builds on [ui-foundation](107-ui-foundation.md) (landed) and on the bottom bar body that [hub](107-hub.md) built as `scenes/ui/bottom_bar.tscn`.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md). This spec adds only what is new.

This is one module, so there is no capability map. The parts below are ordered. The plan stage cuts them into tasks.

## Objective

The Battle screen matches the original's layout. Today the hall fills the whole viewport, the top is a black band, the bottom bar is two stacked frames, and each fighter carries a floating name and two bars.

After this spec:

- The hall is framed between the top panel and the bottom bar, at the SWF's rects.
- The top status bar is built from sprite 3414's parts. It shows every fighter's name, health and focus bars with numbers, and buff and debuff icons with counters, and it updates live.
- The floating name, bars and buff row over each fighter are deleted.
- The bottom bar is the shared `bottom_bar.tscn` body, with its pieces at their SWF positions and one frame per panel.
- A slot with no active Companion shows the original's inactive row, the text of `MENU[52]`.

Two Ruffle screenshots of the original show the member rows and the hidden bar: `references/sonny2_swf_inbattle_three_companions.png` (all three party members selected) and `references/sonny2_swf_inbattle_one_companion_inactive_row.png` (Veradux deselected).

Success is measured by the rect test (0.5 px per piece) and by `just compare-screen` against the original, not by eye. The original is `references/sonny2_swf_inbattle_full_ui_buffs_debuffs.png`, and `references/2026_07_18_flashpoint/9_inbattle_start*.png` shows the start of a fight.

## Assumptions

- Decided with you in this session:
  - Scope is everything in #67: the hall frame, the top bar, the floating bars, the member row and the bottom bar's double frame.
  - The top bar shows everything the original shows, live.
  - The floating name and bars are deleted, not kept behind a setting.
  - The member row works as the original's scripts do.
  - The combat log opens over the bottom bar's right panel, which is empty in the original. The Log button moves there too.
  - `TurnLabel`, the text that says whose half-turn it is, is deleted. The original has no such text.
- Decided in closed tickets and not reopened: the 800x575 Stage ([#111](https://github.com/julian-perge/urchin/issues/111)), panels as flat StyleBoxes and the extracted PNGs where a StyleBox cannot draw them ([#114](https://github.com/julian-perge/urchin/issues/114)), and the hall outline 3415 as a StyleBoxFlat with no fill.
- Guess: the port keeps one `StatusBar` scene per slot, and `FighterPresenter` writes to it as it writes to `UnitOverlay` today, so a bar changes when the event that changes it plays and not when the runner resolves it ([#44](https://github.com/julian-perge/urchin/issues/44)).
- Guess: `UnitOverlay` keeps its `Ring` and `HitButton`, because the click and hover zone over a doll is not a status element in the original.
- Names and paths marked "proposed" are this spec's choice.

## Pieces, with their SWF source

Every position below is read by script from `frame_217` (KRINBATTLESCENE) and its sprites into the rect record. No scene types a number that the record does not check.

| Piece | SWF | Stage rect or rule | How it is drawn |
| --- | --- | --- | --- |
| Top panel | the frame in `top_panel.png` | `battle_layout.json` `chrome.top_panel`: (13.73, 6.5) 773.75x118.25 | One TextureRect of the PNG. Already extracted |
| Hall window | shape 333 | `chrome.stage_rect`: (15.03, 130.0) 770x314 | A clipping Control. The hall and the fighters sit inside it |
| Hall outline | shape 3415 | edges (15, 130.4) to (785, 444.45), 1 px black line, no fill | A StyleBoxFlat with no fill ([#114](https://github.com/julian-perge/urchin/issues/114)) |
| Hall art | the hall labels | `battle_layout.json` `halls[<hall>]` | TextureRect at that rect. The full-canvas stretch goes |
| Bottom bar body | 3317 | `chrome.bottom_bar`: (13.73, 452.45) 773x111.5 | `scenes/ui/bottom_bar.tscn`, instanced. The hub built it |
| Status bars | 3414 as `p1BAR` to `p6BAR`, depths 360, 414, 378, 432, 342, 396 | six placements, scale 1.0853 by 1.1606 | Part 3 |
| Member row container | 3312 on 3317 | placement 3312_7 | `stance_row.tscn`, one per slot |
| Clock ring, alert icon, pass button, retreat button | frame 217 placements | read by the rect extractor | Part 2 |

## Part 1: The hall window

- `battle_scene.tscn`'s `Background` stops being a full-canvas TextureRect. A hall node sits at `halls[<hall>]` and a clipping Control at the hall window clips it.
- The fighters stay at `SLOT_POSITIONS`. That table already matches the six `2676` placements at all ten hall labels, so the hall moving 34 to 35 px puts each fighter on the floor it should be on.
- The sky is already placed from `battle_layout.json`. It moves under the same clipping Control.
- `BattleScreenClip` (GridZoomer and GridShaker) moves the hall and the fighters together. They stay inside the hall window while it zooms and shakes. Shape 333 is placed at depth 72 with `clipDepth` 340, so it masks depths 73 to 340, and BATTLESCREEN is at depth 89 (`frame_217/PlaceObject2_3435_89`). The top panel's bars (depths 342 to 432) are above the mask.
- The hall outline draws above the hall and below the top panel and bottom bar.
- Delete the `SkyFill` black rect if the clipping Control makes it redundant, and say so in the PR.
- `NEXT_PHASES.md` "Battle hall coordinate system - TO BE SPECCED" and `KNOWN_GAPS.md` "Top battle bar panel" and "Battle top panel frame extracted, bars not built" are marked DONE or removed by the task that lands them.

## Part 2: The bottom bar

The hub spec left the Battle screen's bar to this spec. The bar is `scenes/ui/bottom_bar.tscn`, a TextureRect of `bottom_bar.png`.

- `battle_scene.tscn`'s `BottomBar` backdrop (`hotbar_background.png`) and `Panel1` to `Panel3` (the hub hotbar's `background.png`) go. Each panel has one frame.
- These pieces move onto the bar at their SWF positions: the stance host, the pass button and ring, the alert icon, the retreat button, and the clock ring.
- The right panel is empty in the original. The Log button and the Combat log panel go there, as decided. They are port additions, so the rect test does not check them, and the panel's rect is the right panel's inner rect.
- The countdown label keeps its job from [#30](https://github.com/julian-perge/urchin/issues/30). It sits on the clock ring where the original's `thingerClock` is, not in the right panel.
- `TurnLabel` is deleted. This leaves the port with no sign of whose half-turn it is. The original gives it with `thingerClock` frames `friend` and `enemy` (`frame_217/PlaceObject2_3389_480` `onClipEvent(load)` lines 9 to 16, and the `enterFrame` script at 696 to 702). This spec adds the clock ring with those two frames, so the player keeps the cue. The two frames come out of the SWF with ffdec at zoom 4 and sit at the clock ring's SWF rect, and the rect test checks that rect. You confirmed this is in scope.

## Part 3: The top status bar

One `StatusBar` scene per slot (proposed `scenes/battle/status_bar.tscn`), six instances in a `TopStatusBar` host (proposed `scenes/battle/top_status_bar.tscn`) that sits on `top_panel.png`.

Sprite 3414 holds `inner` (3407, 16 frames, labels `second` and `third`) with the text and the bar backing, and `inner2` (3413) with the bars: `lB`, `lB2`, `lB3` for life and `fB`, `fB2`, `fB3` for focus. Each bar is placed at x -2000 twips with scale 0.787, so its fill is a width that the script sets.

- Slots 1, 3 and 5 sit on the left and 2, 4 and 6 on the right. The right-hand bars (p2, p4, p6) go to frame `second` and set `inner2._xscale = -100`, as their load scripts do (`PlaceObject3_3414_396`, `_414`, `_432`). The left bars stay on the first frame.
- A slot whose unit is not active has its bar hidden (`frame_217/PlaceObject2_3389_480` `onClipEvent(load)`, lines 19 to 28). The other bars stay where they are and do not close the gap. Your Ruffle screenshots show it: with three Companion slots filled the left bars read Roald (slot 5), Sonny (slot 1) and Veradux (slot 3) from the top, and with Veradux deselected the third bar is gone and the first two do not move.
- Text: the name, `lifeNow` and `lifeMax`, and `focusNow` and `focusMax`. They come from `lifeBarUpdate` (`frame_42/DoAction_8.as:271-276`). The rect record holds each field's rect, font height and color.
- Bars: `lifeBarUpdate` (`frame_42/DoAction_8.as:271-356`) sets each fill's width to `wsaver` times the share. The life fill's color clip steps to frame `round(share * 100) + 1`. The smoother clips (`LifeBarSmoother` and `LifeBarSmoother2`) show a loss or a heal as a trailing band. The first update after the battle opens sets the widths with no smoother. The port ports this logic, with `wsaver`, the smoother clips and the color frames read by script.
- Buff icons: one `KrinBuffShower` for each of the seven slots whose duration is not 0, in slot order, at x `(110 + 17 * h) * side`, where `side` is 1 on the player's side and -1 on the enemy's side (`frame_42/DoAction_10.as:340-379`). Each icon gets the buff's frame, its element color, its counter, and its tooltip title and text. `UnitOverlay` already does this for the floating row. The code moves to the status bar, and the constants 110 and 17 come from an extractor that reads those AS lines.
- The bars carry the 3414 DropShadow filter (blur 5, distance 3, strength 0.72), which is baked into the extracted art or set by the shared shader, as the rect test's shadow check requires.

Art comes out of the SWF with ffdec at zoom 4 by a new extractor (proposed `uv run extract_top_bar`), written to `assets/ui/battle/top_bar/`. It writes each piece's rect and the constants to one JSON file, and a second run writes the same bytes.

## Part 4: The member row

`stance_row.tscn` is sprite 3311 with two frames: `active` (frame 1: the name and five stance buttons) and `inactive` (frame 9: the text of `MENU[52]`).

- The port builds a row only for a unit whose `origin` is COMPANION. It builds none for an empty slot. The original shows `inactive` for a slot 3 or 5 whose unit is not `active`, and `active` for one that is.
- Each row has a fixed place by slot: slot 5's row is the upper one and slot 3's the lower one, as the fighters stand. Your Ruffle screenshots show it. With all three party members selected, the rows read Roald then Veradux. With Veradux deselected, Roald's row stays on top and the lower row shows the inactive text. The port today stacks only the rows it builds, so one Companion in slot 3 would sit in the upper row. That is wrong.
- The container refreshes at each of the player's Decisions (`frame_217/PlaceObject2_3389_480` `enterFrame`, lines 696 to 746). It shows during the player's half-turn and hides during the enemy's.
- Keep the Tutorial rule (battle 2 hides the container) and the guest rule in `DECODED_ALGORITHMS.md` ("No guest ever shows a stance row"). Check what a guest slot shows in the `inactive` frame in the original, and record it. Open question 1.
- The text is `Strings.menu(52)`. The strings extractor already writes it.
- A companion who dies has `active = false`, so its row flips to `inactive` at the next Decision.

## Part 5: Delete the floating status elements

- `UnitOverlay` loses `NameLabel`, `HealthBar`, `HealthValue`, `FocusBar` and `BuffRow`. It keeps `Ring` and `HitButton`.
- `FighterPresenter` passes the displayed state to its `StatusBar`, and the hover ring and hit zone stay on the overlay.
- Tests that read the deleted nodes move to the status bar. A test that checks a deleted node's value is deleted with it, and the replacement test checks the same fact on the new node.

## Project structure

Follows `AGENTS.md`. New locations:

```
scenes/battle/status_bar.tscn                 one fighter's entry (proposed)
scenes/battle/top_status_bar.tscn             the host on the top panel (proposed)
scripts/battle/status_bar.gd                  bars, numbers, buff icons (proposed)
scripts/battle/top_status_bar.gd              slot to bar, side, hidden slots (proposed)
assets/ui/battle/top_bar/                     zoom 4 pieces and the JSON (proposed)
dev/urchin_dev/swf/extract/top_bar.py         the extractor (proposed)
dev/tests/test_top_bar.py                     its pytest tests, on a small AS sample
```

`GLOSSARY.md` gets two terms, proposed: **Status bar** (one fighter's entry in the top status bar, the original's `pNBAR`) and **Hall window** (the 770x314 area that shape 333 clips the hall to). The HUD term already names the top status bar.

## Code style

```gdscript
# A bar's fill is its extracted full width times the share. Nothing here types a width.
func _show_life(now: float, maximum: float) -> void:
	var share: float = now / maxf(maximum, 1.0)
	_life_fill.size.x = _extract.life_width * share
	_life_color.frame = roundi(share * 100.0) + 1
```

This snippet shows the style only. Each width, scale and frame count is read from the extractor's JSON.

## Testing strategy

- **Rect test.** Add `battle_scene.tscn` to the record, with the top panel, the hall window, the hall outline, the bottom bar, each status bar's backing, text fields and fill at full, the stance rows and the clock ring. Every piece passes under 0.5 px, and every Label's size and color match.
- **Extractor.** `uv run pytest` tests read an AS sample and a small XML sample, never the SWF. A second run writes the same bytes.
- **Status bar.** GUT unit tests read the extracted widths and constants. Cases: full life, half life, zero life, a heal after a loss, the first update with no smoother, a hidden slot, a right-hand bar's mirror, seven buff icons at their x on each side, a counter, and a buff at duration 0 not shown.
- **Presenter.** A GUT integration test checks that the bar changes when the event plays and not before.
- **Member row.** Cases: an active companion shows five buttons, an empty slot shows the inactive text, a death flips the row at the next Decision, and the container hides on an enemy half-turn and in battle 2.
- **Hall.** A GUT test checks that each fighter's feet land on the hall's ground line for all ten hall labels.
- **Compare tool.** Add a `battle` entry. It scores the panels, the hall window's edge and the bars at rest, with text hidden. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Prove it can fail.** For each new test, break the line it claims to pin and watch it go red, as `CODING_STANDARDS.md` says.
- Use the QA save presets in `docs/agents/godot.md` for a manual look at the Hydra fight (battle 408) and battle 109.

## Boundaries

- Always: Run `just gut` before each commit. Read every number from the SWF through an extractor. Commit `.png.import` sidecars with the art.
- Ask first: A new dependency. A change to the rect tolerance. Another ADR.
- Never: Hand-place a coordinate that the rect record does not check. Run ffdec concurrently. Run a windowed render without the `AGENT RENDER` title. Change `SLOT_POSITIONS`.

## Success criteria

1. The hall sits at its SWF rect inside the hall window, and each fighter's feet are on the hall's ground line in all ten halls.
2. The top status bar shows every active fighter's name, life and focus with numbers, and buff and debuff icons with counters. It updates when the event plays.
3. No name, bar or buff row floats over a fighter.
4. The bottom bar is one frame per panel, the pieces are at their SWF positions, and an empty Companion slot shows the inactive row.
5. The rect test passes with every new piece, and its 20 px control fails.
6. `just compare-screen battle` passes its bar, and the shifted control scores over it.
7. `KNOWN_GAPS.md` and `NEXT_PHASES.md` no longer list these as open.

## Out of scope (Deferred)

- The countdown number's own logic: [#30](https://github.com/julian-perge/urchin/issues/30) is closed and the label keeps what it does.
- The speech box: [#156](https://github.com/julian-perge/urchin/issues/156).
- The Combat text banner and the other battle presentation differences: [#158](https://github.com/julian-perge/urchin/issues/158).
- Zone 4 boss dolls: [#162](https://github.com/julian-perge/urchin/issues/162).
- The bottom bar frame difference between ffdec and the Flash Player screenshots: [#299](https://github.com/julian-perge/urchin/issues/299).
- Battle art and the doll rigs.

## Open questions

1. What does a guest in slot 3 or 5 show in the original's `inactive` or `active` frame? `DECODED_ALGORITHMS.md` says no guest gets a row, and it was read from the AS only.

Settled in review: the compare reference is the ffdec render of frame 217 in a fixed state with the dolls masked out, and the screenshot stays as the check by eye. The clock ring with its `friend` and `enemy` frames is in scope.
