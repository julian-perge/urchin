# ability_pool_row.gd
# One row of the ability pool list (icon + move name). abilities_window.gd
# instances 5 of these into the PoolRows VBoxContainer and calls populate()/
# clear() as the visible window scrolls - the row itself has no move_id
# state, the parent tracks that via its own _pool_move_ids/_pool_scroll.
extends Button
class_name AbilityPoolRow

@onready var icon_rect: TextureRect = $HBox/IconRect
@onready var name_label: Label = $HBox/NameLabel


func populate(move: Ability, icon_path: String, icon_tint: Color = Color.WHITE) -> void:
	visible = true
	name_label.text = move.display_name if move != null else ""
	icon_rect.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
	icon_rect.material = IconTint.material(icon_tint)


func clear() -> void:
	visible = false
	name_label.text = ""
	icon_rect.texture = null
	icon_rect.material = null
