// One layer of a hotbar icon's hover Glow (scripts/ui/hotbar.gd). It draws the
// blurred alpha of the icon's texture in the node's modulate color. The node
// is larger than the icon, so the blur has room around it.
shader_type canvas_item;

// The node's size over the icon's size.
uniform vec2 grow = vec2(1.0);
// The blur radius over the icon's size.
uniform vec2 radius = vec2(0.0);
uniform float strength = 1.0;

const int TAPS = 6;

void fragment() {
	vec2 uv = (UV - 0.5) * grow + 0.5;
	float sum = 0.0;
	float weight = 0.0;
	for (int x = -TAPS; x <= TAPS; x++) {
		for (int y = -TAPS; y <= TAPS; y++) {
			vec2 tap = vec2(float(x), float(y)) / float(TAPS);
			float w = exp(-2.5 * dot(tap, tap));
			vec2 at = uv + tap * radius;
			// The texture clamps at its edge, and a tap past it has to read as empty.
			bool inside = all(greaterThanEqual(at, vec2(0.0))) && all(lessThanEqual(at, vec2(1.0)));
			sum += w * (inside ? texture(TEXTURE, at).a : 0.0);
			weight += w;
		}
	}
	COLOR = vec4(COLOR.rgb, COLOR.a * clamp(sum / weight * strength, 0.0, 1.0));
}
