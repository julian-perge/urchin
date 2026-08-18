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

const CharacterVisualScene: PackedScene = preload("res://scenes/character_visual.tscn")
const UnitOverlayScene: PackedScene = preload("res://scenes/battle/unit_overlay.tscn")
const StanceRowScene: PackedScene = preload("res://scenes/battle/stance_row.tscn")
const BACKGROUND_ROOT: String = "res://assets/backgrounds"

# Exact BATTLESCREEN placements from the SWF: BATTLESCREEN sits at
# (400, 294.5); player1-6 offsets pulled from its PlaceObject matrices
# (player3 mirrors player4, its twin on the other team). Team 2 clips carry
# scaleX -1 in the source - mirrored via visual.scale.x below.
const SLOT_POSITIONS: Dictionary[Variant, Variant] = {
	1: Vector2(160.9, 297.4),
	3: Vector2(220.9, 371.0),
	5: Vector2(220.9, 218.5),
	2: Vector2(637.9, 297.4),
	4: Vector2(577.9, 371.0),
	6: Vector2(577.9, 218.5),
}

const RING_COLORS: Dictionary[Variant, Variant] = {
	"player": Color(0.85, 0.85, 0.85),
	"ally": Color(0.35, 0.9, 0.25),
	"enemy": Color(0.95, 0.25, 0.15),
}
const ORB_RADIUS: float = 15.0
# Ability orbs fan out over the unit's head, like the source's floating orbs.
const ORB_ARC_START: float = -2.4  # radians
const ORB_ARC_STEP: float = 0.55
const ORB_ARC_DISTANCE: float = 62.0

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
# Health as DISPLAYED: the runner pre-applies a whole half-turn's damage
# mechanically, so bars must only move when each hit lands visually
# (_show_move_result), then snap to the true values at half-turn end.
var _display_hp: Dictionary = {}
# krinBuff STUN running total per slot, last seen by _update_stun_visual - the
# original re-triggers the stun-in animation on ANY increase and the
# outofstun wake-up on ANY decrease (see DECODED_ALGORITHMS.md), so this has
# to be tracked across calls rather than compared against a fixed threshold.
var _last_stun: Dictionary = {}
var _rings: Dictionary = {}  # slot -> ring Control (hover indicator)
var _stance_rows: Dictionary = {}  # party_id -> Array[Button]
var _selected_move: Dictionary = {}
var _player_action_pending: bool = false
var _finished: bool = false
var _radial_menu: Control = null
var _pending_cutscene: String = ""  # set by _finish_battle() on a cutscene-triggering win
var _pending_goto_scene: String = ""  # ZoneProgression.CUTSCENE_GOTO_SCENE for that cutscene
var _pending_setup_events: Array = []  # runner.setup()'s return - played first by _battle_loop()

@onready var background: TextureRect = $Background
@onready var sky: TextureRect = $Sky
@onready var sky_fill: ColorRect = $SkyFill
@onready var battlefield: Node2D = $Battlefield
@onready var turn_label: Label = $UI/TurnLabel
@onready var speech_label: Label = $UI/SpeechLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/VBox/ResultLabel
@onready var continue_button: Button = $UI/ResultPanel/VBox/ContinueButton
@onready var _pass_ring: Control = $BottomBar/PassRing
@onready var stance_host: Control = $BottomBar/StanceHost


func _ready():
	result_panel.hide()
	speech_label.text = ""
	continue_button.pressed.connect(_on_continue_pressed)
	if not ZoneManager.pending_battle.is_empty():
		start_battle(ZoneManager.pending_battle)
		ZoneManager.pending_battle = {}
	else:
		_maybe_start_debug_battle()


# Debug entry point: run a specific battle directly, skipping the zone-hub
# grind - e.g. to verify a cutscene-triggering win (ZoneProgression.
# CUTSCENE_BATTLES) without playing up to it normally.
#   godot --path . res://scenes/battle_scene.tscn -- --battle=109
# Builds a throwaway save at slot -1, never persisted (GameData.save_game()
# no-ops when current_slot == -1), so a debug run can never clobber a real
# save file. is_story_progress is forced true so a cutscene battle id
# actually fires its cutscene on victory, matching the real story-fight path.
func _maybe_start_debug_battle() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--battle="):
			GameData.new_game(-1, "Debug")
			start_battle({
				"battle_id": int(arg.trim_prefix("--battle=")),
				"is_story_progress": true,
				"is_boss": false,
			})
			return


