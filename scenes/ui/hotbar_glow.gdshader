// One Glow of a hotbar icon's hover (scripts/ui/hotbar.gd), drawn as Flash
// draws a Glow filter with one blur pass. It averages the alpha of the icon's
// texture over a square box, multiplies that by the strength and limits it to
// 1. An outer Glow shows that amount around the icon, on a node that is larger
// than the icon so the blur has room. An inner Glow shows the rest of that
// amount inside the icon's shape, on a node of the icon's size. The amount
// picks the colour between `low` and `high`, which a plain Glow sets to its
// colour at alpha 0 and at alpha 1, and a GradientGlow sets to its two stops.
shader_type canvas_item;

// The node's size over the icon's size.
uniform vec2 grow = vec2(1.0);
// The width of the blur box over the icon's size.
uniform vec2 blur = vec2(0.0);
uniform float strength = 0.0;
uniform bool inner = false;
uniform vec4 low : source_color = vec4(0.0);
uniform vec4 high : source_color = vec4(1.0);

const int TAPS = 6;

// The shader replaces the texture's colour, so the modulate of the nodes above
// has to be carried to the result by hand.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec2 uv = (UV - 0.5) * grow + 0.5;
	float sum = 0.0;
	for (int x = -TAPS; x <= TAPS; x++) {
		for (int y = -TAPS; y <= TAPS; y++) {
			vec2 at = uv + vec2(float(x), float(y)) / float(2 * TAPS) * blur;
			// The texture clamps at its edge, and a tap past it has to read as empty.
			bool inside = all(greaterThanEqual(at, vec2(0.0))) && all(lessThanEqual(at, vec2(1.0)));
			sum += inside ? texture(TEXTURE, at).a : 0.0;
		}
	}
	float cover = sum / float((2 * TAPS + 1) * (2 * TAPS + 1));
	float amount = clamp((inner ? 1.0 - cover : cover) * strength, 0.0, 1.0);
	vec4 glow = mix(low, high, amount);
	if (inner) {
		glow.a *= texture(TEXTURE, uv).a;
	}
	COLOR = glow * modulate;
}
