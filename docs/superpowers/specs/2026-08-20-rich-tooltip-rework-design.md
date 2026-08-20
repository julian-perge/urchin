# Rich Tooltip Rework Design

## Goal

Replace every tooltip in the game with a design that matches the original's
own layout: a title bar, an optional colored info bar, and a body of
independently-colored text lines - instead of the current mix of a plain
single-panel `AbilityTooltip` (abilities screen only) and Godot's bare
default `tooltip_text` popup (items, hotbar, battle-orb, buff-icon hovers).

## Background

A user investigation of the abilities screen and in-battle UI found:

- The abilities-screen tooltip (`AbilityTooltip`) renders as one flat panel
  with plain-colored text - no title bar, no colored info bar, nothing like
  the original.
- Every other tooltip in the game (`ItemSlot`, hotbar buttons, buff icons,
  and - before the companion battle-orb fix - the in-battle radial menu)
  uses Godot's built-in `tooltip_text`, which can only render one uniform
  box with one text color. It cannot reproduce the original's look at all.
- The battle-orb bugs found alongside this (missing description text,
  missing icon art, orbs shifting position under cooldown) were already
  fixed and committed separately (commit `3856129`). This spec covers
  what's left: the tooltip's visual rework.

### How the original builds a tooltip

The tooltip is `_root.KrinToolTipper` (`DefineSprite` id 2717, referenced
from `frame_181/DoAction_2.as` as `KrinToolTipper.inner.gotoAndStop(...)`).
It's AS2, and it isn't a set of hand-authored frames, one per item or
ability - it's a small runtime layout engine. An
`onClipEvent(enterFrame)` handler creates a `TextField` per line, sets its
`TextFormat` (font, size, color, bold, word wrap, auto-size), reads back
the field's own measured width and height, and resizes a shared "backer"
clip to match. Different frame labels (`GO`, `GO2`, `GO3`, `GO4`, `GO7`)
are different section layouts - more or fewer backer bars, recolored
per label.

Only two backer graphics exist, and every section reuses one of them via
an additive `ColorTransform` rather than separate art:

- **`fontBacker`/`fontBacker4`** (shape 68): flat black, alpha 230/255
  (~90% opaque) - the body.
- **`fontBacker2`/`fontBacker3`** (shape 2714): a gradient white -> gray
  -> white -> white (`255,255,255` -> `170,170,170` at ratio 60/255 ->
  `255,255,255` at ratio 177/255 -> `255,255,255`, alpha 217-255) - the
  glossy header look.

Confirmed color transforms applied to that white gradient at different
frame labels:

| Frame label | ADD(R, G, B) | Resulting look |
|---|---|---|
| `GO` (header) | none | white -> gray(170,170,170) -> white gloss |
| `GO2` (cost/type bar) | (-31, -6, 0) | steel-blue gloss, mid-tone (139,164,170) |
| `GO7` (next-rank header) | (-31, -6, 0), reused | same steel-blue gloss |
| `GO7` (next-rank body, separate `fontBacker4` instance) | (50, 40, 53) on black | dark plum body (50,40,53) |

Text colors are literal `TextFormat.color` values pushed inside raw AS2
bytecode that ffdec couldn't decompile to readable pseudocode for this
tag - decoding those by hand wasn't worth it for what pixel-sampling the
reference captures already gave cleanly (see below). This spec uses
source-derived colors for backgrounds and pixel-sampled colors for text.

### Colors, pixel-sampled from reference captures

Sampled by taking, for each row of a reference screenshot, the most common
color in a horizontal strip (cancels out sparse text pixels, since most of
each row is background) - then cross-checked against the source data above.
Both agreed.

| Element | Color (approx.) | Reference |
|---|---|---|
| Title text | near-black, bold | all references |
| Cost/type-line text | dark navy | `13_inbattle_after_player_click_on_hover_ability...png` |
| Body text (plain description) | near-white | same |
| Body text (stat bonus / next-rank preview) | gold (~`250,200,20`) | `references/.../zone1_itemshop...png`, user's "Vicious Strike" capture |
| Body text (item flavor line) | green (~`180,250,70`) | user's "A Broken Pipe" capture |

