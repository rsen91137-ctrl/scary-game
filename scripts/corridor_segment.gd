class_name CorridorSegment
extends Node3D
## Two bays of the endless corridor (SEG_LEN = 6.4 m, from local z = 0 down to
## z = -SEG_LEN). Everything that can vary is regenerated from a seed in
## configure(): the same seed always rebuilds the identical stretch, which is
## how the corridor "repeats" (déjà vu) — a new seed gives a new random stretch.

var b: CorridorBuilder
var seed_value := 0
var lamp: Node3D
var _mm := {}                  # key -> MultiMesh
var _tree_slot: Node3D
var _prop_slot: Node3D
var _shore_light: OmniLight3D

const MAX := {
	"block": 12, "base": 4, "core": 4, "post": 4, "tbeam": 2, "lbeam": 8, "rafter": 20,
	"seat": 4, "support": 8, "rail_lo": 4, "rail_hi": 4, "slat": 96,
	"twig": 200, "strand": 170, "shrub": 34,
	"fs_post": 4, "fs_rail": 4, "fs_diag": 8, "fs_light": 4,
}
const MATS := {
	"block": "stone", "base": "granite", "core": "core", "post": "wood", "tbeam": "wood", "lbeam": "wood",
	"rafter": "wood", "seat": "bench", "support": "granite", "rail_lo": "bench", "rail_hi": "bench",
	"slat": "bench", "twig": "twig", "strand": "strand", "shrub": "leaves",
	"fs_post": "railing", "fs_rail": "railing", "fs_diag": "railing", "fs_light": "warm_emit",
}
const NO_SHADOW := ["core", "fs_post", "fs_rail", "fs_diag", "fs_light"]


func setup(builder: CorridorBuilder) -> void:
	b = builder
	for key: String in MAX:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = b.meshes[key]
		mm.instance_count = MAX[key]
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = b.mat(MATS[key])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key in NO_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mm[key] = mm
	# plain static pieces of this stretch
	var L := CorridorBuilder.SEG_LEN
	_static(b.meshes["floor"], "floor", Vector3(0, -0.15, -L * 0.5), false)
	_static(b.meshes["wall"], "dark_stone", Vector3(-2.12, -0.5, -L * 0.5), false)
	_static(b.meshes["curb"], "granite", Vector3(-2.1, 0.0, -L * 0.5), false)
	_static(b.meshes["ground"], "ground", Vector3(1.95 + 30.0, -0.16, -L * 0.5), false)
	_static(b.meshes["fs_bank"], "dark_stone", Vector3(CorridorBuilder.SHORE_X - 2.0, -0.3, -L * 0.5), false)
	_static(b.meshes["fs_path"], "granite", Vector3(CorridorBuilder.SHORE_X - 1.4, 0.22, -L * 0.5), false)
	_shore_light = OmniLight3D.new()
	_shore_light.position = Vector3(CorridorBuilder.SHORE_X + 0.4, 0.6, -L * 0.5)
	_shore_light.light_color = Color(1.0, 0.6, 0.3)
	_shore_light.light_energy = 2.0
	_shore_light.omni_range = 7.0
	_shore_light.light_volumetric_fog_energy = 0.6
	_shore_light.shadow_enabled = false
	add_child(_shore_light)
	_tree_slot = Node3D.new()
	add_child(_tree_slot)
	_prop_slot = Node3D.new()
	add_child(_prop_slot)
	lamp = b.lamp_script.new()
	lamp.set("pendant", true)
	add_child(lamp)


