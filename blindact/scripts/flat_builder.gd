class_name FlatBuilder
extends Node3D
## Her flat, built in code. A hallway from the front door; the living room
## (piano, sofa under a dust sheet, his armchair, a long-case clock, a rainy
## window) on the left; the bathroom on the right; the bedroom at the end
## with a wardrobe you can hide in and a window onto the fire escape.
## Every solid thing gets a box collider. Interactables are Area3Ds with
## meta "interact" (a key for the prompt) and "id".
##
## Plan (metres, y up):            z ->
##   hallway   x in [-0.65, 0.65], z in [0, 6.4]      front door at z = 0
##   living    x in [-5.2, -0.65], z in [0, 4.6]      doorway z in [1.2, 2.4]
##   bathroom  x in [0.65, 3.0],   z in [3.4, 5.8]    door z in [3.7, 4.5]
##   bedroom   x in [-2.4, 2.4],   z in [6.4, 9.8]    door x in [-0.45, 0.45]

const CEIL := 2.75
const WT := 0.16

var interactables := {}            # id -> Area3D
var spots := {}                    # named Vector3 positions (piano seat, armchair, tub ...)
var lamps := {}                    # name -> OmniLight3D
var window_mat: ShaderMaterial
var clock_pendulum: Node3D
var doors := {}                    # id -> hinge Node3D
var piano_keys: MultiMeshInstance3D
var metronome_arm: Node3D
var chandelier_light: OmniLight3D
var _chandelier_base := 0.8
var _ft := 0.0
var _m := {}


func build() -> void:
	_materials()
	_living()
	_hallway()
	_bathroom()
	_bedroom()
	_home()
	_dress()


# ---------------------------------------------------------------------------
# materials and helpers
# ---------------------------------------------------------------------------
func _tex(n: String) -> Texture2D:
	var p := "res://assets/textures/%s.png" % n
	return load(p) if ResourceLoader.exists(p) else null


