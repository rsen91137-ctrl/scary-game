shader_type canvas_item;

// Background of the sketch-eye screen: near-black paper with fibres, damp
// stains and a faint red bloom where the eye is.

uniform vec2 glow_center = vec2(0.56, 0.4);
uniform float glow_amount = 1.0;
uniform float time_s = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + 13.1;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = UV * vec2(aspect, 1.0);
	float fib = vnoise(p * vec2(420.0, 60.0)) * 0.5 + vnoise(p * vec2(60.0, 380.0)) * 0.5;
	float stain = fbm(p * 2.2 + 3.0);
	float blot = smoothstep(0.55, 0.75, fbm(p * 4.0 - 7.0));
	vec3 col = vec3(0.022, 0.012, 0.011) * (0.7 + 0.6 * stain);
	col += vec3(0.01, 0.006, 0.005) * fib;
	col = mix(col, vec3(0.04, 0.008, 0.006), blot * 0.6);
	vec2 g = (UV - glow_center) * vec2(aspect, 1.0);
	col += vec3(0.11, 0.008, 0.006) * exp(-dot(g, g) * 3.2) * glow_amount * (0.9 + 0.1 * sin(time_s * 0.7));
	COLOR = vec4(col, 1.0);
}
