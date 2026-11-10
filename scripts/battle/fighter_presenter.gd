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
# LifeBarSmoother starts at the death, and its frame 18 clears the overlay 17
# frames later (DefineSprite_57_LifeBarSmoother/frame_18/DoAction.as). From the
# next frame on, its frame 38 takes this much off the bar's alpha, out of 100,
# every frame, and hides the bar on the frame after the alpha reaches 0
# (DefineSprite_57_LifeBarSmoother/frame_38/DoAction.as).
const DEATH_CLEAR_FRAME: int = 17
const DEATH_FADE_PER_FRAME: int = 5

# Health and stun as displayed. The runner pre-applies a whole half-turn before
# the replay starts, so the bars and the stun pose follow these numbers instead
# of the unit's own, and only show_result(), snap_to_unit() and die() change
# them.
var displayed_hp: float = 0.0
var displayed_stun: float = 0.0

var _unit: CombatUnit
var _buffs_by_id: Dictionary = {}
var _float_layer: Node2D
var _dead: bool = false
var _frames_since_death: float = 0.0
var _ring_fade: Tween = null
var _hover_info: Label = null
# setup() puts the doll this far from its home, and rig_position() takes it
# back off.
var _doll_offset: Vector2 = Vector2.ZERO

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
	displayed_stun = unit.stun
	_doll.position = home
	if unit.team_side == CombatUnit.Team.TWO:
		_doll.scale.x = -1  # mirrored, facing left
	# dressChar's MODEL5 quirk: 0.8x scale, 10px lower.
	if not unit.model.is_empty() and str(unit.model[0]) == "MODEL5":
		_doll.scale *= 0.8
		_doll.position.y += 10
	_doll_offset = _doll.position - home
	_doll.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, items_by_id))
	# The overlay is the doll's sibling because parenting it to a mirrored doll
	# flipped its offsets on team 2.
	_overlay.position = _doll.position
	_overlay.setup(unit.player_name)
	_overlay.ring.draw.connect(_draw_ring)
	redraw()


# Shows one move's result at the moment it lands on this fighter: the number,
# then the death or flinch, then the voice, then the bar and the stun pose. Every
# result but a miss moves the bar and the stun pose to the life and stun it
# states, because the original recomputes and redraws its target after every
# strike that lands (the conductor, line 103) and runs nothing on a miss. The
# life a result states already holds any life cost or damage-over-time tick the
# unit took earlier in the half-turn. The original drew those when they
# happened, and here they reach the bar with the next result on the unit.
func show_result(result: MoveResult, move: Ability) -> void:
	var amount: float = result.amount
	var critical: bool = result.critical
	match result.kind:
		MoveResult.Kind.DAMAGE when result.direction == MoveResult.Direction.HEAL:
			# Under sswitch this damage healed the target. The original draws its
			# number in heal green and plays no hit animation or hit voice
			# (frame_42/DoAction_8.as:133-149).
			float_text(str(int(amount)), MenuTheme.HEAL_COLOR, critical)
		MoveResult.Kind.DAMAGE:
			# KrinNumberShow: numbers colored by the move's ELEMENT; crits
			# play the bigger "critical" variant of the same color.
			float_text(str(int(amount)), _damage_color(move), critical)
			_die_or_flinch(result)
			# The original plays the hit voice only when the target survives, and
			# plays it on a stunned target too (frame_42/DoAction_8.as:104-131).
			if not result.killed:
				voice_cue.emit(_unit.voice_hit)
		MoveResult.Kind.HEAL when result.direction == MoveResult.Direction.HARM:
			# Under sswitch this heal hurt the target. The original draws its
			# number in the Shadow color, plays the hit animation unless the
			# target is stunned, plays no hit voice, and plays the death at the
			# impact when the heal kills (frame_42/DoAction_8.as:189-229).
			float_text(str(int(amount)), MenuTheme.ELEMENT_COLORS[CombatUnit.Element.SHADOW], critical)
			_die_or_flinch(result)
		MoveResult.Kind.HEAL:
			float_text("+%d" % int(amount), MenuTheme.HEAL_COLOR)
		MoveResult.Kind.FOCUS:
			float_text("+%d FOCUS" % int(amount), Color.SKY_BLUE)
		MoveResult.Kind.MISS:
			# The special miss frame KrinNumberShow swaps to at impact,
			# instead of a damage number - the caster's own animation still
			# played in full to get here (see _execute_move_action's comment).
			# battle_scene.gd plays the miss sound, because the move's type
			# decides it.
			float_text("MISS", Color.GRAY)
	if result.kind != MoveResult.Kind.MISS:
		displayed_hp = result.life_after
		_show_stun(result.stun_after)
	redraw()


func _damage_color(move: Ability) -> Color:
	if move == null or move.damage_element_type == -1:
		return Color.WHITE
	return MenuTheme.ELEMENT_COLORS[move.damage_element_type]


