// Draws one layer of a Floating number's glyph under the two color transforms
// the original puts on it. KrinNumberShow's setRGB gives a KN fill the number's
// color and keeps the fill's alpha (frame_42/DoAction_7.as:58-59). Then
// NumberFixer's holder pushes every layer toward white by the share its frame
// sets. FloatingNumber gives its KN layers a material with tinted on and its
// other layers one with tinted off, and sets white on both on every frame.
shader_type canvas_item;

uniform bool tinted = false;
uniform vec4 tint = vec4(1.0);
uniform float white = 0.0;

void fragment() {
	vec3 rgb = tinted ? tint.rgb : COLOR.rgb;
	COLOR.rgb = mix(rgb, vec3(1.0), white);
}
