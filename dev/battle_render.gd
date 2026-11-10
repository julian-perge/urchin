# battle_render.gd
# Saves PNGs of a battle, to see what a shader or a clip draws, because a
# headless run draws nothing. Run it without --headless:
#
#   /Applications/Godot.app/Contents/MacOS/Godot --path . \
#       -s res://dev/battle_render.gd -- --battle=109 --out=<folder> \
#       --show=1:hit --show=2:heal --show=3:focus --frames=0-14 --alpha
#
# It starts the battle the way `--battle=<id>` starts battle_scene.tscn. It waits
# until the battle waits for the player's pick and every Floating number has
# left, and then freezes the battle. Each --show=<slot>:<what> then happens on
# the fighter in that slot, in the order given:
#   hit, heal, focus   a Move result of 10 that plays that Result flash
#   shield_block       a Shield block
#   shield_clip        the Shield clip alone, as a Buff tick that a shield
#                      soaks plays it
# Frame 0 is the frame the shows happen on. Each later frame steps every Result
# flash, Shield clip and Floating number on by one SWF frame, and nothing else in
# the battle moves. A hit puts its doll on the first frame of its flinch. Every
# other doll keeps the pose it had when the battle froze, which can differ from
# one run to the next. --frames picks the frames to save, as 0-14 or 1,4,12, and
# the default is frame 0. Each saved frame is battle_fNN.png, the battle as the
# player sees it. With --alpha it is also black_fNN.png and white_fNN.png, the
# fighters alone over black and over white. From those two, a pixel's alpha is
# 1 - (white - black) / 255 and its color before blending is black / alpha.
#
# The log gives the screen position of each shown fighter's doll origin, and the
# frame each shown Shield clip is on in each saved frame.
extends SceneTree

const SHOWS: Array[String] = ["hit", "heal", "focus", "shield_block", "shield_clip"]
const SWF_FPS: float = 30.0
const BATTLE_SCENE: String = "res://scenes/battle_scene.tscn"
const SETTLE_TIMEOUT_MSEC: int = 60000


# The window's title starts with AGENT RENDER, because the user once took a
# render like this for a bug in the game.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var words: PackedStringArray = []
	for arg in args:
		if not arg.begins_with("--out="):
			words.append(arg.trim_prefix("--"))
	DisplayServer.window_set_title("AGENT RENDER - " + " ".join(words))
	_render.call_deferred(args)


func _render(args: PackedStringArray) -> void:
	var options: Dictionary = parse_args(args)
	if options.has("error"):
		_fail(options["error"])
		return
	if DisplayServer.get_name() == "headless":
		_fail("a headless run draws nothing, so run this without --headless")
		return
	# The window shows on the user's screen. The render must not play the
	# battle's music, and the mouse over the window must not hover a fighter.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.gui_disable_input = true
	DirAccess.make_dir_recursive_absolute(options["out"])
	var scene: Node = load(BATTLE_SCENE).instantiate()
	root.add_child(scene)
	if scene.battle == null:
		_fail("there is no battle %d" % options["battle"])
		return
	for show in options["shows"]:
		if not scene.units.has(show[0]):
			_fail("battle %d has no slot %d. Its slots are %s." % [options["battle"], show[0], scene.units.keys()])
			return
	if not await _settle(scene):
		_fail("battle %d did not get to a Decision with no Floating number up" % options["battle"])
		return
	# A disabled battle runs no _process, animation or tween, so only step()
	# changes what it draws from here on.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	for show in options["shows"]:
		var presenter: Node = scene._presenters[show[0]]
		show_on(presenter, scene.units[show[0]], show[1])
		var doll: Node2D = presenter.get_node("Doll")
		var origin: Vector2 = root.get_final_transform() * doll.get_global_transform_with_canvas().origin
		print("slot %d %s: doll origin at %s screen px" % [show[0], show[1], origin])
	var presenters: Array = scene._presenters.values()
	for frame in options["frames"].max() + 1:
		if frame > 0:
			step(presenters, scene.floating_numbers)
		if frame in options["frames"]:
			await _save_frame(scene, options, frame)
	quit()