func _std(prefix: String, uv: float, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(prefix + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(prefix + "_normal")
	m.roughness_texture = _tex(prefix + "_rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough_mul
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _glass(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## A wall / floor / ceiling material (shaders/room_surface.gdshader).
func _surface(kind: int, base: String, repeat_m: float, under: String, under_repeat: float, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/room_surface.gdshader")
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("base_albedo", _tex(base + "_albedo"))
	m.set_shader_parameter("base_normal", _tex(base + "_normal"))
	m.set_shader_parameter("base_rough", _tex(base + "_rough"))
	m.set_shader_parameter("under_albedo", _tex(under + "_albedo"))
	m.set_shader_parameter("under_normal", _tex(under + "_normal"))
	m.set_shader_parameter("peel_mask", _tex("peel_mask"))
	m.set_shader_parameter("repeat_m", repeat_m)
	m.set_shader_parameter("under_repeat_m", under_repeat)
	m.set_shader_parameter("ceil_y", CEIL)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


func _materials() -> void:
	# printed damask over pasted plaster; herringbone oak; cracked distemper
	_m.wall = _surface(0, "damask", 0.53, "glue", 1.1, {"peel": 0.55, "water": 0.7, "grime": 0.55, "mould": 0.35, "seed": Vector2(0.13, 0.71)})
	_m.ceiling = _surface(2, "ceiling", 2.0, "plaster", 1.6, {"peel": 0.45, "water": 0.85, "mould": 0.35})
	_m.floor = _surface(1, "herring", 0.7, "concrete", 1.5, {"rotate_deg": 45.0, "grime": 0.55, "water": 0.35, "decay": 0.7})
	_m.tile = _surface(3, "walltile", 0.6, "concrete", 1.0, {"peel": 0.7, "water": 0.6, "grime": 0.75, "mould": 0.7, "under_tint": Vector3(0.8, 0.8, 0.78)})
	_m.tile_floor = _surface(1, "hexfloor", 0.5, "concrete", 1.0, {"grime": 0.85, "water": 0.6, "decay": 0.6})
	# his room: bare plaster coming off the brick, a floor worn to the grain
	_m.home_wall = _surface(0, "plaster", 1.8, "brick", 1.1, {"seams": 0.0, "peel": 0.8, "water": 0.8, "grime": 0.8, "mould": 0.5, "tint": Vector3(0.84, 0.82, 0.74), "seed": Vector2(0.5, 0.2)})
	_m.home_floor = _surface(1, "herring", 0.7, "concrete", 1.5, {"grime": 0.95, "water": 0.6, "decay": 1.0, "tint": Vector3(0.8, 0.78, 0.74)})
	_m.fabric = _std("velvet", 1.2)
	_m.velvet = _std("velvet", 1.4)
	_m.linen = _std("linen", 1.3)
	_m.linen.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.sheet = _m.linen
	_m.blanket = _std("velvet", 1.0, Color(0.62, 0.66, 0.68))
	_m.blanket.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.coat = _std("velvet", 2.0, Color(0.32, 0.33, 0.36))
	_m.wood = _std("panel", 1.0)
	_m.frame = _std("panel", 2.0, Color(0.8, 0.8, 0.82), 0.8)
	# the piano: black lacquer, the grain just showing through
	_m.lacquer = _std("panel", 1.2, Color(0.3, 0.3, 0.32), 0.35)
	_m.lacquer.clearcoat_enabled = true
	_m.lacquer.clearcoat = 1.0
	_m.lacquer.clearcoat_roughness = 0.12
	_m.metal = _flat(Color(0.5, 0.52, 0.53), 0.35, 0.9)
	_m.nickel = _flat(Color(0.52, 0.53, 0.54), 0.38, 1.0)
	_m.brass = _m.nickel
	_m.chrome = _flat(Color(0.7, 0.72, 0.74), 0.12, 1.0)
	_m.iron = _flat(Color(0.5, 0.53, 0.52), 0.62)
	_m.porcelain = _flat(Color(0.78, 0.8, 0.79), 0.18)
	_m.dark = _flat(Color(0.015, 0.015, 0.017), 0.9)
	_m.ivory = _flat(Color(0.78, 0.79, 0.76), 0.3)
	_m.ebony = _flat(Color(0.015, 0.015, 0.017), 0.22)
	_m.bakelite = _m.ebony
	_m.rust = _std("rust", 1.0)
	_m.mirror = _flat(Color(0.65, 0.68, 0.7), 0.03, 1.0)
	_m.paper = _flat(Color(0.6, 0.62, 0.6), 0.9)
	_m.dial = _flat(Color(0.72, 0.74, 0.72), 0.5)
	_m.wine = _flat(Color(0.1, 0.008, 0.012), 0.12)
	_m.mourning = _flat(Color(0.012, 0.012, 0.014), 0.8)
	_m.mourning.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.glass = _glass(Color(0.75, 0.8, 0.82, 0.16))
	_m.glass_dark = _glass(Color(0.04, 0.05, 0.06, 0.6))
	_m.bottle = _glass(Color(0.05, 0.12, 0.09, 0.78))
	var enamel := _flat(Color(0.76, 0.79, 0.78), 0.16)
	enamel.clearcoat_enabled = true
	enamel.clearcoat = 0.6
	enamel.clearcoat_roughness = 0.1
	_m.enamel = enamel
	_m.plaster_trim = _flat(Color(0.6, 0.62, 0.61), 0.85)
	var curtain := StandardMaterial3D.new()
	curtain.albedo_color = Color(0.7, 0.76, 0.76, 0.82)
	curtain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	curtain.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain.roughness = 0.6
	_m.curtain = curtain
	var drape := _std("velvet", 1.6, Color(0.5, 0.56, 0.58))
	drape.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.drape = drape
	window_mat = ShaderMaterial.new()
	window_mat.shader = load("res://shaders/night_window.gdshader")
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.12, 0.006, 0.006)
	blood.roughness = 0.06
	blood.metallic_specular = 0.8
	_m.blood = blood


## A box with a collider.
func _solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


## A rounded box (bevelled edges) with a box collider.
func _rsolid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0, collide := true) -> MeshInstance3D:
	var r := minf(0.012, minf(size.x, minf(size.y, size.z)) * 0.3)
	var mi := Props.rb(parent, size, pos, mat, r, Vector3(0.0, rot_y, 0.0))
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


const SKIRT_PROFILE := [Vector2(0.0, 0.0), Vector2(0.02, 0.0), Vector2(0.02, 0.105), Vector2(0.016, 0.118), Vector2(0.011, 0.124),
		Vector2(0.009, 0.135), Vector2(0.005, 0.143), Vector2(0.0, 0.146)]
const CORNICE_PROFILE := [Vector2(0.0, -0.13), Vector2(0.012, -0.124), Vector2(0.012, -0.112), Vector2(0.02, -0.104),
		Vector2(0.034, -0.088), Vector2(0.05, -0.07), Vector2(0.07, -0.05), Vector2(0.085, -0.03), Vector2(0.095, -0.016),
		Vector2(0.11, -0.012), Vector2(0.11, -0.004), Vector2(0.12, 0.0)]


## Skirting boards (broken at the doors in `cuts`: [[side, from, to]]) and a
## moulded plaster cornice round the top of a room's walls.
func _trims(parent: Node3D, x0: float, x1: float, z0: float, z1: float, cuts: Array, skirt := true, cornice := true) -> void:
	var t := WT * 0.5
	for side: String in ["x0", "x1", "z0", "z1"]:
		var along_x := side.begins_with("z")
		var a0 := (x0 if along_x else z0) + t
		var a1 := (x1 if along_x else z1) - t
		var fixed: float = {"x0": x0 + t, "x1": x1 - t, "z0": z0 + t, "z1": z1 - t}[side]
		if cornice:
			_molding(parent, CORNICE_PROFILE, a0, a1, side, fixed, CEIL, _m.plaster_trim)
		if skirt:
			var segs := [[a0, a1]]
			for c: Array in cuts:
				if c[0] != side:
					continue
				var nxt := []
				for sg: Array in segs:
					if float(c[2]) <= sg[0] or float(c[1]) >= sg[1]:
						nxt.append(sg)
					else:
						nxt.append([sg[0], float(c[1])])
						nxt.append([float(c[2]), sg[1]])
				segs = nxt
			for sg: Array in segs:
				_molding(parent, SKIRT_PROFILE, sg[0], sg[1], side, fixed, 0.0, _m.wood)


func _molding(parent: Node3D, profile: Array, a0: float, a1: float, side: String, fixed: float, y: float, mat: Material) -> void:
	if a1 - a0 < 0.02:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.extrude(PackedVector2Array(profile), a1 - a0)
	mi.material_override = mat
	var mid := (a0 + a1) * 0.5
	match side:
		"z0":
			mi.position = Vector3(mid, y, fixed)
		"z1":
			mi.position = Vector3(mid, y, fixed)
			mi.rotation.y = PI
		"x0":
			mi.position = Vector3(fixed, y, mid)
			mi.rotation.y = PI * 0.5
		"x1":
			mi.position = Vector3(fixed, y, mid)
			mi.rotation.y = -PI * 0.5
	parent.add_child(mi)


## A lathed fixture (MeshUtil.lathe) with an optional trimesh collider.
func _lathe(parent: Node3D, profile: PackedVector2Array, half: Vector2, e: float, pos: Vector3, mat: Material, segments := 32, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.lathe(profile, half, e, segments)
	if mat:
		mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _interact(parent: Node3D, id: String, prompt: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.position = pos
	a.collision_layer = 2
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.set_meta("interact", prompt)
	a.set_meta("id", id)
	parent.add_child(a)
	interactables[id] = a
	return a


## Walls of a rectangular room with door openings. openings: [[side, from, to, top]]
## side: "x0" | "x1" | "z0" | "z1"; from/to along that wall.
func _room(parent: Node3D, x0: float, x1: float, z0: float, z1: float, wall_mat: Material, floor_mat: Material, openings: Array) -> void:
	_solid(parent, Vector3(x1 - x0, 0.1, z1 - z0), Vector3((x0 + x1) * 0.5, -0.05, (z0 + z1) * 0.5), floor_mat)
	_solid(parent, Vector3(x1 - x0, 0.1, z1 - z0), Vector3((x0 + x1) * 0.5, CEIL + 0.05, (z0 + z1) * 0.5), _m.ceiling, 0.0, false)
	for side: String in ["x0", "x1", "z0", "z1"]:
		var along_x := side.begins_with("z")
		var a0 := x0 if along_x else z0
		var a1 := x1 if along_x else z1
		var fixed: float = {"x0": x0, "x1": x1, "z0": z0, "z1": z1}[side]
		var cuts: Array = []
		for o: Array in openings:
			if o[0] == side:
				cuts.append(o)
		cuts.sort_custom(func(p: Array, q: Array) -> bool: return float(p[1]) < float(q[1]))
		var cur := a0
		for o: Array in cuts:
			var f := float(o[1])
			var t := float(o[2])
			var top := float(o[3])
			if f > cur:
				_wall_piece(parent, along_x, fixed, cur, f, 0.0, CEIL, wall_mat)
			if top < CEIL:
				_wall_piece(parent, along_x, fixed, f, t, top, CEIL, wall_mat)
			cur = t
		if cur < a1:
			_wall_piece(parent, along_x, fixed, cur, a1, 0.0, CEIL, wall_mat)


func _wall_piece(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, y0: float, y1: float, mat: Material) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	if along_x:
		_solid(parent, Vector3(b - a, y1 - y0, WT), Vector3((a + b) * 0.5, (y0 + y1) * 0.5, fixed), mat)
	else:
		_solid(parent, Vector3(WT, y1 - y0, b - a), Vector3(fixed, (y0 + y1) * 0.5, (a + b) * 0.5), mat)


func _lamp(parent: Node3D, name: String, pos: Vector3, col: Color, energy: float, rng := 6.0, shadow := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = 0.5
	l.position = pos
	parent.add_child(l)
	lamps[name] = l
	return l


func _shade_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.66, 0.66)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.7, 0.82, 0.95)
	m.emission_energy_multiplier = 0.3
	return m


const COLD := Color(0.72, 0.83, 1.0)          # every bulb in the flat: cold, bluish
const SICK := Color(0.76, 0.95, 0.84)         # the hall bulb and the bathroom tube: greenish


## A table lamp: turned base and stem, a cone shade over a cold bulb.
func _table_lamp(parent: Node3D, lname: String, pos: Vector3, energy: float) -> void:
	var n := Props.node(parent, pos)
	Props.lathe(n, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.015), Vector2(0.55, 0.05), Vector2(0.3, 0.08),
			Vector2(0.18, 0.1), Vector2(0.18, 0.3), Vector2(0.35, 0.32), Vector2(0.0, 0.33)], Vector2(0.075, 0.075), Vector3.ZERO, _m.nickel, 2.0, 18)
	var shade := Props.lathe(n, [Vector2(1.0, 0.24), Vector2(0.55, 0.42)], Vector2(0.17, 0.17), Vector3.ZERO, _shade_mat(), 2.0, 28)
	shade.name = "Shade"
	_lamp(n, lname, Vector3(0.0, 0.31, 0.0), COLD, energy, 5.5)


## A standard lamp: weighted base, brass pole, a pleated shade that throws
## its light up and down (the shade casts shadows, so the walls get pools).
func _standard_lamp(parent: Node3D, lname: String, pos: Vector3, energy: float) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_lathe(n, PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.02), Vector2(0.6, 0.05), Vector2(0.2, 0.07), Vector2(0.0, 0.07)]),
			Vector2(0.16, 0.16), 2.0, Vector3.ZERO, _m.brass, 20)
	_lathe(n, PackedVector2Array([Vector2(1.0, 0.06), Vector2(1.0, 1.42), Vector2(0.0, 1.42)]), Vector2(0.012, 0.012), 2.0, Vector3.ZERO, _m.brass, 10)
	var shade := _lathe(n, PackedVector2Array([Vector2(1.0, 1.3), Vector2(0.62, 1.58)]), Vector2(0.24, 0.24), 2.0, Vector3.ZERO, _shade_mat(), 28)
	shade.name = "Shade"
	_lamp(n, lname, Vector3(0.0, 1.46, 0.0), COLD, energy, 5.0)


