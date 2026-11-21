class_name CharacterRig
extends Node3D
## One of the people of the night (assets/models/<who>.glb, MakeHuman
## skeleton). Poses are written as limb directions in character space
## (+Y up, +Z the way he faces, +X his left), e.g. "the right forearm points
## forward", or as rotations of the trunk about the character axes; they are
## solved into bone rotations once and blended between at runtime.

signal pose_reached(name: String)
signal arrived                        # walk_path finished (and turned to face)
signal stepped(pos: Vector3, loud: float)

## Poses he stands on his feet in: the walk and the foot contact work in these.
const STANDING := ["stand", "lean_in", "offer", "knife_high", "knife_low", "lunge", "peer"]
## How hard his right hand closes in a pose (0 relaxed, 1 a fist round a handle).
const GRIP := {"knife_high": 1.0, "knife_low": 1.0, "lunge": 1.0, "offer": 0.55}

const POSES := {
	"stand": {
		"upperarm01.L": {"dir": Vector3(0.14, -1.0, 0.04)}, "upperarm01.R": {"dir": Vector3(-0.14, -1.0, 0.04)},
		"lowerarm01.L": {"dir": Vector3(0.06, -1.0, 0.16)}, "lowerarm01.R": {"dir": Vector3(-0.06, -1.0, 0.16)},
	},
	"sit": {
		"spine01": {"rot": Vector3(-8, 0, 0)},
		"upperleg01.L": {"dir": Vector3(0.1, -0.08, 1.0)}, "upperleg01.R": {"dir": Vector3(-0.1, -0.08, 1.0)},
		"lowerleg01.L": {"dir": Vector3(0.04, -1.0, 0.12)}, "lowerleg01.R": {"dir": Vector3(-0.04, -1.0, 0.12)},
		"upperarm01.L": {"dir": Vector3(0.3, -0.85, 0.3)}, "upperarm01.R": {"dir": Vector3(-0.3, -0.85, 0.3)},
		"lowerarm01.L": {"dir": Vector3(0.12, -0.2, 1.0)}, "lowerarm01.R": {"dir": Vector3(-0.12, -0.2, 1.0)},
	},
	"knife_high": {
		"spine01": {"rot": Vector3(6, 0, 0)},
		"upperarm01.R": {"dir": Vector3(-0.2, 0.9, 0.35)}, "lowerarm01.R": {"dir": Vector3(0.05, 0.8, -0.6)},
		"upperarm01.L": {"dir": Vector3(0.25, -0.7, 0.6)}, "lowerarm01.L": {"dir": Vector3(0.1, -0.1, 1.0)},
		"neck01": {"rot": Vector3(8, 0, 0)},
	},
	"lunge": {
		"spine01": {"rot": Vector3(20, 0, 0)},
		"upperarm01.R": {"dir": Vector3(-0.15, 0.25, 1.0)}, "lowerarm01.R": {"dir": Vector3(-0.05, 0.05, 1.0)},
		"upperarm01.L": {"dir": Vector3(0.3, -0.3, 0.9)}, "lowerarm01.L": {"dir": Vector3(0.1, -0.1, 1.0)},
		"upperleg01.L": {"dir": Vector3(0.06, -1.0, 0.45)}, "lowerleg01.L": {"dir": Vector3(0.02, -1.0, -0.05)},
		"upperleg01.R": {"dir": Vector3(-0.06, -1.0, -0.35)}, "lowerleg01.R": {"dir": Vector3(-0.02, -1.0, -0.55)},
		"neck01": {"rot": Vector3(-12, 0, 0)},
	},
	"lean_in": {
		"spine05": {"rot": Vector3(13, 0, 0)}, "spine04": {"rot": Vector3(9, 0, 0)},
		"spine03": {"rot": Vector3(8, 0, 0)}, "spine01": {"rot": Vector3(8, 0, 0)},
		"neck01": {"rot": Vector3(-26, 0, 0)},
		"upperarm01.L": {"dir": Vector3(0.18, -0.9, -0.45)}, "upperarm01.R": {"dir": Vector3(-0.18, -0.9, -0.45)},
		"lowerarm01.L": {"dir": Vector3(-0.35, -0.3, -0.9)}, "lowerarm01.R": {"dir": Vector3(0.35, -0.3, -0.9)},
	},
	"knife_low": {
		"upperarm01.R": {"dir": Vector3(-0.12, -0.95, 0.28)}, "lowerarm01.R": {"dir": Vector3(-0.05, -0.45, 0.9)},
		"upperarm01.L": {"dir": Vector3(0.14, -1.0, 0.04)}, "lowerarm01.L": {"dir": Vector3(0.06, -1.0, 0.16)},
	},
	"peer": {
		"spine05": {"rot": Vector3(24, 0, 0)}, "spine04": {"rot": Vector3(16, 0, 0)},
		"spine03": {"rot": Vector3(10, 0, 0)}, "spine01": {"rot": Vector3(6, 0, 0)},
		"neck01": {"rot": Vector3(-34, 0, 0)}, "head": {"rot": Vector3(-14, 0, 0)},
		"upperleg01.L": {"dir": Vector3(0.12, -1.0, 0.9)}, "upperleg01.R": {"dir": Vector3(-0.12, -1.0, 0.8)},
		"lowerleg01.L": {"dir": Vector3(0.02, -1.0, -0.55)}, "lowerleg01.R": {"dir": Vector3(-0.02, -1.0, -0.5)},
		"foot.L": {"rot": Vector3(-29, 0, 0)}, "foot.R": {"rot": Vector3(-27, 0, 0)},
		"upperarm01.L": {"dir": Vector3(0.2, -0.9, -0.3)}, "upperarm01.R": {"dir": Vector3(-0.2, -0.9, -0.3)},
		"lowerarm01.L": {"dir": Vector3(-0.2, -0.6, -0.7)}, "lowerarm01.R": {"dir": Vector3(0.2, -0.6, -0.7)},
	},
	"offer": {
		"upperarm01.R": {"dir": Vector3(-0.15, -0.45, 0.88)}, "lowerarm01.R": {"dir": Vector3(-0.05, -0.05, 1.0)},
		"upperarm01.L": {"dir": Vector3(0.14, -1.0, 0.04)}, "lowerarm01.L": {"dir": Vector3(0.06, -1.0, 0.16)},
	},
	"hang": {
		"upperarm01.L": {"dir": Vector3(0.1, -1.0, 0.02)}, "upperarm01.R": {"dir": Vector3(-0.1, -1.0, 0.02)},
		"lowerarm01.L": {"dir": Vector3(0.04, -1.0, 0.06)}, "lowerarm01.R": {"dir": Vector3(-0.04, -1.0, 0.06)},
		"neck01": {"rot": Vector3(30, 0, 18)}, "head": {"rot": Vector3(12, 0, 8)},
		"lowerleg01.L": {"dir": Vector3(0.0, -1.0, -0.12)}, "lowerleg01.R": {"dir": Vector3(0.0, -1.0, -0.08)},
		"foot.L": {"rot": Vector3(-55, 0, 0)}, "foot.R": {"rot": Vector3(-60, 0, 0)},
	},
	"lie": {
		"upperarm01.L": {"dir": Vector3(0.75, -0.65, 0.0)}, "upperarm01.R": {"dir": Vector3(-0.5, -0.85, 0.1)},
		"lowerarm01.L": {"dir": Vector3(0.5, -0.4, 0.75)}, "lowerarm01.R": {"dir": Vector3(-0.2, -1.0, 0.0)},
		"neck01": {"rot": Vector3(0, 35, 0)},
		"upperleg01.L": {"dir": Vector3(0.12, -1.0, 0.0)}, "lowerleg01.L": {"dir": Vector3(0.05, -1.0, 0.0)},
		"upperleg01.R": {"dir": Vector3(-0.05, -1.0, 0.25)}, "lowerleg01.R": {"dir": Vector3(-0.05, -1.0, -0.15)},
	},
	"slump": {
		"spine01": {"rot": Vector3(16, 0, -14)}, "spine03": {"rot": Vector3(6, 0, -8)},
		"neck01": {"rot": Vector3(32, 0, -30)}, "head": {"rot": Vector3(10, 0, -12)},
		"upperleg01.L": {"dir": Vector3(0.1, -0.08, 1.0)}, "upperleg01.R": {"dir": Vector3(-0.1, -0.08, 1.0)},
		"lowerleg01.L": {"dir": Vector3(0.04, -1.0, 0.12)}, "lowerleg01.R": {"dir": Vector3(-0.04, -1.0, 0.12)},
		"upperarm01.L": {"dir": Vector3(0.05, -0.6, 0.8)}, "upperarm01.R": {"dir": Vector3(-0.15, -0.6, 0.8)},
		"lowerarm01.L": {"dir": Vector3(0.0, -0.45, 1.0)}, "lowerarm01.R": {"dir": Vector3(-0.1, -0.45, 1.0)},
	},
}

