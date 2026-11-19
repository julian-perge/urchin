# Spec: world-map

Source issue: [#361](https://github.com/julian-perge/urchin/issues/361). Module `world-map` of [the capability map](107-capability-map.md), under [#107](https://github.com/julian-perge/urchin/issues/107). It depends on [ui-foundation](107-ui-foundation.md) (the viewport, the rect test and its extractor, `strings.json`) and on [hub](107-hub.md) (the Hub that hosts the map, the hotbar and its World Map button).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the World map as the original builds it: the root frame `overMap` (449), which places only `krinMapper` (sprite 4173) and the tooltip `KrinToolTipper` (2717). The map art sits in a 1 px frame at the mask's rect, seven zone buttons sit on it, the links between them are drawn at run time, and the Stage colour shows around the frame.

Success is that every piece sits where the SWF places it, every piece of art comes out of the SWF by script, a zone shows its name in the tooltip, and the port's own close button is gone.

## Assumptions

- Decided in this session, by the rule "take what matches the original":
  - `CloseButton` goes. The original has one way out, a zone button with `canUse`. Zone 1 always has `canUse`, so the player can always leave. No ADR, because this matches the original.
  - A locked zone shows its tooltip too. The rollOver script (`DefineButton2_4155/BUTTONCONDACTION on(rollOver).as`) does not read `canUse`. Only the release script does.
  - The Stage around the frame shows the Stage colour. Root frame 449 places nothing else (`dev/source_files/exported_assets/frames/449.png` shows the colour there). The port hides the zone art while the map shows, as it does for a Window, so the Hub's `BackgroundFill` shows.
- The three ways in stay as they are: the hotbar's World Map button, Proceed after a boss win that is not a progress fight, and the cutscenes after battles 109 and 409. [#241](https://github.com/julian-perge/urchin/issues/241) owns when Victory's Proceed opens the map.
- The zone cap (`ZoneManager.max_zone()`), the link colours and the zone access check stay as they are. `zone_map_connectors.gd` already ports `frame_449/DoAction.as`.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px. `krinMapper` sits at (400.45, 275.45) on root frame 449. The rect record reads every number below from the SWF. The table only shows them.

| Piece | Source | Box | Port node |
| --- | --- | --- | --- |
| map art | sprite 4172 without its depth 51: mask 4163, background 4171, terrain 4170, 4165 and 4167 under blend modes, highlight 4168 | the mask's rect, (20.00, 23.00) 760.95x504.95 | `MapArt`, a TextureRect |
| map frame | shape 4162 at depth 51 of 4172, a 1 px black line | (19.50, 22.50) 761.95x505.95 | `MapFrame`, a Panel with a 1 px border |
| links | `lineMC` (4161) at depth 53, under a DropShadow | drawn at run time | `Connectors` |
| zone buttons | `mb1` to `mb7` (4160) at depths 55 to 91, each under a DropShadow | centres (117.45, 455.70), (313.20, 355.80), (663.70, 443.10), (740.35, 350.30), (612.65, 215.40), (506.35, 138.95), (109.35, 185.40) | `Zones/Zone<n>` |

Each zone button holds:

- `underGF` (4159), the 30x30 face. Frame 1 is the open face 4157. Frame 2, label `blank`, is the locked face 4158.
- the 32x32 frame 4156, a 2 px black line.
- the hit button 4155, a 30x30 hit shape that draws nothing.

The port draws each zone button as a TextureButton on the hit rect, with one TextureRect child, `Art`, that shows the whole button: face, frame and DropShadow. `Art` shows one of two renders of the same size: `zone_button_open` or `zone_button_locked`.

### Art

A new extractor, `extract_zone_map` (proposed, `dev/urchin_dev/swf/extract/zone_map.py`), writes to `assets/ui/zone_map/`:

- `zone_map.png`: sprite 4172 rendered at 4x with its depth 51 hidden, trimmed. Its rect is measured from sprite 4172's origin. The blend modes and the mask render inside the sprite, so the render needs no other change.
- `zone_button_open.png` and `zone_button_locked.png`: `krinMapper`'s depth 55 (`mb1`) rendered alone at 5x, so the DropShadow on the placement is in the render. The locked render moves `underGF` to its `blank` label. Both are cut to the union of their alpha boxes, so they share one rect and one size. The rect is measured from sprite 4160's origin, so it holds for all seven placements, which have no scale.
- `zone_map.json`: the rect, size and zoom of each PNG, and the DropShadow of `lineMC` (colour, blur, angle, distance, strength).

The render driver's `goto` moves a sprite at a depth of the rendered frame only. `underGF` is one level down, inside 4160. The driver gains a `goto` that names an owner timeline, the way `hide_depths` already does, and `render.Job` gains a field for it.

The frame 4162 is an `outline` piece of the rect record, so it needs no PNG.

### Removed hand exports

`zone_map_full.png`, `zone_map_button_active.png`, `zone_map_button_inactive.png`, `zone_map_button_outer.png` and `exit_screen.png` go, with their `.import` files. Nothing else uses them.

## Behavior

From `frame_449/DoAction.as` and `DefineButton2_4155`:

- **Zone cap.** As today: `ZoneManager.max_zone()` hides the zones past the cap.
- **Open zone** (`canUse`): zone 1, or a zone whose linked zone is beaten. It shows the open face. A click sets the zone and goes to Navigation, as `_on_zone_selected` does today.
- **Locked zone**: it shows the `blank` face and a click does nothing.
- **Tooltip**: rollOver shows `ZONES[n]` over `ZONES2[n]` in the `GO` layout, the header and body sections that the hotbar's tooltip uses. rollOut hides it. Open and locked zones both show it.
- **Links**: each link is a 6 px black line, then a 2 px line, #3189df when the linked zone is beaten and #333333 when not, as today. The links now also draw `lineMC`'s DropShadow, read from `zone_map.json`. The shadow is the lines again, moved by the shadow's distance at its angle, in one CanvasGroup whose shader `scenes/ui/zone_map_shadow.gdshader` blurs them by the shadow's blur and paints its colour at its alpha times its strength. Each line has round caps, because `lineStyle` gets no caps argument and Flash then rounds both ends.
- **Hotbar**: it hides while the map shows, as today.
- **Zone art**: it hides while the map shows. `ZoneMapOverlay` joins the `menu_screen` group in `game.tscn`, so `game.gd`'s `_sync_art_visibility` covers it.

The tooltip's two sections are built in three places after this change: the hotbar, the orbs and the map. `GameTooltip` gains `show_title_and_body(title, body, anchor)` (proposed), and the three callers use it.

## Project structure

Follows `AGENTS.md`. New or changed locations:

```
dev/urchin_dev/swf/extract/zone_map.py     the extractor (proposed)
dev/urchin_dev/swf/java/Render.java        goto with an owner
dev/urchin_dev/swf/render.py               Job field for that goto
dev/urchin_dev/swf/extract/screen_rects.py the scene's SCENES entry, zone_map art source
assets/ui/zone_map/                        the three PNGs and zone_map.json
scenes/zone_map.tscn                       rebuilt at the record's rects
scripts/zones/zone_map.gd                  faces, tooltip, no close
scripts/zones/zone_map_connectors.gd       the links' DropShadow
scripts/ui/game_tooltip.gd                 show_title_and_body
```

## Code style

As in ui-foundation. The scene types its numbers into its `.tscn`, and the rect test checks them against the record. The script reads no coordinate.

## Testing strategy

- **Rect test.** `scenes/zone_map.tscn` joins `SCENES` with timeline 0 and frame `overMap`. Its pieces are `MapArt` (art), `MapFrame` (outline), and for each zone `Zones/Zone<n>` (hit, the 4155 hit shape) and `Zones/Zone<n>/Art` (art). `test/unit/test_screen_rects.gd` checks them to 0.5 px.
- **Faces (GUT).** With a save where zone 2 is locked, `Zone2/Art` shows `zone_button_locked.png`, a press does not change the zone, and `Zone1/Art` shows `zone_button_open.png`.
- **Tooltip (GUT).** Hovering zone n calls the tooltip with `ZONES[n]` and `ZONES2[n]`, read from `strings.json` in the test, for an open zone and a locked one.
- **Zone art.** The zone art hides while the map shows and comes back when it closes.
- **Extractor (pytest).** The record's math, with no SWF: the union crop gives both PNGs one rect, and the rect is moved to sprite 4160's origin.
- **Must-fail control.** Move `Zone3` 20 px in the scene and expect the rect test to fail.
- **Compare tool.** The `world_map` entry in `dev/screen_compare/screens.json` scores `zone_map.tscn` against root frame 449, with `Connectors` hidden, because `lineMC` is empty in the SWF.
- **Whole suite.** `just gut` and `just pytest` pass before each commit.

## Boundaries

- Always: take every number, colour and string from the SWF through an extractor, the rect record or `strings.json`. Commit `.png.import` sidecars.
- Ask first: a change to when the map opens. #241 owns the Victory path.
- Never: hand-cut art or hand-place a coordinate. Add a way out of the map that the original lacks.

## Out of scope

- When Victory's Proceed opens the map (#241).
- The tooltip's own layout and colours, which the tooltip spec owns.

## Success criteria

1. `test/unit/test_screen_rects.gd` checks the map, its frame and the seven buttons against the SWF, to 0.5 px.
2. Hovering a zone shows `ZONES[n]` over `ZONES2[n]`, checked against `strings.json` by a test.
3. A locked zone shows the `blank` face and does nothing on click.
4. No hand export is left in `assets/ui/zone_map/`.
5. The map has no close button, and the zone art hides while it shows.
