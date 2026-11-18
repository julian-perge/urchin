# buff_look.gd
# The look the buffs of a unit give its doll: a color state and a filter list,
# which applyChangesKrin picks from the unit's FILTERSBUFFARRAY
# (frame_42/DoAction_10.as:380-466). convert_buff_looks reads the rules into
# dev/converted_json/buff_looks.json.
class_name BuffLook
extends RefCounted

const LOOKS_PATH: String = "res://dev/converted_json/buff_looks.json"

static var _looks: Dictionary = {}

# The name of the color state and of the filter list, as buff_looks.json names
# them.
var color: String = ""
var filter: String = ""


static func looks() -> Dictionary:
	if _looks.is_empty():
		_looks = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
	return _looks


# Returns the look that `buff_slots` give a doll, each slot being
# {cd, buff_id, ...} as CombatUnit.buff_slots holds it. FILTERSBUFFARRAY counts
# the buffs of each visual filter index, and applyChangesKrin runs one `if` for
# each index in a fixed order, so of the indexes that hold a buff the last one in
# that order wins. A slot with no turns left, a buff that the table does not
# hold and an index of 0 count for nothing.
static func resolve(buff_slots: Array, buffs_by_id: Dictionary) -> BuffLook:
	var held: Dictionary = {}
	for slot in buff_slots:
		if int(slot["cd"]) == 0:
			continue
		var buff: Buff = buffs_by_id.get(slot["buff_id"])
		if buff != null and buff.visual_filter_index > 0:
			held[buff.visual_filter_index] = true
	var table: Dictionary = looks()
	var look := BuffLook.new()
	look.color = table["default_color"]
	look.filter = table["default_filter"]
	for entry in table["color_by_index"]:
		if held.has(int(entry[0])):
			look.color = entry[1]
	for entry in table["filter_by_index"]:
		if held.has(int(entry[0])):
			look.filter = entry[1]
	return look