var who := "man"
var tex_who := "man"         # whose textures (the head prop wears hers)
var body_shape: StaticBody3D
var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var current := ""
var _solved := {}          # pose name -> {bone_idx: Quaternion}
var _from := {}
var _to := {}
var _t := 1.0
var _len := 0.0
var _target_name := ""

# --- motion (see the bottom of the file)
var alive := true             # breathes, blinks, looks about; false for her
var quiet := false            # no footsteps: creeping up on you
var walk_speed := 1.05
var moving := false
var look_node: Node3D         # whose head he watches (null: his gaze drifts)
var look_target := Vector3.INF
var look_while_walking := false
var _inst: Node3D
var _inst_y0 := 0.0
var _base := {}               # bone -> Quaternion, the blended pose
var _prest := {}              # bone -> its parent's rest rotation (skeleton space)
var _idx := {}
var _dirty := true
var _path := PackedVector3Array()
var _pi := 0
var _speed := 0.0
var _max_speed := 1.05
var _face_pt := Vector3.INF
var _yaw := 0.0
var _yaw_v := 0.0
var _face_yaw := INF
var _turn_t := 0.0
var _arrive_after_turn := false
var _phase := 0.0
var _walk := 0.0
var _gait := 0.0              # the speed the cycle is drawn at
var _clock := 0.0
var _blink_at := 2.0
var _blink_t := 1.0
var _talk_until := -1.0
var _look := Vector2.ZERO
var _eyes := Vector2.ZERO
var _ground := 0.0
var _ground_w := 1.0
var _grip := 0.0
var _leg_len := 0.85
var _foot_rest := {}          # bone -> rest height (skeleton space)
var _flex := {}               # finger bone -> flexion axis (rest, skeleton space)
var _lid := {}                # lid bone -> [closing axis (rest), amount]
var _jaw_axis := Vector3.RIGHT
var _seed := 0.0


