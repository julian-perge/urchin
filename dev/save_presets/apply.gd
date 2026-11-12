# Copies a QA save preset into one of the game's save slots. A preset with a
# matching .achievements.cfg also replaces the game's achievements file, and the
# first replacement keeps the original as achievements.cfg.bak.
# The justfile recipes apply-preset, list-presets and restore-achievements run
# this, and docs/agents/godot.md says when to use them. Godot resolves user://
# itself, so the copy lands in the folder the game reads on every OS.
extends SceneTree

const PRESETS_DIR: String = "res://dev/save_presets/"
const ACHIEVEMENTS_BACKUP: String = Achievements.SAVE_PATH + ".bak"

const USAGE: String = """Usage: just apply-preset <preset> <slot 1-4>
       just list-presets
       just restore-achievements"""


func _process(_delta: float) -> bool:
	quit(_run(OS.get_cmdline_user_args()))
	return true


func _run(args: PackedStringArray) -> int:
	if args.size() == 1 and args[0] == "--list":
		_list_presets()
		return 0
	if args.size() == 1 and args[0] == "--restore-achievements":
		return _restore_achievements()
	if args.size() != 2:
		printerr(USAGE)
		return 2
	return _apply(args[0], args[1])


func _list_presets() -> void:
	for file_name in DirAccess.get_files_at(PRESETS_DIR):
		if file_name.get_extension() == "tres":
			print(file_name.get_basename())


func _restore_achievements() -> int:
	if not FileAccess.file_exists(ACHIEVEMENTS_BACKUP):
		printerr("No backup to restore at %s" % ProjectSettings.globalize_path(ACHIEVEMENTS_BACKUP))
		return 1
	var error: Error = DirAccess.rename_absolute(ACHIEVEMENTS_BACKUP, Achievements.SAVE_PATH)
	if error != OK:
		printerr("Could not move the backup back: %s" % error_string(error))
		return 1
	print("Restored achievements.cfg from the backup.")
	return 0


func _apply(preset: String, slot_arg: String) -> int:
	# A -s script fails to compile if it names an autoload as an identifier, so
	# this reads the GameData constants from the autoload node at runtime.
	var game_data_constants: Dictionary = root.get_node("GameData").get_script().get_script_constant_map()
	var save_dir: String = game_data_constants["SAVE_DIR"]
	var slot_count: int = game_data_constants["NUM_SLOTS"]
	var preset_file: String = PRESETS_DIR + preset + ".tres"
	var variant_file: String = PRESETS_DIR + preset + ".achievements.cfg"

	if not FileAccess.file_exists(preset_file):
		printerr("Unknown preset: %s (just list-presets shows them)" % preset)
		return 1
	if not slot_arg.is_valid_int() or int(slot_arg) < 1 or int(slot_arg) > slot_count:
		printerr("Slot must be 1 to %d, got: %s" % [slot_count, slot_arg])
		return 1
	var slot: int = int(slot_arg)

	DirAccess.make_dir_recursive_absolute(save_dir)
	if not _copy(preset_file, save_dir + "slot%d.tres" % slot):
		return 1
	print("Copied %s to slot %d." % [preset, slot])
	if FileAccess.file_exists(variant_file):
		if not _replace_achievements(variant_file):
			return 1
		print("Replaced achievements.cfg. just restore-achievements puts the original back.")
	print("Start the game after this. A running game keeps the slot it already loaded.")
	return 0


func _replace_achievements(variant_file: String) -> bool:
	if not FileAccess.file_exists(ACHIEVEMENTS_BACKUP):
		if FileAccess.file_exists(Achievements.SAVE_PATH):
			if not _copy(Achievements.SAVE_PATH, ACHIEVEMENTS_BACKUP):
				return false
		else:
			# An empty backup stands in for a missing file, because the game
			# reads both as no achievements unlocked.
			if FileAccess.open(ACHIEVEMENTS_BACKUP, FileAccess.WRITE) == null:
				printerr("Could not write %s: %s" % [ACHIEVEMENTS_BACKUP, error_string(FileAccess.get_open_error())])
				return false
	return _copy(variant_file, Achievements.SAVE_PATH)


func _copy(from: String, to: String) -> bool:
	var error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
	if error != OK:
		printerr("Could not copy %s to %s: %s" % [from, to, error_string(error)])
		return false
	return true
