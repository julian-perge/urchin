# Store

The store window shows the shopkeeper and a line, the player's doll and
equip slots, up to 15 wares, and the player's inventory grid with the money
bar. A click on a ware buys it: the money goes down and the item goes into
the first free inventory slot.

## Sub-features

- `store-open` opens the store from the blue hub orb.
- `store-buy` buys a ware with one click.
- `store-sell` sells an item through the sell slot. Not yet driven.
- `store-close` closes the window with the x.

## How to get to it (user POV)

- Click the blue store orb in the hub (`ZoneHost/Zone1/ItemStore/Control`).

## Driving it with urchin_verify

Preconditions:

- `$V launch v --preset rich:1`, then the `menu-load` steps in
  [main-menu.md](./main-menu.md). `rich` has 999999 money and an empty
  inventory.

- **Open.** Run `$V click v ZoneHost/Zone1/ItemStore/Control --label store-open --wait 2000`.
  The window shows `Click on items to purchase:` and `Your Inventory`.
- **Read the money.** Run `$V node v StoreWindow/RightColumn/Amount`. The
  text is `999999`.
- **Buy.** Run `$V tree v StoreWindow/CentreBottomPanel/Content/Wares --depth 2 --paths`
  and pick a slot, such as `StoreWindow/CentreBottomPanel/Content/Wares/Row0/Slot2`.
  Run `$V click v <that path> --label store-buy --wait 1000`.
- **Side effect.** `$V node v StoreWindow/RightColumn/Amount` reads less
  than before by the ware's price. On 2026-11-21, Row0/Slot2 was Frosted
  Gloves at 16, and the money went from 999999 to 999983. The screenshot
  shows the item in the first inventory slot and its tooltip.
- **Close.** Run `$V click v StoreWindow/WindowShell/CloseButton`.
- **Proof.** The screenshots before and after the buy, and both money reads.

## Gotchas

- `tree --paths` lists each row before its slots. A click on a row clicks
  the row's center, which is its middle slot.
- The hover tooltip stays at the last injected pointer place in the
  screenshot. It is not part of the result.
- A purchase changes the save in memory only. Use the hotbar Save button
  before you look for it in `saves/`. Not yet driven.
