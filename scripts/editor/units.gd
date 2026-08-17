# Run this as an Editor script when you need to update resources
@tool
extends EditorScript

const CharacterScript = preload("res://scripts/entities/character.gd")

# Canonical key order, from the original AS3 source (not JSON dict order, which
# does not match): frame42/sonny2_agression.txt agModeNames, and frame41's
# elementMainArray. Existing hand-authored unit .tres files store these as plain
# arrays in this order, so new ones must match.
#
# DECODED (2026-07-18, from frame42/sonny2_createNewBattle.txt agressionArray):
# the aggression "mode names" are junk labels from the dump tooling - the 5
# values are positional AI tuning scalars. In AGGRESSION_ORDER position:
#   [0] "Phalanx"    -> Aggression       (chance to keep attacking between boundaries)
#   [1] "Defensive"  -> LifeBoundary1    (team HP% below which defense is considered)
#   [2] "Tactical"   -> LifeBoundary2    (team HP% below which defense is forced)
#   [3] "Aggressive" -> FocusAggression  (chance to target the weakest enemy)
#   [4] "Relentless" -> FocusRegenLimit  (focus threshold for focus-restore moves)
# Verified: LifeBoundary2 <= LifeBoundary1 holds for all 75 units in this order
# (and fails for the alternative order). CombatUnit.from_character() reads these
# positions.
const AGGRESSION_ORDER: Array[String] = ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
const ELEMENT_ORDER: Array[String] = ["Physical", "Magic", "Ice", "Fire", "Lightning", "Earth", "Shadow", "Poison"]

func _ids(move_list: Array) -> Array:
	var ids: Array[int] = []
	for move in move_list:
		ids.append(int(move["id"]))
	return ids

# Absolute (boss-priority) moves carry a phase lock: the converter's "turn"
# field is really the battle PHASE the move is restricted to (0 = usable in any
# phase) - AImoveAdder checks moveArrayABS[i][1] == 0 || == _root.phase.
func _absolute_moves(move_list: Array) -> Array:
	var moves: Array[Dictionary] = []
	for move in move_list:
		moves.append({"id": int(move["id"]), "phase": int(move["turn"])})
	return moves

func _ordered(stat_dict: Dictionary, order: Array) -> Array:
	var result: Array[Variant] = []
	for key in order:
		result.append(stat_dict[key])
	return result

func _run():
	var file: FileAccess = FileAccess.open(
		"res://dev/converted_json/units.json",
		FileAccess.READ
	)
	var json = JSON.parse_string(file.get_as_text())
	file.close()

	for unit_data in json["units"]:
		var unit: Resource = Resource.new()
		unit.set_script(CharacterScript)  # This line is crucial!

		unit.id = int(unit_data["id"])
		unit.name = unit_data["name"]
		unit.vitality = float(unit_data["health"])
		unit.strength = float(unit_data["strength"])
		unit.magic = float(unit_data["magic"])
		unit.speed = float(unit_data["speed"])
		unit.focus = float(unit_data["focus"])

		unit.moves = {
			"absolute": _absolute_moves(unit_data["moves"]["absolute"]),
			"attack": _ids(unit_data["moves"]["attack"]),
			"defense": _ids(unit_data["moves"]["defense"]),
		}

		unit.stats = {
			"aggression": _ordered(unit_data["stats"]["aggression"], AGGRESSION_ORDER),
			"piercing": _ordered(unit_data["stats"]["piercing"], ELEMENT_ORDER),
			"defense": _ordered(unit_data["stats"]["defense"], ELEMENT_ORDER),
		}

		var equipment_ids: Array[Variant] = []
		for slot in unit_data["visuals"]["equipment"]:
			equipment_ids.append(slot["id"])

		unit.visuals = {
			"model": unit_data["visuals"]["model"],
			"equipment": equipment_ids,
			"skin": unit_data["visuals"]["skin"],
			"voice": unit_data["visuals"]["voice"],
		}

		# Prefixed with id: "Felicity" (and possibly others) appears twice in the
		# source data as distinct units (different ids, different movesets) -
		# name alone is not a unique key.
		var file_name = unit.name.to_lower().replace(" ", "_").replace("'", "").replace("/", "_")
		# JSON.parse_string() always returns float for numbers (no int type in
		# JSON) - cast explicitly so the filename doesn't end up as "11.0_...".
		var err: int = ResourceSaver.save(
			unit,
			"res://resources/units/%s_%s.tres" % [int(unit_data["id"]), file_name]
		)
		if err != OK:
			print("Failed to save unit: %s, err %s" % [unit.name, err])
