# Run this as an Editor script when you need to update resources
@tool
extends EditorScript

const ItemScript = preload("res://scripts/entities/game_item.gd")

# Add these to your conversion script
var rarity_map: Dictionary[String, GameItem.Rarity] = {
	"Common": GameItem.Rarity.COMMON,
	"Uncommon": GameItem.Rarity.UNCOMMON,
	"Rare": GameItem.Rarity.RARE,
	"Epic": GameItem.Rarity.EPIC,
	"Legendary": GameItem.Rarity.LEGENDARY
}

var class_type_map: Dictionary[String, GameItem.ClassType] = {
	"None": GameItem.ClassType.NONE,
	"Dreadnaught": GameItem.ClassType.DREADNAUGHT,
	"Phantom": GameItem.ClassType.PHANTOM,
	"Enigma": GameItem.ClassType.ENIGMA,
	"Templar": GameItem.ClassType.TEMPLAR,
	"Phaser": GameItem.ClassType.PHASER
}

var item_type_map: Dictionary[String, GameItem.ItemType] = {
	"None": GameItem.ItemType.NONE,
	"Headwear": GameItem.ItemType.HEAD,
	"Bodywear": GameItem.ItemType.CHEST,
	"Gloves": GameItem.ItemType.HAND,
	"Leggings": GameItem.ItemType.LEGS,
	"Footwear": GameItem.ItemType.FOOT,
	"Primary Arms": GameItem.ItemType.MAINHAND,
	"Two-Handed Arms": GameItem.ItemType.TWOHAND,
	"Secondary Arms": GameItem.ItemType.OFFHAND
}

# Inventory-slot icon lookup: assets/item_slot_icons/<CATEGORY>/<Name>.png,
# where <Name> is the display name with spaces as underscores and apostrophes
# stripped. Tries the type-mapped category first, then all categories.
const SLOT_ICON_ROOT: String = "res://assets/item_slot_icons"
const SLOT_ICON_CATEGORIES: Dictionary[GameItem.ItemType, String] = {
	GameItem.ItemType.HEAD: "HELMS",
	GameItem.ItemType.CHEST: "ARMOR",
	GameItem.ItemType.HAND: "GLOVES",
	GameItem.ItemType.LEGS: "PANTS",
	GameItem.ItemType.FOOT: "SHOES",
	GameItem.ItemType.MAINHAND: "WEAPONS",
	GameItem.ItemType.OFFHAND: "WEAPONS",
	GameItem.ItemType.TWOHAND: "WEAPONS",
}

# Items whose extracted icon-clip frame doesn't match the live game
# (verified by side-by-side playtest) keep a hand-picked icon.
const SLOT_ICON_OVERRIDES: Dictionary[int, String] = {
	11: "res://assets/item_slot_icons/OTHER/White_T_Shirt.png",  # White T-shirt
}
# Icons extracted from the original icon clip (sprite 2064) by
# conversion_scripts/swf_extraction/extract_item_icons.py.
const EXTRACTED_ICON_ROOT: String = "res://assets/ui/items"

var _extracted_icons: Dictionary = {}  # lowercase file name -> actual file name


func _find_slot_icon(item) -> Texture2D:
	if SLOT_ICON_OVERRIDES.has(item.id):
		return load(SLOT_ICON_OVERRIDES[item.id])
	# Prefer the original icon sheet art (sanitized like the extractor:
	# non-alphanumeric runs -> single underscore).
	var extracted_name: String = ""
	var last_was_underscore: bool = true
	for character in item.display_name:
		if (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			extracted_name += character
			last_was_underscore = false
		elif not last_was_underscore:
			extracted_name += "_"
			last_was_underscore = true
	extracted_name = extracted_name.trim_suffix("_")
	# Case-insensitive match (labels capitalize differently than item names).
	if _extracted_icons.is_empty():
		for file_name in DirAccess.get_files_at(EXTRACTED_ICON_ROOT):
			if file_name.ends_with(".png"):
				_extracted_icons[file_name.to_lower()] = file_name
	var extracted_file = _extracted_icons.get((extracted_name + ".png").to_lower(), "")
	if extracted_file != "":
		return load("%s/%s" % [EXTRACTED_ICON_ROOT, extracted_file])
	var icon_name = item.display_name.replace(" ", "_").replace("'", "")
	if icon_name == "":
		return null
	var candidates: Array[Variant] = []
	if SLOT_ICON_CATEGORIES.has(item.item_type):
		candidates.append(SLOT_ICON_CATEGORIES[item.item_type])
	for category in ["OTHER", "HELMS", "ARMOR", "GLOVES", "PANTS", "SHOES", "WEAPONS"]:
		if category not in candidates:
			candidates.append(category)
	for category in candidates:
		var path: String = "%s/%s/%s.png" % [SLOT_ICON_ROOT, category, icon_name]
		if ResourceLoader.exists(path):
			return load(path)
	return null

func _run():
	var file: FileAccess = FileAccess.open(
		"res://conversion_scripts/converted_json/items.json",
		FileAccess.READ
	)
	var json = JSON.parse_string(file.get_as_text())
	file.close()

	for item_data in json["items"]:
		var item: Resource = Resource.new()
		item.set_script(ItemScript)  # This line is crucial!

		# JSON.parse_string() always returns float for numbers (no int type in
		# JSON), and assigning through a generic Resource reference (rather than
		# a statically-typed GameItem one) skips the usual int coercion - cast
		# explicitly wherever the field is declared as int.
		item.id = int(item_data["id"])
		item.looks = item_data["looks"]
		item.name = item_data["name"]
		item.display_name = item_data["display_name"]
		item.internal_name = item_data["internal_name"]
		item.item_type = item_type_map[item_data["item_type"]]
		item.rarity = rarity_map[item_data["rarity"]]
		item.class_type = class_type_map[item_data["class_type"]]
		# The real equip restriction - see GameItem.required_unit_id.
		item.required_unit_id = int(item_data.get("class_unit_id", 0))
		item.required_level = int(item_data["required_level"])
		item.price = int(item_data["price"])
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

		item.slot_image = _find_slot_icon(item)

		var err: int = ResourceSaver.save(
			item,
			"res://resources/items/%s_%s.tres"
			% [item.id, item.display_name.replace(" ", "_").replace("'", "").replace("/", "_")]
		)
		if err != OK:
			print("Failed to save item: %s, err %s" % [item.display_name, err])
