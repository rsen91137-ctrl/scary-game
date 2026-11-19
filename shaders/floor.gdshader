shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Corridor paving. The tile layout is computed from world position so it never
// visibly repeats: running-bond slabs, a darker granite band under every pair
// of pillars (as in the photos), per-slab tone, dirt and damp patches that
// turn into reflective puddles.

uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float bay = 3.2;
uniform float band_width = 0.34;
uniform vec2 slab = vec2(0.62, 0.42);
uniform float wetness = 0.55;
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 v_wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	float zb = mod(p.y + band_width * 0.5, bay);
	bool band = zb < band_width;

	vec2 size = band ? vec2(0.5, band_width) : slab;
	vec2 q = vec2(p.x, band ? zb : p.y) / size;
	float row = floor(q.y);
	if (!band) {
		q.x += mod(row, 2.0) * 0.5;
	}
	vec2 cell = floor(q);
	vec2 f = fract(q);
	vec2 dist = min(f, 1.0 - f) * size;
	float seam_d = min(dist.x, dist.y);
	if (band) {
		// the band's long edges are seams too
		seam_d = min(seam_d, min(zb, band_width - zb));
	}
	float seam = 1.0 - smoothstep(0.0015, 0.0055, seam_d);
	float h = hash(cell + (band ? vec2(91.0, 7.0) : vec2(13.0, 57.0)) + floor(p.y / bay) * 3.1);

	vec2 suv = p * 0.85 + vec2(h * 7.31, h * 3.17);
	vec3 a;
	float rough;
	vec3 nmap = texture(stone_normal, suv).rgb;
	if (band) {
		a = texture(granite_albedo, suv * 1.6).rgb * vec3(0.42, 0.41, 0.4);
		rough = 0.6;
	} else {
		a = texture(stone_albedo, suv).rgb * mix(0.8, 1.14, h);
		rough = texture(stone_rough, suv).r;
	}
	a *= tint;

	// grime: large scale dirt + darker along the bench line and the seams
	float n1 = texture(noise_tex, p * 0.045).r;
	float n2 = texture(noise_tex, p * 0.21 + 0.37).r;
	float dirt = smoothstep(0.35, 0.75, n1 * 0.7 + n2 * 0.3);
	float edge = smoothstep(1.05, 1.5, abs(p.x));
	a *= 1.0 - 0.25 * dirt - 0.3 * edge;
	a = mix(a, a * 0.35, seam);

	// damp patches -> puddles
	float wetn = texture(noise_tex, p * 0.11 + vec2(0.21, 0.63)).r * 0.75 + n2 * 0.25;
	float damp = smoothstep(0.42, 0.62, wetn) * wetness;
	float puddle = smoothstep(0.6, 0.68, wetn) * wetness;
	a *= 1.0 - 0.35 * damp;
	rough = mix(rough, 0.32, damp);
	rough = mix(rough, 0.04, puddle);
	rough = max(rough, seam * 0.9);

	ALBEDO = a;
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), puddle * 0.9);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	SPECULAR = mix(0.4, 0.6, damp);
}
