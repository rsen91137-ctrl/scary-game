shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sandstone pillar blocks.
// The atlas holds 16 block faces (4x4) rectified from the reference photos.
// Each side face of every block instance picks a tile through INSTANCE_CUSTOM
// (r: +X, g: -X, b: +Z, a: -Z). Tile values >= 16 are mirrored.

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rough_atlas : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float ground_grime = 0.4;

varying flat float v_tile;
varying vec3 v_wpos;

void vertex() {
	vec3 n = NORMAL;
	float t = INSTANCE_CUSTOM.r;
	if (abs(n.x) > 0.5) {
		t = n.x > 0.0 ? INSTANCE_CUSTOM.r : INSTANCE_CUSTOM.g;
	} else if (abs(n.z) > 0.5) {
		t = n.z > 0.0 ? INSTANCE_CUSTOM.b : INSTANCE_CUSTOM.a;
	}
	v_tile = t;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = floor(v_tile + 0.5);
	bool flip = t >= 16.0;
	t = mod(t, 16.0);
	vec2 cell = vec2(mod(t, 4.0), floor(t / 4.0));
	vec2 uv = UV;
	if (flip) {
		uv.x = 1.0 - uv.x;
	}
	uv = clamp(uv, vec2(0.006), vec2(0.994));
	vec2 auv = (cell + uv) * 0.25;

	vec3 a = texture(albedo_atlas, auv).rgb * tint;
	float ground = smoothstep(1.3, 0.35, v_wpos.y);
	a *= mix(1.0, 0.7, ground * ground_grime);
	ALBEDO = a;

	vec3 nm = texture(normal_atlas, auv).rgb;
	if (flip) {
		nm.x = 1.0 - nm.x;
	}
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = texture(rough_atlas, auv).r;
	SPECULAR = 0.35;
}
