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
	m.albedo_texture = _tex("%s_%s_albedo" % [who, part])
	var n := _tex("%s_%s_normal" % [who, part])
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = normal_scale
	var r := _tex("%s_%s_rough" % [who, part])
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _apply_materials() -> void:
	var dead := who == "woman"
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
