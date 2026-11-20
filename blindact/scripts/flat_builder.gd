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
var _m := {}


func build() -> void:
	_materials()
	_living()
	_hallway()
	_bathroom()
	_bedroom()
	_home()


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


func _flat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _materials() -> void:
	_m.wall = _std("wallpaper", 0.6)
	_m.ceiling = _std("plaster", 0.5, Color(0.8, 0.78, 0.74))
	_m.floor = _std("parquet", 0.55)
	_m.tile = _std("tiles", 0.9)
	_m.tile_floor = _std("tiles", 1.6, Color(0.7, 0.68, 0.64))
	_m.fabric = _std("fabric", 1.2)
	_m.sheet = _std("plaster", 1.0, Color(0.85, 0.83, 0.78))
	_m.wood = _std("wood", 1.0)
	_m.lacquer = _std("wood", 1.2, Color(0.12, 0.08, 0.06), 0.35)
	_m.lacquer.clearcoat_enabled = true
	_m.lacquer.clearcoat = 0.8
	_m.lacquer.clearcoat_roughness = 0.15
	_m.metal = _flat(Color(0.55, 0.5, 0.4), 0.35, 0.9)
	_m.porcelain = _flat(Color(0.82, 0.81, 0.77), 0.18)
	_m.dark = _flat(Color(0.02, 0.02, 0.02), 0.9)
	_m.ivory = _flat(Color(0.86, 0.82, 0.72), 0.3)
	_m.ebony = _flat(Color(0.02, 0.02, 0.02), 0.25)
	_m.rust = _std("rust", 1.0)
	_m.mirror = _flat(Color(0.65, 0.68, 0.7), 0.03, 1.0)
	var curtain := StandardMaterial3D.new()
	curtain.albedo_color = Color(0.75, 0.78, 0.72, 0.82)
	curtain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	curtain.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain.roughness = 0.6
	_m.curtain = curtain
	var drape := _std("fabric", 2.0, Color(0.6, 0.55, 0.5))
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


