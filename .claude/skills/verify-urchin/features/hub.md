# Zone hub

The hub is the zone's art with orbs on it: the story fight (red), the store
(blue) and the training fight (yellow), plus info spots. The hotbar at the
bottom opens the Inventory, Abilities, Save, Options, Respec, Achievements
and Zone Map windows, and shows the zone title, subtitle and stage.

## Sub-features

- `hub-orbs` shows the story, store and training orbs of the zone.
- `hub-hotbar` opens each window from its hotbar button.
- `hub-zone-label` shows the zone title, subtitle and stage.

## How to get to it (user POV)

- Load a saved game from the main menu.
- Win or leave a battle. Not yet driven.

## Driving it with urchin_verify

Preconditions:

- `$V launch v --preset rich:1`, then the `menu-load` steps in
  [main-menu.md](./main-menu.md). The `rich` preset is in Zone 1, Stage 11.

- **Zone label.** Run `$V node v Hotbar/ZoneTitleSlot/ZoneTitle Hotbar/ZoneSubtitleSlot/ZoneSubtitle Hotbar/StageSlot/StageLabel`.
  The texts are `Zone 1`, `New Alcatraz: The Iron Prison` and `Stage 11`.
- **Orbs.** Run `$V tree v ZoneHost --depth 3`. `Zone1` holds
  `StoryFight`, `ItemStore` and `TrainingFight`. Each orb is an Area2D,
  and its `Control` child gives the rect to click, such as
  `ZoneHost/Zone1/StoryFight/Control`.
- **Hotbar window.** Run `$V click v InventoryButton --label hub-inventory --wait 1000`.
  `$V tree v --depth 1` lists `InventoryWindow`. Close it with
  `$V click v InventoryWindow/WindowShell/CloseButton`.
- **Proof.** The hub screenshot after load, the label texts, and a
  screenshot of an open window.

## Gotchas

- While a window is open, the hub art (`ZoneHost`) is hidden, so `click`
  refuses an orb. Close the window first.
- Each window has its own `WindowShell/CloseButton`, and hidden windows
  stay in the tree. Use the full path.
- Other zones use `Zone2` to `Zone7` under `ZoneHost`. Use a zone preset
  such as `zone3_boss` to reach one.
- The Abilities, Save, Options, Respec, Achievements and Zone Map buttons
  are not yet driven.
