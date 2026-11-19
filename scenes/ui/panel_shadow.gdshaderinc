// The inner DropShadow ramp that the SWF puts on each flat KRINMENU Panel and on
// the Abilities Window's ability pool, sprite 3120: black, blur 5, distance 5,
// angle 45. On a solid rectangle, a box blur of a straight edge is a straight
// ramp, so the shadow is one linear ramp per axis. Each ramp is centred
// `distance` in from the edge along `angle` and is `blur` wide. It is measured
// in design px from the drawing node's own top left, so it darkens only the top
// and left edges (spec/107-ui-foundation.md, Part 3, julian-perge/urchin#115 and
// julian-perge/urchin#190). The result is the factor that the colour under the
// shadow is multiplied by: 0 at the edge and 1 past the band.
float shadow_ramp(vec2 local, float blur, float distance, float angle) {
	vec2 centre = distance * vec2(cos(radians(angle)), sin(radians(angle)));
	vec2 ramp = clamp((local - (centre - blur * 0.5)) / blur, 0.0, 1.0);
	return ramp.x * ramp.y;
}
