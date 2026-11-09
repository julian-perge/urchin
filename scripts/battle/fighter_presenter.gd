# fighter_presenter.gd
# Everything one fighter shows on the Battle screen: its doll, its bars, the
# health those bars display, its hover ring, its floating numbers, its stun and
# its death. battle_scene.gd keeps one per slot and tells it when a hit lands,
# when to snap to the unit, when it is hovered during a Decision and when it
# dies.
#
# Nothing here reads an autoload, so a test can build one from a hand-made
# CombatUnit. The scene passes the item and buff tables to setup() and connects
# voice_cue and effect_cue to the audio manager.
extends Node2D
class_name FighterPresenter

signal voice_cue(cues: Array)
signal effect_cue(cue: String)

enum Relation { PLAYER, ALLY, ENEMY }

const RING_COLORS: Dictionary[Relation, Color] = {
	Relation.PLAYER: Color(0.85, 0.85, 0.85),
	Relation.ALLY: Color(0.35, 0.9, 0.25),
	Relation.ENEMY: Color(0.95, 0.25, 0.15),
}
# Source-verified (frame_217/PlaceObject3_3394_450 and 5 sibling files):
# the hover ring fades in at +20/frame and out at -5/frame at the
# original's 30fps - a ~4x faster fade-in than fade-out.
const RING_FADE_IN_TIME: float = 0.17
const RING_FADE_OUT_TIME: float = 0.67
const FLOAT_OFFSET: Vector2 = Vector2(-15, -72)

# Health as displayed. The runner pre-applies a whole half-turn's damage before
# the replay starts, so the bars follow this number instead of the unit's life,
# and only show_result() and snap_to_unit() change it.
var displayed_hp: float = 0.0

var _unit: CombatUnit
var _buffs_by_id: Dictionary = {}
var _float_layer: Node2D
var _last_stun: float = 0.0
var _ring_fade: Tween = null
var _hover_info: Label = null

@onready var hit_area: Button = $Overlay/HitButton
@onready var _doll: CharacterVisual = $Doll
@onready var _overlay: UnitOverlay = $Overlay


# Call once, after the presenter is in the tree. It leaves the fighter drawn.
# Floating numbers go on float_layer rather than on this node because they have
# to draw over every fighter, and a fighter later in the tree would cover a
# number parented here.
func setup(unit: CombatUnit, home: Vector2, items_by_id: Dictionary, buffs_by_id: Dictionary, float_layer: Node2D) -> void:
	_unit = unit
	_buffs_by_id = buffs_by_id
	_float_layer = float_layer
	displayed_hp = unit.life_n
	_last_stun = unit.stun
	_doll.position = home
	if unit.team_side == CombatUnit.Team.TWO:
		_doll.scale.x = -1  # mirrored, facing left
	# dressChar's MODEL5 quirk: 0.8x scale, 10px lower.
	if not unit.model.is_empty() and str(unit.model[0]) == "MODEL5":
		_doll.scale *= 0.8
		_doll.position.y += 10
	_doll.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, items_by_id))
	# The overlay is the doll's sibling because parenting it to a mirrored doll
	# flipped its offsets on team 2.
	_overlay.position = _doll.position
	_overlay.setup(unit.player_name)
	_overlay.ring.draw.connect(_draw_ring)
	redraw()


# Shows one move's result at the moment it lands on this fighter: the number,
# then the bar, then the death or flinch, then the voice.
func show_result(result: Dictionary, move: Ability) -> void:
	var amount: float = float(result.get("amount", 0))
	var critical: bool = result.get("did_crit", false)
	match result.get("type"):
		BattleManager.ResultType.DAMAGE when result.get("sswitched", false):
			# Under sswitch this damage healed the target. The original draws its
			# number in heal green and plays no hit animation or hit voice
			# (frame_42/DoAction_8.as:133-149).
			float_text(str(int(amount)), MenuTheme.HEAL_COLOR, critical)
			displayed_hp = minf(displayed_hp + amount, _unit.life_u)
		BattleManager.ResultType.DAMAGE:
			# KrinNumberShow: numbers colored by the move's ELEMENT; crits
			# play the bigger "critical" variant of the same color.
			float_text(str(int(amount)), _damage_color(move), critical)
			displayed_hp = maxf(displayed_hp - amount, 0.0)
			_die_or_flinch(result)
			voice_cue.emit(_unit.voice_hit)
		BattleManager.ResultType.HEAL when result.get("sswitched", false):
			# Under sswitch this heal hurt the target. The original draws its
			# number in the Shadow color, plays the hit animation unless the
			# target is stunned, plays no hit voice, and plays the death at the
			# impact when the heal kills (frame_42/DoAction_8.as:189-229).
			float_text(str(int(amount)), MenuTheme.ELEMENT_COLORS[CombatUnit.Element.SHADOW], critical)
			displayed_hp = maxf(displayed_hp - amount, 0.0)
			_die_or_flinch(result)
		BattleManager.ResultType.HEAL:
			float_text("+%d" % int(amount), MenuTheme.HEAL_COLOR)
			displayed_hp = minf(displayed_hp + amount, _unit.life_u)
		BattleManager.ResultType.FOCUS:
			float_text("+%d FOCUS" % int(amount), Color.SKY_BLUE)
		BattleManager.ResultType.MISS:
			# The special miss frame KrinNumberShow swaps to at impact,
			# instead of a damage number - the caster's own animation still
			# played in full to get here (see _execute_move_action's comment).
			float_text("MISS", Color.GRAY)
			effect_cue.emit("sfx_magicmiss")
	redraw()


