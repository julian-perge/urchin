# Spec: inventory

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `inventory` of [the capability map](107-capability-map.md). It depends on [window-shell](107-window-shell.md): `WindowShell`, `ShellPanel`, the slots and `RightColumn`. Through it, it uses the ui-foundation pieces: `FloatBox`, the rect test, the compare tool and `strings.json`.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the Inventory Window, the original's `KRINMENU` label `inventory` (frame 1), on the window-shell parts and containers, at the SWF's rects. It has three columns: the player's doll with the equip slots and the experience bar, the stats with the piercing and defense bars, and the shared right column.

It also builds the visual states of the party bar, which [#11](https://github.com/julian-perge/urchin/issues/11) and [#195](https://github.com/julian-perge/urchin/issues/195) wire up.

Success is that every piece sits where the SWF places it, the element bars draw the original's layers, the stat and bar text comes from extracted data, and the party bar shows the states those two issues need.

## Assumptions

- Decided with you in this session: the element bars get all of the original's layers, and the inventory builds the bars' tooltip content from `strings.json` and computed numbers, while the tooltip spec owns the tooltip's look.
- The `normal` label (frame 2) repeats this Window without the experience pieces. No ActionScript sends KRINMENU to `normal` (a search for `gotoAndStop("normal")` on KRINMENU finds none), so it is not built.
- Behavior stays as it is, including the port's click-to-equip flow and its `StatusLabel`. The original's pick-up and put-down flow is out of scope, as in window-shell.
- Party bar behavior (shift-click, selection, the Deployed pair) belongs to #11, and Companion equipping to #195. This module builds the states they need and sets them from data that exists today.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. The rect extractor from ui-foundation is the source the test reads. The shell (backdrop, close X) and the right column are window-shell's and are placed, not redefined.

### Panels

| Panel | Variant | Box |
| --- | --- | --- |
| left | `tall` | (47.50, 86.60) 249.05x267.15 |
| party bar | `bar` | (47.50, 358.20) 249.05x50.85 |
| centre | `centre` | (308.95, 82.15) 183.05x326.50 |
| right column | window-shell | origin (503.50, 81.60) |

The centre panel holds a 1 px outline, 2980, at (321.75, 89.45) 158.35x313.20, line #333333. It is a StyleBoxFlat with no fill and no shadow.

### Left panel

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2891 `yut_name` | the member's name | (92.00, 90.05) 166.95x20.20 | `_sans` bold 14 #cccccc center |
| 2890 `yut_info` | `MENU[0]`, level, class (`CLASS[n]`) | (92.00, 109.85) 166.95x19.60 | `_sans` bold 12 #cccccc center |
| 2984 `playerSlot0` to `playerSlot6` | equip slots | centres below | `ItemSlot` |
| 121 to 143 | the doll: 31 part placements named `arm2` to `hand1_f` | part origins between (163.75, 163.30) and (207.95, 260.45) | doll art |
| 2869 `yut_info51` | "Experience:" (`MENU[17]`) | (30.20, 284.40) 103.55x19.05 | `_sans` bold 12 #cccccc right |
| 2868 | experience left box | (138.45, 282.85) 34.30x18.80 | solid #111111 |
| 2867 `bar` | experience fill, 14 frames | (172.60, 283.30) 95.10x18.75 | solid #cccccc |
| 2864 | the gloss over both | (138.50, 283.15) 129.25x19.10 | five-stop black and white alpha gradient, art from #161 |
| 2863 `exp2` | the percent | (136.55, 284.40) 34.80x17.70 | `_sans` bold 10 #ffffff right |

Equip slot centres, by `playerSlot` index: 0 (82.20, 172.15), 1 (263.10, 172.15), 2 (82.20, 212.15), 3 (263.10, 212.15), 4 (263.10, 252.15), 5 (122.20, 252.15), 6 (82.20, 252.15).

- The doll stays `CharacterVisual`, the battle doll, dressed by `dress_from_model`. The battle art is out of scope. This module sets the doll's position and scale from the 31 placements, not from today's typed `DOLL_POSITION` (192.5, 214.4) and `DOLL_SCALE` 1.2.
- The slots are `ItemSlot` scenes, placed by centre. `EquipDollView` keeps its signal and its `setup` and `refresh` methods.
- The experience fill's width is `experience / 100` of its box, as today. The AS for sprite 2867 and its 14 frames is read in the build issue. The result must match the capture.
- The labels, texts and stat names read from `strings.json` (`MENU[0]`, `MENU[17]`, `SYSTEM[0]` to `[6]`, `CLASS`).

### Centre panel: the stats

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2889 to 2885 | `yut_lif`, `yut_str`, `yut_mag`, `yut_spd`, `yut_foc`: `SYSTEM[0]` to `[4]` plus ":" | x 329.95, y 97.10, 114.55, 132.70, 150.85, 168.30, each 85.35x21.90 | `_sans` bold 12, colors #679339, #993333, #c48c3c, #735588, #8da9e9 |
| 2884 to 2880 | the five values | x 385.95, the same rows, 85.35x19.60 | the same colors, right |

- The row pitches are 17.45, 18.15 and 18.15 px, so each row is a fixed-height slot with its own height in a `FloatBox` column.
- The port types its own approximate stat colors today (`MenuTheme.STAT_COLORS`). They go, and the colors come from the record.
- The stat names read `SYSTEM[0]` to `[4]`. The port's typed "Vitality:" and the other four go.

### Centre panel: the element bars

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2879 `yut_per` | "Piercing" (`SYSTEM[5]`) | (329.80, 196.80) 119.80x19.60 | `_sans` bold 12 #666666 |
| 2877 `perBarShow` | eight bars | at (400.50, 256.00). The first bar's box 2874: (332.00, 221.75) 137.00x68.00 | eight 11x68 bars on an 18 px pitch |
| 2878 `yut_def` | "Defense" (`SYSTEM[6]`) | (329.80, 303.20) 119.80x19.60 | as 2879 |
| 2877 `defBarShow` | eight bars | at (400.50, 360.50) | as `perBarShow` |

Each bar is sprite 2873 or 2872 around the white 11x68 shape 2870, stacked in four copies over a track (shape 333 scaled to 13x70):

| Layer | Look | Height, from `DefineSprite_3142/frame_1/DoAction.as` |
| --- | --- | --- |
| `ybar` | dimmed to 10% | not set by the script |
| `bar` | at 30% | `saveH * nT1` for piercing and `saveH * nT4` for defense, capped at `saveH` |
| `gbar` | brightened, with a Glow | `(saveH / 100) * nT2` and `* nT5`, capped at `saveH` |
| `xbar` | brightened, with a Glow | `saveH * nT3` and `* nT6`, not capped |

The colors come from `elementColorArray` (`setRGB`, `frame_1/DoAction.as:226-230`). `value` is `allocation + ceil(100 + 15 * level)`, `x = value / (100 + 15 * level)`, and the `n` terms are the AS's quartic and linear terms of `x + 1`, with the coefficients and thresholds the AS gives. `xbar`'s term can go negative. Flash then flips the clip, and the build checks what the capture shows.

- This module builds all four layers for all 16 bars. Today the port draws one `ColorRect` per bar with `MenuTheme.bar_fill_fraction`, which is only the `bar` layer.
- The formulas are extracted, not typed. A small extractor (proposed: `uv run convert_menu_math`, in `dev/urchin_dev/convert/menu_math.py`) parses the coefficients and the defense-tip thresholds from `frame_1/DoAction.as` into `dev/converted_json/menu_math.json`. The port and its test read that file. `MenuTheme.bar_fill_fraction` and `element_display_value` go.
- The element colors are today a typed constant, `MenuTheme.ELEMENT_COLORS`, which the battle code also reads. See the open questions.
- The Glow on `gbar` and `xbar` is drawn with the existing approach for glows, a tinted extra layer from ffdec art. The build issue shows it against the SWF's frame.

The bar tooltips, built here:

- Piercing: the title is `ELEMENTS[i]`, `SYSTEM[5]`, ": " and the value. The body is `SYSTEM[38]`, `nT2_x`, "%", `SYSTEM[37]`, `nT1_x`, "%", `SYSTEM[39]`, `nT3_x`, "%", `SYSTEM[40]`, with the rounded percentages.
- Defense: the title is `ELEMENTS[i]`, `SYSTEM[6]`, ": " and the value. The body is `DEFTIP[DEF_FACTOR]`, where `DEF_FACTOR` is picked by the thresholds 1, 0.81, 0.61, 0.41 and 0.31 on `1 / x`.
- The inventory passes title and body to the shared tooltip. The tooltip's look stays with the tooltip spec.

### Party bar

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 2979 `fa0` to `fa5` | party faces | centres x 72.20 + 40n, y 384.90 | the parts below |

Each face holds: a black backing, shape 333, 29.50x39.50 (`blacker`); the face 2978 under mask 2898, one frame per member (`avIn`); a hit button 2895; and the frame 2893 with a Glow #99ff00, shown only on the selected member.

- Built as a `PartyFace` scene (proposed: `scenes/ui/menu/party_face.tscn`) with three states:
  - `selected`: the green-Glow frame shows.
  - `deployed`: the black backing is hidden. A member outside the Deployed pair keeps it. The original shows the backing when `friendArrayX` does not hold the member (`updateFriends`).
  - `joined`: a member who has not joined is hidden, not dimmed. The original hides a face whose `id` is below 0, and #11 asks for the same.
- Faces are the existing `assets/ui/menu/portraits/` art from `extract_faces`. The face is drawn under a mask, as the SWF does. The compare tool masks faces out, because ffdec draws them empty.
- The six faces sit at a 40 px pitch, so they are a horizontal `FloatBox` with separation set from the record.
- This module sets the states from data that exists today: the player is `selected`, `deployed` follows `party_deployed`, and `joined` follows the roster. #11 adds the click handling and shift-click. It also adds the rule that a plain click moves `selected`.
- The tooltip on a face is `NameSets[id]` over `MENU[48]` for a Companion and `MENU[49]` for the player (`DefineButton2_2895`, rollOver). The inventory passes both to the shared tooltip.

### The status line

The port draws a `StatusLabel` that shows why an equip or unequip failed ("Inventory is full." and the `Equipment.EQUIP_RESULT_MESSAGES` strings). The original has no such text, because its pick-up flow has no refusal message. It stays as a port-only piece, placed under the doll inside the left panel. It has no rect in the record, and the rect test skips it by name.

## Replacements

- `scenes/ui/menu/inventory_window.tscn` (731 lines of hand-set nodes) is rebuilt from `WindowShell`, three `ShellPanel` scenes, `FloatBox` containers and `RightColumn`. `scripts/ui/menu/inventory_window.gd` keeps `refresh()` and its signals' behavior, and loses the typed geometry constants (`INVENTORY_AT`, `EQUIP_SLOT_CENTERS`, `DOLL_POSITION`, `DOLL_SCALE`, `BAR_BLOCK_CENTERS_Y`, `BAR_TRACK_HEIGHT`, `EXP_FILL`).
- `EquipDollView` keeps working, and its centres come from the scene.
- `MenuTheme` loses `STAT_LABELS`, `STAT_COLORS`, `bar_fill_fraction` and `element_display_value`. `ELEMENT_COLORS` and `HEAL_COLOR` stay until the open question below is settled.
- The Store window also uses `EquipDollView`, and its spec places it with its own centres. This module does not change that view's interface.

## Project structure

Follows `AGENTS.md`. New or changed locations:

```
scenes/ui/menu/inventory_window.tscn      rebuilt
scenes/ui/menu/party_face.tscn            one party face with three states
scenes/ui/menu/element_bar.tscn           one bar with its four layers
scripts/ui/menu/element_bar.gd            sets the layer heights
dev/urchin_dev/convert/menu_math.py       bar coefficients and defense-tip thresholds
dev/converted_json/menu_math.json         its output
```

## Code style

As in ui-foundation. A scene types its Stage numbers once, and the rect test checks them. The bar math reads the extracted file:

```gdscript
class_name ElementBar
extends Control

func show_value(value: float, level: int, math: Dictionary) -> void:
	var x: float = value / (100.0 + 15.0 * level)
	var heights: Dictionary = MenuMath.layer_heights(x, math)
	$Bar.size.y = minf(heights.bar, BAR_HEIGHT)
	$Glow.size.y = minf(heights.glow, BAR_HEIGHT)
	$Extra.size.y = heights.extra
```

The snippet shows style only. `MenuMath` is a small loader for `menu_math.json`.

## Testing strategy

- **Rect test.** Add `inventory_window.tscn`, `party_face.tscn` and `element_bar.tscn` to the record. Every piece in the tables passes under 0.5 px, and the Labels' sizes and colors match.
- **Bar math (GUT).** For a set of values and levels, the layer heights equal the AS formulas, with the coefficients read from `menu_math.json`. The test includes a value below the level's average, where `xbar` goes negative, and one above the cap.
- **Tooltips.** A test builds the piercing and defense tooltips for one element and compares the title and body with `strings.json` and the computed percentages. A second case covers each of the seven `DEFTIP` factors.
- **Party face.** A test checks the three states: a member outside `party_deployed` shows the black backing, an unjoined member is hidden, and only the selected member shows the green frame.
- **Existing tests.** `test_inventory_panel.gd`, `test_item_slot.gd` and the inventory window tests keep passing after the nodes move.
- **Must-fail controls.** Move one stat row 20 px in a copy of the scene and expect the rect test to fail. Change one coefficient in a copy of `menu_math.json` and expect the bar test to fail.
- **Extractor.** A second `uv run convert_menu_math` leaves the JSON byte-identical. `uv run pytest` covers the parsing on a small AS sample.
- **Compare tool.** An `inventory` entry in `chrome` mode, scoring the panels, the bars, the slots and the experience bar inside their masks. Faces and the doll are masked out. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number, color or string from the rect record, `strings.json` or `menu_math.json`. Keep `refresh()` and the right column's API working. Commit `.png.import` sidecars.
- Ask first: A change to `CharacterVisual` or the doll rig. A change to the click-to-equip flow. A change to what `ELEMENT_COLORS` is used for in the battle code.
- Never: Type a stat color, a stat name or a bar coefficient. Hand-place a coordinate the rect record can supply. Dim an unjoined member in place of hiding it. Change party bar behavior in this module.

## Out of scope

- Party bar behavior: selection, shift-click and the Deployed pair ([#11](https://github.com/julian-perge/urchin/issues/11)).
- Companion equipping and per-member stats ([#195](https://github.com/julian-perge/urchin/issues/195)). The window shows the player's stats until then.
- The pick-up and put-down item flow.
- The tooltip's look, and the slot and rarity tooltips named in window-shell.
- The doll rig and its art.
- The `normal` label.

## Success criteria

1. `inventory_window.tscn` places every piece within 0.5 px of the SWF, and the doll is placed from the 31 part placements.
2. The 16 element bars draw four layers each, and their heights match the AS formulas under the bar test.
3. The stat names, colors, labels and tooltips come from `strings.json`, `menu_math.json` or the record. No typed copy is left in `MenuTheme`.
4. The party bar shows the three states, and an unjoined member is hidden.
5. The inventory, equip, unequip, sell and delete flows work as before.
6. The compare tool scores the `inventory` entry under its bar, with the 20 px control over it.
7. `uv run gut` passes.

## Open questions

1. **Element colors.** The colors are typed in `MenuTheme.ELEMENT_COLORS` and used by the battle code too. The standard says to read them from extractor output. This spec leaves them typed and asks whether to extract `elementColorArray` here, in `convert_menu_math`, or in a later battle spec.
2. **Doll placement check.** The doll is a Node2D with art, so the rect test's 0.5 px rule does not fit it directly. This spec proposes that the rect record holds the union rect of the unequipped male doll and that the test allows 1 px. Decide the tolerance.
3. **The doll's pose.** The menu doll may be the rig's idle frame at another scale, or its own pose. The build issue compares the 31 placements with the rig's part origins. If they differ, the build asks you before it changes the doll.
4. **`xbar` below the average.** When `x` is below 1, `xbar`'s height is negative and Flash flips the clip. The spec keeps what the capture shows, as a Quirk, and the build issue records it.