func _door(parent: Node3D, id: String, hinge_pos: Vector3, width: float, rot_y: float, closed_angle := 0.0) -> Node3D:
	var h := Node3D.new()
	h.position = hinge_pos
	h.rotation.y = rot_y + closed_angle
	parent.add_child(h)
	var leaf := _solid(h, Vector3(width, 2.05, 0.045), Vector3(width * 0.5, 1.025, 0.0), _m.wood)
	leaf.name = "Leaf"
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.028
	km.height = 0.056
	knob.mesh = km
	knob.material_override = _m.metal
	knob.position = Vector3(width - 0.08, 1.0, 0.05)
	h.add_child(knob)
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
	# the window (rain, lightning) on the far wall z = 4.6, with heavy curtains
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.4, 1.5)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(-3.2, 1.55, 4.75)
	win.rotation.y = PI
	r.add_child(win)
	_solid(r, Vector3(1.4, 2.3 - 0.8, WT), Vector3(-3.2, 0.4, 4.6), _m.wall)
	for side: float in [-1.0, 1.0]:
		var d := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.75, 2.5)
		pm.subdivide_width = 12
		pm.orientation = PlaneMesh.FACE_Z
		d.mesh = pm
		d.material_override = _m.drape
		d.position = Vector3(-3.2 + side * 0.9, 1.35, 4.5)
		r.add_child(d)
	for i in 3:
		_solid(r, Vector3(0.04, 1.5, 0.04), Vector3(-3.2 - 0.47 + i * 0.47, 1.55, 4.62), _m.wood, 0.0, false)
	_solid(r, Vector3(1.4, 0.05, 0.04), Vector3(-3.2, 1.55, 4.62), _m.wood, 0.0, false)
	# the upright piano against the wall x = x0, facing +x
	var piano := Node3D.new()
	piano.name = "Piano"
	piano.position = Vector3(x0 + 0.33, 0.0, 2.2)
	piano.rotation.y = PI * 0.5
	r.add_child(piano)
	_build_piano(piano)
	spots.piano_seat = Vector3(x0 + 1.15, 0.0, 2.2)      # where the bench is
	spots.piano_view = Vector3(-1.0, 0.0, 0.0)           # he faces -x when playing
	_solid(r, Vector3(0.38, 0.5, 0.85), Vector3(x0 + 1.15, 0.25, 2.2), _m.lacquer)   # bench
	_interact(r, "piano", "ACT_SIT_PIANO", Vector3(x0 + 1.15, 0.6, 2.2), Vector3(0.6, 0.8, 1.0))
	# a lamp on the piano: the warm heart of the room
	_lamp(r, "piano_lamp", Vector3(x0 + 0.35, 1.62, 1.6), Color(1.0, 0.62, 0.32), 1.5, 5.5)
	var shade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.16
	cm.height = 0.2
	shade.mesh = cm
	var smat := _flat(Color(0.75, 0.62, 0.42), 0.8)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.6, 0.3)
	smat.emission_energy_multiplier = 0.6
	shade.material_override = smat
	shade.position = Vector3(x0 + 0.35, 1.66, 1.6)
	r.add_child(shade)
	# his armchair, behind the bench, looking at the player's back
	_armchair(r, Vector3(-2.2, 0.0, 3.3), deg_to_rad(-120.0))
	spots.armchair = Vector3(-2.2, 0.0, 3.3)
	# the sofa under a dust sheet along z = 0 wall
	_solid(r, Vector3(2.1, 0.45, 0.9), Vector3(-3.4, 0.225, 0.55), _m.fabric)
	_solid(r, Vector3(2.1, 0.5, 0.22), Vector3(-3.4, 0.7, 0.13), _m.fabric)
	var sheet := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2(2.3, 1.4)
	sp.subdivide_width = 10
	sp.subdivide_depth = 6
	sheet.mesh = sp
	sheet.material_override = _m.sheet
	sheet.position = Vector3(-3.4, 0.86, 0.45)
	sheet.rotation.x = -0.35
	r.add_child(sheet)
	# coffee table, rug, long-case clock, floor lamp, pictures
	_solid(r, Vector3(1.0, 0.42, 0.55), Vector3(-3.2, 0.21, 1.9), _m.wood)
	var rug := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(2.6, 1.8)
	rug.mesh = rp
	rug.material_override = _std("fabric", 0.8, Color(0.75, 0.6, 0.55))
	rug.position = Vector3(-3.0, 0.005, 2.1)
	r.add_child(rug)
	_clock(r, Vector3(x1 - 0.3, 0.0, 4.2))
	_lamp(r, "floor_lamp", Vector3(-1.0, 1.5, 0.35), Color(1.0, 0.7, 0.42), 0.35, 4.0, false)
	_solid(r, Vector3(0.03, 1.5, 0.03), Vector3(-1.0, 0.75, 0.35), _m.metal, 0.0, false)
	for i in 3:
		var fr := _solid(r, Vector3(0.45 + i * 0.1, 0.55, 0.03), Vector3(-1.9 - i * 0.8, 1.75 + (i % 2) * 0.12, 0.09), _m.wood, 0.0, false)
		fr.name = "Frame%d" % i
	# a side table with a landline by the doorway
	_solid(r, Vector3(0.45, 0.75, 0.45), Vector3(-1.0, 0.375, 3.8), _m.wood)
	_phone(r, Vector3(-1.0, 0.76, 3.8))
	_interact(r, "flat_phone", "ACT_PHONE", Vector3(-1.0, 0.85, 3.8), Vector3(0.4, 0.3, 0.4))


func _build_piano(p: Node3D) -> void:
	# local: x along the keyboard, +z towards the player, y up
	_solid(p, Vector3(1.48, 1.22, 0.32), Vector3(0, 0.61, -0.12), _m.lacquer)          # cabinet
	_solid(p, Vector3(1.48, 0.06, 0.62), Vector3(0, 1.25, 0.03), _m.lacquer, 0.0, false)  # lid
	_solid(p, Vector3(1.4, 0.08, 0.3), Vector3(0, 0.68, 0.15), _m.lacquer)             # key bed
	_solid(p, Vector3(0.06, 0.75, 0.6), Vector3(-0.73, 0.4, 0.05), _m.lacquer)
	_solid(p, Vector3(0.06, 0.75, 0.6), Vector3(0.73, 0.4, 0.05), _m.lacquer)
	_solid(p, Vector3(1.4, 0.04, 0.18), Vector3(0, 0.98, 0.08), _m.lacquer, 0.0, false)   # music shelf
	var stand := _solid(p, Vector3(0.7, 0.32, 0.02), Vector3(0, 1.12, 0.12), _m.lacquer, 0.0, false)
	stand.rotation.x = -0.2
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
	# candlesticks and sheet music
	for s: float in [-0.55, 0.55]:
		_solid(p, Vector3(0.03, 0.18, 0.03), Vector3(s, 1.37, 0.12), _m.metal, 0.0, false)
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.3)
	sheet.mesh = q
	sheet.material_override = _flat(Color(0.75, 0.72, 0.62), 0.9)
	sheet.position = Vector3(0, 1.13, 0.135)
	sheet.rotation.x = -0.2
	p.add_child(sheet)


