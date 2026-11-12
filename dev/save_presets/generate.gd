# Rebuilds every QA save preset in this folder. Each one starts from the same
# steps as the main menu's new game and wins its story fights through
# ZoneProgression, so companions, unlocks and quest_progress match a real run.
# docs/agents/godot.md has the command that runs this. `just apply-preset`
# copies a preset into a slot.
extends SceneTree

const OUTPUT_DIR: String = "res://dev/save_presets/"
const STRONG_LEVEL: int = 99
# This is the lowest value tried that beat every story boss within five moves.
# Using 900, about what slot 4 was hand-edited to, lost 19 of 20 fights against
# battle 703.
const STRONG_STAT: float = 5000.0
const STRONG_EURO: float = 999999.0
const WEAK_EURO: float = 1000.0
const PREDATOR_ZONE: int = 2
const LEGEND_ZONE: int = 5

var _game_data: Node
var _failed: bool = false


func _process(_delta: float) -> bool:
	# A -s script fails to compile if it names an autoload as an identifier, so
	# this finds the GameData node at runtime instead.
	_game_data = root.get_node("GameData")
	_build_fresh()
	_build_zone_bosses()
	_build_postgame()
	_build_no_training()
	_build_weak()
	_build_rich()
	quit(1 if _failed else 0)
	return true


func _build_fresh() -> void:
	_write_preset(_new_game("fresh_normal", CombatUnit.Difficulty.NORMAL))


func _build_zone_bosses() -> void:
	var last_normal_zone: int = ZoneProgression.max_zone(CombatUnit.Difficulty.NORMAL)
	for zone: int in ZoneProgression.QUEST_HUB:
		var needs_legend: bool = zone > last_normal_zone
		var difficulty: CombatUnit.Difficulty = CombatUnit.Difficulty.HARD if needs_legend else CombatUnit.Difficulty.NORMAL
		var save: PlayerSave = _save_with_boss_next("zone%d_boss" % zone, difficulty, zone)
		_make_strong(save)
		_write_preset(save)
		if needs_legend:
			_write_achievements(save.name_user, [_legend_id()])


func _build_postgame() -> void:
	for entry: Array in [
		["postgame_easy", CombatUnit.Difficulty.EASY],
		["postgame_normal", CombatUnit.Difficulty.NORMAL],
		["postgame_heroic", CombatUnit.Difficulty.HARD],
	]:
		var save: PlayerSave = _save_past_every_open_zone(entry[0], entry[1])
		_make_strong(save)
		_write_preset(save)
	_write_achievements("postgame_heroic", [])

	var legend_save: PlayerSave = _save_past_every_open_zone("heroic_legend", CombatUnit.Difficulty.HARD)
	_make_strong(legend_save)
	legend_save.section_in = ZoneProgression.max_zone(CombatUnit.Difficulty.HARD)
	_write_preset(legend_save)
	_write_achievements("heroic_legend", [_legend_id()])


func _build_no_training() -> void:
	for entry: Array in [["no_training_predator", PREDATOR_ZONE], ["no_training_legend", LEGEND_ZONE]]:
		var save: PlayerSave = _save_with_boss_next(entry[0], CombatUnit.Difficulty.HARD, entry[1])
		_make_strong(save)
		_write_preset(save)
		_write_achievements(save.name_user, [])


func _build_weak() -> void:
	var save: PlayerSave = _save_with_boss_next("weak", CombatUnit.Difficulty.NORMAL, LEGEND_ZONE)
	save.euro = WEAK_EURO
	_write_preset(save)


func _build_rich() -> void:
	var save: PlayerSave = _save_past_every_open_zone("rich", CombatUnit.Difficulty.NORMAL)
	save.euro = STRONG_EURO
	_write_preset(save)


# These are the steps of main_menu.gd's _on_start_new_game that build the save.
# They leave out its first fight and do not write a slot. The preset name goes in
# name_user so the slot button shows which preset a slot holds.
func _new_game(preset_name: String, difficulty: CombatUnit.Difficulty) -> PlayerSave:
	_game_data.new_game(0, preset_name, PlayerSave.PlayerClass.BIOLOGICAL)
	var save: PlayerSave = _game_data.current_save
	save.difficulty = difficulty
	save.autosave = true
	return save


func _save_with_boss_next(preset_name: String, difficulty: CombatUnit.Difficulty, zone: int) -> PlayerSave:
	var save: PlayerSave = _new_game(preset_name, difficulty)
	for earlier_zone in range(1, zone):
		_win_story_fights(save, earlier_zone, false)
	_win_story_fights(save, zone, true)
	return save


func _save_past_every_open_zone(preset_name: String, difficulty: CombatUnit.Difficulty) -> PlayerSave:
	var save: PlayerSave = _new_game(preset_name, difficulty)
	for zone in range(1, ZoneProgression.max_zone(difficulty) + 1):
		_win_story_fights(save, zone, false)
	save.section_in = 1
	save.used_training = true
	return save


# The boss a preset stops at is the fight at the zone's progress_max. The
# pick's is_boss can't say where that is, because zone 4's first fight there,
# 409, isn't flagged as a boss fight.
func _win_story_fights(save: PlayerSave, zone: int, stop_at_boss: bool) -> void:
	save.section_in = zone
	var progress_max: int = int(ZoneProgression.QUEST_HUB[zone]["progress_max"])
	while true:
		var pick: Dictionary = ZoneProgression.pick_story_battle(save)
		var at_boss: bool = ZoneProgression.quest_progress(save, zone) == progress_max
		if not pick["is_story_progress"] or (stop_at_boss and at_boss):
			return
		ZoneProgression.after_battle_won(save, pick["battle_id"], true)


# This sets the level and stats directly, because the stat curve behind
# Leveling.compute_stats and points_for_level_up turns negative by level 55.
# Stat points stay at zero because spending one recomputes the stats from that
# curve.
func _make_strong(save: PlayerSave) -> void:
	save.level = STRONG_LEVEL
	save.skill_points = STRONG_LEVEL - 1 + TalentTree.STARTING_SKILL_POINTS
	save.life = STRONG_STAT + save.stat_allocated[Leveling.Stat.LIFE]
	save.strength = STRONG_STAT + save.stat_allocated[Leveling.Stat.STRENGTH]
	save.magic = STRONG_STAT + save.stat_allocated[Leveling.Stat.MAGIC]
	save.speed = STRONG_STAT + save.stat_allocated[Leveling.Stat.SPEED]
	save.euro = STRONG_EURO


func _legend_id() -> int:
	return Achievements.NAMES.find("Legend")


func _write_preset(save: PlayerSave) -> void:
	var path: String = OUTPUT_DIR + save.name_user + ".tres"
	# The saver otherwise picks a random id for the script reference, and every
	# regeneration would then rewrite every preset.
	save.get_script().set_id_for_path(path, "1_player_save")
	var error: Error = ResourceSaver.save(save, path)
	if error != OK:
		push_error("generate: could not write %s: %s" % [path, error_string(error)])
		_failed = true


func _write_achievements(preset_name: String, unlocked_ids: Array) -> void:
	var path: String = OUTPUT_DIR + preset_name + ".achievements.cfg"
	var config: ConfigFile = ConfigFile.new()
	for id in Achievements.ACHIEVEMENT_COUNT:
		config.set_value("achievements", str(id), id in unlocked_ids)
	var error: Error = config.save(path)
	if error != OK:
		push_error("generate: could not write %s: %s" % [path, error_string(error)])
		_failed = true
