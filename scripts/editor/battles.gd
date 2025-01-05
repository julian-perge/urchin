# Run this as an Editor script when you need to update resources
@tool
extends EditorScript

const _script = preload("res://scripts/battle/battle_fight.gd")

func _run():
	var file = FileAccess.open(
		"res://python_conversion_scripts/converted_json/converted_battles.json",
		FileAccess.READ
	)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	var item_num = 0
	for item_data in json["items"]:
		var item = Resource.new()
		item.set_script(_script)  # This line is crucial!

		item.id = item_data["id"]
		item.looks = item_data["looks"]
		item.name = item_data["name"]
		item.display_name = item_data["display_name"]
		item.internal_name = item_data["internal_name"]
		item.item_type = item_type_map[item_data["item_type"]]
		item.rarity = rarity_map[item_data["rarity"]]
		item.class_type = class_type_map[item_data["class_type"]]
		item.required_level = item_data["required_level"]
		item.price = item_data["price"]
		item.price_modifier = item_data["price_modifier"]
		item.stats = item_data["stats"]
		item.tooltipAlt = item_data["tool_tip_alt"]
		item.tooltip = ""
		if str(item_data["tool_tip"]) != "0":
			item.tooltip = item_data["tool_tip"]
		
		if item.looks != "":
			var png_item_type = GameItem.ItemType.keys()[item.item_type]
			if (
				item.item_type == GameItem.ItemType.MAINHAND 
				or item.item_type == GameItem.ItemType.TWOHAND 
				or item.item_type == GameItem.ItemType.OFFHAND
			):
				png_item_type = "WEAPON"
			elif item.item_type == GameItem.ItemType.LEGS:
				png_item_type = "LEG2"
			item.sprite_image = load("res://resources/sprites/M_%s_%s.png" % [png_item_type, item.looks])
		
		var err = ResourceSaver.save(
			item, 
			"res://resources/items/%s_%s.tres"
			% [item.id, item.display_name.replace(" ", "_").replace("'", "").replace("/", "_")]
		)
		if err != OK:
			print("Failed to save item: %s, err %s" % [item.display_name, err])
