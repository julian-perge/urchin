# store_manager.gd
# Shop data + store window orchestration. Catalogs from krinSetShop()
# (frame42/sonny2_item_shop.txt); the zone -> shop id mapping comes from each
# zone's store-orb button in the SWF (they set Krin.shopId directly) - NOTE
# zones 6 and 7 are swapped versus the naive order: zone 6 uses shop 6,
# zone 7 uses shop 5. Dialogue from frame1/sonny2_shop_say.txt (shops 5/6
# have no dialogue in the original). Backdrops are the per-shop scene art
# from the shop screen's portrait sprite (sprite 3036, frames = shop ids),
# extracted to assets/ui/store/backdrops/shop<id>.jpg.
extends Node

signal store_opened
signal store_closed

# Zone id -> shop id (from the store-orb button scripts).
const ZONE_SHOP_IDS: Dictionary[int, int] = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 6, 7: 5}

# KrinLang.ENGLISH.SHOP[shopId].
const SHOP_DIALOGUE: Dictionary[int, String] = {
	0: "I got what you need mate. Except soap. Someone's taken all the soap. That's why it always stinks around here. But don't worry mate, you'll get used to it.",
	1: "Sssh! Keep your voices down, lads. We're amongst enemies here. In fact, I don't even know if I can trust you. Just buy what you need and leave.",
	2: "Listen. I'm a collector of antique artifacts, and I usually don't sell what I find, but since we're in tough financial times... Consider yourself lucky.",
	3: "I'm fine, I'm fine! My nose is bleeding a little but I'll be alright. You need any more gear? I've got another suitcase of things for you to buy.",
	4: "Police? Proletariat? I don't care, I buy and sell everything from everyone. But do keep your distance, stranger. You're in the city now.",
	5: "",
	6: "",
}

const BACKDROP_PATH: String = "res://assets/ui/store/backdrops/shop%d.jpg"

# From krinSetShop() - 8 fixed 15-item catalogs. Shop 7 has no zone that
# selects it (no store orb sets shopId 7) - kept since it's real source data.
const KRIN_SHOP_ITEMS: Dictionary[int, Array] = {
	0: [508, 509, 510, 511, 512, 513, 502, 514, 0, 0, 0, 0, 0, 0, 0],
	1: [326, 327, 328, 382, 329, 526, 524, 523, 352, 353, 354, 350, 0, 0, 0],
	2: [528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 557, 558, 560, 554, 556],
	3: [598, 599, 600, 601, 604, 574, 576, 580, 582, 583, 586, 590, 592, 593, 594],
	4: [650, 652, 653, 654, 656, 609, 614, 619, 629, 634, 611, 616, 621, 631, 636],
	5: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
	6: [659, 668, 669, 674, 677, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	7: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
}
# DEBUG: For testing items.
# const KRIN_SHOP_ITEMS: Dictionary[int, Array] = {
# 	0: [300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314],
# 	1: [315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329],
# 	2: [330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344],
# 	3: [345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359],
# 	4: [360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374],
# 	5: [375, 376, 377, 378, 379, 380, 381, 382, 500, 501, 502, 503, 504, 505, 506],
# 	6: [507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521],
# 	7: [522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536],
# }


func get_current_shop_id() -> int:
	return int(ZONE_SHOP_IDS.get(ZoneManager.current_zone, 0))


func get_current_shop_items() -> Array[GameItem]:
	var ids = KRIN_SHOP_ITEMS.get(get_current_shop_id(), [])
	var result: Array[GameItem] = []
	for id in ids:
		if id != 0:
			var item: GameItem = ItemManagerAuto.get_item(id)
			if item:
				result.append(item)
	return result


func get_current_shop_dialogue() -> String:
	return str(SHOP_DIALOGUE.get(get_current_shop_id(), ""))


func get_current_shop_backdrop() -> Texture2D:
	var path: String = BACKDROP_PATH % get_current_shop_id()
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _store_window() -> Node:
	return get_tree().get_first_node_in_group("store_window")


func open_store() -> void:
	var window: Node = _store_window()
	if window:
		# Only one menu overlay at a time (the original's single KRINMENU).
		for screen in get_tree().get_nodes_in_group("menu_screen"):
			screen.visible = false
		window.open_store()
		store_opened.emit()


func close_store() -> void:
	var window: Node = _store_window()
	if window:
		window.hide()
		store_closed.emit()