func _die_or_flinch(result: MoveResult) -> void:
	if result.killed:
		# The death plays at the impact that actually kills, because the queued
		# DEATH event only reaches the replay after the caster's whole move,
		# melee runback included, has finished.
		die()
	elif not result.target_stunned:
		# The original skips the hit animation on a target that is stunned when
		# the hit lands (frame_42/DoAction_8.as:100-103 and 204-207).
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


# Plays the death: the doll's dead label, an empty bar, the death voice, and the
# overlay's clear and fade, which _process() counts out. The original's
# lifeBarUpdate plays the voice and starts the fade only when the bar's rounded
# percent changes (frame_42/DoAction_8.as:295-298 and 345-347), which skips a
# unit killed from under 0.5% life. ADR 0005 counts that as an Original bug, so
# every death plays them here.
func die() -> void:
	_dead = true
	_doll.set_state(CharacterVisual.State.DEAD)
	displayed_hp = 0.0
	redraw()
	effect_cue.emit(_unit.voice_die)


# Counts the frames since the death, so the overlay clears, fades and hides on
# the original's frames. The count is in frames rather than seconds, because a
# sum of 1/30 s steps drifts off whole frames.
func _process(delta: float) -> void:
	if not _dead:
		return
	_frames_since_death += delta * BattleScreenClip.fps()
	var frames_since_clear: int = int(_frames_since_death) - DEATH_CLEAR_FRAME
	if frames_since_clear < 0:
		return
	_overlay.clear_for_death()
	var alpha_percent: int = 100 - DEATH_FADE_PER_FRAME * frames_since_clear
	_overlay.modulate.a = maxi(alpha_percent, 0) / 100.0
	if alpha_percent < 0:
		_overlay.hide()
		set_process(false)


# Draws the displayed health and the unit's true focus and buffs. It never moves
# the health bar toward the unit's real life, and never changes the stun pose.
func redraw() -> void:
	_overlay.show_status(_unit, displayed_hp, _buffs_by_id)


# For the half-turn's end, which is where a damage-over-time tick, a buff that
# wears off or a life cost with no later result on the unit reaches the bar and
# the stun pose.
func snap_to_unit() -> void:
	displayed_hp = _unit.life_n
	_show_stun(_unit.stun)
	redraw()


# A unit's stun is a running total over every stun buff it holds. Any rise
# replays the "stun" label, even on a doll that is already stunned, and any fall
# plays "outofstun", even one that leaves it stunned by a shorter buff, the way
# applyChangesKrin compares STUN with its last value (see DECODED_ALGORITHMS.md).
# The original changes no dead unit's stun pose, so a dead doll keeps its death.
func _show_stun(stun: float) -> void:
	if not _dead:
		if stun > displayed_stun:
			_doll.enter_stun()
		elif stun < displayed_stun:
			_doll.exit_stun()
	displayed_stun = stun


# battle_scene.gd passes true only while the mouse is over the fighter during a
# Decision, so the ring fades in only then and fades out on any other call. A
# dead fighter ignores this.
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


# Starts the caster's melee swing at `target` and returns at its Impact, once
# on_impact has run. The doll runs toward where the target's rig stands on each
# frame, and stops short of where it stood as the swing started by half of each
# fighter's width. The doll's Runback then takes it home on its own while the
# battle goes on. With wait false nothing waits for the swing, so on_impact runs
# at once. If the presenter leaves the tree during the swing, on_impact doesn't
# run.
func melee(target: FighterPresenter, label: String, on_impact: Callable, wait: bool = true) -> void:
	_doll.play_melee(_doll_spot_on.bind(target), target.rig_size().x / 2.0, label)
	if wait:
		await _doll.attack_connected
		if not is_inside_tree():
			return
	on_impact.call()


# Returns where this fighter's doll would stand if its rig stood where `other`'s
# rig stands now, in this presenter's space. krinMelee runs the caster's rig toward
# the target's rig, so a MODEL5 doll's 10 px drop inside its rig doesn't tilt
# the run.
func _doll_spot_on(other: FighterPresenter) -> Vector2:
	return other.rig_position() - position + _doll_offset


func cast(move: Ability) -> void:
	_doll.set_state(CharacterVisual.State.CAST)
	# The real colortobe glow tint (frame217/onClipEvent(enterFrame).as:
	# 417,450) - the move's own color, not an element-color
	# approximation. set_state() resets modulate back to white when the
	# cast label finishes.
	_doll.modulate = move.visual_effect_color.lerp(Color.WHITE, 0.4)


# Returns where the original's rig stands, the clip that dressChar puts the doll
# in. That is the doll's own spot but for the 10 px that dressChar moves a
# MODEL5 doll down inside its rig (frame_217/DoAction_2.as:19-24).
func rig_position() -> Vector2:
	return position + _doll.position - _doll_offset


# Returns the rig's _width and _height, which is the size of the box around
# everything its doll draws right now.
func rig_size() -> Vector2:
	return _doll.get_bounds().size
