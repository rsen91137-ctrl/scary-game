shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;

// Distant institutional building across the lake: dark facade, a grid of
// windows, only a few of them lit (cold office light / warm), some of which
// slowly switch off and on.

uniform vec3 wall : source_color = vec3(0.035, 0.036, 0.04);
uniform vec2 cell = vec2(3.4, 3.9);
uniform vec2 window = vec2(1.5, 2.1);
uniform float lit_ratio = 0.13;
uniform float emission_energy = 2.2;
uniform float flicker_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.37, 289.11))) * 13758.5453);
}

void fragment() {
	vec2 p = UV; // metres on the facade
	vec2 c = floor(p / cell);
	vec2 f = mod(p, cell) - (cell - window) * 0.5;
	float inside = step(0.0, f.x) * step(f.x, window.x) * step(0.0, f.y) * step(f.y, window.y);
	float h = hash(c);
	float h2 = hash(c + 17.3);
	float lit = step(1.0 - lit_ratio, h);
	// slow random switching of some windows
	float sw = step(0.5, fract(sin(floor(flicker_time / (25.0 + h2 * 40.0)) * 91.7 + h * 13.0) * 4375.5));
	lit *= mix(1.0, sw, step(0.7, h2));
	vec3 lc = mix(vec3(0.75, 0.86, 1.0), vec3(1.0, 0.78, 0.52), step(0.6, h2));
	// blinds / structure inside the window
	float bars = 0.75 + 0.25 * step(0.08, fract(f.x / (window.x / 3.0)));
	ALBEDO = mix(wall, wall * 0.6, inside);
	ROUGHNESS = mix(0.95, 0.15, inside);
	EMISSION = lc * lit * inside * bars * emission_energy * (0.6 + 0.4 * h2);
}
