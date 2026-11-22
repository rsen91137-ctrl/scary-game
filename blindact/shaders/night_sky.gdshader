shader_type sky;

// The night over the estate: a deep indigo zenith sinking to a dark teal
// horizon with a faint glow of the town beyond the trees, two layers of
// stars (a few bright, many faint, a smudge of the Milky Way), thin ragged
// clouds drifting across and silvered where they pass the moon, and the moon
// itself (maria, limb darkening, a wide halo in the damp air). The moon sits
// where the DirectionalLight3D comes from (LIGHT0), so its light and its
// disc always agree. Stars and fine cloud detail are skipped in the
// radiance cubemap (reflections only need the broad colours).

uniform vec3 zenith_color : source_color = vec3(0.01, 0.016, 0.042);
uniform vec3 horizon_color : source_color = vec3(0.028, 0.055, 0.06);
uniform vec3 town_glow : source_color = vec3(0.07, 0.075, 0.1);
uniform vec3 ground_color : source_color = vec3(0.01, 0.012, 0.016);
uniform float star_intensity = 1.0;
uniform vec3 moon_color : source_color = vec3(0.82, 0.88, 1.0);
uniform float moon_radius = 0.027;       // angular radius (radians)
uniform float moon_energy = 5.0;
uniform float halo_energy = 0.32;
uniform vec3 cloud_color : source_color = vec3(0.045, 0.055, 0.075);
uniform float cloud_cover = 0.56;
uniform float cloud_speed = 0.004;
uniform float brightness = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// one layer of stars on a 3D cell grid around the eye direction
float stars(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	vec3 h = hash33(c);
	if (h.x >= density) {
		return 0.0;
	}
	vec3 sp = (c + 0.25 + 0.5 * hash33(c + 7.1)) / scale;
	float dist = length(normalize(sp) - d) * scale;
	float b = pow(h.y, 6.0) * 3.0 + 0.25;
	return b * exp(-dist * dist / (size * size));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	float hz = clamp(up, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(hz, 0.45));
	// the town's glow low over the trees, strongest to the north-west
	float az = atan(d.x, -d.z);
	float glow = exp(-max(up, 0.0) * 9.0) * (0.55 + 0.45 * cos(az + 0.8));
	col += town_glow * glow;

	vec3 L = vec3(0.0, 0.5, 0.86);
	if (LIGHT0_ENABLED) {
		L = normalize(LIGHT0_DIRECTION);
	}
	float md = acos(clamp(dot(d, L), -1.0, 1.0));

	// clouds on a flat layer above (projected), drifting
	float cloud = 0.0;
	if (up > 0.0) {
		vec2 cp = d.xz / (up + 0.18) * 1.6 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = AT_CUBEMAP_PASS ? vnoise(cp * 1.3) : fbm(cp * 1.3);
		float streak = AT_CUBEMAP_PASS ? 0.5 : fbm(vec2(cp.x * 0.6, cp.y * 3.0) + 4.0);
		cloud = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n * 0.75 + streak * 0.35);
		cloud *= smoothstep(0.0, 0.12, up);
	}

	// stars (not in the reflection cubemap), hidden by clouds and the moon's glare
	if (!AT_CUBEMAP_PASS && up > -0.05) {
		float s = stars(d, 260.0, 0.02, 0.5) * 1.4 + stars(d, 620.0, 0.045, 0.55) * 0.5;
		// the Milky Way: a faint dusty band
		vec3 band_n = normalize(vec3(0.35, 0.25, 0.9));
		float band = exp(-pow(dot(d, band_n) * 4.0, 2.0));
		float dust = fbm(d.xy * 7.0 + d.z * 3.0);
		s += stars(d, 1100.0, 0.12 * band, 0.55) * 0.4;
		col += vec3(0.012, 0.014, 0.022) * band * smoothstep(0.3, 0.8, dust) * 1.5;
		float twinkle = 0.75 + 0.25 * sin(TIME * 3.0 + hash13(floor(d * 260.0)) * 40.0);
		float hide = (1.0 - cloud) * smoothstep(0.08, 0.5, md) * smoothstep(-0.02, 0.15, up);
		col += vec3(0.85, 0.9, 1.0) * s * twinkle * star_intensity * hide * 0.05;
	}

	// the moon: halo, disc with maria and a darker limb
	float halo = exp(-md / 0.09) * 0.8 + exp(-md / 0.35) * 0.25;
	col += moon_color * halo * halo_energy * 0.25;
	if (md < moon_radius * 1.15) {
		vec3 rt = normalize(cross(L, vec3(0.0, 1.0, 0.0)));
		vec3 upv = normalize(cross(rt, L));
		vec2 q = vec2(dot(d - L, rt), dot(d - L, upv)) / moon_radius;
		float r2 = dot(q, q);
		float disc = 1.0 - smoothstep(0.92, 1.0, sqrt(r2));
		float limb = sqrt(max(0.0, 1.0 - r2));
		float maria = smoothstep(0.45, 0.7, fbm(q * 2.2 + 3.0)) * 0.35 + smoothstep(0.55, 0.8, fbm(q * 6.0 + 11.0)) * 0.12;
		vec3 mc = moon_color * (0.55 + 0.45 * limb) * (1.0 - maria);
		col = mix(col, mc * moon_energy, disc * (1.0 - cloud * 0.75));
	}

	// clouds: dark against the sky, silver near the moon
	vec3 cc = cloud_color + moon_color * (exp(-md / 0.25) * 0.5 + exp(-md / 0.06) * 0.8) * 0.35;
	col = mix(col, cc, cloud * 0.85);

	// below the horizon: the dark ground (fog covers most of it)
	col = mix(col, ground_color, smoothstep(0.0, -0.06, up));
	COLOR = col * brightness;
}