## p_who: the model (assets/models/<p_who>.glb); p_tex: whose textures it
## wears (default the same); collider: a body you bump into (people only).
func setup(p_who: String, p_tex := "", collider := true) -> void:
	who = p_who
	tex_who = p_tex if p_tex != "" else p_who
	var path := "res://assets/models/%s.glb" % who
	if not ResourceLoader.exists(path):
		push_warning("missing model " + path)
		return
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	add_child(inst)
	skel = _find_skeleton(inst)
	_collect_meshes(inst)
	# MakeHuman's origin is at the hips: stand the model on y = 0 (people only)
	if skel:
		var low := 0.0
		for m: MeshInstance3D in meshes:
			low = minf(low, m.get_aabb().position.y)
		inst.position.y = -low
		_inst = inst
		_inst_y0 = inst.position.y
	_apply_materials()
	if skel:
		_init_motion()
		set_pose("stand", 0.0)
	if not collider:
		return
	# a body you can bump into
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.85
	sb.add_child(cs)
	sb.collision_layer = 4
	add_child(sb)
	body_shape = sb


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)


func _tex(name: String) -> Texture2D:
	var p := "res://assets/textures/chars/%s.png" % name
	return load(p) if ResourceLoader.exists(p) else null


## A PBR material from assets/textures/chars/<who>_<part>_{albedo,normal,rough}.
func _pbr(part: String, normal_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("%s_%s_albedo" % [tex_who, part])
	var n := _tex("%s_%s_normal" % [tex_who, part])
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = normal_scale
	var r := _tex("%s_%s_rough" % [tex_who, part])
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _apply_materials() -> void:
	var dead := tex_who == "woman"
	var mats := {}
	var skin := _pbr("skin", 0.8)
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.12 if dead else 0.4
	skin.subsurf_scatter_skin_mode = true
	skin.metallic_specular = 0.38
	mats["body"] = skin
	var cloth := _pbr("cloth", 0.6 if dead else 0.35)
	cloth.rim_enabled = true
	cloth.rim = 0.25 if dead else 0.2
	cloth.rim_tint = 0.7
	cloth.metallic_specular = 0.4 if dead else 0.3
	mats["cloth"] = cloth
	var shoes := _pbr("shoes", 0.6)
	shoes.clearcoat_enabled = true
	shoes.clearcoat = 0.35
	shoes.clearcoat_roughness = 0.4
	mats["shoes"] = shoes
	# hair: solid where opaque (depth pre-pass), soft blended edges
	var hair := _pbr("hair", 0.5)
	hair.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	hair.alpha_scissor_threshold = 0.3
	hair.cull_mode = BaseMaterial3D.CULL_DISABLED
	hair.metallic_specular = 0.3
	mats["hair"] = hair
	for part in ["brows", "lashes"]:
		var fine := _pbr(part)
		fine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fine.cull_mode = BaseMaterial3D.CULL_DISABLED
		fine.roughness = 0.6
		fine.metallic_specular = 0.2
		mats[part] = fine
	var eye := _pbr("eyes")
	eye.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	eye.subsurf_scatter_enabled = true
	eye.subsurf_scatter_strength = 0.1
	mats["eyes"] = eye
	# the cornea: a wet film that only adds reflections and highlights
	var cornea := StandardMaterial3D.new()
	cornea.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cornea.albedo_color = Color.BLACK
	cornea.roughness = 0.04 if not dead else 0.3
	cornea.metallic_specular = 1.0 if not dead else 0.5
	cornea.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mats["cornea"] = cornea
	var teeth := _pbr("teeth")
	teeth.metallic_specular = 0.5
	mats["teeth"] = teeth
	# a severed neck: wet, dark meat
	var stump := StandardMaterial3D.new()
	stump.albedo_color = Color(0.2, 0.012, 0.016)
	stump.roughness = 0.12
	stump.metallic_specular = 0.7
	mats["stump"] = stump
	var tongue := _pbr("tongue")
	tongue.subsurf_scatter_enabled = true
	tongue.subsurf_scatter_strength = 0.2
	mats["tongue"] = tongue
	for m: MeshInstance3D in meshes:
		var part := String(m.name).get_slice("_", 1).to_lower()
		var mat: Material = mats.get(part, skin)
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, mat)
		var shadow := part not in ["brows", "lashes", "cornea", "eyes", "teeth", "tongue"]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _solve(spec: Dictionary) -> Dictionary:
	var result := {}
	var global := {}
	for i in skel.get_bone_count():
		var parent := skel.get_bone_parent(i)
		var rest: Transform3D = skel.get_bone_rest(i)
		var pb: Basis = global[parent] if parent >= 0 else Basis.IDENTITY
		var unposed: Basis = pb * rest.basis
		var target := unposed
		var bname := skel.get_bone_name(i)
		if spec.has(bname):
			var s: Dictionary = spec[bname]
			if s.has("dir"):
				var cur := unposed.y.normalized()
				var want := (s["dir"] as Vector3).normalized()
				if cur.dot(want) < 0.9999:
					var axis := cur.cross(want)
					if axis.length() < 1e-5:
						axis = unposed.x
					target = Basis(axis.normalized(), cur.angle_to(want)) * unposed
			elif s.has("rot"):
				var e: Vector3 = s["rot"]
				target = Basis.from_euler(e * (PI / 180.0)) * unposed
		global[i] = target
		result[i] = (pb.inverse() * target).get_rotation_quaternion()
	return result


