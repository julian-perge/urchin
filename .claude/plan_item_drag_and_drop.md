# Implementation Plan — Item Click-n-Drag

## Problem Statement
Items currently equip and unequip via click only. The goal is to add drag-and-drop so inventory slots, equip slots, and the sell button all participate in a drag surface — inventory↔equip (equip/unequip), inventory↔inventory (swap), and inventory/equip→sell button (sell on drop with hover price preview). Click-to-equip/click-to-keep stays as a parallel path; nothing breaks for players who don't drag.

## Requirements
- Drag from any inventory slot: begins a drag with the slot's `GameItem` as the payload
- Drag from any equip slot: begins a drag with the equipped `GameItem` as the payload
- Drop inventory → equip slot: calls `GameData.equip_from_inventory(src_index, equip_slot)` — existing path, now reachable by drag
- Drop equip slot → inventory slot: calls `GameData.unequip_to_slot(equip_slot, inventory_index)` — places item in the specific destination cell, swapping with whatever is there
- Drop inventory → inventory: swaps `save.item_array[src]` and `save.item_array[dst]`, emits `inventory_changed`
- Drop inventory/equip → sell button: sells the item at `ceil(item.price * 0.15)`, updates sell button `tooltip_text` to `"Sell for €N"` on drag-enter, restores original text on drag-exit/cancel
- Drop anything → anywhere else: no-op, item snaps back (Godot's default)
- A drag preview (31×31 icon matching the slot's `ItemIcon` texture, semi-transparent at 0.75 alpha) follows the cursor during drag
- Click-to-equip/click-to-keep untouched — both interaction modes work simultaneously
- Store catalog stays click-to-buy (original behavior, no drag from catalog)
- GUT tests cover: inventory↔inventory swap, unequip-to-specific-cell, and sell-button tooltip text update logic

## Background
Godot 4's built-in Control drag API (`_get_drag_data`, `_can_drop_data`, `_drop_data`) is the right tool. `_get_drag_data` returns a Dictionary payload and a drag preview Control; `_can_drop_data` gates acceptance; `_drop_data` commits the action. No custom drag manager node is needed — Godot manages the preview lifetime and cursor positioning automatically.

`ItemSlot` is both drag source and drop target. The sell button drop target is handled at the `InventoryPanel` Control level (checking drop position against `sell_button.get_rect()`) rather than subclassing `Button`, since `SellItemButton` has no existing script.

`GameData.unequip_to_inventory` always places into the first free cell — a new `GameData.unequip_to_slot(equip_slot, inventory_index)` variant places into a specific cell, swapping with whatever is there. `GameData.swap_inventory_slots(a, b)` is a two-line item_array swap + `inventory_changed` emit.

Drag payload shape:
```gdscript
{
    "item": GameItem,       # the item being dragged
    "source": String,       # "inventory" or "equip"
    "index": int,           # save_index (inventory) or equip_index (equip)
}
```

Sell tooltip: `_can_drop_data` on `InventoryPanel` sets `sell_button.tooltip_text` to the sell price when the cursor is over the button. `NOTIFICATION_DRAG_END` resets it on cancel; `_drop_data` resets it after a completed sell.

```
Drag surfaces:
  ItemSlot (inventory)  ──► _get_drag_data  → payload {item, "inventory", save_index}
                         ◄── _can_drop_data ← payload from inventory or equip slot
                         ◄── _drop_data     ← swap (inv→inv) or unequip-to-slot (equip→inv)

  ItemSlot (equip)      ──► _get_drag_data  → payload {item, "equip", equip_index}
                         ◄── _can_drop_data ← payload from inventory slot only
                         ◄── _drop_data     ← equip_from_inventory at this equip_slot

  InventoryPanel root   ◄── _can_drop_data  ← any payload with item != null, position
                            over sell_button.get_rect() → updates tooltip_text to sell price
                         ◄── _drop_data     ← GameData.sell_item(payload.item)
```

## Task Breakdown

### Task 1: Add `GameData.swap_inventory_slots` and `GameData.unequip_to_slot`
- Objective: the two new data-layer operations that drag needs but click never required — inventory↔inventory swap and unequip-into-a-specific-cell. Pure logic, no UI changes.
- Add to `game_data.gd`:
  ```gdscript
  # Swaps item_array[slot_a] and item_array[slot_b] in place.
  func swap_inventory_slots(slot_a: int, slot_b: int) -> bool:
      if current_save == null:
          return false
      if slot_a < 0 or slot_a >= current_save.item_array.size():
          return false
      if slot_b < 0 or slot_b >= current_save.item_array.size():
          return false
      var tmp: int = int(current_save.item_array[slot_a])
      current_save.item_array[slot_a] = current_save.item_array[slot_b]
      current_save.item_array[slot_b] = tmp
      inventory_changed.emit()
      return true

  # Unequips equip_slot and places the item into inventory_index specifically,
  # displacing whatever was there into the first free cell (or keeping it if
  # inventory_index was already empty). Returns false only if equip_slot is
  # empty or save is null.
  func unequip_to_slot(equip_slot: int, inventory_index: int) -> bool:
      if current_save == null:
          return false
      if inventory_index < 0 or inventory_index >= current_save.item_array.size():
          return false
      var item_id: int = Equipment.unequip(current_save, equip_slot, ItemManagerAuto.items_by_id)
      if item_id == 0:
          return false
      var displaced_id: int = int(current_save.item_array[inventory_index])
      current_save.item_array[inventory_index] = item_id
      if displaced_id != 0:
          var free_cell: int = current_save.item_array.find(0)
          if free_cell != -1:
              current_save.item_array[free_cell] = displaced_id
          else:
              push_warning("unequip_to_slot: inventory full, displaced item %d lost" % displaced_id)
      inventory_changed.emit()
      return true
  ```
- GUT tests (alongside existing save/equip tests):
  - `swap_inventory_slots`: place items A and B at indices 2 and 5, swap, assert positions reversed.
  - `swap_inventory_slots` with one empty cell: assert item and empty (id 0) exchange correctly.
  - `unequip_to_slot` into an empty cell: item lands exactly at `inventory_index`.
  - `unequip_to_slot` into an occupied cell: unequipped item lands at `inventory_index`, displaced item moves to first free cell.
- No UI changes in this task.
- Demo: GUT headless passes with new tests. `GameData.swap_inventory_slots(2, 5)` and `GameData.unequip_to_slot(equip_slot, 3)` work correctly on a fresh save.

### Task 2: Drag source on `ItemSlot` — `_get_drag_data` + drag preview
- Objective: any occupied `ItemSlot` (inventory or equip) becomes a drag source. A semi-transparent 31×31 icon follows the cursor during drag.
- Add to `item_slot.gd`:
  ```gdscript
  func _get_drag_data(at_position: Vector2) -> Variant:
      if item == null:
          return null
      var preview := Control.new()
      preview.custom_minimum_size = MenuTheme.SLOT_SIZE
      var icon := TextureRect.new()
      icon.texture = item_icon.texture
      icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
      icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
      icon.set_anchors_preset(Control.PRESET_FULL_RECT)
      icon.modulate = Color(1, 1, 1, 0.75)
      icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
      preview.add_child(icon)
      set_drag_preview(preview)
      var source: String = str(get_meta("drag_source", "inventory"))
      var index: int = int(get_meta("drag_index", get_meta("save_index", -1)))
      return {"item": item, "source": source, "index": index}
  ```
- In `inventory_panel.gd`'s `_ready` loop, set `slot.set_meta("drag_source", "inventory")` on each instantiated slot. (`save_index` is already set in `populate_from_save`; `drag_index` defaults to it.)
- In `equip_doll_view.gd`'s `setup` loop, set `slot.set_meta("drag_source", "equip")` and `slot.set_meta("drag_index", equip_index)` on each equip slot.
- Click behavior (`_on_gui_input`, `slot_clicked` signal) is completely unchanged.
- Demo: dragging an item from any inventory or equip slot shows a semi-transparent icon following the cursor. Releasing over a non-target area snaps the item back with no state change.

### Task 3: Drop target on `ItemSlot` — inventory↔inventory swap and equip↔inventory
- Objective: dropping a dragged item onto an inventory or equip slot commits the correct `GameData` operation.
- Add to `item_slot.gd`:
  ```gdscript
  func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
      if not data is Dictionary or not data.has("item"):
          return false
      var source: String = str(data.get("source", ""))
      var my_source: String = str(get_meta("drag_source", "inventory"))
      if my_source == "inventory":
          return source in ["inventory", "equip"]
      if my_source == "equip":
          return source == "inventory"
      return false

  func _drop_data(at_position: Vector2, data: Variant) -> void:
      var source: String = str(data.get("source", ""))
      var src_index: int = int(data.get("index", -1))
      var my_source: String = str(get_meta("drag_source", "inventory"))
      var my_index: int = int(get_meta("drag_index", get_meta("save_index", -1)))
      if my_source == "inventory" and source == "inventory":
          GameData.swap_inventory_slots(src_index, my_index)
      elif my_source == "inventory" and source == "equip":
          GameData.unequip_to_slot(src_index, my_index)
      elif my_source == "equip" and source == "inventory":
          GameData.equip_from_inventory(src_index, my_index)
  ```
- Both `inventory_changed` and the existing signal connections in `inventory_panel.gd` / `store_window.gd` / `equip_doll_view.gd` handle the refresh automatically — no extra refresh calls needed.
- GUT integration test (add to `test_ui_scenes.gd`):
  - Inventory↔inventory swap: place items A and B at indices 0 and 1, call `_drop_data` on slot 0 with a payload sourced from index 1, assert `item_array[0] == item_b.id` and `item_array[1] == item_a.id`.
  - Equip→inventory drop: equip item A in its natural slot, call `_drop_data` on inventory slot 2 with a payload sourced from the equip slot, assert item lands at index 2 and equip slot is 0.
- Demo: dragging inventory→inventory swaps cells. Dragging equip→inventory unequips into that specific cell. Dragging inventory→equip slot equips. All click paths still work.

### Task 4: Sell button as drop target with hover price tooltip
- Objective: dropping any item onto the sell button sells it. Hovering over the sell button during a drag shows the sell price in the button's tooltip.
- The drop logic lives on `InventoryPanel` (its root `Control`) rather than the `Button` node itself. Change `InventoryPanel` root `mouse_filter` from `MOUSE_FILTER_IGNORE` (2) to `MOUSE_FILTER_PASS` (1) in `inventory.tscn` so drag events reach it while still passing through to child slots.
- Add to `inventory_panel.gd`:
  ```gdscript
  const _DEFAULT_SELL_TOOLTIP: String = \
      "Sell Item\nSelect an item, then click here to sell it for 15% of its price."

  func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
      if not data is Dictionary or not "item" in data:
          return false
      var item: GameItem = data["item"]
      if item == null:
          return false
      if not sell_button.get_rect().has_point(at_position):
          return false
      sell_button.tooltip_text = "Sell for \u20ac%d" % int(ceil(item.price * 0.15))
      return true

  func _drop_data(at_position: Vector2, data: Variant) -> void:
      if not sell_button.get_rect().has_point(at_position):
          return
      var item: GameItem = data.get("item")
      if item == null:
          return
      GameData.sell_item(item)
      sell_button.tooltip_text = _DEFAULT_SELL_TOOLTIP

  func _notification(what: int) -> void:
      if what == NOTIFICATION_DRAG_END:
          sell_button.tooltip_text = _DEFAULT_SELL_TOOLTIP
  ```
- GUT test: instantiate `InventoryPanel` with a save that has item A in `item_array[0]`. Call `_can_drop_data` with a position inside `sell_button.get_rect()` and payload `{item: item_a, source: "inventory", index: 0}`. Assert `sell_button.tooltip_text` contains the correct sell price string. Then call `_drop_data` at the same position and assert `save.euro` increased by `ceil(item_a.price * 0.15)` and `item_array[0] == 0`.
- Demo: hovering an item over the sell button during a drag shows `"Sell for €N"`. Dropping sells the item and gold updates. Cancelling the drag restores the original tooltip text.

### Task 5: Verify store window and run full suite
- Objective: confirm `InventoryPanel`'s drag changes work identically in the store window (which hosts its own `InventoryPanel` instance), and that no existing click interactions regressed.
- Because all drag logic lives in `InventoryPanel` and `ItemSlot` (shared scenes), the store window inherits sell-by-drag automatically. No store-specific code changes are needed.
- Verify the `mouse_filter = PASS` change on `InventoryPanel` root does not interfere with the store's own backdrop click handling. The store's `Backdrop` node has `mouse_filter = STOP` (it handles its own clicks) and sits at a different position — no overlap issue.
- Run the full GUT headless suite. The existing `test_inventory_window_equips_from_grid_click` test must still pass (click path unaffected). The new drag tests from Tasks 1, 3, and 4 must all pass.
- Demo: in the store screen, dragging an inventory item over the sell button shows the sell price, dropping sells it, and gold updates. All previous click interactions in both inventory and store screens work unchanged. GUT suite passes with all new and existing tests green.
