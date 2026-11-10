# battle_scene.gd
# The playable battle screen - glues the headless stack (BattleSetup ->
# BattleRunner -> BattleRewards/ZoneProgression/Achievements) to visuals
# (one FighterPresenter per slot), input, and audio.
#
# Interaction model matches the original (frame 217 KRIN_BATTLE_SCENE):
# - hover a unit: a target ring glows under it (white = you, green = ally,
#   red = enemy) with "Lvl. N" and the name
# - click a unit on your turn: your bar's abilities fan out around it as
#   orbs (RadialMenu); unusable ones (wrong target, focus, cooldown) are darkened;
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

const FighterPresenterScene: PackedScene = preload("res://scenes/battle/fighter_presenter.tscn")
const StanceRowScene: PackedScene = preload("res://scenes/battle/stance_row.tscn")
const ProjectileScene: PackedScene = preload("res://scenes/battle/projectile.tscn")
const ImpactEffectScene: PackedScene = preload("res://scenes/battle/impact_effect.tscn")
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

# 1.0 = normal pacing; 0.0 = instant (tests).
var animation_speed: float = 1.0

var runner: BattleRunner
var battle_manager: BattleManager
var battle: BattleFight
var units: Dictionary = {}
var battle_info: Dictionary = {}

var _presenters: Dictionary = {}  # slot -> FighterPresenter
var _stance_rows: Dictionary = {}  # party_id -> StanceRow
var _selected_move: Dictionary = {}
# True while the turn loop waits for the player's pick. The menu follows it
# through this setter, so a pick, a pass and the Heroic timeout all close the
# menu by clearing it.
var decision_open: bool = false:
	set(value):
		decision_open = value
		radial_menu.decision_open = value
# How many seconds the player has left to pick on Heroic. The original's
# conductor adds 1 to BattleTimeNow every frame while the player's team decides
# and starts the half-turn when it reaches BattleTimeLimit, whether or not the
# player picked (frame_217/PlaceObject2_3389_480 enterFrame, lines 593-596 and
# 769-792), so _process passes for the player when this reaches 0.
var _decision_timer: float = 0.0
# Mirrors the original's turnBasedKrin, which is true on Easy and Normal
# (frame_201/DoAction.as:65-79) and becomes true for the rest of the battle once
# a half-turn ends with the player's unit dead (conductor lines 200-202). While
# it is true the decision waits for the player and the countdown label is
# hidden, because the original's clock does not move then.
var _turn_based: bool = true
var _finished: bool = false
var _pending_cutscene: String = ""  # set by _finish_battle() on a cutscene-triggering win
var _pending_goto_scene: String = ""  # ZoneProgression.CUTSCENE_GOTO_SCENE for that cutscene
var _pending_setup_events: Array = []  # runner.setup()'s return - played first by _battle_loop()
# The SPEECH event _play_speech has on screen, or {} when no line is up.
var _line_on_screen: Dictionary = {}
# The original's hardSkip. Space sets it during a line, and _play_events then
# drops the rest of that batch's lines, until its next call clears it.
var _hard_skip: bool = false
var _pause_timer: SceneTreeTimer = null  # the running _pause's timer, which Space runs out during a line

@onready var background: TextureRect = $Background
@onready var sky: TextureRect = $Sky
@onready var sky_fill: ColorRect = $SkyFill
@onready var battlefield: Node2D = $Battlefield
@onready var turn_label: Label = $UI/TurnLabel
@onready var speech_label: Label = $UI/SpeechLabel
@onready var _pass_ring: Control = $BottomBar/PassRing
@onready var radial_menu: RadialMenu = $RadialMenu
@onready var stance_host: Control = $BottomBar/StanceHost
@onready var _countdown_label: Label = $BottomBar/Panel3/CountdownLabel
@onready var _combat_log: CombatLogPanel = $CombatLogPanel


