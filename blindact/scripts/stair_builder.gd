class_name StairBuilder
extends Node3D
## The stairwell of a decaying block of flats: switchback flights, a half
## landing with a barred window, floor landings with two doors each. Three
## identical floors are built; the menu walker climbs from floor 0 to 1 and is
## moved back down, while the floors' dressing is shuffled (configure(seed)),
## so the climb never ends and never quite repeats.

const H := 2.9           # floor to floor
const W := 1.3           # half width of the shaft
const GAP := 0.09        # half width of the well between the flights
const Z0 := -1.75        # near wall (behind the floor landing)
const ZL := 1.25         # first riser of flight A
const NRISE := 9
const RUN := 0.28
const ZH := ZL + (NRISE - 1) * RUN   # half landing edge
const Z1 := ZH + 1.25    # far wall
const SLAB := 0.17
const WALL_T := 0.2

var floors: Array[Node3D] = []
var lights: Array[SensorLight] = []        # [floor0 landing, floor0 half, floor1 ...]
var moon: SpotLight3D
var window_mat: ShaderMaterial
var _mats := {}
var _decal_tex := {}
var _floor_numbers := ["3", "4", "5"]


func rise() -> float:
	return H * 0.5 / NRISE


func build() -> void:
	_make_materials()
	for k in 3:
		var f := Node3D.new()
		f.name = "Floor%d" % k
		f.position.y = k * H
		add_child(f)
		floors.append(f)
		_build_floor(f, k)
	# roof over the top floor
	_box(self, Vector3(2 * W + 2 * WALL_T, 0.3, Z1 - Z0 + 2 * WALL_T), Vector3(0, 3 * H + 0.15, (Z0 + Z1) * 0.5), _mats.concrete)
	# outside the landing windows: one shared night view and the moon
	moon = SpotLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 2.2
	moon.spot_range = 14.0
	moon.spot_angle = 38.0
	moon.spot_attenuation = 0.6
	moon.shadow_enabled = true
	moon.light_volumetric_fog_energy = 2.5
	add_child(moon)
	for k in 3:
		configure(k, 1000 + k)


func place_moon(floor_k: int) -> void:
	## keep the moonlight on the landing the walker is near
	moon.position = Vector3(0.6, floor_k * H + H * 0.5 + 3.2, Z1 + 2.2)
	moon.look_at(Vector3(-0.2, floor_k * H + H * 0.5, ZH + 0.2), Vector3.UP)


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------
func _tex(name: String) -> Texture2D:
	var p := "res://assets/textures/%s.png" % name
	return load(p) if ResourceLoader.exists(p) else null