## A wall sconce: brass plate and arm, a small cone shade pointing up.
func _sconce(parent: Node3D, lname: String, pos: Vector3, energy: float) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_solid(n, Vector3(0.08, 0.14, 0.012), Vector3(0, 0, 0.006), _m.brass, 0.0, false)
	_solid(n, Vector3(0.012, 0.012, 0.14), Vector3(0, -0.02, 0.07), _m.brass, 0.0, false)
	_lathe(n, PackedVector2Array([Vector2(0.45, -0.02), Vector2(1.0, 0.12)]), Vector2(0.075, 0.075), 2.0, Vector3(0, 0.0, 0.14), _shade_mat(), 20)
	_lamp(n, lname, Vector3(0.0, 0.05, 0.14), COLD, energy, 3.5)


func _door(parent: Node3D, id: String, hinge_pos: Vector3, width: float, rot_y: float, closed_angle := 0.0, trim := true, tall := 2.05) -> Node3D:
	var h := Node3D.new()
	h.position = hinge_pos
	h.rotation.y = rot_y + closed_angle
	parent.add_child(h)
	var leaf := _rsolid(h, Vector3(width, tall, 0.045), Vector3(width * 0.5, tall * 0.5, 0.0), _m.wood)
	leaf.name = "Leaf"
	# raised panels on both faces: two tall ones above, two short below
	var pw := width * 0.34
	for face: float in [-1.0, 1.0]:
		for fx: float in [0.28, 0.72]:
			Props.rb(h, Vector3(pw, tall * 0.44, 0.012), Vector3(width * fx, tall * 0.69, face * 0.025), _m.wood, 0.005)
			Props.rb(h, Vector3(pw, tall * 0.27, 0.012), Vector3(width * fx, tall * 0.24, face * 0.025), _m.wood, 0.005)
		if width > 0.7:
			Props.rb(h, Vector3(0.05, 0.13, 0.006), Vector3(width - 0.08, 1.0, face * 0.026), _m.nickel, 0.004)
		if true:
			var knob := Props.lathe(h, [Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.35, 0.03), Vector2(1.0, 0.045), Vector2(0.8, 0.06),
					Vector2(0.0, 0.062)], Vector2(0.026, 0.026), Vector3(width - 0.08, 1.0, face * 0.028), _m.nickel, 2.0, 14)
			knob.rotation.x = face * PI * 0.5
	if trim:
		# architraves round the opening, both faces of the wall (not swinging)
		var t := Props.node(parent, hinge_pos, rot_y)
		for face: float in [-1.0, 1.0]:
			var z := face * (WT * 0.5 + 0.008)
			Props.rb(t, Vector3(0.07, tall + 0.1, 0.018), Vector3(-0.035, (tall + 0.1) * 0.5, z), _m.wood, 0.005)
			Props.rb(t, Vector3(0.07, tall + 0.1, 0.018), Vector3(width + 0.035, (tall + 0.1) * 0.5, z), _m.wood, 0.005)
			Props.rb(t, Vector3(width + 0.16, 0.08, 0.02), Vector3(width * 0.5, tall + 0.1, z), _m.wood, 0.006)
	h.set_meta("base_rot", rot_y)
	doors[id] = h
	return h


# ---------------------------------------------------------------------------
# rooms
# ---------------------------------------------------------------------------
func _living() -> void:
	var r := Node3D.new()
	r.name = "Living"
	add_child(r)
	var x0 := -5.2
	var x1 := -0.65
	_room(r, x0, x1, 0.0, 4.6, _m.wall, _m.floor, [["x1", 1.2, 2.4, 2.15], ["z1", -3.9, -2.5, 2.3]])
	_trims(r, x0, x1, 0.0, 4.6, [], false, true)
	# the window (rain, lightning) on the far wall z = 4.6: frame, sill,
	# a radiator under it, heavy curtains
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.4, 1.5)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(-3.2, 1.55, 4.75)
	win.rotation.y = PI
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(win)
	_solid(r, Vector3(1.4, 2.3 - 0.8, WT), Vector3(-3.2, 0.4, 4.6), _m.wall)
	_window_frame(r, Vector3(-3.2, 1.15, 4.6), Vector2(1.4, 1.15), PI)
	for side: float in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		c.mesh = MeshUtil.curtain(0.78, 2.42, 6, 0.06, 3 + int(side))
		c.material_override = _m.drape
		c.position = Vector3(-3.2 + side * 0.86, 2.5, 4.47)
		c.rotation.y = PI
		r.add_child(c)
	Props.tube(r, [Vector3(-4.2, 2.53, 4.47), Vector3(-2.2, 2.53, 4.47)], [0.014, 0.014], _m.nickel)
	Props.radiator(r, _m, Vector3(-3.2, 0.0, 4.43), PI)
	# the upright piano against the wall x = x0, facing +x
	var piano := Node3D.new()
	piano.name = "Piano"
	piano.position = Vector3(x0 + 0.33, 0.0, 2.2)
	piano.rotation.y = PI * 0.5
	r.add_child(piano)
	_build_piano(piano)
	spots.piano_seat = Vector3(x0 + 1.15, 0.0, 2.2)      # where the bench is
	spots.piano_view = Vector3(-1.0, 0.0, 0.0)           # he faces -x when playing
	Props.bench(r, _m, Vector3(x0 + 1.15, 0.0, 2.2), PI * 0.5)
	_interact(r, "piano", "ACT_SIT_PIANO", Vector3(x0 + 1.15, 0.6, 2.2), Vector3(0.6, 0.8, 1.0))
	# a lamp on the piano, a cold bulb under an old shade
	_table_lamp(r, "piano_lamp", Vector3(x0 + 0.33, 1.273, 1.62), 1.0)
	# pools of cold light: standard lamps, two sconces, the street through the rain
	_standard_lamp(r, "arm_lamp", Vector3(-1.4, 0.0, 4.2), 0.7)
	_standard_lamp(r, "floor_lamp", Vector3(-1.05, 0.0, 0.42), 0.4)
	_sconce(r, "sconce_a", Vector3(-1.35, 1.92, 0.08), 0.22)
	_sconce(r, "sconce_b", Vector3(-4.6, 1.92, 0.08), 0.22)
	var street := SpotLight3D.new()
	street.light_color = Color(0.45, 0.56, 0.95)
	street.light_energy = 2.2
	street.spot_range = 9.0
	street.spot_angle = 30.0
	street.shadow_enabled = true
	street.light_volumetric_fog_energy = 1.8
	street.position = Vector3(-3.2, 3.2, 6.4)
	r.add_child(street)
	street.look_at(Vector3(-3.4, 0.0, 2.6), Vector3.UP)
	lamps["street"] = street
	# his armchair, behind the bench, looking at the player's back
	Props.armchair(r, _m, Vector3(-2.2, 0.0, 3.3), deg_to_rad(-120.0))
	spots.armchair = Vector3(-2.2, 0.0, 3.3)
	# the sofa under a dust sheet along the z = 0 wall; a sheeted chair in the
	# corner by the window that looks like somebody sitting very still
	Props.sheeted_sofa(r, _m, Vector3(-3.4, 0.0, 0.52), 0.0)
	Props.sheeted_chair(r, _m, Vector3(-4.72, 0.0, 4.12), deg_to_rad(150.0))
	# coffee table (what they drank), rug, long-case clock
	Props.coffee_table(r, _m, Vector3(-3.2, 0.0, 1.9))
	var rug := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(2.6, 1.8)
	rug.mesh = rp
	rug.material_override = _std("velvet", 0.8, Color(0.55, 0.6, 0.62))
	rug.position = Vector3(-3.0, 0.005, 2.1)
	r.add_child(rug)
	var clk := Props.longcase_clock(r, _m, Vector3(x1 - 0.3, 0.0, 4.2), -PI * 0.5)
	clock_pendulum = clk.get_meta("pendulum")
	spots.clock = Vector3(x1 - 0.3, 1.7, 4.2)
	# photographs and a painting, framed behind glass
	Props.picture(r, _m, "photo_wedding", Vector2(0.38, 0.46), Vector3(-1.95, 1.75, 0.09), 0.0)
	Props.picture(r, _m, "painting", Vector2(0.56, 0.42), Vector3(-2.75, 1.87, 0.09), 0.0)
	Props.picture(r, _m, "photo_her", Vector2(0.5, 0.48), Vector3(-3.6, 1.75, 0.09), 0.0)
	# a side table with the landline by the doorway
	Props.pedestal_table(r, _m, Vector3(-1.0, 0.0, 3.8))
	Props.rotary_phone(r, _m, Vector3(-1.0, 0.75, 3.8), -PI * 0.5)
	_interact(r, "flat_phone", "ACT_PHONE", Vector3(-1.0, 0.85, 3.8), Vector3(0.4, 0.3, 0.4))