# Combat debug log -> user://logs/battle.log (see LogManagerAuto).
func _log(message: String) -> void:
	LogManagerAuto.log_to("battle", message)


func start_battle(info: Dictionary) -> void:
	battle_info = info
	battle_manager = BattleManager.new()
	add_child(battle_manager)
	battle = BattleSetup.load_battle(int(info["battle_id"]))
	if battle == null:
		push_warning("battle_scene: no battle %s" % info.get("battle_id"))
		return
	_log("=== battle %s start: %s ===" % [info.get("battle_id"), str(info)])
	var save: PlayerSave = GameData.current_save
	units = BattleSetup.build_units(
		battle, save, UnitManagerAuto.units_by_id, save.difficulty,
		int(info.get("train_cap", BattleSetup.DEFAULT_TRAIN_CAP))
	)
	for slot in units:
		var unit: CombatUnit = units[slot]
		_log("unit slot=%d name=%s lvl=%d team=%d hp=%d/%d focus=%d" % [
			slot, unit.player_name, unit.plevel, unit.team_side,
			int(unit.life_n), int(unit.life_u), int(unit.focus_n),
		])
	runner = BattleRunner.new()
	# setup()'s own return is events generated before any advance_half_turn()
	# call exists (currently just a turnTime:0 speech, if the battle has
	# one) - _battle_loop() plays these first, same as every other half-turn's
	# events, instead of them sitting unplayed (see setup()'s own comment).
	_pending_setup_events = runner.setup(
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
# hall PNGs have a transparent sky region. The sky art is a wide horizon
# STRIP (~800x140 natural), not a full-screen image - it sits with its
# bottom on the ground line, and the area above it is filled with the
# strip's own top-edge color.
const SKY_HORIZON_Y: float = 292.0

func _load_background() -> void:
	var key: String = battle.zone_background.replace(" ", "_")
	var path: String = "%s/battle/%s.png" % [BACKGROUND_ROOT, key]
	if ResourceLoader.exists(path):
		background.texture = load(path)
	var sky_key: String = key
	var sky_path: String = "%s/sky/SKY_%s.png" % [BACKGROUND_ROOT, sky_key]
	if not ResourceLoader.exists(sky_path):
		# STREETS2 -> SKY_STREETS, CHURCH2 -> SKY_CHURCH, JAIL3 -> SKY_JAIL...
		sky_key = key.rstrip("0123456789")
		sky_path = "%s/sky/SKY_%s.png" % [BACKGROUND_ROOT, sky_key]
	if not ResourceLoader.exists(sky_path):
		sky_path = "%s/sky/SKY_JAIL.png" % BACKGROUND_ROOT  # generic city glow
	if not ResourceLoader.exists(sky_path):
		return
	var sky_texture: Texture2D = load(sky_path)
	sky.texture = sky_texture
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	var strip_height: float = 800.0 * sky_texture.get_height() / sky_texture.get_width()
	sky.position = Vector2(0, SKY_HORIZON_Y - strip_height)
	sky.size = Vector2(800, strip_height)
	# Solid fill above the strip, sampled from its top edge.
	var image: Image = sky_texture.get_image()
	var top_color: Color = image.get_pixel(int(image.get_width() / 2.0), 0)
	sky_fill.color = top_color
	sky_fill.position = Vector2.ZERO
	sky_fill.size = Vector2(800, SKY_HORIZON_Y - strip_height + 2)


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
	_display_hp[slot] = unit.life_n
	_last_stun[slot] = unit.stun
	var overlay: UnitOverlay = UnitOverlayScene.instantiate()
	overlay.position = visual.position
	battlefield.add_child(overlay)
	overlay.setup(unit.player_name)
	_overlays[slot] = overlay
	_rings[slot] = overlay.ring
	overlay.ring.draw.connect(_draw_ring.bind(overlay.ring, slot))
	_health_bars[slot] = overlay.health_bar
	_health_values[slot] = overlay.health_value
	_focus_bars[slot] = overlay.focus_bar
	overlay.hit_button.mouse_entered.connect(_on_unit_hovered.bind(slot, true))
	overlay.hit_button.mouse_exited.connect(_on_unit_hovered.bind(slot, false))
	overlay.hit_button.pressed.connect(_on_unit_clicked.bind(slot))


# The original's target ring: a thick circle with four tick marks.
func _draw_ring(ring: Control, slot: int) -> void:
	var unit: CombatUnit = units.get(slot)
	if unit == null:
		return
	var color: Color = RING_COLORS[_relation_to_player(slot)]
	ring.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(color, 0.55), 7.0, true)
	ring.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 48, Color(color, 0.25), 3.0, true)
	for k in 4:
		var angle: float = k * TAU / 4.0
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
	var existing: Node = overlay.get_node_or_null("HoverInfo")
	if existing:
		existing.queue_free()
	if entered:
		var info: Label = Label.new()
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
		var usable: bool = _move_valid_for_target(move, slot)
		var orb: Button = Button.new()
		orb.custom_minimum_size = Vector2(ORB_RADIUS * 2, ORB_RADIUS * 2)
		orb.size = orb.custom_minimum_size
		var angle: float = ORB_ARC_START + i * ORB_ARC_STEP
		orb.position = Vector2.from_angle(angle) * ORB_ARC_DISTANCE - orb.size / 2.0
		orb.text = _move_initials(move)
		orb.tooltip_text = _move_tooltip(move)
		var color: Color = _move_color(move)
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
	# Not enough focus darkens the orb (picking it would waste the turn).
	var player: CombatUnit = units.get(BattleRunner.PLAYER_SLOT)
	if player != null and move.focus_cost > 0 and player.focus_n < move.focus_cost:
		return false
	var is_ally: bool = target.team_side == 1
	var is_self: bool = slot == BattleRunner.PLAYER_SLOT
	return (
		(is_self and move.can_target_self)
		or (not is_ally and move.can_target_others)
		or (is_ally and not is_self and move.targets_allies)
	)


