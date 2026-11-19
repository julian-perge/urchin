// An outer DropShadow on everything a CanvasGroup holds, drawn as Flash draws
// one with a single blur pass and composite_source on. It averages the group's
// alpha over a box as wide as the blur, at the point the shadow's distance and
// angle move it from, multiplies that by the strength, limits it to 1, and
// paints the shadow's colour at that amount times the colour's own alpha behind
// what the group drew. The status bar's Clip uses it for the filter on each
// p#BAR placement. It leaves COLOR out, as scenes/doll_body.gdshader does,
// because Godot already applies the modulate of the group's parents to what is
// inside it.
shader_type canvas_item;
render_mode unshaded;

#include "res://scenes/box_blur.gdshaderinc"

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// The blur box and the distance in stage px, and the angle in degrees, as the
// SWF gives them. Flash measures a filter in stage px, not in the clip's own
// scaled px, so stage_scale is the screen px for each stage px.
uniform vec2 blur = vec2(0.0);
uniform float distance = 0.0;
uniform float angle = 0.0;
uniform float strength = 1.0;
uniform float stage_scale = 1.0;
uniform sampler2D picture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec2 stage_pixel = SCREEN_PIXEL_SIZE * stage_scale;
	vec2 offset = vec2(cos(radians(angle)), sin(radians(angle))) * distance * stage_pixel;
	float cover = box_alpha(picture, SCREEN_UV - offset, blur * stage_pixel);
	float shadow = clamp(cover * strength, 0.0, 1.0) * shadow_color.a;
	// The screen texture holds premultiplied alpha, so the shadow goes under
	// the drawn pixel in that form, and the sum is turned back at the end.
	vec4 drawn = texture(picture, SCREEN_UV);
	drawn += vec4(shadow_color.rgb * shadow, shadow) * (1.0 - drawn.a);
	if (drawn.a > 0.0001) {
		drawn.rgb /= drawn.a;
	}
	COLOR = drawn;
}
