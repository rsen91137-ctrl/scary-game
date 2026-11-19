shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Still night lake: near-black body, slow wind ripples, mirror-like so that
// screen-space reflections pick up the lamps and the far shore.

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.006, 0.008, 0.01);
uniform float ripple_strength = 0.18;
uniform float roughness = 0.025;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	vec2 uv1 = p * 0.06 + TIME * vec2(0.0035, 0.0018);
	vec2 uv2 = p * 0.13 + TIME * vec2(-0.0024, 0.0041);
	vec2 uv3 = p * 0.37 + TIME * vec2(0.006, -0.003);
	vec3 n = texture(normal_tex, uv1).rgb * 0.5 + texture(normal_tex, uv2).rgb * 0.35 + texture(normal_tex, uv3).rgb * 0.15;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = ripple_strength;
	ALBEDO = deep_color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