## Window frame in a wall: jambs, head, a mullion and transom, and a sill on
## the room side. `pos` is the bottom centre of the opening (in the wall
## plane), `rot_y` turns the room side to +z.
func _window_frame(parent: Node3D, pos: Vector3, size: Vector2, rot_y: float) -> void:
	var f := Props.node(parent, pos, rot_y)
	var fr: Material = _m.iron
	Props.rb(f, Vector3(0.06, size.y, 0.1), Vector3(-size.x * 0.5 + 0.03, size.y * 0.5, 0.0), fr, 0.01)
	Props.rb(f, Vector3(0.06, size.y, 0.1), Vector3(size.x * 0.5 - 0.03, size.y * 0.5, 0.0), fr, 0.01)
	Props.rb(f, Vector3(size.x, 0.06, 0.1), Vector3(0, size.y - 0.03, 0.0), fr, 0.01)
	Props.rb(f, Vector3(0.04, size.y, 0.06), Vector3(0, size.y * 0.5, 0.0), fr, 0.008)
	Props.rb(f, Vector3(size.x, 0.04, 0.06), Vector3(0, size.y * 0.62, 0.0), fr, 0.008)
	Props.rb(f, Vector3(size.x + 0.16, 0.045, 0.24), Vector3(0, 0.0, 0.1), _m.plaster_trim, 0.012)


func _build_piano(p: Node3D) -> void:
	# local: x along the keyboard, +z towards the player, y up. An old upright:
	# crowned lid, a framed upper panel of faded silk, brass candle sconces,
	# the fallboard folded back, turned legs on toe blocks, a framed kick
	# board, three brass pedals.
	var lq: Material = _m.lacquer
	_rsolid(p, Vector3(1.44, 1.2, 0.32), Vector3(0, 0.6, -0.12), lq)                   # back case
	for sx: float in [-0.725, 0.725]:
		_rsolid(p, Vector3(0.05, 1.22, 0.36), Vector3(sx, 0.61, -0.1), lq, 0.0, false)  # side panels
		_rsolid(p, Vector3(0.06, 0.1, 0.32), Vector3(sx * 0.99, 0.72, 0.15), lq)        # key blocks
		_rsolid(p, Vector3(0.07, 0.06, 0.38), Vector3(sx * 0.91, 0.03, 0.12), lq, 0.0, false)  # toe blocks
		var leg := MeshInstance3D.new()
		var pts := PackedVector3Array()
		var rad := PackedFloat32Array([0.026, 0.022, 0.03, 0.034, 0.024, 0.018, 0.026, 0.03, 0.022, 0.026])
		for k in rad.size():
			pts.append(Vector3(sx * 0.91, 0.06 + 0.6 * float(k) / float(rad.size() - 1), 0.25))
		leg.mesh = MeshUtil.tube(pts, rad, 14)
		leg.material_override = lq
		p.add_child(leg)
	_rsolid(p, Vector3(1.56, 0.035, 0.46), Vector3(0, 1.255, -0.08), lq, 0.0, false)    # lid
	_rsolid(p, Vector3(1.52, 0.03, 0.43), Vector3(0, 1.225, -0.08), lq, 0.0, false)     # crown steps
	_rsolid(p, Vector3(1.48, 0.02, 0.41), Vector3(0, 1.2, -0.08), lq, 0.0, false)
	_rsolid(p, Vector3(1.44, 0.07, 0.36), Vector3(0, 0.035, -0.1), lq, 0.0, false)      # plinth
	# upper front: rails and stiles framing faded silk
	var silk := _flat(Color(0.2, 0.06, 0.06), 0.85)
	_rsolid(p, Vector3(1.32, 0.3, 0.01), Vector3(0, 1.02, 0.045), silk, 0.0, false)
	for y: float in [0.86, 1.18]:
		_rsolid(p, Vector3(1.4, 0.035, 0.025), Vector3(0, y, 0.055), lq, 0.0, false)
	for x: float in [-0.68, -0.23, 0.23, 0.68]:
		_rsolid(p, Vector3(0.035, 0.33, 0.025), Vector3(x, 1.02, 0.055), lq, 0.0, false)
	# key bed, key slip, the fallboard folded back, the name rail
	_rsolid(p, Vector3(1.4, 0.06, 0.3), Vector3(0, 0.68, 0.15), lq)
	_rsolid(p, Vector3(1.42, 0.05, 0.02), Vector3(0, 0.69, 0.305), lq, 0.0, false)
	_rsolid(p, Vector3(1.38, 0.03, 0.02), Vector3(0, 0.775, 0.06), lq, 0.0, false)
	var fall := _rsolid(p, Vector3(1.38, 0.13, 0.018), Vector3(0, 0.83, 0.075), lq, 0.0, false)
	fall.rotation.x = -0.32
	# music desk with a ledge
	_rsolid(p, Vector3(1.0, 0.022, 0.07), Vector3(0, 0.93, 0.1), lq, 0.0, false)
	var stand := _rsolid(p, Vector3(0.8, 0.28, 0.015), Vector3(0, 1.06, 0.085), lq, 0.0, false)
	stand.rotation.x = -0.22
	# brass candle sconces on swinging arms
	for sx: float in [-0.6, 0.6]:
		_rsolid(p, Vector3(0.012, 0.012, 0.12), Vector3(sx, 1.0, 0.11), _m.brass, 0.0, false)
		var cup := MeshInstance3D.new()
		cup.mesh = MeshUtil.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.55, 0.02), Vector2(1.0, 0.035), Vector2(0.9, 0.045), Vector2(0.5, 0.04), Vector2(0.0, 0.04)]), Vector2(0.035, 0.035), 2.0, 16)
		cup.material_override = _m.brass
		cup.position = Vector3(sx, 1.0, 0.17)
		p.add_child(cup)
		var candle := MeshInstance3D.new()
		candle.mesh = MeshUtil.lathe(PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.0, 0.07), Vector2(0.85, 0.085), Vector2(0.0, 0.08)]), Vector2(0.011, 0.011), 2.0, 12)
		candle.material_override = _m.ivory
		candle.position = Vector3(sx, 1.04, 0.17)
		p.add_child(candle)
	# kick board with its frame, pedals in their opening
	_rsolid(p, Vector3(1.3, 0.5, 0.02), Vector3(0, 0.33, 0.035), lq, 0.0, false)
	for y: float in [0.1, 0.56]:
		_rsolid(p, Vector3(1.34, 0.03, 0.02), Vector3(0, y, 0.05), lq, 0.0, false)
	for x: float in [-0.65, 0.65]:
		_rsolid(p, Vector3(0.03, 0.46, 0.02), Vector3(x, 0.33, 0.05), lq, 0.0, false)
	_rsolid(p, Vector3(0.26, 0.05, 0.005), Vector3(0, 0.055, 0.047), _m.dark, 0.0, false)
	for x: float in [-0.075, 0.0, 0.075]:
		_rsolid(p, Vector3(0.03, 0.012, 0.09), Vector3(x, 0.055, 0.09), _m.brass, 0.0, false)
	# keys: 52 white, 36 black
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshUtil.box(Vector3(1, 1, 1), true)
	mm.instance_count = 88
	var white_w := 1.36 / 52.0
	var wi := 0
	var i := 0
	for k in 88:
		var n := (k + 9) % 12
		var black := n in [1, 3, 6, 8, 10]
		if not black:
			var x := -0.68 + white_w * (wi + 0.5)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(white_w * 0.94, 0.022, 0.15)), Vector3(x, 0.735, 0.22)))
			mm.set_instance_color(i, Color(0.84, 0.8, 0.7) * (0.85 + 0.15 * fmod(float(k) * 0.37, 1.0)))
			wi += 1
		else:
			var x2 := -0.68 + white_w * wi
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(white_w * 0.55, 0.03, 0.09)), Vector3(x2, 0.755, 0.19)))
			mm.set_instance_color(i, Color(0.02, 0.02, 0.02))
		i += 1
	piano_keys = MultiMeshInstance3D.new()
	piano_keys.multimesh = mm
	var km := StandardMaterial3D.new()
	km.vertex_color_use_as_albedo = true
	km.roughness = 0.3
	piano_keys.material_override = km
	p.add_child(piano_keys)
	# sheet music on the desk
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.3)
	sheet.mesh = q
	sheet.material_override = _flat(Color(0.75, 0.72, 0.62), 0.9)
	sheet.position = Vector3(0, 1.07, 0.098)
	sheet.rotation.x = -0.22
	p.add_child(sheet)


