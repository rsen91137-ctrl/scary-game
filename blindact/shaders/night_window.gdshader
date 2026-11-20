shader_type spatial;
render_mode unshaded, cull_disabled;

// What you see through the landing window: a rainy night, another block of
// flats across the yard with a few lit windows, rain streaking down the glass.
// Lightning flashes the whole sky.

uniform float flash = 0.0;
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

void fragment() {
	vec2 uv = UV;
	// rain on the glass refracts the view a little
	float streak = vnoise(vec2(uv.x * 60.0, uv.y * 3.0 - time_s * 1.4));
	vec2 ruv = uv + vec2(0.0, (streak - 0.5) * 0.02);
	vec3 sky = mix(vec3(0.012, 0.016, 0.03), vec3(0.03, 0.035, 0.05), ruv.y);
	// the block across the yard
	float bld = step(ruv.y, 0.78) * step(0.04, ruv.x) * step(ruv.x, 0.96);
	vec3 col = mix(sky, vec3(0.006, 0.006, 0.008), bld);
	vec2 cell = vec2(floor(ruv.x * 9.0), floor(ruv.y * 12.0));
	vec2 f = fract(vec2(ruv.x * 9.0, ruv.y * 12.0));
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
	float lit = step(0.86, hash(cell + 3.0)) * bld;
	vec3 wc = mix(vec3(0.5, 0.35, 0.18), vec3(0.25, 0.3, 0.4), hash(cell + 7.0));
	col += wc * win * lit * (0.25 + 0.1 * sin(time_s * 0.3 + hash(cell) * 6.0));
	// rain streaks and drops on the glass
	float drops = smoothstep(0.82, 0.95, vnoise(vec2(uv.x * 90.0, uv.y * 40.0 + time_s * 0.6)));
	col += vec3(0.03, 0.035, 0.045) * drops;
	col += vec3(0.02, 0.022, 0.03) * smoothstep(0.6, 1.0, streak);
	col += vec3(0.55, 0.6, 0.75) * flash * (0.6 + 0.4 * (1.0 - bld));
	ALBEDO = col;
}
