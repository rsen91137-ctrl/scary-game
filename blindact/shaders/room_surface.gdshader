shader_type spatial;

// Walls, floors and ceilings of her flat (and his room). Textures are mapped
// in world space for axis-aligned surfaces, so patterns run on unbroken
// across wall pieces; the decay is laid on by where a point sits in the room.
//   kind 0  wallpaper: seams lifting, strips torn off down to the pasted
//           plaster, tide marks and drip runs under the ceiling, grime and
//           scuffs along the floor, mould in the top corners and low down
//   kind 1  floor: worn paths, dirt, old water marks
//   kind 2  ceiling: water rings, mould, paint fallen off to the plaster
//   kind 3  tiles: whole tiles fallen off (adhesive left behind), rust and
//           water runs, mould
// peel_mask.png: R = patches, G = water-stain rings, B = grime noise.
// Normal maps may be RG-only (RGTC), so Z is rebuilt here.
// Close up, a procedural micro relief (paper fibre, plaster grain, glaze
// ripple, wood pores) takes over where the texels run out; it fades out with
// distance so it never shimmers.

uniform int kind = 0;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D under_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D peel_mask : filter_linear_mipmap, repeat_enable;
uniform float repeat_m = 0.53;          // metres per texture repeat
uniform float under_repeat_m = 1.2;
uniform float rotate_deg = 0.0;         // floors: herringbone laid at 45 degrees
uniform vec3 tint = vec3(1.0);
uniform vec3 under_tint = vec3(1.0);
uniform float decay = 0.6;
uniform float peel = 0.5;
uniform float water = 0.6;
uniform float grime = 0.6;
uniform float mould = 0.3;
uniform float floor_y = 0.0;
uniform float ceil_y = 2.75;
uniform float normal_depth = 1.0;
uniform float tiles_per_repeat = 4.0;
uniform float seams = 1.0;              // kind 0: wallpaper strips (0 for bare plaster)
uniform vec2 seed = vec2(0.0);
uniform float micro = 1.0;              // close-up relief strength
uniform float cracks = 0.5;             // hairline cracks (plaster, ceilings, tiles)

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

// slope of the noise: a bump direction for the micro relief
vec2 vslope(vec2 p) {
	const float e = 0.35;
	return vec2(vnoise(p + vec2(e, 0.0)) - vnoise(p - vec2(e, 0.0)),
			vnoise(p + vec2(0.0, e)) - vnoise(p - vec2(0.0, e)));
}

// thin dark lines where a ridged noise peaks: hairline cracks
float crack_lines(vec2 m, float scale) {
	float r = 1.0 - abs(vnoise(m * scale) * 2.0 - 1.0);
	float r2 = 1.0 - abs(vnoise(m * scale * 2.3 + 17.0) * 2.0 - 1.0);
	float gate = smoothstep(0.55, 0.75, vnoise(m * scale * 0.21 + 3.0));
	return max(smoothstep(0.965, 0.995, r), smoothstep(0.975, 0.997, r2) * 0.6) * gate;
}

