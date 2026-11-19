shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Dead vine tendrils and aerial roots. Instance-local mesh hangs from y = 0 down
// to y = -1, so the sway grows with the distance from the attachment point.

uniform vec3 color : source_color = vec3(0.52, 0.47, 0.38);
uniform float sway = 0.05;
uniform float speed = 1.0;
uniform float roughness = 0.9;

void vertex() {
	float down = clamp(-VERTEX.y, 0.0, 1.0);
	vec3 base = MODEL_MATRIX[3].xyz;
	float ph = base.x * 1.71 + base.z * 0.93 + base.y * 0.37;
	float t = TIME * speed;
	float wx = sin(t * 1.07 + ph) + 0.45 * sin(t * 2.31 + ph * 1.7);
	float wz = cos(t * 0.83 + ph * 1.3) + 0.35 * sin(t * 1.9 + ph);
	vec3 off = vec3(wx, 0.0, wz * 0.6) * sway * down * down;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	ALBEDO = color * (0.75 + 0.5 * COLOR.r);
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	BACKLIGHT = color * 0.35;
}