## Requirements

- A tooltip is a vertical stack of **sections**. Each section has its own
  background color and holds one or more **lines**, each with its own text
  color. This matches the source's own architecture (resizable backer bars
  per text field), just built with Godot containers instead of AS2's
  manual `_width`/`_height` measurement.
- One shared implementation, used everywhere a tooltip appears: item slots,
  hotbar buttons, the abilities screen (talent tree / action-bar wheel /
  ability pool), the in-battle radial menu's orbs, and buff icons.
- Section backgrounds are **flat colors**, not rendered gradients. Each
  flat color is the source gradient's own recorded midpoint stop (170,170,170
  for the neutral gloss, then the same additive transform applied to that
  midpoint for the tinted variants) - not an arbitrary guess, just a
  simplified (non-gradient) rendering of a real value. Godot's
  `StyleBoxFlat` has no built-in multi-stop gradient; reproducing the true
  gradient would need a `GradientTexture2D` per section variant for a
  cosmetic detail nobody asked for. If this reads as too flat once it's
  built, upgrading a specific section to a real gradient later is a small,
  isolated change.
- Positioning clamps to the viewport (nothing does this today - a tooltip
  near a screen edge can currently run off-screen). No edge-flip logic;
  simple axis clamping only.

## Architecture

### Data model

A tooltip is `Array[Dictionary]` sections; a section is:

```gdscript
{
	"bg_color": Color,
	"lines": Array[Dictionary],  # [{"text": String, "color": Color}, ...]
}
```

No `"style"` enum or section-type tag - `bg_color` alone fully determines
how a section looks, and callers pass whichever named constant fits (see
below). This keeps the data model - and the renderer that walks it - to
one shape, no branching on section "kind".

### `scripts/ui/tooltip_theme.gd` (new)

Holds the palette as named constants, so every caller reads real,
source-derived values instead of re-guessing colors per call site:

```gdscript
class_name TooltipTheme
extends RefCounted

const BG_HEADER: Color = Color(170.0/255, 170.0/255, 170.0/255, 217.0/255)
const BG_COST: Color = Color(139.0/255, 164.0/255, 170.0/255, 217.0/255)
const BG_BODY: Color = Color(0.0, 0.0, 0.0, 230.0/255)
const BG_NEXT_RANK: Color = Color(50.0/255, 40.0/255, 53.0/255, 230.0/255)

const TEXT_TITLE: Color = Color(0.08, 0.08, 0.08)
const TEXT_SUBHEADER: Color = Color(0.08, 0.08, 0.12)
const TEXT_BODY: Color = Color(0.96, 0.96, 0.96)
const TEXT_STAT: Color = Color(0.98, 0.78, 0.08)
const TEXT_FLAVOR: Color = Color(0.7, 0.98, 0.27)
```

### `scenes/ui/game_tooltip.tscn` + `scripts/ui/game_tooltip.gd` (new autoload: `GameTooltip`)

```
GameTooltip (CanvasLayer, layer = 100)
  Root (Control, mouse_filter = IGNORE, visible = false)
    HBox (HBoxContainer)
      IconBacking (ColorRect, custom_minimum_size 32x32, visible only with an icon)
        Icon (TextureRect)
      Sections (VBoxContainer, custom_minimum_size.x = 220)
        # one PanelContainer per section, built and cleared at runtime
```

Public API:

```gdscript
# icon/icon_color are optional - only the abilities screen uses them today.
func show_sections(sections: Array, anchor: Control, icon: Texture2D = null, icon_color: Color = Color.WHITE) -> void

func hide_tooltip() -> void
```

`show_sections()`: clears `Sections`' children, builds one `PanelContainer`
per input section (a `StyleBoxFlat` using the section's `bg_color`, a small
`MarginContainer`, then one word-wrapped `Label` per line, colored per
line), shows/hides `IconBacking` based on whether `icon` is non-null,
positions the root at `anchor.global_position + Vector2(anchor.size.x + 8,
0)`, clamps both axes so the tooltip's own rect stays inside the viewport,
then sets `Root.visible = true`.

