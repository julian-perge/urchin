# Spec: abilities

Source issue: [#107](https://github.com/julian-perge/urchin/issues/107). Module `abilities` of [the capability map](107-capability-map.md). It depends on [window-shell](107-window-shell.md) (`WindowShell` and `ShellPanel`). Through it, it uses `FloatBox`, the rect test, the compare tool, the panel shader and `strings.json` from ui-foundation.

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/godot.md` and `docs/agents/art-extraction.md`. Terms are in [GLOSSARY.md](../GLOSSARY.md).

## Objective

Rebuild the Abilities Window, the original's `KRINMENU` label `skills` (frame 25), on the window-shell parts and containers, at the SWF's rects. It has three columns: the class ability tree, the points and attributes with a hint box, and the combat action bar with the ability pool.

Success is that the panels, titles, points, attribute rows, tree and action ring sit where the SWF places them, the pool's backing, frame and inner shadow match the SWF, and the middle panel shows the hint box that the port lacks.

## Assumptions

- Decided with you in this session, after a side-by-side of the original's capture and the port:
  - The pool keeps the port's named rows. The original shows two columns of icon tiles with no names.
  - The rank text on the tree nodes stays, as a quality-of-life addition.
  - The tree lines stay drawn in code, not extracted art.
  - The buttons stay native Godot Buttons, not image buttons.
  - The hint box is built with its default random tip. Its tutorial steps are left for a follow-up issue.
- Each of those is a departure a player can see, so ADR 0007 (proposed) records them together.
- Behavior stays as it is: learn a talent by click, place an ability in the first free socket, send it back by clicking the socket, spend attribute points with the plus buttons.
- Names and paths marked "proposed" are this spec's choice.

## Pieces

All numbers are Stage px from `timeline.frames()`. The rect extractor from ui-foundation is the source the test reads. Pieces placed from code (the tree nodes, the ring sockets and the pool rows) keep their numbers in script, as [#117](https://github.com/julian-perge/urchin/issues/117) allows, and the rect test checks where they land.

### Panels

| Panel | Variant | Placement | Box |
| --- | --- | --- | --- |
| tree, left | `tall` | 2990 scaled 1x1.296 | (44.93, 73.43) 249.08x346.10 |
| points and hint, centre top | `centre` | 2988 scaled 1.041x0.663 | (304.21, 74.15) 190.62x216.31 |
| attributes, centre bottom | `centre` | 2988 scaled 1.041x0.357 | (304.21, 302.20) 190.62x116.56 |
| action bar and pool, right | `tall` | 2990 scaled 1x1.296 | (506.33, 73.43) 249.10x346.10 |

Each Panel's border is the recipe's rounded mean scale, from the record.

### Titles, name and points

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 3061 `k_title1` | the tree title, `K_TITLE1` | (51.65, 78.10) 232.70x22.10 | `_sans` bold 13 #5e5e5e center |
| 3079 `yut_name` | the member's name | (315.25, 77.70), 166.95 wide | `_sans` bold 14 #cccccc center, as Inventory |
| 3078 `yut_info` | `MENU[0]`, level, class | (315.25, 97.50), 166.95 wide | `_sans` bold 12 #cccccc center, as Inventory |
| 3081 `skLoadKrin` | `SKLOAD` plus ":" | (312.30, 120.15) | `_sans` bold 12 #ffffff |
| 3077 `skillPoints` | the ability points | (378.80, 120.15) | `_sans` bold 12 #ffffff |
| 3080 `spLoadKrin` | `SPLOAD` plus ":" | (312.30, 139.15) | `_sans` bold 12 #ffffff |
| 3076 `statPoints` | the attribute points | (378.80, 139.15) | `_sans` bold 12 #ffffff |
| 3063 `k_title2` | `K_TITLE2` | (311.00, 304.80) 164.45x21.90 | `_sans` bold 13 #333333 center |
| 3062 `k_title3` | `K_TITLE3` | (514.30, 78.10) 233.75x21.90 | `_sans` bold 13 #5e5e5e center |
| 3060 `k_title4` | "Ability Pool", `MENU[16]` | (514.30, 248.10) 233.75x21.90 | as `k_title3` |

- Every string reads from `strings.json`. The port types "Ability Points:" and "Attribute Points:" today, and those constants go.
- The name and class line are the same data as Inventory's, placed at this panel's rects.

### The hint box

The centre top panel holds the clip `reader` (3059), at (317.95, 169.70) 159.70x104.80, text `_sans` 12 #999999.

- The port draws nothing there.
- Its first frame shows a random tip, `MENU[43 + random(4)]` (`DefineSprite_3059/frame_1/DoAction.as`). This module builds that: a Label in the box that shows one of the four tips, picked when the Window opens.
- The clip's other frames are a three-step tutorial (`MENU[7]` to `[10]`, each with `MENU[11]`, "< Click Here >"), shown with a green Glow in the original's capture. They are a follow-up issue and are not built here. The Label and its rect leave room for them.

### The attribute rows

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 3068 to 3071 | the four plus buttons, tinted, at (332.60, 347.45), (332.60, 365.20), (332.60, 383.70), (332.75, 401.35) | | native Buttons |
| 3089 to 3082 | four names at x 356.90 and four values at x 393.90, rows y 338.45 to 392.20 | | `_sans` bold 12, the stat colors from Inventory, values right |

- The row pitches are uneven (17.75, 18.50 and 17.65 px between the plus buttons), so each row is a fixed-height slot with its own height in a `FloatBox` column.
- There is no Focus row, as in the original.
- Each plus button is a native Button. Its StyleBoxFlat fill is the row's color from the record, in plain per-state fills. The SWF's gradient plates and black plus glyph (shapes 3064 to 3067) are not extracted, and the ADR records that.
- The names come from `SYSTEM[0]` to `[3]`, and the colors from the record, as in Inventory.

### The tree

The tree is the sprite `talenttreefull` (3100) at (45.40, 74.15), with 28 nodes `st0` to `st27` in 4 columns on a 52 px pitch (centres x 86.80, 138.80, 190.80, 242.80) and 7 rows on a 40 px pitch (centres y 124.00 to 364.00).

- The nodes are native Buttons over the ability icon, with a rank label, as today. They stay placed from code. Their centres come from the SWF, and the typed `TREE_COLUMNS_X`, `TREE_ROWS_Y` and `TREE_ORIGIN` constants change to values the record confirms.
- The lines between nodes stay drawn in code from `TalentTree` data, as today.
- The icons are the existing `extract_ability_icons` art.

### The action ring

The ring `selector` (3109) is centred at (630.60, 172.20), scaled 1.038, with eight sockets on a 49.5 px radius.

- The sockets are native Buttons over the ability icon, placed from code. The eight offsets in `WHEEL_OFFSETS` are checked against the SWF's `thing0` to `thing7` offsets by the rect test. The socket's shadow (blur 6, distance 4) is a StyleBoxFlat shadow.
- An empty socket's tooltip reads `SKILLNONE`, `SKILLTUT` and `SKILLTUT2` from `strings.json`. The tooltip's look stays with the tooltip spec.

### The ability pool

| cid | Piece | Box | Look |
| --- | --- | --- | --- |
| 3120 `talentPool`, mask 3117 | the pool | (523.60, 274.20) 217.35x133.05 | flat rectangle |
| 3119 | the backing | the pool's rect | solid #1e1e1e |
| 3116 | the frame | over the rows | #262626 |
| 3115, 3114 | the scroll buttons | at the right edge, 33 px apart | native Buttons |

- The backing and the frame are StyleBoxFlat in a PanelContainer. The build issue reads shape 3116's records. If it is a plain outline, it is a border with no fill, and if not, it is art from the chrome extractor, and the build tells you.
- The rows keep the port's named design, five visible rows with a scroll step per click. The rows' size and look are port decisions, covered by the ADR, and they have no rect in the record. The rect test skips them by name.
- The scroll buttons are native Buttons placed at the SWF's rects.
- **The inner shadow** is the one #190 decided. A transparent Control sits above the backing, the rows and the frame. It is clipped to the pool's rect and ignores the mouse. Its canvas item shader uses `blend_mul` with the same ramp as the panel shader, measured from the overlay's own top left, and the 16 panels keep their own shader. The shared ramp moves to a shader include, which ui-foundation's panel shader and this overlay both use. The scroll buttons sit outside the shadow band and the overlay leaves them alone. The build issue runs the render comparison on the pool's rect and posts the score.

### Port-only pieces

- `StatusLabel`, which shows why a learn or an equip failed. The original has none. It stays, as in the other Windows, and the rect test skips it by name.
- The rank text on every tree node.
- The row names in the pool.

## Decisions to record

ADR 0007 (proposed): keep the Abilities window's named pool rows, the tree nodes' rank text, the code-drawn tree lines and the native buttons. Each is a change from the original that a player can see. The ADR says why: the rows and the rank text are quality-of-life additions, and native Godot Buttons are simpler to handle than image buttons and cost only the SWF's gradient plates.

## Replacements

- `scenes/ui/menu/abilities_window.tscn` (469 lines of hand-set nodes) is rebuilt from `WindowShell`, four `ShellPanel` scenes, `FloatBox` containers, the pool's PanelContainer and its overlay. `scripts/ui/menu/abilities_window.gd` keeps its behavior and loses the typed numbers the record replaces, as well as `PoolBackdrop`'s `ColorRect` color constant and the `"^"` and `"v"` scroll texts if the build issue gives the buttons arrows.
- The "Ability Points:" and "Attribute Points:" strings and the stat label strings are read from `strings.json`.
- This module deletes no hand art, because Achievements still uses it.

## Project structure

Follows `AGENTS.md`. New or changed locations:

```
scenes/ui/menu/abilities_window.tscn      rebuilt
scenes/ui/menu/pool_shadow.tscn           the overlay above the pool (proposed)
scenes/ui/panel_shadow.gdshaderinc        the shared ramp, split from the panel shader (proposed)
docs/adr/0007-...                         the departures above
```

## Code style

As in ui-foundation. The overlay's shader reads the shared ramp:

```glsl
shader_type canvas_item;
render_mode blend_mul;

#include "res://scenes/ui/panel_shadow.gdshaderinc"

void fragment() {
	COLOR = vec4(vec3(shadow_ramp(UV, TEXTURE_PIXEL_SIZE)), 1.0);
}
```

The snippet shows style only. `shadow_ramp` stands for the include's function, and the build issue writes it from the panel shader.

## Testing strategy

- **Rect test.** Add `abilities_window.tscn` to the record. Every piece in the tables passes under 0.5 px, the tree nodes and ring sockets included, and the Labels' sizes and colors match.
- **Overlay (GUT).** The overlay is above the backing, rows and frame, ignores the mouse, and is clipped to the pool's rect. Its ramp equals the panel shader's on the same inputs.
- **Behavior (GUT).** The existing abilities window tests keep passing. A new test checks that the hint box shows one of `MENU[43]` to `[46]`.
- **Strings.** A test compares the points labels, the titles and the empty-socket tooltip with `strings.json`.
- **Must-fail controls.** Move one tree node 20 px in a copy of the scene and expect the rect test to fail. Remove the overlay from a copy and expect the overlay test to fail.
- **Compare tool.** An `abilities` entry in `chrome` mode, scoring the panels, the pool backing, the frame and the shadow band. The tree, the ring and the rows are masked out. The build issue posts the score on the pool's rect, as #190 asks. The bar comes from the first passing run, and the reference shifted 20 px scores over it.
- **Whole suite.** `uv run gut` passes before each commit.

## Boundaries

- Always: Take a SWF number, color or string from the rect record or `strings.json`. Keep the learn, place and spend flows working. Commit `.png.import` sidecars.
- Ask first: A change to the pool's row design. A change to `TalentTree` or the ability data. A change to the tooltip content.
- Never: Draw a flat Panel from a PNG. Type a title, a points label or a hint tip. Hand-place a coordinate the rect record can supply. Build the tutorial steps in this module.

## Out of scope

- The hint box's three tutorial steps (a follow-up issue).
- Opening the Window after a level-up. The victory spec does that ([#52](https://github.com/julian-perge/urchin/issues/52)).
- The tooltip's look.
- The radial menu in battle, which shares the ring's art in the original but is a Battle HUD piece.
- The doll and ability art.

## Success criteria

1. `abilities_window.tscn` places every piece within 0.5 px of the SWF.
2. The pool has the backing, the frame and the overlay, and the overlay scores under its bar on the pool's rect.
3. The hint box shows one of the four tips.
4. Every title, points label and attribute name comes from `strings.json`.
5. The learn, place, send back and spend flows work as before.
6. ADR 0007 is in `docs/adr/`.
7. The compare tool scores the `abilities` entry under its bar, with the 20 px control over it.
8. `uv run gut` passes.

## Open questions

1. **The pool's frame.** Whether shape 3116 is a plain outline or has more to it is not read yet. The build issue reads it and says which way it goes.
2. **Plus button color.** The spec fills each plus button with its row's stat color. The SWF tints the plates through `statColor` (3075), and the build issue checks that the tint matches the row color.
3. **Hint box default.** The spec assumes the random tip shows when the player has no upgrade points. The AS that starts the tutorial steps is read in the follow-up issue, so this spec does not say when the tip changes to a step.
4. **ADR scope.** One ADR covers all four departures. Say if you want them split.
