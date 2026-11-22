shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;

// Foliage cards: needles, bare twigs, fern fronds, bush leaves, grass.
// Alpha-scissor with alpha-to-coverage; the alpha is raised with the mip
// level so a far crown keeps its density instead of thinning to nothing.
// Normals are baked into the mesh pointing out of the crown (soft, volumetric
// lighting) and used on both faces. Moonlight shining through from behind
// lights the needles a little (BACKLIGHT).
// Wind (identical in foliage_bark.gdshader, so cards stay on their branches):
//   the whole tree bends with height (tree_height), each branch bobs
//   (vertex COLOR.g = how far out along its branch, COLOR.b = its phase),
//   each card flutters at its free end (COLOR.r). COLOR.a = baked occlusion.
// Per instance (MultiMesh custom data): x = autumn yellowing, y = darkening,
//   z = wind phase, w = extra sway.
// Distance fade: dithered out between fade_far and fade_far + fade_len,
//   measured from cam_pos (set every frame by ExteriorBuilder) so the shadow
//   pass agrees with the camera pass. fade_far <= 0 disables it.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.42;
uniform float roughness_v = 0.82;
uniform float translucency = 0.35;
uniform float ao_strength = 1.0;
uniform float tree_height = 12.0;
uniform float sway_amt = 1.0;
uniform float branch_amt = 1.0;
uniform float flutter_amt = 1.0;
uniform float wind_strength = 0.3;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float wind_speed = 1.0;
uniform vec3 cam_pos = vec3(0.0);
uniform float fade_far = 0.0;
uniform float fade_len = 6.0;

varying vec3 v_n;
varying float v_ao;
varying vec2 v_ic;
varying float v_dist;

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
	vec4 ic = INSTANCE_CUSTOM;
	float ph = ic.z * 6.2831 + MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.07;
	vec3 disp = tree_sway(VERTEX, MODEL_MATRIX, ph, sway_amt * (1.0 + ic.w));
	float t = TIME * wind_speed;
	float bw = COLOR.g;
	float bph = COLOR.b * 6.2831 + ph;
	disp.y += sin(t * 1.9 + bph) * 0.05 * bw * bw * wind_strength * branch_amt * 3.0;
	disp.xz += vec2(sin(t * 1.3 + bph), cos(t * 1.1 + bph)) * 0.03 * bw * wind_strength * branch_amt * 3.0;
	float fw = COLOR.r;
	disp += NORMAL * sin(t * 6.5 + bph * 3.0 + VERTEX.x * 4.0 + VERTEX.z * 3.0) * 0.025 * fw * wind_strength * flutter_amt * 3.0;
	VERTEX += disp;
	v_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_ao = mix(1.0, COLOR.a, ao_strength);
	v_ic = ic.xy;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = distance(wp, cam_pos);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec2 tsz = vec2(textureSize(albedo_tex, 0));
	vec2 dx = dFdx(UV * tsz);
	vec2 dy = dFdy(UV * tsz);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	float a = tex.a * (1.0 + mip * 0.28);
	if (fade_far > 0.0) {
		float f = clamp((v_dist - fade_far) / fade_len, 0.0, 1.0);
		float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (f > ign) {
			discard;
		}
	}
	vec3 c = tex.rgb * tint;
	c = mix(c, c * vec3(1.3, 1.05, 0.45) + vec3(0.03, 0.022, 0.0), clamp(v_ic.x, 0.0, 1.0));
	c *= 1.0 - clamp(v_ic.y, 0.0, 1.0) * 0.55;
	ALBEDO = c;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * tsz;
	NORMAL = normalize(v_n);
	ROUGHNESS = roughness_v;
	SPECULAR = 0.22;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = c * translucency;
}
