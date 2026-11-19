# Leave out the Effects and Graphics options

The original's options have two switches the port does not have: Effects (`MENU[28]`, `Krin.graphics`) and Graphics (`MENU[38]`, `Krin.qual`). We leave both out. They exist to help a slow Flash player, and the port has no use for them. Leaving them out was the project owner's call on 2026-07-18, when the port's options screen came in. The port's options keep the other rows: difficulty, Tutorial, Sound and Autosave.

AS paths below are relative to `dev/source_files/action_script/`.

## What the original does

- Both switches are on at the start of a new game: `Krin.graphics = true` and `Krin.qual = "HIGH"` (`frame_93/DoAction.as:4-5`).
- The new game options (root frame 93, `frame_93/DoAction_2.as:15-23`) and the in-game options (`DefineSprite_3142/frame_39/DoAction.as`) show both rows.
- The Graphics button, `DefineButton2_3124`, flips `Krin.qual` and sets Flash's `_quality` to `"HIGH"` or `"LOW"`, which changes how smoothly the Flash player draws the stage.
- When a battle loads, `Krin.graphics` sets `KrinSettings.SFX` (`frame_201/DoAction.as:87-100`). The speech timing in the conductor (`frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as:832-840`) reads both switches, but both of its branches set `benderADJ` to 30, so the switches change nothing there.
- `DefineButton2_2773` flips `Krin.graphics`. It and the buttons around it only refresh the row's On or Off label.
- The help text says why they exist: "If your game runs slowly or the speech is out of sync, we recommend you turn down the Graphics and Effects." (`MENU[34]`, `frame_1/DoAction.as:242`).

## Consequences

- The port always draws as the original does with both switches on.
- The in-game Options Window (`spec/379-options-window.md`) leaves out the same two rows. Its rect record names their depths in `left_out`.
- A player of the original will notice that the two rows are gone.
