# Inventory

The inventory window shows the player's doll with seven equip slots, the
experience bar, the element bars (Piercing, Defense and the others), the
party faces, and a 6x6 item grid with the delete slot.

## Sub-features

- `inventory-open` opens the window from the hotbar and closes it with the x.
- `inventory-equip` moves an item between the grid and an equip slot by drag. Not yet driven.
- `inventory-party` shows a companion's gear from the party faces. Not yet driven.

## How to get to it (user POV)

- Click the first hotbar button (`InventoryButton`) in the hub.

## Driving it with urchin_verify

Preconditions:

- `$V launch v --preset rich:1`, then the `menu-load` steps in
  [main-menu.md](./main-menu.md).

- **Open.** Run `$V click v InventoryButton --label inventory-open --wait 1000`.
  `$V tree v InventoryWindow --depth 1` lists `LeftPanel`, `CenterPanel`,
  `PartyFaces` and `RightColumn`. `ExperienceLabel` reads `Experience:`.
- **Find the slots.** Run `$V tree v InventoryWindow --depth 6 --paths`.
  The equip slots are `Slot0` to `Slot6` under `EquipDollView`, and the
  grid slots are `Slot0` to `Slot5` in each of six rows under
  `RightColumn`.
- **Equip.** Not yet driven. Use one `send` with a `mouse_drag` from the
  grid slot's center to the equip slot's center, then read the slot and the
  stat labels with `$V node`.
- **Close.** Run `$V click v InventoryWindow/WindowShell/CloseButton`.
- **Proof.** The screenshot of the open window and of the hub after close.

## Gotchas

- A bare `CloseButton` used to hit the hidden Store window's button. The
  harness now takes the first visible match, but a full path is safer.
- The `rich` preset starts with an empty grid. Buy an item in the store
  first (see [store.md](./store.md)) to have one to equip.
