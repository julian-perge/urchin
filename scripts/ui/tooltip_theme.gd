# tooltip_theme.gd
# Shared tooltip palette, recovered from the original's own KrinToolTipper
# clip (DefineSprite 2717): two backer graphics (a black body, alpha
# 230/255, and a white-gray-white gradient used for a glossy header-style
# bar) recolored per section via additive ColorTransforms rather than
# separate art. Background colors below are each gradient's own recorded
# midpoint stop (170,170,170) with the same additive transform the source
# applies at that stop - not an arbitrary flat-color guess. Text colors are
# pixel-sampled from reference captures (the source's own TextFormat.color
# values are buried in undecompiled AS2 bytecode) - see
# docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md.
class_name TooltipTheme
extends RefCounted

const BG_HEADER: Color = Color(170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_COST: Color = Color(139.0 / 255.0, 164.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_BODY: Color = Color(0.0, 0.0, 0.0, 230.0 / 255.0)
const BG_NEXT_RANK: Color = Color(50.0 / 255.0, 40.0 / 255.0, 53.0 / 255.0, 230.0 / 255.0)

const TEXT_TITLE: Color = Color(0.08, 0.08, 0.08)
const TEXT_SUBHEADER: Color = Color(0.08, 0.08, 0.12)
const TEXT_BODY: Color = Color(0.96, 0.96, 0.96)
const TEXT_STAT: Color = Color(0.98, 0.78, 0.08)
const TEXT_FLAVOR: Color = Color(0.7, 0.98, 0.27)
