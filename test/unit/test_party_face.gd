# PartyFace (scripts/ui/menu/party_face.gd): one face of the Inventory's party
# bar, and how the inventory window sets its three states from the save. The
# original is DefineSprite_3142/frame_1/DoAction.as (updateFriends, updateAvs
# and the face loop at the bottom) and DefineButton2_2895.
extends GutTest

const FaceScene: PackedScene = preload("res://scenes/ui/menu/party_face.tscn")
const WindowScene: PackedScene = preload("res://scenes/ui/menu/inventory_window.tscn")

var _previous_save: PlayerSave


func before_each() -> void:
	_previous_save = GameData.current_save


func after_each() -> void:
	GameData.current_save = _previous_save


func _face() -> PartyFace:
	return add_child_autofree(FaceScene.instantiate())


func test_a_companion_outside_the_deployed_pair_shows_the_dim() -> void:
	var face: PartyFace = _face()
	face.show_member(3, false, false)
	assert_true(face.shows_blacker())


func test_a_deployed_companion_hides_the_dim() -> void:
	var face: PartyFace = _face()
	face.show_member(1, false, true)
	assert_false(face.shows_blacker())


func test_the_player_never_shows_the_dim() -> void:
	var face: PartyFace = _face()
	face.show_member(Party.PLAYER_PARTY_ID, true, false)
	assert_false(face.shows_blacker(), "the original hides the player's dim when the clip loads")


func test_an_unjoined_member_is_hidden_and_keeps_its_slot() -> void:
	var face: PartyFace = _face()
	face.show_member(-1, false, false)
	assert_false(face.is_joined())
	assert_false(face.shows_frame())
	assert_false(face.shows_blacker())
	assert_true(face.visible, "a hidden child of the party bar's FloatBox would move the faces after it")
	assert_false(face.get_node("Parts").visible)


func test_only_the_selected_member_shows_the_frame() -> void:
	var face: PartyFace = _face()
	face.show_member(2, false, false)
	assert_false(face.shows_frame())
	face.show_member(2, true, false)
	assert_true(face.shows_frame())


func test_a_joined_member_shows_its_portrait() -> void:
	var face: PartyFace = _face()
	face.show_member(2, false, false)
	assert_eq((face.get_node("Parts/Face") as TextureRect).texture.resource_path, "res://assets/ui/menu/portraits/roald.png")


func test_the_tooltip_of_a_companion_is_its_name_over_menu_48() -> void:
	var face: PartyFace = _face()
	face.show_member(2, false, false)
	assert_eq(face.tooltip(), {"title": "Roald", "body": Strings.menu(48)})
	assert_string_contains(Strings.menu(48), "Shift-Click")


func test_the_tooltip_of_the_player_is_the_name_over_menu_49() -> void:
	var face: PartyFace = _face()
	face.show_member(Party.PLAYER_PARTY_ID, true, false)
	assert_eq(face.tooltip(), {"title": "Sonny", "body": Strings.menu(49)})


func test_hovering_a_face_shows_its_title_and_body_in_the_shared_tooltip_and_leaving_hides_them() -> void:
	GameTooltip.hide_tooltip()
	var face: PartyFace = _face()
	face.show_member(2, false, false)
	face.hit_button.mouse_entered.emit()
	assert_true(GameTooltip._root.visible)
	assert_eq(GameTooltip._sections.get_child_count(), 2, "a title section and a body section")
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	var body: Label = GameTooltip._sections.get_child(1).get_child(0).get_child(0)
	assert_eq(title.text, face.tooltip()["title"])
	assert_eq(body.text, face.tooltip()["body"])
	face.hit_button.mouse_exited.emit()
	assert_false(GameTooltip._root.visible)


func test_an_unjoined_face_has_no_tooltip() -> void:
	var face: PartyFace = _face()
	face.show_member(-1, false, false)
	assert_true(face.tooltip().is_empty())


func test_the_window_sets_each_face_from_the_roster_and_the_deployed_pair() -> void:
	var save: PlayerSave = PlayerSave.new_game("PartyFaceTest", 0)
	save.party_roster = [0, 1, 2, -1, -1, -1]
	save.party_deployed = [2, 1]
	GameData.current_save = save
	var window: Control = add_child_autofree(WindowScene.instantiate())
	window.refresh()
	var faces: Array[PartyFace] = []
	for face: Node in window.get_node("PartyFaces").get_children():
		faces.append(face as PartyFace)
	assert_eq(faces.size(), 6)
	var joined: Array = faces.map(func(face: PartyFace) -> bool: return face.is_joined())
	assert_eq(joined, [true, true, true, false, false, false], "a member who has not joined is hidden")
	var framed: Array = faces.map(func(face: PartyFace) -> bool: return face.shows_frame())
	assert_eq(framed, [true, false, false, false, false, false], "the player is the selected member")
	var dimmed: Array = faces.map(func(face: PartyFace) -> bool: return face.shows_blacker())
	assert_eq(dimmed, [false, false, false, false, false, false], "the player and the Deployed pair show no dim")


