// Every doll sprite but the shadow draws through this shader: a piece's colour
// transform from its model's frame (extract_model_pieces), and plain identity
// for the other parts. It gives each channel of the art times its multiplier
// plus its offset, as Flash applies a ColorTransform, then times the sprite's
// modulate. The fragment's COLOR comes in already multiplied by the texture, so
// the modulate is kept from the vertex function instead.
//
// The doll PNGs are rendered at 2x and imported with mipmaps, and MODEL8 draws
// its parts at about 0.67, so an 800x575 window shows each PNG at about a third
// of its size. Plain bilinear sampling skips texels there and aliases the edges,
// and Godot's own mipmap choice blurs them. MIPMAP_BIAS picks a sharper mipmap
// level. Measured for #482 against the Flash capture in
// references/traced_runs/zone4_boss/glow_scales.png, M_SFOOT_HYDRA2 at 66.9% has
// a white core of 16 px in Flash, 21 px with no mipmaps, 10 px with a bias of 0
// and 16 px with this bias. The bias has a cost in an 800x575 window: a part at
// 100% there draws a little softer than with no mipmaps. The 1600x1150 window
// draws a part at 100% from the full-size level only, and a part at 66.9%
// almost only from it.
shader_type canvas_item;

const float MIPMAP_BIAS = -0.5;

uniform vec4 multiplier = vec4(1.0);
uniform vec4 offset = vec4(0.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = clamp(texture(TEXTURE, UV, MIPMAP_BIAS) * multiplier + offset, 0.0, 1.0) * tint;
}
