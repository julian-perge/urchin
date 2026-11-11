# battle_scene.gd
# The playable battle screen - glues the headless stack (BattleSetup ->
# BattleRunner -> BattleSettlement) to visuals (one FighterPresenter per
# slot), input, and audio.
#
# Interaction model matches the original (frame 217 KRIN_BATTLE_SCENE):
# - hover a unit: a target ring glows under it (white = you, green = ally,
#   red = enemy) with "Lvl. N" and the name
# - click a unit on your turn: your bar's abilities fan out around it as
#   orbs (RadialMenu); a wrong target or a cooldown darkens an orb, a click on
#   an orb you cannot use says why in the Combat text banner, and orb tooltips
#   carry name/cost/description
# - when your own move fails as it dispatches, the Combat text banner says why.
#   When an AI unit's or a Companion's move fails, the banner shows nothing.
# - the bottom bar: companion stance buttons (agModeAr presets) on the
#   left, the Pass ring in the center (light blue while waiting for your
#   choice, gray during the fight loop) with the retreat X beside it
# - a left-click anywhere while no Decision is open, until the battle is
#   decided, puts "You cannot move yet" in the Combat text banner if it is not
#   already up
#
# Entry: ZoneManager.battle_selected stores the pick in
# ZoneManager.pending_battle and the game scene switches here; _ready()
# consumes it. Tests inject via start_battle() with animation_speed = 0.
extends Control

signal battle_finished(outcome: int)
# Emitted every process frame once the battle clock has moved on. Every wait in
# the scene resumes on it.
signal clock_ticked

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

# What the Combat text banner says when the player's own move fails as it
# dispatches. The conductor writes these only when the caster is the player
# (frame_217/PlaceObject2_3389_480 enterFrame, lines 477-488 and 538-542).
const STUNNED_MESSAGE: String = "You failed to use your ability because you are stunned this round."
const COST_FAILURE_MESSAGES: Dictionary[BattleRunner.FailReason, String] = {
	BattleRunner.FailReason.FOCUS: "You failed to use your ability because you don't have enough Focus.",
	BattleRunner.FailReason.HEALTH: "You failed to use your ability because you don't have enough Health.",
}
# MENU[37] (frame_1/DoAction.as:245), which the original's click listener puts
# in the Combat text banner.
const CANNOT_MOVE_YET_MESSAGE: String = "You cannot move yet. Please wait until the 'ring' is blue, then click on a target."

# At 1.0 the battle plays at the original's pace, and at 0.0 it plays at once,
# as the tests run it. It scales the battle clock.
var animation_speed: float = 1.0

var runner: BattleRunner
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
var _player_leveled: bool = false  # set by _finish_battle() on a win whose XP filled the bar, like playerLeveled
var _pending_setup_events: Array = []  # runner.setup()'s return - played first by _battle_loop()
# The SPEECH event _play_speech has on screen, or {} when no line is up.
var _line_on_screen: Dictionary = {}
# The original's hardSkip. Space sets it during a line, and _play_events then
# drops the rest of that batch's lines, until its next call clears it.
var _hard_skip: bool = false
# Space sets it to end the line on screen at once, and _play_speech clears it.
var _line_cut: bool = false
var _fade_tween: Tween = null  # the running _play_fade's tween, which the next fade kills
# _clock counts the SWF frames the battle has played, scaled by animation_speed.
var _clock: float = 0.0
# The last action still holds the next Dispatch back for this many frames.
# _play_events waits them out before the next action, and before the Half-turn
# ends.
var _frames_to_dispatch: int = 0
# These say whether the action playing was a move, and whether its caster's Buff
# tick is still to come.
var _acting_moved: bool = false
var _buff_tick_due: bool = false

