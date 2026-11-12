class_name Strings
extends RefCounted

# dev/urchin_dev/convert/strings.py writes this file from the KrinLang.ENGLISH
# table of the original. An array index here is the index in the AS.
const STRINGS_FILE := "res://dev/converted_json/strings.json"

static var _table: Dictionary = {}


static func system(index: int) -> String:
	return text("SYSTEM", index)


static func menu(index: int) -> String:
	return text("MENU", index)


# Returns the KrinLang.ENGLISH member `name`, or its entry at `index` when
# the member is an array. An unknown name or index pushes an error and
# returns "".
static func text(name: String, index: int = -1) -> String:
	var table := _load()
	if not table.has(name):
		push_error("Strings: no KrinLang.ENGLISH member %s" % name)
		return ""
	var value: Variant = table[name]
	if index < 0:
		return str(value)
	if not value is Array or index >= value.size() or value[index] == null:
		push_error("Strings: no entry %s[%d]" % [name, index])
		return ""
	return str(value[index])


static func _load() -> Dictionary:
	if _table.is_empty():
		var file := FileAccess.open(STRINGS_FILE, FileAccess.READ)
		if file == null:
			push_error("Strings: cannot open %s" % STRINGS_FILE)
			return _table
		_table = JSON.parse_string(file.get_as_text())
	return _table