func _hallway() -> void:
	var r := Node3D.new()
	r.name = "Hall"
	add_child(r)
	_room(r, -0.65, 0.65, 0.0, 6.4, _m.wall, _m.floor, [["x0", 1.2, 2.4, 2.15], ["x1", 3.7, 4.5, 2.1], ["z1", -0.45, 0.45, 2.1], ["z0", -0.45, 0.45, 2.1]])
	_trims(r, -0.65, 0.65, 0.0, 6.4, [["x0", 1.2, 2.4], ["x1", 3.7, 4.5], ["z1", -0.45, 0.45], ["z0", -0.45, 0.45]])
	# the front door (to the stairwell)
	_door(r, "front", Vector3(-0.45, 0.0, 0.0), 0.9, 0.0)
	_interact(r, "front_door", "ACT_DOOR", Vector3(0.0, 1.0, 0.15), Vector3(0.9, 2.0, 0.3))
	spots.front_inside = Vector3(0.0, 0.0, 0.7)
	# a coat stand with his coats (something might be in a pocket)
	Props.coat_stand(r, _m, Vector3(0.42, 0.0, 0.8))
	_interact(r, "coat", "ACT_SEARCH", Vector3(0.45, 1.25, 0.8), Vector3(0.3, 0.9, 0.7))
	spots.coat = Vector3(0.45, 1.25, 0.8)
	# the hall mirror, covered with black cloth; her photograph further on
	Props.covered_mirror(r, _m, Vector3(-0.57, 1.55, 3.1), PI * 0.5)
	Props.picture(r, _m, "photo_her", Vector2(0.24, 0.3), Vector3(-0.57, 1.55, 4.75), PI * 0.5)
	# a bare bulb on its flex, greenish, buzzing
	_bare_bulb(r, "hall", Vector3(0.0, CEIL, 3.0), SICK, 0.8)
	spots.hall_mid = Vector3(0.0, 0.0, 3.0)
	spots.blood_pool = Vector3(0.0, 0.0, 3.25)


## A bulb hanging from the ceiling on its flex.
func _bare_bulb(parent: Node3D, lname: String, ceiling_pos: Vector3, col: Color, energy: float) -> void:
	var n := Props.node(parent, ceiling_pos)
	Props.lathe(n, [Vector2(0.0, -0.03), Vector2(1.0, -0.025), Vector2(1.0, 0.0)], Vector2(0.05, 0.05), Vector3.ZERO, _m.plaster_trim, 2.0, 14)
	Props.rb(n, Vector3(0.006, 0.42, 0.006), Vector3(0, -0.24, 0), _m.dark, 0.002)
	Props.lathe(n, [Vector2(0.0, -0.5), Vector2(1.0, -0.49), Vector2(1.0, -0.44), Vector2(0.4, -0.43), Vector2(0.0, -0.43)],
			Vector2(0.022, 0.022), Vector3.ZERO, _m.dark, 2.0, 12)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.9, 0.95, 1.0)
	bm.emission_enabled = true
	bm.emission = col
	bm.emission_energy_multiplier = 2.5
	var bulb := Props.lathe(n, [Vector2(0.0, -0.6), Vector2(0.7, -0.59), Vector2(1.0, -0.565), Vector2(0.9, -0.53), Vector2(0.5, -0.505),
			Vector2(0.45, -0.495), Vector2(0.0, -0.495)], Vector2(0.032, 0.032), Vector3.ZERO, bm, 2.0, 16)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp(n, lname, Vector3(0.0, -0.56, 0.0), col, energy, 5.5)