@onready var battle_screen_clip: BattleScreenClip = $BattleScreenClip
@onready var background: TextureRect = $BattleScreenClip/Background
@onready var sky: TextureRect = $Sky
@onready var sky_fill: ColorRect = $SkyFill
@onready var battlefield: Node2D = $BattleScreenClip/Battlefield
# The original attaches each Floating number to BATTLESCREEN at depth 1620 to
# 1639 (frame_42/DoAction_7.as:4 and 37), so the numbers zoom and shake with
# the fighters. That depth is over the fighters at depths 40 to 240, the impact
# clip at -9 and the bolts from depth 600 (frame_42/DoAction_4.as:78 and 140).
# So battle_scene.tscn puts this node in BattleScreenClip right after
# Battlefield, which holds all of those.
@onready var floating_numbers: FloatingNumberLayer = $BattleScreenClip/FloatingNumbers
@onready var turn_label: Label = $UI/TurnLabel
@onready var speech_label: Label = $UI/SpeechLabel
@onready var _pass_ring: Control = $BottomBar/PassRing
@onready var radial_menu: RadialMenu = $RadialMenu
# The battle frame places KrinCombatText at depth 630, above the orb ring at 500
# and below the speech box at 634. So battle_scene.tscn puts this node after the
# RadialMenu, where it draws over the Radial menu, and the speech line is on the
# UI layer, which draws over both.
@onready var combat_text_banner: CombatTextBanner = $CombatTextBanner
@onready var stance_host: Control = $BottomBar/StanceHost
@onready var _countdown_label: Label = $BottomBar/Panel3/CountdownLabel
@onready var _combat_log: CombatLogPanel = $CombatLogPanel
@onready var _fade_black: ColorRect = $Fade/Black


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
	battle_screen_clip.advance(delta * animation_speed)
	if decision_open and not _turn_based:
		_decision_timer = maxf(_decision_timer - delta, 0.0)
		if _decision_timer == 0.0:
			_on_pass_pressed()
	_countdown_label.visible = not _turn_based
	_countdown_label.text = str(int(ceil(_decision_timer)))
	if animation_speed > 0.0:
		_clock += delta * BattleScreenClip.fps() * animation_speed
	clock_ticked.emit()


func _reset_decision_timer() -> void:
	_decision_timer = BattleRunner.BATTLE_TIME_LIMIT / BattleScreenClip.fps()


# Combat debug log -> user://logs/battle.log (see LogManagerAuto).
func _log(message: String) -> void:
	LogManagerAuto.log_to("battle", message)


func start_battle(info: Dictionary) -> void:
	battle_info = info
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
		BuffManagerAuto.buffs_by_internal_name, TalentTree.get_passive_buff_names(save)
	)
	radial_menu.setup(units, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id)
	_load_background()
	_spawn_visuals()
	_populate_stance_rows()
	AudioManagerAuto.play_battle_music(info.get("is_boss", false))
	# The battle frame opens on blacker5's frame 1, which fades the battle in
	# from black until the stop() on its frame 31
	# (DefineSprite_3355/frame_31/DoAction.as).
	_play_fade(1, int(_layout()["fade"]["stop_frame"]))
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


func _layout() -> Dictionary:
	if _battle_layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		_battle_layout = JSON.parse_string(file.get_as_text())
	return _battle_layout


# -> {x, y, w, h} for one sky label, or {} when the JSON has no entry for it.
func _sky_rect(sky_key: String) -> Dictionary:
	return _layout().get("skies", {}).get(sky_key, {})


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
		presenter.setup(units[slot], home, ItemManagerAuto.items_by_id, BuffManagerAuto.buffs_by_id, floating_numbers)
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


# BOOM_*/ex_* impact clip at the target, gated on result.kind != MISS -
# matching frame_42/DoAction_4.as's krinBoltMake, which only attaches its
# impact clip if(_root.strikeSuccess).
func _spawn_impact(target_slot: int, move: Ability, result: MoveResult) -> void:
	if move == null or move.impact_effect_name.is_empty():
		return
	if result.kind == MoveResult.Kind.MISS:
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
const START_WAIT_FRAMES: float = 30.0
# The conductor ends a Half-turn on the frame its last action's count runs out.
# On the next frame the AI picks its moves at once, and on the frame after that
# the first of them dispatches (enterFrame, lines 139-312 and 589-792). The
# port opens the player's Decision after the same 2 frames.
const TEAM_SWITCH_FRAMES: int = 2


