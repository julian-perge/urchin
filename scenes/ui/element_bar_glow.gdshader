// One Glow of an element bar layer (scripts/ui/menu/element_bar.gd), drawn as
// Flash draws a Glow filter on a plain rectangle. Flash blurs the layer's alpha
// with a box blur, one pass for each of the filter's passes, multiplies the
// result by the strength and limits it to 1. Three passes of one box width are
// the same as one blur with a quadratic B-spline kernel, three box widths
// across, and the blur of a rectangle is the product of one blur of its
// width and one of its height. So the shader needs no texture: it integrates
// the kernel over the rectangle's two sides.
//
// The node is larger than the rectangle by `reach` on every side, so the blur
// has room. `node_size` is the node's size in px.
shader_type canvas_item;

uniform vec2 node_size = vec2(1.0);
uniform float reach = 0.0;
// The width of one box of the blur, in px.
uniform vec2 blur = vec2(9.0);
uniform float strength = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

// The shader replaces the node's colour, so the modulate of the nodes above has
// to be carried to the result by hand.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

// The integral of the kernel from far left to the point at u, where the kernel
// spans u = 0 to 3 and its three pieces are u^2 / 2, (-2u^2 + 6u - 3) / 2 and
// (3 - u)^2 / 2.
float kernel_integral(float u) {
	if (u <= 0.0) {
		return 0.0;
	}
	if (u < 1.0) {
		return u * u * u / 6.0;
	}
	if (u < 2.0) {
		return 0.5 - u * u * u / 3.0 + 1.5 * u * u - 1.5 * u;
	}
	if (u < 3.0) {
		float rest = 3.0 - u;
		return 1.0 - rest * rest * rest / 6.0;
	}
	return 1.0;
}

// How much of the kernel centred on `point` lies over the span start to end.
float covered(float point, float start, float end, float width) {
	return kernel_integral((point - start) / width + 1.5) - kernel_integral((point - end) / width + 1.5);
}

void fragment() {
	vec2 point = UV * node_size;
	float cover = covered(point.x, reach, node_size.x - reach, blur.x) * covered(point.y, reach, node_size.y - reach, blur.y);
	COLOR = vec4(tint.rgb, clamp(cover * strength, 0.0, 1.0) * tint.a) * modulate;
}