func _move_tooltip(move: Ability) -> String:
	var cost_line: String = "This move costs nothing"
	if move.focus_cost > 0:
		cost_line = "This move costs %d Focus" % int(move.focus_cost)
	var lines: Array[Variant] = [move.display_name, cost_line]
	if move.cooldown_turns > 0:
		lines.append("Cooldown: %d turns" % move.cooldown_turns)
	return "\n".join(lines)


func _move_color(move: Ability) -> Color:
	var element_index: int = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


func _move_initials(move: Ability) -> String:
	var words: PackedStringArray = move.display_name.split(" ", false)
	if words.size() >= 2:
		return words[0].substr(0, 1) + words[1].substr(0, 1)
	return move.display_name.substr(0, 2)


func _style_orb(orb: Button, color: Color, usable: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		var bg: Color = Color(0.08, 0.08, 0.1) if usable else Color(0.05, 0.05, 0.06)
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


# A click on a unit's hit_button or an orb Button is consumed by that Button
# before it ever gets here (both are real Buttons, not mouse_filter=IGNORE) -
# _unhandled_input only ever fires for a click that landed on neither, i.e.
# empty battlefield space. There was previously no close-on-click-away at
# all (only _on_unit_clicked's own _close_radial_menu() when a DIFFERENT
# unit is clicked next).
func _unhandled_input(event: InputEvent) -> void:
	if _radial_menu == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_radial_menu()


# --- bottom bar: stances + pass ring + retreat -----------------------------

func _draw_pass_ring() -> void:
	var active: bool = _player_action_pending
	var color: Color = Color(0.4, 0.75, 1.0, 0.95) if active else Color(0.35, 0.35, 0.38, 0.7)
	_pass_ring.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 64, color, 5.0, true)
	if active:
		_pass_ring.draw_arc(Vector2.ZERO, 41.0, 0.0, TAU, 64, Color(0.4, 0.75, 1.0, 0.35), 7.0, true)


