shader_type canvas_item;

// The ability icon sheet (DefineSprite 2427) is a near-black silhouette per
// move/buff family - the original tints it per-element at runtime
// (elementColorArray). A plain `modulate` multiply can't recolor near-black
// source pixels (black * anything = black), so this replaces the RGB
// outright and keeps only the source alpha (the silhouette shape).
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float source_alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(tint_color.rgb, source_alpha * tint_color.a);
}