func solved(name: String) -> Dictionary:
	if not _solved.has(name):
		_solved[name] = _solve(POSES.get(name, {}))
	return _solved[name]


## Blend to a pose over `secs` (0 = snap).
func set_pose(name: String, secs := 0.4) -> void:
	if skel == null:
		return
	_from = _base.duplicate()
	_to = solved(name)
	_target_name = name
	_len = maxf(secs, 0.0)
	_t = 0.0 if secs > 0.0 else 1.0
	if secs <= 0.0:
		for i: int in _to:
			_base[i] = _to[i]
		current = name
	_dirty = true


## The pose being blended to (current is only set once it is reached).
func target_pose() -> String:
	return _target_name


func _process(delta: float) -> void:
	if skel == null:
		return
	_clock += delta
	if _t < 1.0:
		_t = minf(1.0, _t + delta / maxf(_len, 0.001))
		var k := smoothstep(0.0, 1.0, _t)
		for i: int in _to:
			var a: Quaternion = _from.get(i, _to[i])
			_base[i] = a.slerp(_to[i], k)
		_dirty = true
		if _t >= 1.0:
			current = _target_name
			pose_reached.emit(current)
	_locomote(delta)
	if alive or _dirty or moving or _walk > 0.0:
		_compose(delta)
		_dirty = false


## World position of a bone (e.g. "head", "wrist.R").
func bone_pos(bone: String) -> Vector3:
	if skel == null:
		return global_position
	var i := skel.find_bone(bone)
	if i < 0:
		return global_position
	return skel.global_transform * skel.get_bone_global_pose(i).origin


## Attach a node to a bone (follows it).
func attach(bone: String, node: Node3D) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	ba.add_child(node)
	return ba