func _battle_loop() -> void:
	await _pause(START_WAIT_FRAMES / BattleScreenClip.fps())
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
			_log("  event: %s" % _event_log_text(event))
		await _play_events(events)
		if not is_inside_tree() or _finished:
			return
		_refresh_bars()
		var player: CombatUnit = units.get(BattleRunner.PLAYER_SLOT)
		if player == null or not player.active:
			_turn_based = true
		if not runner.is_over():
			await _wait_frames(TEAM_SWITCH_FRAMES)
			if not is_inside_tree() or _finished:
				return
	_log("battle over: outcome=%d turns=%d" % [runner.win_condition, runner.turn_count])
	_finish_battle()


# battle.log gets an event's result and unit snapshots as their fields and a
# MOVE_FAILED event's reason as its name, because JSON.stringify would print an
# object as its id and the reason as its number.
func _event_log_text(event: Dictionary) -> String:
	var logged: Dictionary = event.duplicate()
	for key in logged:
		if logged[key] is MoveResult or logged[key] is UnitSnapshot:
			logged[key] = logged[key].to_dict()
	if logged.get("type") == BattleRunner.EventType.MOVE_FAILED:
		logged["reason"] = BattleRunner.FailReason.find_key(logged["reason"])
	return JSON.stringify(logged)


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


# Replays a half-turn's event log on the battle clock. Each event plays once it
# is due (see _wait_until_due), and the last action's frames run out before
# this returns, which is when the conductor ends the Half-turn.
func _play_events(events: Array) -> void:
	_hard_skip = false
	for event in events:
		if _hard_skip and event["type"] == BattleRunner.EventType.SPEECH:
			continue
		await _wait_until_due(event)
		_combat_log.append_event(event, units)
		match event["type"]:
			BattleRunner.EventType.MOVE:
				await _play_move_event(event)
			BattleRunner.EventType.STUNNED:
				if int(event["caster_slot"]) == BattleRunner.PLAYER_SLOT:
					combat_text_banner.show_text(STUNNED_MESSAGE)
			BattleRunner.EventType.MOVE_FAILED:
				if int(event["caster_slot"]) == BattleRunner.PLAYER_SLOT:
					combat_text_banner.show_text(COST_FAILURE_MESSAGES[event["reason"]])
			BattleRunner.EventType.DISPEL:
				# The original draws nothing for a dispel (the conductor, lines
				# 22-53), so only the combat log above shows it.
				pass
			BattleRunner.EventType.DEATH:
				# A move's death already played at its Impact (see
				# FighterPresenter.show_result). A death from a Buff tick plays
				# here, on the frame the tick comes due.
				if event.get("cause") != BattleRunner.DeathCause.MOVE:
					_presenters[int(event["slot"])].die()
			BattleRunner.EventType.SPEECH:
				await _play_speech(event)
			BattleRunner.EventType.PHASE_ADVANCED:
				# The original changes no music when a phase advances. Its phase
				# block only moves the phase on (the conductor, lines 176-193), and
				# it picks the battle track once, when the battle loads
				# (frame_201/DoAction.as:86).
				pass
			BattleRunner.EventType.BATTLE_ENDED, BattleRunner.EventType.PASSED:
				pass
	await _wait_for_dispatch()


# Waits until `event` is due on the battle clock. A move's death is due at that
# move's Impact, and a death from a Buff tick when the tick comes due. Every
# other event is due once the last action's frames have run out: a MOVE,
# STUNNED, MOVE_FAILED or PASSED starts the next action, a DISPEL comes with the
# MOVE after it, and the rest come at the Half-turn's end.
func _wait_until_due(event: Dictionary) -> void:
	match event["type"]:
		BattleRunner.EventType.DEATH:
			if event.get("cause") == BattleRunner.DeathCause.MOVE:
				return
			await _reach_buff_tick()
			# The tick that killed this unit did something. After a move the
			# conductor then holds the next Dispatch a whole AttackEndCounter
			# more (frame_217/PlaceObject2_3389_480 enterFrame, lines 118-127).
			# After a stun, a failed cost or a pass it moves on 1 frame later
			# anyway, because it first checks that the caster lived through its
			# tick (lines 515 and 569).
			if _acting_moved:
				_frames_to_dispatch = _attack_end_counter_limit() + 1
		BattleRunner.EventType.MOVE, BattleRunner.EventType.STUNNED, BattleRunner.EventType.MOVE_FAILED, BattleRunner.EventType.PASSED:
			await _wait_for_dispatch()
			_start_action(event["type"] == BattleRunner.EventType.MOVE)
		_:
			await _wait_for_dispatch()


