extends SceneTree

const ARIAL := "/System/Library/Fonts/Supplemental/Arial.ttf"
const ARIAL_BOLD := "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
const ARIMO := "/Users/sweetjp/Library/Application Support/com.kodjodevf.mangayomi/Arimo_regular_dbc3f5256cfcb1aa62736daaab3bea7dc85c7c68028cd408671a796537da3a0e.ttf"
const SAMPLES: Array = [
	["Victory! Items that dropped:", 12, false],
	["Once you are finished, press", 12, false],
	["below to proceed:", 12, false],
	["CLICK on the items that you", 12, true],
	["wish to keep!", 12, true],
	["Money gained:", 12, true],
	["Exp. gained:", 12, true],
	["Proceed!", 18, true],
	["Character Experience", 13, true],
	["Your Inventory", 13, true],
	["New Alcatraz: The Iron Prison", 12, true],
	["Zone 1", 17, true],
	["Stage 2", 10, true],
]


func _file(path: String, hinting := TextServer.HINTING_LIGHT, subpixel := TextServer.SUBPIXEL_POSITIONING_AUTO) -> FontFile:
	var font := FontFile.new()
	font.load_dynamic_font(path)
	font.hinting = hinting
	font.subpixel_positioning = subpixel
	return font


func _lines(font: Font, text: String, size: int, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.add_string(text, font, size)
	paragraph.width = width
	return paragraph.get_line_count()


func _width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _total(font: Font, corpus: PackedStringArray, size: int) -> float:
	var total := 0.0
	for line in corpus:
		total += _width(font, line, size)
	return total


func _tooltips() -> void:
	var downloads := "/Users/sweetjp/tmp/2026-11-09-urchin-sans-font/downloads/"
	var fonts := {}
	var settings := {
		"light_auto": [TextServer.HINTING_LIGHT, TextServer.SUBPIXEL_POSITIONING_AUTO],
		"none_auto": [TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_AUTO],
		"none_quarter": [TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER],
		"light_quarter": [TextServer.HINTING_LIGHT, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER],
	}
	for setting in settings:
		var hinting: int = settings[setting][0]
		var subpixel: int = settings[setting][1]
		fonts["arial " + setting] = _file(ARIAL, hinting, subpixel)
		fonts["arimo " + setting] = _file(downloads + "arimo-regular/Arimo-Regular.ttf", hinting, subpixel)
		fonts["heros " + setting] = _file(downloads + "heros-regular/texgyreheros-regular.otf", hinting, subpixel)
		print("WIDTH %s: arial %.2f arimo %.2f heros %.2f" % [setting, _width(fonts["arial " + setting], "Attack the enemy for 170%", 12), _width(fonts["arimo " + setting], "Attack the enemy for 170%", 12), _width(fonts["heros " + setting], "Attack the enemy for 170%", 12)])
	var tips: Array = [
		["Biological blurb", 166.0, 11, "Wild and animalistic, the Biological line harnesses its power from strength and speed. You have the choice of ripping your prey apart with advanced physical combat, or melting them down with your toxic arsenal of poisons. This is probably the most straightforward class to play. Recommended for beginners."],
		["New Game warning", 166.0, 5, "Warning! Starting a new game in a saved slot will remove your old data! Saved games are stored relative to where you play this game."],
		["Leading Strike", 146.0, 3, "Attack the enemy for 170% of your Strength, and restores 50 Focus to you."],
	]
	var server := TextServerManager.get_primary_interface()
	for tip in tips:
		for face in ["arial light_auto", "arimo light_auto", "heros light_auto"]:
			var counts := PackedStringArray()
			for extra in [0.0, 3.34, 4.0, 8.0]:
				var paragraph := TextParagraph.new()
				paragraph.add_string(tip[3], fonts[face], 12)
				paragraph.width = tip[1] + extra
				paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_TRIM_START_EDGE_SPACES | TextServer.BREAK_TRIM_END_EDGE_SPACES
				counts.append("+%.2f:%d" % [extra, paragraph.get_line_count()])
			print("TIP %s | %s | capture=%d | %s" % [tip[0], face, tip[2], " ".join(counts)])


func _init() -> void:
	var fallback: Font = ThemeDB.fallback_font
	print("fallback ", fallback.get_class(), " name=", fallback.get_font_name(), " style=", fallback.get_font_style_name(), " weight=", fallback.get_font_weight())
	var engine_bold: FontVariation = ThemeDB.get_default_theme().get_font("bold_font", "RichTextLabel")
	print("engine bold embolden=", engine_bold.variation_embolden)
	var embolden := FontVariation.new()
	embolden.base_font = fallback
	embolden.variation_embolden = 1.2
	var arial := _file(ARIAL)
	var arial_bold := _file(ARIAL_BOLD)
	var arial_embolden := FontVariation.new()
	arial_embolden.base_font = arial
	arial_embolden.variation_embolden = 1.2
	var arimo := _file(ARIMO)
	print("arimo ", arimo.get_font_name(), " ", arimo.get_font_style_name())
	print("text | size | bold | fallback | embolden | arial | arial_bold | arimo")
	for sample in SAMPLES:
		var text: String = sample[0]
		var size: int = sample[1]
		print("%s | %d | %s | %.2f | %.2f | %.2f | %.2f | %.2f" % [text, size, sample[2], _width(fallback, text, size), _width(embolden, text, size), _width(arial, text, size), _width(arial_bold, text, size), _width(arimo, text, size)])
	var corpus: PackedStringArray = FileAccess.get_file_as_string("res://corpus.txt").split("\n", false)
	print("corpus lines ", corpus.size())
	for size in [10, 12, 14, 18, 24, 36]:
		var totals := {
			"fallback": _total(fallback, corpus, size),
			"embolden": _total(embolden, corpus, size),
			"arial": _total(arial, corpus, size),
			"arial_bold": _total(arial_bold, corpus, size),
			"arimo": _total(arimo, corpus, size),
			"arial_embolden": _total(arial_embolden, corpus, size),
		}
		print("size %d arial_embolden/arial %.3f  arial_embolden/arial_bold %.3f" % [size, totals["arial_embolden"] / totals["arial"], totals["arial_embolden"] / totals["arial_bold"]])
		print("size %d fallback/arial %.3f  embolden/arial_bold %.3f  embolden/fallback %.3f  arial_bold/arial %.3f  arimo/arial %.4f" % [size, totals["fallback"] / totals["arial"], totals["embolden"] / totals["arial_bold"], totals["embolden"] / totals["fallback"], totals["arial_bold"] / totals["arial"], totals["arimo"] / totals["arial"]])
	var downloads := "/Users/sweetjp/tmp/2026-11-09-urchin-sans-font/downloads/"
	var candidates := {
		"arimo_regular": [_file(downloads + "arimo-regular/Arimo-Regular.ttf"), arial],
		"arimo_bold": [_file(downloads + "arimo-bold/Arimo-Bold.ttf"), arial_bold],
		"heros_regular": [_file(downloads + "heros-regular/texgyreheros-regular.otf"), arial],
		"heros_bold": [_file(downloads + "heros-bold/texgyreheros-bold.otf"), arial_bold],
		"arimo_regular_unhinted": [_file(downloads + "arimo-regular/Arimo-Regular.ttf", TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER), _file(ARIAL, TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER)],
		"heros_regular_unhinted": [_file(downloads + "heros-regular/texgyreheros-regular.otf", TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER), _file(ARIAL, TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER)],
	}
	var seen := {}
	for line in corpus:
		for i in line.length():
			seen[line.unicode_at(i)] = true
	for candidate in candidates:
		var font: Font = candidates[candidate][0]
		var reference: Font = candidates[candidate][1]
		var ratios := PackedStringArray()
		for size in [10, 12, 14, 18, 24, 36]:
			ratios.append("%d:%.4f" % [size, _total(font, corpus, size) / _total(reference, corpus, size)])
		var worst := 0.0
		var worst_line := ""
		for line in corpus:
			var difference: float = abs(_width(font, line, 12) - _width(reference, line, 12))
			if difference > worst:
				worst = difference
				worst_line = line
		var missing := PackedStringArray()
		for code in seen:
			if not font.has_char(code):
				missing.append("U+%04X" % code)
		print("CAND %s name=%s/%s ratio_to_arial %s worst_12px_diff=%.1f on [%s] missing=%s" % [candidate, font.get_font_name(), font.get_font_style_name(), " ".join(ratios), worst, worst_line.left(60), missing])
		var disagreements := PackedStringArray()
		for width in [146.0, 166.0, 196.0]:
			var wrapped := 0
			var differ := 0
			for line in corpus:
				var theirs := _lines(reference, line, 12, width)
				if theirs > 1:
					wrapped += 1
				if _lines(font, line, 12, width) != theirs:
					differ += 1
			disagreements.append("%d px: %d differ of %d wrapped" % [width, differ, wrapped])
		print("LINES %s %s" % [candidate, ", ".join(disagreements)])
	_tooltips()
	quit()
