# The _alpha values that the #442 Traced run logged in the Flash debug player
# (references/traced_runs/alpha_steps_web_flash.txt). Ruffle logged the same
# values. alpha_steps_probe.as, in the same folder, is the Probe that wrote
# them. Its ALPHA cases add one step to an empty clip on every frame, and its
# FADE cases replay one fade script of the original each, with the frames on
# which the script's input changes.
extends RefCounted

const LOG_PATH: String = "res://references/traced_runs/alpha_steps_web_flash.txt"


# The _alpha that the case `name` of `kind` (ALPHA or FADE) read on each frame,
# from frame 0, which is its alpha before the first enterFrame.
static func values(kind: String, name: String) -> Array[float]:
	var found: Array[float] = []
	for line: String in FileAccess.get_file_as_string(LOG_PATH).split("\n"):
		var fields: PackedStringArray = line.split("\t")
		if fields.size() == 4 and fields[0] == kind and fields[2] == name and fields[3].is_valid_float():
			found.append(float(fields[3]))
	return found


# The frame on which the FADE case `name` logged `event`, such as "hidden".
static func event_frame(name: String, event: String) -> int:
	for line: String in FileAccess.get_file_as_string(LOG_PATH).split("\n"):
		var fields: PackedStringArray = line.split("\t")
		if fields.size() == 4 and fields[0] == "FADE" and fields[2] == name and fields[3] == event:
			return int(fields[1])
	return -1


# Every ALPHA case's name, in the order the log first names them.
static func alpha_cases() -> Array[String]:
	var names: Array[String] = []
	for line: String in FileAccess.get_file_as_string(LOG_PATH).split("\n"):
		var fields: PackedStringArray = line.split("\t")
		if fields.size() == 4 and fields[0] == "ALPHA" and not names.has(fields[2]):
			names.append(fields[2])
	return names
