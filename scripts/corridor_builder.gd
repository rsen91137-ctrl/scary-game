class_name CorridorBuilder
extends Node3D
## The endless lakeside corridor, rebuilt from the reference photos:
## sandstone-clad pillars on granite plinths, timber beams/rafters with dead
## vines, "美人靠" goose-neck benches, wet paving, the lake with a lit railing on
## the far shore, distant buildings, banyan trees with aerial roots.
##
## The corridor is a treadmill of N_SEG CorridorSegment stretches. When a
## stretch falls behind the walker it is moved to the front and re-generated
## from a seed chosen by `seed_policy` — the same seed rebuilds an identical
## stretch (the corridor repeats itself), a new seed gives a new random one.

const BAYS_PER_SEG := 2
const BAY := 3.2
const SEG_LEN := BAY * BAYS_PER_SEG
const N_SEG := 14
const PX := 1.62                  # pillar centre, |x|
const PW := 0.46                  # sandstone width
const BASE_H := 0.42              # granite plinth height
const BLOCK_H := 0.58
const GAP := 0.007
const STONE_TOP := BASE_H + 3.0 * (BLOCK_H + GAP)
const POST_W := 0.3
const BEAM_Y := 2.48              # underside of the transverse beams
const SHORE_X := -34.0
const END_LIGHT_AHEAD := 62.0     # the light you never reach

var segments: Array[CorridorSegment] = []
var lamps: Array[Node3D] = []     # every lamp (segment lamps + the far light)
var end_lamp: Node3D
var meshes := {}
var banyans: Array[Node3D] = []   # templates, duplicated into segments
var props := {}                   # templates: umbrella, shoe, phone
var lamp_script: Script
var seed_policy: Callable         # func(seg: CorridorSegment) -> int
var front_z := 0.0

var _mats := {}
var _rng := RandomNumberGenerator.new()
var _lake: MeshInstance3D
var _cards: Array[MeshInstance3D] = []
var _buildings: Array[MeshInstance3D] = []


func build(start_z: float) -> void:
	_rng.seed = 20261119
	lamp_script = load("res://scripts/flicker_lamp.gd")
	_make_materials()
	_make_meshes()
	_make_banyans()
	_make_props()
	_make_backdrop()
	var z := start_z + SEG_LEN * 1.5
	for i in N_SEG:
		var seg := CorridorSegment.new()
		seg.name = "Seg%02d" % i
		add_child(seg)
		seg.setup(self)
		seg.position.z = z
		seg.configure(_next_seed(seg))
		segments.append(seg)
		lamps.append(seg.lamp)
		z -= SEG_LEN
	front_z = z
	end_lamp = lamp_script.new()
	end_lamp.name = "FarLight"
	end_lamp.set("mode", "end")
	end_lamp.set("pendant", false)
	end_lamp.set("seed_value", 4242)
	end_lamp.position = Vector3(0.0, 2.15, start_z - END_LIGHT_AHEAD)
	add_child(end_lamp)
	lamps.append(end_lamp)


func _next_seed(seg: CorridorSegment) -> int:
	if seed_policy.is_valid():
		return seed_policy.call(seg)
	return _rng.randi()


