# Art draws LINEAR from the project's default texture filter, and the NearestText
# autoload (scripts/autoload/nearest_text.gd) keeps text NEAREST.
extends GutTest

const LINEAR_DEFAULT: int = 1


func test_project_default_filter_is_linear():
	assert_eq(
		ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"),
		LINEAR_DEFAULT,
	)


func test_label_comes_out_nearest():
	var label: Label = Label.new()
	add_child_autofree(label)
	assert_eq(label.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_rich_text_label_comes_out_nearest():
	var rich_text: RichTextLabel = RichTextLabel.new()
	add_child_autofree(rich_text)
	assert_eq(rich_text.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_line_edit_comes_out_nearest():
	var line_edit: LineEdit = LineEdit.new()
	add_child_autofree(line_edit)
	assert_eq(line_edit.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_text_edit_comes_out_nearest():
	var text_edit: TextEdit = TextEdit.new()
	add_child_autofree(text_edit)
	assert_eq(text_edit.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_button_with_text_comes_out_nearest():
	var button: Button = Button.new()
	button.text = "Buy"
	add_child_autofree(button)
	assert_eq(button.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_label_entering_inside_a_parent_comes_out_nearest():
	var parent: Control = Control.new()
	var label: Label = Label.new()
	parent.add_child(label)
	add_child_autofree(parent)
	assert_eq(label.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(parent.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)


func test_texture_rect_stays_on_parent_node():
	var texture_rect: TextureRect = TextureRect.new()
	add_child_autofree(texture_rect)
	assert_eq(texture_rect.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)


func test_button_with_only_an_icon_stays_on_parent_node():
	var button: Button = Button.new()
	button.icon = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_child_autofree(button)
	assert_eq(button.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)
