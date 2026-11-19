// The DropShadow of the World map's links, the filter on lineMC, drawn as Flash
// draws a DropShadow with one blur pass. The links draw opaque into this
// CanvasGroup, already moved by the shadow's distance at its angle. This
// averages their alpha over a box as wide as the blur, multiplies that by the
// strength, limits it to 1, and paints the shadow's colour at that amount times
// the colour's own alpha. So two links that cross make one shadow, as Flash's
// one filter on the whole of lineMC does. It does not multiply by the COLOR that
// comes in, as scenes/doll_body.gdshader does not, because Godot already applies
// the modulate of the group's parents to the lines inside it.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// The blur box in stage px, and the screen px for each stage px.
uniform vec2 blur = vec2(0.0);
uniform float strength = 1.0;
uniform float stage_scale = 1.0;
uniform sampler2D lines : hint_screen_texture, repeat_disable, filter_linear;

const int TAPS = 6;

void fragment() {
	vec2 stage_pixel = SCREEN_PIXEL_SIZE * stage_scale;
	float sum = 0.0;
	for (int x = -TAPS; x <= TAPS; x++) {
		for (int y = -TAPS; y <= TAPS; y++) {
			vec2 at = SCREEN_UV + vec2(float(x), float(y)) / float(2 * TAPS) * blur * stage_pixel;
			sum += texture(lines, at).a;
		}
	}
	float cover = sum / float((2 * TAPS + 1) * (2 * TAPS + 1));
	COLOR = vec4(shadow_color.rgb, shadow_color.a * clamp(cover * strength, 0.0, 1.0));
}
