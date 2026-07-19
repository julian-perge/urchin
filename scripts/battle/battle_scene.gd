# battle_scene.gd
# The playable battle screen - glues the headless stack (BattleSetup ->
# BattleRunner -> BattleRewards/ZoneProgression/Achievements) to visuals
# (CharacterVisual paper dolls), input, and audio.
#
# Interaction model matches the original (frame 217 KRIN_BATTLE_SCENE):
# - hover a unit: a target ring glows under it (white = you, green = ally,
#   red = enemy) with "Lvl. N" and the name
# - click a unit on your turn: your bar's abilities fan out around it as
#   orbs; unusable ones (wrong target, focus, cooldown) are darkened;
#   orb tooltips carry name/cost/description
# - the bottom bar: companion stance buttons (agModeAr presets) on the
#   left, the Pass ring in the center (light blue while waiting for your
#   choice, gray during the fight loop) with the retreat X beside it
#
# Entry: ZoneManager.battle_selected stores the pick in
# ZoneManager.pending_battle and the game scene switches here; _ready()
# consumes it. Tests inject via start_battle() with animation_speed = 0.
extends Control

signal battle_finished(outcome: int)

const CharacterVisualScene = preload("res://scenes/character_visual.tscn")
const BACKGROUND_ROOT = "res://assets/backgrounds"

# Exact BATTLESCREEN placements from the SWF: BATTLESCREEN sits at
# (400, 294.5); player1-6 offsets pulled from its PlaceObject matrices
# (player3 mirrors player4, its twin on the other team). Team 2 clips carry
# scaleX -1 in the source - mirrored via visual.scale.x below.
const SLOT_POSITIONS = {
	1: Vector2(160.9, 297.4),
	3: Vector2(220.9, 371.0),
	5: Vector2(220.9, 218.5),
	2: Vector2(637.9, 297.4),
	4: Vector2(577.9, 371.0),
	6: Vector2(577.9, 218.5),
}

const RING_COLORS = {
	"player": Color(0.85, 0.85, 0.85),
	"ally": Color(0.35, 0.9, 0.25),
	"enemy": Color(0.95, 0.25, 0.15),
}
const ORB_RADIUS = 15.0
# Ability orbs fan out over the unit's head, like the source's floating orbs.
const ORB_ARC_START = -2.4  # radians
const ORB_ARC_STEP = 0.55
const ORB_ARC_DISTANCE = 62.0

const BOTTOM_BAR_TOP = 470.0

# 1.0 = normal pacing; 0.0 = instant (tests).
var animation_speed: float = 1.0

var runner: BattleRunner
var battle_manager: BattleManager
var battle: BattleFight
var units: Dictionary = {}
var battle_info: Dictionary = {}

var _visuals: Dictionary = {}  # slot -> CharacterVisual
var _overlays: Dictionary = {}  # slot -> Control (bars/name/hover, unmirrored)
var _health_bars: Dictionary = {}
var _health_values: Dictionary = {}
var _focus_bars: Dictionary = {}
var _rings: Dictionary = {}  # slot -> ring Control (hover indicator)
var _stance_rows: Dictionary = {}  # party_id -> Array[Button]
var _selected_move: Dictionary = {}
var _player_action_pending: bool = false
var _finished: bool = false
var _radial_menu: Control = null
var _pass_ring: Control = null
var _pass_button: Button = null

@onready var background: TextureRect = $Background
@onready var sky: TextureRect = $Sky
@onready var battlefield: Node2D = $Battlefield
@onready var turn_label: Label = $UI/TurnLabel
@onready var speech_label: Label = $UI/SpeechLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/VBox/ResultLabel
@onready var continue_button: Button = $UI/ResultPanel/VBox/ContinueButton


func _ready():
	result_panel.hide()
	speech_label.text = ""
	continue_button.pressed.connect(_on_continue_pressed)
	_build_bottom_bar()
	if not ZoneManager.pending_battle.is_empty():
		start_battle(ZoneManager.pending_battle)
		ZoneManager.pending_battle = {}


