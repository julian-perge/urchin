# Godot container patterns for the original's nested panels

Date: 2026-11-09. Wayfinder ticket [#110](https://github.com/julian-perge/urchin/issues/110) asks which patterns in godotengine/godot-demo-projects fit the original's nested panels and backgrounds, and where native containers fall short of an absolute layout. It belongs to the map [#107](https://github.com/julian-perge/urchin/issues/107), whose Notes ask for screens on native containers instead of TextureRects at hardcoded sizes and offsets, with the look kept faithful to the original. This review reads the demo projects, the Godot 4.7 docs, the 4.7.2-stable engine source, the web SWF through the repo's own `swf_index.py` and `timeline.py`, and the port's scenes. Nothing was measured inside Godot. Container behavior comes from the docs and the engine source. Nothing in the repo changed except this file.

Every claim carries a tag:

- [source]: read in code, data or documentation. The link or path is given.
- [measured]: a script run for this note. The script and its output are in `S/`.
- [inferred]: reasoned from the cited sources. The reasoning is given.
- [guess]: nothing read here settles it.

## Answer

**The original nests its menu panels by position, not by parent.** [measured] On the `win` frame, KRINMENU (DefineSprite 3142) holds 76 direct children: the backdrop and its edge shape, four panels, 51 slot clips, 13 text fields, two buttons, the delete button's art and the three experience rows. Each panel sprite holds one shape and nothing else (`S/krinmenu_frames.txt`). Real nesting exists only inside widgets, such as the experience row 3002, the member bar 3311, the item slot 2986 and the shop picture 3036. [inferred] So a screen's container tree has to be read off rect containment, with margins and separations taken from the differences between rects, while a widget's tree can be copied from its clip.

**Every menu panel is one of three flat rectangles, stretched by its placement matrix.** [source] Shapes 2989, 2987 and 2991 are each four straight edges with one solid fill, #373737, #1A1A1A and #404040, and a 1 px black stroke that scales with the shape (`X:435581-435682`). [measured] KRINMENU draws them at 12 sizes across its five panel frames, with scale factors from 0.3570 to 2.6144 (`S/panel_rects.txt`), and neither SWF has a DefineScalingGrid tag, so nothing in the original is nine-sliced. [measured] All 16 panel placements and moves carry the same inner drop shadow, at 45 degrees with 5 px of blur and distance (`S/panel_filters.txt`), and the port's panel PNGs have the fill and the stroke but no shadow (`S/panel_edges.txt`).

**The demos cover panels, padding and theming, and handle art through slots and overlays.** [source] The patterns that fit, each with its evidence in section 2:

| Pattern | Demo | Fits |
|---|---|---|
| PanelContainer, MarginContainer, VBoxContainer | `gui/theming_override`, `3d/truck_town` | a panel and the column of content in it |
| StyleBox content margins as the padding | `gui/control_gallery`, `mobile/android_iap`, `2d/platformer` | a panel's inset, in fractions of a pixel |
| StyleBoxTexture nine-patches as the theme's panel and button skins | `2d/role_playing_game` | texture-backed panels whose border keeps its width |
| Theme type variations declared in the theme | `2d/role_playing_game` (`title_panel`) | one look per panel shape, text format and slot |
| A plain Control as a slot, with the art inside at its own offset, scale or rotation | `gui/control_gallery`, `mobile/android_iap` | scaled faces and slots, art offset in its panel |
| Overlays anchored inside a widget | `3d/voxel` main menu | the percent over the XP bar, covers over buttons |
| Blocks placed absolutely, containers inside them | `2d/role_playing_game` combat UI, `3d/truck_town`, `gui/multiple_resolutions` | a screen's panel columns |
| Pieces at art-specific positions over a picture | `misc/joypads` | equip slots around the doll, zone buttons |
| Duplicating a theme StyleBox and overriding it per state at run time | `gui/theming_override` | rarity title bars, a selected slot |

[measured] No demo in the clone uses NinePatchRect, and only the role-playing game uses StyleBoxTexture (`rg -l -uu NinePatchRect` and `rg -l -uu StyleBoxTexture` over `D/`).

**Containers fall short of the SWF in nine places, and each has a native answer.**

| Shortfall | Port case | Native answer | Section |
|---|---|---|---|
| Box and Grid children never overlap | percent over the XP bar, "No Items Found" over the drop grid, covers over stance icons | PanelContainer, MarginContainer and CenterContainer give every child the same rect, and a child anchored inside a widget overlaps it | 3.1 |
| A container resets a direct child's rect, rotation and scale | the face scaled 1.6532 in the experience row, equip slots scaled 0.8604 in the shop | a plain Control slot holding the art at its own transform | 3.2 |
| Art bigger than its rect | the WHITE stance cover, glows | StyleBox `expand_margin_*`, or a child whose offsets pass its parent's edge | 3.3 |
| Background bigger than its content | the menu backdrop, the experience row backing | the background as the PanelContainer's StyleBox, with content margins | 3.4 |
| One separation per box | the victory screen's centre column | spacer Controls, or minimum heights from each text field's bounds | 3.5 |
| Whole-pixel layout | the 37.50, 92.50 and 34.40 px pitches | PanelContainer content margins keep fractions, Box, Grid and Margin do not, and a small custom container places children at float positions | 3.6 |
| Texture size is not design size | every 2x, 4x and 5x export | `EXPAND_IGNORE_SIZE` with `custom_minimum_size` at PNG size over zoom. Nine-patch borders draw one canvas unit per texture pixel | 3.7 |
| Flash filters and masks | the panels' inner shadow, glows, the shop picture's mask | StyleBoxFlat's shadow is outer only. Rect masks are `clip_contents`, shaped ones `clip_children` | 3.8 |
| Not a row or a grid | equip slots, zone buttons, talent tree, ability wheel | positions from SWF data inside a fixed-size Control, or a custom container | 3.9 |

**The port's cases.** [measured] The inventory window and the shared inventory panel already match the SWF within 0.10 px. The victory screen draws its two panels at the `inventory` frame's rects, which the `win` frame scales and moves, so they are off by up to 54.50 px. The store is off by up to 15.85 px, the abilities window by up to 33.43 px and the achievements panel by 14.65 px (`S/panel_diffs.txt`, section 4.5). [source] The worked example, the stance rows, is an absolute layout read from `battle_layout.json` at run time. [inferred] In container terms it is a fixed-size slot with a backing, a name and five buttons on a whole-pixel 32.00 pitch with an overlay per button, and its 37.50 px row pitch is the one number a VBoxContainer cannot hold (section 4.1). 19 scene files place TextureRects or TextureButtons at literal offsets (section 4.4).

**What this means for the map.** [inferred] Keep each screen's top-level blocks, the backdrop and the panel columns, at rects read from the SWF, the way the role-playing game demo places its combat UI blocks, and use containers inside each panel. Panel insets go in StyleBox content margins, where fractions survive. Widgets become scenes whose trees follow their clips. Overlap, offset art and art outside its rect use slots and anchored overlays. The repeated looks move into theme type variations, one per panel shape, text format and slot, instead of the 298 local `theme_override_` lines spread over 15 scenes today (`rg -c theme_override_ scenes`).

## How to read this

- Godot source links are pinned to tag `4.7.2-stable`, commit `ed1daf0bf001b61586d9930840f2f1394092c079` (`gh api repos/godotengine/godot/git/ref/tags/4.7.2-stable`), which matches the build string `4.7.2.stable.official.ed1daf0bf`. Docs links point at docs.godotengine.org/en/4.7.
- `D/` is the godot-demo-projects clone at `~/DEV/git_repos/godot-demo-projects`, commit `b761b4cd5718a7118f2c95eb55f181d0a5f004f1` (2026-10-08). The same paths are on GitHub under `https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/`. The demos cited here all set `config/features` to 4.7, like urchin.
- `S/` is `~/tmp/2026-11-09-godot-container-patterns/`, listed in the appendix.
- `X:` line numbers are in `dev/source_files/swf_xml/sonny-2-2900.xml`, the web build's dump. `AS/` is `dev/source_files/action_script/`.
- urchin paths are relative to the repo, with line numbers at commit `92ddb929`. "The spec" is the worked example, `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md`.
- Geometry is in design px. KRINMENU sits unscaled at (400.50, 222.40) on root frame 181 [measured, `S/krinmenu_stage.txt`], so a KRINMENU local position plus that offset is a stage position, and stage coordinates drop into the port's window 1:1 (CLAUDE.md, Godot specifics). Where the 800x575 stage sits in the 800x600 window is [#111](https://github.com/julian-perge/urchin/issues/111)'s question and changes nothing below.
- In a `.tscn`, `layout_mode = 0` is position mode, 1 anchors, 2 container and 3 uncontrolled ([control.h:149-154](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/control.h#L149-L154)). "Literal offsets" below means position mode with typed `offset_*` values.

## 1. What the original nests

### 1.1 Screens are flat

- [source] The menu shows one labeled frame at a time, and every entry point is a `gotoAndStop` on a label, for example `this.gotoAndStop("win")` after a won battle (`AS/frame_181/PlaceObject3_3142_175/CLIPACTIONRECORD onClipEvent(load).as:3-6`) and `KRINMENU.gotoAndStop("skills")` (`AS/DefineButton2_3184/BUTTONCONDACTION on(release).as:6`). Every rect in this note is read on the labeled frame.
- [measured] The `win` frame's 76 children of KRINMENU are the backdrop sprite 2994 and edge shape 2995, the panels at depths 5, 7, 11 and 21, the 36 `itemSlot` and 15 `dropSlot` clips, 13 text fields, the Proceed hit button 3004, the delete button 2858 and its art 2860, and the experience rows at depths 1111, 1154 and 1197 (`S/krinmenu_frames.txt`). The left panel is depth 11 of the same timeline as the rows that appear inside it, and its sprite 2990 holds only shape 2989.
- [inferred] Flash draws a panel and the content over it as siblings, so the SWF never says which panel a text field belongs to. A container rebuild has to decide it from geometry: a piece belongs to the smallest panel whose rect contains its own, and that panel's content margins are the gaps between its rect and the union of its pieces' rects.

### 1.2 The panels

[source] The three panel shapes (`X:435581-435682`):

| Shape | Sprite | Fill | Stroke | Unscaled size |
|---|---|---|---|---|
| 2989 | 2990 | #373737 | 1 px black, scaling | 249.05 x 267.15 |
| 2987 | 2988 | #1A1A1A | 1 px black, scaling | 183.05 x 326.50 |
| 2991 | 2992 | #404040 | 1 px black, scaling | 249.05 x 50.85 |

Each is one StyleChangeRecord and four StraightEdgeRecords, so square corners and nothing else. The stroke is 20 twips with `noHScaleFlag` and `noVScaleFlag` false, in a DefineShape4 with `usesScalingStrokes` true, so it scales with the placement.

[measured] Stage rects on each labeled frame, from the shape bounds through the placement matrix (`S/panel_rects.txt`):

| Frame | Depth | Panel | Scale x, y | Stage rect, x then y |
|---|---|---|---|---|
| inventory | 7 | large | 1, 1 | 503.50..752.55, 81.60..348.75 |
| inventory | 5 | bar | 1, 1 | 503.50..752.55, 358.20..409.05 |
| inventory | 11 | large | 1, 1 | 47.50..296.55, 86.60..353.75 |
| inventory | 9 | bar | 1, 1 | 47.50..296.55, 358.20..409.05 |
| inventory | 21 | centre | 1, 1 | 308.95..492.00, 82.15..408.65 |
| win | 11 | large | 0.8942, 1.2249 | 36.12..258.82, 80.96..408.20 |
| win | 21 | centre | 1.1644, 1 | 274.90..488.05, 82.15..408.65 |
| shop | 11 | large | 0.8942, 1.2249 | 36.12..258.82, 80.96..408.20 |
| shop | 21 | centre | 1.1644, 0.4178 | 274.90..488.05, 81.83..218.25 |
| shop | 23 | centre | 1.1644, 0.5375 | 274.90..488.05, 232.36..407.86 |
| skills | 7 | large | 1.0001, 1.2955 | 44.93..294.02, 73.43..419.53 |
| skills | 5 | large | 1.0002, 1.2955 | 506.33..755.42, 73.43..419.53 |
| skills | 23 | centre | 1.0414, 0.6625 | 304.21..494.84, 74.15..290.46 |
| skills | 21 | centre | 1.0414, 0.3570 | 304.21..494.84, 302.20..418.76 |
| ach | 5 | large | 2.6144, 1.1228 | 74.96..726.07, 82.41..382.35 |

The `win` and `shop` frames keep the inventory frame's depth 7 and 5, the shared inventory panel and its money bar, unchanged.

- [measured] Neither SWF has a DefineScalingGrid tag: `rg -c -i 'scalinggrid|scale9'` finds nothing in either XML dump. [inferred] Flash scales a whole panel, stroke included, so the achievements panel's left and right strokes are 2.61 px wide and its top and bottom 1.12 px.
- [measured] Every placement and move of a panel sprite in KRINMENU, 16 tags, carries one filter: a DropShadow with `innerShadow` true, angle 0.785 rad, blur 5 by 5, distance 5, strength 1, black, one pass (`S/panel_filters.txt`, the first at `X:441599-441605`). [inferred] An inner shadow at 45 degrees darkens the inside of the panel along its top and left edges.
- [source] ffdec applies a placement's filters at the export zoom only. `Timeline.java:1462` passes `unzoom` and `DROPSHADOWFILTER.java:100-101` multiplies blur and distance by it, at jpexs `cde1cc21a` (`~/DEV/git_repos/jpexs/libsrc/ffdec_lib/src/com/jpexs/decompiler/flash/`). So in the ffdec renders the project verifies against, the shadow keeps its 5 px at every panel scale. [guess] Flash Player does the same.
- [measured] The port's `panel_large.png`, `panel_center.png` and `panel_bar.png` are flat gray 55, 26 and 64 inside a one-pixel dark edge, with no shadow anywhere (`S/panel_edges.txt`).

### 1.3 Widgets are nested

[measured] Four clips on these frames own their children (`S/krinmenu_frames.txt`):

- The experience row 3002, placed on `win` at (-252.90, -49.75), (-252.90, 42.75) and (-252.90, 135.25), a 92.50 pitch. It holds a black backing 3001 of 196.80 x 83.20, the face sheet 2978 (`avIn`) scaled 1.6532 at (-66.40, 0.50), the name and level fields 3000 and 2999, the XP bar 2867 (`bar`), a 128.80 x 18.75 shape 2998 above it and the percent field 2997 over both.
- The member bar 3311, set out in `docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md:45-94`.
- The item slot 2986: slot art 2983, the icon sheet 2064 (`inner`) and the button 2985, all at (0, 0).
- The shop picture 3036 on `shop`: a 186 x 140 mask 3021 at `clipDepth` 3, the 203.05 x 154 picture 3023 clipped by it, and the 187 x 141 shape 3020 above both and outside the mask.

[inferred] These are the widgets whose Godot scenes can copy the clip's tree: a backing, then each piece at its local offset. They are also where most of the overlap and the offset art live (sections 3.1 and 3.2).

## 2. Demo patterns that fit

### 2.1 Panel, margin, stack

- [source] `D/gui/theming_override/test.tscn:58-81` centres a PanelContainer with anchors and offsets, puts a MarginContainer with 20 px margins in it and a VBoxContainer with a 10 px separation in that. The theme is a sub-resource on the root Control (`:35-55`), so every control below inherits it. `D/3d/truck_town/car_select/car_select.tscn:85-120` repeats the PanelContainer, MarginContainer, HBoxContainer chain inside a fixed 1024 x 600 root.
- [source] The rule underneath: a container's children stop positioning themselves, and the container re-positions them whenever it is resized ([Using Containers](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html#container-layout)).
- [inferred] Fits a menu panel and the column of content in it.

### 2.2 Content margins as padding

- [source] `D/gui/control_gallery/control_gallery.tscn:6-15` gives a StyleBoxFlat 10 px content margins and uses it as the panel override on four PanelContainers (`:72`, `:362`, `:446`, `:482`), with no MarginContainer. `D/mobile/android_iap/item.tscn:6-26` does the same with 15 px for a store card, and `D/2d/platformer/gui/theme.tres:6-57` sets content margins on every StyleBox in its theme.
- [source] A PanelContainer insets its children by its StyleBox's margins ([Using Containers](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html#panelcontainer)). Content margins are floats ([StyleBox](https://docs.godotengine.org/en/4.7/classes/class_stylebox.html#class-stylebox-property-content-margin-left)), and the sort uses them unrounded ([panel_container.cpp:106-121](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/panel_container.cpp#L106-L121)).
- [inferred] Fits every scaled KRINMENU panel, whose content sits at fractional insets.

### 2.3 Texture skins in the theme

- [source] `D/2d/role_playing_game/theme/theme.tres:39-45` and `:87-88` skin Panel and PanelContainer with a StyleBoxTexture over `panel_rect.png`, 128 x 152, and `:15-37` and `:74-78` do the same for Button's states. The texture margins are 32 px on three sides and 56 px at the bottom, which keeps the art's thick bottom lip and shadow from stretching. The PanelContainer reference lists this demo as its example ([PanelContainer](https://docs.godotengine.org/en/4.7/classes/class_panelcontainer.html)).
- [source] A StyleBoxTexture fully stretches only the centre cell of its 3x3 grid, and its texture margins stand in for the content margins when those are negative ([StyleBoxTexture](https://docs.godotengine.org/en/4.7/classes/class_styleboxtexture.html#class-styleboxtexture-property-texture-margin-left)).
- [inferred] Fits texture-backed art whose border has to keep its width at any size. KRINMENU's panels are not that case, since Flash scales their whole shape (1.2).

### 2.4 Type variations

- [source] The same theme declares `title_panel` as a variation of Panel with its own panel StyleBox (`theme.tres:105-106`), and `D/2d/role_playing_game/dialogue/interface/interface.tscn:13-20` puts it on one Panel through `theme_type_variation`. A variation extends a base type, keeps whatever it does not override and can chain ([theme type variations](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_theme_type_variations.html)). A control checks its variation before its class name at every step of the theme lookup ([GUI skinning](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html#customizing-a-project)).
- [source] The port's project theme has one variation, `RegularLabel` (`scenes/ui/project_theme.tres:10-11`), used by seven scene nodes and two scripts. [measured] Against that, the scenes carry 298 local `theme_override_` lines.
- [source] The skinning tutorial treats local overrides as the normal tool for layout constants, the separations and margins of Box, Grid and Margin containers, and as a poor tool for a consistent look ([GUI skinning](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html#customizing-a-control)).
- [inferred] Fits the original's repeated looks: one variation per panel shape (2989, 2987, 2991), per text format and per slot style, with each screen's spacing left as local overrides read from the SWF.

### 2.5 Slots

- [source] `D/gui/control_gallery/control_gallery.tscn:424-438` puts a plain Control with a 64 x 64 `custom_minimum_size` in an HBoxContainer, and inside it a 128 x 128 TextureProgressBar at `scale` 0.5. `D/mobile/android_iap/item.tscn:32-53` puts a Control with a 180 px minimum height in a VBoxContainer, and inside it a 170 x 170 TextureRect anchored to the slot's centre and rotated 40 degrees about its own middle.
- [source] The plain Control is there because a container sets each direct child's rect and resets its rotation to 0 and its scale to 1 ([container.cpp:151-153](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/container.cpp#L151-L153)), which the Control reference also notes for scale ([Control.scale](https://docs.godotengine.org/en/4.7/classes/class_control.html#class-control-property-scale)). A container only sorts its direct Control children, and it skips top-level ones and non-Controls ([container.cpp:170-174](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/container.cpp#L170-L174)).
- [source] The port already does this for buff icons: each icon and its counter sit in a plain Control with a minimum size inside the buff row's HBoxContainer (`scripts/battle/unit_overlay.gd:81-118`).
- [inferred] Fits art that keeps its own transform inside a laid-out slot: the face scaled 1.6532 in the experience row, the shop's equip slots scaled 0.8604, a hi-res texture shown at 1/zoom. The doll, a Node2D (`scripts/entities/character_visual.gd:21`), keeps its own position inside any container for the same reason.

### 2.6 Overlays inside a widget

- [source] `D/3d/voxel/menu/main/main_menu.tscn:89-102` gives each TextureButton in a VBoxContainer a Label child anchored to the button's full rect with its bottom offset at -18 px, and `:45-75` pins a rotated Label to the logo TextureRect's bottom-right corner through a holder Control anchored there. The TextureRect reference lists this demo ([TextureRect](https://docs.godotengine.org/en/4.7/classes/class_texturerect.html)).
- [source] A control drawn over a button has to ignore the mouse, or it takes the button's clicks ([Control](https://docs.godotengine.org/en/4.7/classes/class_control.html#description), "User Interface nodes and input").
- [source] The port's hotbar does this already: each button's Glow and Icon TextureRects are anchored to its centre (`scenes/ui/hotbar.tscn:150` onward).
- [inferred] Fits the percent field over the XP bar, the covers over the stance icons and the highlight over an item slot.

### 2.7 Blocks placed absolutely, containers inside

- [source] `D/2d/role_playing_game/combat/combat.tscn:881-910` places an HBoxContainer and a PanelContainer at fixed offsets under one themed Control, and lays out their children with containers. `D/gui/multiple_resolutions/main.tscn:70-176` puts a Panel in an AspectRatioContainer, pins ColorRects and TextureRects to its corners with anchors and offsets, and centres a CenterContainer with a VBoxContainer of options in the same Panel.
- [inferred] Fits a screen whose columns sit at uneven gaps, which is every KRINMENU frame. On `win` the left, centre and right panels are 16.08 and 15.45 px apart and their tops differ by up to 1.19 px (1.2), and one HBoxContainer has one separation and one top edge.

### 2.8 Pieces over a picture

- [source] `D/misc/joypads/joypad_diagram.tscn:6-60` lays highlight sprites over a controller picture at fixed positions, one per button.
- [inferred] Fits pieces whose positions belong to the art: the equip slots around the doll, the zone buttons on the world map.

### 2.9 Run-time style changes

- [source] `D/gui/theming_override/test.gd:23-35` duplicates a Button's theme StyleBoxes and installs the copies with `add_theme_stylebox_override`, one per state.
- [inferred] Fits state the original shows with color, such as rarity title bars or a selected slot.

## 3. Where containers fall short

### 3.1 Overlap

- [source] BoxContainer and GridContainer lay children out one after another, so they never overlap ([box_container.cpp:176-290](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L176-L290), [grid_container.cpp:236-331](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/grid_container.cpp#L236-L331)). Flash has no such rule. [measured] On `win` the "No Items Found" field 3003 sits at stage y 165.80, between the drop grid's first and last row centres at 146.65 and 222.65.
- [source] PanelContainer and MarginContainer give every child the same rect ([panel_container.cpp:114-120](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/panel_container.cpp#L114-L120), [margin_container.cpp:122-131](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/margin_container.cpp#L122-L131)), and CenterContainer centres every child at its minimum size ([CenterContainer](https://docs.godotengine.org/en/4.7/classes/class_centercontainer.html)). Their children overlap by design and draw in tree order, children over parents ([CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#description)).
- [source] `z_index` changes only the draw order, input still follows the tree ([CanvasItem.z_index](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-z-index)), and `show_behind_parent` draws a child under its parent ([same page](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-show-behind-parent)).
- [inferred] Native answer: overlapping alternatives, such as the drop grid and "No Items Found", are siblings in one MarginContainer with one shown at a time. An overlay on a widget is a child anchored inside it that ignores the mouse (2.6).

### 3.2 Offset and scaled art

- [measured] Inside the experience row the face sheet sits at (-66.40, 0.50) scaled 1.6532, and on `shop` every equip slot 2984 is scaled 0.8604, against unscaled slots on `inventory` (`S/krinmenu_frames.txt`).
- [source] A container would reset both the offset and the scale of a direct child (2.5).
- [inferred] Native answer: the slot pattern (2.5). An offset alone becomes the child's anchors and offsets inside its slot ([size and anchors](https://docs.godotengine.org/en/4.7/tutorials/ui/size_and_anchors.html)).
- [source] The obvious native node is not always the faithful one. The XP bar looks like a TextureProgressBar, whose progress texture is clipped by its value ([TextureProgressBar](https://docs.godotengine.org/en/4.7/classes/class_textureprogressbar.html#class-textureprogressbar-property-texture-progress)), but the original stretches the bar clip: `bar._width = exp / 100 * 95.10000000000001` (`AS/DefineSprite_3142/frame_9/PlaceObject3_3002_1111/CLIPACTIONRECORD onClipEvent(enterFrame).as:12`). A TextureRect whose width is set, as the port does, matches it. The port's full width is 150 px (`scripts/battle/victory_experience_row.gd:21`), not 95.1.

### 3.3 Art bigger than its rect

- [source] The WHITE stance cover is 33.25 x 18.50 against a 28.25 x 13.75 icon (`docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md:88-94`).
- [source] StyleBoxFlat and StyleBoxTexture both have `expand_margin_*`, which draws the box past the control's rect without changing its size, and for StyleBoxFlat the docs add that the clickable area does not grow ([StyleBoxFlat](https://docs.godotengine.org/en/4.7/classes/class_styleboxflat.html#class-styleboxflat-property-expand-margin-left), [StyleBoxTexture](https://docs.godotengine.org/en/4.7/classes/class_styleboxtexture.html#class-styleboxtexture-property-expand-margin-left)).
- [source] A Control clips its children only with `clip_contents` on ([Control.clip_contents](https://docs.godotengine.org/en/4.7/classes/class_control.html#class-control-property-clip-contents)), so a child with offsets past its parent's edges draws there.
- [inferred] Native answer: a glow around one control is that control's StyleBox with expand margins. The port's `_place_cover` centres each cover at its own size in code (`scripts/battle/stance_row.gd:93-97`), and the same placement can be declared in the scene with centre anchors.

### 3.4 Backgrounds bigger than their content

- [measured] The menu backdrop 2994 is 768.55 x 425.10 at stage 14.15..782.70, 15.00..440.10, with every panel inside it. The experience row backing 3001 is 196.80 x 83.20 behind a face, two fields and a bar.
- [source] A PanelContainer draws its StyleBox at its full rect and insets its children by the content margins (2.2). A StyleBoxTexture with zero texture margins has no border cells, so the whole texture stretches to the rect ([style_box_texture.cpp:166-185](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/style_box_texture.cpp#L166-L185)).
- [inferred] Native answer: the background is the containing PanelContainer's StyleBox, the extracted art in a zero-margin StyleBoxTexture so it stretches the way Flash scales it, with the measured insets as content margins. A background that has to stay its own node is the first child of a MarginContainer or PanelContainer, which stacks it under the content (3.1).

### 3.5 Uneven gaps

- [measured] The centre column on `win`, by the stage y of each piece's placement: `vb1` (the drops heading) 92.40, the drop grid's row centres 146.65 to 222.65, `vb2` (the "CLICK on the items" hint) 246.80, the money and experience rows 289.20 and 306.80, `vb7` 329.20, and the Proceed text `vb8` 365.65. No two gaps are equal.
- [source] A BoxContainer has a single `separation` constant ([BoxContainer](https://docs.godotengine.org/en/4.7/classes/class_boxcontainer.html#class-boxcontainer-theme-constant-separation)). `D/3d/voxel/menu/main/main_menu.tscn:152` and `:169` put empty Controls named Spacer inside boxes.
- [inferred] Native answer: each text field takes a minimum height from its DefineEditText bounds and the rest of each gap is a spacer, or a child sits in a MarginContainer with its own top margin. Either way the numbers come from an extractor, not a hand.

### 3.6 Fractional geometry

- [source] BoxContainer works in whole pixels: its size is a `Size2i`, each child's minimum size is rounded up, and offsets and the separation are ints ([box_container.cpp:48](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L48), [:70](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L70), [:104](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L104), [:178](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L178), [:252-256](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/box_container.cpp#L252-L256)). GridContainer uses `Size2i` too ([grid_container.cpp:50](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/grid_container.cpp#L50), [:66](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/grid_container.cpp#L66)). MarginContainer's inner size is an int ([margin_container.cpp:128-130](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/margin_container.cpp#L128-L130)), theme constants are integers by definition ([GUI skinning](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html#theme-items)), and a shrink-centred child's offset is floored ([container.cpp:131](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/container.cpp#L131), [:147](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/container.cpp#L147)).
- [source] The SWF's pitches: item slots 38.00 (`scripts/ui/menu/menu_theme.gd:21-24`), stance buttons 32.00 (spec `:65`), member bar rows 37.50 (spec `:47-48`). [measured] Experience rows 92.50, the shop's equip slots 34.40 to 34.45.
- [inferred] 38 and 32 fit a container exactly. 37.50 and 92.50 drift by half a pixel per row, and 34.40 by 0.40 per slot.
- [source] Native answers: PanelContainer content margins keep fractions (2.2), and a custom container is a script that handles `NOTIFICATION_SORT_CHILDREN` and calls `fit_child_in_rect` with any Rect2 ([Using Containers](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html#creating-custom-containers), [Container](https://docs.godotengine.org/en/4.7/classes/class_container.html)), so it can place children at float positions.
- [source] Godot snaps Control vertices to pixels by default ([gui/common/snap_controls_to_pixels](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-gui-common-snap-controls-to-pixels)), and urchin also turns on `rendering/2d/snap/snap_2d_transforms_to_pixel` (`project.godot:66`). [guess] Whether that rounds to design pixels or to the 1600 x 1200 window's pixels (`project.godot:39-41`) decides whether a half-pixel container error shows at all. The victory prototype ([#108](https://github.com/julian-perge/urchin/issues/108)) can measure it with its ffdec comparison.

### 3.7 Texture size is not design size

- [source] The port exports art at 2x for the menus (`scripts/ui/menu/menu_theme.gd:5`), 4x for the battle chrome (`assets/backgrounds/battle/battle_layout.json:147`) and 5x for the class cards (`scenes/main_menu.tscn:265-267`), and checks `rect * ZOOM == PNG pixel size` (CLAUDE.md, Verifying).
- [source] A TextureRect in the default `EXPAND_KEEP_SIZE` mode cannot shrink below its texture, `EXPAND_IGNORE_SIZE` drops that, and the fit-width and fit-height modes are flagged experimental inside containers ([TextureRect](https://docs.godotengine.org/en/4.7/classes/class_texturerect.html#enum-texturerect-expandmode)).
- [source] A nine-patch draws its border cells at one canvas unit per texture pixel. NinePatchRect and StyleBoxTexture both hand their margins to `canvas_item_add_nine_patch` ([nine_patch_rect.cpp:50](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/nine_patch_rect.cpp#L50), [style_box_texture.cpp:181-184](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/style_box_texture.cpp#L181-L184)), the renderer passes those margins on with a pixel size of one over the source size ([renderer_canvas_render_rd.cpp:2567-2576](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp#L2567-L2576), [:2605-2608](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp#L2605-L2608)), and the shader maps a border pixel of the destination straight to a texture pixel ([canvas.glsl:278](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/canvas.glsl#L278), [:435-441](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/canvas.glsl#L435-L441)). [inferred] A 4x nine-patch therefore draws its borders four times too wide. With zero margins there are no border cells, and the texture simply stretches.
- [inferred] Native answers: `EXPAND_IGNORE_SIZE` with `custom_minimum_size` at PNG size over zoom, which `scripts/battle/stance_row.gd:96` already computes for the covers. A nine-patch made from a 1x render. Or the slot pattern (2.5), the native-size node scaled by 1/zoom inside a plain Control, as the control gallery does at 0.5.

### 3.8 Filters and masks

- [source] StyleBoxFlat's shadow is an outer one, set by `shadow_color`, `shadow_size` and `shadow_offset`, its border widths are ints per side, and `border_blend` fades a border into the fill ([StyleBoxFlat](https://docs.godotengine.org/en/4.7/classes/class_styleboxflat.html#class-styleboxflat-property-shadow-size)). Nothing in it draws an inner shadow, so the panels' 5 px inner DropShadow (1.2) has no StyleBoxFlat equivalent.
- [inferred] Options for the inner shadow: a StyleBoxTexture nine-patch made from an ffdec render of the filtered placement at 1x, whose 5 px edge then holds at every size the way ffdec draws it (1.2). That texture is magnified 2x by the 1600 x 1200 window with the project's nearest filter (`project.godot:64`, where 0 is Nearest per [project_settings.cpp:1844](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp#L1844)). A CanvasItem shader on the panel. Or an ADR that leaves the shadow out. [guess] A wide `border_blend` border on the top and left comes close, since a one-pass box blur of an edge is a linear ramp.
- [source] Text Glow and DropShadow filters map at best to a Label's outline and shadow theme items, which the role-playing game theme sets for Label (`D/2d/role_playing_game/theme/theme.tres:79-86`). The port already reads the class card names' two glows as two label colors (`scenes/main_menu.tscn:268-269`).
- [source] `clip_contents` clips children to the control's rectangle and stops their input outside it ([Control.clip_contents](https://docs.godotengine.org/en/4.7/classes/class_control.html#class-control-property-clip-contents)). `clip_children` masks children with a CanvasItem's alpha, and clipping nodes cannot nest ([CanvasItem.clip_children](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-clip-children)). The shop picture's mask 3021 is a plain rectangle (`X:436380-436400`), so `clip_contents` is enough, and the port's ShopBackdrop already sets it (`scenes/ui/store/store_window.tscn:61-67`).

### 3.9 Layouts that are not rows or grids

- [source] The equip slots stand around the doll (`scripts/ui/store/store_window.gd:23-31`), the zone buttons sit on the world map art and are hand-placed (`scripts/zones/zone_map.gd:2`), the talent tree's nodes sit on four columns and seven rows (`scripts/ui/menu/abilities_window.gd:22-23`), and the ability wheel's eight sockets sit on a ring (`:26-32`).
- [inferred] Native answer: a fixed-size Control with each piece at a position read from the SWF, the joypad pattern (2.8). The tree's columns are 52 px apart and its rows about 40, so a GridContainer could hold it if its prerequisite lines are drawn over it. The wheel needs a custom container or plain positions.

## 4. The port's cases

### 4.1 The worked example: stance rows

- [source] The spec extracts the parts, a backing 3309, five stance icons and two covers, and rebuilds the arrangement in Godot (`docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md:153-203`). `scripts/battle/stance_row.gd:49-73` places the backing, the name and the five buttons at run time from `battle_layout.json`, and `scripts/battle/battle_scene.gd:647-668` stacks the rows `row_pitch` apart. Nothing in it is a container, and none of its numbers is typed by hand.
- [inferred] The same row on containers: a fixed 285.00 x 31.50 PanelContainer whose panel StyleBox is the extracted backing in a zero-margin StyleBoxTexture, the name Label at its own offset, and an HBoxContainer with a separation of 0 holding five 32 px slots, each with its 28.25 x 13.75 icon centred and its cover centred over the icon (2.6, 3.3). The 32.00 pitch is whole, so the box reproduces it exactly. The 37.50 row pitch is not, so the rows stay where `battle_scene.gd` puts them, or go in a custom container (3.6).
- [inferred] The spec's rule carries over unchanged: the parts are art, the arrangement is Godot. Containers are one native way to build the arrangement, the run-time placement from the layout JSON is another, and both read their numbers from the SWF.
- [source] Battle HUD decisions wait on [R1](https://github.com/julian-perge/urchin/issues/41) and [R2](https://github.com/julian-perge/urchin/issues/44) (map Notes), so this is a mapping, not a proposal.

### 4.2 Victory screen

- [source] The victory screen is KRINMENU stopped at `win` (1.1). `scenes/battle/victory_screen.tscn:43-75` draws LeftPanel and MiddlePanel at the `inventory` frame's rects.
- [measured] On `win` the left panel is 36.12..258.82, 80.96..408.20 and the centre panel 274.90..488.05, 82.15..408.65, so the port is off by up to 54.50 and 34.10 px (`S/panel_diffs.txt`).
- [measured] The left panel holds three experience rows, 196.80 x 83.20 each, at x 49.20..246.00 and a 92.50 pitch, under the title field `vbbc1` at (43.30, 89.10). The port places its rows 62 px apart from y 120 with no backing (`scripts/battle/victory_screen.gd:71-88`, `scenes/battle/victory_experience_row.tscn`).
- [measured] The centre panel holds a 5 by 3 drop grid on a 38 px pitch, with slot centres at x 305.10 to 457.10 and y 146.65 to 222.65. [inferred] With the 31 px slot art centred on each placement point, as the inventory grid's already-matching slots show, the grid leaves 14.70 and 15.45 px to the panel's sides. [source] The port uses 4 columns (`scripts/battle/victory_screen.gd:19-20`).
- [source] The original's Proceed is the text field `vb8` with Glow and DropShadow filters, over button 3004, which has only a hit-test record (`X:436158-436168`) and is stretched to (5.7167, 0.8537) [measured]. The port's ProceedButton has dark StyleBoxFlat backings (`scenes/battle/victory_screen.tscn:8-20`, `:168-169`).
- [inferred] On containers: three absolute columns (2.7), the right one the existing InventoryPanel scene. The left column is a PanelContainer in the large panel's look with a VBoxContainer of the title and up to three row scenes, each row a PanelContainer over 3001 with the face in a slot (2.5) and the percent over its bar (2.6). The centre column is a PanelContainer with a VBoxContainer whose uneven gaps come from spacers (3.5), with the drop grid and "No Items Found" stacked in one MarginContainer (3.1), and Proceed as a Button with empty StyleBoxes in a text-button variation.

### 4.3 Store window

- [measured] On `shop` the left panel is 36.12..258.82, 80.96..408.20, the centre panels 274.90..488.05 by 81.83..218.25 and 232.36..407.86, and the port's three panels are off by up to 15.85 px (`S/panel_diffs.txt`). The port's left panel keeps the unscaled 249.10 width around the same centre, where the SWF squeezes it to 222.70.
- [measured] The shop picture's mask is 186 x 140 at 55.25..241.25, 99.90..239.90, with the 187 x 141 shape 3020 drawn over it. The port's ShopBackdrop is 227 x 150 at 34.0..261.0, 92.0..242.0 (`scenes/ui/store/store_window.tscn:61-67`).
- [measured] The equip slots' centres match the SWF (`scripts/ui/store/store_window.gd:23-31`), but the SWF scales each slot by 0.8604 and the doll's parts by the same factor against the inventory frame, where the port draws 31 px slots and a 0.85 doll (`:32-33`).
- [measured] The catalog grid matches: the SWF's first catalog slot is centred at (305.10, 291.85), and the port's StoreItems GridContainer starts at (289.6, 276.4) with a 7 px separation on 31 px slots, which centres its first slot at (305.1, 291.9) (`scenes/ui/store/store_window.tscn:120-129`).
- [inferred] On containers: the left column is a VBoxContainer of the picture slot, a fixed 187 x 141 Control with the picture under `clip_contents` and shape 3020 over it, and the dialogue Label. The centre top is a fixed-size Control with the doll and the seven slots at SWF positions (2.8). The centre bottom is a VBoxContainer of the hint Label and the existing GridContainer.

### 4.4 Scenes with TextureRects at hardcoded offsets

[measured] Every TextureRect and TextureButton in position mode with typed offsets (`S/scan_textures.txt`):

| Scene | Nodes | Where the numbers come from |
|---|---|---|
| `scenes/battle/victory_screen.tscn` | Backdrop, LeftPanel, MiddlePanel | the backdrop is `MenuTheme.BACKDROP_RECT`, the panels are the `inventory` frame's rects, not `win`'s |
| `scenes/battle/victory_experience_row.tscn` | Face, ExpTrack, ExpFill | typed, with rows at 120 + 62n (`scripts/battle/victory_screen.gd:71-88`) |
| `scenes/ui/store/store_window.tscn` | Backdrop, CloseButton, LeftPanel, ShopBackdrop, MiddleTopPanel, MiddleBottomPanel | backdrop and close X from `MenuTheme`, panels within 15.85 px of the shop frame |
| `scenes/ui/inventory.tscn` | PanelBackground, BarBackground | the inventory frame, within 0.05 px, under `INVENTORY_AT` in three scripts |
| `scenes/ui/menu/inventory_window.tscn` | Backdrop, CloseButton, LeftPanel, ExpTrack, ExpFill, ExpZeroBox, CenterPanel, PartyBar | panels within 0.10 px of the inventory frame |
| `scenes/ui/menu/abilities_window.tscn` | Backdrop, CloseButton, LeftPanel, MiddleTopPanel, MiddleBottomPanel, RightPanel | panels within 33.43 px of the skills frame |
| `scenes/ui/menu/achievements_window.tscn` | Backdrop, CloseButton, PanelBackground | panel within 14.65 px of the ach frame |
| `scenes/ui/menu/talent_node.tscn` | IconRect | a 2 px inset inside a 32 px button |
| `scenes/ui/hotbar.tscn` | LeftPanel, MiddlePanel, RightPanel | hand-made art (`docs/superpowers/specs/2026-08-22-battle-screen-extraction-design.md:40`), one 1947 x 323 PNG stretched to 320 x 110 and 120 x 110 |
| `scenes/battle_scene.tscn` | BottomBar/Backdrop, Panel1, Panel2, Panel3, Panel3/CountdownRing | the hotbar's panels again over the older hand-made backdrop (`NEXT_PHASES.md:208-209`), the ring 20 px inside Panel3 |
| `scenes/main_menu.tscn` | ClassPicker/Psychological, Biological, Hydraulic | SWF placements printed by `extract_start_screens` (`scenes/main_menu.tscn:265-267`) |
| `scenes/zone_map.tscn` | Zones/Zone1 to Zone7 | hand-placed (`scripts/zones/zone_map.gd:2`) |
| `scenes/zones/zone1_prison.tscn` to `zone7_shotul.tscn` | HubArt | one rect, (18, 16) to (782, 430), in all seven |

[source] Placed from code instead of the scene: the stance rows and the battle sky from `battle_layout.json` (`scripts/battle/stance_row.gd:49-73`, `scripts/battle/battle_scene.gd:313`), the equip slots from each screen's `EQUIP_SLOT_CENTERS` (`scripts/ui/menu/equip_doll_view.gd:32`), the talent tree and wheel from typed SWF numbers (`scripts/ui/menu/abilities_window.gd:86`, `:106`), and the drop slots from `DROP_ORIGIN` (`scripts/battle/victory_screen.gd:94`).

[measured] Already anchored or contained, with no typed position: the game over and ending backgrounds, the tooltip icon, the item slot's icon and highlight, the hotbar's Glow and Icon, the ability pool row icon and the inventory window's portrait faces (`S/scan_textures.txt`, `S/scan_containers.txt`).

### 4.5 Panel rects against the SWF

[measured] Largest edge difference between each panel TextureRect and the KRINMENU placement it stands for (`S/panel_diffs.txt`):

| Scene | Node | SWF frame and depth | Largest edge difference |
|---|---|---|---|
| inventory_window | LeftPanel, CenterPanel, PartyBar | inventory 11, 21, 9 | 0.10 px |
| inventory | PanelBackground, BarBackground | inventory 7, 5 | 0.05 px |
| victory_screen | LeftPanel | win 11 | 54.50 px |
| victory_screen | MiddlePanel | win 21 | 34.10 px |
| store_window | LeftPanel | shop 11 | 13.22 px |
| store_window | MiddleTopPanel, MiddleBottomPanel | shop 21, 23 | 15.85 px |
| abilities_window | LeftPanel | skills 7 | 33.43 px |
| abilities_window | RightPanel | skills 5 | 30.57 px |
| abilities_window | MiddleTopPanel | skills 23 | 21.54 px |
| abilities_window | MiddleBottomPanel | skills 21 | 19.80 px |
| achievements_window | PanelBackground | ach 5 | 14.65 px |

[inferred] The two scenes that match are the two built on the unscaled `inventory` frame. Every frame that scales a panel was approximated by hand, which is the failure a layout read from the SWF prevents whether the scene uses containers or not.

## 5. Open questions and candidate tickets

1. Panel look. The menu panels are plain rectangles, so a StyleBoxFlat generated from the shape records and an extracted texture in a zero-margin StyleBoxTexture both reproduce fill and stroke. The worked example settled on extraction for 3309 (`docs/superpowers/specs/2026-08-23-battle-bottom-bar-and-stance-rows.md:232-234`). The map should say which one the spec uses for KRINMENU.
2. The panels' inner shadow is missing from the port today. A 1x nine-patch from an ffdec render, a shader or an ADR (3.8). [#109](https://github.com/julian-perge/urchin/issues/109)'s piece inventory should list it.
3. Fractional pitches. Accept whole-pixel rounding in BoxContainer, or write one small custom container that places children at float positions (3.6). #108's ffdec diff can measure the cost.
4. Where the SWF-derived menu rects live. The battle has `battle_layout.json`, written by `extract_battle_screen`. The menus have typed constants in `MenuTheme` and in each scene. A menu layout file written by an extractor would carry panel rects, content margins and pitches.
5. Candidate tickets from section 4: the victory screen's panels, rows, drop grid, XP bar width and Proceed backing (likely #108's prototype). The store's panels, picture size, slot scale and doll scale. The abilities and achievements panel rects. The hub hotbar and battle bottom bar art, which is hand-made and stretched into three panels.

## Appendix: scratch files

`S/` is `~/tmp/2026-11-09-godot-container-patterns/`.

- `krinmenu_stage.py`, `krinmenu_stage.txt`: where KRINMENU sits on the root timeline.
- `menu_frames.py`, `krinmenu_frames.txt`: KRINMENU's `win`, `shop` and `inventory` frames two levels deep, through `timeline.frames()`.
- `panel_rects.py`, `panel_rects.txt`: each panel's stage rect on each labeled frame.
- `panel_filters.py`, `panel_filters.txt`: every panel placement's DropShadow in the XML dump.
- `panel_edges.py`, `panel_edges.txt`: pixels along the port's panel PNGs.
- `panel_diffs.py`, `panel_diffs.txt`: port panel rects against the SWF's.
- `scan_tscn.py`, `scan_textures.txt`, `scan_containers.txt`: texture nodes and containers in every scene.
- `png_sizes.py`: PNG sizes from their headers.
- `docs/`: the Godot 4.7 doc pages and 4.7.2-stable source files read for this note.

The SWF scripts run with the worktree's package on the path, for example `uv run --project <urchin> python panel_rects.py <urchin>/sonny-2-2900.swf`.