func _bathroom() -> void:
	var r := Node3D.new()
	r.name = "Bath"
	add_child(r)
	_room(r, 0.65, 3.0, 3.4, 5.8, _m.tile, _m.tile_floor, [["x0", 3.7, 4.5, 2.1]])
	_trims(r, 0.65, 3.0, 3.4, 5.8, [], false, true)
	_door(r, "bath", Vector3(0.65, 0.0, 3.7), 0.8, -PI * 0.5, -1.2)
	# a clawfoot bathtub along the far wall (z = 5.8), the curtain half drawn
	var tub := _lathe(r, PackedVector2Array([
			Vector2(0.0, 0.15), Vector2(0.6, 0.15), Vector2(0.84, 0.17), Vector2(0.93, 0.24), Vector2(0.98, 0.36),
			Vector2(1.0, 0.5), Vector2(1.01, 0.58), Vector2(1.03, 0.61), Vector2(1.02, 0.635), Vector2(0.98, 0.64),
			Vector2(0.95, 0.62), Vector2(0.94, 0.55), Vector2(0.92, 0.42), Vector2(0.87, 0.3), Vector2(0.78, 0.23),
			Vector2(0.5, 0.2), Vector2(0.0, 0.2)]), Vector2(0.8, 0.35), 2.6, Vector3(1.9, 0.0, 5.42), _m.enamel, 48, true)
	tub.name = "Tub"
	for fx: float in [-0.6, 0.6]:
		for fz: float in [-0.21, 0.21]:
			_lathe(r, PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.03), Vector2(0.55, 0.07),
					Vector2(0.45, 0.11), Vector2(0.8, 0.165), Vector2(0.0, 0.17)]), Vector2(0.045, 0.045), 2.0,
					Vector3(1.9 + fx, 0.0, 5.42 + fz), _m.iron, 12)
	var water := _lathe(r, PackedVector2Array([Vector2(0.925, 0.47), Vector2(0.0, 0.47)]), Vector2(0.8, 0.35), 2.6, Vector3(1.9, 0.0, 5.42), null, 48)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.16, 0.025, 0.025, 0.93)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.02
	wm.metallic_specular = 0.9
	water.material_override = wm
	water.name = "Water"
	# the tap at the head of the tub
	Props.tube(r, [Vector3(2.62, 0.62, 5.42), Vector3(2.66, 0.72, 5.42), Vector3(2.62, 0.78, 5.42), Vector3(2.52, 0.76, 5.42)],
			[0.018, 0.016, 0.014, 0.012], _m.chrome)
	spots.tub = Vector3(1.9, 0.12, 5.42)
	var cur := MeshInstance3D.new()
	cur.mesh = MeshUtil.curtain(1.0, 1.92, 8, 0.035, 2)
	cur.material_override = _m.curtain
	cur.position = Vector3(1.45, 2.19, 5.04)
	r.add_child(cur)
	spots.curtain = Vector3(1.45, 1.0, 5.04)
	Props.tube(r, [Vector3(0.75, 2.2, 5.04), Vector3(2.95, 2.2, 5.04)], [0.01, 0.01], _m.chrome)
	# a pedestal sink with a mirror cabinet on the wall x = 3.0
	_lathe(r, PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.03), Vector2(0.75, 0.08), Vector2(0.62, 0.4),
			Vector2(0.7, 0.62), Vector2(0.9, 0.68), Vector2(0.0, 0.68)]), Vector2(0.11, 0.13), 2.0, Vector3(2.8, 0.0, 4.0), _m.enamel, 24, true)
	_lathe(r, PackedVector2Array([Vector2(0.0, 0.66), Vector2(0.35, 0.66), Vector2(0.7, 0.7), Vector2(0.95, 0.78), Vector2(1.0, 0.83),
			Vector2(1.02, 0.86), Vector2(0.98, 0.875), Vector2(0.93, 0.86), Vector2(0.85, 0.81), Vector2(0.6, 0.75),
			Vector2(0.25, 0.73), Vector2(0.0, 0.73)]), Vector2(0.22, 0.27), 2.3, Vector3(2.76, 0.0, 4.0), _m.enamel, 32, true)
	for tz: float in [-0.08, 0.08]:
		_lathe(r, PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.0, 0.05), Vector2(0.6, 0.06), Vector2(1.8, 0.065), Vector2(1.8, 0.08), Vector2(0.0, 0.085)]),
				Vector2(0.014, 0.014), 2.0, Vector3(2.93, 0.86, 4.0 + tz), _m.chrome, 12)
	Props.tube(r, [Vector3(2.96, 0.88, 4.0), Vector3(2.93, 0.95, 4.0), Vector3(2.86, 0.96, 4.0), Vector3(2.82, 0.92, 4.0)],
			[0.012, 0.011, 0.01, 0.009], _m.chrome)
	var mirror := _rsolid(r, Vector3(0.03, 0.62, 0.5), Vector3(2.97, 1.55, 4.0), _m.mirror, 0.0, false)
	mirror.name = "Mirror"
	_rsolid(r, Vector3(0.14, 0.66, 0.56), Vector3(2.92, 1.55, 4.0), _m.enamel, 0.0, false)
	_interact(r, "sink", "ACT_WASH", Vector3(2.6, 0.95, 4.0), Vector3(0.5, 0.4, 0.6))
	_interact(r, "cabinet", "ACT_SEARCH", Vector3(2.85, 1.55, 4.0), Vector3(0.3, 0.6, 0.6))
	spots.sink_stand = Vector3(2.25, 0.0, 4.0)
	spots.cabinet = Vector3(2.85, 1.55, 4.0)
	# a fluorescent tube over the mirror: greenish, never quite steady
	Props.rb(r, Vector3(0.07, 0.05, 0.62), Vector3(2.95, 1.97, 4.0), _m.enamel, 0.01)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.9, 1.0, 0.95)
	tm.emission_enabled = true
	tm.emission = SICK
	tm.emission_energy_multiplier = 3.0
	var tube_light := Props.rb(r, Vector3(0.026, 0.026, 0.56), Vector3(2.91, 1.945, 4.0), tm, 0.012)
	tube_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp(r, "bath", Vector3(2.75, 1.92, 4.0), SICK, 1.1, 4.5)
	# toilet: bowl, a cracked seat, the cistern on the wall
	_lathe(r, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.62, 0.0), Vector2(0.6, 0.12), Vector2(0.72, 0.28), Vector2(0.92, 0.36),
			Vector2(1.0, 0.4), Vector2(1.0, 0.415), Vector2(0.9, 0.42), Vector2(0.8, 0.4), Vector2(0.55, 0.3), Vector2(0.3, 0.22),
			Vector2(0.0, 0.2)]), Vector2(0.19, 0.25), 2.2, Vector3(1.2, 0.0, 3.82), _m.enamel, 32, true)
	_lathe(r, PackedVector2Array([Vector2(0.76, 0.425), Vector2(1.0, 0.425), Vector2(1.03, 0.44), Vector2(0.99, 0.455),
			Vector2(0.8, 0.455), Vector2(0.75, 0.44), Vector2(0.76, 0.425)]), Vector2(0.19, 0.25), 2.2, Vector3(1.2, 0.0, 3.82), _m.lacquer, 32)
	_rsolid(r, Vector3(0.42, 0.38, 0.18), Vector3(1.2, 0.64, 3.5), _m.enamel)
	_rsolid(r, Vector3(0.45, 0.03, 0.2), Vector3(1.2, 0.845, 3.5), _m.enamel, 0.0, false)
	# a towel on a chrome rail, a bath mat
	_interact(r, "towels", "ACT_SEARCH", Vector3(1.0, 1.2, 5.6), Vector3(0.5, 0.5, 0.3))
	spots.towels = Vector3(1.0, 1.2, 5.6)
	Props.tube(r, [Vector3(0.75, 1.1, 5.72), Vector3(0.75, 1.1, 5.66), Vector3(1.25, 1.1, 5.66), Vector3(1.25, 1.1, 5.72)],
			[0.01, 0.01, 0.01, 0.01], _m.chrome)
	var towel := MeshInstance3D.new()
	towel.mesh = MeshUtil.curtain(0.44, 0.6, 3, 0.02, 9)
	towel.material_override = _m.linen
	towel.position = Vector3(1.0, 1.11, 5.645)
	r.add_child(towel)
	Props.rb(r, Vector3(0.62, 0.012, 0.4), Vector3(1.9, 0.006, 4.82), _m.linen, 0.004)


func _bedroom() -> void:
	var r := Node3D.new()
	r.name = "Bed"
	add_child(r)
	_room(r, -2.4, 2.4, 6.4, 9.8, _m.wall, _m.floor, [["z0", -0.45, 0.45, 2.1], ["z1", 0.6, 1.8, 2.3]])
	_trims(r, -2.4, 2.4, 6.4, 9.8, [["z0", -0.45, 0.45], ["z1", 0.6, 1.8]])
	_door(r, "bedroom", Vector3(-0.45, 0.0, 6.4), 0.9, 0.0, -1.3)
	# window onto the fire escape (z = 9.8), low sill, thin curtains
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.2, 1.6)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(1.2, 1.4, 9.95)
	win.rotation.y = PI
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(win)
	_solid(r, Vector3(1.2, 0.6, WT), Vector3(1.2, 0.3, 9.8), _m.wall)
	_window_frame(r, Vector3(1.2, 0.6, 9.8), Vector2(1.2, 1.7), PI)
	for cx: float in [0.45, 1.95]:
		var c := MeshInstance3D.new()
		c.mesh = MeshUtil.curtain(0.55, 2.3, 4, 0.045, int(cx * 10.0))
		c.material_override = _m.curtain
		c.position = Vector3(cx, 2.45, 9.66)
		c.rotation.y = PI
		r.add_child(c)
	_interact(r, "window_escape", "ACT_WINDOW", Vector3(1.2, 1.2, 9.65), Vector3(1.2, 1.2, 0.3))
	spots.escape = Vector3(1.2, 0.0, 9.4)
	# the bed, the blanket thrown back; a nightstand; a radiator
	Props.bed(r, _m, Vector3(-1.4, 0.0, 8.6), PI)
	Props.nightstand(r, _m, Vector3(-0.3, 0.0, 9.5), PI)
	Props.radiator(r, _m, Vector3(-2.24, 0.0, 7.4), PI * 0.5, 8)
	# wardrobe (hide inside): carcass, cornice, plinth, panelled doors
	_rsolid(r, Vector3(0.62, 2.1, 0.06), Vector3(2.05, 1.05, 6.9), _m.wood)
	_rsolid(r, Vector3(0.62, 2.1, 0.06), Vector3(2.05, 1.05, 8.1), _m.wood)
	_rsolid(r, Vector3(0.06, 2.1, 1.26), Vector3(2.37, 1.05, 7.5), _m.wood)
	_rsolid(r, Vector3(0.62, 0.06, 1.26), Vector3(2.05, 2.13, 7.5), _m.wood)
	Props.rb(r, Vector3(0.72, 0.1, 1.38), Vector3(2.03, 2.21, 7.5), _m.wood, 0.02)
	Props.rb(r, Vector3(0.66, 0.08, 1.3), Vector3(2.05, 0.04, 7.5), _m.wood, 0.01)
	_door(r, "wardrobe_a", Vector3(1.74, 0.0, 6.9), 0.6, -PI * 0.5, 0.0, false)
	_door(r, "wardrobe_b", Vector3(1.74, 0.0, 8.1), 0.6, PI * 0.5, 0.0, false)
	_interact(r, "wardrobe", "ACT_HIDE", Vector3(1.7, 1.1, 7.5), Vector3(0.4, 1.8, 1.2))
	spots.wardrobe_in = Vector3(2.05, 0.0, 7.5)
	spots.wardrobe_front = Vector3(1.2, 0.0, 7.5)
	# the chest of drawers (one of them holds something)
	Props.chest(r, _m, Vector3(-1.9, 0.0, 6.83), 0.0)
	_interact(r, "drawer", "ACT_SEARCH", Vector3(-1.9, 0.8, 7.0), Vector3(0.6, 0.4, 0.5))
	spots.drawer = Vector3(-1.9, 0.8, 7.0)
	_lamp(r, "bed_moon", Vector3(1.2, 1.8, 9.2), Color(0.5, 0.6, 0.95), 0.7, 5.0)


