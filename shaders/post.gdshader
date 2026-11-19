shader_type canvas_item;

// Full-screen post process drawn over the 3D view (below the UI):
// heartbeat pulse (zoom punch, barrel distortion, chromatic split, vignette
// squeeze with a faint blood tint), vertigo (swimming warp, double vision,
// smear), tinnitus (washed-out, desaturated, slightly blown highlights),
// lens softness towards the edges, film grain, fade to black, brightness.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float pulse = 0.0;          // 0..1 heartbeat envelope
uniform float shake_amount = 1.0;   // user setting
uniform float grain = 0.055;
uniform float vignette = 0.55;
uniform float aberration = 0.0012;
uniform float distortion = 0.035;
uniform float fade = 0.0;           // 0 = visible, 1 = black
uniform float brightness = 1.0;     // display brightness (gamma style)
uniform float tension = 0.0;        // 0..1 overall dread, tightens vignette
uniform float glitch = 0.0;         // 0..1 short tearing during blackouts
uniform float dizzy = 0.0;          // 0..1 vertigo
uniform float tinnitus = 0.0;       // 0..1 ringing ears
uniform float time_s = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 ca = vec2(c.x * aspect, c.y);
	float r2 = dot(ca, ca);

	float p = pulse * shake_amount;
	// zoom punch + barrel distortion that breathes with the heartbeat
	float k = distortion + p * 0.06 + dizzy * 0.05 * sin(time_s * 0.9);
	vec2 duv = 0.5 + c * (1.0 - p * 0.022 - tinnitus * 0.012) * (1.0 + k * r2) / (1.0 + k * 0.35);

	// vertigo: the image swims
	if (dizzy > 0.001) {
		duv += vec2(sin(uv.y * 6.0 + time_s * 1.6) + 0.5 * sin(uv.y * 13.0 - time_s * 2.3),
			cos(uv.x * 5.0 + time_s * 1.2) + 0.5 * cos(uv.x * 11.0 + time_s * 1.9)) * 0.0045 * dizzy;
	}

	// horizontal tearing during blackouts / flicker spikes
	if (glitch > 0.001) {
		float band = floor(uv.y * 38.0 + floor(time_s * 24.0) * 7.0);
		float g = hash(vec2(band, floor(time_s * 24.0)));
		duv.x += (g - 0.5) * 0.04 * glitch * step(0.82, g);
	}

	vec2 dir = ca * (aberration + p * 0.004 + glitch * 0.003 + dizzy * 0.004);
	dir.x /= aspect;
	vec3 col;
	col.r = texture(screen_tex, duv + dir).r;
	col.g = texture(screen_tex, duv).g;
	col.b = texture(screen_tex, duv - dir).b;

	// vertigo: double vision and smear
	if (dizzy > 0.001) {
		vec2 off = vec2(0.016 * sin(time_s * 0.73), 0.006 * cos(time_s * 0.51)) * dizzy;
		vec3 ghost = texture(screen_tex, duv + off).rgb;
		col = mix(col, ghost, 0.4 * dizzy);
		col = mix(col, textureLod(screen_tex, duv, 3.0).rgb, 0.16 * dizzy);
	}

	// softer, slightly blurred edges like a phone lens at night
	vec3 soft = textureLod(screen_tex, duv, 2.0).rgb;
	col = mix(col, soft, smoothstep(0.12, 0.5, r2) * (0.3 + 0.22 * dizzy));

	// tinnitus: the world drains of colour and goes thin and bright
	float lum0 = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum0), 0.65 * tinnitus);
	col = mix(col, col * 0.8 + vec3(0.07, 0.07, 0.075), 0.7 * tinnitus);
	col += textureLod(screen_tex, duv, 4.0).rgb * 0.6 * tinnitus;

	// vignette, tightened by tension, the heartbeat and vertigo
	float vr = length(ca * vec2(0.92, 1.0));
	float inner = mix(0.92, 0.55, clamp(tension * 0.6 + p * 0.5 + dizzy * 0.18, 0.0, 1.0));
	float v = smoothstep(inner, 0.12, vr);
	col *= mix(1.0, v, vignette * (1.0 - 0.5 * tinnitus));
	col = mix(col, col * vec3(1.25, 0.55, 0.5), (1.0 - v) * p * 0.35);

	// brightness (applied in display space, keeps the blacks black)
	col = pow(max(col, vec3(0.0)), vec3(1.0 / max(brightness, 0.05)));

	// film grain, stronger in the shadows
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float t = floor(time_s * 24.0);
	float n = hash(FRAGCOORD.xy + t * 37.0) + hash(FRAGCOORD.xy * 1.37 + t * 11.0) - 1.0;
	col += n * (grain + 0.03 * tinnitus) * mix(1.0, 0.35, smoothstep(0.0, 0.5, l));

	col *= 1.0 - fade;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
