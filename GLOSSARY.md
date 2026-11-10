# Urchin

urchin is a Godot port of the Flash game Sonny 2. These are the terms its code, docs and issues use.

## Language

### UI

**Screen**:
A full-window state the player navigates to, such as Title, Hub, Battle, Victory, Game over or Ending.
_Avoid_: Scene, page, menu

**Window**:
A set of Panels opened over the Hub, such as Inventory, Store or Abilities.
_Avoid_: Screen, popup, dialog

**Panel**:
A flat rectangle a Screen or Window is built on: one solid fill and at most one stroke.
_Avoid_: Box, column

**Backdrop**:
The art behind a Window's Panels.
_Avoid_: Background

**HUD**:
The Battle screen's status elements drawn over the hall: unit overlays, member bars, the top status bar and the speech box.
_Avoid_: Overlay, battle UI

**Decision**:
The part of the player's half-turn when the turn loop waits for a pick or a pass.
_Avoid_: Window, decision window

**Radial menu**:
The ring of orbs, one per bar slot, that opens around a clicked unit during a Decision.
_Avoid_: Selector

**Fighter presenter**:
The node that owns one battle slot's on-screen state: its doll, bars, displayed health, hover ring, floating numbers, stun and death.
_Avoid_: Unit view

**Stage**:
The 800x575 area the original game draws on, which every position recorded from the SWF is measured in.
_Avoid_: Viewport, canvas

**Quest progress**:
How far the player has got through a zone's story battles, which the Hub labels "Stage 11".
_Avoid_: Stage

### Battle

**Battle roster**:
The units placed in one battle, one per slot, as `BattleSetup.build_units` returns them.
_Avoid_: Party roster, which is the save's list of companions who have joined

**Origin**:
Where a unit in a Battle roster came from: the player, a Companion, a Guest or an enemy.
_Avoid_: Source, type

**Companion**:
A member of the player's party, identified by a party id, who fights when deployed.
_Avoid_: Ally, friend

**Guest**:
A unit built from a template that fights on the player's team, such as Felicity in battle 508.
_Avoid_: Companion

**Settlement**:
Everything a finished battle does to the save and the achievements, applied in one call by `BattleSettlement.settle`, and the summary the Victory and Game over screens show.
_Avoid_: Rewards, which are only the money and XP a win pays

### Fonts

**Device font**:
A font the SWF names without embedding it, so the player's machine supplied it.
_Avoid_: System font

**Stand-in font**:
The font the port ships in place of a Device font.
_Avoid_: Fallback font
