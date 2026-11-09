extends SceneTree
# Throwaway main loop for the pixel snapping ticket. It never writes into the project.
# Arguments after "--":
#   --snap=on|off|ctl_off|2d_off   which of the two viewport flags to clear
#   --out=<prefix>                 output path prefix
#   --mode=synthetic|scene
#   --scene=res://...              scene to run in scene mode
#   --hub                          build a throwaway slot -1 save first
#   --frames=60,61,62              frames after the scene change to capture
#   --open=<Node/Path:method>      call a method on a node once, at --open-frame
#   --open-frame=30

var _args := {}
var _frames: Array[int] = []
var _stretch := 2.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	var snap: String = _args.get("snap", "on")
	if snap != "project":
		root.gui_snap_controls_to_pixels = snap in ["on", "2d_off"]
		root.snap_2d_transforms_to_pixel = snap in ["on", "ctl_off"]
	print("snapdriver: flags ", root.gui_snap_controls_to_pixels, " ", root.snap_2d_transforms_to_pixel)
	match _args.get("filter", "nearest"):
		"linear":
			root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		"mip":
			root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"nearest":
			root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	print("filterdriver: filter ", root.canvas_item_default_texture_filter)
	for f in String(_args.get("frames", "60")).split(","):
		_frames.append(int(f))
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	if _args.get("mode", "scene") == "halls":
		await _halls()
	elif _args.get("mode", "scene") == "synthetic":
		await _synthetic()
	else:
		await _scene()
	quit()


func _scene() -> void:
	if _args.has("hub"):
		root.get_node("GameData").new_game(-1, "Debug")
	seed(12345)
	change_scene_to_file(_args["scene"])
	var opened := not _args.has("open")
	var open_frame := int(_args.get("open-frame", "30"))
	var last: int = _frames.max()
	for frame in range(1, last + 1):
		await process_frame
		if not opened and frame == open_frame:
			opened = true
			var target: String = _args["open"]
			var pieces := target.split(":")
			var node := current_scene.get_node_or_null(pieces[0])
			if node == null:
				printerr("snapdriver: no node ", pieces[0])
			else:
				if pieces.size() > 2:
					node.call(pieces[1], pieces[2])
				else:
					node.call(pieces[1])
		if _args.has("motion") and frame == 60:
			var visuals: Dictionary = current_scene.get("_visuals")
			var slot = visuals.keys()[0]
			var dx := 300.0 if visuals[slot].position.x < 400.0 else -300.0
			print("snapdriver: melee slot ", slot, " from ", visuals[slot].position, " dx ", dx)
			visuals[slot].play_melee(Vector2(dx, -20))
			current_scene.call("_float_text", slot, "123", Color.YELLOW)
		if _args.has("bolt") and frame == 60:
			var move = root.get_node("MoveManager").get_move(int(_args["bolt"]))
			var bolt_visuals: Dictionary = current_scene.get("_visuals")
			var slots: Array = bolt_visuals.keys()
			slots.sort_custom(func(a, b): return bolt_visuals[a].position.x < bolt_visuals[b].position.x)
			print("snapdriver: bolt ", move.animation_label, " from slot ", slots[0], " to ", slots[-1])
			current_scene.call("_fire_projectile", slots[0], slots[-1], move, {})
		if frame in _frames:
			await _capture("%s_f%04d.png" % [_args["out"], frame])
	_walk("%s_walk.txt" % _args["out"])
	if _args.has("scan"):
		_scan("%s_scan.tsv" % _args["out"])


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_stretch = float(image.get_width()) / root.get_visible_rect().size.x
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	print("snapdriver: %s %dx%d stretch %.2f" % [path.get_file(), image.get_width(), image.get_height(), float(image.get_width()) / root.get_visible_rect().size.x])