func start_battle(info: Dictionary) -> void:
	battle_info = info
	battle_manager = BattleManager.new()
	add_child(battle_manager)
	battle = BattleSetup.load_battle(int(info["battle_id"]))
	if battle == null:
		push_warning("battle_scene: no battle %s" % info.get("battle_id"))
		return
	var save = GameData.current_save
	units = BattleSetup.build_units(
		battle, save, UnitManagerAuto.units_by_id, save.difficulty,
		int(info.get("train_cap", BattleSetup.DEFAULT_TRAIN_CAP))
	)
	runner = BattleRunner.new()
	runner.setup(
		units, battle, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id,
		BuffManagerAuto.buffs_by_internal_name, battle_manager,
		TalentTree.get_passive_buff_names(save)
	)
	_load_background()
	_spawn_visuals()
	_populate_stance_rows()
	AudioManagerAuto.play_battle_music(info.get("is_boss", false))
	_battle_loop.call_deferred()


# The original composites a sky layer (SKY_<key>) behind the hall art; the
# hall PNGs have a transparent sky region.
func _load_background() -> void:
	var key = battle.zone_background.replace(" ", "_")
	var path = "%s/battle/%s.png" % [BACKGROUND_ROOT, key]
	if ResourceLoader.exists(path):
		background.texture = load(path)
	var sky_key = key
	var sky_path = "%s/sky/SKY_%s.png" % [BACKGROUND_ROOT, sky_key]
	if not ResourceLoader.exists(sky_path):
		# STREETS2 -> SKY_STREETS, CHURCH2 -> SKY_CHURCH, JAIL3 -> SKY_JAIL...
		sky_key = key.rstrip("0123456789")
		sky_path = "%s/sky/SKY_%s.png" % [BACKGROUND_ROOT, sky_key]
	if not ResourceLoader.exists(sky_path):
		sky_path = "%s/sky/SKY_JAIL.png" % BACKGROUND_ROOT  # generic city glow
	if ResourceLoader.exists(sky_path):
		sky.texture = load(sky_path)


func _spawn_visuals() -> void:
	for slot in units:
		var unit: CombatUnit = units[slot]
		var visual: CharacterVisual = CharacterVisualScene.instantiate()
		visual.position = SLOT_POSITIONS.get(slot, Vector2(400, 300))
		if unit.team_side == 2:
			visual.scale.x = -1  # mirrored, facing left
		# dressChar's MODEL5 quirk: 0.8x scale, 10px lower.
		if not unit.model.is_empty() and str(unit.model[0]) == "MODEL5":
			visual.scale *= 0.8
			visual.position.y += 10
		battlefield.add_child(visual)
		visual.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, ItemManagerAuto.items_by_id))
		_visuals[slot] = visual
		_add_unit_overlay(slot, unit, visual)
	_refresh_bars()


