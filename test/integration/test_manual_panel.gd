# Tests for the Game Manual panel, the original's designMenu, root frame 124
# (spec/107-game-manual.md). The texts are read from strings.json here, so the
# panel's own reads are checked against the file and not against themselves.
extends GutTest

const ManualPanelScene = preload("res://scenes/ui/menu/manual_panel.tscn")
var _strings: Dictionary


func before_all() -> void:
	_strings = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))


func _panel() -> ManualPanel:
	var panel: ManualPanel = add_child_autofree(ManualPanelScene.instantiate())
	await get_tree().process_frame
	return panel


# frame_124/DoAction.as fills xRx1 to xRx5 from MANUAL[0] to MANUAL[4] and
# xRx6 from EXPLAINEXTRA.
func test_open_shows_the_five_topics_and_asks_for_one() -> void:
	var panel: ManualPanel = await _panel()
	panel.open()
	assert_eq(panel.get_node("Topics").get_child_count(), _strings["MANUAL"].size(), "one topic for each MANUAL caption")
	for n in _strings["MANUAL"].size():
		assert_eq(panel.get_node("Topics/Topic%d/Caption" % n).text, _strings["MANUAL"][n])
	assert_eq(panel.get_node("Body").text, _strings["EXPLAINEXTRA"])
	assert_eq(panel.get_node("Body").text, "Please select a topic.")


# Topic n from the top is the hit button that sets xRx6 to MANUALEX[n]
# (DefineButton2_2800, 2804, 2803, 2802 and 2801, on(release)).
func test_a_press_on_a_topic_shows_its_text() -> void:
	var panel: ManualPanel = await _panel()
	panel.open()
	for n in _strings["MANUALEX"].size():
		panel.get_node("Topics/Topic%d/HitButton" % n).pressed.emit()
		assert_eq(panel.get_node("Body").text, _strings["MANUALEX"][n], "topic %d" % n)


# The frame script runs on every entry to designMenu, so a second open asks
# for a topic again.
func test_open_after_a_topic_asks_for_a_topic_again() -> void:
	var panel: ManualPanel = await _panel()
	panel.open()
	panel.get_node("Topics/Topic3/HitButton").pressed.emit()
	panel.open()
	assert_eq(panel.get_node("Body").text, "Please select a topic.")


# The original's field has no scroll bar, so every text has to fit the field's
# rect. A Label whose lines do not fit grows past its offsets.
func test_every_topic_text_fits_the_body_field() -> void:
	var panel: ManualPanel = await _panel()
	var body: Label = panel.get_node("Body")
	var height: float = body.size.y
	for n in _strings["MANUALEX"].size():
		panel.show_topic(n)
		await get_tree().process_frame
		assert_eq(body.get_visible_line_count(), body.get_line_count(), "topic %d shows every line" % n)
		assert_almost_eq(body.size.y, height, 0.01, "topic %d keeps the field's height" % n)