# Waits out the frames the last action holds the next Dispatch back for.
func _wait_for_dispatch() -> void:
	var frames: int = _frames_to_dispatch
	_frames_to_dispatch = 0
	_buff_tick_due = false
	await _wait_frames(frames)


# An action dispatches. A caster that doesn't move, because it is stunned, can't
# pay the cost or has nothing to do, ticks its buffs on its Dispatch frame
# unless it is dead, and the next action dispatches 1 frame later
# (frame_217/PlaceObject2_3389_480 enterFrame, lines 503-530 and 557-584). A
# move's tick comes due once it lands (see _count_from_impact).
func _start_action(moves: bool) -> void:
	_acting_moved = moves
	_buff_tick_due = not moves
	_frames_to_dispatch = 0 if moves else 1


# The conductor sets its AttackEndCounter to 0 at every Impact and counts that
# frame too, so the caster's Buff tick comes due 25 frames after the Impact and
# the next action dispatches 26 frames after it (frame_217/PlaceObject2_3389_480
# enterFrame, lines 12-15 and 112-138). A caster its own move killed has no
# tick, and the next action dispatches on frame 25 (line 118).
func _count_from_impact(event: Dictionary) -> void:
	var result: MoveResult = event["result"]
	var killed_its_caster: bool = result.killed and int(event["target_slot"]) == int(event["caster_slot"])
	_buff_tick_due = not killed_its_caster
	_frames_to_dispatch = _attack_end_counter_limit() + (0 if killed_its_caster else 1)


# Returns the conductor's AttackEndCounterLimit, 25, which its onClipEvent(load)
# sets (frame_217/PlaceObject2_3389_480, line 7). _count_from_impact has what
# it decides.
func _attack_end_counter_limit() -> int:
	return int(BattleScreenClip.motion()["conductor"]["AttackEndCounterLimit"])


# Waits until the acting caster's Buff tick comes due, on the frame before the
# next Dispatch could come.
func _reach_buff_tick() -> void:
	if not _buff_tick_due:
		return
	_buff_tick_due = false
	var frames: int = _frames_to_dispatch - 1
	_frames_to_dispatch = 1
	await _wait_frames(frames)


func _play_move_event(event: Dictionary) -> void:
	var caster_slot: int = int(event["caster_slot"])
	var target_slot: int = int(event["target_slot"])
	var move: Ability = MoveManagerAuto.get_move(int(event["move_id"]))
	var caster: FighterPresenter = _presenters.get(caster_slot)
	_start_camera(move, target_slot)
	# The caster paid the move's costs as it dispatched, and the original redraws
	# its bars right there (the conductor, line 359), before any swing or cast.
	if caster != null:
		caster.show_state(event["caster_after_dispatch"])
	# Only Melee moves run and swing; the original plays "cast" for both
	# Missile and Shock (param 12 is the projectile clip for Missiles, and
	# unused for Shock) - see DECODED_ALGORITHMS.md.
	if caster != null and move != null and move.attack_animation_type == "Melee":
		# The original runs the caster to the target and swings, and the Move
		# result applies at Impact. The caster hands back at Impact and runs
		# back on its own.
		var start_ms: int = Time.get_ticks_msec()
		var on_impact: Callable = func():
			_log("melee impact: caster=%d move=%s +%dms" % [
				caster_slot, move.display_name, Time.get_ticks_msec() - start_ms,
			])
			_play_landing_sound(move, event["result"])
			_spawn_impact(target_slot, move, event["result"])
			_show_move_result(event, target_slot)
		_log("melee start: caster=%d target=%d move=%s label=%s" % [
			caster_slot, target_slot, move.display_name, move.animation_label,
		])
		await caster.melee(_presenters[target_slot], move.animation_label, on_impact, animation_speed > 0.0)
		if not is_inside_tree():
			return
		_count_from_impact(event)
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
			_spawn_impact(target_slot, move, event["result"])
			_show_move_result(event, target_slot)
			_count_from_impact(event)
			return
		if move.attack_animation_type == "Missile":
			# Missile: sfx_cast plays at cast start, then a krinBoltMake bolt
			# flies to the target - impact lands when the bolt REACHES the
			# target, not on a fixed cast-clip time (the bolt's own
			# accel/arrival model decides it).
			AudioManagerAuto.play_effect("sfx_cast")
			var bolt: Projectile = await _fire_projectile(caster_slot, target_slot, move, event["result"])
			if not is_inside_tree():
				return
			_play_landing_sound(move, event["result"])
			_show_move_result(event, target_slot)
			# A missed bolt flies on and raises the impact flag again on every
			# frame until it is gone (frame_42/DoAction_4.as:188-205), so the
			# count to the next Dispatch starts then.
			if bolt != null and not bolt.is_queued_for_deletion():
				await bolt.flight_ended
				if not is_inside_tree():
					return
			_count_from_impact(event)
			return
		AudioManagerAuto.play_effect("sfx_cast")
	# A move the scene can't animate, because its caster, its record or its
	# animation type is unknown, lands at its Dispatch like a Shock.
	if move != null:
		AudioManagerAuto.play_effect(move.sound_effect_name)
	_show_move_result(event, target_slot)
	_count_from_impact(event)


