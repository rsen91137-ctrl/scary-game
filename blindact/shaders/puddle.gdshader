shader_type spatial;
render_mode cull_disabled;

// Rainwater that came in through the broken pane: an irregular dark puddle,
// mirror-smooth (SSR picks up the window and the bulbs), with rings from
// the drops that keep falling into it.

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
	vec2 p = UV * 2.0 - 1.0;
	float edge = length(p * vec2(1.0, 1.3)) + (vnoise(UV * 6.0) - 0.5) * 0.5 + (vnoise(UV * 17.0) - 0.5) * 0.15;
	float wet = smoothstep(0.95, 0.8, edge);
	if (wet < 0.02) {
		discard;
	}
	// ripples from a few drop points
	vec2 n = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 c = vec2(hash(vec2(float(i), 1.0)), hash(vec2(float(i), 2.0))) * 1.2 - 0.6;
		float period = 1.3 + float(i) * 0.37;
		float t = fract(time_s / period + hash(vec2(float(i), 3.0)));
		vec2 d = p - c;
		float r = length(d);
		float ring = sin((r - t * 0.9) * 60.0) * exp(-abs(r - t * 0.9) * 18.0) * (1.0 - t);
		n += normalize(d + 1e-4) * ring * 0.35;
	}
	ALBEDO = vec3(0.025, 0.024, 0.022);
	ROUGHNESS = mix(0.6, 0.02, wet);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz * wet);
	ALPHA = wet;
}
