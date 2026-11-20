shader_type canvas_item;

// The main-menu eye, after the owner's sketch: a long almond with a tapering
// tail to the left (outer corner), a rounder inner corner on the right with
// the caruncle, and a large iris cut by the upper lid. Traced analytically
// per pixel (orthographic macro view; iris radius = 0.5 eye units):
//   * the white is an ellipsoid stretched sideways so it fills the long
//     fissure; the iris / cornea use a unit sphere riding on its front
//   * iris seen through the cornea with refraction, pupil, corneal caustic
//   * sclera vessels (eye_veins.png) that rotate with the gaze, haemorrhage
//   * lids with margins, tear meniscus, caruncle, lashes and lash shadows
//   * skin with pores and wrinkles under a dim warm key light that sinks
//     into darkness; window catchlight; blood tear; cataract; red reflex
// Textures are sampled raw (sRGB) and linearised here; output is tonemapped.

uniform sampler2D iris_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D vein_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D skin_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D skin_n_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D lash_up_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D lash_lo_tex : filter_linear_mipmap, repeat_disable;

uniform vec2 eye_center = vec2(0.575, 0.37);  // screen uv of the iris centre at rest
uniform float eye_scale = 0.42;               // screen heights per eye unit
uniform vec2 gaze = vec2(0.0);                // yaw (+ right), pitch (+ up), radians
uniform float pupil = 0.35;                   // 0 pinhole .. 1 fully dilated
uniform float blink = 0.0;                    // 0 open .. 1 closed
uniform float squint = 0.0;
uniform float wide = 0.0;                     // fear: lids pulled open
uniform float redness = 1.0;                  // 0 clean .. 1.6 flooded with blood
uniform float vein_pulse = 0.0;               // heartbeat
uniform float bleed = 0.0;                    // blood tear progress 0..1
uniform float milky = 0.0;                    // cataract / blind
uniform float red_reflex = 0.0;               // the pupil glows red
uniform float light = 1.0;                    // key light (flicker)
uniform float window_light = 1.0;             // catchlight strength
uniform float exposure = 1.0;
uniform float time_s = 0.0;

const float X_L = -2.0;
const float Y_L = 0.07;
const float X_R = 1.35;
const float Y_R = -0.25;
const float UP_H = 0.69;
const float UP_PK = 0.68;
const float UP_PL = 1.6;
const float UP_PR = 0.5;
const float LO_H = 0.32;
const float LO_PK = 0.65;
const float LO_PL = 1.85;
const float LO_PR = 0.45;
const float L_UP = 0.42;
const float L_LO = 0.20;
const float A_L = 2.1;          // ellipsoid half-width to the left
const float A_R = 1.45;         // ... and to the right
const float EYE_CY = 0.11;      // eyeball centre height
const float IRIS_R = 0.5;
const float IRIS_D = 0.80;
const float CORNEA_C = 0.451;
const float CORNEA_R = 0.65;
const float LIMBUS_Z = 0.866;

float bump2(float s, float pk, float pl, float pr) {
	s = clamp(s, 0.0, 1.0);
	bool left = s < pk;
	float u = left ? s / pk : (1.0 - s) / (1.0 - pk);
	float v = max(sin(0.5 * PI * u), 0.0);
	return pow(v, left ? pl : pr);
}

