shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Weathered beam wood. The texture holds two 8:1 strips rectified from the
// photos (top half / bottom half). Mesh UVs are in metres: u along the
// timber, v across it. INSTANCE_CUSTOM.r picks the strip, .g offsets u.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float strip_length = 2.4;  // metres covered by one strip along u
uniform float strip_height = 0.3;  // metres covered by one strip across v
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.86;
uniform float use_instance = 1.0;

varying flat vec2 v_sel;

void vertex() {
	v_sel = mix(vec2(0.0), INSTANCE_CUSTOM.rg, use_instance);
}

void fragment() {
	float strip = step(0.5, v_sel.x);
	float u = UV.x / strip_length + v_sel.y;
	float m = fract(UV.y / (strip_height * 2.0));
	m = 1.0 - abs(m * 2.0 - 1.0);  // mirrored repeat across the timber
	m = clamp(m, 0.02, 0.98);
	vec2 uv = vec2(u, (strip + m) * 0.5);
	vec3 a = texture(albedo_tex, uv).rgb * tint;
	ALBEDO = a;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
