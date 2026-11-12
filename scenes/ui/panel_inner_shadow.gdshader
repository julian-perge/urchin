// The inner DropShadow that the SWF puts on each flat KRINMENU Panel. On a
// solid rectangle, a box blur of a straight edge is a straight ramp, so the
// shadow is the fill times one linear ramp per axis. The ramp is centred
// `distance` in from the edge along `angle`, is `blur` wide, and is measured in
// design px from the Panel's own top left, so it darkens only the top and left
// edges (spec/107-ui-foundation.md, Part 3, and julian-perge/urchin#115).
shader_type canvas_item;

uniform float blur;
uniform float distance;
uniform float angle;

varying vec2 local;


void vertex() {
	local = VERTEX;
}


void fragment() {
	vec2 centre = distance * vec2(cos(radians(angle)), sin(radians(angle)));
	vec2 ramp = clamp((local - (centre - blur * 0.5)) / blur, 0.0, 1.0);
	COLOR.rgb *= ramp.x * ramp.y;
}