# ---------------------------------------------------------------------------
# his own room (the opening), far from the flat: x in [38, 41.6], z in [0, 4]
# ---------------------------------------------------------------------------
func _home() -> void:
	var r := Node3D.new()
	r.name = "Home"
	add_child(r)
	var ox := 38.0
	_room(r, ox, ox + 3.6, 0.0, 4.0, _m.home_wall, _m.home_floor, [["z0", ox + 2.5, ox + 3.4, 2.1]])
	_trims(r, ox, ox + 3.6, 0.0, 4.0, [["z0", ox + 2.5, ox + 3.4]], true, false)
	_door(r, "home_door", Vector3(ox + 2.5, 0.0, 0.0), 0.9, 0.0)
	_interact(r, "home_door", "ACT_LEAVE", Vector3(ox + 2.95, 1.0, 0.15), Vector3(0.9, 2.0, 0.3))
	# a narrow iron bed, the blanket kicked back
	var bed := Props.node(r, Vector3(ox + 0.5, 0.0, 2.9), 0.0, "IronBed")
	for sz: float in [-0.98, 0.98]:
		var top := 0.85 if sz > 0.0 else 0.62
		for sx: float in [-0.42, 0.42]:
			Props.tube(bed, [Vector3(sx, 0.0, sz), Vector3(sx, top, sz)], [0.014, 0.014], _m.iron)
		Props.tube(bed, [Vector3(-0.42, top - 0.03, sz), Vector3(0.42, top - 0.03, sz)], [0.012, 0.012], _m.iron)
		for k in 5:
			var bx := -0.28 + k * 0.14
			Props.tube(bed, [Vector3(bx, 0.35, sz), Vector3(bx, top - 0.03, sz)], [0.007, 0.007], _m.iron)
	Props.rb(bed, Vector3(0.82, 0.14, 1.9), Vector3(0, 0.42, 0), _m.linen, 0.05)
	Props.rb(bed, Vector3(0.52, 0.1, 0.3), Vector3(0, 0.54, 0.75), _m.linen, 0.05)
	var btop := func(_x: float, _z: float) -> float:
		return 0.5
	Props.add(bed, MeshUtil.drape(btop, Vector2(0.41, 0.5), 0.36, Vector2i(32, 32), 4), _m.blanket, Vector3(0, 0, -0.35))
	Props.collider(bed, Vector3(0.9, 0.55, 2.0), Vector3(0, 0.27, 0))
	# the table with the landline
	var tb := Props.node(r, Vector3(ox + 2.9, 0.0, 3.6), 0.0, "Table")
	Props.rb(tb, Vector3(1.0, 0.035, 0.6), Vector3(0, 0.735, 0), _m.wood, 0.01)
	Props.rb(tb, Vector3(0.92, 0.08, 0.52), Vector3(0, 0.68, 0), _m.wood, 0.006)
	for sx: float in [-0.46, 0.46]:
		for sz: float in [-0.26, 0.26]:
			Props.rb(tb, Vector3(0.04, 0.72, 0.04), Vector3(sx, 0.36, sz), _m.wood, 0.008)
	Props.collider(tb, Vector3(1.0, 0.75, 0.6), Vector3(0, 0.375, 0))
	Props.rotary_phone(r, _m, Vector3(ox + 2.7, 0.753, 3.6), PI)
	_interact(r, "home_phone", "ACT_PHONE", Vector3(ox + 2.7, 0.86, 3.6), Vector3(0.4, 0.3, 0.4))
	spots.home_phone = Vector3(ox + 2.7, 0.86, 3.6)
	# his dark glasses, folded on the table
	var gl := Props.node(r, Vector3(ox + 3.15, 0.755, 3.5), 0.3, "Glasses")
	for sx: float in [-0.034, 0.034]:
		Props.rb(gl, Vector3(0.052, 0.042, 0.006), Vector3(sx, 0.022, 0.0), _m.glass_dark, 0.012, Vector3(-0.2, 0, 0))
		Props.rb(gl, Vector3(0.004, 0.004, 0.13), Vector3(sx * 1.6, 0.008, -0.06), _m.ebony, 0.0015)
	Props.rb(gl, Vector3(0.02, 0.006, 0.006), Vector3(0, 0.035, 0.0), _m.ebony, 0.002)
	_interact(r, "glasses", "ACT_GLASSES", Vector3(ox + 3.15, 0.8, 3.5), Vector3(0.3, 0.2, 0.3))
	var cane := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0065
	cm.bottom_radius = 0.0065
	cm.height = 1.2
	cane.mesh = cm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cane.gdshader")
	cane.material_override = mat
	cane.position = Vector3(ox + 3.45, 0.6, 0.35)
	cane.rotation.z = 0.12
	cane.name = "HomeCane"
	r.add_child(cane)
	_interact(r, "cane", "ACT_CANE", Vector3(ox + 3.4, 0.9, 0.4), Vector3(0.3, 1.0, 0.3))
	# a cheap electric piano on an X stand: what he practises on
	var kb := Props.node(r, Vector3(ox + 0.95, 0.0, 0.34), 0.0, "Keyboard")
	for sx: float in [-0.42, 0.42]:
		for a: float in [-0.62, 0.62]:
			Props.rb(kb, Vector3(0.03, 0.86, 0.03), Vector3(sx, 0.36, 0.0), _m.iron, 0.01, Vector3(a, 0, 0))
	Props.rb(kb, Vector3(1.15, 0.08, 0.3), Vector3(0, 0.76, 0), _m.ebony, 0.02)
	Props.rb(kb, Vector3(1.05, 0.02, 0.14), Vector3(0, 0.805, 0.06), _m.ivory, 0.004)
	for k in 36:
		var oct := k / 5
		var black_pos: Array[float] = [0.5, 1.5, 3.5, 4.5, 5.5]
		var pos_in: float = black_pos[k % 5]
		var x: float = -0.525 + (oct * 7 + pos_in) * (1.05 / 51.0) + 0.0103
		if x > 0.52:
			break
		Props.rb(kb, Vector3(0.011, 0.016, 0.085), Vector3(x, 0.82, 0.035), _m.ebony, 0.002)
	Props.collider(kb, Vector3(1.15, 0.85, 0.35), Vector3(0, 0.42, 0))
	# the window, a thin curtain, a cold bare bulb
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.0, 1.2)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(ox - 0.1, 1.5, 2.0)
	win.rotation.y = PI * 0.5
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(win)
	var wc := MeshInstance3D.new()
	wc.mesh = MeshUtil.curtain(0.6, 1.5, 4, 0.04, 21)
	wc.material_override = _m.curtain
	wc.position = Vector3(ox + 0.12, 2.25, 1.75)
	wc.rotation.y = PI * 0.5
	r.add_child(wc)
	_bare_bulb(r, "home_lamp", Vector3(ox + 1.9, CEIL, 2.1), COLD, 0.9)
	spots.home_start = Vector3(ox + 1.6, 0.0, 1.6)
	spots.home_out = Vector3(ox + 2.95, 0.0, 0.6)