# The original plays a move's own sound only when the move lands (the conductor,
# lines 19-21). A miss plays missToMake instead (lines 105-108), which a Missile
# sets to sfx_magicmiss (line 415). A Melee move sets missToMake to undefined on
# purpose (line 407), and addSound plays nothing for undefined
# (frame_42/DoAction.as:7), so a Melee miss is silent.
func _play_landing_sound(move: Ability, result: MoveResult) -> void:
	if result.kind != MoveResult.Kind.MISS:
		AudioManagerAuto.play_effect(move.sound_effect_name)
	elif move.attack_animation_type == "Missile":
		AudioManagerAuto.play_effect("sfx_magicmiss")


# At Dispatch the conductor zooms GridZoomer toward the target of every move
# but a Missile that hits every enemy, and plays GridShaker with a Shock whose
# speed modifier is 0 or more (line 464). It does both only while the Graphics
# option is on, which frame_201/DoAction.as:87-100 copies into
# KrinSettings.SFX. The rig point the zoom aims at is the target's rig x plus
# half its width and its y plus half its height, from where BATTLESCREEN rests.
# Each move type's zoom multiplies that point by a factor, adds a center, and
# holds GridZoomer at its peak for some frames. battle_screen_motion.json has
# each type's zoom from the scripts that set it up: the conductor's for a
# Missile and a Shock (lines 419-428 and 455-462), and krinMelee's for a Melee
# move (frame_42/DoAction_4.as:58-65). Nothing waits for the zoom or the shake.
func _start_camera(move: Ability, target_slot: int) -> void:
	var target: FighterPresenter = _presenters.get(target_slot)
	var save: PlayerSave = GameData.current_save
	if move == null or target == null or save == null or not save.graphics:
		return
	var zoom: Dictionary = BattleScreenClip.motion()["zooms"].get(move.attack_animation_type, {})
	if zoom.is_empty() or (move.attack_animation_type == "Missile" and move.hits_all_enemies):
		return
	var rig_point: Vector2 = target.rig_position() - battle_screen_clip.rest + target.rig_size() / 2.0
	var center := Vector2(float(zoom["center"]["x"]), float(zoom["center"]["y"]))
	battle_screen_clip.zoom(rig_point * float(zoom["factor"]) + center, int(zoom["hold"]))
	if move.attack_animation_type == "Shock" and move.combat_speed_modifier >= 0:
		battle_screen_clip.shake()


