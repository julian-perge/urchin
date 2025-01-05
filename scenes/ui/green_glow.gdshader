shader_type canvas_item;

uniform vec4 glow_color: source_color = vec4(0.2, 0.6, 0.3, 1.0);
uniform float glow_power: hint_range(0.0, 8.0, 0.1) = 2.0;
uniform float glow_shift: hint_range(0.0, 10.0, 0.1) = 1.0;
uniform float glow_radius: hint_range(1.0, 10.0, 1.0) = 1.0;

uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;


void fragment() {
	vec4 current_color = texture(TEXTURE, UV);

	// Only apply glow effect to the filled portion
	float glow_mask = step(UV.x, progress);

	// Create glow effect
	float glow = smoothstep(0.5, 1.0, current_color.a) * glow_intensity;
	vec3 glow_result = mix(current_color.rgb, glow_color.rgb, glow * glow_mask);

	COLOR = vec4(glow_result, current_color.a);
	//COLOR = mix(texture(TEXTURE, UV), glow, glow.a);
}

//void fragment() {
	//vec4 glow = vec4(0.0);
	//float count = 0.0;
	//for (float x = -glow_radius; x <= glow_radius; x += 1.0) {
		//for (float y = -glow_radius; y <= glow_radius; y += 1.0) {
			//vec2 offset = vec2(x, y) * glow_shift * TEXTURE_PIXEL_SIZE;
			//glow += texture(TEXTURE, UV + offset);
		//}
	//}
//
	//glow += glow_power / count;
	//COLOR = mix(texture(TEXTURE, UV), glow, glow.a);
//}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