# ---------------------------------------------------------------------------
# motion: walking and turning, breathing, looking, blinking, talking, hands.
# Each frame the blended pose (_base) gets small rotations added on top:
#   _rc: about an axis in character space as he stands now (gross motion)
#   _rr: about an axis of the rest skeleton, carried along with the parent
#        bone (joint hinges: fingers, lids, jaw)
# Rest-pose axes are worked out from the skeleton itself, so they don't
# depend on how the bones happen to be rolled.
# ---------------------------------------------------------------------------
func _init_motion() -> void:
	_seed = randf() * 100.0
	_yaw = rotation.y
	for i in skel.get_bone_count():
		_idx[skel.get_bone_name(i)] = i
		var p := skel.get_bone_parent(i)
		_prest[i] = skel.get_bone_global_rest(p).basis.get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
		_base[i] = skel.get_bone_pose_rotation(i)
	if not _idx.has("foot.L"):
		return
	_leg_len = maxf(0.5, _rest_pos("upperleg01.L").y - _rest_pos("foot.L").y)
	for b: String in ["foot.L", "foot.R", "toe3-1.L", "toe3-1.R"]:
		if _idx.has(b):
			_foot_rest[_idx[b]] = _rest_pos(b).y
	# fingers curl towards the palm: the side the rest fingers already bend
	# to, and where the thumb is
	for side: String in ["L", "R"]:
		if not _idx.has("finger2-1." + side):
			continue
		var k2 := _rest_pos("finger2-1." + side)
		var k5 := _rest_pos("finger5-1." + side)
		var across := (k5 - k2).normalized()
		var hint := (_rest_pos("finger1-3." + side) - (k2 + k5) * 0.5) * 0.5
		for f in [2, 3, 4, 5]:
			var a := _rest_pos("finger%d-1.%s" % [f, side])
			var b := _rest_pos("finger%d-2.%s" % [f, side])
			var c := _rest_pos("finger%d-3.%s" % [f, side])
			var d1 := (b - a).normalized()
			var d2 := (c - b).normalized()
			hint += (d2 - d1 * d1.dot(d2)) * 4.0
		for f in [1, 2, 3, 4, 5]:
			for j in [1, 2, 3]:
				var bn := "finger%d-%d.%s" % [f, j, side]
				if not _idx.has(bn):
					continue
				var d := _rest_dir(bn)
				var n := d.cross(across).normalized()
				if n.dot(hint) < 0.0:
					n = -n
				_flex[bn] = _axis_towards(d, n)
	# lids: of each pair the bone pointing higher is the upper lid; it closes
	# downwards, the lower one rises a little
	for side: String in ["L", "R"]:
		var a := "orbicularis03." + side
		var b := "orbicularis04." + side
		if not (_idx.has(a) and _idx.has(b)):
			continue
		var up := a if _rest_dir(a).y > _rest_dir(b).y else b
		var lo := b if up == a else a
		_lid[up] = [_axis_towards(_rest_dir(up), Vector3.DOWN), 1.0]
		_lid[lo] = [_axis_towards(_rest_dir(lo), Vector3.DOWN), -0.35]
	if _idx.has("jaw"):
		_jaw_axis = _axis_towards(_rest_dir("jaw"), Vector3(0.0, -1.0, -0.35).normalized())


func _rest_pos(b: String) -> Vector3:
	return skel.get_bone_global_rest(_idx[b]).origin


func _rest_dir(b: String) -> Vector3:
	return skel.get_bone_global_rest(_idx[b]).basis.y.normalized()


## The axis a positive rotation about which turns direction d towards f.
static func _axis_towards(d: Vector3, f: Vector3) -> Vector3:
	var ax := d.cross(f)
	return ax.normalized() if ax.length() > 1e-4 else Vector3.RIGHT


func _rc(q: Dictionary, bone: String, axis: Vector3, ang: float) -> void:
	var i: int = _idx.get(bone, -1)
	if i >= 0 and absf(ang) > 1e-6:
		q[i] = Quaternion(axis, ang) * q.get(i, Quaternion.IDENTITY)


func _rr(q: Dictionary, bone: String, axis: Vector3, ang: float) -> void:
	_rc(q, bone, axis, ang)


func _noise(freq: float, off: float) -> float:
	var t := _clock + _seed
	return sin(t * freq * TAU + off) * 0.6 + sin(t * freq * 2.71 * TAU + off * 1.7) * 0.4


## Walk along `pts` (points on the floor) at `speed` m/s (default walk_speed),
## then turn to face `face` if given; `arrived` is emitted at the end.
func walk_path(pts: PackedVector3Array, speed := -1.0, face := Vector3.INF) -> void:
	_path = pts
	_pi = 0
	_max_speed = walk_speed if speed <= 0.0 else speed
	_face_pt = face
	_face_yaw = INF
	_arrive_after_turn = false
	moving = _path.size() > 0
	if not moving:
		_end_walk.call_deferred()


func stop() -> void:
	_path = PackedVector3Array()
	moving = false
	_face_yaw = INF