# Lists canvas items whose drawn origin differs from their layout origin, using the two
# rounding rules at control.cpp:760-761 and renderer_canvas_cull.cpp:361-364.
func _walk(path: String) -> void:
	var lines: Array[String] = []
	var scale_factor := _stretch
	var stack: Array[Dictionary] = []
	for child in root.get_children():
		if child is CanvasItem or child is CanvasLayer:
			stack.append({"n": child, "f": Transform2D.IDENTITY.scaled(Vector2.ONE * scale_factor), "e": Transform2D.IDENTITY.scaled(Vector2.ONE * scale_factor)})
	var fractional := 0
	var total := 0
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		var node: Node = entry["n"]
		var drawn: Transform2D = entry["f"]
		var exact: Transform2D = entry["e"]
		if node is CanvasItem and node.visible:
			var own: Transform2D = node.get_transform()
			var rounded := own
			rounded.origin = (own.origin + Vector2(0.5, 0.5)).floor()
			var parent_rounded := drawn
			parent_rounded.origin = (drawn.origin + Vector2(0.5, 0.5)).floor()
			drawn = parent_rounded * rounded
			exact = exact * own
			total += 1
			if own.origin.distance_to(rounded.origin) > 0.001:
				fractional += 1
			var moved := drawn.origin.distance_to(exact.origin) / scale_factor
			if moved >= 0.05:
				lines.append("%.2f\t%s\t%s\tlocal=(%.2f,%.2f)\tlayout=(%.2f,%.2f)\tdrawn=(%.2f,%.2f)" % [moved, node.get_class(), root.get_path_to(node), own.origin.x, own.origin.y, exact.origin.x / scale_factor, exact.origin.y / scale_factor, drawn.origin.x / scale_factor, drawn.origin.y / scale_factor])
		elif node is CanvasItem:
			continue
		for child in node.get_children():
			if child is CanvasItem or child is CanvasLayer:
				stack.append({"n": child, "f": drawn, "e": exact})
	lines.sort_custom(func(a: String, b: String) -> bool: return a.to_float() > b.to_float())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_line("canvas items %d, with a fractional local offset %d, moved by snapping at least 0.05 design px %d, stretch %.3f" % [total, fractional, lines.size(), scale_factor])
	for line in lines:
		file.store_line(line)
	print("snapdriver: walk ", total, " items, fractional ", fractional, ", moved ", lines.size())


func _synthetic() -> void:
	var canvas := Control.new()
	canvas.size = root.get_visible_rect().size
	root.add_child(canvas)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.size = canvas.size
	canvas.add_child(back)

	var box := Control.new()
	box.position = Vector2(10.3, 10.3)
	canvas.add_child(box)
	var box2 := Control.new()
	box2.position = Vector2(20.4, 0.0)
	box.add_child(box2)
	var leaf := ColorRect.new()
	leaf.position = Vector2(30.2, 0.0)
	leaf.size = Vector2(40, 40)
	leaf.color = Color.RED
	box2.add_child(leaf)

	var n1 := Node2D.new()
	n1.position = Vector2(10.3, 70.3)
	canvas.add_child(n1)
	var n2 := Node2D.new()
	n2.position = Vector2(20.4, 0.0)
	n1.add_child(n2)
	var image := Image.create(40, 40, false, Image.FORMAT_RGB8)
	image.fill(Color.GREEN)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.position = Vector2(30.2, 0.0)
	n2.add_child(sprite)

	var fractions: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
	var sizes: Array[int] = [12, 16]
	var filters := {"inherit": CanvasItem.TEXTURE_FILTER_PARENT_NODE, "linear": CanvasItem.TEXTURE_FILTER_LINEAR}
	var y := 130.0
	for size_name in sizes:
		for filter_name in filters:
			for i in fractions.size():
				var label := Label.new()
				label.text = "Hamburgefonstiv 0123 Attack"
				label.add_theme_font_size_override("font_size", size_name)
				label.add_theme_color_override("font_color", Color.WHITE)
				label.position = Vector2(20.0 + fractions[i], y + fractions[i])
				label.texture_filter = filters[filter_name]
				canvas.add_child(label)
				print("snapdriver: label %d %s %.3f y=%.3f" % [size_name, filter_name, fractions[i], y + fractions[i]])
				y += size_name + 6
	for _i in 4:
		await process_frame
	await _capture(_args["out"] + ".png")