func _armchair(r: Node3D, pos: Vector3, rot: float) -> void:
	var a := Node3D.new()
	a.position = pos
	a.rotation.y = rot
	r.add_child(a)
	_solid(a, Vector3(0.85, 0.42, 0.8), Vector3(0, 0.21, 0), _m.fabric)
	_solid(a, Vector3(0.85, 0.65, 0.18), Vector3(0, 0.75, -0.33), _m.fabric)
	_solid(a, Vector3(0.14, 0.25, 0.8), Vector3(-0.38, 0.55, 0), _m.fabric)
	_solid(a, Vector3(0.14, 0.25, 0.8), Vector3(0.38, 0.55, 0), _m.fabric)


func _clock(r: Node3D, pos: Vector3) -> void:
	var c := Node3D.new()
	c.position = pos
	c.rotation.y = -PI * 0.5
	r.add_child(c)
	_solid(c, Vector3(0.48, 2.05, 0.3), Vector3(0, 1.025, 0), _m.lacquer)
	var face := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.17
	cm.height = 0.02
	face.mesh = cm
	face.material_override = _m.ivory
	face.rotation.x = PI * 0.5
	face.position = Vector3(0, 1.72, 0.16)
	c.add_child(face)
	clock_pendulum = Node3D.new()
	clock_pendulum.position = Vector3(0, 1.45, 0.16)
	c.add_child(clock_pendulum)
	_solid(clock_pendulum, Vector3(0.012, 0.6, 0.01), Vector3(0, -0.3, 0), _m.metal, 0.0, false)
	var bob := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.06
	bm.bottom_radius = 0.06
	bm.height = 0.01
	bob.mesh = bm
	bob.material_override = _m.metal
	bob.rotation.x = PI * 0.5
	bob.position = Vector3(0, -0.62, 0.01)
	clock_pendulum.add_child(bob)
	spots.clock = pos + Vector3(0, 1.7, 0)


func _phone(r: Node3D, pos: Vector3) -> void:
	_solid(r, Vector3(0.2, 0.08, 0.22), pos + Vector3(0, 0.04, 0), _flat(Color(0.05, 0.05, 0.05), 0.3), 0.0, false)
	_solid(r, Vector3(0.22, 0.05, 0.06), pos + Vector3(0, 0.1, -0.06), _flat(Color(0.05, 0.05, 0.05), 0.3), 0.0, false)


func _hallway() -> void:
	var r := Node3D.new()
	r.name = "Hall"
	add_child(r)
	_room(r, -0.65, 0.65, 0.0, 6.4, _m.wall, _m.floor, [["x0", 1.2, 2.4, 2.15], ["x1", 3.7, 4.5, 2.1], ["z1", -0.45, 0.45, 2.1], ["z0", -0.45, 0.45, 2.1]])
	# the front door (to the stairwell)
	_door(r, "front", Vector3(-0.45, 0.0, 0.0), 0.9, 0.0)
	_interact(r, "front_door", "ACT_DOOR", Vector3(0.0, 1.0, 0.15), Vector3(0.9, 2.0, 0.3))
	spots.front_inside = Vector3(0.0, 0.0, 0.7)
	# coat rack with coats (something might be in a pocket)
	_solid(r, Vector3(0.05, 1.8, 0.05), Vector3(0.52, 0.9, 0.8), _m.wood, 0.0, false)
	for i in 2:
		var coat := _solid(r, Vector3(0.12, 0.85, 0.42), Vector3(0.48, 1.25, 0.65 + i * 0.3), _std("fabric", 2.0, Color(0.25, 0.25, 0.28)), 0.0, false)
		coat.name = "Coat%d" % i
	_interact(r, "coat", "ACT_SEARCH", Vector3(0.45, 1.25, 0.8), Vector3(0.3, 0.9, 0.7))
	spots.coat = Vector3(0.45, 1.25, 0.8)
	# a bulb in the hall
	_lamp(r, "hall", Vector3(0.0, CEIL - 0.35, 3.0), Color(1.0, 0.66, 0.36), 0.7, 5.0)
	spots.hall_mid = Vector3(0.0, 0.0, 3.0)
	spots.blood_pool = Vector3(0.0, 0.0, 3.25)