func _damage_color(move: Ability) -> Color:
	if move == null or move.damage_element_type == -1:
		return Color.WHITE
	return MenuTheme.ELEMENT_COLORS[move.damage_element_type]


func _die_or_flinch(result: Dictionary) -> void:
	if result.get("target_died", false):
		# The death plays at the impact that actually kills, because the queued
		# DEATH event only reaches the replay after the caster's whole move,
		# melee runback included, has finished.
		die()
	elif _unit.stun == 0:
		# The original skips the hit animation on a stunned target
		# (frame_42/DoAction_8.as:101-104).
		_doll.set_state(CharacterVisual.State.HIT)


func float_text(text: String, color: Color, critical: bool = false) -> void:
	var label: Label = Label.new()
	label.text = text
	# The original draws these numbers with the digit shapes of its
	# NumberSetter clip (frame_42/DoAction_7.as), not in a font, so they use
	# RegularLabel and keep the regular face instead of the project theme's
	# bold default.
	label.theme_type_variation = &"RegularLabel"
	label.modulate = color
	label.position = _doll.position + FLOAT_OFFSET
	label.scale = Vector2.ONE
	if critical:
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 4)
	_float_layer.add_child(label)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func die() -> void:
	_doll.set_state(CharacterVisual.State.DEAD)
	_overlay.visible = false
	effect_cue.emit(_unit.voice_die)


# Draws the displayed health and the unit's true focus and buffs, and plays any
# change in its stun. It never moves the health bar toward the unit's real life.
func redraw() -> void:
	_overlay.show_status(_unit, displayed_hp, _buffs_by_id)
	_play_stun_change()


# For the half-turn's end, which is where damage-over-time ticks, life costs and
# shields reach the bar, since no hit shows them.
func snap_to_unit() -> void:
	displayed_hp = _unit.life_n
	redraw()


# krinBuff STUN is a running total across active stun-inflicting buffs -
# replay "stun" on any increase (including stacking while already stunned),
# "outofstun" on any decrease (even a partial one that leaves the unit still
# stunned by a shorter-lived buff); both labels flow back to idle/stun2 on
# their own once triggered (see DECODED_ALGORITHMS.md).
func _play_stun_change() -> void:
	var current: float = _unit.stun if _unit.active else 0.0
	if current > _last_stun:
		_doll.enter_stun()
	elif current < _last_stun:
		_doll.exit_stun()
	_last_stun = current


# battle_scene.gd passes true only while the mouse is over the fighter during a
# Decision, so the ring fades in only then and fades out on any other call. A
# dead fighter ignores this, because its overlay is already hidden.
func show_hover(showing: bool) -> void:
	if not _unit.active:
		return
	var ring: Control = _overlay.ring
	ring.queue_redraw()
	if _ring_fade != null:
		_ring_fade.kill()
	_ring_fade = create_tween()
	_ring_fade.tween_property(ring, "modulate:a", 1.0 if showing else 0.0, RING_FADE_IN_TIME if showing else RING_FADE_OUT_TIME)
	if _hover_info != null:
		_hover_info.queue_free()
		_hover_info = null
	if showing:
		_hover_info = Label.new()
		_hover_info.text = "Lvl. %d" % _unit.plevel
		_hover_info.position = Vector2(-40, -8)
		_hover_info.size = Vector2(80, 16)
		_hover_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hover_info.add_theme_font_size_override("font_size", 11)
		_hover_info.add_theme_color_override("font_color", RING_COLORS[_relation_to_player()])
		_hover_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(_hover_info)


# The original's target ring: a thick circle with four tick marks.
func _draw_ring() -> void:
	var ring: Control = _overlay.ring
	var color: Color = RING_COLORS[_relation_to_player()]
	ring.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(color, 0.55), 7.0, true)
	ring.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 48, Color(color, 0.25), 3.0, true)
	for k in 4:
		var angle: float = k * TAU / 4.0
		ring.draw_line(
			Vector2.from_angle(angle) * 26.0, Vector2.from_angle(angle) * 44.0,
			Color(color, 0.7), 3.0, true
		)


func _relation_to_player() -> Relation:
	if _unit.player_id == BattleRunner.PLAYER_SLOT:
		return Relation.PLAYER
	return Relation.ALLY if _unit.team_side == CombatUnit.Team.ONE else Relation.ENEMY


# Runs the caster's melee swing to offset and back, and returns once the doll is
# home. on_blow runs once, at the blow. If the swing ends without one, as an
# interrupted swing does, it runs then and this returns true. With wait false
# nothing waits for the swing, so on_blow runs at once. If the presenter leaves
# the tree during the swing, on_blow doesn't run.
func melee(offset: Vector2, label: String, on_blow: Callable, wait: bool = true) -> bool:
	_doll.attack_connected.connect(on_blow, CONNECT_ONE_SHOT)
	_doll.play_melee(offset, label)
	if wait:
		await _doll.melee_finished
		if not is_inside_tree():
			return false
	if _doll.attack_connected.is_connected(on_blow):
		_doll.attack_connected.disconnect(on_blow)
		on_blow.call()
		return true
	return false


func cast(move: Ability) -> void:
	_doll.set_state(CharacterVisual.State.CAST)
	# The real colortobe glow tint (frame217/onClipEvent(enterFrame).as:
	# 417,450) - the move's own color, not an element-color
	# approximation. set_state() resets modulate back to white when the
	# cast label finishes.
	_doll.modulate = move.visual_effect_color.lerp(Color.WHITE, 0.4)