float lin1(float c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
vec3 lin(vec3 c) { return vec3(lin1(c.r), lin1(c.g), lin1(c.b)); }

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

vec3 tonemap(vec3 x) {
	x *= exposure;
	vec3 c = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
	return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

// a dim rain-streaked window reflected in wet surfaces
float window_spec(vec3 r, float soft) {
	vec3 wd = normalize(vec3(-0.38, 0.5, 0.78));
	vec3 wx = normalize(cross(vec3(0.0, 1.0, 0.0), wd));
	vec3 wy = cross(wd, wx);
	float f = dot(r, wd);
	if (f <= 0.0) {
		return 0.0;
	}
	vec2 a = vec2(dot(r, wx), dot(r, wy)) / f;
	float w = smoothstep(0.075 + soft, 0.075 - soft, abs(a.x)) * smoothstep(0.11 + soft, 0.11 - soft, abs(a.y));
	float bars = smoothstep(0.003, 0.009 + soft, abs(a.x + 0.01)) * smoothstep(0.003, 0.009 + soft, abs(a.y + 0.02));
	float rain = 0.75 + 0.25 * vnoise(vec2(a.x * 90.0, a.y * 8.0 + time_s * 0.6));
	return w * mix(0.2, 1.0, bars) * rain;
}

float lamp_spec(vec3 r, float rough) {
	vec3 ld = normalize(vec3(-0.3, 0.72, 0.62));
	return pow(max(dot(r, ld), 0.0), mix(2200.0, 160.0, rough));
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - eye_center) * vec2(aspect, 1.0) / eye_scale;
	p.y = -p.y;
	float aa = max(fwidth(p.x), 1e-4) * 1.2;

	vec3 key_dir = normalize(vec3(-0.32, 0.78, 0.54));
	vec3 key_col = vec3(1.0, 0.56, 0.44) * 1.2 * light;
	vec3 fill_col = vec3(0.045, 0.008, 0.006) * (0.65 + 0.35 * light);
	vec2 sq = (p - vec2(-0.2, 0.06)) / vec2(2.15, 0.92);
	float spot = exp(-pow(dot(sq, sq), 1.8));

	// ---- lids ------------------------------------------------------------
	float s = (p.x - X_L) / (X_R - X_L);
	float base = mix(Y_L, Y_R, clamp(s, 0.0, 1.0));
	float bu = bump2(s, UP_PK, UP_PL, UP_PR);
	float bl = bump2(s, LO_PK, LO_PL, LO_PR);
	float hu = UP_H * (1.0 + 0.30 * wide + 0.9 * gaze.y - 0.15 * squint);
	float hl = LO_H * (1.0 + 0.15 * wide - 0.6 * gaze.y - 0.5 * squint);
	float y_closed = base - 0.4 * LO_H * bl;
	float y_lo = mix(base - hl * bl, y_closed, 0.3 * blink);
	float bk = smoothstep(0.0, 1.0, blink);
	float y_up = mix(base + hu * bu, y_lo - 0.002, bk);
	float y_up_rest = base + UP_H * bu;
	float y_cr = y_up_rest + 0.22 + 0.10 * bump2(s, UP_PK, 1.2, 0.8) - 0.08 * bk - 0.05 * squint + 0.05 * wide;
	float span = smoothstep(-0.1, 0.05, s) * smoothstep(1.1, 0.96, s);
	float d_up = y_up - p.y;
	float d_lo = p.y - y_lo;
	float open = smoothstep(-aa, aa, min(d_up, d_lo)) * step(0.0, s) * step(s, 1.0);
	float m_up = 0.028;
	float m_lo = 0.03 * (0.3 + 0.7 * bl);

	vec3 view = vec3(0.0, 0.0, 1.0);
	vec3 rd = vec3(0.0, 0.0, -1.0);

	// ---- eyeball ----------------------------------------------------------------
	vec3 eye_col = vec3(0.0);
	if (open > 0.0) {
		vec3 ez = normalize(vec3(sin(gaze.x) * cos(gaze.y), sin(gaze.y), cos(gaze.x) * cos(gaze.y)));
		vec3 ex = normalize(cross(vec3(0.0, 1.0, 0.0), ez));
		vec3 ey = cross(ez, ex);
		float occl_up = mix(0.08, 1.0, smoothstep(0.0, 0.42, d_up));
		float occl_lo = mix(0.45, 1.0, smoothstep(0.0, 0.16, d_lo));
		float lash_sh = textureLod(lash_up_tex, vec2(clamp(s, 0.0, 1.0), 1.0 - clamp((p.y - y_up) / L_UP + 0.22, 0.0, 1.0)), 2.5).a;
		float shadow = occl_up * occl_lo * (1.0 - 0.6 * lash_sh * smoothstep(0.22, 0.0, d_up));

		float a = p.x < 0.0 ? A_L : A_R;
		vec2 pe = vec2(p.x / a, p.y - EYE_CY);
		float r2 = dot(pe, pe);
		if (r2 < 1.0) {
			float z = sqrt(1.0 - r2);
			vec3 ns = vec3(pe, z);                          // unit-sphere point
			vec3 n = normalize(vec3(pe.x / a, pe.y, z));     // ellipsoid normal
			vec3 nl = vec3(dot(ns, ex), dot(ns, ey), dot(ns, ez));
			// --- the white
			float th = acos(clamp(nl.z, -1.0, 1.0));
			float ph = atan(nl.y, nl.x);
			vec2 chart = th * vec2(cos(ph), sin(ph));
			vec4 vs = texture(vein_tex, vec2(chart.x / 3.6 + 0.5, 0.5 - chart.y / 3.6));
			float rdn = clamp(redness, 0.0, 1.6);
			vec3 sc = vec3(0.6, 0.45, 0.41);
			sc = mix(sc, vec3(0.62, 0.22, 0.19), smoothstep(0.56, 1.25, th) * (0.25 + 0.55 * rdn));
			sc = mix(sc, vec3(0.58, 0.2, 0.17), 0.22 * rdn);
			sc = mix(sc, vec3(0.55, 0.53, 0.56), smoothstep(0.66, 0.54, th) * 0.45);
			float vp = 1.0 + 0.3 * vein_pulse;
			sc = mix(sc, vec3(0.24, 0.04, 0.08), clamp(vs.a * 0.55 * rdn * vp, 0.0, 1.0));
			sc = mix(sc, vec3(0.5, 0.05, 0.04), clamp(vs.g * (0.3 + 1.2 * rdn) * vp, 0.0, 1.0));
			sc = mix(sc, vec3(0.3, 0.012, 0.012), clamp(vs.r * (0.55 + 0.6 * rdn) * vp, 0.0, 1.0));
			sc = mix(sc, vec3(0.34, 0.008, 0.008), clamp(vs.b * smoothstep(0.5, 1.1, rdn), 0.0, 1.0));
			sc = mix(sc, vec3(0.30, 0.01, 0.008), smoothstep(1.15, 1.6, rdn) * smoothstep(0.58, 0.72, th) * 0.9);
			float ndl = dot(n, key_dir);
			float diff = clamp((ndl + 0.3) / 1.3, 0.0, 1.0);
			vec3 lit_s = sc * (key_col * diff * spot * shadow + fill_col);
			lit_s *= mix(0.25, 1.0, smoothstep(0.0, 0.55, n.z));
			vec3 rr = reflect(rd, n);
			float fres = 0.04 + 0.96 * pow(1.0 - n.z, 5.0);
			lit_s += vec3(0.62, 0.7, 0.85) * window_spec(rr, 0.06) * 0.22 * window_light * shadow * (0.5 + fres);
			lit_s += vec3(1.0, 0.7, 0.55) * lamp_spec(rr, 0.7) * 0.35 * light * shadow;

			// --- iris through the cornea (unit sphere riding on the ellipsoid)
			float ag = gaze.x < 0.0 ? A_L : A_R;
			vec2 pc2 = vec2(p.x - (ag - 1.0) * sin(gaze.x) * cos(gaze.y), p.y - EYE_CY);
			vec3 o = vec3(pc2, 5.0);
			vec3 cc = ez * CORNEA_C;
			vec3 oc = o - cc;
			float b = dot(oc, rd);
			float c = dot(oc, oc) - CORNEA_R * CORNEA_R;
			float disc = b * b - c;
			vec3 lit_i = lit_s;
			if (disc > 0.0) {
				vec3 hc = o + rd * (-b - sqrt(disc));
				float on_cornea = smoothstep(LIMBUS_Z - 0.004, LIMBUS_Z + 0.012, dot(hc, ez));
				if (on_cornea > 0.0) {
					vec3 nc = normalize(hc - cc);
					vec3 rfr = refract(rd, nc, 1.0 / 1.336);
					float s2 = (IRIS_D - dot(hc, ez)) / min(dot(rfr, ez), -1e-3);
					vec3 X = hc + rfr * s2;
					vec2 q = vec2(dot(X, ex), dot(X, ey));
					float rq = length(q);
					float rp = mix(0.09, 0.37, clamp(pupil, 0.0, 1.0));
					float ang = atan(q.y, q.x) / TAU + 0.5;
					float v = (rq - rp) / (IRIS_R - rp);
					vec4 it = texture(iris_tex, vec2(ang, clamp(v, 0.0, 1.0)));
					vec3 ic = lin(it.rgb) * vec3(1.05, 0.82, 0.78);
					float hx = texture(iris_tex, vec2(ang + 0.0015, clamp(v, 0.0, 1.0))).a - it.a;
					float hy = texture(iris_tex, vec2(ang, clamp(v + 0.01, 0.0, 1.0))).a - it.a;
					vec2 rdir = rq > 1e-4 ? q / rq : vec2(1.0, 0.0);
					vec3 inrm = normalize(ez + (ex * (-hx * 6.0 * -rdir.y + -hy * 3.0 * rdir.x) + ey * (-hx * 6.0 * rdir.x + -hy * 3.0 * rdir.y)) * 0.6);
					float idiff = clamp(dot(inrm, key_dir) * 0.6 + 0.45, 0.0, 1.0);
					vec2 kl = normalize(vec2(dot(key_dir, ex), dot(key_dir, ey)));
					float caustic = smoothstep(0.0, 0.8, dot(rdir, -kl)) * smoothstep(rp, IRIS_R, rq) * smoothstep(IRIS_R, IRIS_R * 0.75, rq);
					vec3 iris_lit = ic * (key_col * (idiff + caustic * 1.1) * spot * shadow + fill_col * 1.5);
					float pupil_m = smoothstep(rp + 0.006, rp - 0.006, rq);
					vec3 pcol = vec3(0.003, 0.002, 0.002) + vec3(0.45, 0.015, 0.01) * red_reflex * smoothstep(rp, 0.0, rq);
					iris_lit = mix(iris_lit, pcol, pupil_m);
					float mk = clamp(milky, 0.0, 1.0);
					if (mk > 0.0) {
						float cloud = fbm(q * 9.0 + 3.0) * 0.6 + 0.4;
						vec3 mc = vec3(0.6, 0.63, 0.66) * cloud * (key_col * 0.45 * spot * shadow + fill_col * 3.0);
						iris_lit = mix(iris_lit, mc, mk * smoothstep(IRIS_R + 0.04, IRIS_R * 0.55, rq) * (0.75 + 0.25 * cloud));
					}
					float in_iris = smoothstep(IRIS_R + 0.012, IRIS_R - 0.02, rq);
					vec3 limb = lit_s * vec3(0.55, 0.55, 0.62);
					iris_lit = mix(mix(lit_s, limb, smoothstep(IRIS_R + 0.08, IRIS_R, rq)), iris_lit, in_iris);
					vec3 rc = reflect(rd, nc);
					float fc = 0.03 + 0.97 * pow(1.0 - max(dot(nc, view), 0.0), 5.0);
					iris_lit += vec3(0.7, 0.78, 0.95) * window_spec(rc, 0.03) * 0.75 * window_light * mix(0.35, 1.0, shadow);
					iris_lit += vec3(1.0, 0.75, 0.55) * lamp_spec(rc, 0.12) * 1.2 * light * mix(0.3, 1.0, shadow);
					iris_lit += vec3(0.04, 0.02, 0.02) * fc;
					lit_i = mix(lit_s, iris_lit, on_cornea);
				}
			}
			eye_col = lit_i;
		} else {
			eye_col = vec3(0.04, 0.008, 0.006) * key_col * spot * 0.25;
		}
		// caruncle and plica at the inner (right) corner
		float car = smoothstep(1.0, 1.24, p.x);
		if (car > 0.0) {
			float bumps = fbm(p * 24.0);
			vec3 cc2 = mix(vec3(0.5, 0.14, 0.14), vec3(0.7, 0.3, 0.29), bumps);
			vec3 cl = cc2 * (key_col * (0.45 + 0.4 * bumps) * spot * 0.7 * shadow + fill_col);
			cl += vec3(1.0, 0.8, 0.65) * smoothstep(0.9, 0.98, vnoise(p * 50.0)) * 0.12 * light * spot * smoothstep(1.12, 1.25, p.x);
			eye_col = mix(eye_col, cl, car);
		}
		// the long outer tail sinks into the socket
		eye_col *= mix(1.0, 0.18, smoothstep(-1.2, -1.95, p.x));
		float men = exp(-pow((d_lo - 0.012) / 0.006, 2.0)) * span;
		eye_col += vec3(0.85, 0.75, 0.7) * men * 0.1 * spot * (0.6 + 0.4 * light) * smoothstep(0.85, 0.3, abs(s - 0.6) * 2.0);
		eye_col = mix(eye_col, vec3(0.2, 0.004, 0.004) * (key_col * spot * 0.35 + fill_col), smoothstep(0.03, 0.0, d_lo) * smoothstep(0.0, 0.25, bleed) * 0.85);
	}

	// ---- skin, margins, lashes -------------------------------------------------
	vec3 skin_c;
	{
		float y_tex = p.y;
		if (p.y > y_up && p.y < y_cr) {
			float k = (p.y - y_up) / max(y_cr - y_up, 1e-3);
			y_tex = mix(y_up_rest, y_cr, k);
		}
		vec2 suv = vec2((p.x + 3.2) / 6.4, (1.8 - y_tex) / 3.6);
		vec4 st = texture(skin_tex, suv);
		vec3 alb = lin(st.rgb);
		vec3 fn = texture(skin_n_tex, suv).rgb * 2.0 - 1.0;
		// big shapes as the gradient of a smooth height field (no seams)
		vec2 dq = (p - vec2(-0.3, 0.04)) / vec2(2.1, 0.95);
		float dome = 0.6 * exp(-dot(dq, dq));
		vec2 grad = dome * (-2.0 * dq / vec2(2.1, 0.95));
		float cy = clamp((p.y - (y_cr - 0.03)) / 0.28, 0.0, 1.0);
		grad.y += 0.14 * 6.0 * cy * (1.0 - cy) / 0.28 * span;
		float gr = (p.y - y_cr) / 0.03;
		grad.y += 0.025 * exp(-gr * gr) * 2.0 * gr / 0.03 * span;
		float lb = (p.y - (y_lo - 0.17)) / 0.11;
		grad.y += -0.05 * exp(-lb * lb) * 2.0 * lb / 0.11 * span * step(p.y, y_lo);
		float tt = (p.y - (y_lo - 0.46)) / 0.1;
		grad.y += 0.06 * exp(-tt * tt) * 2.0 * tt / 0.1 * smoothstep(-1.6, -0.6, p.x) * smoothstep(1.6, 0.8, p.x);
		grad.y -= 0.18 * smoothstep(-0.5, -1.4, p.y);
		vec3 nb = normalize(vec3(-grad, 1.0));
		// the upper lid hugs the eyeball
		if (p.y > y_lo) {
			float a2 = p.x < 0.0 ? A_L : A_R;
			vec2 pl = vec2(p.x / (a2 * 1.04), (p.y - EYE_CY) / 1.06);
			float rl = dot(pl, pl);
			float lid_w = smoothstep(y_cr + 0.06, y_cr - 0.04, p.y) * span;
			if (rl < 0.995 && lid_w > 0.0) {
				vec3 ne = normalize(vec3(pl.x / a2, pl.y, sqrt(1.0 - rl)));
				nb = normalize(mix(nb, ne, lid_w));
			}
		}
		vec3 N = normalize(nb + vec3(fn.xy * 0.35, 0.0));
		float ndl = dot(N, key_dir);
		float diff = clamp(ndl, 0.0, 1.0);
		float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
		vec3 sss = vec3(0.85, 0.2, 0.12) * max(wrap - diff, 0.0);
		float cav = mix(0.6, 1.0, st.a);
		vec3 lit = alb * (key_col * (diff + sss) * spot * cav + fill_col);
		vec3 hv = normalize(key_dir + view);
		lit += vec3(1.0, 0.75, 0.6) * pow(max(dot(N, hv), 0.0), 34.0) * 0.08 * cav * spot * light;
		lit *= mix(1.0, 0.4, exp(-pow((p.y - y_cr) / 0.035, 2.0)) * span);
		// upper margin: a ledge facing down, mostly in shadow
		float in_f = step(0.0, s) * step(s, 1.0);
		float um = smoothstep(m_up + aa, m_up - aa, p.y - y_up) * smoothstep(-aa, aa, p.y - y_up) * span * in_f;
		lit = mix(lit, vec3(0.4, 0.13, 0.12) * (key_col * 0.12 * spot + fill_col), um);
		// lower margin: the wet waterline
		float lm = smoothstep(m_lo + aa, m_lo - aa, y_lo - p.y) * smoothstep(-aa, aa, y_lo - p.y) * span * in_f;
		vec3 wl = vec3(0.5, 0.17, 0.16) * (key_col * 0.32 * spot + fill_col);
		wl += vec3(1.0, 0.8, 0.7) * smoothstep(0.75, 1.0, vnoise(vec2(p.x * 40.0, 3.0))) * 0.08 * spot * light;
		wl = mix(wl, vec3(0.2, 0.004, 0.004) * (key_col * spot * 0.4 + fill_col), smoothstep(0.0, 0.3, bleed));
		lit = mix(lit, wl, lm);
		// eyelashes
		float ts = clamp(s, 0.0, 1.0);
		float sgn = mix(1.0, -0.5, bk);
		float vu = (p.y - y_up) * sgn / L_UP;
		vec4 lu = textureLod(lash_up_tex, vec2(ts, 1.0 - clamp(vu, 0.0, 1.0)), 0.9);
		lu.a *= step(0.0, vu) * step(vu, 1.0) * smoothstep(-0.02, 0.03, s) * smoothstep(1.03, 0.97, s);
		float vl = (y_lo - p.y) / L_LO;
		vec4 ll = textureLod(lash_lo_tex, vec2(ts, clamp(vl, 0.0, 1.0)), 1.0);
		ll.a *= step(0.0, vl) * step(vl, 1.0) * span * in_f;
		vec3 lash_c = vec3(0.012, 0.009, 0.008) * (key_col * spot + fill_col) + vec3(0.25, 0.18, 0.15) * 0.03 * spot * light;
		lit = mix(lit, lash_c, clamp(lu.a * 1.15, 0.0, 1.0));
		lit = mix(lit, lash_c, clamp(ll.a, 0.0, 1.0));
		skin_c = lit;
	}
	vec3 col = mix(skin_c, eye_col, open);

	// ---- blood tear ------------------------------------------------------------
	if (bleed > 0.0) {
		float x0 = 0.22;
		float s0 = (x0 - X_L) / (X_R - X_L);
		float ys = mix(Y_L, Y_R, s0) - hl * bump2(s0, LO_PK, LO_PL, LO_PR) - 0.02;
		float len = bleed * 1.5;
		float dy = ys - p.y;
		if (dy > -0.06 && dy < len + 0.1) {
			float xc = x0 + 0.05 * sin(dy * 3.3) + 0.022 * sin(dy * 8.1 + 1.0) - 0.05 * dy;
			float w = 0.024 * (1.0 - 0.35 * clamp(dy / 1.5, 0.0, 1.0)) + 0.012 * smoothstep(0.0, 0.1, dy) * (1.0 - smoothstep(0.1, 0.3, dy));
			float dx = p.x - xc;
			float trail = smoothstep(w + aa, w - aa, abs(dx)) * step(0.0, dy) * step(dy, len);
			vec2 tip = vec2(x0 + 0.05 * sin(len * 3.3) + 0.022 * sin(len * 8.1 + 1.0) - 0.05 * len, ys - len);
			float drop = smoothstep(0.046 + aa, 0.046 - aa, length((p - tip - vec2(0.0, -0.018)) * vec2(1.0, 0.82)));
			float m = max(trail, drop);
			if (m > 0.0) {
				float shade = 0.55 + 0.45 * smoothstep(w, -w, dx);
				vec3 bc = vec3(0.26, 0.006, 0.005) * (key_col * shade * spot * 0.7 + fill_col * 1.4);
				float hl2 = smoothstep(0.5, 0.95, 1.0 - abs(dx + w * 0.45) / max(w * 0.5, 1e-3)) * trail;
				hl2 += smoothstep(0.02, 0.0, length(p - tip - vec2(-0.016, -0.004))) * drop;
				bc += vec3(1.0, 0.7, 0.6) * hl2 * 0.35 * spot * light;
				col = mix(col, bc, m);
			}
		}
	}

	COLOR = vec4(tonemap(col), 1.0);
}