## Keep the treadmill running around the walker's z.
func update_stream(walker_z: float) -> void:
	for seg in segments:
		if seg.position.z - SEG_LEN > walker_z + SEG_LEN * 0.6:
			seg.position.z = front_z
			front_z -= SEG_LEN
			seg.configure(_next_seed(seg))
	# backdrop follows (world-space shaders keep it seamless)
	_lake.position.z = walker_z - 60.0
	for c in _cards:
		c.position.z = walker_z + float(c.get_meta("dz"))
	for bmi in _buildings:
		if bmi.position.z > walker_z + 160.0:
			bmi.position.z -= 520.0
			bmi.scale = Vector3(1.0, _rng.randf_range(0.8, 1.25), _rng.randf_range(0.7, 1.3))
	end_lamp.position.z = walker_z - END_LIGHT_AHEAD


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------
func _tex(name: String) -> Texture2D:
	return load("res://assets/textures/%s.png" % name)


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _noise_tex(size: int, freq: float, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 5
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t


func mat(key: String) -> Material:
	return _mats[key]


func _make_materials() -> void:
	var stone := _shader_mat("res://shaders/stone_atlas.gdshader")
	stone.set_shader_parameter("albedo_atlas", _tex("sandstone_albedo"))
	stone.set_shader_parameter("normal_atlas", _tex("sandstone_normal"))
	stone.set_shader_parameter("rough_atlas", _tex("sandstone_rough"))
	stone.set_shader_parameter("tint", Color(0.92, 0.9, 0.86))
	_mats["stone"] = stone

	var wood := _shader_mat("res://shaders/wood_strip.gdshader")
	wood.set_shader_parameter("albedo_tex", _tex("beam_albedo"))
	wood.set_shader_parameter("normal_tex", _tex("beam_normal"))
	wood.set_shader_parameter("tint", Color(0.78, 0.74, 0.7))
	_mats["wood"] = wood

	var granite := StandardMaterial3D.new()
	granite.albedo_texture = _tex("granite_albedo")
	granite.normal_enabled = true
	granite.normal_texture = _tex("granite_normal")
	granite.roughness = 0.72
	granite.uv1_scale = Vector3(2.0, 2.0, 1.0)
	granite.albedo_color = Color(0.86, 0.85, 0.83)
	granite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats["granite"] = granite

	var bench := StandardMaterial3D.new()
	bench.albedo_texture = _tex("benchwood_albedo")
	bench.normal_enabled = true
	bench.normal_texture = _tex("benchwood_normal")
	bench.normal_scale = 0.6
	bench.roughness_texture = _tex("benchwood_rough")
	bench.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	bench.uv1_scale = Vector3(0.55, 2.2, 1.0)
	bench.albedo_color = Color(0.8, 0.78, 0.76)
	bench.cull_mode = BaseMaterial3D.CULL_DISABLED
	bench.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats["bench"] = bench

	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.06, 0.055, 0.05)
	core.roughness = 1.0
	_mats["core"] = core

	var floor_m := _shader_mat("res://shaders/floor.gdshader")
	floor_m.set_shader_parameter("stone_albedo", _tex("floor_albedo"))
	floor_m.set_shader_parameter("stone_normal", _tex("floor_normal"))
	floor_m.set_shader_parameter("stone_rough", _tex("floor_rough"))
	floor_m.set_shader_parameter("granite_albedo", _tex("granite_albedo"))
	floor_m.set_shader_parameter("noise_tex", _noise_tex(512, 0.008, 3))
	floor_m.set_shader_parameter("bay", BAY)
	_mats["floor"] = floor_m

	var strand := _shader_mat("res://shaders/strand.gdshader")
	strand.set_shader_parameter("color", Color(0.5, 0.45, 0.36))
	strand.set_shader_parameter("sway", 0.07)
	_mats["strand"] = strand

	var twig := _shader_mat("res://shaders/strand.gdshader")
	twig.set_shader_parameter("color", Color(0.33, 0.29, 0.23))
	twig.set_shader_parameter("sway", 0.0)
	_mats["twig"] = twig

	var bark := StandardMaterial3D.new()
	bark.albedo_texture = _tex("bark_albedo")
	bark.normal_enabled = true
	bark.normal_texture = _tex("bark_normal")
	bark.normal_scale = 1.3
	bark.roughness = 0.92
	bark.uv1_scale = Vector3(1.0, 0.7, 1.0)
	bark.albedo_color = Color(0.72, 0.7, 0.66)
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats["bark"] = bark

	var root_m := _shader_mat("res://shaders/strand.gdshader")
	root_m.set_shader_parameter("color", Color(0.3, 0.27, 0.23))
	root_m.set_shader_parameter("sway", 0.025)
	root_m.set_shader_parameter("speed", 0.6)
	_mats["root"] = root_m

	var leaves := _shader_mat("res://shaders/foliage.gdshader")
	leaves.set_shader_parameter("albedo_tex", _tex("leaves_albedo"))
	leaves.set_shader_parameter("tint", Color(0.55, 0.62, 0.5))
	_mats["leaves"] = leaves

	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.045, 0.05, 0.04)
	ground.albedo_texture = _tex("floor_albedo")
	ground.normal_enabled = true
	ground.normal_texture = _tex("bark_normal")
	ground.normal_scale = 0.8
	ground.roughness = 0.97
	ground.uv1_triplanar = true
	ground.uv1_world_triplanar = true
	ground.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mats["ground"] = ground

	var railing := StandardMaterial3D.new()
	railing.albedo_color = Color(0.16, 0.08, 0.05)
	railing.roughness = 0.6
	_mats["railing"] = railing

	var dark_stone := StandardMaterial3D.new()
	dark_stone.albedo_texture = _tex("granite_albedo")
	dark_stone.albedo_color = Color(0.3, 0.3, 0.3)
	dark_stone.roughness = 0.85
	dark_stone.uv1_triplanar = true
	dark_stone.uv1_world_triplanar = true
	dark_stone.uv1_scale = Vector3(0.8, 0.8, 0.8)
	_mats["dark_stone"] = dark_stone

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.05, 0.05, 0.05)
	metal.metallic = 0.6
	metal.roughness = 0.45
	_mats["metal"] = metal

	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.1, 0.06, 0.03)
	warm.emission_enabled = true
	warm.emission = Color(1.0, 0.56, 0.24)
	warm.emission_energy_multiplier = 7.0
	_mats["warm_emit"] = warm

	_mats["building"] = _shader_mat("res://shaders/building.gdshader")