func _bathroom() -> void:
	var r := Node3D.new()
	r.name = "Bath"
	add_child(r)
	_room(r, 0.65, 3.0, 3.4, 5.8, _m.tile, _m.tile_floor, [["x0", 3.7, 4.5, 2.1]])
	_door(r, "bath", Vector3(0.65, 0.0, 3.7), 0.8, -PI * 0.5, -1.2)
	# bathtub along the far wall (z = 5.8), the curtain half drawn
	var tub := CSGCombiner3D.new()
	tub.use_collision = true
	tub.position = Vector3(1.9, 0.0, 5.42)
	r.add_child(tub)
	var outer := CSGBox3D.new()
	outer.size = Vector3(1.7, 0.6, 0.72)
	outer.position = Vector3(0, 0.3, 0)
	outer.material = _m.porcelain
	tub.add_child(outer)
	var inner := CSGBox3D.new()
	inner.size = Vector3(1.56, 0.6, 0.58)
	inner.position = Vector3(0, 0.38, 0)
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.material = _m.porcelain
	tub.add_child(inner)
	var water := MeshInstance3D.new()
	var wq := PlaneMesh.new()
	wq.size = Vector2(1.55, 0.57)
	water.mesh = wq
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.04, 0.035, 0.9)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.02
	water.material_override = wm
	water.position = Vector3(1.9, 0.48, 5.42)
	r.add_child(water)
	spots.tub = Vector3(1.9, 0.12, 5.42)
	var cur := MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(1.0, 1.9)
	cp.subdivide_width = 16
	cp.orientation = PlaneMesh.FACE_Z
	cur.mesh = cp
	cur.material_override = _m.curtain
	cur.position = Vector3(1.45, 1.25, 5.04)
	r.add_child(cur)
	spots.curtain = Vector3(1.45, 1.0, 5.04)
	_solid(r, Vector3(1.8, 0.02, 0.02), Vector3(1.9, 2.2, 5.04), _m.metal, 0.0, false)
	# sink with a mirror cabinet on the wall x = 3.0
	_solid(r, Vector3(0.45, 0.82, 0.5), Vector3(2.75, 0.41, 4.0), _m.porcelain)
	var mirror := _solid(r, Vector3(0.03, 0.62, 0.5), Vector3(2.97, 1.55, 4.0), _m.mirror, 0.0, false)
	mirror.name = "Mirror"
	_solid(r, Vector3(0.14, 0.62, 0.55), Vector3(2.92, 1.55, 4.0), _m.wood, 0.0, false)
	_interact(r, "sink", "ACT_WASH", Vector3(2.6, 0.95, 4.0), Vector3(0.5, 0.4, 0.6))
	_interact(r, "cabinet", "ACT_SEARCH", Vector3(2.85, 1.55, 4.0), Vector3(0.3, 0.6, 0.6))
	spots.sink_stand = Vector3(2.25, 0.0, 4.0)
	spots.cabinet = Vector3(2.85, 1.55, 4.0)
	# toilet
	_solid(r, Vector3(0.42, 0.42, 0.6), Vector3(1.2, 0.21, 3.75), _m.porcelain)
	_solid(r, Vector3(0.42, 0.4, 0.18), Vector3(1.2, 0.62, 3.5), _m.porcelain)
	_interact(r, "towels", "ACT_SEARCH", Vector3(1.0, 1.2, 5.6), Vector3(0.5, 0.5, 0.3))
	spots.towels = Vector3(1.0, 1.2, 5.6)
	_solid(r, Vector3(0.6, 0.04, 0.25), Vector3(1.0, 1.0, 5.65), _m.wood, 0.0, false)
	_lamp(r, "bath", Vector3(1.8, CEIL - 0.3, 4.4), Color(0.95, 0.85, 0.7), 0.8, 4.5)