# Lists every visible textured canvas item with how many texels land on one window pixel.
func _scan(path: String) -> void:
	var window_scale: float = _stretch
	var lines: Array[String] = ["family\tfile\tnode_class\ttex_w\ttex_h\tdesign_scale_x\tdesign_scale_y\trotated\ttexels_per_window_px_x\ttexels_per_window_px_y\tfrac_x\tfrac_y\tnode"]
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CanvasItem and not node.is_visible_in_tree():
			continue
		for child in node.get_children():
			stack.append(child)
		if not node is CanvasItem:
			continue
		for item: Array in _textures_of(node):
			var tex: Texture2D = item[0]
			var local: Vector2 = item[1]
			if tex == null:
				continue
			var xf: Transform2D = node.get_global_transform()
			var global_scale: Vector2 = xf.get_scale()
			var scale_x: float = absf(local.x * global_scale.x)
			var scale_y: float = absf(local.y * global_scale.y)
			var origin: Vector2 = xf.origin * window_scale
			var source: Texture2D = tex
			if tex is AtlasTexture:
				source = tex.atlas
			var res_path: String = source.resource_path
			var family: String = res_path.get_base_dir() if res_path != "" else "runtime"
			var tx: float = 1.0 / (scale_x * window_scale) if scale_x > 0 else 0.0
			var ty: float = 1.0 / (scale_y * window_scale) if scale_y > 0 else 0.0
			lines.append("%s\t%s\t%s\t%d\t%d\t%.4f\t%.4f\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%s" % [
				family, res_path.get_file(), node.get_class(), tex.get_width(), tex.get_height(),
				scale_x, scale_y, str(absf(xf.get_rotation()) > 0.001), tx, ty,
				fposmod(origin.x, 1.0), fposmod(origin.y, 1.0), root.get_path_to(node),
			])
	var file := FileAccess.open(path, FileAccess.WRITE)
	for line in lines:
		file.store_line(line)
	print("filterdriver: scan ", lines.size() - 1, " textured items, window scale ", window_scale)


func _textures_of(node: Node) -> Array:
	var found: Array = []
	if node is TextureRect and node.texture != null:
		var tex: Texture2D = node.texture
		var ratio: Vector2 = node.size / tex.get_size()
		match node.stretch_mode:
			TextureRect.STRETCH_SCALE:
				found.append([tex, ratio])
			TextureRect.STRETCH_TILE, TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED:
				found.append([tex, Vector2.ONE])
			TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				found.append([tex, Vector2.ONE * minf(ratio.x, ratio.y)])
			TextureRect.STRETCH_KEEP_ASPECT_COVERED:
				found.append([tex, Vector2.ONE * maxf(ratio.x, ratio.y)])
	elif node is Sprite2D and node.texture != null:
		found.append([node.texture, Vector2.ONE])
	elif node is AnimatedSprite2D and node.sprite_frames != null:
		var frames: SpriteFrames = node.sprite_frames
		if frames.has_animation(node.animation) and frames.get_frame_count(node.animation) > 0:
			found.append([frames.get_frame_texture(node.animation, node.frame), Vector2.ONE])
	elif node is NinePatchRect and node.texture != null:
		found.append([node.texture, node.size / node.texture.get_size()])
	elif node is TextureButton:
		var tex: Texture2D = node.texture_normal
		if tex != null:
			var ratio: Vector2 = node.size / tex.get_size() if node.ignore_texture_size else Vector2.ONE
			found.append([tex, ratio])
	elif node is TextureProgressBar:
		for tex: Texture2D in [node.texture_under, node.texture_progress, node.texture_over]:
			if tex != null:
				found.append([tex, node.size / tex.get_size()])
	elif node is Button and node.icon != null:
		found.append([node.icon, Vector2.ONE])
	elif node is Panel or node is PanelContainer:
		var box := (node as Control).get_theme_stylebox("panel")
		if box is StyleBoxTexture and box.texture != null:
			found.append([box.texture, (node as Control).size / box.texture.get_size()])
	return found



func _halls() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_args["pairs"]))
	var stage := Control.new()
	stage.size = Vector2(800, 600)
	root.add_child(stage)
	var fill := ColorRect.new()
	fill.color = Color.BLACK
	stage.add_child(fill)
	var sky := TextureRect.new()
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	stage.add_child(sky)
	var hall := TextureRect.new()
	hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hall.stretch_mode = TextureRect.STRETCH_SCALE
	stage.add_child(hall)
	var pairs: Array = data["pairs"]
	for i in pairs.size():
		var hall_name: String = String(pairs[i][0]).replace(" ", "_")
		var sky_name: String = String(pairs[i][1]).replace(" ", "_")
		var hall_rect: Dictionary = data["halls"][hall_name]
		var sky_rect: Dictionary = data["skies"][sky_name]
		hall.texture = load("res://assets/backgrounds/battle/%s.png" % hall_name)
		sky.texture = load("res://assets/backgrounds/sky/SKY_%s.png" % sky_name)
		hall.position = Vector2(hall_rect["x"], hall_rect["y"])
		hall.size = Vector2(hall_rect["w"], hall_rect["h"])
		sky.position = Vector2(sky_rect["x"], sky_rect["y"])
		sky.size = Vector2(sky_rect["w"], sky_rect["h"])
		fill.position = Vector2.ZERO
		fill.size = Vector2(800, float(sky_rect["y"]) + 2.0)
		for _f in 3:
			await process_frame
		await _capture("%s_%02d.png" % [_args["out"], i])
