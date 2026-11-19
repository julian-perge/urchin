// The inner shadow on each of the 16 flat KRINMENU Panels. It multiplies the
// Panel's own colour by the ramp in panel_shadow.gdshaderinc.
shader_type canvas_item;

#include "res://scenes/ui/panel_shadow.gdshaderinc"

uniform float blur;
uniform float distance;
uniform float angle;

varying vec2 local;


void vertex() {
	local = VERTEX;
}


void fragment() {
	COLOR.rgb *= shadow_ramp(local, blur, distance, angle);
}
