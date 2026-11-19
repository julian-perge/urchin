// A doll piece's colour transform from its model's frame
// (extract_model_pieces): each channel of the art times its multiplier plus its
// offset, as Flash applies a ColorTransform, then the piece's modulate.
shader_type canvas_item;

uniform vec4 multiplier = vec4(1.0);
uniform vec4 offset = vec4(0.0);

void fragment() {
	COLOR *= clamp(texture(TEXTURE, UV) * multiplier + offset, 0.0, 1.0);
}