# ---------------------------------------------------------------------------
# shared meshes
# ---------------------------------------------------------------------------
func _slat_mesh() -> ArrayMesh:
	# goose-neck back slat: rises from the seat back, then flares outwards (+x)
	var pts := PackedVector3Array()
	var p0 := Vector2(0, 0)
	var p1 := Vector2(-0.035, 0.17)
	var p2 := Vector2(0.09, 0.34)
	var p3 := Vector2(0.235, 0.47)
	for i in 13:
		var t := float(i) / 12.0
		var u := 1.0 - t
		var p := p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t
		pts.append(Vector3(p.x, p.y, 0))
	return MeshUtil.swept_rect(pts, 0.046, 0.022, Vector3.BACK)


func _make_meshes() -> void:
	var lb := BAY - PW - 0.06
	meshes = {
		"block": MeshUtil.box(Vector3(PW, BLOCK_H, PW), true),
		"base": MeshUtil.box(Vector3(0.52, BASE_H, 0.52)),
		"core": MeshUtil.box(Vector3(PW - 0.03, STONE_TOP - BASE_H, PW - 0.03)),
		"post": MeshUtil.box(Vector3(POST_W, BEAM_Y - STONE_TOP + 0.01, POST_W)),
		"tbeam": MeshUtil.box(Vector3(4.6, 0.28, 0.17)),
		"lbeam": MeshUtil.box(Vector3(0.16, 0.25, BAY + 0.03)),
		"rafter": MeshUtil.box(Vector3(4.9, 0.12, 0.07)),
		"seat": MeshUtil.box(Vector3(0.4, 0.055, lb)),
		"support": MeshUtil.box(Vector3(0.3, 0.395, 0.13)),
		"rail_lo": MeshUtil.box(Vector3(0.05, 0.075, lb)),
		"rail_hi": MeshUtil.box(Vector3(0.08, 0.055, lb + 0.02)),
		"slat": _slat_mesh(),
		"twig": MeshUtil.strand(3, 0.004),
		"strand": MeshUtil.strand(5, 0.0028),
		"shrub": MeshUtil.quad(0.9, 0.9),
		"floor": MeshUtil.box(Vector3(3.9, 0.3, SEG_LEN + 0.002)),
		"wall": MeshUtil.box(Vector3(0.35, 1.0, SEG_LEN + 0.002)),
		"curb": MeshUtil.box(Vector3(0.3, 0.06, SEG_LEN + 0.002)),
		"ground": MeshUtil.box(Vector3(60.0, 0.2, SEG_LEN + 0.002)),
		"fs_bank": MeshUtil.box(Vector3(5.0, 1.0, SEG_LEN + 0.002)),
		"fs_path": MeshUtil.box(Vector3(3.0, 0.1, SEG_LEN + 0.002)),
		"fs_post": MeshUtil.box(Vector3(0.1, 1.05, 0.1)),
		"fs_rail": MeshUtil.box(Vector3(0.08, 0.06, 1.6)),
		"fs_diag": MeshUtil.box(Vector3(0.03, 0.03, 1.4)),
		"fs_light": MeshUtil.box(Vector3(0.14, 0.08, 0.1)),
	}


# ---------------------------------------------------------------------------
# banyan templates (duplicated into segments)
# ---------------------------------------------------------------------------
func _make_banyans() -> void:
	for i in 3:
		var t := _build_banyan(9100 + i * 17)
		t.visible = false
		add_child(t)
		banyans.append(t)