func _static(mesh: Mesh, mat_key: String, pos: Vector3, shadow: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = b.mat(mat_key)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func configure(new_seed: int) -> void:
	seed_value = new_seed
	var r := RandomNumberGenerator.new()
	r.seed = new_seed
	var lists := {}
	for key: String in MAX:
		lists[key] = []
	var L := CorridorBuilder.SEG_LEN
	# ---- pillars + beams for the two pillar rows of this stretch
	for row in 2:
		var z := -float(row) * CorridorBuilder.BAY
		for sx: float in [-1.0, 1.0]:
			var x := sx * CorridorBuilder.PX
			lists["base"].append([Transform3D(Basis(Vector3.UP, r.randf_range(-0.004, 0.004)), Vector3(x, CorridorBuilder.BASE_H * 0.5, z)), Color()])
			lists["core"].append([Transform3D(Basis(), Vector3(x, (CorridorBuilder.BASE_H + CorridorBuilder.STONE_TOP) * 0.5, z)), Color()])
			for k in 3:
				var y := CorridorBuilder.BASE_H + float(k) * (CorridorBuilder.BLOCK_H + CorridorBuilder.GAP) + CorridorBuilder.BLOCK_H * 0.5
				var cu := Color(r.randi_range(0, 31), r.randi_range(0, 31), r.randi_range(0, 31), r.randi_range(0, 31))
				lists["block"].append([Transform3D(Basis(Vector3.UP, r.randf_range(-0.006, 0.006)), Vector3(x + r.randf_range(-0.003, 0.003), y, z + r.randf_range(-0.003, 0.003))), cu])
			lists["post"].append([Transform3D(Basis(), Vector3(x, (CorridorBuilder.STONE_TOP + CorridorBuilder.BEAM_Y) * 0.5, z)), Color(r.randf(), r.randf(), 0, 0)])
		lists["tbeam"].append([Transform3D(Basis(Vector3.FORWARD, r.randf_range(-0.004, 0.004)), Vector3(0, CorridorBuilder.BEAM_Y + 0.14, z)), Color(r.randf(), r.randf(), 0, 0)])
	for bay in 2:
		var zc := -float(bay) * CorridorBuilder.BAY - CorridorBuilder.BAY * 0.5
		for x: float in [-CorridorBuilder.PX, CorridorBuilder.PX, -2.12, 2.12]:
			lists["lbeam"].append([Transform3D(Basis(), Vector3(x, CorridorBuilder.BEAM_Y + 0.28 + 0.125, zc)), Color(r.randf(), r.randf(), 0, 0)])
	var zr := -0.2
	while zr > -L and lists["rafter"].size() < MAX["rafter"]:
		lists["rafter"].append([Transform3D(Basis(Vector3.UP, r.randf_range(-0.012, 0.012)), Vector3(r.randf_range(-0.05, 0.05), CorridorBuilder.BEAM_Y + 0.28 + 0.25 + 0.06, zr)), Color(r.randf(), r.randf(), 0, 0)])
		zr -= r.randf_range(0.36, 0.44)
	# ---- benches ("美人靠")
	var lb := CorridorBuilder.BAY - CorridorBuilder.PW - 0.06
	for bay in 2:
		var zc := -float(bay) * CorridorBuilder.BAY - CorridorBuilder.BAY * 0.5
		for sx: float in [-1.0, 1.0]:
			var flip := Basis(Vector3.UP, PI) if sx < 0.0 else Basis()
			lists["seat"].append([Transform3D(Basis(), Vector3(sx * 1.43, 0.4225, zc)), Color()])
			for k: float in [-0.3, 0.3]:
				lists["support"].append([Transform3D(Basis(), Vector3(sx * 1.43, 0.1975, zc + k * lb)), Color()])
			lists["rail_lo"].append([Transform3D(Basis(), Vector3(sx * 1.625, 0.485, zc)), Color()])
			lists["rail_hi"].append([Transform3D(Basis(Vector3.FORWARD, sx * -0.35), Vector3(sx * (1.625 + 0.235), 0.99, zc)), Color()])
			var n := int(lb / 0.118)
			var start := zc - lb * 0.5 + (lb - float(n - 1) * 0.118) * 0.5
			var missing := r.randi_range(-1, n - 1) if r.randf() < 0.25 else -2   # sometimes a slat is gone
			for s in n:
				if s == missing or s == missing + 1:
					continue
				var bb := flip * Basis(Vector3.UP, r.randf_range(-0.02, 0.02))
				lists["slat"].append([Transform3D(bb, Vector3(sx * 1.625, 0.5, start + float(s) * 0.118)), Color()])
	# ---- dead vines
	var y_top := CorridorBuilder.BEAM_Y + 0.28 + 0.25 + 0.12
	var density := r.randf_range(0.5, 1.0)
	for bay in 2:
		var z0 := -float(bay) * CorridorBuilder.BAY
		for k in int(95 * density):
			var p := Vector3(r.randf_range(-2.4, 2.4), y_top + r.randf_range(0.0, 0.12), z0 - r.randf() * CorridorBuilder.BAY)
			var tb := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + r.randf_range(-0.4, 0.4))
			lists["twig"].append([Transform3D(tb * Basis.from_scale(Vector3(1.0, r.randf_range(0.3, 1.1), 1.0)), p), Color(r.randf(), 0, 0, 0)])
		for k in int(80 * density):
			var p := Vector3(r.randf_range(-2.2, 2.2), CorridorBuilder.BEAM_Y + 0.53, z0 - r.randf() * CorridorBuilder.BAY)
			var l := r.randf_range(0.08, 0.55)
			if r.randf() < 0.12:
				l = r.randf_range(0.6, 1.1)
			if absf(p.x) < 0.6:
				l = minf(l, 0.75)
			var sb := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, r.randf_range(-0.25, 0.25))
			lists["strand"].append([Transform3D(sb * Basis.from_scale(Vector3(1.0, l, 1.0)), p), Color(r.randf(), 0, 0, 0)])
	# ---- shrubs on the right
	for k in r.randi_range(16, MAX["shrub"]):
		var p := Vector3(r.randf_range(2.1, 6.5), r.randf_range(0.15, 1.1), -r.randf() * L)
		var hb := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, r.randf_range(-0.6, 0.6))
		lists["shrub"].append([Transform3D(hb.scaled(Vector3.ONE * r.randf_range(0.7, 1.5)), p), Color()])
	# ---- far shore railing and its lamps (some dead)
	var sxs := CorridorBuilder.SHORE_X
	for k in 4:
		var z := -float(k) * 1.6
		lists["fs_post"].append([Transform3D(Basis(), Vector3(sxs, 0.75, z)), Color()])
		lists["fs_rail"].append([Transform3D(Basis(), Vector3(sxs, 1.25, z - 0.8)), Color()])
		lists["fs_diag"].append([Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(sxs, 0.75, z - 0.8)), Color()])
		lists["fs_diag"].append([Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(sxs, 0.75, z - 0.8)), Color()])
		if r.randf() < 0.7:
			lists["fs_light"].append([Transform3D(Basis(), Vector3(sxs + 0.12, 0.32, z - 0.8)), Color()])
	_shore_light.visible = lists["fs_light"].size() >= 2
	for key: String in lists:
		var mm: MultiMesh = _mm[key]
		var arr: Array = lists[key]
		var cnt := mini(arr.size(), MAX[key])
		for i in cnt:
			mm.set_instance_transform(i, arr[i][0])
			mm.set_instance_custom_data(i, arr[i][1])
		mm.visible_instance_count = cnt

	# ---- a failing lamp over one of the two beams (or none)
	var lamp_roll := r.randf()
	var has_lamp := lamp_roll < 0.45
	var modes := ["steady", "flicker", "flicker", "dying", "dying", "dead"]
	var mode: String = modes[r.randi() % modes.size()]
	lamp.position = Vector3(0.0, CorridorBuilder.BEAM_Y, -CorridorBuilder.BAY * float(r.randi() % 2))
	lamp.call("configure", has_lamp, mode, new_seed)

	# ---- a banyan with aerial roots behind the shrubs (some stretches)
	for c in _tree_slot.get_children():
		c.queue_free()
	if r.randf() < 0.4 and not b.banyans.is_empty():
		var t: Node3D = b.banyans[r.randi() % b.banyans.size()].duplicate()
		t.visible = true
		t.position = Vector3(r.randf_range(4.8, 7.4), -0.05, -r.randf_range(0.8, L - 0.8))
		t.rotation.y = r.randf() * TAU
		_tree_slot.add_child(t)

	# ---- something left behind
	for c in _prop_slot.get_children():
		c.queue_free()
	if r.randf() < 0.16 and not b.props.is_empty():
		var keys: Array = b.props.keys()
		var key: String = keys[r.randi() % keys.size()]
		var pr: Node3D = (b.props[key] as Node3D).duplicate()
		pr.visible = true
		var side := -1.0 if r.randf() < 0.5 else 1.0
		var bay_z := -CorridorBuilder.BAY * (0.5 + float(r.randi() % 2)) + r.randf_range(-0.8, 0.8)
		match key:
			"umbrella":
				pr.position = Vector3(side * 1.36, 0.0, bay_z)
				pr.rotation = Vector3(0.0, r.randf() * TAU, side * deg_to_rad(16.0))
			"shoe":
				pr.position = Vector3(r.randf_range(-0.7, 0.7), 0.0, bay_z)
				pr.rotation.y = r.randf() * TAU
			_:
				pr.position = Vector3(side * 1.43, 0.452, bay_z)
				pr.rotation.y = r.randf_range(-0.4, 0.4)
		_prop_slot.add_child(pr)
