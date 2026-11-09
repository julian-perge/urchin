# Rebuilds every resources/battles/*.tres from
# dev/converted_json/battles.json.
#
# Run it inside a headless editor, the same way as scripts/editor/units.gd.
# Start a throwaway SceneTree script with
#   godot --headless -e --path . -s <script>
# and have its _process wait 30 frames, load every .tres in
# resources/battles/, then call
# load("res://scripts/editor/battles.gd").new()._run(). Without -e, Godot
# refuses to instantiate an EditorScript, and a plain -s save writes no uid at
# all. The committed battle files carry no uid, so the -e run adds one to each
# file's header and to its script line. Run that way on Godot 4.7.2, those two
# lines were the only change in all 99 files, and every ext_resource id came
# through unchanged.
@tool
extends EditorScript

const BattleFightScript = preload("res://scripts/battle/battle_fight.gd")

func _run():
	var file: FileAccess = FileAccess.open(
		"res://dev/converted_json/battles.json",
		FileAccess.READ
	)
	var json = JSON.parse_string(file.get_as_text())
	file.close()

	for battle_data in json["battles"]:
		var battle: Resource = Resource.new()
		battle.set_script(BattleFightScript)  # This line is crucial!

		# JSON.parse_string() always returns float for numbers (no int type in JSON),
		# and assigning through a generic Resource reference (rather than a statically-typed BattleFight one)
		# skips the usual int coercion - cast explicitly wherever the field is declared as int.
		battle.id = int(battle_data["id"])
		battle.id_name = battle_data["id_name"]
		battle.absolute_start = int(battle_data["absolute_start"])
		battle.item_drops = battle_data["item_drops"]
		battle.item_rare = _dicts(battle_data["item_rare"])
		battle.item_rare2 = _dicts(battle_data["item_rare2"])
		battle.item_rare3 = _dicts(battle_data["item_rare3"])
		battle.item_rare_dropper = int(battle_data["item_rare_dropper"])
		battle.item_rare_dropper2 = int(battle_data["item_rare_dropper2"])
		battle.item_rare_dropper3 = int(battle_data["item_rare_dropper3"])
		battle.phases = battle_data["phases"]
		battle.players = battle_data["players"]
		battle.players_levels = battle_data["players_levels"]
		battle.sky_background = battle_data["sky_background"]
		battle.speeches = _dicts(battle_data["speeches"])
		battle.time_lock = battle_data["time_lock"]
		battle.win_date = int(battle_data["win_date"])
		battle.win_date_condition = int(battle_data["win_date_condition"])
		battle.zone_background = battle_data["zone_background"]

		var err: int = ResourceSaver.save(
			battle,
			"res://resources/battles/%s_%s.tres" % [battle.id, battle.id_name]
		)
		if err != OK:
			print("Failed to save battle: %s, err %s" % [battle.id_name, err])


# Godot 4.7.2 refuses to assign an untyped Array to an Array[Dictionary] field
# through a plain Resource reference, so the JSON arrays are copied into typed
# ones first.
func _dicts(values: Array) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	typed.assign(values)
	return typed