func test_the_window_dims_a_companion_outside_the_deployed_pair() -> void:
	var save: PlayerSave = PlayerSave.new_game("PartyFaceTest", 0)
	save.party_roster = [0, 1, 2, 3, -1, -1]
	save.party_deployed = [1, 2]
	GameData.current_save = save
	var window: Control = add_child_autofree(WindowScene.instantiate())
	window.refresh()
	var faces: Node = window.get_node("PartyFaces")
	assert_false((faces.get_child(1) as PartyFace).shows_blacker())
	assert_false((faces.get_child(2) as PartyFace).shows_blacker())
	assert_true((faces.get_child(3) as PartyFace).shows_blacker())


func _window(roster: Array, deployed: Array) -> Control:
	var save: PlayerSave = PlayerSave.new_game("PartyFaceTest", 0)
	save.party_roster = roster
	save.party_deployed = deployed
	GameData.current_save = save
	var window: Control = add_child_autofree(WindowScene.instantiate())
	window.refresh()
	return window


func _faces(window: Control) -> Array[PartyFace]:
	var faces: Array[PartyFace] = []
	for face: Node in window.get_node("PartyFaces").get_children():
		faces.append(face as PartyFace)
	return faces


func test_pressing_the_hit_button_reports_the_member_and_the_shift_state() -> void:
	var face: PartyFace = _face()
	face.show_member(2, false, false)
	watch_signals(face)
	face.hit_button.pressed.emit()
	assert_signal_emitted_with_parameters(face, "chosen", [2, false])


func test_the_hit_button_acts_on_press_as_the_original_does() -> void:
	assert_eq(_face().hit_button.action_mode, BaseButton.ACTION_MODE_BUTTON_PRESS)


func test_a_plain_click_moves_the_frame_to_that_member() -> void:
	var window: Control = _window([0, 1, 2, -1, -1, -1], [1, 2])
	var faces: Array[PartyFace] = _faces(window)
	faces[2].chosen.emit(2, false)
	var framed: Array = faces.map(func(face: PartyFace) -> bool: return face.shows_frame())
	assert_eq(framed, [false, false, true, false, false, false])
	assert_eq(GameData.current_save.party_deployed, [1, 2], "a plain click leaves the Deployed pair alone")


func test_a_shift_click_on_a_deployed_companion_leaves_a_0_and_dims_them() -> void:
	var window: Control = _window([0, 1, 2, -1, -1, -1], [1, 2])
	var faces: Array[PartyFace] = _faces(window)
	faces[2].chosen.emit(2, true)
	assert_eq(GameData.current_save.party_deployed, [1, 0])
	assert_true(faces[2].shows_blacker())
	assert_false(faces[1].shows_blacker())
	assert_true(faces[0].shows_frame(), "a shift-click does not move the selection")


func test_a_shift_click_on_an_undeployed_companion_takes_the_empty_slot() -> void:
	var window: Control = _window([0, 1, 2, 3, -1, -1], [1, 0])
	var faces: Array[PartyFace] = _faces(window)
	faces[3].chosen.emit(3, true)
	assert_eq(GameData.current_save.party_deployed, [1, 3])
	assert_false(faces[3].shows_blacker())


func test_a_shift_click_on_the_player_changes_nothing() -> void:
	var window: Control = _window([0, 1, 2, -1, -1, -1], [1, 2])
	_faces(window)[0].chosen.emit(0, true)
	assert_eq(GameData.current_save.party_deployed, [1, 2])


func test_the_selection_goes_back_to_the_player_when_the_window_opens() -> void:
	var window: Control = _window([0, 1, 2, -1, -1, -1], [1, 2])
	var faces: Array[PartyFace] = _faces(window)
	faces[1].chosen.emit(1, false)
	assert_true(faces[1].shows_frame())
	window.hide()
	window.show()
	assert_true(faces[0].shows_frame())
	assert_false(faces[1].shows_frame())
