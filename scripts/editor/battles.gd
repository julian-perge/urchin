# Run this as an Editor script when you need to update resources
@tool
extends EditorScript

const BattleFightScript = preload("res://scripts/battle/battle_fight.gd")

func _run():
	var file: FileAccess = FileAccess.open(
		"res://conversion_scripts/converted_json/battles.json",
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
		battle.item_rare = battle_data["item_rare"]
		battle.item_rare2 = battle_data["item_rare2"]
		battle.item_rare3 = battle_data["item_rare3"]
		battle.item_rare_dropper = int(battle_data["item_rare_dropper"])
		battle.item_rare_dropper2 = int(battle_data["item_rare_dropper2"])
		battle.item_rare_dropper3 = int(battle_data["item_rare_dropper3"])
		battle.phases = battle_data["phases"]
		battle.players = battle_data["players"]
		battle.players_levels = battle_data["players_levels"]
		battle.sky_background = battle_data["sky_background"]
		battle.speeches = battle_data["speeches"]
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
