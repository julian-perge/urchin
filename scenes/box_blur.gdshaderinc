// The blur that Flash's filters run with one pass, which zone_map_shadow,
// doll_body and drop_shadow share. It averages the alpha of `picture` over a
// box `box` wide in UV, centred on `uv`. Each sample sits at the centre of
// one cell of a 5 by 5 grid over the box, so the samples cover a box exactly as
// wide as the blur.
const int BOX_SAMPLES = 5;

float box_alpha(sampler2D picture, vec2 uv, vec2 box) {
	float sum = 0.0;
	for (int i = 0; i < BOX_SAMPLES; i++) {
		for (int j = 0; j < BOX_SAMPLES; j++) {
			vec2 offset = (vec2(float(i), float(j)) + 0.5) / float(BOX_SAMPLES) - 0.5;
			sum += texture(picture, uv + offset * box).a;
		}
	}
	return sum / float(BOX_SAMPLES * BOX_SAMPLES);
}
