shader_type spatial;

// Kitchen-knife steel: brushed along the blade, with blood dried in smears
// and runs towards the edge.

uniform float blood = 0.7;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// lpos: y along the blade, z across it (0 at the spine, negative to the edge)
	float brush = vnoise(vec2(lpos.y * 18.0, lpos.z * 900.0));
	vec3 steel = vec3(0.62, 0.64, 0.66) * (0.9 + 0.1 * brush);
	float edge = smoothstep(0.0, -0.035, lpos.z);
	float b = smoothstep(0.42, 0.62, vnoise(lpos.yz * vec2(28.0, 60.0)) * 0.7 + edge * 0.45) * blood;
	b *= smoothstep(0.21, 0.12, lpos.y);
	ALBEDO = mix(steel, vec3(0.16, 0.01, 0.012), b);
	METALLIC = mix(1.0, 0.0, b);
	ROUGHNESS = mix(0.18 + 0.12 * brush, 0.35, b);
	SPECULAR = 0.6;
}
