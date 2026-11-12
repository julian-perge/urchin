# Spec: window-shell

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `window-shell` of [the capability map](107-capability-map.md). It depends on [ui-foundation](107-ui-foundation.md): the viewport, `FloatBox`, the Panel recipe, the rect test, the compare tool and the chrome art from `extract_window_chrome` (#161).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the parts every KRINMENU Window shares, as Godot scenes on containers, so Inventory, Store, Abilities and Victory instance them and do not draw their own chrome.

In the original, Windows are labels of one sprite, KRINMENU (3142), placed at (400.50, 222.40). Every label draws the same backdrop and close X, and most draw the same right column of 36 item slots and a money bar. The port rebuilds each of these per Window today, from hand-made PNGs and fixed offsets.

The module delivers four scenes:

| Scene (proposed path) | Holds |
| --- | --- |
| `scenes/ui/window/window_shell.tscn` | The backdrop, the close X, and the KRINMENU origin |
| `scenes/ui/window/shell_panel.tscn` | One Panel built to the ui-foundation recipe, with a fill variant |
| `scenes/ui/item_slot.tscn` (existing, art swapped) | The slot art and the highlight |
| `scenes/ui/window/right_column.tscn` | The "Your Inventory" Panel, the 36-slot grid and the money bar with its sell and delete slots |

Success is that the three Windows that show the right column place one `RightColumn` and no longer carry their own copy, and that the shell's pieces match the SWF under the rect test and the compare tool.

## Assumptions

- Decided with you in this session: the shell is one scene plus shared parts; tooltips go to the tooltip spec; Achievements is not rebuilt here; slot work is look only.
- The three Windows that show the right column are Inventory, Store and Victory. Abilities has no right column.
- The Window's own Panels (their rects, and how many each label places) belong to each Window's spec. This module gives them the `ShellPanel` scene and its three fills, and nothing more.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

Every number comes from the SWF through `timeline.frames()` and is in Stage px. A number below is a reference for this spec. The rect extractor from ui-foundation is the source the test reads.

### The shell

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 2994, shape 2993 | backdrop | (14.15, 15.00) 768.55x425.10 | radial #b03e3e to #211212, black line, with KRINMENU's Bevel (#ca6e6e, #100a0a), 2 px black Glow and DropShadow (blur 5, distance 5) | One TextureRect of the zoom 4 backdrop from #161. Its rect comes from the same render. |
| 2855, shape 2854 | close X | (734.55, 29.75) 36.70x36.40 | #000000, DropShadow (blur 7, distance 3) | Art from #161, drawn by a TextureRect |
| 2853 | close hit button | (738.60, 32.70) 30.00x30.00 | none | A Control sized to this box. It is separate from the art. |

- The shell exposes a `close_pressed` signal and a `close_visible` property. The `win` label (Victory) drops the close X, so the Victory spec sets `close_visible` to false.
- The 1 px vertical line 2995 at depth 1 is not drawn. #161 hides it, and its backdrop scores p90 3 against a real capture without it.
- The shell does not hide the Hub art. The original hides `KrinScreen` when a Window opens and leaves the bottom bar showing. That belongs to the hub spec.

### ShellPanel

A PanelContainer built to the ui-foundation Panel recipe: a StyleBoxFlat of fill and border, content margins, and the one shared inner shadow material.

| Variant | Source | Fill |
| --- | --- | --- |
| `tall` | sprite 2990, shape 2989 | #373737 |
| `bar` | sprite 2992, shape 2991 | #404040 |
| `centre` | sprite 2988, shape 2987 | #1a1a1a |

- The border is black. Its width is the recipe's mean scale stroke for the placement, so the scene that places a Panel sets it. The default is 1 px.
- The host sets the Panel's rect. The rects differ by label and are in each Window's spec.
- Each Panel's fill, border and shadow material are in the rect record, so the rect test fails a Panel with a wrong color or stroke.

### Item slots

| cid | Slot | Used by | Look |
| --- | --- | --- | --- |
| 2986 | inventory slot | the 36-slot grid | linear #090909 to #262626, black line, inner DropShadow (blur 5, distance 5, angle 52) |
| 2984 | equip slot | Inventory and Store equip slots | the same, with angle 45 |
| 3013 | drop slot | Victory drops and Store wares | the same, with angle 52 |
| 2857 | highlight | the hover and down state of all three | no fill, 2 px line #ffffff, 32x32 around the slot centre |

- Each slot is 31x31 and is placed by its centre, so a slot's top left is a fractional number. `FloatBox` places it.
- Every slot uses the art of 2986 from #161 at zoom 4. The equip and drop slots differ from it only in the shadow angle, which is too small to see, so they have no art of their own (#211).
- The highlight is a StyleBoxFlat with `draw_center` off and a 2 px white border. #161 does not render it, and the Panel recipe already draws a plain stroke.
- Look only. `ItemSlot`'s script, signals, drag and drop and meta keys do not change.

### RightColumn

Its origin is the Panel's top left, (503.50, 81.60), as Inventory, Store and Victory all place it.

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 2990 | right Panel | (503.50, 81.60) 249.05x267.15 | `tall` | ShellPanel |
| 2856 | `vbbc0`, "Your Inventory" (`MENU[14]`) | (512.30, 87.10) 233.75x21.90 | `_sans` bold 13 #5e5e5e center | Label in a fixed-height slot |
| 2986 x36 | `itemSlot0` to `itemSlot35` | first centre (533.10, 128.15) | `inventory` slot, 6 columns on a 38 px pitch | `FloatBox` rows in a `FloatBox` column, separation 7 |
| 2992 | money Panel | (503.50, 358.20) 249.05x50.85 | `bar` | ShellPanel |
| 2861 | the euro sign | (505.25, 364.90) 30.40x43.40 | `_sans` bold 31 #fad95a right | Label in a fixed-height slot |
| 2862 | `dumbEuro`, the amount | (537.10, 371.55) 116.40x28.55 | `_sans` bold 22 #fad95a left | Label in a fixed-height slot |
| 3017 | sell slot | centre (685.10, 384.20) | linear #ffcc00 to #a33507, black line, baked shadow | Art from #161 in a hit Control. Store only. Hidden in the scene, and the Store shows it through `show_sell_button`. |
| 2860 | delete slot | centre not in the inventory note | linear #aa1111 to #350606, black line, baked shadow | Art from #161 in a hit Control |

- The euro sign and the amount are two Labels, as in the SWF. The port has one "€ 7" Label today, which cannot match the capture, as the #107 comment from #139 records.
- The right column keeps the `InventoryPanel` script API: the signals `item_selected`, `sell_pressed` and `delete_pressed`, and the methods `populate`, `populate_from_save`, `set_gold` and `show_sell_button`. Hosts keep working. Its integration test is `test_right_column.gd`, renamed from `test_inventory_panel.gd`. Its internals move to the new nodes.
- The sell slot is a drop target. The existing drag-to-sell code moves with it unchanged.

## Replacements

- `scenes/ui/inventory.tscn` and `scripts/ui/inventory_panel.gd` become `right_column.tscn` and its script, and the three hosts instance that.
- `scripts/ui/menu/menu_theme.gd` loses its backdrop, close, slot size and slot pitch constants, which the scenes and the rect record replace. It also loses `format_money`, because the amount is a plain integer (see Decisions). Its element colors, heal color and the bar math stay, because the battle code uses them.
- These hand exports stay until their last user is rebuilt: `menu_backdrop.png`, `close_x.png`, `panel_large.png`, `panel_bar.png`, `panel_center.png`, `slot.png`, `slot_highlight.png`, `button_delete.png`, `button_sell.png`. The Achievements window still uses them, and a later spec rebuilds Achievements. The same holds for `assets/ui/store/sell.png`, which nothing loads.
- The deletions are a task for the spec that rebuilds Achievements, and not for this module.

## Project structure

Follows `AGENTS.md`. New locations:

```
scenes/ui/window/window_shell.tscn      backdrop, close X, KRINMENU origin
scenes/ui/window/shell_panel.tscn       Panel recipe with three fills
scenes/ui/window/right_column.tscn      grid, money bar, sell and delete
scripts/ui/window/window_shell.gd       close_pressed, close_visible
scripts/ui/window/right_column.gd       the InventoryPanel API, moved
assets/ui/window/                       art from extract_window_chrome (ui-foundation)
```

## Code style

As in ui-foundation. A scene types its Stage numbers once, and the rect test checks them. This is the shape of a shell node:

```gdscript
class_name WindowShell
extends Control

signal close_pressed

@export var close_visible := true:
	set(value):
		close_visible = value
		if is_node_ready():
			$CloseButton.visible = value
			$CloseArt.visible = value

func _on_close_button_pressed() -> void:
	close_pressed.emit()
```

The snippet shows style only.

## Testing strategy

- **Rect test.** Add `window_shell.tscn` and `right_column.tscn` to the rect record, with every piece in the tables above. All pass under 0.5 px. The control moves one piece 20 px and fails.
- **Panel recipe.** The rect test already fails a `ShellPanel` with a wrong fill, stroke or shadow material.
- **RightColumn.** The existing `test/integration/test_right_column.gd` (renamed from `test_inventory_panel.gd`) and `test_item_slot.gd` keep passing after the nodes move. New cases cover the two Labels (sign and amount) and the sell slot's visibility.
- **Slots.** A GUT test checks that the slot loads the inventory art and that the highlight is a 2 px white border.
- **Compare tool.** Add a `window-shell` entry in `chrome` mode. It scores the backdrop, the close X and the right column inside their masks on a labelled capture of the Inventory Window. The build issue sets the bar from the first passing run and shows the 20 px shift scoring over it.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number from the rect record or an extractor. Keep `ItemSlot`'s public signals and methods, and the `InventoryPanel` ones that `RightColumn` took over. Commit `.png.import` sidecars.
- Ask first: A change to a hand export that Achievements still uses. A change to a slot's drag and drop behavior. A new dependency.
- Never: Draw a flat Panel from a PNG. Hand-place a coordinate the rect record can supply. Delete a hand export before every Window that loads it is rebuilt. Change tooltip text here.

## Out of scope

- Tooltip text and look for the sell slot, delete slot, empty cell and the rarity-tinted title bars. The tooltip spec owns them. The shell scenes expose each slot as a node it can drive.
- The original's pick-up and put-down handling, where a press moves an item onto the cursor. The port selects a slot and drags. That is behavior, and no spec in this map covers it.
- Hiding the Hub art when a Window opens. That is the hub spec.
- Achievements and Options Windows.
- Each Window's own Panel rects.

## Success criteria

1. `window_shell.tscn` draws the backdrop and close X from the zoom 4 art, with every rect under 0.5 px from the SWF.
2. `ShellPanel` has the three fills. A test fails on a wrong fill, border or missing shadow material.
3. The slot and the highlight pass the rect test. The slot script is unchanged.
4. `right_column.tscn` places 36 slots at a 38 px pitch, the title, the money bar with a separate euro sign and amount, and the sell and delete slots. Every rect is under 0.5 px from the SWF.
5. Inventory, Store and Victory each instance `RightColumn`. No scene keeps its own copy of the grid, money bar or sell and delete buttons.
6. The compare tool scores the `window-shell` entry under its bar, and the 20 px shift scores over it.
7. `uv run gut` passes, and no test names a removed constant.

## Decisions

1. **The amount's format.** The original sets `dumbEuro = _root.Krin.Euro`, a plain number with no thousands separators (`DefineSprite_3142/frame_1/DoAction.as:267`). The port shows `12,345`. The amount Label shows a plain integer, with no commas, and `MenuTheme.format_money` goes. A test checks the plain format. No ADR, because this follows the original.
2. **Text in the rect record.** ui-foundation Part 4 records each text field's font height and color, so the rect test checks the size and color of the right column's three Labels (13, 31 and 22 px).
3. **The highlight** is a StyleBoxFlat in this module, and #161 stays as written.

## Open questions

1. **The delete slot's centre.** The inventory note gives the sell centre but not the delete centre. The rect extractor supplies it. By my arithmetic the port's sell button sits about 15 px left of the SWF centre (a guess, the rect test will confirm it).
