# fighter_presenter.gd
# Everything one fighter shows on the Battle screen: its doll, its bars, its
# buff icons, its hover ring, its Floating numbers, its Result flash, its Shield
# clip, its stun and its death.
# battle_scene.gd keeps one per slot and tells it when its move starts, when a
# hit lands, when its Buff tick comes due, when to snap to the unit, when it is
# hovered during a Decision and when it dies.
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
# LifeBarSmoother starts at the death, and its frame 18 clears the overlay 17
# frames later (DefineSprite_57_LifeBarSmoother/frame_18/DoAction.as). From the
# next frame on, its frame 38 takes this much off the bar's alpha, out of 100,
# every frame, and hides the bar on the frame after the alpha reaches 0
# (DefineSprite_57_LifeBarSmoother/frame_38/DoAction.as).
const DEATH_CLEAR_FRAME: int = 17
const DEATH_FADE_PER_FRAME: int = 5

# What the fighter shows: the life, Focus, stun and buff slots that the last
# event shown on it left on its unit. The runner resolves a whole half-turn
# before the replay starts, so the bars, the stun pose and the buff icons follow
# this instead of the unit, and only show_state(), show_result(), show_tick(),
# snap_to_unit() and die() change it.
var displayed: UnitSnapshot

var _unit: CombatUnit
var _buffs_by_id: Dictionary = {}
var _floating_numbers: FloatingNumberLayer
# Where the original's rig, the unit's clip on BATTLESCREEN, stands. dressChar
# lowers only the doll inside it for a MODEL5 unit (frame_217/DoAction_2.as:19-24),
# so the rig and every Floating number on the unit stay here.
var _home: Vector2
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
@onready var _flash: ResultFlash = $ResultFlash
@onready var _shield_clip: RigClip = $ShieldClip


# Call once, after the presenter is in the tree. It leaves the fighter drawn.
# Floating numbers go on the battle's one FloatingNumberLayer rather than on this
# node, because they have to draw over every fighter, and a fighter later in the
# tree would cover a number parented here.
func setup(unit: CombatUnit, home: Vector2, items_by_id: Dictionary, buffs_by_id: Dictionary, floating_numbers: FloatingNumberLayer) -> void:
	_unit = unit
	_buffs_by_id = buffs_by_id
	_floating_numbers = floating_numbers
	_home = home
	displayed = UnitSnapshot.of(unit)
	_doll.position = home
	# The Shield clip is the rig's own, so the MODEL5 quirk below leaves it alone.
	_shield_clip.position = home
	if unit.team_side == CombatUnit.Team.TWO:
		_doll.scale.x = -1  # mirrored, facing left
		_shield_clip.scale.x = -1
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
	_draw_status()


# Shows one move's result at the moment it lands on this fighter: the number
# and the Result flash, then the death or flinch, then the voice, or for a
# Shield block the Shield clip, its sound and SHIELDED. Then comes the update of
# the bars, the buff icons and the stun pose. Every result but a miss shows the
# target it states, because the original recomputes and redraws its target
# after every strike that lands (the conductor, line 103) and runs nothing on a
# miss. A Buff tick that the unit took earlier in the half-turn has already
# shown, because it has an event of its own (see show_tick()).
func show_result(result: MoveResult, move: Ability) -> void:
	var amount: float = result.amount
	var critical: bool = result.critical
	match result.kind:
		MoveResult.Kind.DAMAGE when result.shield_took_all:
			# A Shield block. The original checks the shield before it checks
			# sswitch, plays the Shield clip and sfx_shield, draws SHIELDED, and
			# runs nothing else of the hit: no Result flash, no flinch and no hit
			# voice (frame_42/DoAction_8.as:70-76).
			play_shield_clip()
			effect_cue.emit("sfx_shield")
			_floating_numbers.show_shield(_home)
		MoveResult.Kind.DAMAGE when result.direction == MoveResult.Direction.HEAL:
			# Under sswitch this damage healed the target. The original plays the
			# `heal` flash and no hit animation or hit voice
			# (frame_42/DoAction_8.as:133-149). It draws the number in the move's
			# element color and then a heal green one over it (lines 80 and 137),
			# and ADR 0005 has the port draw one number, in heal green.
			_floating_numbers.show_number(_home, amount, MenuTheme.HEAL_COLOR, critical)
			_flash.play(ResultFlash.Kind.HEAL)
		MoveResult.Kind.DAMAGE:
			# The original draws this number twice (frame_42/DoAction_8.as:80 and
			# 84), and ADR 0005 has the port draw it once. Then it plays the `hit`
			# flash (95-99).
			_floating_numbers.show_number(_home, amount, _element_color(move), critical)
			_flash.play(ResultFlash.Kind.HIT)
			_die_or_flinch(result)
			# The original plays the hit voice only when the target survives, and
			# plays it on a stunned target too (frame_42/DoAction_8.as:104-131).
			if not result.killed:
				voice_cue.emit(_unit.voice_hit)
		MoveResult.Kind.HEAL when result.direction == MoveResult.Direction.HARM:
			# Under sswitch this heal hurt the target. The original draws its
			# number in the Shadow color, plays the `hit` flash, plays the hit
			# animation unless the target is stunned, plays no hit voice, and
			# plays the death at the impact when the heal kills
			# (frame_42/DoAction_8.as:189-229).
			_floating_numbers.show_number(_home, amount, MenuTheme.ELEMENT_COLORS[CombatUnit.Element.SHADOW], critical)
			_flash.play(ResultFlash.Kind.HIT)
			_die_or_flinch(result)
		MoveResult.Kind.HEAL:
			# A heal of 0 draws nothing and plays no flash, because the
			# original's whole heal branch sits inside DamageOutputKrinFinal > 0
			# (frame_42/DoAction_8.as:172). A heal above 0 plays the `heal` flash
			# (182-186).
			if amount > 0:
				_floating_numbers.show_number(_home, amount, MenuTheme.HEAL_COLOR, critical)
				_flash.play(ResultFlash.Kind.HEAL)
		MoveResult.Kind.FOCUS:
			# The original draws no number for a focus result, only its `focus`
			# flash (frame_42/DoAction_8.as:232-249).
			_flash.play(ResultFlash.Kind.FOCUS)
		MoveResult.Kind.MISS:
			# The conductor shows a miss as the MISS word in the move's element
			# color (line 108), and no Result flash. The caster's own animation
			# still played in full to get here (see _execute_move_action's
			# comment). battle_scene.gd plays the miss sound, because the move's
			# type decides it.
			_floating_numbers.show_miss(_home, _element_color(move))
	if result.kind != MoveResult.Kind.MISS:
		show_state(result.target_after)