# Bars/name/hover live in an UNMIRRORED overlay at the slot position -
# parenting them to a mirrored visual flipped their offsets on team 2.
func _add_unit_overlay(slot: int, unit: CombatUnit, visual: CharacterVisual) -> void:
	var overlay = Control.new()
	overlay.position = visual.position
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield.add_child(overlay)
	_overlays[slot] = overlay

	var ring = Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	ring.draw.connect(_draw_ring.bind(ring, slot))
	overlay.add_child(ring)
	_rings[slot] = ring

	var name_label = Label.new()
	name_label.text = unit.player_name
	name_label.position = Vector2(-52, -82)
	name_label.size = Vector2(104, 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(name_label)

	var health = ProgressBar.new()
	health.custom_minimum_size = Vector2(52, 6)
	health.position = Vector2(-26, -66)
	health.show_percentage = false
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(health)
	_health_bars[slot] = health
	var health_value = Label.new()
	health_value.position = Vector2(28, -69)
	health_value.size = Vector2(46, 12)
	health_value.add_theme_font_size_override("font_size", 9)
	health_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(health_value)
	_health_values[slot] = health_value

	var focus = ProgressBar.new()
	focus.custom_minimum_size = Vector2(52, 3)
	focus.position = Vector2(-26, -58)
	focus.show_percentage = false
	focus.modulate = Color(0.5, 0.7, 1.0)
	focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(focus)
	_focus_bars[slot] = focus

	# Hover/click zone over the doll.
	var hit = Button.new()
	hit.flat = true
	hit.custom_minimum_size = Vector2(56, 100)
	hit.size = hit.custom_minimum_size
	hit.position = Vector2(-28, -52)
	hit.mouse_entered.connect(_on_unit_hovered.bind(slot, true))
	hit.mouse_exited.connect(_on_unit_hovered.bind(slot, false))
	hit.pressed.connect(_on_unit_clicked.bind(slot))
	overlay.add_child(hit)


# The original's target ring: a thick circle with four tick marks.
func _draw_ring(ring: Control, slot: int) -> void:
	var unit: CombatUnit = units.get(slot)
	if unit == null:
		return
	var color: Color = RING_COLORS[_relation_to_player(slot)]
	ring.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(color, 0.55), 7.0, true)
	ring.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 48, Color(color, 0.25), 3.0, true)
	for k in 4:
		var angle = k * TAU / 4.0
		ring.draw_line(
			Vector2.from_angle(angle) * 26.0, Vector2.from_angle(angle) * 44.0,
			Color(color, 0.7), 3.0, true
		)


func _relation_to_player(slot: int) -> String:
	if slot == BattleRunner.PLAYER_SLOT:
		return "player"
	var unit: CombatUnit = units.get(slot)
	return "ally" if unit != null and unit.team_side == 1 else "enemy"


func _on_unit_hovered(slot: int, entered: bool) -> void:
	var ring: Control = _rings.get(slot)
	var unit: CombatUnit = units.get(slot)
	if ring == null or unit == null or not unit.active:
		return
	ring.visible = entered
	ring.queue_redraw()
	var overlay: Control = _overlays[slot]
	var existing = overlay.get_node_or_null("HoverInfo")
	if existing:
		existing.queue_free()
	if entered:
		var info = Label.new()
		info.name = "HoverInfo"
		info.text = "Lvl. %d" % unit.plevel
		info.position = Vector2(-40, -8)
		info.size = Vector2(80, 16)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 11)
		info.add_theme_color_override("font_color", RING_COLORS[_relation_to_player(slot)])
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(info)


# --- radial ability menu ---------------------------------------------------

func _on_unit_clicked(slot: int) -> void:
	if not _player_action_pending:
		return
	var target: CombatUnit = units.get(slot)
	if target == null or not target.active:
		return
	_close_radial_menu()
	var entries: Array = runner.get_player_usable_moves()
	if entries.is_empty():
		return
	_radial_menu = Control.new()
	_radial_menu.position = SLOT_POSITIONS.get(slot, Vector2(400, 300))
	_radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield.add_child(_radial_menu)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var move: Ability = MoveManagerAuto.get_move(int(entry["move_id"]))
		if move == null:
			continue
		var usable = _move_valid_for_target(move, slot)
		var orb = Button.new()
		orb.custom_minimum_size = Vector2(ORB_RADIUS * 2, ORB_RADIUS * 2)
		orb.size = orb.custom_minimum_size
		var angle = ORB_ARC_START + i * ORB_ARC_STEP
		orb.position = Vector2.from_angle(angle) * ORB_ARC_DISTANCE - orb.size / 2.0
		orb.text = _move_initials(move)
		orb.tooltip_text = _move_tooltip(move)
		var color = _move_color(move)
		_style_orb(orb, color, usable)
		if usable:
			orb.pressed.connect(_on_radial_move_picked.bind(entry, slot))
		else:
			orb.disabled = true
		_radial_menu.add_child(orb)


