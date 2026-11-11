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

**Info card**:
The framed text the Hub shows over everything, with a dim behind it, when the player presses an info spot or Save, or after Proceed on some wins. The Hub does nothing else until the player closes it. It is the original's `krinNavFadeSpeech`.
_Avoid_: Popup, dialog

**HUD**:
The Battle screen's status elements drawn over the hall: unit overlays, member bars, the top status bar and the speech box.
_Avoid_: Overlay, battle UI

**Decision**:
The part of the player's half-turn when the turn loop waits for a pick or a pass.
_Avoid_: Window, decision window

**Radial menu**:
The ring of orbs, one per bar slot, that opens around a clicked unit during a Decision.
_Avoid_: Selector

**Combat text banner**:
The line of text that slides up near the top of the Battle screen to tell the player why a pick or a move was refused, or that they cannot move yet, then fades out. It is the original's `KrinCombatText`.
_Avoid_: Toast, Floating number

**Floating number**:
The number that rises over a unit and fades when a Move result or a Buff tick lands on it, or in its place the miss or shield frame. It is the original's `NumberFixer`.
_Avoid_: Floating text, damage number, popup

**Result flash**:
The glow that pulses on a unit's doll when a hit, a heal or a Focus change lands on it, in one color for each. It is the original's `BATTLEFLASH`.
_Avoid_: Glow, hit flash

**Shield clip**:
The bubble and spark that play on a unit on a Shield block, or when its shield soaks a whole Buff tick. It is the original's `shield` clip on the fighter rig.
_Avoid_: Shield bubble, shield effect

**Fighter presenter**:
The node that owns one battle slot's on-screen state: its doll, bars, displayed health, hover ring, Floating numbers, Result flash, Shield clip, stun and death.
_Avoid_: Unit view

**Buff look**:
What a doll shows from the buffs it holds: its color, its glow and its form. It is separate from the buff icons.
_Avoid_: Buff visual, buff filter

**Ground shadow**:
The shadow under a doll. It is the original's `shadower` clip, and it hides when the unit dies.
_Avoid_: Drop shadow

**Stage**:
The 800x575 area the original game draws on, which every position recorded from the SWF is measured in.
_Avoid_: Viewport, canvas

**Quest progress**:
How far the player has got through a zone's story battles, which the Hub labels "Stage 11".
_Avoid_: Stage

**Cutscene**:
A full-window clip or text screen that fades in from black, plays and fades out to black, as `CutscenePlayer` draws it. It is one of the original's seven `CS_` labels. CS_CUT1 to CS_CUT5 and CS_INTRO2 are video clips, and CS_INTRO is four lines of text over a gradient. One plays before a fight, such as CS_CUT1 before the zone 1 boss, or after a win, such as CS_CUT2. The player can end any of them with the SKIP button, and the Cutscene then goes on where its end would go.
_Avoid_: Cinematic, movie

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

**Deployed pair**:
The two Companions the player has chosen to fight. An empty slot is allowed and spawns no one.
_Avoid_: Active party, team

**Team select**:
The part of the inventory Window where the player picks a Companion to equip and sets the Deployed pair.
_Avoid_: Party menu, team panel

**Half-turn**:
One side's part of a turn, in which each of that side's living units takes one action. The player's half-turn opens with a Decision.
_Avoid_: Turn, round

**Dispatch**:
The moment a unit's action starts, when it pays the move's costs, or fails for lack of them, or is found stunned.
_Avoid_: Cast, start

**Impact**:
The moment a move lands on its target and its Move result applies, which the original marks with `BAMBAMBAM`.
_Avoid_: Hit, blow

**Runback**:
A melee caster's run home after its swing. The original starts the next action without waiting for it.
_Avoid_: Return

**Refusal**:
The reason the player may not pick a move on a target right now: a bad target, too little life or Focus, a cooldown, silence, or a target missing a required buff. When several apply, the Refusal is the one the original would show.
_Avoid_: Failure, which is a move that was picked but could not run

**Move result**:
What one move did to its target, as `BattleManager` resolved it: what kind of move it was, which way it pushed the target's life once sswitch had its say, how much damage, heal or focus change it made, the target's life before it and whether the target was stunned when it landed, and the target's life, Focus, stun and buffs after it.
_Avoid_: Hit, outcome

**Shield block**:
A hit the target's shield is bigger than, so the shield takes all of it and the target takes none. A shield exactly as big as the hit is not a Shield block: the original plays that as a hit that did nothing.
_Avoid_: Absorb, a hit for 0

**Buff tick**:
The damage, healing and Focus change a unit's buffs deal it once after each of its own actions.
_Avoid_: DoT, HoT, ticker

**Settlement**:
Everything a finished battle does to the save and the achievements, applied in one call by `BattleSettlement.settle`, and the summary the Victory and Game over screens show.
_Avoid_: Rewards, which are only the money and XP a win pays

**Story fight**:
A fight picked with the original's `progressFight` on, so a win advances Quest progress. The story orb starts one at each step of Quest progress up to the zone's boss fight, and a new game's first fight, battle 100, is one. A Story fight can name a Cutscene to play before it, as `cutscene_before`.
_Avoid_: Quest fight

**Boss replay**:
A fight the story orb starts once the player has beaten the zone's boss. It has `progressFight` off and `bossFight` on, so a win leaves Quest progress as it is and Proceed opens the zone map, as after the first win over the boss. In zones 1 to 5 it counts as training. It plays no Cutscene before it, so a Boss replay of battle 109 starts with no CS_CUT1.
_Avoid_: Rematch

**Tutorial**:
The fight a new game opens on when the Tutorial option on the new-game screen is on, which it is by default: battle 2, the Metabii fight with Louis the Blind as a Guest. It is not a Story fight. CS_INTRO plays before it and the two Tutorial moves are on the player's bar for it. Losing Sonny loses the game. A win pays no money, XP, drops or achievements and opens no Victory screen. It puts the class's starting moves back on the bar, leaves Quest progress at 0 and goes straight on to CS_INTRO2 and battle 100.
_Avoid_: Training fight, which a training orb starts

### Cutscenes

**Cutscene camera**:
The clip each Cutscene's animation places, whose box, scale and color transform the original applies to the whole animation every frame, so the 533x300 view pans, zooms and tints. The original never draws the clip itself.
_Avoid_: Virtual camera, guide overlay, Camera

### Porting

**Original bug**:
Code in the original that cannot do what it evidently means, such as a variable that is stale or missing in that scope, an accidental repeat or a flag set on the wrong object. The port fixes it.
_Avoid_: Quirk

**Quirk**:
Odd behavior that follows consistently from the original's rules. The port keeps it, and notes it in case it is readdressed later.
_Avoid_: Original bug

### Fonts

**Device font**:
A font the SWF names without embedding it, so the player's machine supplied it.
_Avoid_: System font

**Stand-in font**:
The font the port ships in place of a Device font.
_Avoid_: Fallback font
