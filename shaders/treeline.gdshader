shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

// Distant tree-line silhouette card. The horizontal texture coordinate comes
// from world Z so the card can slide along with the walker without the
// silhouette moving: the far shore looks endless and seamless.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float period = 110.0;      // metres per texture repeat
uniform vec3 tint : source_color = vec3(0.5);

varying float v_wz;

void vertex() {
	v_wz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec4 c = texture(albedo_tex, vec2(v_wz / period, UV.y));
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