static func parse_args(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"shows": [], "frames": [0], "alpha": false}
	for arg in args:
		var value: String = arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--battle":
				if not value.is_valid_int():
					return {"error": "%s: the battle is a number" % arg}
				options["battle"] = int(value)
			"--out":
				options["out"] = value
			"--show":
				var slot: String = value.get_slice(":", 0)
				var what: String = value.get_slice(":", 1)
				if not slot.is_valid_int() or what not in SHOWS:
					return {"error": "%s: write --show=<slot>:<what>, where <what> is one of %s" % [arg, ", ".join(SHOWS)]}
				options["shows"].append([int(slot), what])
			"--frames":
				var frames: Array = _parse_frames(value)
				if frames.is_empty():
					return {"error": "%s: write the frames as 0-14 or 1,4,12" % arg}
				options["frames"] = frames
			"--alpha":
				options["alpha"] = true
			_:
				return {"error": "%s: unknown option" % arg}
	for required in ["battle", "out"]:
		if not options.has(required):
			return {"error": "--%s is required" % required}
	return options


static func show_on(presenter: Node, unit: CombatUnit, what: String) -> void:
	if what == "shield_clip":
		presenter.play_shield_clip()
		return
	var result := MoveResult.new()
	result.amount = 10.0
	result.target_after = UnitSnapshot.of(unit)
	match what:
		"hit":
			result.kind = MoveResult.Kind.DAMAGE
			result.direction = MoveResult.Direction.HARM
		"heal":
			result.kind = MoveResult.Kind.HEAL
			result.direction = MoveResult.Direction.HEAL
		"focus":
			result.kind = MoveResult.Kind.FOCUS
			result.direction = MoveResult.Direction.NONE
		"shield_block":
			result.kind = MoveResult.Kind.DAMAGE
			result.direction = MoveResult.Direction.HARM
			result.amount = 0.0
			result.shield_took_all = true
	presenter.show_result(result, null)


static func step(presenters: Array, floating_numbers: Node) -> void:
	for presenter in presenters:
		presenter.get_node("ResultFlash").advance(1.0 / SWF_FPS)
		presenter.get_node("ShieldClip").advance(1.0 / SWF_FPS)
	floating_numbers.advance(1.0 / SWF_FPS)


# Reads a list such as 0-2,5 into [0, 1, 2, 5], or into [] when any part of it
# is not a frame or a range of frames.
static func _parse_frames(value: String) -> Array:
	var frames: Array = []
	for part in value.split(","):
		var first: String = part.get_slice("-", 0)
		var last: String = part.get_slice("-", 1) if part.contains("-") else first
		if not first.is_valid_int() or not last.is_valid_int() or int(first) > int(last):
			return []
		for frame in range(int(first), int(last) + 1):
			frames.append(frame)
	return frames


# The battle waits for the player's pick in a Decision. Waiting for the half-turns
# before it to take their Floating numbers off too means that step() moves only
# the numbers the shows draw.
func _settle(scene: Node) -> bool:
	var deadline: int = Time.get_ticks_msec() + SETTLE_TIMEOUT_MSEC
	while not (scene.decision_open and scene.floating_numbers.numbers().is_empty()):
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _save_frame(scene: Node, options: Dictionary, frame: int) -> void:
	var file_name: String = "_f%02d.png" % frame
	await _save(options["out"].path_join("battle" + file_name))
	if options["alpha"]:
		var hidden: Array = []
		for child in scene.get_children():
			if child != scene.battlefield and (child is CanvasItem or child is CanvasLayer) and child.visible:
				hidden.append(child)
		for presenter in scene._presenters.values():
			if presenter.get_node("Overlay").visible:
				hidden.append(presenter.get_node("Overlay"))
		for node in hidden:
			node.visible = false
		RenderingServer.set_default_clear_color(Color.BLACK)
		await _save(options["out"].path_join("black" + file_name))
		RenderingServer.set_default_clear_color(Color.WHITE)
		await _save(options["out"].path_join("white" + file_name))
		for node in hidden:
			node.visible = true
		RenderingServer.set_default_clear_color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color"))
	var line: String = "saved frame %d" % frame
	for show in options["shows"]:
		if show[1].begins_with("shield"):
			line += ", slot %d's Shield clip on its frame %d" % [show[0], scene._presenters[show[0]].get_node("ShieldClip").frame]
	print(line)


# Saves the window's image once a frame drawn after the last change is done.
func _save(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save %s: %s" % [path, error_string(error)])


func _fail(message: String) -> void:
	printerr("battle_render: " + message)
	quit(1)
