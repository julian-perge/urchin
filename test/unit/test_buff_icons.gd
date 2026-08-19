# BuffIcons.icon_for() resolves a Buff to its real extracted icon
# (dev/urchin_dev/swf/extract/buff_icons.py - assets/ui/buffs/<internal_name>.png).
extends GutTest


func test_icon_for_returns_a_real_texture_for_a_real_buff():
	var buff: Buff = BuffManagerAuto.buffs_by_internal_name.get("FIRESAM")
	assert_not_null(buff, "FIRESAM exists in the real buff data")
	var texture: Texture2D = BuffIcons.icon_for(buff)
	assert_not_null(texture, "resolves to a real icon texture")


func test_icon_for_returns_null_for_unknown_buff():
	var fake_buff: Buff = Buff.new()
	fake_buff.internal_name = "NOT_A_REAL_BUFF_NAME"
	assert_null(BuffIcons.icon_for(fake_buff), "no icon exists for a made-up name")