`hide_tooltip()` sets `Root.visible = false`. Named `hide_tooltip`, not
`hide` - `hide()`/`show()` are `CanvasItem` built-ins already in scope on
this node and shadowing them would be confusing to call correctly.

Every caller below wires its own `mouse_entered`/`mouse_exited` (or
`mouse_exited` equivalent) to `GameTooltip.show_sections(...)` /
`GameTooltip.hide_tooltip()`. Nothing shows a tooltip automatically - same
as today.

### Per-call-site retrofit

**Abilities screen** (`scripts/ui/menu/abilities_window.gd`): its three
hover handlers (`_on_tree_node_hovered`, `_on_socket_hovered`,
`_on_pool_row_hovered`) stop calling `_tooltip.populate()` and instead call
`GameTooltip.show_sections(sections, button, icon, element_color)`, where
`sections` comes from a renamed `AbilityTooltipBuilder.build_sections()`
(replacing today's `build_fields()`, which returns a flat
`{title, description, cost, next_rank_text, element_color}` dict).
`build_sections()` returns:

- Header section (`BG_HEADER`, `TEXT_TITLE`): title.
- Cost section (`BG_COST`, `TEXT_SUBHEADER`): the move's cost line, or
  `"Passive"` for a passive node - skipped if the field would be empty
  (matches today's `next_rank_text.is_empty()`-style skip pattern).
- Body section (`BG_BODY`, `TEXT_BODY`): the description, if non-empty.
- Next-rank section (`BG_NEXT_RANK`, `TEXT_STAT`): the next-rank preview
  text, if non-empty.

Delete `scenes/ui/menu/ability_tooltip.tscn` and
`scripts/ui/menu/ability_tooltip.gd` - superseded by `GameTooltip`.
`ability_tooltip_builder.gd` stays (renamed method, same responsibility:
pure data, no scene dependency).

**Item slots** (`scripts/ui/store/item_slot.gd`): `_refresh()` stops
building `tooltip_text` and instead builds:

- Header section (`BG_HEADER`, `TEXT_TITLE`): `item.display_name`.
- Type section (`BG_HEADER`, `TEXT_SUBHEADER` - same neutral gloss as the
  header, the reference shows no blue tint here, only moves get that):
  `"Lvl. %d %s" % [item.required_level, item.slot_type_display_name()]`,
  skipped when `item.item_type == GameItem.ItemType.NONE`.
- Body section (`BG_BODY`), lines in the same order the old flat list
  used: the price line for catalog slots first (`TEXT_STAT` - no
  reference capture shows a priced tooltip, so this styling is a judgment
  call, flagged below), then one `TEXT_STAT` line per `item.tooltipAlt`
  entry (gold - matches the sampled "Strength +6" color), then
  `item.tooltip` (`TEXT_FLAVOR`, green) if non-empty.

Add `GameItem.slot_type_display_name() -> String`, a small `ItemType ->
String` map mirroring `scripts/editor/items.gd`'s existing (reversed)
`item_type_map` - `"Headwear"`, `"Bodywear"`, `"Gloves"`, `"Leggings"`,
`"Footwear"`, `"Primary Arms"`, `"Two-Handed Arms"`, `"Secondary Arms"`,
plus `"Tool"` for `TOOL` (not in that map; a reasonable guess, called out
below) and `""` for `NONE` (never shown, since the type section is
skipped).

**Hotbar** (`scripts/ui/hotbar.gd` / `hotbar.tscn`): drop the
scene-authored `tooltip_text` properties on each button. Add a
`TOOLTIP_CAPTIONS: Dictionary[String, Array]` (button name -> `[title,
body_text]`) and wire `mouse_entered`/`mouse_exited` inside the existing
`_setup_icon_glow()` loop (which already iterates every hover-enabled
button) to build a 2-section tooltip: header section (`BG_HEADER`,
`TEXT_TITLE`) + one body section (`BG_BODY`, `TEXT_BODY`) line.

**Battle orbs** (`scripts/battle/battle_scene.gd`): the Phase-A fix left
`orb.tooltip_text = _move_tooltip(move)` in place. Replace it: connect
`orb.mouse_entered`/`mouse_exited` to build/show/hide sections - header
section (`BG_HEADER`, `TEXT_TITLE`, the move name), cost section
(`BG_COST`, `TEXT_SUBHEADER`), body section (`BG_BODY`, `TEXT_BODY` for
the description, plus the cooldown line as a second `TEXT_BODY` line when
`cooldown_turns > 0`). Delete `_move_tooltip()`, now unused.

**Buff icons** (`scripts/battle/unit_overlay.gd`): `refresh_buffs()`'s
`icon_rect.tooltip_text = "%s (%d turns)\n%s" % [...]` becomes the same
`mouse_entered`/`mouse_exited` wiring - header section (`BG_HEADER`,
`TEXT_TITLE`, buff name + turns remaining), body section (`BG_BODY`,
`TEXT_BODY`, the buff's `tooltip_description`). Included for visual
consistency (every other tooltip in the game will look like this after
this rework) even though it wasn't one of the originally reported bugs.

### Positioning and clamping

`_position_near(anchor)`: start at `anchor.global_position +
Vector2(anchor.size.x + 8, 0)`, then clamp `x` to `[0, viewport_width -
tooltip_width]` and `y` to `[0, viewport_height - tooltip_height]`. No
edge-flip - if the clamped position visually overlaps the anchor near a
corner, that's an accepted simplification (see Requirements).

## Testing

No pytest suite exists in this repo - all of the following are GUT tests
(`test/unit/`, `test/integration/`).

- `test_game_tooltip.gd` (new): `show_sections()` builds one
  `PanelContainer` per section with the right `bg_color` and per-line text
  and color; an icon section shows/hides correctly; `hide_tooltip()` hides
  the root; positioning clamps at each viewport edge (four cases: top,
  bottom, left, right).
- `test_ability_tooltip_builder.gd`: update for `build_sections()`'s
  section-list shape (the existing rank/passive/pool-row cases carry over,
  asserting on section contents instead of flat fields).
- `test_game_item.gd` (or wherever `GameItem` is covered): new coverage for
  `slot_type_display_name()` across every `ItemType`.
- `item_slot.gd`, `hotbar.gd`, `battle_scene.gd`, `unit_overlay.gd`: update
  their existing tests to assert against `GameTooltip`'s last-shown
  sections (an autoload the tests can read directly) instead of
  `tooltip_text`.
- Every test that shows a tooltip must call `GameTooltip.hide_tooltip()`
  in teardown (or the equivalent existing `GameData.current_save = null`
  -style reset block) - it's an autoload, so it persists across tests in
  the same run.

## Out of Scope

- **World-map orbs** (`fight_orb.gd`, `store_orb.gd`, `training_orb.gd`,
  and the broken, already-dead `orb_tooltip.gd`/`.tscn`): same plain
  `tooltip_text` pattern, a different subsystem (zone hub screens, not
  abilities/battle). Not part of what was reported; a separate pass if
  wanted later.
- **The inventory sell-button drag preview**
  (`inventory_panel.gd`'s `sell_button.tooltip_text`): a single-line,
  transient drag-feedback string with its own direct test coverage
  (`test_inventory_panel.gd`). Converting it would mean rewriting those
  tests for a UI element nobody reported as broken.
- **True rendered gradients** for section backgrounds - see Requirements.
- **Edge-flip positioning** - see Requirements.

## Open assumptions (flagged for review, not silently decided)

1. **Item price line styling**: no reference capture shows a store item's
   priced tooltip. Styled as a gold body line, same as a stat bonus. Easy
   to change once someone has a real reference.
2. **`ItemType.TOOL`'s display name** (`"Tool"`): not in
   `scripts/editor/items.gd`'s existing type map; a reasonable guess, not
   a verified source value.
3. **Buff-icon tooltips included** for visual consistency, though not one
   of the originally reported bugs - see Per-call-site retrofit above.