func _ready():
	speech_label.text = ""
	# The retreat button is the original's battle Quit button,
	# DefineButton2_3356, which shows SYSTEM[25] over SYSTEM[26]
	# (frame_1/DoAction.as:92-93). The pass button, DefineButton2_3383, shows
	# no tooltip in the original and the original has no log toggle, so both
	# keep the port's own native tooltips.
	var retreat: Button = $BottomBar/RetreatButton
	var quit_sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Quit", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": "Click here to exit. Warning! All unsaved progress will be lost!", "color": TooltipTheme.TEXT_BODY}]},
	]
	retreat.mouse_entered.connect(func(): GameTooltip.show_sections(quit_sections, retreat))
	retreat.mouse_exited.connect(GameTooltip.hide_tooltip)
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


func _process(delta: float) -> void:
	if decision_open and not _turn_based:
		_decision_timer = maxf(_decision_timer - delta, 0.0)
		if _decision_timer == 0.0:
			_on_pass_pressed()
	_countdown_label.visible = not _turn_based
	_countdown_label.text = str(int(ceil(_decision_timer)))


func _reset_decision_timer() -> void:
	_decision_timer = BattleRunner.BATTLE_TIME_LIMIT / 30.0


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
	_turn_based = save.difficulty != CombatUnit.Difficulty.HARD
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
	radial_menu.setup(units, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id)
	_load_background()
	_spawn_visuals()
	_populate_stance_rows()
	AudioManagerAuto.play_battle_music(info.get("is_boss", false))
	_battle_loop.call_deferred()


# The original composites a sky layer behind the hall art; the hall PNGs have a
# transparent sky region. The sky art is a wide horizon STRIP, not a
# full-screen image - it sits with its bottom on the ground line, and the area
# above it is filled with SKY_FILL_COLOR.
#
# The hall and the sky are two independent per-battle fields, not one key: the
# original drives DefineSprite 3435 from Krin.ZoneBG and DefineSprite 3454 from
# Krin.SkyBG, and 16 of its 99 battles set them to different labels. Zone 6
# fights in the CHURCH hall under the ROME sky, one STREETS fight uses the
# TUNNEL sky, and WHITE NOVEMBER uses SEA.
#
# Where the strip sits comes from battle_layout.json, which extract_battle_screen
# writes out of the SWF's own placements. A tuned constant used to stand in for
# it and put every sky's ground line at y = 292.0; the real line differs per
# label, and ROME's is at 306.0.
const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"

# What the original shows above the strip. The battle frame places DefineShape
# 333, a solid black rect, under the sky, and a render of the frame reads
# (0, 0, 0) at every pixel between that rect's top edge at y = 130 and the sky.
# Do not sample the sky art for it instead: the SWF renders are trimmed to their
# own soft top edge, so five of the nine skies read alpha 0 at row 0 centre and
# SEA reads 0.37.
const SKY_FILL_COLOR: Color = Color.BLACK

var _battle_layout: Dictionary = {}


# -> {x, y, w, h} for one sky label, or {} when the JSON has no entry for it.
func _sky_rect(sky_key: String) -> Dictionary:
	if _battle_layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		_battle_layout = JSON.parse_string(file.get_as_text())
	return _battle_layout.get("skies", {}).get(sky_key, {})


func _load_background() -> void:
	var key: String = battle.zone_background.replace(" ", "_")
	var path: String = "%s/battle/%s.png" % [BACKGROUND_ROOT, key]
	if ResourceLoader.exists(path):
		background.texture = load(path)
	var sky_key: String = battle.sky_background.replace(" ", "_")
	var sky_path: String = "%s/sky/SKY_%s.png" % [BACKGROUND_ROOT, sky_key]
	if not ResourceLoader.exists(sky_path):
		# All nine sky labels the battle records use have art, so a miss here
		# is a real gap rather than something to substitute around.
		push_error("no sky art for %s (battle %d)" % [sky_key, battle.id])
		return
	var sky_texture: Texture2D = load(sky_path)
	var rect: Dictionary = _sky_rect(sky_key)
	if rect.is_empty():
		push_error("no layout entry for sky %s (battle %d)" % [sky_key, battle.id])
		return
	sky.texture = sky_texture
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.position = Vector2(float(rect["x"]), float(rect["y"]))
	sky.size = Vector2(float(rect["w"]), float(rect["h"]))
	sky_fill.color = SKY_FILL_COLOR
	sky_fill.position = Vector2.ZERO
	sky_fill.size = Vector2(800, float(rect["y"]) + 2.0)