# ---------------------------------------------------------------------------
# dressing: what makes it somebody's home, gone wrong
# ---------------------------------------------------------------------------
## Wainscot panelling 0.95 m high along a wall face from a to b: backing,
## capping rail, skirting, rails and stiles framing raised fields.
func _wainscot(parent: Node3D, a: Vector3, b: Vector3, inward: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	var rot := atan2(d.x / ln, d.z / ln)
	var lx := Vector3(cos(rot), 0.0, -sin(rot))
	var sg := 1.0 if lx.dot(inward) > 0.0 else -1.0
	var w := Props.node(parent, (a + b) * 0.5, rot)
	var wd: Material = _m.wood
	Props.rb(w, Vector3(0.02, 0.95, ln), Vector3(sg * 0.01, 0.475, 0), wd, 0.004)
	Props.rb(w, Vector3(0.05, 0.045, ln), Vector3(sg * 0.025, 0.97, 0), wd, 0.012)
	Props.rb(w, Vector3(0.03, 0.14, ln), Vector3(sg * 0.025, 0.07, 0), wd, 0.008)
	Props.rb(w, Vector3(0.016, 0.07, ln), Vector3(sg * 0.026, 0.88, 0), wd, 0.006)
	Props.rb(w, Vector3(0.016, 0.07, ln), Vector3(sg * 0.026, 0.19, 0), wd, 0.006)
	var n := maxi(1, int(round(ln / 0.6)))
	for i in n + 1:
		var z := clampf(-ln * 0.5 + ln * float(i) / n, -ln * 0.5 + 0.035, ln * 0.5 - 0.035)
		Props.rb(w, Vector3(0.016, 0.62, 0.07), Vector3(sg * 0.026, 0.535, z), wd, 0.006)
	for i in n:
		var z0 := -ln * 0.5 + ln * float(i) / n
		var z1 := -ln * 0.5 + ln * float(i + 1) / n
		Props.rb(w, Vector3(0.012, 0.5, maxf(0.05, z1 - z0 - 0.16)), Vector3(sg * 0.024, 0.535, (z0 + z1) * 0.5), wd, 0.01)


func _dress() -> void:
	var liv: Node3D = get_node("Living")
	var hall: Node3D = get_node("Hall")
	# panelling round the living room, on the walls' inner faces (not behind
	# the piano, not under the window where the radiator is)
	_wainscot(liv, Vector3(-5.12, 0, 0.08), Vector3(-0.73, 0, 0.08), Vector3.BACK)
	_wainscot(liv, Vector3(-0.73, 0, 0.08), Vector3(-0.73, 0, 1.2), Vector3.LEFT)
	_wainscot(liv, Vector3(-0.73, 0, 2.4), Vector3(-0.73, 0, 4.52), Vector3.LEFT)
	_wainscot(liv, Vector3(-0.73, 0, 4.52), Vector3(-2.45, 0, 4.52), Vector3.FORWARD)
	_wainscot(liv, Vector3(-3.95, 0, 4.52), Vector3(-5.12, 0, 4.52), Vector3.FORWARD)
	# a chandelier with candle bulbs under a plaster rose; two still work, and they stutter
	Props.lathe(liv, [Vector2(0.0, CEIL - 0.045), Vector2(0.3, CEIL - 0.04), Vector2(0.6, CEIL - 0.034), Vector2(0.85, CEIL - 0.02),
			Vector2(1.0, CEIL)], Vector2(0.26, 0.26), Vector3(-3.0, 0.0, 2.2), _m.plaster_trim, 2.0, 32)
	var ch := Node3D.new()
	ch.position = Vector3(-3.0, CEIL - 0.55, 2.2)
	liv.add_child(ch)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.31
	ring.mesh = tm
	ring.material_override = _m.metal
	ch.add_child(ring)
	Props.rb(ch, Vector3(0.012, 0.55, 0.012), Vector3(0, 0.28, 0), _m.metal, 0.004)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.9, 0.95, 1.0)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = COLD
	bulb_mat.emission_energy_multiplier = 3.0
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var c := Props.rb(ch, Vector3(0.026, 0.09, 0.026), Vector3(cos(ang) * 0.3, 0.06, sin(ang) * 0.3), _m.ivory, 0.008)
		c.name = "Candle%d" % i
		var lit := i == 1 or i == 4
		var fl := Props.lathe(ch, [Vector2(0.0, 0.0), Vector2(1.0, 0.012), Vector2(0.6, 0.035), Vector2(0.0, 0.045)], Vector2(0.012, 0.012),
				Vector3(cos(ang) * 0.3, 0.105, sin(ang) * 0.3), bulb_mat if lit else _m.glass, 2.0, 10)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chandelier_light = _lamp(ch, "chandelier", Vector3(0.0, 0.05, 0.0), COLD, 0.55, 6.5)
	_chandelier_base = chandelier_light.light_energy
	# on the piano: metronome, dead flowers, a pile of music
	var piano: Node3D = liv.get_node("Piano")
	var met := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.07
	cm.height = 0.22
	cm.radial_segments = 4
	met.mesh = cm
	met.material_override = _m.lacquer
	met.position = Vector3(0.45, 1.39, 0.0)
	met.rotation.y = PI * 0.25
	piano.add_child(met)
	metronome_arm = Node3D.new()
	metronome_arm.position = Vector3(0.45, 1.3, 0.05)
	piano.add_child(metronome_arm)
	Props.rb(metronome_arm, Vector3(0.006, 0.2, 0.006), Vector3(0, 0.1, 0), _m.metal, 0.002)
	Props.lathe(piano, [Vector2(0.0, 0.0), Vector2(0.8, 0.0), Vector2(1.0, 0.08), Vector2(0.75, 0.2), Vector2(0.55, 0.24), Vector2(0.62, 0.26),
			Vector2(0.0, 0.25)], Vector2(0.06, 0.06), Vector3(-0.35, 1.275, 0.0), _m.porcelain, 2.0, 20)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 7:
		var stem := _solid(piano, Vector3(0.005, 0.3, 0.005), Vector3(-0.35 + rng.randf_range(-0.03, 0.03), 1.64, rng.randf_range(-0.03, 0.03)), _flat(Color(0.1, 0.1, 0.07), 0.9), 0.0, false)
		stem.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.6, 0.6))
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.03
		head.mesh = sm
		head.material_override = _flat(Color(0.12, 0.03, 0.04), 0.9)
		head.position = Vector3(0, 0.15, 0)
		stem.add_child(head)
	for i in 4:
		Props.rb(piano, Vector3(0.31, 0.012, 0.23), Vector3(0.05 + i * 0.006, 1.282 + i * 0.012, -0.05 + i * 0.004), _m.paper, 0.002, Vector3(0, 0.08 * i - 0.1, 0))
	# dust drifting in the lamplight
	var dust := GPUParticles3D.new()
	dust.amount = 120
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.position = Vector3(-4.3, 1.5, 1.9)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.7, 0.9)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.004
	pm.initial_velocity_max = 0.02
	pm.gravity = Vector3(0, -0.003, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.15
	dust.process_material = pm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.004, 0.004)
	var dm := StandardMaterial3D.new()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.85, 0.9, 1.0, 0.5)
	dq.material = dm
	dust.draw_pass_1 = dq
	liv.add_child(dust)
	# drag marks down the hall, from the bathroom door
	for i in 7:
		var d := Decal.new()
		var tp := "res://assets/textures/decals/stain2.png"
		if ResourceLoader.exists(tp):
			d.texture_albedo = load(tp)
		d.modulate = Color(0.3, 0.02, 0.025)
		d.size = Vector3(0.4, 0.2, 0.6)
		d.position = Vector3(0.15 * sin(float(i)), 0.02, 4.0 - i * 0.42)
		hall.add_child(d)


func _process(delta: float) -> void:
	# the chandelier's two bulbs: steady, then a stutter, now and then a drop
	if chandelier_light == null:
		return
	_ft += delta
	var f := 1.0
	if fmod(_ft, 7.3) < 0.35:
		f = 0.2 + 0.8 * float(int(_ft * 30.0) % 2)
	elif fmod(_ft, 13.1) < 0.12:
		f = 0.08
	chandelier_light.light_energy = _chandelier_base * f
