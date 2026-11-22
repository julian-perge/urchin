# Records the size that GameTooltip has on each frame the game draws it.
# SceneTree emits process_frame before any node runs _process, so the tooltip
# still has the size that the previous frame drew. A headless run draws
# nothing, so this is the closest a test gets to the drawn frame.
extends RefCounted

# The most frames to wait for every section to show. The ability icon delay is
# 5 frames at 30 fps, and a headless run steps far more often than that.
const MAX_FRAMES: int = 300
# The frames to keep recording after every section shows.
const FRAMES_AFTER_DETAILS: int = 3


# -> one [details_shown, size] pair for each drawn frame on which the tooltip
# shows, from the hover until every section has shown for a few frames.
# details_shown is false while an ability icon's tooltip shows its title alone.
# The game gets mouse_entered from an input event, before any node runs
# _process, so the hover runs inside a process_frame emission too.
static func record(tree: SceneTree, hover: Callable) -> Array:
	var frames: Array = []
	var recorder: Callable = func() -> void:
		if GameTooltip.is_showing():
			frames.append([_details_shown(), GameTooltip.box_size()])
	await tree.process_frame
	hover.call()
	tree.process_frame.connect(recorder)
	var after_details: int = 0
	for i in MAX_FRAMES:
		await tree.process_frame
		if _details_shown():
			after_details += 1
		if after_details > FRAMES_AFTER_DETAILS:
			break
	tree.process_frame.disconnect(recorder)
	return frames


# -> the stages that the frames show, in order: false for the title alone and
# true for every section.
static func stages(frames: Array) -> Array:
	var found: Array = []
	for frame: Array in frames:
		if not found.has(frame[0]):
			found.append(frame[0])
	return found


# -> the frames whose size differs from the size of the last frame of the same
# stage. Each stage keeps one size from its first frame, so this is empty when
# the tooltip never draws at a size it does not keep.
static func resized_frames(frames: Array) -> Array:
	var last_size: Dictionary = {}
	for frame: Array in frames:
		last_size[frame[0]] = frame[1]
	var resized: Array = []
	for frame: Array in frames:
		if frame[1] != last_size[frame[0]]:
			resized.append(frame)
	return resized


static func _details_shown() -> bool:
	var sections: Array[Node] = GameTooltip.sections()
	return sections.size() > 1 and (sections[1] as Control).visible
