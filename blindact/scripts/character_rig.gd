class_name CharacterRig
extends Node3D
## One of the people of the night (assets/models/<who>.glb, MakeHuman
## skeleton). Poses are written as limb directions in character space
## (+Y up, +Z the way he faces, +X his left), e.g. "the right forearm points
## forward", or as rotations of the trunk about the character axes; they are
## solved into bone rotations once and blended between at runtime.

signal pose_reached(name: String)

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
		"spine01": {"rot": Vector3(28, 0, 0)}, "spine03": {"rot": Vector3(10, 0, 0)},
		"neck01": {"rot": Vector3(-28, 0, 0)},
		"upperarm01.L": {"dir": Vector3(0.18, -0.9, -0.45)}, "upperarm01.R": {"dir": Vector3(-0.18, -0.9, -0.45)},
		"lowerarm01.L": {"dir": Vector3(-0.35, -0.3, -0.9)}, "lowerarm01.R": {"dir": Vector3(0.35, -0.3, -0.9)},
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
var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var current := ""
var _solved := {}          # pose name -> {bone_idx: Quaternion}
var _from := {}
var _to := {}
var _t := 1.0
var _len := 0.0
var _target_name := ""


func setup(p_who: String) -> void:
	who = p_who
	var path := "res://assets/models/%s.glb" % who
	if not ResourceLoader.exists(path):
		push_warning("missing model " + path)
		return
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	add_child(inst)
	skel = _find_skeleton(inst)
	_collect_meshes(inst)
	# MakeHuman's origin is at the hips: stand the model on y = 0
	var low := 0.0
	for m: MeshInstance3D in meshes:
		low = minf(low, m.get_aabb().position.y)
	inst.position.y = -low
	_apply_materials()
	set_pose("stand", 0.0)


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


func _apply_materials() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = _tex(who + "_albedo")
	skin.normal_enabled = true
	skin.normal_texture = _tex(who + "_normal")
	skin.normal_scale = 0.6
	skin.roughness_texture = _tex(who + "_rough")
	skin.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.35 if who == "man" else 0.15
	skin.subsurf_scatter_skin_mode = true
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var eye := StandardMaterial3D.new()
	eye.albedo_texture = _tex("eye_" + who)
	eye.roughness = 0.08
	eye.clearcoat_enabled = true
	eye.clearcoat = 1.0
	eye.clearcoat_roughness = 0.02
	var hair := StandardMaterial3D.new()
	hair.albedo_texture = _tex("hair_strands")
	hair.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	hair.alpha_hash_scale = 1.0
	hair.cull_mode = BaseMaterial3D.CULL_DISABLED
	hair.roughness = 0.45
	hair.anisotropy_enabled = true
	hair.anisotropy = 0.7
	for m: MeshInstance3D in meshes:
		var n := m.name.to_lower()
		var mat: Material = skin
		if "eye" in n:
			mat = eye
		elif "hair" in n:
			mat = hair
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, mat)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


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
	_from = {}
	for i in skel.get_bone_count():
		_from[i] = skel.get_bone_pose_rotation(i)
	_to = solved(name)
	_target_name = name
	_len = maxf(secs, 0.0)
	_t = 0.0 if secs > 0.0 else 1.0
	if secs <= 0.0:
		_apply(1.0)
		current = name


func _apply(k: float) -> void:
	for i: int in _to:
		var a: Quaternion = _from.get(i, _to[i])
		var b: Quaternion = _to[i]
		skel.set_bone_pose_rotation(i, a.slerp(b, k))


func _process(delta: float) -> void:
	if skel == null or _t >= 1.0:
		return
	_t = minf(1.0, _t + delta / maxf(_len, 0.001))
	_apply(smoothstep(0.0, 1.0, _t))
	if _t >= 1.0:
		current = _target_name
		pose_reached.emit(current)


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