func _build_banyan(seed_v: int) -> Node3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var tree := Node3D.new()
	tree.name = "Banyan"
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var lean := Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))
	var h := r.randf_range(4.5, 6.0)
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector3(0, t * h, 0) + lean * t * t + Vector3(sin(t * 5.0 + seed_v) * 0.12, 0, cos(t * 4.0 + seed_v) * 0.1))
		radii.append(lerpf(0.62, 0.32, t) * (1.25 if i == 0 else 1.0))
	var trunk := MeshInstance3D.new()
	trunk.mesh = MeshUtil.tube(pts, radii, 14, 3.0, 0.18, seed_v)
	trunk.material_override = _mats["bark"]
	tree.add_child(trunk)
	var leaf := MeshUtil.quad(1.6, 1.6)
	var root_mesh := MeshUtil.strand(6, 0.0025)
	var leaf_xf: Array[Transform3D] = []
	var root_xf: Array[Transform3D] = []
	var n_br := r.randi_range(4, 6)
	for bi in n_br:
		var ang := TAU * float(bi) / float(n_br) + r.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(ang), r.randf_range(0.25, 0.7), sin(ang)).normalized()
		var start := pts[r.randi_range(5, 7)]
		var blen := r.randf_range(3.0, 5.5)
		var bp := PackedVector3Array()
		var br := PackedFloat32Array()
		for i in 7:
			var t := float(i) / 6.0
			bp.append(start + dir * blen * t + Vector3(0, -0.6 * t * t + 0.4 * t, 0))
			br.append(lerpf(0.24, 0.06, t))
		var bmi := MeshInstance3D.new()
		bmi.mesh = MeshUtil.tube(bp, br, 8, 2.0, 0.12, seed_v + bi)
		bmi.material_override = _mats["bark"]
		tree.add_child(bmi)
		for k in 70:
			var t := r.randf_range(0.3, 1.0)
			var c := bp[int(t * 6.0)] + Vector3(r.randf_range(-1.6, 1.6), r.randf_range(-0.2, 1.8), r.randf_range(-1.6, 1.6))
			var lbs := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, r.randf_range(-1.2, 1.2))
			leaf_xf.append(Transform3D(lbs.scaled(Vector3.ONE * r.randf_range(0.8, 1.6)), c))
		for k in r.randi_range(10, 18):
			var t := r.randf_range(0.15, 0.95)
			var a := bp[int(t * 6.0)]
			var l := a.y * (1.0 if r.randf() < 0.45 else r.randf_range(0.25, 0.85))
			var rb := Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3(r.randf_range(3.0, 10.0), l, r.randf_range(3.0, 10.0)))
			root_xf.append(Transform3D(rb, a + Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))))
	for k in 40:
		var ang := r.randf() * TAU
		var rad := r.randf_range(0.5, 1.3)
		var top := r.randf_range(2.5, h)
		var rb := Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3(r.randf_range(3.0, 9.0), top + 0.05, r.randf_range(3.0, 9.0)))
		root_xf.append(Transform3D(rb, Vector3(cos(ang) * rad, top, sin(ang) * rad)))
	tree.add_child(_mm_node(leaf, _mats["leaves"], leaf_xf, true))
	tree.add_child(_mm_node(root_mesh, _mats["root"], root_xf, true))
	# eerie green uplight from the ground, as in the park in the photos
	var spot := SpotLight3D.new()
	var sp := Vector3(r.randf_range(-1.8, -1.2), 0.15, r.randf_range(-0.6, 0.6))
	spot.light_color = Color(0.72, 1.0, 0.78)
	spot.light_energy = 6.0
	spot.spot_range = 11.0
	spot.spot_angle = 38.0
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 0.7
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 35.0
	spot.distance_fade_shadow = 20.0
	spot.distance_fade_length = 10.0
	spot.transform = Transform3D(Basis.looking_at(Vector3(0, 4.5, 0) - sp, Vector3.RIGHT), sp)
	tree.add_child(spot)
	var fx := MeshInstance3D.new()
	fx.mesh = MeshUtil.box(Vector3(0.22, 0.12, 0.22))
	fx.material_override = _mats["metal"]
	fx.position = sp + Vector3(0, -0.08, 0)
	tree.add_child(fx)
	return tree