func _populate_stance_rows() -> void:
	for child in stance_host.get_children():
		child.queue_free()
	_stance_rows.clear()
	var save: PlayerSave = GameData.current_save
	var row_y: float = 0.0
	for slot in [3, 5]:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		var party_id: int = _party_id_for_unit(unit)
		if party_id <= 0:
			continue
		var row: StanceRow = StanceRowScene.instantiate()
		row.position = Vector2(0, row_y)
		stance_host.add_child(row)
		row.setup(unit.player_name)
		var buttons: Array = row.buttons
		for mode in buttons.size():
			buttons[mode].pressed.connect(_on_stance_pressed.bind(party_id, mode, slot))
		_stance_rows[party_id] = buttons
		_refresh_stance_row(party_id, Party.get_ag_mode(save, party_id) if save != null else 2)
		row_y += 46.0


# Stance tint runs green (hold back) to red (all in), like the original's
# five icons.
func _refresh_stance_row(party_id: int, selected_mode: int) -> void:
	var colors: Array[Variant] = [
		Color(0.25, 0.55, 0.3), Color(0.35, 0.55, 0.25), Color(0.6, 0.55, 0.2),
		Color(0.65, 0.35, 0.15), Color(0.65, 0.15, 0.12),
	]
	var buttons: Array = _stance_rows.get(party_id, [])
	for mode in buttons.size():
		var button: Button = buttons[mode]
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = colors[mode]
		style.set_corner_radius_all(3)
		style.set_border_width_all(2)
		style.border_color = Color.WHITE if mode == selected_mode else Color(0.15, 0.15, 0.15)
		button.add_theme_stylebox_override("normal", style)
		var hover: Resource = style.duplicate()
		hover.bg_color = colors[mode].lightened(0.2)
		button.add_theme_stylebox_override("hover", hover)


func _party_id_for_unit(unit: CombatUnit) -> int:
	for party_id in Party.COMPANIONS:
		if Party.COMPANIONS[party_id]["name"] == unit.player_name:
			return party_id
	return -1