func _spawn_visuals() -> void:
	for slot in units:
		var home: Vector2 = SLOT_POSITIONS.get(slot, Vector2(400, 300))
		var presenter: FighterPresenter = FighterPresenterScene.instantiate()
		battlefield.add_child(presenter)
		presenter.setup(units[slot], home, ItemManagerAuto.items_by_id, BuffManagerAuto.buffs_by_id, battlefield)
		presenter.voice_cue.connect(AudioManagerAuto.voice)
		presenter.effect_cue.connect(AudioManagerAuto.play_effect)
		presenter.hit_area.mouse_entered.connect(_on_unit_hovered.bind(slot, true))
		presenter.hit_area.mouse_exited.connect(_on_unit_hovered.bind(slot, false))
		presenter.hit_area.pressed.connect(radial_menu.open.bind(slot, home, presenter.hit_area))
		_presenters[slot] = presenter


func _on_unit_hovered(slot: int, entered: bool) -> void:
	_presenters[slot].show_hover(entered and decision_open)


func _move_color(move: Ability) -> Color:
	var element_index: CombatUnit.Element = move.damage_element_type
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


# BOOM_*/ex_* impact clip at the target, gated on result.type != MISS -
# matching frame_42/DoAction_4.as's krinBoltMake, which only attaches its
# impact clip if(_root.strikeSuccess).
func _spawn_impact(target_slot: int, move: Ability, result: Dictionary) -> void:
	if move == null or move.impact_effect_name.is_empty():
		return
	if result.get("type") == BattleManager.ResultType.MISS:
		return
	var effect: ImpactEffect = ImpactEffectScene.instantiate()
	effect.position = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	battlefield.add_child(effect)
	effect.play(move.impact_effect_name)


func _on_radial_move_picked(bar_index: int, move_id: int, target_slot: int) -> void:
	_selected_move = {"bar_index": bar_index, "move_id": move_id, "target_slot": target_slot}
	decision_open = false


# --- bottom bar: stances + pass ring + retreat -----------------------------

func _draw_pass_ring() -> void:
	var active: bool = decision_open
	var color: Color = Color(0.4, 0.75, 1.0, 0.95) if active else Color(0.35, 0.35, 0.38, 0.7)
	_pass_ring.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 64, color, 5.0, true)
	if active:
		_pass_ring.draw_arc(Vector2.ZERO, 41.0, 0.0, TAU, 64, Color(0.4, 0.75, 1.0, 0.35), 7.0, true)


func _populate_stance_rows() -> void:
	for child in stance_host.get_children():
		child.queue_free()
	_stance_rows.clear()
	var row_y: float = 0.0
	# Slot 5 first: the original's member bar container places its "p5" copy
	# above its "p3" copy (DefineSprite 3312, y 12.60 vs y 50.10), matching the
	# battlefield where slot 5 is the upper fighter and slot 3 the lower one.
	for slot in [5, 3]:
		var unit: CombatUnit = units.get(slot)
		# Only a companion gets a row. The original fills the bar from whoever
		# is active in slots 3 and 5 at each Decision, but no guest's row ever
		# appears there: DECODED_ALGORITHMS.md has why.
		if unit == null or unit.origin != CombatUnit.Origin.COMPANION:
			continue
		var party_id: int = unit.party_id
		var row: StanceRow = StanceRowScene.instantiate()
		row.position = Vector2(0, row_y)
		stance_host.add_child(row)
		row.setup(unit.player_name)
		for mode in row.buttons.size():
			row.buttons[mode].pressed.connect(_on_stance_pressed.bind(party_id, mode, slot))
		_stance_rows[party_id] = row
		# Party.build_companion_unit starts every companion on Tactical, so
		# that is the stance each row shows until a button is pressed.
		_refresh_stance_row(party_id, Party.AggressionStance.TACTICAL)
		row_y += StanceRow.row_pitch()