# Plays the Shield clip once on this fighter's rig. show_result() plays it with a
# sound for a Shield block, and show_tick() plays it with none for a Buff tick that
# a shield soaks whole, so it takes no Move result.
func play_shield_clip() -> void:
	_shield_clip.play()


# Shows one Buff tick at the moment it comes due on this fighter. buffTicker
# draws one Floating number in `normal` for the whole total: heal green for
# healing, the color of the strongest element for damage, SHIELDED for a tick that
# a shield soaked whole, and nothing for a total of 0 (frame_42/DoAction_10.as:64-98).
# A tick plays no Result flash and no sound. The original also plays no Shield clip
# for a soaked tick, because its call names IDKT, which buffTicker never declares
# (line 72). ADR 0005 has the port play the clip on this fighter. Then comes the
# update of the bars, the buff icons and the stun pose, because the
# applyChangesKrin that ends buffTicker redraws the unit (line 135). A tick that
# kills the unit is followed by a DEATH event, which plays the death.
func show_tick(tick: BuffTick) -> void:
	if tick.shield_took_all:
		play_shield_clip()
		_floating_numbers.show_shield(_home)
	else:
		match tick.direction:
			MoveResult.Direction.HARM:
				_floating_numbers.show_number(_home, tick.amount, MenuTheme.ELEMENT_COLORS[tick.element], false)
			MoveResult.Direction.HEAL:
				_floating_numbers.show_number(_home, tick.amount, MenuTheme.HEAL_COLOR, false)
	show_state(tick.after)


func _element_color(move: Ability) -> Color:
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


# Plays the death: the doll's dead label, an empty bar, the death voice, and the
# overlay's clear and fade, which _process() counts out. The original's
# lifeBarUpdate plays the voice and starts the fade only when the bar's rounded
# percent changes (frame_42/DoAction_8.as:295-298 and 345-347), which skips a
# unit killed from under 0.5% life. ADR 0005 counts that as an Original bug, so
# every death plays them here.
func die() -> void:
	_dead = true
	_doll.set_state(CharacterVisual.State.DEAD)
	displayed = displayed.with_life(0.0)
	_draw_status()
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


# Shows the bars, the buff icons and the stun pose that an event left on this
# fighter's unit.
func show_state(state: UnitSnapshot) -> void:
	_show_stun(state.stun)
	displayed = state
	_draw_status()


func _draw_status() -> void:
	_overlay.show_status(displayed, _buffs_by_id)


# The backstop for the half-turn's end. Every change to a unit has an event that
# states it, and each shows when it plays, so this only catches a change that no
# event states.
func snap_to_unit() -> void:
	show_state(UnitSnapshot.of(_unit))


# A unit's stun is a running total over every stun buff it holds. Any rise
# replays the "stun" label, even on a doll that is already stunned, and any fall
# plays "outofstun", even one that leaves it stunned by a shorter buff, the way
# applyChangesKrin compares STUN with its last value (see DECODED_ALGORITHMS.md).
# The original changes no dead unit's stun pose, so a dead doll keeps its death.
func _show_stun(stun: float) -> void:
	if _dead:
		return
	if stun > displayed.stun:
		_doll.enter_stun()
	elif stun < displayed.stun:
		_doll.exit_stun()


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
