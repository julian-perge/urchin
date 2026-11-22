# Main menu

The main menu is the first screen. The player starts a new game (name, save
slot, class, settings, then the intro cutscene), loads a saved game into the
hub, or reads the Game Manual and the Credits.

## Sub-features

- `menu-title` shows Start!, Game Manual and Credits.
- `menu-new` takes a name, a slot, a class and the settings, then starts the intro.
- `menu-load` lists the four slots with their save names and loads one into the hub.
- `menu-back` returns each screen to the title.

## How to get to it (user POV)

- Start the game. The title is the first screen.
- Quit from the hub (the red x on the hotbar). Not yet driven.

## Driving it with urchin_verify

Preconditions:

- For `menu-load`: `$V launch v --preset rich:1`. Slot 1 then shows the
  save name `rich`.
- For `menu-new`: `$V launch v` with no preset.

- **Title.** Run `$V tree v TitlePanel --depth 4`. It shows the captions
  `Start!`, `Game Manual` and `Credits`.
- **Open the mode screen.** Run
  `$V click v TitlePanel/Captions/PlaySlot/HitButton --label menu-start`.
  `New Game` and `Load Game` show.
- **Load a game.** Run
  `$V click v ModePanel/Captions/LoadGameSlot/HitButton --label menu-load`,
  then `$V node v SlotPanel/Rows/Row1/SaveName`. Its text is `rich`. Run
  `$V click v SlotPanel/Rows/Row1/HitButton --label menu-slot1 --wait 3000`.
  `$V tree v --depth 1` then prints `scene res://scenes/game.tscn`, and the
  screenshot shows the Zone 1 hub.
- **New game name.** From the mode screen, run
  `$V click v ModePanel/Captions/NewGameSlot/HitButton --label menu-new`,
  `$V click v NamePanel/NameInput --label menu-name-field`, and
  `$V send v '[{"type":"key","key":"Ctrl+A"},{"type":"text","text":"Verify"},{"type":"screenshot"}]' --label menu-name`.
  `$V node v NamePanel/NameInput` reads `"text": "Verify"`.
- **Slot and class.** Run `$V click v NamePanel/OkButton`, then
  `$V click v SlotPanel/Rows/Row1/HitButton --wait 1500`. The class screen
  shows `Please select a class:`. Run
  `$V click v NewGamePanel/ClassPicker/Psychological --wait 4000`. The
  settings screen shows `Difficulty:` `Easy` and `Click here to START!`.
- **Start.** Run `$V click v OptionsPanel/StartButton --label menu-start-game --wait 5000`.
  The scene is `res://scenes/battle_scene.tscn` and the screenshot shows the
  intro text "One month ago. Sonny wakes up on the ship." with `SKIP` at the
  bottom right.
- **Proof.** For `menu-load`, the hub screenshot and the scene line. For
  `menu-new`, the settings screenshot and the intro screenshot.

## Gotchas

- The class cards fade in. Wait about 4 s after the class click before you
  read the settings screen.
- Right after Start, `saves/` under `$V userdir v` is still empty
  (observed 2026-11-21). Do not use a slot file as proof that a new game
  started.
- Each screen has its own `Back/HitButton`. Use the full path, such as
  `ModePanel/Back/HitButton`.
- The intro cutscene's SKIP control is not yet driven.
