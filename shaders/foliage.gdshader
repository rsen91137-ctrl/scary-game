shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Alpha-tested leaf cards with wind and a bit of translucency.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.42;
uniform float wind = 0.05;
uniform float wind_speed = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = dot(wp, vec3(0.37, 0.21, 0.53));
	float t = TIME * wind_speed;
	float g = sin(t * 1.3 + ph) * 0.6 + sin(t * 2.9 + ph * 2.1) * 0.3 + sin(t * 0.45 + ph * 0.3) * 0.8;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(g, g * 0.25, g * 0.6)) * wind;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
	BACKLIGHT = c.rgb * tint * 0.6;
}