func _move_valid_for_target(move: Ability, slot: int) -> bool:
	var target: CombatUnit = units.get(slot)
	if target == null or not target.active:
		return false
	var is_ally = target.team_side == 1
	var is_self = slot == BattleRunner.PLAYER_SLOT
	return (
		(is_self and move.can_target_self)
		or (not is_ally and move.can_target_others)
		or (is_ally and not is_self and move.targets_allies)
	)


func _move_tooltip(move: Ability) -> String:
	var cost_line = "This move costs nothing"
	if move.focus_cost > 0:
		cost_line = "This move costs %d Focus" % int(move.focus_cost)
	var lines = [move.display_name, cost_line]
	if move.cooldown_turns > 0:
		lines.append("Cooldown: %d turns" % move.cooldown_turns)
	return "\n".join(lines)


func _move_color(move: Ability) -> Color:
	var element_index = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


func _move_initials(move: Ability) -> String:
	var words = move.display_name.split(" ", false)
	if words.size() >= 2:
		return words[0].substr(0, 1) + words[1].substr(0, 1)
	return move.display_name.substr(0, 2)


func _style_orb(orb: Button, color: Color, usable: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style = StyleBoxFlat.new()
		var bg = Color(0.08, 0.08, 0.1) if usable else Color(0.05, 0.05, 0.06)
		style.bg_color = bg.lightened(0.1) if state == "hover" else bg
		style.border_color = color if usable else Color(0.18, 0.18, 0.2)
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		orb.add_theme_stylebox_override(state, style)
	orb.add_theme_font_size_override("font_size", 9)
	orb.add_theme_color_override("font_color", Color.WHITE if usable else Color(0.35, 0.35, 0.35))
	orb.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.32))


func _on_radial_move_picked(entry: Dictionary, target_slot: int) -> void:
	_selected_move = {
		"bar_index": entry["bar_index"],
		"move_id": entry["move_id"],
		"target_slot": target_slot,
	}
	_close_radial_menu()
	_player_action_pending = false


func _close_radial_menu() -> void:
	if _radial_menu != null:
		_radial_menu.queue_free()
		_radial_menu = null


# --- bottom bar: stances + pass ring + retreat -----------------------------

func _build_bottom_bar() -> void:
	var bar = Control.new()
	bar.name = "BottomBar"
	bar.position = Vector2(0, BOTTOM_BAR_TOP)
	bar.size = Vector2(800, 600 - BOTTOM_BAR_TOP)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.06)
	backdrop.size = bar.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.add_child(backdrop)
	var texture = load("res://assets/ui/hotbar/background.png")
	for rect in [Rect2(12, 10, 320, 110), Rect2(340, 10, 120, 110), Rect2(468, 10, 320, 110)]:
		var panel = TextureRect.new()
		panel.texture = texture
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.stretch_mode = TextureRect.STRETCH_SCALE
		panel.position = rect.position
		panel.size = rect.size
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(panel)

	# Stance rows fill in when the battle starts (companions known then).
	var stance_host = Control.new()
	stance_host.name = "StanceHost"
	stance_host.position = Vector2(24, 18)
	stance_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(stance_host)

	# Pass ring: light blue while the player chooses, gray otherwise.
	_pass_ring = Control.new()
	_pass_ring.position = Vector2(400, 65)
	_pass_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_ring.draw.connect(_draw_pass_ring)
	bar.add_child(_pass_ring)
	_pass_button = Button.new()
	_pass_button.custom_minimum_size = Vector2(56, 56)
	_pass_button.size = _pass_button.custom_minimum_size
	_pass_button.position = Vector2(400 - 28, 65 - 28)
	_pass_button.text = "!"
	_pass_button.tooltip_text = "Pass your turn"
	for state in ["normal", "hover", "pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.11) if state == "normal" else Color(0.16, 0.16, 0.18)
		style.border_color = Color(0.3, 0.3, 0.32)
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		_pass_button.add_theme_stylebox_override(state, style)
	_pass_button.add_theme_font_size_override("font_size", 22)
	_pass_button.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	_pass_button.pressed.connect(_on_pass_pressed)
	bar.add_child(_pass_button)

	var retreat = Button.new()
	retreat.custom_minimum_size = Vector2(26, 26)
	retreat.size = retreat.custom_minimum_size
	retreat.position = Vector2(442, 12)
	retreat.tooltip_text = "Retreat from battle"
	var retreat_style = StyleBoxFlat.new()
	retreat_style.bg_color = Color(0.55, 0.1, 0.08)
	retreat_style.set_border_width_all(2)
	retreat_style.border_color = Color(0.8, 0.3, 0.25)
	retreat_style.set_corner_radius_all(3)
	retreat.add_theme_stylebox_override("normal", retreat_style)
	var retreat_hover = retreat_style.duplicate()
	retreat_hover.bg_color = Color(0.75, 0.15, 0.1)
	retreat.add_theme_stylebox_override("hover", retreat_hover)
	retreat.text = "x"
	retreat.pressed.connect(_on_retreat_pressed)
	bar.add_child(retreat)


func _draw_pass_ring() -> void:
	var active = _player_action_pending
	var color = Color(0.4, 0.75, 1.0, 0.95) if active else Color(0.35, 0.35, 0.38, 0.7)
	_pass_ring.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 64, color, 5.0, true)
	if active:
		_pass_ring.draw_arc(Vector2.ZERO, 41.0, 0.0, TAU, 64, Color(0.4, 0.75, 1.0, 0.35), 7.0, true)


