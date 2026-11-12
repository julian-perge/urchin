# Spec: store

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `store` of [the capability map](107-capability-map.md). It depends on [window-shell](107-window-shell.md) (`WindowShell`, `ShellPanel`, the slots and `RightColumn`) and [inventory](107-inventory.md) (`EquipDollView` and its doll placement). Through them it uses `FloatBox`, the rect test, the compare tool and `strings.json` from ui-foundation.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the Store Window, the original's `KRINMENU` label `shop` (frame 16), on the window-shell parts and containers, at the SWF's rects. It has three columns: the shop keeper's scene and line, the player's small doll with the equip slots above the wares, and the shared right column with its sell slot.

Success is that every piece sits where the SWF places it, the keeper line comes from `strings.json`, the equip slots draw at their scaled size, and the wares behave as the original's do.

## Assumptions

- Behavior stays as it is: a click on a ware buys it, and the port's click-to-equip flow and `StatusLabel` stay. The original's pick-up flow is out of scope, as in window-shell and inventory.
- The inventory spec's note that the port's Store has no equip slots or doll is wrong. The port builds both in code, through `EquipDollView`, with typed centres. The real gap is scale: the SWF places the equip slots at scale 0.86 (26.66 px), and the port draws them at 31 px.
- The shop catalogs and the zone to shop map stay as they are (see Out of scope).
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. The rect extractor from ui-foundation is the source the test reads. The shell, the right column and the money bar are window-shell's and are placed, not redefined.

### Panels

| Panel | Placement | Box |
| --- | --- | --- |
| left, `tall` | 2990 scaled 0.894x1.225 | (36.12, 80.96) 222.70x327.24 |
| centre top, `centre` | 2988 scaled 1.164x0.418 | (274.90, 81.83) 213.15x136.42 |
| centre bottom, `centre` | 2988 scaled 1.164x0.538 | (274.90, 232.36) 213.15x175.50 |
| right column | window-shell | origin (503.50, 81.60), with the sell slot shown |

The border of each Panel is the recipe's rounded mean scale, from the record. The port's left panel is at (22.9, 81.6) 249x327.5 today, which is off from the SWF by 13 px at the left edge and 26 px in width.

### Left column: the keeper

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 3036 | the shop keeper scene, frame `shopId + 1`, at (148.25, 169.90) | mask 3021: (55.25, 99.90) 186.00x140.00 | bitmap fills | One TextureRect of `assets/ui/store/backdrops/shop<id>.png`, placed at its Stage rect |
| 3019 `vb2` | the keeper's line, `SHOP[shopId]` | (54.20, 257.15) 194.40x138.10 | `_sans` 12 #ffffff, multiline | Label in a fixed-height slot |

- `extract_store_art` writes the seven PNGs, cropped to the union of all seven frames, and prints their size only. It does not write the Stage rect, and the port places the art by hand at (34, 92) to (261, 242). The extractor gains a record of the union rect, from the same render, so the TextureRect and the rect test read it. A rect times 4 equals the PNG size.
- The keeper line reads `SHOP[n]` from `strings.json`. `StoreManager.SHOP_DIALOGUE` goes. Shops 5 and 6 have no line in the original, and the Label stays empty there. The port's "..." fallback goes, because the original shows nothing.

### Centre top panel: doll and equip slots

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2984 x7, scaled 0.86 | equip slots, indexes 0 to 6 | centres from (301.10, 117.55) to (456.75, 186.40) | `ItemSlot`, 26.66 px |
| the doll | the player's doll, small | placed from its part placements | doll art, mirrored to face left |

The seven centres, by equip index, are in the record. Today's typed values are 0 (301.1, 117.6), 2 (301.1, 152.0), 6 (301.1, 186.4), 5 (335.5, 186.4), 1 (456.7, 117.6), 3 (456.7, 152.0) and 4 (456.7, 186.4).

- The slots are `ItemSlot` scenes, placed by centre and scaled to 0.86. The slot's art, its baked shadow and its highlight scale together, as the SWF scales the clip. The window-shell slot scene needs a scale that its rect record can state. If its fixed 31x31 size gets in the way, the build issue adds a `scale` to the slot. It does not draw a second set of art.
- The doll stays `CharacterVisual` through `EquipDollView`, placed by the same method as the Inventory doll, from the part placements in this frame. It replaces `DOLL_POSITION` (396.5, 162.4) and `DOLL_SCALE` 0.85. The store doll faces left, which `EquipDollView.setup` already does by mirroring.
- This label places no party faces and no element bars. The frame script sets them up, and no piece draws them.

### Centre bottom panel: the wares

| cid | Piece | Box | Look | Built as |
| --- | --- | --- | --- | --- |
| 3018 `vb1` | `MENU[6]`, "Click on items to purchase:" | (288.20, 235.60) 187.30x55.00 | `_sans` 12 #666666 | Label in a fixed-height slot |
| 3013 `dropSlot0` to `dropSlot14` | wares | first centre (305.10, 291.85), 5 columns on a 38 px pitch | `ItemSlot` | `FloatBox` rows in a `FloatBox` column, separation 7 |

- The hint text reads `MENU[6]` from `strings.json`. The port's `PURCHASE_HINT` constant goes.
- An empty ware slot is hidden, as the original does (`frame_16/DoAction.as`, `_visible = false` when `dropArray[w] == 0`). The port shows 15 slots with empty ones. This is a change a player can see, and it follows the original, so it needs no ADR.
- A ware's tooltip title is "€" plus the price, " - " and the item name. The port already builds it. The look stays with the tooltip spec.

