// The ability pool's inner shadow (julian-perge/urchin#190). The game adds the
// pool's rows while it runs, and Flash draws the DropShadow of sprite 3120 over
// them, so this overlay lies above the pool's backing, rows, frame and scroll
// buttons. It multiplies what is under it by the ramp in
// panel_shadow.gdshaderinc, the same ramp that the 16 Panels draw.
shader_type canvas_item;
render_mode blend_mul;

#include "res://scenes/ui/panel_shadow.gdshaderinc"

uniform float blur;
uniform float distance;
uniform float angle;

varying vec2 local;


void vertex() {
	local = VERTEX;
}


void fragment() {
	COLOR = vec4(vec3(shadow_ramp(local, blur, distance, angle)), 1.0);
}