func _populate_stance_rows() -> void:
	var host: Control = get_node("BottomBar/StanceHost")
	for child in host.get_children():
		child.queue_free()
	_stance_rows.clear()
	var save = GameData.current_save
	var row_y = 0.0
	for slot in [3, 5]:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		var party_id = _party_id_for_unit(unit)
		if party_id <= 0:
			continue
		var name_label = Label.new()
		name_label.text = unit.player_name
		name_label.position = Vector2(0, row_y + 4)
		name_label.size = Vector2(90, 20)
		name_label.add_theme_font_size_override("font_size", 12)
		host.add_child(name_label)
		var buttons: Array = []
		for mode in Party.AGGRESSION_PRESETS.size():
			var button = Button.new()
			button.custom_minimum_size = Vector2(34, 26)
			button.size = button.custom_minimum_size
			button.position = Vector2(96 + mode * 40, row_y)
			button.tooltip_text = Party.AGGRESSION_NAMES[mode]
			button.pressed.connect(_on_stance_pressed.bind(party_id, mode, slot))
			host.add_child(button)
			buttons.append(button)
		_stance_rows[party_id] = buttons
		_refresh_stance_row(party_id, Party.get_ag_mode(save, party_id) if save != null else 2)
		row_y += 46.0


# Stance tint runs green (hold back) to red (all in), like the original's
# five icons.
func _refresh_stance_row(party_id: int, selected_mode: int) -> void:
	var colors = [
		Color(0.25, 0.55, 0.3), Color(0.35, 0.55, 0.25), Color(0.6, 0.55, 0.2),
		Color(0.65, 0.35, 0.15), Color(0.65, 0.15, 0.12),
	]
	var buttons: Array = _stance_rows.get(party_id, [])
	for mode in buttons.size():
		var button: Button = buttons[mode]
		var style = StyleBoxFlat.new()
		style.bg_color = colors[mode]
		style.set_corner_radius_all(3)
		style.set_border_width_all(2)
		style.border_color = Color.WHITE if mode == selected_mode else Color(0.15, 0.15, 0.15)
		button.add_theme_stylebox_override("normal", style)
		var hover = style.duplicate()
		hover.bg_color = colors[mode].lightened(0.2)
		button.add_theme_stylebox_override("hover", hover)


func _party_id_for_unit(unit: CombatUnit) -> int:
	for party_id in Party.COMPANIONS:
		if Party.COMPANIONS[party_id]["name"] == unit.player_name:
			return party_id
	return -1


