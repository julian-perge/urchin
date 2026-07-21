# log_manager.gd (autoload "LogManagerAuto")
# Per-channel debug log files: LogManagerAuto.log_to("battle", "...") writes
# a timestamped line to user://logs/battle.log (truncated fresh each
# session, flushed per line so `tail -f` works) and echoes to stdout with a
# channel prefix. Any scene can claim its own channel - battle scene ->
# battle.log, store -> store.log, etc.
#
# On macOS the files land in:
#   ~/Library/Application Support/Godot/app_userdata/<project name>/logs/
extends Node

const LOG_DIR = "user://logs"
const ECHO_TO_STDOUT = true

var _files: Dictionary = {}  # channel -> FileAccess


func _ready():
	name = "LogManagerAuto"
	DirAccess.make_dir_recursive_absolute(LOG_DIR)


func log_to(channel: String, message: String) -> void:
	var file: FileAccess = _files.get(channel)
	if file == null:
		file = FileAccess.open("%s/%s.log" % [LOG_DIR, channel], FileAccess.WRITE)
		if file == null:
			push_warning("log_manager: cannot open log for channel %s" % channel)
			return
		_files[channel] = file
		file.store_line("=== %s session %s ===" % [channel, Time.get_datetime_string_from_system()])
	var stamp = "%.3f" % (Time.get_ticks_msec() / 1000.0)
	file.store_line("[%s] %s" % [stamp, message])
	file.flush()
	if ECHO_TO_STDOUT:
		print("[%s %s] %s" % [channel, stamp, message])


func _exit_tree():
	for file in _files.values():
		file.close()
