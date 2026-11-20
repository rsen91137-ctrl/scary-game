shader_type spatial;

// The white cane: black rubber grip at the top, scuffed white shaft, a red
// band near the tip, a dark tip. UV.y runs along the cane (0 = top on a
// CylinderMesh).

void fragment() {
	float y = UV.y;
	vec3 col = vec3(0.78, 0.77, 0.74);
	float rough = 0.45;
	if (y < 0.2) {
		col = vec3(0.03, 0.03, 0.03);
		rough = 0.8;
	} else if (y > 0.78 && y < 0.95) {
		col = vec3(0.5, 0.04, 0.03);
		rough = 0.5;
	} else if (y >= 0.97) {
		col = vec3(0.05, 0.05, 0.05);
	}
	float scuff = fract(sin(dot(floor(UV * vec2(8.0, 220.0)), vec2(12.9898, 78.233))) * 43758.5453);
	col *= 0.9 + 0.1 * scuff;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