func _refresh_stance_row(party_id: int, selected_mode: Party.AggressionStance) -> void:
	var row: StanceRow = _stance_rows.get(party_id)
	if row != null:
		row.set_selected(selected_mode)


func _on_stance_pressed(party_id: int, mode: Party.AggressionStance, slot: int) -> void:
	var unit: CombatUnit = units.get(slot)
	if unit != null:
		Party.apply_aggression_mode(unit, mode)
	_refresh_stance_row(party_id, mode)


# --- turn loop ---------------------------------------------------------------

# The conductor starts every battle with timerWait at 30 and counts it down a
# frame at a time, and its whole decision block waits for 0, the opening lines
# included (frame_217/PlaceObject2_3389_480 onClipEvent(load), line 6, and
# enterFrame, lines 5-8 and 589). That is a second at the SWF's 30 fps.
const START_WAIT_SECONDS: float = 30.0 / 30.0


func _battle_loop() -> void:
	await _pause(START_WAIT_SECONDS)
	if not is_inside_tree() or _finished:
		return
	if not _pending_setup_events.is_empty():
		await _play_events(_pending_setup_events)
		_pending_setup_events = []
	while not runner.is_over():
		if runner.is_player_turn():
			decision_open = true
			_reset_decision_timer()
			turn_label.text = "Your move"
			_log("half-turn %d: waiting for player" % runner.turn_count)
			_pass_ring.queue_redraw()
			while decision_open:
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
		var events: Array = runner.advance_half_turn(action)
		_log("advance_half_turn -> %d events" % events.size())
		for event in events:
			_log("  event: %s" % JSON.stringify(event))
		await _play_events(events)
		if not is_inside_tree() or _finished:
			return
		_refresh_bars()
		var player: CombatUnit = units.get(BattleRunner.PLAYER_SLOT)
		if player == null or not player.active:
			_turn_based = true
	_log("battle over: outcome=%d turns=%d" % [runner.win_condition, runner.turn_count])
	_finish_battle()


func _on_pass_pressed() -> void:
	if not decision_open:
		return
	_selected_move = {}
	decision_open = false


func _on_log_toggle_pressed() -> void:
	_combat_log.toggle()


# Retreat abandons the fight and returns to the save-select screen.
func _on_retreat_pressed() -> void:
	if _finished:
		return
	_finished = true
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Replays a half-turn's event log with animation + audio pacing.
func _play_events(events: Array) -> void:
	_hard_skip = false
	for event in events:
		if _hard_skip and event["type"] == BattleRunner.EventType.SPEECH:
			continue
		_combat_log.append_event(event, units)
		match event["type"]:
			BattleRunner.EventType.MOVE:
				await _play_move_event(event)
			BattleRunner.EventType.STUNNED:
				_presenters[int(event["caster_slot"])].float_text("STUNNED", Color.YELLOW)
				await _pause(0.3)
			BattleRunner.EventType.MOVE_FAILED:
				_presenters[int(event["caster_slot"])].float_text("NOT ENOUGH %s" % str(event.get("reason", "")).to_upper(), Color.ORANGE)
				await _pause(0.3)
			BattleRunner.EventType.DISPEL:
				_presenters[int(event["target_slot"])].float_text("DISPEL", Color.CYAN)
			BattleRunner.EventType.DEATH:
				# A move-caused death already played at the killing blow's
				# impact (see FighterPresenter.show_result) - only the pacing
				# pause still belongs here. damage_over_time deaths (buff
				# ticks, not a move) have no impact moment to hook into, so
				# they still play here, same as always.
				if event.get("cause") != BattleRunner.DeathCause.MOVE:
					_presenters[int(event["slot"])].die()
				await _pause(0.4)
			BattleRunner.EventType.SPEECH:
				await _play_speech(event)
			BattleRunner.EventType.PHASE_ADVANCED:
				AudioManagerAuto.play_battle_music(true)
			BattleRunner.EventType.BATTLE_ENDED:
				pass
		# Mid-batch: redraw from DISPLAYED hp only - snapping here would
		# reveal damage from hits that haven't animated yet.
		_refresh_bars(false)