### The right column

`RightColumn` with `show_sell_button(true)`. The sell slot's centre is (685.10, 384.20), and the delete slot is as in window-shell. The Store keeps the port's signals: `item_selected`, `sell_pressed` and `delete_pressed`.

### Port-only pieces

- `StatusLabel`: the refusal messages ("You cannot afford that item.", "Your inventory is full." and the equip messages). The original has none. The label stays, inside the centre bottom panel, in the band under the three ware rows (y 385 to 405, 187.30 wide). It has no rect in the record, and the rect test skips it by name.

## Replacements

- `scenes/ui/store/store_window.tscn` is rebuilt from `WindowShell`, three `ShellPanel` scenes, `FloatBox` containers, the ware slots and `RightColumn`. `scripts/ui/store/store_window.gd` keeps `open_store`, `refresh_store`, `store_closed` and its handlers. It loses `INVENTORY_AT`, `EQUIP_SLOT_CENTERS`, `DOLL_POSITION`, `DOLL_SCALE`, `CATALOG_SLOTS` (the count comes from the scene) and `PURCHASE_HINT`.
- `StoreManager.get_current_shop_dialogue()` reads `strings.json`. `SHOP_DIALOGUE` goes.
- The right column in the Store is `RightColumn`, which window-shell's replacements already cover. This module deletes no hand art, because Achievements still uses it.

## Project structure

Follows `AGENTS.md`. New or changed locations:

```
scenes/ui/store/store_window.tscn         rebuilt
dev/urchin_dev/swf/extract/store_art.py   writes the Stage rect of the union crop
```

## Code style

As in ui-foundation. A scene types its Stage numbers once, and the rect test checks them. The ware grid hides empty slots:

```gdscript
func _load_store_items() -> void:
	var catalog: Array[GameItem] = GameData.get_store_inventory()
	var slots: Array[Node] = %Wares.get_children()
	for i in slots.size():
		var slot := slots[i] as ItemSlot
		slot.set_item(catalog[i] if i < catalog.size() else null)
		slot.modulate.a = 1.0 if i < catalog.size() else 0.0
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if i < catalog.size() else Control.MOUSE_FILTER_IGNORE
```

The snippet shows style only. A hidden ware slot keeps its place and size and draws nothing, because the original's `_visible = false` does not move the other slots. Setting `visible` to false would make `FloatBox` skip the slot and pull the slots after it forward, so the build does not use it.

## Testing strategy

- **Rect test.** Add `store_window.tscn` to the record. Every piece in the tables passes under 0.5 px, the equip slots included at their 0.86 scale, and the Labels' sizes and colors match.
- **Behavior (GUT).**
  - Opening the Store shows the keeper art and line of the current zone's shop.
  - Shops 5 and 6 show an empty keeper line.
  - A catalog of 8 items shows 8 ware slots and hides 7.
  - Buying, selling, equipping and unequipping work as before. The existing store window tests keep passing after the nodes move.
- **Strings.** A test compares the keeper line and the hint with `strings.json`, so a typed string fails.
- **Extractor.** A second `uv run extract_store_art` leaves the PNGs and the rect record byte-identical, and the rect times 4 equals the PNG size.
- **Must-fail controls.** Move one ware slot 20 px in a copy of the scene and expect the rect test to fail. Type a different keeper line and expect the strings test to fail.
- **Compare tool.** A `store` entry in `chrome` mode, scoring the panels, the slots and the keeper art inside their masks. The doll and faces are masked out. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number, color or string from the rect record or `strings.json`. Keep `open_store`, `refresh_store` and the right column's API working. Commit `.png.import` sidecars.
- Ask first: A change to a shop's catalog or to the zone to shop map. A change to the click-to-buy flow. A change to `EquipDollView`'s interface.
- Never: Type a keeper line or a hint. Hand-place a coordinate the rect record can supply. Draw an equip slot at 31 px where the SWF scales it. Delete a hand export that Achievements still loads.

## Out of scope

- The shop catalogs (`StoreManager.KRIN_SHOP_ITEMS`) and the zone to shop map. They are data, they have a test, and the Store's layout does not depend on them.
- The pick-up and put-down item flow.
- The tooltip's look and the slot tooltips named in window-shell.
- The doll rig and its art.
- Shop 7, which no store orb selects.

## Success criteria

1. `store_window.tscn` places every piece within 0.5 px of the SWF, with the equip slots at 0.86 scale and the keeper art at the extractor's rect.
2. The keeper line and the hint come from `strings.json`, and shops 5 and 6 show no line.
3. Empty ware slots are hidden, and the visible ones sit in their grid cells.
4. Buy, sell, equip, unequip and delete work as before.
5. The compare tool scores the `store` entry under its bar, with the 20 px control over it.
6. `uv run gut` passes.

## Open questions

1. **Hidden empty wares.** This spec hides empty ware slots as the original does, which changes what a player sees in shops with fewer than 15 items. Confirm.
2. **The scaled slot.** The equip slot at 0.86 may need a `scale` on the window-shell slot. If it does, the build issue adds it there and tells you, because window-shell's spec drew the slot at 31 px only.
3. **The status band.** The port-only `StatusLabel` sits in the free band under the wares. Confirm the place, or name another.
4. **Catalog source.** The catalogs are typed from `krinSetShop` and not read from an extractor. This spec leaves them, and asks whether a later issue should extract them.
