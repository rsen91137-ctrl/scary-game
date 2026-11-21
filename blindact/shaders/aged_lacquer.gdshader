shader_type spatial;

// The piano's black lacquer after decades: a clear coat that still gives back
// the lamp, worn through to swirl marks where it was polished, clouded by
// fingers along the edges, the grain ghosting through, and dust lying on
// every surface that faces up. Mapped in world space (no UVs needed).

uniform vec3 base_color : source_color = vec3(0.03, 0.03, 0.033);
uniform sampler2D grain_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grain_amount = 0.18;
uniform float dust = 0.65;
uniform float smudge = 0.6;
uniform float scratches = 0.7;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 an = abs(n);
	vec2 p = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float g = texture(grain_albedo, p * 1.4).r;
	vec3 alb = base_color * (1.0 + (g - 0.5) * grain_amount * 4.0);
	// polishing swirls: short arcs, fine and dense, only seen in a reflection
	vec2 sw = p * 140.0;
	float ang = vnoise(p * 6.0) * 6.2832;
	vec2 dir = vec2(cos(ang), sin(ang));
	float arc = vnoise(vec2(dot(sw, dir) * 6.0, dot(sw, vec2(-dir.y, dir.x)) * 0.25));
	float scr = smoothstep(0.86, 0.98, arc) * scratches;
	// fingers: clouded patches, mostly low on the case and round the keys
	float smg = smoothstep(0.5, 0.85, vnoise(p * 8.0 + 3.1)) * smudge * (0.5 + 0.5 * smoothstep(1.2, 0.6, wpos.y));
	// dust on anything facing up, thicker away from where hands go
	float up = smoothstep(0.55, 0.95, n.y);
	float dst = up * dust * (0.45 + 0.55 * vnoise(p * 21.0)) * (0.6 + 0.4 * vnoise(p * 3.3 + 7.0));
	alb = mix(alb, vec3(0.3, 0.31, 0.32), dst * 0.5);
	float rough = 0.06 + scr * 0.22 + smg * 0.32;
	rough = mix(rough, 0.9, dst);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	CLEARCOAT = 1.0 - dst * 0.9;
	CLEARCOAT_ROUGHNESS = clamp(0.04 + smg * 0.3 + scr * 0.25, 0.0, 1.0);
}
