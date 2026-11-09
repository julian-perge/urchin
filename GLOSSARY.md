# Urchin

urchin is a Godot port of the Flash game Sonny 2. These are the terms its code, docs and issues use.

## Language

### UI

**Screen**:
A full-window state the player navigates to, such as Title, Hub, Battle, Victory, Game over or Ending.
_Avoid_: Scene, page, menu

**Window**:
A panel opened over the Hub, such as Inventory, Store or Abilities.
_Avoid_: Screen, popup, dialog

**HUD**:
The Battle screen's status elements drawn over the hall: unit overlays, member bars, the top status bar and the speech box.
_Avoid_: Overlay, battle UI

**Quest progress**:
How far the player has got through a zone's story battles, which the Hub labels "Stage 11".
_Avoid_: Stage
