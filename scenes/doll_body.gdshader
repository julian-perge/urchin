// The doll's body, a CanvasGroup, drawn from the screen texture its parts were
// drawn into. Godot 4.7.2 applies the doll's modulate to the parts inside a
// CanvasGroup and again to the CanvasGroup's own draw, so this leaves COLOR out.
// With COLOR in, a cast tint and the death fade showed twice: measured on
// 2026-11-10, the tinted doll came out at the plain doll times the tint again.
//
// During a Result flash it also runs the three GlowFilters each of BATTLEFLASH's
// labels sets on the original's whole doll (frame_42/DoAction_3.as:117-130 and
// 162-168). Each GlowFilter has quality 1, so it averages the alpha over one box
// as wide as its blur, multiplies that by its strength and caps it at 1. An inner
// glow averages the alpha outside the doll and paints over the doll, and an outer
// glow averages the doll's alpha and paints behind it. Each filter reads what
// the one before it left. The screen texture holds premultiplied alpha, and this
// works in it until the last step.
shader_type canvas_item;
render_mode unshaded;

uniform bool result_flash = false;
uniform vec4 color : source_color = vec4(1.0);
// Screen px for each stage px, because Flash measures a blur in stage px.
uniform float stage_scale = 1.0;
uniform sampler2D doll : hint_screen_texture, repeat_disable, filter_linear;

// Each box's average is taken from a grid of SAMPLES by SAMPLES points.
const int SAMPLES = 5;
const float WHITE_BLUR = 100.0;
const float WHITE_STRENGTH = 10.0;
const float COLOR_BLUR = 10.0;
const float COLOR_STRENGTH = 1.0;

float box_alpha(vec2 uv, float blur, vec2 stage_pixel) {
	float sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		for (int j = 0; j < SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(SAMPLES) - 0.5;
			sum += texture(doll, uv + offset * blur * stage_pixel).a;
		}
	}
	return sum / float(SAMPLES * SAMPLES);
}

float outer_glow(vec2 uv, vec2 stage_pixel) {
	return clamp(box_alpha(uv, COLOR_BLUR, stage_pixel) * COLOR_STRENGTH, 0.0, 1.0);
}

// The alpha the outer glow leaves, which the third glow reads, averaged over its
// box. Each sample works the outer glow out again where it lands.
float box_alpha_after_outer_glow(vec2 uv, vec2 stage_pixel) {
	float sum = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		for (int j = 0; j < SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(SAMPLES) - 0.5;
			vec2 sample_uv = uv + offset * COLOR_BLUR * stage_pixel;
			float alpha = texture(doll, sample_uv).a;
			sum += alpha + outer_glow(sample_uv, stage_pixel) * (1.0 - alpha);
		}
	}
	return sum / float(SAMPLES * SAMPLES);
}

void fragment() {
	vec4 drawn = texture(doll, SCREEN_UV);
	if (result_flash) {
		vec2 stage_pixel = SCREEN_PIXEL_SIZE * stage_scale;
		vec4 glow_color = vec4(color.rgb, 1.0);
		// The first glow, white and inner.
		float white = clamp((1.0 - box_alpha(SCREEN_UV, WHITE_BLUR, stage_pixel)) * WHITE_STRENGTH, 0.0, 1.0);
		drawn = vec4(1.0) * white * drawn.a + drawn * (1.0 - white);
		// The second glow, outer and in the label's color.
		drawn += glow_color * outer_glow(SCREEN_UV, stage_pixel) * (1.0 - drawn.a);
		// The third glow, inner and in the label's color.
		float inner = clamp((1.0 - box_alpha_after_outer_glow(SCREEN_UV, stage_pixel)) * COLOR_STRENGTH, 0.0, 1.0);
		drawn = glow_color * inner * drawn.a + drawn * (1.0 - inner);
	}
	if (drawn.a > 0.0001) {
		drawn.rgb /= drawn.a;
	}
	COLOR = drawn;
}