func _mm_node(mesh: Mesh, m: Material, xfs: Array[Transform3D], shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# ---------------------------------------------------------------------------
# things left behind in the corridor
# ---------------------------------------------------------------------------
func _part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _make_props() -> void:
	# a closed red umbrella leaning on a bench
	var umb := Node3D.new()
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.42, 0.03, 0.03)
	cloth.roughness = 0.55
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.008
	shaft.bottom_radius = 0.008
	shaft.height = 0.95
	_part(umb, shaft, _mats["metal"], Vector3(0, 0.475, 0))
	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.012
	canopy.bottom_radius = 0.05
	canopy.height = 0.62
	_part(umb, canopy, cloth, Vector3(0, 0.5, 0))
	var handle := CylinderMesh.new()
	handle.top_radius = 0.016
	handle.bottom_radius = 0.016
	handle.height = 0.12
	_part(umb, handle, _mats["metal"], Vector3(0, 0.98, 0))
	props["umbrella"] = umb
	# a single child's shoe on the paving
	var shoe := Node3D.new()
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.5, 0.06, 0.08)
	leather.roughness = 0.4
	_part(shoe, MeshUtil.box(Vector3(0.075, 0.02, 0.17)), _mats["core"], Vector3(0, 0.01, 0))
	_part(shoe, MeshUtil.box(Vector3(0.07, 0.05, 0.12)), leather, Vector3(0, 0.045, 0.02))
	props["shoe"] = shoe
	# a phone lying face up on a bench, its screen still lit
	var phone := Node3D.new()
	_part(phone, MeshUtil.box(Vector3(0.075, 0.009, 0.155)), _mats["metal"], Vector3(0, 0.0045, 0))
	var screen_m := StandardMaterial3D.new()
	screen_m.albedo_color = Color(0, 0, 0)
	screen_m.emission_enabled = true
	screen_m.emission = Color(0.72, 0.82, 1.0)
	screen_m.emission_energy_multiplier = 2.5
	_part(phone, MeshUtil.box(Vector3(0.066, 0.001, 0.142)), screen_m, Vector3(0, 0.0095, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.72, 0.82, 1.0)
	glow.light_energy = 0.35
	glow.omni_range = 0.9
	glow.position = Vector3(0, 0.06, 0)
	phone.add_child(glow)
	props["phone"] = phone
	for k: String in props:
		var n: Node3D = props[k]
		n.visible = false
		add_child(n)


# ---------------------------------------------------------------------------
# backdrop that travels with the walker
# ---------------------------------------------------------------------------
func _make_backdrop() -> void:
	var water := _shader_mat("res://shaders/water.gdshader")
	water.set_shader_parameter("normal_tex", _tex("water_normal"))
	var wm := PlaneMesh.new()
	wm.size = Vector2(240.0, 320.0)
	_lake = MeshInstance3D.new()
	_lake.mesh = wm
	_lake.material_override = water
	_lake.position = Vector3(-2.2 - 120.0, -0.42, 0.0)
	_lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lake)
	_card("treeline", SHORE_X - 5.0, 7.5, true, 110.0)
	_card("treeline_far", SHORE_X - 22.0, 11.0, true, 140.0)
	_card("treeline", 22.0, 10.0, false, 95.0)
	for i in 4:
		var bmi := MeshInstance3D.new()
		bmi.mesh = MeshUtil.box(Vector3(30.0, 30.0, 90.0))
		bmi.material_override = _mats["building"]
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bmi.position = Vector3(-118.0 - _rng.randf_range(0.0, 30.0), 13.0, 40.0 - float(i) * 130.0)
		bmi.scale = Vector3(1.0, _rng.randf_range(0.8, 1.25), _rng.randf_range(0.7, 1.3))
		add_child(bmi)
		_buildings.append(bmi)


func _card(tex_name: String, x: float, height: float, faces_right: bool, period: float) -> void:
	var m := _shader_mat("res://shaders/treeline.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(tex_name))
	m.set_shader_parameter("period", period)
	var qm := QuadMesh.new()
	qm.size = Vector2(360.0, height)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, height * 0.5 - 0.2, 0.0)
	mi.rotation = Vector3(0.0, PI * 0.5 if faces_right else -PI * 0.5, 0.0)
	mi.set_meta("dz", -60.0)
	add_child(mi)
	_cards.append(mi)
