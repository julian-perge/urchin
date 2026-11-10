# floating_number_layer.gd
# The one layer every Floating number of a battle goes on, the original's
# BATTLESCREEN at depths 1620 to 1639. KrinNumberShow attaches each NumberFixer
# one depth above the last and goes from 1639 back to 1620
# (frame_42/DoAction_7.as:4 and 75-79). So this keeps 20 slots and puts each
# new number in the next one, and a number replaces any number still in its
# slot. A later slot draws over an earlier one, as a higher depth does.
#
# show_number(), show_miss() and show_shield() are KrinNumberShow's three
# branches. Each one takes the target rig's origin, where the original puts the
# number with no offset (lines 38-39).
extends Node2D
class_name FloatingNumberLayer

const LAYOUT_PATH: String = "res://assets/ui/battle/floating_number/floating_number.json"
const SLOTS: int = 20
# numberSpacingKrin, the distance between two digits along the holder
# (frame_42/DoAction_7.as:3).
const DIGIT_SPACING: float = 19.0

var _layout: Dictionary = {}
var _slots: Array[Node2D] = []
var _next: int = 0


func _init() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	for i in SLOTS:
		var slot := Node2D.new()
		add_child(slot)
		_slots.append(slot)


func _process(delta: float) -> void:
	advance(delta)


# Steps every live number on by `delta` seconds. _process() passes the real
# time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	for number in numbers():
		number.advance(delta)


# The live Floating numbers, oldest first.
func numbers() -> Array[FloatingNumber]:
	var live: Array[FloatingNumber] = []
	for i in SLOTS:
		for number in _slots[(_next + i) % SLOTS].get_children():
			live.append(number)
	return live


# A number of 0 or less draws nothing (frame_42/DoAction_7.as:8). The digit
# loop drops any fraction, so a number under 1 still takes a slot and plays its
# label, with no digits. The first digit sits at -19 * (digits - 2) / 2 - 10
# and the rest follow DIGIT_SPACING apart (lines 34-35 and 56).
func show_number(anchor: Vector2, amount: float, color: Color, critical: bool) -> void:
	if amount <= 0.0:
		return
	var digits: Array[String] = []
	if amount >= 1.0:
		for digit in str(int(amount)):
			digits.append(digit)
	var first: float = -DIGIT_SPACING * (digits.size() - 2) / 2.0 - 10.0
	var offsets: Array[float] = []
	for i in digits.size():
		offsets.append(first + DIGIT_SPACING * i)
	_show(anchor, "critical" if critical else "normal", color, digits, offsets)


# The MISS word's KN fill takes `color` (frame_42/DoAction_7.as:63-68).
func show_miss(anchor: Vector2, color: Color) -> void:
	_show_word(anchor, "miss", color)


# SHIELDED has no KN fill, so it takes no color.
func show_shield(anchor: Vector2) -> void:
	_show_word(anchor, "shield", Color.WHITE)


# A word label's holder is the word itself, so the word sits at the holder's
# own origin.
func _show_word(anchor: Vector2, label: String, color: Color) -> void:
	var word: Array[String] = [_layout["labels"][label]["word"]]
	var offsets: Array[float] = [0.0]
	_show(anchor, label, color, word, offsets)


func _show(anchor: Vector2, label: String, color: Color, glyphs: Array[String], offsets: Array[float]) -> void:
	var slot: Node2D = _slots[_next]
	for old in slot.get_children():
		slot.remove_child(old)
		old.queue_free()
	var number := FloatingNumber.new()
	number.position = anchor
	slot.add_child(number)
	number.setup(_layout, label, color, glyphs, offsets)
	_next = (_next + 1) % SLOTS
