# ability_tooltip.gd
# The rich floating ability tooltip (KRINTOOLTIPPER-style), shown by
# abilities_window.gd on hover over a talent-tree node, pool row, or wheel
# socket. Hidden by default; the caller shows/hides and positions it.
extends PanelContainer
class_name AbilityTooltip

const ICON_DIR: String = "res://assets/ui/abilities/"

@onready var _icon_backing: ColorRect = $Margin/HBox/IconBacking
@onready var _icon: TextureRect = $Margin/HBox/IconBacking/Icon
@onready var _title_label: Label = $Margin/HBox/VBox/TitleLabel
@onready var _desc_label: Label = $Margin/HBox/VBox/DescLabel
@onready var _cost_label: Label = $Margin/HBox/VBox/CostLabel
@onready var _next_rank_label: Label = $Margin/HBox/VBox/NextRankLabel


# icon_key: the sanitized label to load from assets/ui/abilities/ (move
# display_name for actives, buff family name for passives) - callers build
# this with the same sanitize() transform the extraction script used.
func populate(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff, icon_key: String) -> void:
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, move, buff)
	_title_label.text = fields["title"]
	_desc_label.text = fields["description"]
	_desc_label.visible = not fields["description"].is_empty()
	_cost_label.text = fields["cost"]
	_next_rank_label.text = fields["next_rank_text"]
	_next_rank_label.visible = not fields["next_rank_text"].is_empty()
	_icon_backing.color = fields["element_color"]
	var icon_path: String = "%s%s.png" % [ICON_DIR, icon_key]
	_icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
