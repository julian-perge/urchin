# ability_tooltip_builder.gd
# Pure data builder for the abilities screen's rich tooltip (talent tree
# node / action-bar wheel socket / ability pool row hover). No Node/scene
# dependency on purpose - abilities_window.gd consumes build_sections()'s
# output directly; GUT tests target this directly.
class_name AbilityTooltipBuilder
extends RefCounted


# node: a TalentTree node dict, or {} for a pool-row/wheel-socket hover
#   (no rank progress to show - no next-rank section in that case).
# save: used to read the node's current rank (ignored when node is {}).
# move: the resolved Ability for this hover - for a TREE node hover, the
#   CALLER must resolve the rank-specific move id first (see
#   TalentTree.granted_move_id()) - this builder does not do that
#   resolution itself, it only formats whatever move it's given.
# buff: the resolved Buff for a passive node hover, or null for an active
#   node / pool row / wheel socket hover.
# Returns {"sections": Array, "icon_color": Color} - icon_color is kept
# separate from the section list since the icon isn't itself a section.
static func build_sections(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff) -> Dictionary:
	var is_passive: bool = not node.is_empty() and TalentTree.is_passive(node)
	var title: String
	var description: String
	var cost: String
	if is_passive:
		title = str(node["buff_family"]).capitalize()
		description = buff.tooltip_description if buff != null else ""
		cost = "Passive"
	else:
		title = move.display_name if move != null else "?"
		description = move.tooltip_description if move != null else ""
		cost = move.tooltip_cost if move != null else ""
	var next_rank_text: String = ""
	if not node.is_empty():
		var rank: int = TalentTree.get_rank(save, node.get("_node_index", -1)) if save != null else 0
		var max_rank: int = int(node.get("max_rank", 0))
		if rank >= max_rank:
			next_rank_text = "MAX"
		else:
			next_rank_text = "Next Tier (Lvl. %d)" % TalentTree.required_level(node, rank)
	var element_index: CombatUnit.Element = -1
	if not is_passive and move != null:
		element_index = move.damage_element_type
	var element_color: Color = MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.6, 0.6, 0.4)

	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": title, "color": TooltipTheme.TEXT_TITLE}]},
	]
	if not cost.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_COST, "lines": [{"text": cost, "color": TooltipTheme.TEXT_SUBHEADER}]})
	if not description.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": description, "color": TooltipTheme.TEXT_BODY}]})
	if not next_rank_text.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_NEXT_RANK, "lines": [{"text": next_rank_text, "color": TooltipTheme.TEXT_STAT}]})
	return {"sections": sections, "icon_color": element_color}
