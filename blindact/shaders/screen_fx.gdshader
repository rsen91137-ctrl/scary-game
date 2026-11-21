shader_type canvas_item;

// Full-screen post process drawn over everything below it (UI goes above).
// Used by the stairwell menu, the sketch-eye screen and the game itself.
//   stretch / zoom / tremble / ghost (double vision) / blur / glitch tearing
//   glow (ink bleed + highlights), heartbeat pulse, red flash
//   sunglasses: the protagonist wears dark glasses -> everything is dimmer,
//   flatter and slightly tinted, the edges of the lenses darken the corners
//   vignette, lens softness, chromatic aberration, film grain, fade

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 stretch = vec2(0.0);           // >0 enlarges the image along that axis
uniform vec2 stretch_center = vec2(0.5);
uniform float melt = 0.0;                   // wavy warp that goes with stretching
uniform float zoom = 0.0;
uniform vec2 zoom_center = vec2(0.5);
uniform float tremble = 0.0;
uniform float ghost = 0.0;
uniform float blur = 0.0;
uniform float glitch = 0.0;
uniform float glow = 0.0;
uniform float pulse = 0.0;
uniform float red_flash = 0.0;
uniform float sunglasses = 0.0;             // 0 none .. 1 dark lenses
uniform float vignette = 0.5;
uniform float grain = 0.05;
uniform float aberration = 0.0012;
uniform float fade = 0.0;
uniform float brightness = 1.0;
uniform float desaturate = 0.0;
uniform float flash = 0.0;                 // a blown-out frame
uniform float negative = 0.0;              // a frame turned inside out
uniform float cold = 0.0;                  // drain warm hues, push shadows to blue-green
uniform float time_s = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 sample_blur(vec2 uv, float amount) {
	if (amount < 0.002) {
		return texture(screen_tex, uv).rgb;
	}
	float lod = amount * 4.0;
	vec3 acc = textureLod(screen_tex, uv, lod).rgb * 0.4;
	float r = amount * 0.012;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472 + time_s * 0.0;
		acc += textureLod(screen_tex, uv + vec2(cos(a), sin(a)) * r, lod * 0.8).rgb * 0.1;
	}
	return acc;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	// tremble: a nervous, frame-stepped shake with a hint of rotation
	if (tremble > 0.001) {
		float tf = floor(time_s * 24.0);
		vec2 j = vec2(hash(vec2(tf, 1.7)), hash(vec2(tf, 9.3))) - 0.5;
		uv += j * 0.014 * tremble;
		float ang = (hash(vec2(tf, 4.1)) - 0.5) * 0.012 * tremble;
		vec2 c = uv - 0.5;
		c.x *= 1.0 / aspect;
		c = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * c;
		c.x *= aspect;
		uv = c + 0.5;
	}
	// zoom
	uv = zoom_center + (uv - zoom_center) / (1.0 + zoom);
	// stretch (+ a melting wave so it never looks like a clean scale)
	vec2 d = uv - stretch_center;
	d /= (1.0 + stretch);
	uv = stretch_center + d;
	if (melt > 0.001) {
		uv.x += sin(uv.y * 7.0 + time_s * 1.3) * 0.012 * melt + sin(uv.y * 23.0 - time_s * 2.1) * 0.003 * melt;
		uv.y += sin(uv.x * 5.0 - time_s * 0.9) * 0.008 * melt;
	}
	// heartbeat punch
	uv = 0.5 + (uv - 0.5) * (1.0 - pulse * 0.018);
	// tearing
	if (glitch > 0.001) {
		float band = floor(uv.y * 34.0 + floor(time_s * 24.0) * 7.0);
		float g = hash(vec2(band, floor(time_s * 24.0)));
		uv.x += (g - 0.5) * 0.05 * glitch * step(0.8, g);
	}

	vec2 c = uv - 0.5;
	vec2 ca = vec2(c.x * aspect, c.y);
	float r2 = dot(ca, ca);
	vec2 dir = ca * (aberration + pulse * 0.003 + tremble * 0.003 + ghost * 0.002);
	dir.x /= aspect;
	vec3 col;
	col.r = sample_blur(uv + dir, blur).r;
	col.g = sample_blur(uv, blur).g;
	col.b = sample_blur(uv - dir, blur).b;

	if (ghost > 0.001) {
		vec2 off = vec2(0.03 * sin(time_s * 0.83), 0.008 * cos(time_s * 0.61)) * ghost;
		vec3 g1 = sample_blur(uv + off, blur * 0.5 + 0.1 * ghost);
		vec3 g2 = sample_blur(uv - off * 0.7, blur * 0.5 + 0.1 * ghost);
		col = mix(col, max(col, max(g1, g2) * 0.85), 0.6 * ghost);
	}

	// glow: ink bleeding into the paper / highlights blooming
	if (glow > 0.001) {
		vec3 g = textureLod(screen_tex, uv, 3.0).rgb * 0.5 + textureLod(screen_tex, uv, 5.0).rgb * 0.5;
		col += g * glow * 0.9;
	}

	// lens softness towards the edges
	vec3 soft = textureLod(screen_tex, uv, 2.0).rgb;
	col = mix(col, soft, smoothstep(0.14, 0.55, r2) * 0.3);

	// sunglasses: darker, flatter, a cold blue-green cast, darker corners
	// blood: red standing far above green and blue. It is never drained,
	// never cooled, and the lenses hardly dim it.
	float redk = smoothstep(0.025, 0.14, col.r - max(col.g, col.b) * 1.3);
	if (sunglasses > 0.001) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 lens = mix(col, vec3(lum), 0.3) * vec3(0.8, 0.9, 0.96);
		lens *= 0.62;
		lens = lens * lens * 1.1 + lens * 0.42;   // about a stop darker, shadows kept
		lens = mix(lens, col * vec3(1.0, 0.55, 0.55), redk * 0.9);
		float frame = smoothstep(0.42, 0.95, length(ca * vec2(0.82, 1.05)));
		lens *= 1.0 - frame * 0.6;
		col = mix(col, lens, sunglasses);
	}

	float lum0 = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum0), desaturate * (1.0 - redk));
	if (cold > 0.001) {
		// warm hues lose their colour, the shadows sink into blue-green;
		// all but blood
		float warm = clamp((col.r - col.b) * 3.0, 0.0, 1.0);
		vec3 c2 = mix(col, vec3(lum0), 0.12 + 0.4 * warm);
		c2 *= mix(vec3(0.8, 0.94, 1.08), vec3(0.95, 1.0, 1.04), smoothstep(0.0, 0.45, lum0));
		col = mix(col, c2, cold * (1.0 - redk));
	}
	col = mix(col, vec3(col.r * 1.25 + 0.01, col.g * 0.7, col.b * 0.7), redk * 0.7);

	// vignette, tightened by the heartbeat
	float vr = length(ca * vec2(0.92, 1.0));
	float inner = mix(0.95, 0.55, clamp(pulse * 0.6, 0.0, 1.0));
	float v = smoothstep(inner, 0.1, vr);
	col *= mix(1.0, v, vignette);
	col = mix(col, col * vec3(1.3, 0.5, 0.45), (1.0 - v) * pulse * 0.35);
	col += vec3(0.5, 0.0, 0.0) * red_flash * (0.4 + 0.6 * (1.0 - v));

	col = mix(col, vec3(1.0) - col, negative);
	col += vec3(0.9, 0.86, 0.8) * flash;
	col = pow(max(col, vec3(0.0)), vec3(1.0 / max(brightness, 0.05)));

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float t = floor(time_s * 24.0);
	float n = hash(FRAGCOORD.xy + t * 37.0) + hash(FRAGCOORD.xy * 1.37 + t * 11.0) - 1.0;
	col += n * grain * mix(1.0, 0.35, smoothstep(0.0, 0.5, l));

	col *= 1.0 - fade;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
