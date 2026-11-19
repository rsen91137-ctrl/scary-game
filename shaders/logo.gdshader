shader_type canvas_item;

// CORRIDOR logotype. Texture masks (tools/gen_logo.py):
//   R = weathered bone letters, G = blood coverage (the "I", spatter, drips),
//   B = blood shading (dark coagulated rims, wet highlights).
// The letters dim with the nearest failing lamp and tear sideways now and
// then; the blood swells a little on every heartbeat.

uniform vec3 letter_color : source_color = vec3(0.86, 0.83, 0.79);
uniform vec3 blood_dark : source_color = vec3(0.12, 0.0, 0.004);
uniform vec3 blood_bright : source_color = vec3(0.62, 0.025, 0.02);
uniform float light = 1.0;      // 0..1 lamp level
uniform float pulse = 0.0;      // 0..1 heartbeat envelope
uniform float glitch = 0.0;     // 0..1
uniform float time_s = 0.0;
uniform float letters_alpha = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = floor(time_s * 30.0);
	if (glitch > 0.001) {
		float band = floor(uv.y * 14.0);
		float g = hash(vec2(band, t));
		uv.x += (g - 0.5) * 0.05 * glitch * step(0.6, g);
	}
	vec2 split = vec2(0.004 * glitch, 0.0);
	float lr = texture(TEXTURE, uv + split).r;
	float lg = texture(TEXTURE, uv).r;
	float lb = texture(TEXTURE, uv - split).r;
	vec3 m = texture(TEXTURE, uv).rgb;

	float lit = 0.72 + 0.28 * clamp(light, 0.0, 1.0);
	vec3 bone = vec3(lr, lg, lb) * letter_color * lit;
	float ba = max(lr, max(lg, lb)) * letters_alpha;

	float cover = m.g;
	float sh = m.b;
	vec3 blood = mix(blood_dark, blood_bright, clamp(sh * 1.3, 0.0, 1.0));
	blood += max(sh - 0.8, 0.0) * 2.0 * vec3(0.9, 0.5, 0.45);   // wet glints
	blood *= 1.0 + pulse * 0.45;

	// blood over bone
	vec3 col = blood * cover + bone * (1.0 - cover);
	float a = clamp(cover + ba * (1.0 - cover), 0.0, 1.0);
	vec3 straight = (blood * cover + bone * ba * (1.0 - cover)) / max(a, 0.001);
	COLOR = vec4(straight, a * COLOR.a);
}
