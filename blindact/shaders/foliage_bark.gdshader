shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Bark of trunks, branches, roots, stumps and fallen logs.
// UV: u round the stem (repeats set per tube), v along it in metres.
// Moss grows on upward-facing bark, low on the trunk and on the north-west
// side, in patches; a birch darkens to rough black bark at its foot.
// Cut and broken ends (vertex COLOR.r = 1, UV = 0..1 across the disc) show
// growth rings. Wind maths are the same as foliage.gdshader: the whole tree
// bends with height, branches bob (COLOR.g out along the branch, COLOR.b
// phase), so the needle cards stay where they grow.
// Per instance (MultiMesh custom data): z = wind phase, w = extra sway,
//   y = darkening (old, wet bark).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 uv_scale = vec2(1.0, 0.8);
uniform float normal_depth = 1.2;
uniform float moss_amount = 0.5;
uniform float moss_low = 1.6;
uniform float base_dark = 0.0;
uniform float tree_height = 12.0;
uniform float sway_amt = 1.0;
uniform float branch_amt = 1.0;
uniform float wind_strength = 0.3;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float wind_speed = 1.0;

varying vec3 v_obj;
varying vec3 v_wn;
varying float v_end;
varying float v_dark;

vec3 tree_sway(vec3 v, mat4 model, float ph, float amt) {
	float hk = clamp(v.y / tree_height, 0.0, 1.4);
	float bend = hk * hk;
	float t = TIME * wind_speed;
	float gust = 0.55 + 0.45 * sin(t * 0.31 + ph * 0.7) * sin(t * 0.17 + ph * 1.9);
	float osc = sin(t * 0.83 + ph) * 0.55 + sin(t * 1.61 + ph * 1.37) * 0.22;
	vec2 w = wind_dir * (gust * 0.7 + osc * 0.5) * wind_strength * amt;
	mat3 m3 = mat3(model[0].xyz, model[1].xyz, model[2].xyz);
	float s2 = max(dot(model[0].xyz, model[0].xyz), 1e-4);
	vec3 wo = (transpose(m3) * vec3(w.x, 0.0, w.y)) / s2;
	return wo * bend * tree_height * 0.06;
}

void vertex() {
	v_obj = VERTEX;
	vec4 ic = INSTANCE_CUSTOM;
	float ph = ic.z * 6.2831 + MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.07;
	vec3 disp = tree_sway(VERTEX, MODEL_MATRIX, ph, sway_amt * (1.0 + ic.w));
	float t = TIME * wind_speed;
	float bw = COLOR.g;
	float bph = COLOR.b * 6.2831 + ph;
	disp.y += sin(t * 1.9 + bph) * 0.05 * bw * bw * wind_strength * branch_amt * 3.0;
	disp.xz += vec2(sin(t * 1.3 + bph), cos(t * 1.1 + bph)) * 0.03 * bw * wind_strength * branch_amt * 3.0;
	VERTEX += disp;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_end = COLOR.r;
	v_dark = ic.y;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(albedo_tex, uv).rgb * tint;
	vec3 nm = texture(normal_tex, uv).rgb;
	float rough = texture(rough_tex, uv).r;
	float mn = texture(moss_tex, uv * 0.23 + vec2(0.31, 0.17)).g;
	float m = max(v_wn.y, 0.0) * 1.3 + smoothstep(moss_low, 0.0, v_obj.y) * 0.85 + max(dot(v_wn.xz, vec2(-0.6, -0.8)), 0.0) * 0.4;
	float mk = smoothstep(0.55, 0.85, m * moss_amount * (0.45 + 1.1 * mn));
	vec2 muv = uv * 1.9;
	alb = mix(alb, texture(moss_tex, muv).rgb, mk);
	nm = mix(nm, texture(moss_nrm, muv).rgb, mk);
	rough = mix(rough, 0.96, mk);
	if (base_dark > 0.0) {
		float bd = smoothstep(1.5, 0.15, v_obj.y + (mn - 0.5) * 1.2) * base_dark;
		alb = mix(alb, alb * vec3(0.22, 0.21, 0.2), bd);
		rough = mix(rough, 0.95, bd);
	}
	if (v_end > 0.5) {
		float rr = length(UV - 0.5) * 2.0;
		float rings = 0.5 + 0.5 * sin(rr * 55.0 + mn * 7.0);
		vec3 wood = mix(vec3(0.2, 0.14, 0.09), vec3(0.34, 0.26, 0.17), rings);
		wood = mix(wood, wood * vec3(0.55, 0.6, 0.5), smoothstep(0.55, 1.0, mn));
		alb = mix(wood, alb, smoothstep(0.86, 1.0, rr));
		nm = mix(vec3(0.5, 0.5, 1.0), nm, smoothstep(0.86, 1.0, rr));
		rough = 0.92;
	}
	alb *= 1.0 - clamp(v_dark, 0.0, 1.0) * 0.45;
	ALBEDO = alb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
