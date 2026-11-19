# Keep the tooltip on the Stage

[#1](https://github.com/julian-perge/urchin/issues/1) asks for an ADR for any departure from the original that a player could notice. This one comes from the tooltip spec, [spec/107-tooltips.md](../../spec/107-tooltips.md) ([#364](https://github.com/julian-perge/urchin/issues/364)).

AS paths below are relative to `dev/source_files/action_script/`.

## What the original does

The tooltip, `KrinToolTipper` (DefineSprite 2717), follows the mouse, because each placement calls `this.startDrag(true)` on every frame. Its frame scripts place the text fields to the right of the mouse, or to its left when the mouse is at x 570 or more. Only the plain layout, `GO`, also moves its fields up 50 px when the mouse is below y 500 (`DefineSprite_2717/frame_4/DoAction.as`). The item layout `GO4` and the ability layouts `GO2` and `GO7` never move up (`frame_7`, `frame_13` and `frame_17`). Nothing clamps the clip to the Stage. So an item or ability tooltip shown low on the Stage, such as over the battle's radial orbs, runs past the bottom edge, and the player cannot read its last lines.

## What the port does

The port places the tooltip at the original's offsets from the mouse first. Then it moves the tooltip back inside the 800x575 Stage when any edge would be outside it. When the original's tooltip fits, the two are at the same place. When it does not fit, the port's tooltip slides up or sideways until it fits, and it can cover the mouse.

## Why

The original's offsets show that it means to keep the tooltip readable: it flips at the right edge and moves the plain layout up near the bottom. The other layouts run off the Stage only because their scripts leave the move out. The port had a clamp before this spec, and removing it would make tooltips that the player can read today unreadable.

## Consequences

- A test checks the original's offsets on a tooltip that fits, and the clamp on one that does not.
- A later change to the clamp is a new decision that supersedes this ADR.