func _play_move_event(event: Dictionary) -> void:
	var caster_slot: int = int(event["caster_slot"])
	var target_slot: int = int(event["target_slot"])
	var move: Ability = MoveManagerAuto.get_move(int(event["move_id"]))
	var caster: FighterPresenter = _presenters.get(caster_slot)
	# Only Melee moves run and swing; the original plays "cast" for both
	# Missile and Shock (param 12 is the projectile clip for Missiles, and
	# unused for Shock) - see DECODED_ALGORITHMS.md.
	if caster != null and move != null and move.attack_animation_type == "Melee":
		# The original order: run to the target, swing, damage lands at the
		# blow, THEN run back.
		var start_ms: int = Time.get_ticks_msec()
		var on_impact: Callable = func():
			_log("melee impact: caster=%d move=%s +%dms" % [
				caster_slot, move.display_name, Time.get_ticks_msec() - start_ms,
			])
			AudioManagerAuto.play_effect(move.sound_effect_name)
			_spawn_impact(target_slot, move, event.get("result", {}))
			_show_move_result(event, target_slot)
		_log("melee start: caster=%d target=%d move=%s label=%s" % [
			caster_slot, target_slot, move.display_name, move.animation_label,
		])
		var flushed: bool = await caster.melee(_melee_offset(caster_slot, target_slot), move.animation_label, on_impact, animation_speed > 0.0)
		if not is_inside_tree():
			return
		if animation_speed > 0.0:
			_log("melee finished: caster=%d +%dms" % [caster_slot, Time.get_ticks_msec() - start_ms])
		if flushed:
			_log("melee impact flushed late (interrupted/instant): caster=%d" % caster_slot)
		await _pause(0.15)
		return
	if caster != null and move != null:
		_log("cast start: caster=%d target=%d move=%s type=%s" % [
			caster_slot, target_slot, move.display_name, move.attack_animation_type,
		])
		caster.cast(move)
		if move.attack_animation_type == "Shock":
			# Shock: sound, the BOOM clip, and impact (BAMBAMBAM) all fire in
			# the same tick as gotoAndPlay("cast") - the doll's cast animation
			# plays out cosmetically but the hit lands immediately, no wait.
			AudioManagerAuto.play_effect(move.sound_effect_name)
			_spawn_impact(target_slot, move, event.get("result", {}))
			_show_move_result(event, target_slot)
			await _pause(0.35)
			return
		if move.attack_animation_type == "Missile":
			# Missile: sfx_cast plays at cast start, then a krinBoltMake bolt
			# flies to the target - impact lands when the bolt REACHES the
			# target, not on a fixed cast-clip time (the bolt's own
			# accel/arrival model decides it).
			AudioManagerAuto.play_effect("sfx_cast")
			await _fire_projectile(caster_slot, target_slot, move, event.get("result", {}))
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
# caster to the target, then spawns the move's impact effect there. On a
# hit the bolt destroys itself the moment it arrives; on a miss it keeps
# flying past the target and only frees once it leaves the canvas. Tests
# run with animation_speed <= 0 - skip the visual flight entirely there
# (no _process tick would ever advance it).
func _fire_projectile(caster_slot: int, target_slot: int, move: Ability, result: Dictionary) -> void:
	if animation_speed <= 0.0:
		return
	var from: Vector2 = SLOT_POSITIONS.get(caster_slot, Vector2(400, 300))
	var to: Vector2 = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	var bolt: Projectile = ProjectileScene.instantiate()
	bolt.color = _move_color(move)  # fallback tinted-circle color if clip_name has no real asset
	bolt.clip_name = move.animation_label
	bolt.trail_color = move.visual_effect_color
	bolt.did_hit = result.get("type") != BattleManager.ResultType.MISS
	battlefield.add_child(bolt)
	bolt.start(from, to)
	await bolt.reached_target
	_spawn_impact(target_slot, move, result)