func _on_stance_pressed(party_id: int, mode: int, slot: int) -> void:
	var save = GameData.current_save
	if save != null:
		Party.set_ag_mode(save, party_id, mode)
	var unit: CombatUnit = units.get(slot)
	if unit != null:
		Party.apply_aggression_mode(unit, mode)
	_refresh_stance_row(party_id, mode)


# --- turn loop ---------------------------------------------------------------

func _battle_loop() -> void:
	while not runner.is_over():
		if runner.is_player_turn():
			_player_action_pending = true
			turn_label.text = "Your move"
			_pass_ring.queue_redraw()
			while _player_action_pending:
				await get_tree().process_frame
		else:
			turn_label.text = "Enemy turn" if runner.team_move_now == 2 else "Ally turn"
			await _pause(0.4)
		_pass_ring.queue_redraw()
		var action = _selected_move.duplicate()
		_selected_move = {}
		_close_radial_menu()
		var events = runner.advance_half_turn(action)
		await _play_events(events)
		_refresh_bars()
	await _finish_battle()


func _on_pass_pressed() -> void:
	if not _player_action_pending:
		return
	_selected_move = {}
	_close_radial_menu()
	_player_action_pending = false


func _on_retreat_pressed() -> void:
	if _finished:
		return
	_finished = true
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# Replays a half-turn's event log with animation + audio pacing.
func _play_events(events: Array) -> void:
	for event in events:
		match event["type"]:
			"move":
				await _play_move_event(event)
			"miss":
				_float_text(int(event["target_slot"]), "MISS", Color.GRAY)
				AudioManagerAuto.play_effect("sfx_magicmiss")
				await _pause(0.3)
			"stunned":
				_float_text(int(event["caster_slot"]), "STUNNED", Color.YELLOW)
				await _pause(0.3)
			"move_failed":
				_float_text(int(event["caster_slot"]), "NOT ENOUGH %s" % str(event.get("reason", "")).to_upper(), Color.ORANGE)
				await _pause(0.3)
			"dispel":
				_float_text(int(event["target_slot"]), "DISPEL", Color.CYAN)
			"death":
				_play_death(int(event["slot"]))
				await _pause(0.4)
			"speech":
				await _play_speech(event)
			"phase_advanced":
				AudioManagerAuto.play_battle_music(true)
			"battle_ended":
				pass
		_refresh_bars()


func _play_move_event(event: Dictionary) -> void:
	var caster_slot = int(event["caster_slot"])
	var target_slot = int(event["target_slot"])
	var move: Ability = MoveManagerAuto.get_move(int(event["move_id"]))
	var caster_visual: CharacterVisual = _visuals.get(caster_slot)
	if caster_visual != null and move != null:
		if move.attack_animation_type == "Melee":
			caster_visual.set_state(CharacterVisual.State.MELEE)
		else:
			caster_visual.set_state(CharacterVisual.State.CAST)
			AudioManagerAuto.play_effect("sfx_cast")
		await _pause(0.25)
	if move != null:
		AudioManagerAuto.play_effect(move.sound_effect_name)
	var result: Dictionary = event.get("result", {})
	var target_visual: CharacterVisual = _visuals.get(target_slot)
	var target_unit: CombatUnit = units.get(target_slot)
	match result.get("type", ""):
		"damage":
			_float_text(target_slot, str(int(result.get("amount", 0))), Color.RED if result.get("did_crit") else Color.WHITE)
			if target_visual != null and not result.get("target_died", false):
				target_visual.set_state(CharacterVisual.State.HIT)
			if target_unit != null:
				AudioManagerAuto.voice(target_unit.voice_hit)
		"heal":
			_float_text(target_slot, "+%d" % int(result.get("amount", 0)), Color.GREEN)
		"focus":
			_float_text(target_slot, "+%d FOCUS" % int(result.get("amount", 0)), Color.SKY_BLUE)
	await _pause(0.35)


