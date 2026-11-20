shader_type canvas_item;

// Red subtitle text: letters tremble, flicker, smear downwards a little and
// dissolve into drips when the line fades out.

uniform float dissolve = 0.0;
uniform float seed = 0.0;
uniform float time_s = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float t = floor(time_s * 14.0);
	VERTEX += (vec2(hash(vec2(t, seed)), hash(vec2(seed, t))) - 0.5) * 2.2;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// downward smear: sample a bit above and keep the max
	vec2 px = TEXTURE_PIXEL_SIZE;
	float smear = 0.0;
	for (int i = 1; i < 6; i++) {
		smear = max(smear, texture(TEXTURE, UV - vec2(0.0, px.y * float(i) * (1.5 + dissolve * 6.0))).a * (1.0 - float(i) / 6.0));
	}
	float drip = smear * (0.35 + dissolve * 0.65) * step(0.6, hash(vec2(floor(UV.x / px.x / 3.0), seed)));
	float a = max(c.a, drip * 0.8);
	float n = hash(floor(UV / px / 2.0) + seed);
	a *= step(dissolve * 1.05, n * 0.9 + 0.05 + (1.0 - c.a) * 0.0);
	float flick = 0.82 + 0.18 * hash(vec2(floor(time_s * 18.0), seed));
	COLOR = vec4(COLOR.rgb * flick, a);
}
