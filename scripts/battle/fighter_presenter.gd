# fighter_presenter.gd
# Everything one fighter shows on the Battle screen: its doll, its status bar,
# its buff icons, its hover ring, its Floating numbers, its Result flash, its Shield
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
# The ring's enterFrame adds 20 to its _alpha while the mouse is over the fighter
# and the alpha is under 100, and takes 5 off while the mouse is off it and the
# alpha is above 0 (frame_217/PlaceObject3_3394_450 and its 5 sibling files,
# lines 2-17). The alpha is in Flash's 1/256 steps (FlashAlpha).
const RING_FADE_IN_STEP: float = 20.0
const RING_FADE_OUT_STEP: float = 5.0
# Render deltas that add up to a whole SWF frame can fall short of it by a float
# rounding error, so a frame counts as passed within this margin.
const FRAME_EPSILON: float = 0.000001
# What the fighter shows: the life, Focus, stun and buff slots that the last
# event shown on it left on its unit. The runner resolves a whole half-turn
# before the replay starts, so the bars, the stun pose and the buff icons follow
# this instead of the unit, and only show_state(), show_result(), show_tick(),
# snap_to_unit() and die() change it.
var displayed: UnitSnapshot

var _unit: CombatUnit
# The fighter's entry in the top status bar, which the scene owns.
var _status_bar: StatusBar
var _buffs_by_id: Dictionary = {}
var _floating_numbers: FloatingNumberLayer
# Where the original's rig, the unit's clip on BATTLESCREEN, stands. dressChar
# lowers only the doll inside it for a MODEL5 unit (frame_217/DoAction_2.as:19-24),
# so the rig and every Floating number on the unit stay here.
var _home: Vector2
var _dead: bool = false
# The ring's _alpha in Flash's 1/256 steps, whether the mouse is over the
# fighter, and the SWF frames that _process() has counted toward the next step.
var _ring_alpha: int = 0
var _ring_hovered: bool = false
var _ring_frames_due: float = 0.0
var _hover_info: Label = null
# setup() puts the doll this far from its home, and rig_position() takes it
# back off.
var _doll_offset: Vector2 = Vector2.ZERO
# The unit's own equipment looks, which a form's empty weapon takes.
var _equip_looks: Array = []
# The form the doll wears, which the original keeps as dressNow.
var _form: String = ""
# Whether the doll is a MODEL5 clip, which dressChar lowers inside its rig.
var _doll_is_model5: bool = false

@onready var hit_area: Button = $Overlay/HitButton
@onready var _doll: CharacterVisual = $Doll
@onready var _overlay: UnitOverlay = $Overlay
@onready var _flash: ResultFlash = $ResultFlash
@onready var _shield_clip: ShieldClip = $ShieldClip
@onready var _speech_bubble: SpeechBubble = $SpeechBubble


# The ring has nothing to fade until setup() has run and show_hover() starts it.
func _ready() -> void:
	set_process(false)


# Call once, after the presenter is in the tree. It leaves the fighter drawn.
# `status_bar` is the fighter's entry in the top status bar.
# Floating numbers go on the battle's one FloatingNumberLayer rather than on this
# node, because they have to draw over every fighter, and a fighter later in the
# tree would cover a number parented here.
func setup(unit: CombatUnit, home: Vector2, items_by_id: Dictionary, buffs_by_id: Dictionary, floating_numbers: FloatingNumberLayer, status_bar: StatusBar) -> void:
	_unit = unit
	_status_bar = status_bar
	_status_bar.death_hidden.connect(_overlay.hide)
	_buffs_by_id = buffs_by_id
	_floating_numbers = floating_numbers
	_home = home
	displayed = UnitSnapshot.of(unit)
	_doll.position = home
	# The doll's swing plays its own sounds, such as the whoosh of sfx_swing.
	_doll.sound_cue.connect(effect_cue.emit)
	# The Shield clip is the rig's own, so the MODEL5 quirk of _set_doll_model leaves it alone.
	_shield_clip.position = home
	_speech_bubble.position = home
	if unit.team_side == CombatUnit.Team.TWO:
		_doll.scale.x = -1  # mirrored, facing left
		_shield_clip.scale.x = -1
		_speech_bubble.scale.x = -1
	_set_doll_model(str(unit.model[0]) if not unit.model.is_empty() else "")
	_equip_looks = CharacterVisual.resolve_equip_looks(unit, items_by_id)
	_form = BuffLook.looks()["default_form"]
	_doll.dress_from_model(unit.model, _equip_looks)
	if not unit.model.is_empty():
		_doll.start_clip(str(unit.model[0]))
	# The overlay is the doll's sibling because parenting it to a mirrored doll
	# flipped its offsets on team 2.
	_overlay.position = _doll.position
	_status_bar.setup(unit.player_name)
	_overlay.ring.draw.connect(_draw_ring)
	_overlay.ring.modulate.a = FlashAlpha.multiplier(_ring_alpha)
	set_process(false)
	_show_form(displayed)
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


# Plays the Speech bubble once over this fighter's head, as the original's
# BATTLESCREEN["player" + n].speech.play() does for the speaker of a line.
func play_speech_bubble() -> void:
	_speech_bubble.play()


# Whether the Speech bubble is playing right now.
var speech_bubble_playing: bool:
	get:
		return _speech_bubble.is_playing()