func _play_death(slot: int) -> void:
	var visual: CharacterVisual = _visuals.get(slot)
	if visual != null:
		visual.set_state(CharacterVisual.State.DEAD)
	var overlay: Control = _overlays.get(slot)
	if overlay != null:
		overlay.visible = false
	var unit: CombatUnit = units.get(slot)
	if unit != null:
		AudioManagerAuto.play_effect(unit.voice_die)


func _play_speech(event: Dictionary) -> void:
	speech_label.text = "%s: %s" % [_speaker_name(int(event.get("speaker_slot", 0))), event.get("say", "")]
	AudioManagerAuto.play_effect(str(event.get("voice_over", "")))
	await _pause(min(float(event.get("time_to_say", 2.0)), 4.0))
	speech_label.text = ""


func _speaker_name(slot: int) -> String:
	var unit: CombatUnit = units.get(slot)
	return unit.player_name if unit != null else "???"


func _refresh_bars() -> void:
	for slot in _visuals:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		var health: ProgressBar = _health_bars[slot]
		health.max_value = unit.life_u
		health.value = unit.life_n
		_health_values[slot].text = str(int(unit.life_n))
		var focus: ProgressBar = _focus_bars[slot]
		focus.max_value = max(unit.focus_u, 1)
		focus.value = unit.focus_n
		var visual: CharacterVisual = _visuals[slot]
		# Stun state holds while the unit is stunned (and alive).
		if unit.active and unit.stun != 0 and visual.is_idle():
			visual.set_state(CharacterVisual.State.STUN)
		elif unit.active and unit.stun == 0 and visual._state == CharacterVisual.State.STUN:
			visual.set_state(CharacterVisual.State.IDLE)


func _float_text(slot: int, text: String, color: Color) -> void:
	var visual: CharacterVisual = _visuals.get(slot)
	if visual == null:
		return
	var label = Label.new()
	label.text = text
	label.modulate = color
	label.position = visual.position + Vector2(-15, -72)
	label.scale = Vector2.ONE
	battlefield.add_child(label)
	if animation_speed <= 0.0:
		label.queue_free()
		return
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func _finish_battle() -> void:
	if _finished:
		return
	_finished = true
	var save = GameData.current_save
	var outcome = runner.win_condition
	if outcome == BattleRunner.Outcome.WIN and save != null:
		var was_story = battle_info.get("is_story_progress", false)
		ZoneProgression.after_battle_won(save, battle.id, was_story)
		var enemy_levels = BattleRewards.unit_levels_from_slots(units, [2, 4, 6])
		var fighting_party = []
		for marker in [-2, -1]:
			var party_id = Party.deployed_party_id(save, marker)
			if party_id > 0:
				fighting_party.append(party_id)
		var rewards = BattleRewards.apply_victory(save, enemy_levels, enemy_levels, fighting_party)
		var drops = BattleRewards.roll_drops(battle)
		var counters = Achievements.collect_battle_counters(runner, units)
		for achievement_id in Achievements.check_battle_victory(save, battle.id, was_story, counters):
			Achievements.unlock(achievement_id)
		# Drops are click-to-keep on the victory screen (VICTORY[1]); the
		# autosave happens on Proceed, like the original.
		var victory = preload("res://scripts/battle/victory_screen.gd").new()
		victory.name = "VictoryScreen"
		victory.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(victory)
		victory.setup(save, rewards, drops, fighting_party)
		victory.proceed_pressed.connect(_on_victory_proceed)
	elif outcome == BattleRunner.Outcome.LOSS:
		result_label.text = "Defeat..."
		result_panel.show()
	else:
		result_label.text = "Draw."
		result_panel.show()
	battle_finished.emit(outcome)


func _on_victory_proceed() -> void:
	# The original autosaves on Proceed (when the option is on).
	if GameData.current_save != null and GameData.current_save.autosave:
		GameData.save_game()
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _pause(seconds: float) -> void:
	if animation_speed <= 0.0:
		return
	await get_tree().create_timer(seconds / animation_speed).timeout
