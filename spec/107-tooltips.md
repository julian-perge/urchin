# Spec: tooltips

Source issue: [#364](https://github.com/julian-perge/urchin/issues/364). Module `tooltips` of [the capability map](107-capability-map.md). It depends on [ui-foundation](107-ui-foundation.md) (`strings.json` and its `Strings` loader) and changes callers that [window-shell](107-window-shell.md), [inventory](107-inventory.md), [abilities](107-abilities.md) and the battle screen own.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/actionscript.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md). AS paths are relative to `dev/source_files/action_script/`, and character ids are the web build's.

## Objective

Make the shared tooltip, `GameTooltip` (`scripts/ui/game_tooltip.gd`), look and move like the original's `KrinToolTipper` (DefineSprite 2717), and move the last native Godot tooltips onto it. Every Window spec of #107 left the tooltip's look to this spec.

Success is that:

- the title bar is the gradient of sprite 2715, tinted by the item's rarity when an item slot shows it;
- every text field the original draws with `border = true` has its 1 px border;
- the tooltip follows the mouse at the field offsets of the frame scripts, and flips to the mouse's left near the right edge;
- an ability icon's tooltip shows only its title for the first 5 frames of a hover;
- no `tooltip_text` is left in `scenes/` or `scripts/`;
- every value from the original comes from an extractor's output, and the tests read the same output.

## Assumptions

- Each open question was answered in the spec session by the rule "take what matches the original" (orchestrator rule for this run). Two answers depart from the original. They are recorded in ADR 0005 (an Original bug) and ADR 0012 (keep the tooltip on the Stage).
- The tooltip's text content stays as each caller builds it today, except for the callers this spec names.
- A test cannot see a gradient in a headless run. Tests check the colors the code builds, not pixels.

## The original

### The clip

- `KrinToolTipper` is placed at (800, 600) on root frames 74, 84, 181, 217 and 449. Each placement's enterFrame calls `this.startDrag(true)` (`frame_181/PlaceObject2_2717_1612/CLIPACTIONRECORD onClipEvent(enterFrame).as`), so the clip's origin is at the mouse on every frame.
- Its labels are `none` (1), `GO` (4), `GO2` (7), `GO3` (10), `GO4` (13), `GO5` (16) and `GO7` (17). Each label's frame script builds the text fields at run time and sizes a backer clip to each field.
  - `GO` (`frame_4/DoAction.as`): the title `my_txt2` and the body `my_txt`, 170 px wide. The plain layout.
  - `GO2` (`frame_7`): the title, the sub-header `my_txt3` and the body, 150 px wide.
  - `GO3` (`frame_10`): the title alone, 150 px wide. It hides `fontBacker` and `fontBacker3`.
  - `GO4` (`frame_13`): the item layout, 200 px wide. The title, the level line `my_txt3`, the stat lines `MY_TX<n>`, the flavor line `ttt`, and the empty field `my_txt4` that frames the stat and flavor lines.
  - `GO5` (`frame_16`) removes the stat lines and goes to `GO4`.
  - `GO7` (`frame_17`): the ability layout, 150 px wide. The title, the sub-header, the body and the next-rank field `my_txt4`.
- The frame scripts place the fields at x `scaffold`. It is 13 when `_root._xmouse < 570`, and the field width plus 13, negative, when not: -183 in `GO`, -213 in `GO4`, -163 in the 150 px layouts. Only `GO` also moves every field up 50 px (`scaffold2`) when `_root._ymouse > 500`.
- The title is at y 0 in every layout, and each field below starts 2 px under the one above it.

### The backers

Read from the SWF by `extract_tooltip_look` (below):

| Instance | Sprite, shape | Fill | Color transform on the timeline |
| --- | --- | --- | --- |
| `fontBacker2` (title) | 2715, 2714 | linear gradient, top to bottom: ratio 0 #ffffff a255, ratio 60 #aaaaaa a217, ratio 177 #ffffff a217, ratio 255 #ffffff a255 | none |
| `fontBacker3` (sub-header and level line) | 2715, 2714 | the same gradient | add (-31, -6, 0) in `GO2` and `GO7`, (5, -41, 96) in `GO3`, none in `GO4` |
| `fontBacker` (body) | 2716, 68 | solid #000000 a230 | none |
| `fontBacker4` (next rank) | 2716, 68 | the same | multiply (0, 0, 0, 1), add (50, 40, 53, 0) in `GO7` |

- The gradient's matrix turns it 90 degrees and scales it to the shape's 30 px box, so it runs from the field's top edge to its bottom edge at every field height.
- `GO` and `GO4` call `_root.krinChangeColor(fontBacker2, colorChange)` when `colorChange != 0`. `krinChangeColor` (`frame_42/DoAction_3.as:49-93`) sets add terms by name: Common (0, 0, 0), Uncommon (-62, -51, 0), Rare (86, 0, -164), Orange (126, 15, -200) and Unique (-67, 0, -159).
- An item slot sets `colorChange` to the item's rarity, `KRINITEM<id>[2]` (`DefineButton2_2985` and `DefineButton2_3012` on(rollOver), line 3, and `DefineButton2_2981` for the equip slots). The delete and sell slots and the hotbar buttons set "Common".
- Frame 1 (`none`) resets `colorChage`, not `colorChange` (`DefineSprite_2717/frame_1/DoAction.as:15`). So a caller that sets no rarity, such as the stance buttons, gets the tint of the last item the player hovered. This is an Original bug (ADR 0005).

### The borders

`border = true` on the title, the sub-header, the level line, the body, the next-rank field and `my_txt4`, which frames the item's stat and flavor lines. The stat lines and the flavor line have `border = false`, and they sit inside `my_txt4`. A TextField border is a 1 px line in `borderColor`, which no script sets, so it is black.

### The ability icon's delay

The ability icon, sprite 2427, drives the tooltip from its enterFrame (`DefineSprite_2427/frame_1/PlaceObject2_2241_11/CLIPACTIONRECORD onClipEvent(enterFrame).as`). While the mouse is over it, the icon plays `GO3` (the title alone) and counts `hitter` up by one on each frame. When `hitter == 5`, it plays `GO7` on a talent tree node (`OKAY`, set by `DefineSprite_3142/frame_25/PlaceObject3_3100_153`) and `GO2` on any other icon. The SWF runs at 30 frames a second, so the title shows alone for 5 / 30 s. An icon whose parent sets `chimney` plays `GO` at once. The only such icon is `krinToMove` (below).

### The callers this spec moves

| Piece | Original | Title | Body | Layout |
| --- | --- | --- | --- | --- |
| Delete slot | `DefineButton2_2858` on(rollOver) | `MENU[1]` | `MENU[2]` | `GO` |
| Sell slot | `DefineButton2_3015` on(rollOver), placed only at KRINMENU's `shop` label | `MENU[3]` | `MENU[4]` + " €" + `ceil(price * 0.15)` while an item is on the mouse, else `MENU[5]` | `GO` |
| Empty backpack cell | `DefineButton2_2985` on(rollOver) with item 0 | item 0's name, "None" | item 0's `toolTip`, "This slot is empty." | `GO`, because item 0's type is under 2 |
| Stance button n | `DefineSprite_3306`, enterFrame of `PlaceObject2_3305_1` | `MENU[54 + n]` + " " + `MENU[64]` | `MENU[59 + n]` | `GO` |
| Empty ability socket | `DefineSprite_3142/frame_25/DoAction.as:86-88` | `SKILLNONE` | `SKILLTUT2` (sub-header), `SKILLTUT` (body) | as the abilities spec builds it |
| Pass button | `krinToMove`, 2427 at root frame 217 depth 484, under the pass button 3383 (`frame_217/PlaceObject2_2427_484/CLIPACTIONRECORD onClipEvent(load).as`) | "No ability selected!" | "You may click here to skip your turn." in the turn-based mode, "First select your target then choose an ability to use." in the other | `GO`, at once (`chimney`) |

- The issue guessed that the Store's sell price is `round(price / 3)` (`DefineButton2_3121`). The SWF places 3121 only at KRINMENU's `data` label, scaled to the size of a save slot, and its press calls `krinHandleData(1)`. It is not the Store's sell slot. The Store's sell slot is 3015, so the port's 15% is right for the tooltip and the sale.
- `frame_201/DoAction.as:66-78` sets `turnBasedKrin` on difficulties 0 and 1. `battle_scene.gd` keeps the same choice in `_turn_based`.
- The empty ability socket already reads its strings (#225). This spec adds its test.
- The combat log's toggle has no original (ADR 0001). Its tooltip "Toggle the combat log" goes, with no replacement.

## The data: `extract_tooltip_look`

A new entry point, `uv run extract_tooltip_look` (`dev/urchin_dev/swf/extract/tooltip_look.py`, recipe `just extract-tooltip-look`). It reads the SWF without ffdec, and the AS export. It writes `dev/converted_json/tooltip_look.json`:

```json
{
  "frame_rate": 30.0,
  "gloss_stops": [{"ratio": 0, "color": [255, 255, 255, 255]}, ...],
  "body_fill": [0, 0, 0, 230],
  "subheader_add": {"GO2": [-31, -6, 0], "GO3": [5, -41, 96], "GO4": [0, 0, 0], "GO7": [-31, -6, 0]},
  "next_rank": {"multiply": [0, 0, 0, 256], "add": [50, 40, 53, 0]},
  "rarity_add": {"Common": [0, 0, 0], "Uncommon": [-62, -51, 0], "Rare": [86, 0, -164], "Orange": [126, 15, -200], "Unique": [-67, 0, -159]},
  "layouts": {"GO": {"field_width": 170, "mouse_x_limit": 570, "near_x": 13, "far_x": -183, "mouse_y_limit": 500, "low_shift_y": -50}, ...},
  "detail_delay_frames": 5,
  "pass_button": {"title": "No ability selected!", "turn_based": "...", "real_time": "..."}
}
```

- The SWF gives the frame rate, the gradient's stops (shape 2714), the body fill (shape 68), and the color transforms of `fontBacker3` and `fontBacker4` on sprite 2717's timeline, keyed by label.
- The AS gives the rarity add terms (`krinChangeColor`), each layout's `createTextField` width and `scaffold` and `scaffold2` lines, the `hitter == 5` threshold, and the `thinger` texts.
- The parsers raise on a line they cannot read. A second run writes the same bytes.
- The JSON shape above is the proposal. The build can rename keys, and the spec's tests follow.

## The port

### TooltipTheme

`scripts/ui/tooltip_theme.gd` reads `tooltip_look.json` once.

- `BG_HEADER`, `BG_COST`, `BG_BODY` and `BG_NEXT_RANK` keep their names and stay Colors, so no caller changes. They come from the JSON: the gradient's middle stop, that stop with the `GO2` add terms, the body fill, and the body fill through the next-rank transform.
- A section whose `bg_color` is `BG_HEADER` or `BG_COST` draws the 2715 gradient, with no add terms or the `GO2` ones. Every other section draws its flat color.
- A function returns the gradient's stops with a set of add terms applied and clamped to 0..255. The alpha add term is 0 in every transform.
- The text colors and widths stay as they are.

### GameTooltip

- **Gradient.** A gradient section draws a TextureRect behind its lines, with a vertical `GradientTexture2D` from those stops.
- **Rarity.** `show_sections` gains an optional `rarity: String` after `text_width`. A non-empty rarity tints the first section's gradient with `rarity_add[rarity]`. No rarity draws it untinted, which is the ADR 0005 fix.
- **Borders.** Every section draws a 1 px black border on top of its fill. The port's sections are the original's bordered fields, and the item body section stands for `my_txt4`. The border sits inside the 2 px text gutter, so no size changes.
- **Follow the mouse.** While it shows, the tooltip places itself on every frame from the mouse position. The sections' left edge is at mouse x + `near_x`, or + `far_x` when mouse x is not under `mouse_x_limit`. The title's top is at mouse y, moved by `low_shift_y` when the layout has one and mouse y is over `mouse_y_limit`. The layout comes from `text_width`: `TEXT_WIDTH_PLAIN` is `GO`, `TEXT_WIDTH_ITEM` is `GO4`, and `TEXT_WIDTH_ABILITY` is `GO7`.
- **Stay on the Stage.** After the offsets, the tooltip is clamped inside the 800x575 Stage (ADR 0012).
- **Anchor.** `anchor` stays in the signature. The tooltip no longer sits beside it. It hides when its anchor leaves the tree.
- **Delay.** `show_sections` gains an optional `detail_delay: bool`. When true, only the first section shows until `detail_delay_frames / frame_rate` seconds of the hover have passed. The tree nodes, the ring sockets and the pool rows of the Abilities window, and the battle's radial orbs, pass true.
- **Two-section helper.** `show_title_and_body(title, body, anchor)` builds the `GO` title and body sections. The world-map spec proposes the same function. The sell, delete, stance and pass tooltips use it.

### Callers

- `item_slot.gd` passes the item's rarity name. `GameItem.Rarity` maps to the AS name: COMMON "Common", UNCOMMON "Uncommon", RARE "Rare". The data holds only those three.
- `item_slot.gd` gains `shows_empty_item: bool`. `RightColumn` sets it on its 36 cells. An empty cell with it set shows item 0 through the same path as any item.
- `right_column.gd` drops `tooltip_text`. The sell slot shows `MENU[3]` over `MENU[4]` + " €" + the sale price of the dragged item, else of the selected item, else `MENU[5]`. The delete slot shows `MENU[1]` over `MENU[2]`. `GameData` gains one function for the sale price, and `sell_item` uses it.
- `stance_row.gd` shows the stance tooltip on each mode button. `stance_row.tscn` drops its five `tooltip_text` lines.
- `battle_scene.gd` shows the pass tooltip from `tooltip_look.json`. `battle_scene.tscn` drops both `tooltip_text` lines.

## Project structure

```
dev/urchin_dev/swf/extract/tooltip_look.py   the extractor
dev/converted_json/tooltip_look.json        its output
dev/tests/test_tooltip_look.py              its parser tests
scripts/ui/tooltip_theme.gd                 reads the JSON
scripts/ui/game_tooltip.gd                  gradient, border, follow, delay
docs/adr/0012-keep-the-tooltip-on-the-stage.md
```

## Code style

As in ui-foundation. A comment passes the three tests. A string index is a named constant with the AS line it comes from, as `game_over_screen.gd` does.

## Testing strategy

- **Extractor (pytest).** The AS parsers read small samples and raise on a broken line. They never read the SWF.
- **Rarity (GUT).** A Rare item's slot shows a title whose gradient colors are the 2715 stops plus `rarity_add["Rare"]`, read from the JSON by the test. A stance tooltip after it has the untinted stops.
- **Borders (GUT).** Each section of an item tooltip and an ability tooltip has a 1 px black border.
- **Follow (GUT).** The test sets the mouse position through a seam, steps the tooltip, and checks the sections' left edge and the title's top against the JSON offsets for a mouse left of the limit, right of it, and low on the Stage in `GO`. A second mouse position moves the tooltip.
- **Delay (GUT).** An ability tooltip with the delay shows one section, then all of them after the delay.
- **Strings (GUT).** The sell (with and without an item), delete, stance, empty cell and empty socket tooltips compare their title and body with `strings.json` and `items.json`, read by the test. The pass tooltip compares with `tooltip_look.json`.
- **No native tooltips.** A GUT test scans `scenes/` and `scripts/` for `tooltip_text` and finds none.
- **Whole suite.** `just gut` and `just pytest` pass before each commit.

## Boundaries

- Always: Read every number from the original out of `tooltip_look.json`, `strings.json` or `items.json`.
- Ask first: A change to any caller's tooltip text that this spec does not name.
- Never: Put a native `tooltip_text` back. Bake a tooltip into a PNG.

## Out of scope

- The zone tooltips on the World map, which the world-map spec owns.
- The pass tooltip's other texts. The original changes it to the queued ability's name and "You will use this ability on ..." while a pick waits, and to "Cannot skip during action." during a move (`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:393-399, 756-780`). The port shows the idle text only. A battle HUD issue can add the others.
- The first-line indent of each field (2 px, 3 px on the title), which `Label` cannot draw.
- The original's `data` frame: button 3121 shows the sell tooltip over a save slot. That is title-slots' piece.

## Success criteria

1. No `tooltip_text` is left in `scenes/` or `scripts/`, checked by a test.
2. A test compares the title and body of the sell, delete, stance, empty cell and empty socket tooltips with `strings.json`.
3. A Rare item's title bar carries the Rare add terms, checked by a test.
4. The tooltip moves with the mouse, checked by a test.
5. `extract_tooltip_look` writes the same JSON twice, and its pytest passes without the SWF.
6. `just gut` and `just pytest` pass.
