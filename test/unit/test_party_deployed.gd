# Party.toggle_deployed: the shift-click rule of a party face. The original is
# DefineButton2_2895 on(press) lines 2-29, with bickerPicker and updateFriends
# in DefineSprite_3142/frame_1/DoAction.as.
extends GutTest


func _save(deployed: Array) -> PlayerSave:
	var save := PlayerSave.new_game("DeployedTest", 0)
	save.party_roster = [0, 1, 2, 3, -1, -1]
	save.party_deployed = deployed
	return save


func test_a_member_in_the_pair_leaves_a_0_and_the_picker_points_at_that_slot() -> void:
	var save := _save([1, 2])
	var picker: int = Party.toggle_deployed(save, 2, 0)
	assert_eq(save.party_deployed, [1, 0])
	assert_eq(picker, 1)
	picker = Party.toggle_deployed(save, 1, picker)
	assert_eq(save.party_deployed, [0, 0])
	assert_eq(picker, 0)


func test_a_member_outside_the_pair_takes_the_picked_slot_and_the_picker_flips() -> void:
	var save := _save([0, 0])
	var picker: int = Party.toggle_deployed(save, 3, 0)
	assert_eq(save.party_deployed, [3, 0])
	assert_eq(picker, 1)
	picker = Party.toggle_deployed(save, 1, picker)
	assert_eq(save.party_deployed, [3, 1])
	assert_eq(picker, 0)


func test_a_member_added_to_a_full_pair_replaces_the_picked_slot() -> void:
	var save := _save([1, 2])
	var picker: int = Party.toggle_deployed(save, 3, 0)
	assert_eq(save.party_deployed, [3, 2], "the picker replaces slot 0 first")
	assert_eq(picker, 1)
	picker = Party.toggle_deployed(save, 1, picker)
	assert_eq(save.party_deployed, [3, 1], "then slot 1")
	assert_eq(picker, 0)


func test_the_player_never_joins_the_pair() -> void:
	var save := _save([1, 2])
	var picker: int = Party.toggle_deployed(save, Party.PLAYER_PARTY_ID, 1)
	assert_eq(save.party_deployed, [1, 2])
	assert_eq(picker, 1, "the original's player face ignores the shift-click")


func test_the_picker_starts_on_the_last_empty_slot() -> void:
	assert_eq(Party.initial_deploy_picker([1, 2]), 0)
	assert_eq(Party.initial_deploy_picker([0, 2]), 0)
	assert_eq(Party.initial_deploy_picker([1, 0]), 1)
	assert_eq(Party.initial_deploy_picker([0, 0]), 1, "the original checks slot 1 after slot 0")


func test_a_0_in_the_pair_spawns_no_companion() -> void:
	var save := _save([0, 2])
	assert_eq(Party.deployed_party_id(save, -2), -1)
	assert_eq(Party.deployed_party_id(save, -1), 2)


func test_the_deployed_pair_survives_a_save_and_load() -> void:
	var save := _save([3, 0])
	var path: String = "user://test_party_deployed.tres"
	assert_eq(ResourceSaver.save(save, path), OK)
	var loaded: PlayerSave = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(path)
	assert_eq(loaded.party_deployed, [3, 0])
