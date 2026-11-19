# Capability map: UI overhaul, menus and Windows

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). This map covers Title and slots, Hub, Inventory, Store, Abilities and Victory. The other Screens (Game Manual, Credits) get their own spec sessions and are not in this map. Game over, Ending, the World map and the tooltips got their own spec sessions and are in the map as `game-over`, `ending`, `world-map` and `tooltips`.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md). Terms are in [GLOSSARY.md](../GLOSSARY.md). The workflow is in `docs/agents/workflow.md`.

## Modules

| Module id | Responsibility | Spec | Depends on |
| --- | --- | --- | --- |
| ui-foundation | The 800x575 viewport, `FloatBox`, the Panel recipe (StyleBoxFlat and inner shadow shader), the rect test and its extractor, the ffdec compare tool, and the chrome extractor ([#161](https://github.com/julian-perge/urchin/issues/161)) | [107-ui-foundation.md](107-ui-foundation.md) | none |
| window-shell | The KRINMENU Window shell: backdrop, close X, the three Panels, the slot, delete, sell and money pieces, and the right column (item grid and money bar) that Inventory, Store and Victory share | [107-window-shell.md](107-window-shell.md) | ui-foundation |
| title-slots | `mainMenu` (46), `subMenu` (56), `dataMenu` (74), the menu background and caption style, the Back caption | [107-title-slots.md](107-title-slots.md) | ui-foundation |
| hub | The bottom bar, the hotbar, zone progress, the orbs, and the info spots with their card ([#16](https://github.com/julian-perge/urchin/issues/16)) | [107-hub.md](107-hub.md) | ui-foundation |
| inventory | KRINMENU labels `inventory` and `normal`: doll, equip slots, stats, element bars, party faces and the party bar ([#11](https://github.com/julian-perge/urchin/issues/11)) | [107-inventory.md](107-inventory.md) | window-shell |
| store | KRINMENU label `shop`: keeper scene, wares, equip slots, small doll | [107-store.md](107-store.md) | window-shell, inventory |
| abilities | KRINMENU label `skills`: talent tree, stats, action bar ring, ability pool ([#52](https://github.com/julian-perge/urchin/issues/52) opens it after a level-up) | [107-abilities.md](107-abilities.md) | window-shell |
| game-over | `gameOverMenu` (104): the Game over Screen on the rect record, `MenuCaption` and `menu_back.tscn`, with its texts from `strings.json` ([#362](https://github.com/julian-perge/urchin/issues/362)) | [107-game-over.md](107-game-over.md) | ui-foundation, title-slots |
| victory | KRINMENU label `win`, a Window on the Hub: XP rows, drops, Proceed ([#122](https://github.com/julian-perge/urchin/issues/122)) | [107-victory.md](107-victory.md) | window-shell, hub, inventory |
| ending | `endMenu` (116), the Ending Screen after CS_CUT5: the `ENDING` text and OK! ([#363](https://github.com/julian-perge/urchin/issues/363)) | [107-ending.md](107-ending.md) | ui-foundation, title-slots |
| tooltips | `KrinToolTipper` (2717): the shared tooltip's gradient title with the rarity tint, the field borders, following the mouse, the ability icon's delay, and the last native tooltips moved onto it ([#364](https://github.com/julian-perge/urchin/issues/364)) | [107-tooltips.md](107-tooltips.md) | ui-foundation, window-shell, inventory, abilities |
| world-map | Root frame `overMap`: the map art and frame, the zone buttons and their faces, the links and the zone tooltip ([#361](https://github.com/julian-perge/urchin/issues/361)) | [107-world-map.md](107-world-map.md) | ui-foundation, hub |

Build order: ui-foundation, then window-shell, title-slots and hub (independent of each other), then inventory, then store, abilities and victory. game-over and ending need only title-slots. world-map needs only ui-foundation and hub. tooltips comes after inventory and abilities.

Spec order: the same order. Each spec is approved before the next one is written.

## Changes since the first proposal

- ui-foundation is a new module. Its pieces are decided in closed tickets but have no spec and no issue, except #161.
- #161 moves from window-shell to ui-foundation. It also renders the hotbar squares and the zone progress track, which belong to hub, and its own text says it lands before any Screen is rebuilt. Keeping it in window-shell would make hub depend on window-shell.

- ui-foundation gained Part 7, the strings extractor `convert_strings`, and text size and color in the rect record.
- hub gained `set_inert`, which the Victory Window calls.

## Decisions the specs record as ADRs

- ADR 0002 widens to every publisher link, with the title-slots module.
- ADR 0006 (proposed) leaves out PvP Arena, with the title-slots module.
- ADR 0007 (proposed) keeps the Abilities window's named pool rows, rank text, code-drawn tree lines and native buttons, with the abilities module.

## Rules for the modules

- A piece belongs to one module. A piece two modules use belongs to the provider module, and the other spec names it and does not redefine it.
- Dependencies point one way, as the table shows.
- Module ids are fixed. Specs and plan issues name modules by these ids.