vec3 unpack_normal(vec3 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 an = abs(n);
	vec2 m;          // surface coordinates in metres (u to the right, v down)
	vec3 T;          // world direction of +u
	vec3 U;          // world direction of "up" in the image (-v)
	if (an.y > 0.5) {
		m = vec2(wpos.x, wpos.z);
		T = vec3(1.0, 0.0, 0.0);
		U = vec3(0.0, 0.0, -1.0);
		if (rotate_deg != 0.0) {
			float a = radians(rotate_deg);
			float c = cos(a);
			float s = sin(a);
			m = vec2(c * m.x - s * m.y, s * m.x + c * m.y);
			T = vec3(c, 0.0, -s);
			U = -vec3(s, 0.0, c);
		}
	} else if (an.x > an.z) {
		float sg = sign(n.x);
		m = vec2(-sg * wpos.z, -wpos.y);
		T = vec3(0.0, 0.0, -sg);
		U = vec3(0.0, 1.0, 0.0);
	} else {
		float sg = sign(n.z);
		m = vec2(sg * wpos.x, -wpos.y);
		T = vec3(sg, 0.0, 0.0);
		U = vec3(0.0, 1.0, 0.0);
	}
	vec2 uv = m / repeat_m;
	vec3 alb = texture(base_albedo, uv).rgb * tint;
	vec3 nb = texture(base_normal, uv).rgb;
	float rg = texture(base_rough, uv).r;
	vec4 pmA = texture(peel_mask, m * 0.45 + seed);
	vec4 pmB = texture(peel_mask, m * 0.17 + seed * 1.7 + 0.37);
	float ao = 1.0;
	float hy = wpos.y - floor_y;           // height above the floor
	float dc = ceil_y - wpos.y;            // distance below the ceiling
	vec3 nu = nb;
	vec2 um = m / under_repeat_m;

	if (kind == 0 || kind == 3) {
		float top = smoothstep(0.9, 0.0, dc);
		float low = smoothstep(0.35, 0.0, hy);
		float torn = 0.0;
		if (kind == 0) {
			// strips torn away, mostly up high and along the seams
			float sx = abs(fract(uv.x + 0.5) - 0.5) * repeat_m;
			float seam_near = smoothstep(0.12, 0.0, sx) * seams;
			float raw = pmB.r * (0.55 + 0.6 * top + 0.35 * seam_near) * peel * 1.25;
			torn = smoothstep(0.55, 0.6, raw);
			float rim = smoothstep(0.42, 0.55, raw) - torn;
			vec3 ua = texture(under_albedo, um).rgb * under_tint;
			alb = mix(alb, ua, torn);
			alb = mix(alb, alb * 1.2 + vec3(0.04, 0.035, 0.02), rim * 0.55);
			ao *= 1.0 - rim * 0.45 * (1.0 - torn);
			nu = mix(nb, texture(under_normal, um).rgb, torn);
			rg = mix(rg, 0.9, torn);
			// seams lifting here and there: a dark gap, a shadowed lip
			float lifted = smoothstep(0.5, 0.72, texture(peel_mask, vec2(floor(uv.x + 0.5) * 0.37 + seed.x, m.y * 0.6)).r) * peel * seams;
			float gap = smoothstep(0.004, 0.0, sx) * lifted;
			float lip = smoothstep(0.025, 0.0, sx) * lifted;
			alb *= 1.0 - gap * 0.75;
			ao *= 1.0 - lip * 0.35;
		} else {
			// tiles that fell off and left the grey adhesive behind
			vec2 tile = floor(uv * tiles_per_repeat);
			float hsh = hash12(tile + seed * 31.0);
			float miss_p = (0.015 + 0.12 * low + 0.05 * top) * peel;
			torn = step(hsh, miss_p);
			// no two tiles quite alike: glaze shade and gloss vary
			float th = hash12(tile + seed * 13.0 + 7.3);
			alb *= 0.93 + 0.12 * th;
			rg *= 0.75 + 0.5 * hash12(tile + 2.9);
			// grout darkened with dirt, worst low down
			vec2 tf = fract(uv * tiles_per_repeat);
			float edge = min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y));
			float grout = 1.0 - smoothstep(0.012, 0.03, edge);
			alb *= 1.0 - grout * (0.25 + 0.4 * low) * grime;
			// a few tiles cracked right across
			if (hash12(tile + 41.0) < 0.07 * cracks + 0.05 * low) {
				vec2 c = tf - 0.5;
				float a = hash12(tile + 5.0) * 6.2832;
				float wob = (vnoise(tf * 7.0 + tile) - 0.5) * 0.08;
				float d = abs(dot(c, vec2(cos(a), sin(a))) + wob);
				float line = smoothstep(0.012, 0.0, d);
				alb *= 1.0 - line * 0.7;
				rg = mix(rg, 0.8, line);
			}
			vec3 ua = texture(under_albedo, um).rgb * under_tint;
			alb = mix(alb, ua, torn);
			nu = mix(nb, texture(under_normal, um).rgb, torn);
			rg = mix(rg, 0.95, torn);
			// rust and water runs down the glaze
			float run = smoothstep(0.62, 0.82, texture(peel_mask, vec2(m.x * 4.0, m.y * 0.3) + seed + 0.5).r);
			alb = mix(alb, alb * vec3(0.78, 0.55, 0.36), run * water * 0.7 * (1.0 - torn));
			rg = mix(rg, 0.55, run * water * 0.6);
		}
		// water: tide marks spreading down from the ceiling, drip runs
		float drip = texture(peel_mask, vec2(m.x * 3.1, m.y * 0.25) + seed).b;
		float runs = smoothstep(0.55, 0.8, drip) * smoothstep(1.6, 0.2, dc);
		float rings = pmA.g * top * 1.3;
		float wet = clamp((rings + runs * 0.7) * water, 0.0, 1.0);
		alb = mix(alb, alb * vec3(0.66, 0.55, 0.4), wet);
		if (kind == 0) {
			// paper faded unevenly: the pattern washes out in patches
			float fade = smoothstep(0.35, 0.8, pmB.g) * (1.0 - torn) * seams;
			float lum = dot(alb, vec3(0.3, 0.59, 0.11));
			alb = mix(alb, vec3(lum) * vec3(0.95, 1.0, 1.03) * 1.08, fade * 0.45);
			// where hands and shoulders brushed along it for years
			float band = smoothstep(0.75, 1.05, hy) * smoothstep(1.65, 1.25, hy);
			alb *= 1.0 - band * smoothstep(0.35, 0.8, pmA.b) * 0.22 * grime;
		}
		// hairline cracks in bare plaster
		float ck = crack_lines(m + seed, 2.2) * cracks * (1.0 - seams * (1.0 - torn));
		alb *= 1.0 - ck * 0.55;
		ao *= 1.0 - ck * 0.3;
		// grime and scuffs along the floor
		float gr = low * (0.5 + 0.5 * pmA.b) * grime;
		alb = mix(alb, alb * vec3(0.5, 0.46, 0.4), gr);
		rg = mix(rg, 0.9, gr * 0.6);
		// mould: black-green speckle in the top corners, low down, in wet rooms
		float sp = smoothstep(0.6, 0.7, texture(peel_mask, m * 2.3 + seed * 3.0).b);
		float ml = sp * (top * 0.8 + low * 0.6 + (kind == 3 ? 0.35 : 0.0)) * mould * smoothstep(0.3, 0.7, pmB.g + 0.3);
		alb = mix(alb, vec3(0.03, 0.035, 0.025), clamp(ml, 0.0, 1.0));
	} else if (kind == 1) {
		float wear = smoothstep(0.4, 0.8, pmB.b) * decay;
		alb = mix(alb, alb * vec3(1.12, 1.08, 1.0) + 0.012, wear * 0.4);
		rg = mix(rg, min(1.0, rg + 0.3), wear);
		float dirt = smoothstep(0.5, 0.9, pmA.b) * grime;
		alb = mix(alb, alb * vec3(0.6, 0.56, 0.5), dirt * 0.5);
		float ring = pmA.g * water * 0.8;
		alb = mix(alb, alb * vec3(0.7, 0.6, 0.5), clamp(ring, 0.0, 1.0));
		// damp patches: darker, and glossy enough to hold a lamp's reflection
		float damp = smoothstep(0.6, 0.72, texture(peel_mask, m * 0.33 + seed + 0.71).g) * water;
		alb *= 1.0 - damp * 0.3;
		rg = mix(rg, 0.12, damp * 0.85);
	} else {
		float big = texture(peel_mask, m * 0.21 + seed + 0.11).g;
		float ring = clamp(big * 1.6 * water, 0.0, 1.0);
		alb = mix(alb, alb * vec3(0.7, 0.6, 0.43), ring);
		float sp = smoothstep(0.6, 0.7, texture(peel_mask, m * 2.0 + seed).b);
		alb = mix(alb, vec3(0.04, 0.045, 0.035), sp * mould * smoothstep(0.4, 0.8, pmB.g + 0.2));
		float raw = pmB.r * peel * 1.3;
		float peeled = smoothstep(0.62, 0.66, raw);
		alb = mix(alb, texture(under_albedo, um).rgb * under_tint, peeled);
		nu = mix(nb, texture(under_normal, um).rgb, peeled);
		ao *= 1.0 - (smoothstep(0.5, 0.62, raw) - peeled) * 0.5;
		float ck = crack_lines(m + seed, 1.6) * cracks;
		alb *= 1.0 - ck * 0.6;
	}
	ALBEDO = alb;
	ROUGHNESS = rg;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	vec3 tn = unpack_normal(nu);
	tn.xy *= normal_depth;
	// micro relief, only close to the eye
	float near = clamp(1.0 - length(VERTEX) / 3.5, 0.0, 1.0);
	if (near > 0.0 && micro > 0.0) {
		float sc = kind == 0 ? 260.0 : (kind == 2 ? 120.0 : (kind == 3 ? 40.0 : 200.0));
		float amt = kind == 0 ? 0.35 : (kind == 2 ? 0.5 : (kind == 3 ? 0.12 : 0.3));
		vec2 g = vslope(m * sc) + 0.5 * vslope(m * sc * 2.7 + 9.0);
		tn.xy += g * amt * micro * near;
	}
	vec3 wn = normalize(T * tn.x + U * tn.y + n * tn.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
