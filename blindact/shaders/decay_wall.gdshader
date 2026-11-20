shader_type spatial;

// Rotting plaster over brick. UVs are in metres (MeshUtil.box unit_uv=false).
// peel_mask.png: R = where the plaster has fallen off (brick shows, the edge
// is a crumbly lip), G = water-stain rings, B = grime noise. World height adds
// grime near the floor and soot under the ceilings; `decay` scales it all.

uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D brick_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D brick_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D peel_mask : filter_linear_mipmap, repeat_enable;
uniform float decay = 0.6;
uniform float tile = 0.55;           // plaster texture scale (repeats per metre)
uniform float brick_tile = 0.9;
uniform vec3 tint = vec3(1.0);
uniform float floor_h = 2.9;
uniform vec2 uv_offset = vec2(0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV + uv_offset;
	vec3 pa = texture(plaster_albedo, uv * tile).rgb * tint;
	vec3 pn = texture(plaster_normal, uv * tile).rgb;
	float pr = texture(plaster_rough, uv * tile).r;
	vec4 pm = texture(peel_mask, uv * 0.32);
	vec4 pm2 = texture(peel_mask, uv * 0.11 + 0.37);
	// big patches + small flakes, more of both with decay
	float peel_raw = max(pm2.r * smoothstep(0.2, 0.9, decay), pm.r * smoothstep(0.4, 1.0, decay) * 0.8);
	float peel = smoothstep(0.45, 0.55, peel_raw);
	float lip = smoothstep(0.25, 0.5, peel_raw) - peel;            // crumbly edge
	vec3 ba = texture(brick_albedo, uv * brick_tile).rgb;
	vec3 bn = texture(brick_normal, uv * brick_tile).rgb;
	vec3 col = mix(pa, ba * 0.8, peel);
	// the edge of the broken plaster: a pale broken rim with a dark shadow inside
	col = mix(col, col * 0.55, lip * 0.8);
	// water stains and grime
	float ring = pm.g * decay;
	col = mix(col, col * vec3(0.72, 0.62, 0.48), clamp(ring, 0.0, 1.0) * (1.0 - peel));
	float yf = mod(wpos.y + 0.2, floor_h * 0.5) / (floor_h * 0.5);
	float grime = smoothstep(0.45, 0.0, yf) * (0.5 + 0.5 * pm.b);
	col = mix(col, col * vec3(0.45, 0.42, 0.38), grime * 0.7 * decay);
	float soot = smoothstep(0.75, 1.0, yf) * pm2.b;
	col = mix(col, vec3(0.05), soot * 0.55 * decay);
	col *= mix(1.0, 0.75 + 0.5 * pm.b, 0.5 * decay);
	ALBEDO = col;
	NORMAL_MAP = mix(pn, bn, peel);
	NORMAL_MAP_DEPTH = 1.0 + peel * 0.6;
	ROUGHNESS = mix(pr, 0.9, peel);
	AO = 1.0 - lip * 0.6;
	AO_LIGHT_AFFECT = 0.4;
}