func _show_move_result(event: Dictionary, target_slot: int) -> void:
	var result: Dictionary = event.get("result", {})
	var target_unit: CombatUnit = units[target_slot]
	_log("result shown: %s target=%d (%s) hp=%d/%d" % [
		JSON.stringify(result), target_slot, target_unit.player_name,
		int(target_unit.life_n), int(target_unit.life_u),
	])
	_presenters[target_slot].show_result(result, MoveManagerAuto.get_move(int(event.get("move_id", 0))))
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


# A line stays up for its whole timeToSay seconds, unless Space cuts it short
# (see _input). The original's speech box adds 30 / fps to a counter every frame
# and lets the next line through once it reaches timeToSay * 30
# (frame_217/PlaceObject2_3389_480 enterFrame, line 841, and
# frame_217/PlaceObject2_3367_634 enterFrame, lines 13-17).
func _play_speech(event: Dictionary) -> void:
	speech_label.text = "%s: %s" % [event["speaker_name"], event.get("say", "")]
	AudioManagerAuto.play_effect(str(event.get("voice_over", "")))
	_line_on_screen = event
	await _pause(float(event.get("time_to_say", 2.0)))
	_line_on_screen = {}
	speech_label.text = ""


# The original's speech box answers Space all through a battle
# (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines 2-9). It stops
# the three effect channels, and while a line is up it ends that line and sets
# hardSkip, which drops the rest of the conversation (BattleRunner.hard_skip).
# The project has no input action for it, and Godot's ui_accept and ui_select
# also fire on Enter or a gamepad button, so this checks the key itself, as
# Key.isDown(32) does.
func _input(event: InputEvent) -> void:
	if _finished or not (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		return
	AudioManagerAuto.stop_effects()
	if _line_on_screen.is_empty():
		return
	_hard_skip = true
	runner.hard_skip(int(_line_on_screen["speech_index"]))
	if _pause_timer != null:
		_pause_timer.time_left = 0.0
	get_viewport().set_input_as_handled()


# snap = true syncs the displayed hp to the true values (half-turn
# boundaries - covers DOTs, life costs, shields); snap = false only redraws
# from the displayed values (mid-batch, so unplayed hits stay hidden).
func _refresh_bars(snap: bool = true) -> void:
	for slot in _presenters:
		var presenter: FighterPresenter = _presenters[slot]
		if not snap:
			presenter.redraw()
			continue
		var unit: CombatUnit = units[slot]
		if int(presenter.displayed_hp) != int(unit.life_n):
			_log("bar snap: slot=%d (%s) hp %d -> %d" % [
				slot, unit.player_name, int(presenter.displayed_hp), int(unit.life_n),
			])
		presenter.snap_to_unit()


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
		var train_cap: int = int(battle_info.get("train_cap", BattleSetup.DEFAULT_TRAIN_CAP))
		var money_levels: Array = BattleRewards.money_levels(battle, save, train_cap)
		var fighting_party: Array[Variant] = []
		for marker in [-2, -1]:
			var party_id: int = Party.deployed_party_id(save, marker)
			if party_id > 0:
				fighting_party.append(party_id)
		var rewards: Dictionary = BattleRewards.apply_victory(save, money_levels, enemy_levels, fighting_party)
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
		# The original never had a turn label, and it draws its victory screen on
		# Navigation, the hub's frame, once a win has left the battle's frame
		# (frame_219/DoAction.as:78-81, frame_181/PlaceObject3_3142_175
		# onClipEvent(load), lines 3-7). The turn label sits on the UI layer above
		# this screen, so it is hidden here instead of still showing whose turn it
		# was across the top of the screen.
		turn_label.hide()
	elif outcome == BattleRunner.Outcome.LOSS or outcome == BattleRunner.Outcome.DRAW:
		# A draw ends the game the same as a defeat: the original sends both to
		# loseCombat (DefineSprite_3355/frame_85/DoAction.as:5-16,
		# frame_241/DoAction.as:1), which resets the game and opens gameOverMenu
		# (frame_230/DoAction.as:1-5, frame_43/DoAction.as:21-25). The screen goes
		# on the UI layer so the turn label there can't draw over it.
		var game_over: GameOverScreen = preload("res://scenes/battle/game_over_screen.tscn").instantiate()
		game_over.name = "GameOverScreen"
		$UI.add_child(game_over)
	battle_finished.emit(outcome)


func _on_victory_proceed() -> void:
	# The original autosaves on Proceed (when the option is on).
	if GameData.current_save != null and GameData.current_save.autosave:
		GameData.save_game()
	if not _pending_cutscene.is_empty():
		# Cleared before the await, not after, so a second call can't start a
		# second copy of the same clip on top of the first. VictoryScreen
		# disables Proceed once it's pressed, so the button can't make that call.
		var cutscene_id: String = _pending_cutscene
		var goto_scene: String = _pending_goto_scene
		_pending_cutscene = ""
		_pending_goto_scene = ""
		# The original stops every sound before it jumps to a cutscene
		# (DefineButton2_3004's release handler calls stopAllSounds). Without
		# this the battle music keeps playing under the cutscene's own audio
		# until _on_continue_pressed() swaps in the menu track, and an effect
		# still playing, such as the last death cry, plays over the clip's start.
		AudioManagerAuto.stop_all_sounds()
		var cutscene: CutscenePlayer = preload("res://scenes/cutscenes/cutscene_player.tscn").instantiate()
		cutscene.animation_speed = animation_speed
		add_child(cutscene)
		await cutscene.play(cutscene_id)
		# The original's cutscene clip starts the music rotation over when the clip
		# ends, before it starts the menu music (frame_263/PlaceObject2_3466_80
		# enterFrame, lines 15-31), so _on_continue_pressed() plays the first menu
		# track.
		AudioManagerAuto.reset_music_rotation()
		# Matches gotoSceneKrin (frame_219): CS_CUT5 ends on the ending screen,
		# and a cutscene that just unlocked a new zone opens the zone map on
		# landing instead of the same hub. The original starts no music for the
		# ending screen (frame_263/PlaceObject2_3466_80 enterFrame, lines 15-19),
		# so the menu track waits until its OK! reaches the hub. The screen goes
		# on the UI layer, like the game over screen, so the speech label there
		# can't draw over it.
		if goto_scene == "endMenu":
			var ending: EndingScreen = preload("res://scenes/battle/ending_screen.tscn").instantiate()
			ending.name = "EndingScreen"
			ending.ok_pressed.connect(_on_continue_pressed)
			$UI.add_child(ending)
			return
		if goto_scene == "overMap":
			ZoneManager.open_zone_map_on_load = true
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _pause(seconds: float) -> void:
	if animation_speed <= 0.0:
		return
	_pause_timer = get_tree().create_timer(seconds / animation_speed)
	await _pause_timer.timeout