func _std(prefix: String, uv_scale: float, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(prefix + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(prefix + "_normal")
	m.roughness_texture = _tex(prefix + "_rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _make_materials() -> void:
	_mats.concrete = _std("concrete", 0.5)
	_mats.step = _std("concrete", 0.9, Color(0.9, 0.88, 0.85))
	_mats.rust = _std("rust", 1.5)
	_mats.wood = _std("wood", 1.0)
	_mats.door = _std("paint_green", 0.8, Color(0.75, 0.55, 0.45))
	_mats.door2 = _std("paint_green", 0.8, Color(0.55, 0.6, 0.7))
	var wall := ShaderMaterial.new()
	wall.shader = load("res://shaders/decay_wall.gdshader")
	wall.set_shader_parameter("plaster_albedo", _tex("plaster_albedo"))
	wall.set_shader_parameter("plaster_normal", _tex("plaster_normal"))
	wall.set_shader_parameter("plaster_rough", _tex("plaster_rough"))
	wall.set_shader_parameter("brick_albedo", _tex("brick_albedo"))
	wall.set_shader_parameter("brick_normal", _tex("brick_normal"))
	wall.set_shader_parameter("peel_mask", _tex("peel_mask"))
	wall.set_shader_parameter("floor_h", H)
	_mats.wall = wall
	var pipe_red := StandardMaterial3D.new()
	pipe_red.albedo_color = Color(0.35, 0.08, 0.06)
	pipe_red.roughness = 0.55
	pipe_red.albedo_texture = _tex("rust_albedo")
	_mats.pipe_red = pipe_red
	var pipe_grey := StandardMaterial3D.new()
	pipe_grey.albedo_color = Color(0.3, 0.31, 0.32)
	pipe_grey.roughness = 0.5
	_mats.pipe_grey = pipe_grey
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	_mats.dark = dark
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.55, 0.6, 0.12)
	glass.roughness = 0.08
	glass.metallic_specular = 0.9
	_mats.glass = glass
	window_mat = ShaderMaterial.new()
	window_mat.shader = load("res://shaders/night_window.gdshader")
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.7, 0.68, 0.6)
	paper.roughness = 0.9
	_mats.paper = paper
	var rubble := _std("concrete", 2.0, Color(0.8, 0.78, 0.74))
	_mats.rubble = rubble
	for n: String in ["tag_red", "tag_black", "tag_white", "tag_green", "arrow", "cross", "eye_tag",
			"floor_3", "floor_4", "floor_5", "floor_13", "flyer_piano", "missing", "stain", "stain2",
			"mold", "soot", "handprint"]:
		var t := _tex("decals/" + n)
		if t:
			_decal_tex[n] = t


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# structure (identical on every floor)
# ---------------------------------------------------------------------------
func _build_floor(f: Node3D, k: int) -> void:
	var r := rise()
	var fw := W - GAP                   # flight width
	# floor landing slab and half landing slab
	_box(f, Vector3(2 * W, SLAB, ZL - Z0), Vector3(0, -SLAB * 0.5, (Z0 + ZL) * 0.5), _mats.step)
	_box(f, Vector3(2 * W, SLAB, Z1 - ZH), Vector3(0, H * 0.5 - SLAB * 0.5, (ZH + Z1) * 0.5), _mats.step)
	# flight A (left, rising towards +z) and flight B (right, rising towards -z)
	for i in NRISE - 1:
		var top := (i + 1) * r
		var za := ZL + i * RUN
		_box(f, Vector3(fw, top + 0.02, RUN), Vector3(-GAP - fw * 0.5, top * 0.5 - 0.01, za + RUN * 0.5), _mats.step)
		var zb := ZH - i * RUN
		_box(f, Vector3(fw, top + 0.02, RUN), Vector3(GAP + fw * 0.5, H * 0.5 + top * 0.5 - 0.01, zb - RUN * 0.5), _mats.step)
	# sloped soffits under the flights (seen from the landing below)
	var slope_len := sqrt(pow(ZH - ZL, 2.0) + pow(H * 0.5, 2.0))
	var ang := atan2(H * 0.5, ZH - ZL)
	var sa := _box(f, Vector3(fw, SLAB, slope_len), Vector3(-GAP - fw * 0.5, H * 0.25 - 0.16, (ZL + ZH) * 0.5), _mats.concrete)
	sa.rotation.x = -ang
	var sb := _box(f, Vector3(fw, SLAB, slope_len), Vector3(GAP + fw * 0.5, H * 0.75 - 0.16, (ZL + ZH) * 0.5), _mats.concrete)
	sb.rotation.x = ang
	# walls (the far wall has the window opening at the half landing)
	var hz := Z1 - Z0 + 2 * WALL_T
	var zc := (Z0 + Z1) * 0.5
	var wl := _box(f, Vector3(WALL_T, H, hz), Vector3(-W - WALL_T * 0.5, H * 0.5, zc), _mats.wall)
	wl.set_meta("wall", true)
	_box(f, Vector3(WALL_T, H, hz), Vector3(W + WALL_T * 0.5, H * 0.5, zc), _mats.wall)
	_box(f, Vector3(2 * W, H, WALL_T), Vector3(0, H * 0.5, Z0 - WALL_T * 0.5), _mats.wall)
	var wy0 := H * 0.5 + 0.95
	var wy1 := H * 0.5 + 2.1
	var wx := 0.55
	var zf := Z1 + WALL_T * 0.5
	_box(f, Vector3(2 * W, wy0, WALL_T), Vector3(0, wy0 * 0.5, zf), _mats.wall)
	_box(f, Vector3(2 * W, H - wy1, WALL_T), Vector3(0, (wy1 + H) * 0.5, zf), _mats.wall)
	_box(f, Vector3(W - wx, wy1 - wy0, WALL_T), Vector3(-(W + wx) * 0.5, (wy0 + wy1) * 0.5, zf), _mats.wall)
	_box(f, Vector3(W - wx, wy1 - wy0, WALL_T), Vector3((W + wx) * 0.5, (wy0 + wy1) * 0.5, zf), _mats.wall)
	_build_window(f, wx, wy0, wy1, zf)
	# railings along the well, a pipe handrail on the outer walls
	_build_railing(f, -GAP, ZL, ZH, 0.0, H * 0.5)
	_build_railing(f, GAP, ZH, ZL, H * 0.5, H)
	var rail_cross := PackedVector3Array([Vector3(-GAP, H * 0.5 + 0.92, ZH), Vector3(GAP, H * 0.5 + 0.92, ZH)])
	var rc := MeshInstance3D.new()
	rc.mesh = MeshUtil.tube(rail_cross, PackedFloat32Array([0.025, 0.025]), 8)
	rc.material_override = _mats.wood
	f.add_child(rc)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var z_a := ZL - 0.2 if side < 0.0 else ZH + 0.2
		var z_b := ZH + 0.2 if side < 0.0 else ZL - 0.2
		var y_a := 0.88 if side < 0.0 else H * 0.5 + 0.88
		var y_b := H * 0.5 + 0.88 if side < 0.0 else H + 0.88
		pts.append(Vector3(side * (W - 0.06), y_a, z_a))
		pts.append(Vector3(side * (W - 0.06), y_b, z_b))
		var tp := MeshInstance3D.new()
		tp.mesh = MeshUtil.tube(pts, PackedFloat32Array([0.018, 0.018]), 8)
		tp.material_override = _mats.rust
		f.add_child(tp)
	# vertical drain pipe in the far corner, conduits along the left wall
	var dp := MeshInstance3D.new()
	dp.mesh = MeshUtil.tube(PackedVector3Array([Vector3(W - 0.12, 0.0, Z1 - 0.12), Vector3(W - 0.12, H, Z1 - 0.12)]), PackedFloat32Array([0.055, 0.055]), 12)
	dp.material_override = _mats.pipe_grey
	f.add_child(dp)
	for j in 3:
		var cp := MeshInstance3D.new()
		var yy := H - 0.32 - j * 0.07
		cp.mesh = MeshUtil.tube(PackedVector3Array([Vector3(-W + 0.07, yy, Z0), Vector3(-W + 0.07, yy, Z1)]), PackedFloat32Array([0.02, 0.02]), 8)
		cp.material_override = _mats.pipe_red if j == 1 else _mats.pipe_grey
		f.add_child(cp)
	# meter box on the near wall with its wires
	var mb := _box(f, Vector3(0.55, 0.5, 0.14), Vector3(-0.55, 1.75, Z0 + 0.07), _mats.rust)
	mb.name = "MeterBox"
	for j in 4:
		var wv := MeshInstance3D.new()
		var x := -0.7 + j * 0.08
		wv.mesh = MeshUtil.tube(PackedVector3Array([Vector3(x, 2.0, Z0 + 0.06), Vector3(x + 0.05, 2.4, Z0 + 0.05), Vector3(x + 0.1 * j, H - 0.05, Z0 + 0.04)]), PackedFloat32Array([0.008, 0.008, 0.008]), 6)
		wv.material_override = _mats.dark
		f.add_child(wv)
	# doors on the floor landing
	_build_door(f, -1.0, -1.0, "DoorL")
	_build_door(f, 1.0, -1.0, "DoorR")
	# lights: landing and half landing
	var l1 := SensorLight.new()
	l1.position = Vector3(0.1, H - SLAB - 0.32, -0.5)
	f.add_child(l1)
	var l2 := SensorLight.new()
	l2.position = Vector3(-0.35, H - 0.4, ZH + 0.7)
	f.add_child(l2)
	lights.append(l1)
	lights.append(l2)
	# a dressing node rebuilt by configure()
	var dress := Node3D.new()
	dress.name = "Dressing"
	f.add_child(dress)


func _build_window(f: Node3D, wx: float, wy0: float, wy1: float, zf: float) -> void:
	var frame_m: Material = _mats.wood
	var t := 0.06
	_box(f, Vector3(2 * wx, t, 0.12), Vector3(0, wy0 + t * 0.5, zf - 0.02), frame_m)
	_box(f, Vector3(2 * wx, t, 0.12), Vector3(0, wy1 - t * 0.5, zf - 0.02), frame_m)
	_box(f, Vector3(t, wy1 - wy0, 0.12), Vector3(-wx + t * 0.5, (wy0 + wy1) * 0.5, zf - 0.02), frame_m)
	_box(f, Vector3(t, wy1 - wy0, 0.12), Vector3(wx - t * 0.5, (wy0 + wy1) * 0.5, zf - 0.02), frame_m)
	_box(f, Vector3(t * 0.7, wy1 - wy0, 0.1), Vector3(0, (wy0 + wy1) * 0.5, zf - 0.02), frame_m)
	_box(f, Vector3(2 * wx, t * 0.7, 0.1), Vector3(0, wy0 + (wy1 - wy0) * 0.62, zf - 0.02), frame_m)
	# bars
	for i in 6:
		var x := -wx + 0.1 + i * (2 * wx - 0.2) / 5.0
		var bar := MeshInstance3D.new()
		bar.mesh = MeshUtil.tube(PackedVector3Array([Vector3(x, wy0, zf - 0.13), Vector3(x, wy1, zf - 0.13)]), PackedFloat32Array([0.011, 0.011]), 6)
		bar.material_override = _mats.rust
		f.add_child(bar)
	# glass (one pane broken) and the night outside
	var g := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(wx * 2 - 0.1, wy1 - wy0 - 0.1)
	g.mesh = qm
	g.material_override = _mats.glass
	g.position = Vector3(0, (wy0 + wy1) * 0.5, zf - 0.01)
	g.rotation.y = PI
	f.add_child(g)
	var outside := MeshInstance3D.new()
	var om := QuadMesh.new()
	om.size = Vector2(4.0, 3.0)
	outside.mesh = om
	outside.material_override = window_mat
	outside.position = Vector3(0, (wy0 + wy1) * 0.5 + 0.3, zf + 1.2)
	outside.rotation.y = PI
	f.add_child(outside)


func _build_railing(f: Node3D, x: float, z_from: float, z_to: float, y_from: float, y_to: float) -> void:
	var n := 18
	for i in n + 1:
		var k := float(i) / n
		var z := lerpf(z_from, z_to, k)
		var y := lerpf(y_from, y_to, k) + rise() * 0.5
		_box(f, Vector3(0.018, 0.86, 0.018), Vector3(x, y + 0.43, z), _mats.rust)
	var hr := MeshInstance3D.new()
	hr.mesh = MeshUtil.tube(PackedVector3Array([Vector3(x, y_from + 0.95, z_from - 0.1 * signf(z_to - z_from)), Vector3(x, y_to + 0.95, z_to + 0.1 * signf(z_to - z_from))]), PackedFloat32Array([0.028, 0.028]), 10)
	hr.material_override = _mats.wood
	f.add_child(hr)


func _build_door(f: Node3D, side: float, zc: float, name: String) -> void:
	var x := side * (W - 0.02)
	var d := Node3D.new()
	d.name = name
	f.add_child(d)
	# frame
	var fr: Material = _mats.wood
	_box(d, Vector3(0.08, 2.15, 0.08), Vector3(x, 1.075, zc - 0.5), fr)
	_box(d, Vector3(0.08, 2.15, 0.08), Vector3(x, 1.075, zc + 0.5), fr)
	_box(d, Vector3(0.08, 0.08, 1.08), Vector3(x, 2.15, zc), fr)
	# the door leaf, hinged at one edge so it can stand ajar
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(x - side * 0.03, 0.0, zc - 0.46)
	d.add_child(hinge)
	var leaf := _box(hinge, Vector3(0.05, 2.06, 0.92), Vector3(0, 1.03, 0.46), _mats.door if side < 0.0 else _mats.door2)
	leaf.name = "Leaf"
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.03
	km.height = 0.06
	knob.mesh = km
	knob.material_override = _mats.rust
	knob.position = Vector3(-side * 0.05, 1.0, 0.82)
	hinge.add_child(knob)
	var peep := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.012
	pm.bottom_radius = 0.012
	pm.height = 0.02
	peep.mesh = pm
	peep.material_override = _mats.dark
	peep.rotation.z = PI * 0.5
	peep.position = Vector3(-side * 0.03, 1.55, 0.46)
	hinge.add_child(peep)
	# darkness behind (seen when the door is ajar)
	_box(d, Vector3(0.3, 2.06, 0.92), Vector3(x + side * 0.18, 1.03, zc), _mats.dark)


# ---------------------------------------------------------------------------
# dressing (seeded): decay, decals, debris, doors ajar, lights dying
# ---------------------------------------------------------------------------
func configure(k: int, seed: int, number := "") -> void:
	var f := floors[k]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var dress: Node3D = f.get_node("Dressing")
	for c in dress.get_children():
		c.queue_free()
	# walls: a per-floor decay level and texture offset (via a material copy)
	var wm: ShaderMaterial = (_mats.wall as ShaderMaterial).duplicate()
	wm.set_shader_parameter("decay", r.randf_range(0.55, 1.0))
	wm.set_shader_parameter("uv_offset", Vector2(r.randf() * 10.0, r.randf() * 10.0))
	for c in f.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == _mats.wall or (c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial and (c as MeshInstance3D).material_override != window_mat):
			(c as MeshInstance3D).material_override = wm
	# floor number on the near wall
	if number == "":
		number = _floor_numbers[k]
	_decal(dress, "floor_" + number, Vector3(0.45, 1.55, Z0 + 0.02), Vector3(0.0, 0.0, 1.0), 0.55)
	# graffiti and grime along the flights and landings
	var walls := [
		[Vector3(-W + 0.02, 0, 0), Vector3(1, 0, 0)],
		[Vector3(W - 0.02, 0, 0), Vector3(-1, 0, 0)],
		[Vector3(0, 0, Z0 + 0.02), Vector3(0, 0, 1)],
	]
	var names := ["tag_red", "tag_black", "tag_white", "tag_green", "arrow", "cross", "stain", "stain2", "mold", "soot", "handprint"]
	for i in r.randi_range(7, 11):
		var w: Array = walls[r.randi() % walls.size()]
		var n: String = names[r.randi() % names.size()]
		var pos: Vector3 = w[0]
		var nrm: Vector3 = w[1]
		if absf(nrm.x) > 0.5:
			pos.z = r.randf_range(Z0 + 0.3, Z1 - 0.3)
		else:
			pos.x = r.randf_range(-W + 0.4, W - 0.4)
		var base_y := _floor_y(pos.x, pos.z)
		pos.y = base_y + r.randf_range(0.5, 1.9)
		if n == "soot":
			pos.y = base_y + r.randf_range(1.9, 2.4)
		_decal(dress, n, pos, nrm, r.randf_range(0.5, 1.2), r.randf_range(-0.3, 0.3))
	if r.randf() < 0.45:
		_decal(dress, "eye_tag", Vector3(r.randf_range(-0.6, 0.6), H * 0.5 + 1.2, Z1 - 0.02 - WALL_T * 0.0), Vector3(0, 0, -1), 0.7)
	if r.randf() < 0.6:
		_decal(dress, "flyer_piano", Vector3(-W + 0.02, 1.45, r.randf_range(-1.4, 0.6)), Vector3(1, 0, 0), 0.32)
	if r.randf() < 0.5:
		_decal(dress, "missing", Vector3(W - 0.02, H * 0.5 + 1.5, ZH + 0.6), Vector3(-1, 0, 0), 0.42)
	# rubble along the wall bases, paper, a few bottles' worth of glass under the window
	var mm := MultiMeshInstance3D.new()
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.mesh = MeshUtil.box(Vector3(1, 1, 1), true)
	mmesh.instance_count = 60
	for i in mmesh.instance_count:
		var on_landing := r.randf() < 0.5
		var x := (W - r.randf_range(0.05, 0.3)) * (1.0 if r.randf() < 0.5 else -1.0)
		var z := r.randf_range(Z0 + 0.1, ZL - 0.1) if on_landing else r.randf_range(ZH + 0.1, Z1 - 0.1)
		var y := 0.0 if on_landing else H * 0.5
		var s := r.randf_range(0.02, 0.09)
		var b := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU)) * Basis.from_scale(Vector3(s, s * r.randf_range(0.4, 1.0), s * r.randf_range(0.6, 1.4)))
		mmesh.set_instance_transform(i, Transform3D(b, Vector3(x, y + s * 0.3, z)))
	mm.multimesh = mmesh
	mm.material_override = _mats.rubble
	dress.add_child(mm)
	var pm := MultiMeshInstance3D.new()
	var pmesh := MultiMesh.new()
	pmesh.transform_format = MultiMesh.TRANSFORM_3D
	var pq := QuadMesh.new()
	pq.size = Vector2(1, 1)
	pq.orientation = PlaneMesh.FACE_Y
	pmesh.mesh = pq
	pmesh.instance_count = 22
	for i in pmesh.instance_count:
		var step_i := r.randi_range(0, NRISE - 2)
		var on_a := r.randf() < 0.5
		var x := r.randf_range(-W + 0.1, -GAP - 0.1) if on_a else r.randf_range(GAP + 0.1, W - 0.1)
		var z := (ZL + step_i * RUN + r.randf_range(0.05, RUN - 0.05)) if on_a else (ZH - step_i * RUN - r.randf_range(0.05, RUN - 0.05))
		var y := (step_i + 1) * rise() + (0.0 if on_a else H * 0.5) + 0.004
		var s := r.randf_range(0.05, 0.14)
		var b := Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3(s, 1.0, s * r.randf_range(0.5, 1.2)))
		pmesh.set_instance_transform(i, Transform3D(b, Vector3(x, y, z)))
	pm.multimesh = pmesh
	pm.material_override = _mats.paper
	dress.add_child(pm)
	# doors: sometimes one stands ajar onto blackness
	for dn: String in ["DoorL", "DoorR"]:
		var hinge: Node3D = f.get_node(dn).get_node("Hinge")
		hinge.rotation.y = 0.0
		if r.randf() < 0.22:
			var side := -1.0 if dn == "DoorL" else 1.0
			hinge.rotation.y = side * r.randf_range(0.12, 0.35)
	# lights: some are dying, now and then one is dead
	for li in [k * 2, k * 2 + 1]:
		var L: SensorLight = lights[li]
		L.dying = r.randf() < 0.3
		L.broken = r.randf() < 0.12
		L.energy = r.randf_range(0.8, 1.25)


func _floor_y(x: float, z: float) -> float:
	if z < ZL:
		return 0.0
	if z >= ZH:
		return H * 0.5
	var k := (z - ZL) / (ZH - ZL)
	return (k if x < 0.0 else (1.0 - k)) * H * 0.5 + (0.0 if x < 0.0 else H * 0.5)


func _decal(parent: Node3D, name: String, pos: Vector3, normal: Vector3, size: float, roll := 0.0) -> void:
	if not _decal_tex.has(name):
		return
	var d := Decal.new()
	d.texture_albedo = _decal_tex[name]
	d.size = Vector3(size, 0.12, size)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	# a Decal projects along its local -Y; aim it into the wall
	var up := normal
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var xax := ref.cross(up).normalized()
	var zax := xax.cross(up).normalized()
	d.basis = Basis(xax, up, zax) * Basis(Vector3.UP, roll)
	d.position = pos
	parent.add_child(d)


## Copy floor `src`'s dressing onto floor `dst` (used when the walker is moved
## down a floor so that what he sees doesn't change).
func copy_floor(dst: int, src_seed: int, number: String) -> void:
	configure(dst, src_seed, number)