func _on_stance_pressed(party_id: int, mode: int, slot: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save != null:
		Party.set_ag_mode(save, party_id, mode)
	var unit: CombatUnit = units.get(slot)
	if unit != null:
		Party.apply_aggression_mode(unit, mode)
	_refresh_stance_row(party_id, mode)


# --- turn loop ---------------------------------------------------------------

func _battle_loop() -> void:
	if not _pending_setup_events.is_empty():
		await _play_events(_pending_setup_events)
		_pending_setup_events = []
	while not runner.is_over():
		if runner.is_player_turn():
			_player_action_pending = true
			turn_label.text = "Your move"
			_log("half-turn %d: waiting for player" % runner.turn_count)
			_pass_ring.queue_redraw()
			while _player_action_pending:
				if not is_inside_tree():
					return  # retreat freed the scene mid-wait
				await get_tree().process_frame
		else:
			turn_label.text = "Enemy turn" if runner.team_move_now == 2 else "Ally turn"
			_log("half-turn %d: AI side %d acts" % [runner.turn_count, runner.team_move_now])
			await _pause(0.4)
		if not is_inside_tree() or _finished:
			return
		_pass_ring.queue_redraw()
		var action: Dictionary = _selected_move.duplicate()
		_selected_move = {}
		if not action.is_empty():
			_log("player action: %s" % str(action))
		_close_radial_menu()
		var events: Array = runner.advance_half_turn(action)
		_log("advance_half_turn -> %d events" % events.size())
		for event in events:
			_log("  event: %s" % JSON.stringify(event))
		await _play_events(events)
		if not is_inside_tree() or _finished:
			return
		_refresh_bars()
	_log("battle over: outcome=%d turns=%d" % [runner.win_condition, runner.turn_count])
	_finish_battle()


func _on_pass_pressed() -> void:
	if not _player_action_pending:
		return
	_selected_move = {}
	_close_radial_menu()
	_player_action_pending = false


# Retreat abandons the fight and returns to the save-select screen.
func _on_retreat_pressed() -> void:
	if _finished:
		return
	_finished = true
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Replays a half-turn's event log with animation + audio pacing.
func _play_events(events: Array) -> void:
	for event in events:
		match event["type"]:
			"move":
				await _play_move_event(event)
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
		# Mid-batch: redraw from DISPLAYED hp only - snapping here would
		# reveal damage from hits that haven't animated yet.
		_refresh_bars(false)


func _play_move_event(event: Dictionary) -> void:
	var caster_slot: int = int(event["caster_slot"])
	var target_slot: int = int(event["target_slot"])
	var move: Ability = MoveManagerAuto.get_move(int(event["move_id"]))
	var caster_visual: CharacterVisual = _visuals.get(caster_slot)
	# Only Melee moves run and swing; the original plays "cast" for both
	# Missile and Shock (param 12 is the projectile clip for Missiles, and
	# unused for Shock) - see DECODED_ALGORITHMS.md.
	if caster_visual != null and move != null and move.attack_animation_type == "Melee":
		# The original order: run to the target, swing, damage lands at the
		# blow, THEN run back. Impact effects hook attack_connected.
		var start_ms: int = Time.get_ticks_msec()
		var on_impact: Callable = func():
			_log("melee impact: caster=%d move=%s +%dms" % [
				caster_slot, move.display_name, Time.get_ticks_msec() - start_ms,
			])
			AudioManagerAuto.play_effect(move.sound_effect_name)
			_show_move_result(event, target_slot)
		caster_visual.attack_connected.connect(on_impact, CONNECT_ONE_SHOT)
		_log("melee start: caster=%d target=%d move=%s label=%s" % [
			caster_slot, target_slot, move.display_name, move.animation_label,
		])
		caster_visual.play_melee(_melee_offset(caster_slot, target_slot), move.animation_label)
		if animation_speed > 0.0:
			await caster_visual.melee_finished
			if not is_inside_tree():
				return
			_log("melee finished: caster=%d +%dms" % [caster_slot, Time.get_ticks_msec() - start_ms])
		# Interrupted sequence (or instant mode, which never runs _process):
		# the blow never fired - land the result anyway.
		if caster_visual.attack_connected.is_connected(on_impact):
			caster_visual.attack_connected.disconnect(on_impact)
			_log("melee impact flushed late (interrupted/instant): caster=%d" % caster_slot)
			on_impact.call()
		await _pause(0.15)
		return
	if caster_visual != null and move != null:
		_log("cast start: caster=%d target=%d move=%s type=%s" % [
			caster_slot, target_slot, move.display_name, move.attack_animation_type,
		])
		caster_visual.set_state(CharacterVisual.State.CAST)
		# Approximates the original's colortobe glow tint (not decoded - see
		# DECODED_ALGORITHMS.md) with the move's element color; set_state()
		# resets modulate back to white when the cast label finishes.
		caster_visual.modulate = _move_color(move).lerp(Color.WHITE, 0.4)
		if move.attack_animation_type == "Shock":
			# Shock: sound, the BOOM clip, and impact (BAMBAMBAM) all fire in
			# the same tick as gotoAndPlay("cast") - the doll's cast animation
			# plays out cosmetically but the hit lands immediately, no wait.
			AudioManagerAuto.play_effect(move.sound_effect_name)
			_show_move_result(event, target_slot)
			await _pause(0.35)
			return
		if move.attack_animation_type == "Missile":
			# Missile: sfx_cast plays at cast start, then a krinBoltMake bolt
			# flies to the target - impact lands on ARRIVAL, not on a fixed
			# cast-clip time (the bolt's own accel/arrival model decides it).
			AudioManagerAuto.play_effect("sfx_cast")
			await _fire_projectile(caster_slot, target_slot, move)
			if not is_inside_tree():
				return
			AudioManagerAuto.play_effect(move.sound_effect_name)
			_show_move_result(event, target_slot)
			await _pause(0.2)
			return
		AudioManagerAuto.play_effect("sfx_cast")
		await _pause(0.25)
	if move != null:
		AudioManagerAuto.play_effect(move.sound_effect_name)
	_show_move_result(event, target_slot)
	await _pause(0.35)


# krinBoltMake port: an accelerating bolt (Projectile) that flies from the
# caster to the target and self-destructs on arrival. Tests run with
# animation_speed <= 0 - skip the visual flight entirely there (no _process
# tick would ever advance it).
func _fire_projectile(caster_slot: int, target_slot: int, move: Ability) -> void:
	if animation_speed <= 0.0:
		return
	var from: Vector2 = SLOT_POSITIONS.get(caster_slot, Vector2(400, 300))
	var to: Vector2 = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	var bolt := Projectile.new()
	bolt.color = _move_color(move)
	battlefield.add_child(bolt)
	bolt.start(from, to)
	await bolt.arrived


func _show_move_result(event: Dictionary, target_slot: int) -> void:
	var result: Dictionary = event.get("result", {})
	var target_visual: CharacterVisual = _visuals.get(target_slot)
	var target_unit: CombatUnit = units.get(target_slot)
	var move: Ability = MoveManagerAuto.get_move(int(event.get("move_id", 0)))
	if target_unit != null:
		_log("result shown: %s target=%d (%s) hp=%d/%d" % [
			JSON.stringify(result), target_slot, target_unit.player_name,
			int(target_unit.life_n), int(target_unit.life_u),
		])
	match result.get("type", ""):
		"damage":
			# KrinNumberShow: numbers colored by the move's ELEMENT; crits
			# play the bigger "critical" variant of the same color.
			var color: Color = Color.WHITE
			if move != null:
				var element_index: int = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
				if element_index != -1:
					color = MenuTheme.ELEMENT_COLORS[element_index]
			_float_text(target_slot, str(int(result.get("amount", 0))), color, result.get("did_crit", false))
			# The bar drops exactly when the hit lands on screen.
			_display_hp[target_slot] = maxf(
				_display_hp.get(target_slot, 0.0) - float(result.get("amount", 0)), 0.0
			)
			if target_visual != null and not result.get("target_died", false):
				target_visual.set_state(CharacterVisual.State.HIT)
			if target_unit != null:
				AudioManagerAuto.voice(target_unit.voice_hit)
		"heal":
			_float_text(target_slot, "+%d" % int(result.get("amount", 0)), MenuTheme.HEAL_COLOR)
			if target_unit != null:
				_display_hp[target_slot] = minf(
					_display_hp.get(target_slot, 0.0) + float(result.get("amount", 0)),
					target_unit.life_u
				)
		"focus":
			_float_text(target_slot, "+%d FOCUS" % int(result.get("amount", 0)), Color.SKY_BLUE)
		"miss":
			# The special miss frame KrinNumberShow swaps to at impact,
			# instead of a damage number - the caster's own animation still
			# played in full to get here (see _execute_move_action's comment).
			_float_text(target_slot, "MISS", Color.GRAY)
			AudioManagerAuto.play_effect("sfx_magicmiss")
	_refresh_bars(false)


# Run-to-target offset for a melee strike: stop just short of the target,
# on the caster's side of it.
func _melee_offset(caster_slot: int, target_slot: int) -> Vector2:
	var from: Vector2 = SLOT_POSITIONS.get(caster_slot, Vector2(400, 300))
	var to: Vector2 = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	var offset: Vector2 = to - from
	if offset.length() <= 60.0:
		return Vector2.ZERO
	return offset - offset.normalized() * 55.0


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


# snap = true syncs the displayed hp to the true values (half-turn
# boundaries - covers DOTs, life costs, shields); snap = false only redraws
# from the displayed values (mid-batch, so unplayed hits stay hidden).
func _refresh_bars(snap: bool = true) -> void:
	for slot in _visuals:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		if snap and int(_display_hp.get(slot, 0)) != int(unit.life_n):
			_log("bar snap: slot=%d (%s) hp %d -> %d" % [
				slot, unit.player_name, int(_display_hp.get(slot, 0)), int(unit.life_n),
			])
		if snap:
			_display_hp[slot] = unit.life_n
		var health: ProgressBar = _health_bars[slot]
		health.max_value = unit.life_u
		health.value = _display_hp.get(slot, unit.life_n)
		_health_values[slot].text = str(int(_display_hp.get(slot, unit.life_n)))
		var focus: ProgressBar = _focus_bars[slot]
		focus.max_value = max(unit.focus_u, 1)
		focus.value = unit.focus_n
		_update_stun_visual(slot, unit, _visuals[slot])


# krinBuff STUN is a running total across active stun-inflicting buffs -
# replay "stun" on any increase (including stacking while already stunned),
# "outofstun" on any decrease (even a partial one that leaves the unit still
# stunned by a shorter-lived buff); both labels flow back to idle/stun2 on
# their own once triggered (see DECODED_ALGORITHMS.md).
func _update_stun_visual(slot: int, unit: CombatUnit, visual: CharacterVisual) -> void:
	var current: float = unit.stun if unit.active else 0.0
	var previous = _last_stun.get(slot, 0.0)
	if current > previous:
		visual.enter_stun()
	elif current < previous:
		visual.exit_stun()
	_last_stun[slot] = current


func _float_text(slot: int, text: String, color: Color, critical: bool = false) -> void:
	var visual: CharacterVisual = _visuals.get(slot)
	if visual == null:
		return
	var label: Label = Label.new()
	label.text = text
	label.modulate = color
	label.position = visual.position + Vector2(-15, -72)
	label.scale = Vector2.ONE
	if critical:
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 4)
	battlefield.add_child(label)
	if animation_speed <= 0.0:
		label.queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func _finish_battle() -> void:
	if _finished:
		return
	_finished = true
	var save: PlayerSave = GameData.current_save
	var outcome: int = runner.win_condition
	if outcome == BattleRunner.Outcome.WIN and save != null:
		var was_story = battle_info.get("is_story_progress", false)
		var battle_result: Dictionary = ZoneProgression.after_battle_won(save, battle.id, was_story)
		_pending_cutscene = battle_result.get("cutscene", "")
		_pending_goto_scene = battle_result.get("goto_scene", "")
		var enemy_levels: Array = BattleRewards.unit_levels_from_slots(units, [2, 4, 6])
		var fighting_party: Array[Variant] = []
		for marker in [-2, -1]:
			var party_id: int = Party.deployed_party_id(save, marker)
			if party_id > 0:
				fighting_party.append(party_id)
		var rewards: Dictionary = BattleRewards.apply_victory(save, enemy_levels, enemy_levels, fighting_party)
		var drops: Array = BattleRewards.roll_drops(battle)
		var counters: Dictionary = Achievements.collect_battle_counters(runner, units)
		for achievement_id in Achievements.check_battle_victory(save, battle.id, was_story, counters):
			Achievements.unlock(achievement_id)
		# Drops are click-to-keep on the victory screen (VICTORY[1]); the
		# autosave happens on Proceed, like the original.
		var victory: VictoryScreen = preload("res://scenes/battle/victory_screen.tscn").instantiate()
		victory.name = "VictoryScreen"
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
	if not _pending_cutscene.is_empty():
		# Cleared before the await, not after: Proceed stays clickable for one
		# more frame while the player is being built, and a second press must
		# not start a second copy of the same clip on top of the first.
		var cutscene_id: String = _pending_cutscene
		var goto_scene: String = _pending_goto_scene
		_pending_cutscene = ""
		_pending_goto_scene = ""
		# The original silences the battle track before jumping to a cutscene
		# (DefineButton2_3004's release handler calls stopAllSounds); without
		# this the battle music keeps playing under the cutscene's own audio
		# until _on_continue_pressed() swaps in the menu track afterwards.
		AudioManagerAuto.stop_music()
		var cutscene: CutscenePlayer = preload("res://scenes/cutscenes/cutscene_player.tscn").instantiate()
		cutscene.animation_speed = animation_speed
		add_child(cutscene)
		await cutscene.play(cutscene_id)
		# Matches gotoSceneKrin (frame_219): a cutscene that just unlocked a
		# new zone opens the zone map on landing instead of the same hub.
		if goto_scene == "overMap":
			ZoneManager.open_zone_map_on_load = true
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _pause(seconds: float) -> void:
	if animation_speed <= 0.0:
		return
	await get_tree().create_timer(seconds / animation_speed).timeout
