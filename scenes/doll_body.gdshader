// The doll's body, a CanvasGroup, drawn from the screen texture its parts were
// drawn into. Godot 4.7.2 applies the doll's modulate to the parts inside a
// CanvasGroup and again to the CanvasGroup's own draw, so this leaves COLOR out.
// With COLOR in, a cast tint and the death fade showed twice: measured on
// 2026-11-10, the tinted doll came out at the plain doll times the tint again.
//
// During a Result flash it also runs the three GlowFilters each of BATTLEFLASH's
// labels sets on the original's whole doll, in this order: a white inner glow,
// then an outer glow and an inner glow in the label's color
// (frame_42/DoAction_3.as:117-130 and 162-168). Each GlowFilter has quality 1,
// so it averages the alpha over one box as wide as its blur, multiplies that by
// its strength and caps it at 1. An inner glow averages the alpha outside the
// doll and paints over the doll, and an outer glow averages the doll's alpha and
// paints behind it. Each filter reads what the one before it left. The screen
// texture holds premultiplied alpha, and this works in it until the last step.
//
// Outside a Result flash it draws the filter list that the doll's buffs give it
// (applyChangesKrin, frame_42/DoAction_10.as:380-466): up to two GlowFilters,
// each inner or outer and each with or without a knockout, and then the color
// offsets that krinChangeColor adds. A color transform applies to a clip after
// its filters, so the offsets reach the glows too. A Result flash replaces
// both, as BATTLEFLASH's scripts replace the filters and the color of the doll
// for the frames the flash is on (DefineSprite_3416/frame_2 and frame_4).
shader_type canvas_item;
render_mode unshaded;

#include "res://scenes/box_blur.gdshaderinc"

uniform bool result_flash = false;
uniform vec4 color : source_color = vec4(1.0);
// Screen px for each stage px, because Flash measures a blur in stage px.
uniform float stage_scale = 1.0;
// The blur and the strength of the white glow and of the two colored glows.
// CharacterVisual.show_result_flash() sets them from result_flash.json, which
// extract_result_flash writes from those GlowFilters.
uniform float white_blur;
uniform float white_strength;
uniform float color_blur;
uniform float color_strength;
uniform sampler2D doll : hint_screen_texture, repeat_disable, filter_linear;

// What the doll's buffs give it, which CharacterVisual.show_buff_look() sets.
// buff_offset is the three offsets of the ColorTransform in 0 to 1. Each glow
// has its color, and its blur in stage px, its strength, 1.0 for an inner glow
// and 1.0 for a knockout in buff_params_<a, b>.
uniform vec3 buff_offset = vec3(0.0);
uniform int buff_glows = 0;
uniform vec4 buff_color_a : source_color = vec4(1.0);
uniform vec4 buff_params_a = vec4(0.0);
uniform vec4 buff_color_b : source_color = vec4(1.0);
uniform vec4 buff_params_b = vec4(0.0);

// The loops below that work a glow out at each sample keep their own copy of
// box_alpha's 5 by 5 grid, because what they average is not the doll's alpha.
const int SAMPLES = BOX_SAMPLES;

float outer_glow(vec2 uv, vec2 stage_pixel) {
	return clamp(box_alpha(doll, uv, vec2(color_blur) * stage_pixel) * color_strength, 0.0, 1.0);
}

// The alpha the outer glow leaves, which the third glow reads, averaged over its
// box. Each sample works the outer glow out again where it lands.
float box_alpha_after_outer_glow(vec2 uv, vec2 stage_pixel) {
	float sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		for (int j = 0; j < SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(SAMPLES) - 0.5;
			vec2 sample_uv = uv + offset * color_blur * stage_pixel;
			float alpha = texture(doll, sample_uv).a;
			sum += alpha + outer_glow(sample_uv, stage_pixel) * (1.0 - alpha);
		}
	}
	return sum / float(SAMPLES * SAMPLES);
}

// Applies one GlowFilter to `src`, a premultiplied pixel, where `average` is the
// alpha of the picture averaged over the glow's box. An outer glow paints the
// average behind the pixel and an inner glow paints what is missing from it over
// the pixel. A knockout takes the pixel's own fill away.
vec4 apply_glow(vec4 src, float average, vec4 glow_color, vec4 params) {
	vec4 glow = vec4(glow_color.rgb, 1.0);
	if (params.z > 0.5) {
		float amount = clamp((1.0 - average) * params.y, 0.0, 1.0);
		vec4 painted = glow * amount * src.a;
		return params.w > 0.5 ? painted : painted + src * (1.0 - amount);
	}
	float amount = clamp(average * params.y, 0.0, 1.0);
	vec4 painted = glow * amount * (1.0 - src.a);
	return params.w > 0.5 ? painted : src + painted;
}

// The picture after the first buff glow, at `uv`.
vec4 after_first_buff_glow(vec2 uv, vec2 stage_pixel) {
	float sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		for (int j = 0; j < SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(SAMPLES) - 0.5;
			sum += texture(doll, uv + offset * buff_params_a.x * stage_pixel).a;
		}
	}
	return apply_glow(texture(doll, uv), sum / float(SAMPLES * SAMPLES), buff_color_a, buff_params_a);
}

// The alpha of the picture after the first buff glow, averaged over the second
// glow's box.
float box_alpha_after_first_buff_glow(vec2 uv, vec2 stage_pixel) {
	float sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		for (int j = 0; j < SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(SAMPLES) - 0.5;
			sum += after_first_buff_glow(uv + offset * buff_params_b.x * stage_pixel, stage_pixel).a;
		}
	}
	return sum / float(SAMPLES * SAMPLES);
}

void fragment() {
	vec4 drawn = texture(doll, SCREEN_UV);
	if (result_flash) {
		vec2 stage_pixel = SCREEN_PIXEL_SIZE * stage_scale;
		vec4 glow_color = vec4(color.rgb, 1.0);
		float white = clamp((1.0 - box_alpha(doll, SCREEN_UV, vec2(white_blur) * stage_pixel)) * white_strength, 0.0, 1.0);
		drawn = vec4(1.0) * white * drawn.a + drawn * (1.0 - white);
		drawn += glow_color * outer_glow(SCREEN_UV, stage_pixel) * (1.0 - drawn.a);
		float inner = clamp((1.0 - box_alpha_after_outer_glow(SCREEN_UV, stage_pixel)) * color_strength, 0.0, 1.0);
		drawn = glow_color * inner * drawn.a + drawn * (1.0 - inner);
	} else if (buff_glows > 0) {
		vec2 stage_pixel = SCREEN_PIXEL_SIZE * stage_scale;
		if (buff_glows == 1) {
			drawn = after_first_buff_glow(SCREEN_UV, stage_pixel);
		} else {
			drawn = apply_glow(after_first_buff_glow(SCREEN_UV, stage_pixel), box_alpha_after_first_buff_glow(SCREEN_UV, stage_pixel), buff_color_b, buff_params_b);
		}
	}
	if (drawn.a > 0.0001) {
		drawn.rgb /= drawn.a;
		if (!result_flash) {
			drawn.rgb = clamp(drawn.rgb + buff_offset, 0.0, 1.0);
		}
	}
	COLOR = drawn;
}
