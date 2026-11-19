// A doll piece's colour transform from its model's frame
// (extract_model_pieces): each channel of the art times its multiplier plus its
// offset, as Flash applies a ColorTransform, then times the piece's modulate.
// The fragment's COLOR comes in already multiplied by the texture, so the
// modulate is kept from the vertex function instead.
shader_type canvas_item;

uniform vec4 multiplier = vec4(1.0);
uniform vec4 offset = vec4(0.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = clamp(texture(TEXTURE, UV) * multiplier + offset, 0.0, 1.0) * tint;
}