func _bedroom() -> void:
	var r := Node3D.new()
	r.name = "Bed"
	add_child(r)
	_room(r, -2.4, 2.4, 6.4, 9.8, _m.wall, _m.floor, [["z0", -0.45, 0.45, 2.1], ["z1", 0.6, 1.8, 2.3]])
	_door(r, "bedroom", Vector3(-0.45, 0.0, 6.4), 0.9, 0.0, -1.3)
	# window onto the fire escape (z = 9.8), low sill
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.2, 1.6)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(1.2, 1.4, 9.95)
	win.rotation.y = PI
	r.add_child(win)
	_solid(r, Vector3(1.2, 0.6, WT), Vector3(1.2, 0.3, 9.8), _m.wall)
	_interact(r, "window_escape", "ACT_WINDOW", Vector3(1.2, 1.2, 9.65), Vector3(1.2, 1.2, 0.3))
	spots.escape = Vector3(1.2, 0.0, 9.4)
	# bed
	_solid(r, Vector3(1.6, 0.5, 2.1), Vector3(-1.4, 0.25, 8.6), _m.wood)
	_solid(r, Vector3(1.55, 0.18, 2.0), Vector3(-1.4, 0.59, 8.62), _m.sheet)
	# wardrobe (hide inside)
	_solid(r, Vector3(0.62, 2.1, 0.06), Vector3(2.05, 1.05, 6.9), _m.wood)
	_solid(r, Vector3(0.62, 2.1, 0.06), Vector3(2.05, 1.05, 8.1), _m.wood)
	_solid(r, Vector3(0.06, 2.1, 1.26), Vector3(2.37, 1.05, 7.5), _m.wood)
	_solid(r, Vector3(0.62, 0.06, 1.26), Vector3(2.05, 2.13, 7.5), _m.wood)
	_door(r, "wardrobe_a", Vector3(1.74, 0.0, 6.9), 0.6, -PI * 0.5)
	_door(r, "wardrobe_b", Vector3(1.74, 0.0, 8.1), 0.6, PI * 0.5)
	_interact(r, "wardrobe", "ACT_HIDE", Vector3(1.7, 1.1, 7.5), Vector3(0.4, 1.8, 1.2))
	spots.wardrobe_in = Vector3(2.05, 0.0, 7.5)
	spots.wardrobe_front = Vector3(1.2, 0.0, 7.5)
	_interact(r, "drawer", "ACT_SEARCH", Vector3(-1.9, 0.8, 7.0), Vector3(0.6, 0.4, 0.5))
	_solid(r, Vector3(0.9, 0.8, 0.45), Vector3(-1.9, 0.4, 6.9), _m.wood)
	spots.drawer = Vector3(-1.9, 0.8, 7.0)
	_lamp(r, "bed_moon", Vector3(1.2, 1.8, 9.2), Color(0.55, 0.65, 0.95), 0.6, 5.0)


# ---------------------------------------------------------------------------
# his own room (the opening), far from the flat: x in [38, 41.6], z in [0, 4]
# ---------------------------------------------------------------------------
func _home() -> void:
	var r := Node3D.new()
	r.name = "Home"
	add_child(r)
	var ox := 38.0
	var poor := _std("plaster", 0.7, Color(0.62, 0.6, 0.55))
	_room(r, ox, ox + 3.6, 0.0, 4.0, poor, _m.floor, [["z0", ox + 2.5, ox + 3.4, 2.1]])
	_door(r, "home_door", Vector3(ox + 2.5, 0.0, 0.0), 0.9, 0.0)
	_interact(r, "home_door", "ACT_LEAVE", Vector3(ox + 2.95, 1.0, 0.15), Vector3(0.9, 2.0, 0.3))
	# narrow bed, a table with the landline, an old electric piano, a chair
	_solid(r, Vector3(0.9, 0.45, 2.0), Vector3(ox + 0.5, 0.225, 2.9), _m.wood)
	_solid(r, Vector3(0.85, 0.15, 1.9), Vector3(ox + 0.5, 0.52, 2.9), _m.sheet)
	_solid(r, Vector3(1.0, 0.75, 0.6), Vector3(ox + 2.9, 0.375, 3.6), _m.wood)
	_phone(r, Vector3(ox + 2.7, 0.76, 3.6))
	_interact(r, "home_phone", "ACT_PHONE", Vector3(ox + 2.7, 0.86, 3.6), Vector3(0.4, 0.3, 0.4))
	spots.home_phone = Vector3(ox + 2.7, 0.86, 3.6)
	# dark glasses on the table, the cane against the wall by the door
	var gl := _solid(r, Vector3(0.14, 0.03, 0.05), Vector3(ox + 3.15, 0.77, 3.5), _m.ebony, 0.0, false)
	gl.name = "Glasses"
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
	_solid(r, Vector3(1.2, 0.8, 0.4), Vector3(ox + 0.25 + 0.6, 0.4, 0.3), _m.lacquer)
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.0, 1.2)
	win.mesh = wq
	win.material_override = window_mat
	win.position = Vector3(ox - 0.1, 1.5, 2.0)
	win.rotation.y = PI * 0.5
	r.add_child(win)
	_lamp(r, "home_lamp", Vector3(ox + 3.0, 1.3, 3.55), Color(1.0, 0.68, 0.4), 0.9, 5.0)
	spots.home_start = Vector3(ox + 1.6, 0.0, 1.6)
	spots.home_out = Vector3(ox + 2.95, 0.0, 0.6)