# Shows one Buff tick at the moment it comes due on this fighter. buffTicker
# draws one Floating number in `normal` for the whole total: heal green for
# healing, the color of the strongest element for damage, SHIELDED for a tick
# that a shield soaked whole, and nothing for a total of 0
# (frame_42/DoAction_10.as:64-98). A tick plays no Result flash and no sound. The
# original also plays no Shield clip for a soaked tick, because its call names
# IDKT, which buffTicker never declares (line 72). ADR 0005 has the port play the
# clip on this fighter. Then comes the update of the bars, the buff icons and the
# stun pose, because the applyChangesKrin that ends buffTicker redraws the unit
# (line 135). A tick that kills the unit is followed by a DEATH event, which plays
# the death.
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
# status bar's clear and fade, which the bar counts out. The original's
# lifeBarUpdate plays the voice and starts the fade only when the bar's rounded
# percent changes (frame_42/DoAction_8.as:295-298 and 345-347), which skips a
# unit killed from under 0.5% life. ADR 0005 counts that as an Original bug, so
# every death plays them here.
func die() -> void:
	_dead = true
	_doll.set_state(CharacterVisual.State.DEAD)
	displayed = displayed.with_life(0.0)
	_draw_status()
	_status_bar.die()
	effect_cue.emit(_unit.voice_die)


# Shows the bars, the buff icons and the stun pose that an event left on this
# fighter's unit.
func show_state(state: UnitSnapshot) -> void:
	# applyChangesKrin runs changeForm before it compares the stun, so a form
	# change comes first and a rise in the stun then replays the stun entry.
	_show_form(state)
	_show_stun(state.stun)
	displayed = state
	_draw_status()


# Dresses the doll in the form that the buffs of `state` give it, if it is not
# wearing that form already, as applyChangesKrin does when dressNow differs from
# its form (frame_42/DoAction_10.as:459-461). The original changes no dead unit's
# doll here either, because a dead unit takes no new buff.
func _show_form(state: UnitSnapshot) -> void:
	if _dead:
		return
	var form: String = BuffLook.resolve(state.buff_slots, _buffs_by_id).form
	if form == _form:
		return
	_form = form
	var stunned: bool = state.stun > 0.0
	var table: Dictionary = BuffLook.looks()
	if form == table["default_form"]:
		_set_doll_model(str(_unit.model[0]))
		_doll.wear_own_form(_unit.model, _equip_looks, stunned)
	else:
		_set_doll_model(table["forms"][form]["model"])
		_doll.wear_form(table["forms"][form], _equip_looks, stunned)


# dressChar draws a MODEL5 doll 0.8x as big and 10 px lower inside its rig
# (frame_217/DoAction_2.as:19-24), and a doll of another model at the rig's own
# scale and place. Only the doll moves, so the rig and the overlay stay.
func _set_doll_model(model: String) -> void:
	var lowered: bool = model == "MODEL5"
	if lowered == _doll_is_model5:
		return
	_doll_is_model5 = lowered
	var size: float = 0.8 if lowered else 1.0
	_doll.scale = Vector2(signf(_doll.scale.x) * size, size)
	var drop: float = 10.0 if lowered else -10.0
	_doll.shift_down(drop)
	_doll_offset.y += drop
	_overlay.position.y += drop


func _draw_status() -> void:
	_status_bar.show_status(displayed)
	_status_bar.refresh_buffs(displayed.buff_slots, _buffs_by_id)
	_draw_buff_look()


# Gives the doll the color and the glow that its buffs give it, as
# applyChangesKrin does after every result and every Buff tick on the unit
# (frame_42/DoAction_10.as:380-466). The look comes from the snapshot the fighter
# shows, so it waits for the event that lands the buff and goes at the event that
# removes it.
func _draw_buff_look() -> void:
	var look: BuffLook = BuffLook.resolve(displayed.buff_slots, _buffs_by_id)
	var looks: Dictionary = BuffLook.looks()
	_doll.show_buff_look(looks["colors"][look.color], looks["filters"][look.filter])


# Shows this fighter's unit as it is now. The scene calls this when the replay of a
# half-turn ends, so a change that no event stated still reaches the bars. A dead
# fighter is skipped, so its bar keeps the empty fill that its death left, even when
# the unit holds life again after the tick that killed it (see
# CombatUnit.tick_buffs).
func snap_to_unit() -> void:
	if _dead:
		return
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
	_overlay.ring.queue_redraw()
	_ring_hovered = showing
	set_process(true)
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


# Runs the ring's enterFrame once for each whole SWF frame that the deltas add
# up to, and stops once the ring is fully in or fully out.
func _process(delta: float) -> void:
	_ring_frames_due += delta * BattleScreenClip.fps()
	while _ring_frames_due >= 1.0 - FRAME_EPSILON:
		_ring_frames_due -= 1.0
		step_ring_frame()
	var fully_in: bool = _ring_hovered and FlashAlpha.to_percent(_ring_alpha) >= 100.0
	var fully_out: bool = not _ring_hovered and _ring_alpha <= 0
	if fully_in or fully_out:
		_ring_frames_due = 0.0
		set_process(false)


# One run of the ring's enterFrame. battle_scene.gd hovers the fighter only during
# a Decision, which stands in for the original's "_root.InBattle == false" test.
func step_ring_frame() -> void:
	if _ring_hovered:
		if FlashAlpha.to_percent(_ring_alpha) < 100.0:
			_ring_alpha = FlashAlpha.add(_ring_alpha, RING_FADE_IN_STEP)
	elif _ring_alpha > 0:
		_ring_alpha = FlashAlpha.add(_ring_alpha, -RING_FADE_OUT_STEP)
	_overlay.ring.modulate.a = FlashAlpha.multiplier(_ring_alpha)


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
