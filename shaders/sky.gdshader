shader_type sky;

// Overcast urban night sky: dark navy zenith, sodium/brown light-pollution glow
// at the horizon, slow drifting clouds lit from below by the city.

uniform vec3 zenith : source_color = vec3(0.02, 0.026, 0.05);
uniform vec3 horizon : source_color = vec3(0.12, 0.105, 0.11);
uniform vec3 cloud_color : source_color = vec3(0.16, 0.145, 0.15);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_amount = 0.75;
uniform float energy = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.45));
	if (d.y > 0.0) {
		vec2 cuv = d.xz / (d.y + 0.12) * 0.18 + vec2(TIME * 0.0016, TIME * 0.0007);
		float c1 = texture(cloud_noise, cuv).r;
		float c2 = texture(cloud_noise, cuv * 2.7 + vec2(0.31, 0.77)).r;
		float c = smoothstep(0.38, 0.78, c1 * 0.68 + c2 * 0.32) * cloud_amount;
		c *= smoothstep(0.0, 0.18, d.y);
		col = mix(col, cloud_color * mix(1.2, 0.6, up), c);
		// a few faint stars in the gaps
		vec2 sg = floor(d.xz / (d.y + 0.2) * 700.0);
		float s = step(0.9985, hash(sg)) * (1.0 - c) * up;
		col += vec3(s) * 0.25;
	} else {
		col = horizon * 0.35;
	}
	COLOR = col * energy;
}