# Ports krinBoltMake: an accelerating bolt (Projectile) flies from the caster to
# the target, spawns the move's impact effect there, and this returns the bolt
# once it gets there. On a hit the bolt destroys itself the moment it arrives.
# On a miss it keeps flying past the target and only frees once it is far
# enough past it. At an animation_speed of 0 or below, as the tests run it,
# this skips the flight and returns null, because no _process tick would ever
# move the bolt. The return type isn't declared, because GUT prints a compiler
# error when it doubles this scene with a declared return type on a function
# that awaits (GUT issue 842).
func _fire_projectile(caster_slot: int, target_slot: int, move: Ability, result: MoveResult):
	if animation_speed <= 0.0:
		return null
	var from: Vector2 = SLOT_POSITIONS.get(caster_slot, Vector2(400, 300))
	var to: Vector2 = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	var bolt: Projectile = ProjectileScene.instantiate()
	bolt.color = _move_color(move)  # fallback tinted-circle color if clip_name has no real asset
	bolt.clip_name = move.animation_label
	bolt.trail_color = move.visual_effect_color
	bolt.did_hit = result.kind != MoveResult.Kind.MISS
	bolt.battle_screen_x = battle_screen_clip.rest.x
	battlefield.add_child(bolt)
	bolt.start(from, to)
	await bolt.reached_target
	_spawn_impact(target_slot, move, result)
	return bolt


func _show_move_result(event: Dictionary, target_slot: int) -> void:
	var result: MoveResult = event["result"]
	var target_unit: CombatUnit = units[target_slot]
	_log("result shown: %s target=%d (%s) hp=%d/%d" % [
		JSON.stringify(result.to_dict()), target_slot, target_unit.player_name,
		int(target_unit.life_n), int(target_unit.life_u),
	])
	_presenters[target_slot].show_result(result, MoveManagerAuto.get_move(int(event.get("move_id", 0))))


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
	_line_cut = false
	speech_label.text = ""