## Turn on the spot to face a point (small steps if it is a big turn).
func turn_to(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	_face_yaw = atan2(d.x, d.z)
	_turn_t = 0.0


func is_turning() -> bool:
	return _face_yaw != INF


## Move his jaw as if speaking for `secs`.
func talk(secs: float) -> void:
	_talk_until = _clock + secs


func _end_walk() -> void:
	moving = false
	if _face_pt != Vector3.INF:
		turn_to(_face_pt)
		if _face_yaw != INF:
			_arrive_after_turn = true
			return
	arrived.emit()


func _locomote(delta: float) -> void:
	var want := 0.0
	var goal := INF
	if moving:
		var pos := global_position
		var tgt := _path[_pi]
		var d := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
		var last := _pi == _path.size() - 1
		if d.length() < (0.04 if last else 0.3):
			_pi += 1
			if _pi >= _path.size():
				global_position = Vector3(tgt.x, pos.y, tgt.z)
				_end_walk()
			else:
				tgt = _path[_pi]
				d = Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
		if moving:
			var rem := d.length()
			for j in range(_pi + 1, _path.size()):
				rem += Vector2(_path[j].x - _path[j - 1].x, _path[j].z - _path[j - 1].z).length()
			goal = atan2(d.x, d.z)
			var err := absf(wrapf(goal - _yaw, -PI, PI))
			# slow down for the last steps and for sharp corners
			want = _max_speed * clampf(rem / 0.45, 0.35, 1.0) * clampf(1.25 - err / 1.4, 0.2, 1.0)
	elif _face_yaw != INF:
		goal = _face_yaw
	_speed = move_toward(_speed, want, delta * (2.2 if want > _speed else 3.5))
	if moving and _speed > 0.0:
		var pos := global_position
		var tgt := _path[_pi]
		var d := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
		global_position = pos + d.normalized() * minf(_speed * delta, d.length())
	# yaw: a critically damped spring, so turns start and finish softly
	if goal != INF:
		var err := wrapf(goal - _yaw, -PI, PI)
		var w := 7.5 if moving else 6.5
		_yaw_v += (w * w * err - 2.0 * w * _yaw_v) * delta
		_yaw_v = clampf(_yaw_v, -4.5, 4.5)
		_yaw += _yaw_v * delta
		rotation.y = _yaw
		if not moving:
			_turn_t += delta
			if (absf(err) < 0.05 and absf(_yaw_v) < 0.2) or _turn_t > 3.0:
				_face_yaw = INF
				_yaw_v = 0.0
				if _arrive_after_turn:
					_arrive_after_turn = false
					arrived.emit()
	else:
		_yaw = rotation.y
		_yaw_v = 0.0
	# the cycle runs at the walking speed, or as small steps while turning
	var eff := maxf(_speed, absf(_yaw_v) * 0.16 if not moving else 0.0)
	_walk = move_toward(_walk, clampf(eff / 0.3, 0.0, 1.0), delta * 3.5)
	if _walk <= 0.0:
		return
	_gait = move_toward(_gait, maxf(eff, 0.3), delta * 3.0)
	var amp := _amp(_gait)
	var stride := 4.0 * _leg_len * sin(amp)
	var prev := _phase
	_phase += TAU * _gait / maxf(stride, 0.2) * delta
	# a footfall each time a leg reaches the front of its swing
	var k0 := floori((prev - PI * 0.5) / PI)
	var k1 := floori((_phase - PI * 0.5) / PI)
	if k1 != k0 and _walk > 0.3 and not quiet:
		var foot := "foot.L" if posmod(k1, 2) == 0 else "foot.R"
		stepped.emit(bone_pos(foot), clampf(_gait / 1.1, 0.25, 1.8))


func _amp(v: float) -> float:
	var run := clampf((v - 1.6) / 0.8, 0.0, 1.0)
	return deg_to_rad(lerpf(8.0, 23.0, clampf(v / 1.3, 0.0, 1.0)) + 9.0 * run)


func _compose(delta: float) -> void:
	var qc := {}
	var qr := {}
	_grip = move_toward(_grip, float(GRIP.get(_target_name, 0.0)), delta * 4.0)
	if _walk > 0.0:
		_layer_walk(qc)
	if alive:
		_layer_idle(qc)
		_layer_look(qc, delta)
		_layer_face(qr, delta)
	_layer_hands(qr)
	# parents as they stood last frame, for the character-space rotations
	var pcur := {}
	for i: int in qc:
		var p := skel.get_bone_parent(i)
		pcur[i] = skel.get_bone_global_pose(p).basis.get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
	for i: int in _base:
		var q: Quaternion = _base[i]
		if qr.has(i):
			var pr: Quaternion = _prest[i]
			q = (pr.inverse() * qr[i] * pr) * q
		if qc.has(i):
			var pc: Quaternion = pcur[i]
			q = (pc.inverse() * qc[i] * pc) * q
		skel.set_bone_pose_rotation(i, q)
	_ground_feet(delta)


func _layer_walk(q: Dictionary) -> void:
	var w := _walk
	var v := _gait
	var run := clampf((v - 1.6) / 0.8, 0.0, 1.0)
	var amp := _amp(v)
	var arm_amp := deg_to_rad(lerpf(4.0, 15.0, clampf(v / 1.3, 0.0, 1.0)) + 16.0 * run)
	for s in 2:
		var side := "L" if s == 0 else "R"
		var ph := _phase + PI * s
		var sw := sin(ph)            # +1: thigh at the front of its swing
		var c := cos(ph)             # > 0 while the leg swings through
		_rc(q, "upperleg01." + side, Vector3.LEFT, amp * sw * w)
		var knee := 5.0 + (50.0 + 32.0 * run) * pow(maxf(0.0, c), 1.6) + 12.0 * maxf(0.0, -c) * maxf(0.0, sw)
		_rc(q, "lowerleg01." + side, Vector3.RIGHT, deg_to_rad(knee) * w)
		# toes up through the swing, pushing off at the back
		var ankle := -9.0 * pow(maxf(0.0, c), 2.0) + 15.0 * pow(maxf(0.0, -sw), 4.0)
		_rc(q, "foot." + side, Vector3.RIGHT, deg_to_rad(ankle) * w)
		# the arms swing against the legs, elbows a little bent (not the knife hand)
		var free := 1.0 - _grip * (1.0 if s == 1 else 0.6)
		_rc(q, "upperarm01." + side, Vector3.LEFT, -arm_amp * sw * w * free)
		var elbow := (8.0 + 12.0 * maxf(0.0, -sw) + 60.0 * run) * free
		_rc(q, "lowerarm01." + side, Vector3.LEFT, deg_to_rad(elbow) * w)
	# the hips turn with the leg that swings, the chest against them
	var twist := deg_to_rad(5.0 + 4.0 * run) * sin(_phase) * w
	_rc(q, "root", Vector3.UP, -twist)
	_rc(q, "spine04", Vector3.UP, twist * 0.6)
	_rc(q, "spine02", Vector3.UP, twist * 0.7)
	_rc(q, "root", Vector3(0, 0, 1), deg_to_rad(-2.0) * cos(_phase) * w)
	# leaning into the walk; the head keeps level
	_rc(q, "spine05", Vector3.RIGHT, deg_to_rad(3.0 + 10.0 * run) * w)
	_rc(q, "neck01", Vector3.RIGHT, deg_to_rad(-2.0 - 8.0 * run) * w)


func _layer_idle(q: Dictionary) -> void:
	var still := (1.0 - _walk) * _ground_w    # no weight shifting while seated
	# breathing: the chest lifts, the shoulders rise a little
	var br := sin((_clock + _seed) * TAU / 4.3)
	_rc(q, "spine03", Vector3.RIGHT, deg_to_rad(-1.2) * br)
	_rc(q, "spine01", Vector3.RIGHT, deg_to_rad(-0.6) * br)
	_rc(q, "clavicle.L", Vector3(0, 0, 1), deg_to_rad(1.3) * br)
	_rc(q, "clavicle.R", Vector3(0, 0, 1), deg_to_rad(-1.3) * br)
	_rc(q, "neck01", Vector3.RIGHT, deg_to_rad(0.7) * br)
	# shifting his weight from foot to foot; never quite still
	var sway := _noise(0.09, 0.0) * still
	_rc(q, "root", Vector3(0, 0, 1), deg_to_rad(1.4) * sway)
	_rc(q, "spine04", Vector3(0, 0, 1), deg_to_rad(-1.6) * sway)
	_rc(q, "root", Vector3.UP, deg_to_rad(1.6) * _noise(0.06, 3.0) * still)
	_rc(q, "upperarm01.L", Vector3.LEFT, deg_to_rad(1.5) * _noise(0.08, 5.0) * still * (1.0 - _grip))
	_rc(q, "upperarm01.R", Vector3.LEFT, deg_to_rad(1.5) * _noise(0.08, 9.0) * still * (1.0 - _grip))


func _layer_look(q: Dictionary, delta: float) -> void:
	# with nothing to watch his gaze drifts
	var goal := Vector2(_noise(0.045, 7.0) * 0.16, 0.05 + _noise(0.04, 2.0) * 0.06)
	var tgt := look_target
	if is_instance_valid(look_node):
		tgt = look_node.global_position
	if tgt != Vector3.INF and (look_while_walking or _walk < 0.5):
		var hi: int = _idx.get("head", -1)
		if hi >= 0:
			var hp := skel.global_transform * skel.get_bone_global_pose(hi).origin
			var d := global_basis.orthonormalized().inverse() * (tgt - hp)
			var yaw := atan2(d.x, d.z)
			if absf(yaw) < 2.0:
				goal = Vector2(clampf(yaw, -1.25, 1.25), clampf(atan2(-d.y, Vector2(d.x, d.z).length()), -0.55, 0.7))
	_look = _look.lerp(goal, 1.0 - exp(-4.0 * delta))
	# the eyes get there first, then the head catches up and they settle
	var e := Vector2(clampf(goal.x - _look.x, -0.45, 0.45), clampf(goal.y - _look.y, -0.3, 0.35))
	e += Vector2(_noise(0.7, 1.0), _noise(0.6, 4.0)) * 0.012
	_eyes = _eyes.lerp(e, 1.0 - exp(-20.0 * delta))
	var y := _look.x
	var p := _look.y
	_rc(q, "neck01", Vector3.UP, y * 0.2)
	_rc(q, "neck02", Vector3.UP, y * 0.15)
	_rc(q, "neck03", Vector3.UP, y * 0.15)
	_rc(q, "head", Vector3.UP, y * 0.5)
	_rc(q, "neck01", Vector3.RIGHT, p * 0.25)
	_rc(q, "neck03", Vector3.RIGHT, p * 0.25)
	_rc(q, "head", Vector3.RIGHT, p * 0.5)
	for eye: String in ["eye.L", "eye.R"]:
		_rc(q, eye, Vector3.UP, _eyes.x)
		_rc(q, eye, Vector3.RIGHT, _eyes.y)


func _layer_face(q: Dictionary, delta: float) -> void:
	# a blink every few seconds (two in a row now and then)
	_blink_t += delta
	if _clock > _blink_at:
		_blink_t = 0.0
		_blink_at = _clock + (0.35 if randf() < 0.15 else randf_range(2.2, 5.5))
	var b := clampf(1.0 - absf(_blink_t - 0.075) / 0.075, 0.0, 1.0)
	for lid: String in _lid:
		_rr(q, lid, _lid[lid][0], deg_to_rad(30.0) * b * float(_lid[lid][1]))
	if _clock < _talk_until:
		var o := 0.5 + 0.5 * sin(_clock * 13.0 + sin(_clock * 4.3) * 2.2)
		_rr(q, "jaw", _jaw_axis, deg_to_rad(10.0) * o * o)
		_rc(q, "head", Vector3.RIGHT, deg_to_rad(1.2) * sin(_clock * 6.1))


func _layer_hands(q: Dictionary) -> void:
	# a relaxed hand is never flat; gripping, the fingers close round it
	for side: String in ["L", "R"]:
		for f in [1, 2, 3, 4, 5]:
			var relaxed := [0.0, 6.0, 10.0, 14.0, 18.0, 22.0][f] as float
			for j in [1, 2, 3]:
				var bn := "finger%d-%d.%s" % [f, j, side]
				if not _flex.has(bn):
					continue
				var fist := ([0.0, 62.0, 88.0, 52.0][j] as float) * (0.5 if f == 1 else 1.0)
				var r := relaxed * ([0.0, 1.0, 1.3, 0.85][j] as float)
				_rr(q, bn, _flex[bn], deg_to_rad(lerpf(r, fist, _grip if side == "R" else 0.0)))


## Keep the lower foot on the floor (the body rises and falls as he walks).
func _ground_feet(delta: float) -> void:
	var on_feet := _target_name in STANDING and (current in STANDING or _t >= 1.0)
	_ground_w = move_toward(_ground_w, 1.0 if on_feet else 0.0, delta * 3.0)
	if _foot_rest.is_empty() or _inst == null:
		return
	var low := INF
	for i: int in _foot_rest:
		low = minf(low, skel.get_bone_global_pose(i).origin.y - float(_foot_rest[i]))
	var sy := skel.global_basis.get_scale().y / maxf(global_basis.get_scale().y, 1e-4)
	var off := -low * sy * _ground_w
	_ground = lerpf(_ground, off, 1.0 - exp(-30.0 * delta))
	_inst.position.y = _inst_y0 + _ground


## Her head is gone (it is on the piano now): the head collapses into the
## neck and a dark wet stump caps it.
func hide_head() -> void:
	if skel == null or not _idx.has("head"):
		return
	skel.set_bone_pose_scale(_idx["head"], Vector3.ONE * 0.001)
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.052
	sm.height = 0.045
	cap.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.012, 0.016)
	mat.roughness = 0.12
	mat.metallic_specular = 0.7
	cap.material_override = mat
	cap.position = Vector3(0.0, 0.045, 0.0)
	attach("neck03", cap)
