# tooltip_theme.gd
# Shared tooltip look, recovered from the original's own KrinToolTipper clip
# (DefineSprite 2717): two backer graphics (a black body, alpha 230/255, and
# a white-gray-white gradient used for a glossy header-style bar) recolored
# per section via additive ColorTransforms rather than separate art.
# Background colors below are each gradient's own recorded midpoint stop
# (170,170,170) with the same additive transform the source applies at that
# stop - not an arbitrary flat-color guess - see
# docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md. Text sizes,
# colors and widths are the TextFormat and createTextField values the clip's
# frame scripts give each text field they build.
class_name TooltipTheme
extends RefCounted

const BG_HEADER: Color = Color(170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_COST: Color = Color(139.0 / 255.0, 164.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_BODY: Color = Color(0.0, 0.0, 0.0, 230.0 / 255.0)
const BG_NEXT_RANK: Color = Color(50.0 / 255.0, 40.0 / 255.0, 53.0 / 255.0, 230.0 / 255.0)

# Every field the clip builds is 12 px (DefineSprite_2717/frame_4/DoAction.as:43).
const FONT_SIZE: int = 12

# The title is black in every layout (frame_4/DoAction.as:60). An ability's
# cost line is 0x000033, its description white and its next tier 0xFFCC00
# (frame_17/DoAction.as:30, 47 and 71). An item's level line is 0x333333, its
# stat lines 0xF8D754 and its flavor text 0xB8FE4E (frame_13/DoAction.as:34,
# 58 and 77).
const TEXT_TITLE: Color = Color("000000")
const TEXT_SUBHEADER: Color = Color("000033")
const TEXT_BODY: Color = Color("ffffff")
const TEXT_NEXT_RANK: Color = Color("ffcc00")
const TEXT_REQUIREMENT: Color = Color("333333")
const TEXT_STAT: Color = Color("f8d754")
const TEXT_FLAVOR: Color = Color("b8fe4e")

# The clip builds every field of a layout at one width: 170 px for a plain
# tooltip (frame_4/DoAction.as:33), 150 for an ability
# (frame_17/DoAction.as:21) and 200 for an item (frame_13/DoAction.as:25),
# and Flash keeps a 2 px gutter on each side of the text. Each width below is
# that field width less both gutters, plus the 3.34 px of one 12 px space,
# because Godot counts the space after a line's last word when it wraps and the
# reference captures wrap as if Flash does not. The sum is rounded down to a
# whole pixel, because a Label only wraps at whole pixels and GameTooltip's
# containers would round a fraction up. Measured over the 3596 different
# tooltip fields the port can show, 3562 then wrap onto as many lines as a wrap
# that ignores trailing spaces at the field's own width less both gutters, and
# the other 34 are one line off.
const TEXT_WIDTH_PLAIN: float = 169.0
const TEXT_WIDTH_ABILITY: float = 149.0
const TEXT_WIDTH_ITEM: float = 199.0