func _input(event: InputEvent) -> void:
	if _finished:
		return
	# The original's click listener is a Mouse.onMouseDown that the battle frame
	# adds (frame_217/DoAction.as:18-27), so it hears every left-click, one that
	# a button or a unit also answers included. This reads the click before any
	# control can take it and leaves it to them. Outside a Decision the listener
	# shows MENU[37] with a bare play(), which show_if_idle() matches. The
	# original's listener goes on showing it once winCondition is set, but the
	# port shows nothing from the moment the runner has decided the battle, while
	# the half-turn that decided it is still playing (DECODED_ALGORITHMS.md, "The
	# Combat text banner").
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var decided: bool = runner != null and runner.is_over()
		if not decision_open and not decided:
			combat_text_banner.show_if_idle(CANNOT_MOVE_YET_MESSAGE)
		return
	# The original's speech box answers Space all through a battle
	# (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines 2-9). It
	# stops the three effect channels, and while a line is up it ends that line
	# and sets hardSkip, which drops the rest of the conversation
	# (BattleRunner.hard_skip). The project has no input action for it, and
	# Godot's ui_accept and ui_select also fire on Enter or a gamepad button, so
	# this checks the key itself, as Key.isDown(32) does.
	if not (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		return
	AudioManagerAuto.stop_effects()
	if _line_on_screen.is_empty():
		return
	_hard_skip = true
	runner.hard_skip(int(_line_on_screen["speech_index"]))
	_line_cut = true
	get_viewport().set_input_as_handled()


# Shows every fighter's unit as the half-turn left it. It runs only once the
# replay has played every event, so it reveals nothing that hasn't played.
func _refresh_bars() -> void:
	for slot in _presenters:
		var presenter: FighterPresenter = _presenters[slot]
		var unit: CombatUnit = units[slot]
		if int(presenter.displayed.life) != int(unit.life_n):
			_log("bar snap: slot=%d (%s) hp %d -> %d" % [
				slot, unit.player_name, int(presenter.displayed.life), int(unit.life_n),
			])
		presenter.snap_to_unit()


func _finish_battle() -> void:
	if _finished:
		return
	_finished = true
	# The original settles a win on winCombat and on the victory screen's own
	# frame, which both come after blacker5's frame 85 sends the result
	# (frame_219/DoAction.as, DefineSprite_3142/frame_9), so nothing is paid
	# until the fade has played.
	var fade: Dictionary = _layout()["fade"]
	await _play_fade(int(fade["stop_frame"]), int(fade["result_frame"]))
	var save: PlayerSave = GameData.current_save
	var settlement := BattleSettlement.settle(runner, save, battle_info, ZoneManager.achievements_path, GameData.slot_saves())
	if settlement.outcome == BattleRunner.Outcome.WIN:
		_pending_cutscene = settlement.cutscene
		_pending_goto_scene = settlement.goto_scene
		_player_leveled = settlement.levels_gained > 0
		# Drops are click-to-keep on the victory screen (VICTORY[1]); the
		# autosave happens on Proceed, like the original.
		var victory: VictoryScreen = preload("res://scenes/battle/victory_screen.tscn").instantiate()
		victory.name = "VictoryScreen"
		add_child(victory)
		victory.setup(save, settlement)
		victory.proceed_pressed.connect(_on_victory_proceed)
		# The original never had a turn label, and it draws its victory screen on
		# Navigation, the hub's frame, once a win has left the battle's frame
		# (frame_219/DoAction.as:78-81, frame_181/PlaceObject3_3142_175
		# onClipEvent(load), lines 3-7). The turn label sits on the UI layer above
		# this screen, so it is hidden here instead of still showing whose turn it
		# was across the top of the screen.
		turn_label.hide()
	elif settlement.game_over:
		# The screen goes on the UI layer so the turn label there can't draw over
		# it.
		var game_over: GameOverScreen = preload("res://scenes/battle/game_over_screen.tscn").instantiate()
		game_over.name = "GameOverScreen"
		$UI.add_child(game_over)
	battle_finished.emit(settlement.outcome)


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
	elif bool(battle_info.get("is_boss", false)):
		# With no cutscene queued, the original opens the zone map after any
		# fight with bossFight on, a first win and a Boss replay alike
		# (DefineButton2_3004 on(release), lines 13-16, and
		# frame_219/DoAction.as:9-16).
		ZoneManager.open_zone_map_on_load = true
	elif _player_leveled:
		# Neither a cutscene nor the map comes next, so the original shows its
		# skills frame when the win filled the XP bar (DefineButton2_3004
		# on(release), lines 17-29). The hub opens the Abilities window.
		ZoneManager.open_abilities_on_load = true
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# Waits `seconds` on the battle clock, for the waits the battle data gives in
# seconds.
func _pause(seconds: float) -> void:
	await _wait_frames(seconds * BattleScreenClip.fps())


# Waits `frames` frames on the battle clock, and returns at once while
# animation_speed is 0. Space ends a line's wait early (see _input), and only a
# line's wait runs while a line is on screen.
func _wait_frames(frames: float) -> void:
	var until: float = _clock + frames
	while animation_speed > 0.0 and _clock < until and not _line_cut:
		await clock_ticked


# Plays blacker5, DefineSprite 3355, from frame `from_frame` to frame `to_frame`
# at the SWF's frame rate, over the whole window. The original places it on the
# battle frame's top depth, and its black shape covers the whole stage, so the
# Fade layer draws over the UI layer too. Its colour, frame rate and the alpha
# of every frame come from battle_layout.json, which extract_battle_screen reads
# out of the SWF. At animation_speed 0 it shows `to_frame` at once, the way
# _pause() returns at once.
func _play_fade(from_frame: int, to_frame: int) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	var fade: Dictionary = _layout()["fade"]
	_fade_black.color = Color(fade["color"])
	if animation_speed <= 0.0:
		_show_fade_frame(to_frame)
		return
	_show_fade_frame(from_frame)
	_fade_tween = create_tween()
	_fade_tween.tween_method(
		_show_fade_frame, float(from_frame), float(to_frame),
		(to_frame - from_frame) / float(fade["fps"]) / animation_speed
	)
	await _fade_tween.finished


# Shows blacker5's frame `frame`. The tween passes it as a float, and each SWF
# frame holds its alpha until the next one starts.
func _show_fade_frame(frame: float) -> void:
	_fade_black.color.a = float(_layout()["fade"]["alphas"][int(frame) - 1])
