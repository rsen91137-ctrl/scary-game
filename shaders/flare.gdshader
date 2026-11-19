shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// Phone-camera style starburst on bright lamps (like the reference photos).
// Drawn as a camera-facing quad that keeps a constant screen size. Occlusion is
// tested against the depth buffer at the lamp's own projected position, so the
// flare disappears when a pillar passes in front of the lamp.

uniform sampler2D flare_tex : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 color : source_color = vec3(1.0, 0.9, 0.75);
uniform float intensity = 1.0;
uniform float screen_size = 0.6;
uniform float rotation = 0.0;

varying float v_visible;
varying float v_depth_ok;

void vertex() {
	// billboard, constant screen size
	vec4 center_view = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = -center_view.z;
	float s = screen_size * dist * 0.5;
	float cr = cos(rotation), sr = sin(rotation);
	vec2 v = vec2(VERTEX.x * cr - VERTEX.y * sr, VERTEX.x * sr + VERTEX.y * cr);
	center_view.xy += v * s;
	POSITION = PROJECTION_MATRIX * center_view;
	v_visible = dist > 0.05 ? 1.0 : 0.0;
}

void fragment() {
	// project the lamp centre and compare with the depth buffer there
	vec4 c_clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(NODE_POSITION_WORLD, 1.0));
	vec2 c_ndc = c_clip.xy / c_clip.w;
	vec2 c_uv = c_ndc * 0.5 + 0.5;
	float occl = 0.0;
	float total = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 suv = c_uv + vec2(float(i), float(j)) * 0.004;
			float d = texture(depth_tex, suv).r;
			vec4 vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
			float scene_z = -vp.z / vp.w;
			float lamp_z = c_clip.w;
			occl += (scene_z + 0.25 < lamp_z) ? 0.0 : 1.0;
			total += 1.0;
		}
	}
	float vis = occl / total;
	vis *= step(0.0, c_uv.x) * step(c_uv.x, 1.0) * step(0.0, c_uv.y) * step(c_uv.y, 1.0);
	float f = texture(flare_tex, UV).r;
	ALBEDO = color * f * intensity * vis * v_visible;
}
