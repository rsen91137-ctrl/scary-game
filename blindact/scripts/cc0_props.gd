class_name CC0Props
extends RefCounted
## The Poly Haven CC0 models in assets/cc0/models (see docs/CREDITS_CC0.md),
## ready for instancing. A file with several variants lays them out side by
## side; each variant comes back as its own mesh, re-centred so its origin is
## the middle of its base.

static var _cache := {}


## [{"mesh": Mesh, "offset": Transform3D, "height": float}, ...] for model `id`.
static func variants(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out := []
	var path := "res://assets/cc0/models/%s/%s_1k.gltf" % [id, id]
	if not ResourceLoader.exists(path):
		_cache[id] = out
		return out
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := _to_root(mi, root)
		var box := xf * mi.mesh.get_aabb()
		var base := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
		out.append({"mesh": mi.mesh, "offset": Transform3D(xf.basis, xf.origin - base), "height": box.size.y,
			"radius": maxf(box.size.x, box.size.z) * 0.5})
	root.free()
	_cache[id] = out
	return out


static func _to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Scatter model `id` at `places` (Transform3Ds in `parent`'s space: position
## on the ground, rotation, scale), one MultiMeshInstance3D per variant; each
## place picks a variant by its index. Returns the instances made.
static func scatter(parent: Node3D, id: String, places: Array, shadows := true, vis_range := 60.0) -> Array:
	var vs := variants(id)
	var made := []
	if vs.is_empty() or places.is_empty():
		return made
	var buckets := []
	for v in vs:
		buckets.append([])
	for i in places.size():
		buckets[i % vs.size()].append(places[i])
	for k in vs.size():
		var list: Array = buckets[k]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = vs[k].mesh
		mm.instance_count = list.size()
		var off: Transform3D = vs[k].offset
		for j in list.size():
			mm.set_instance_transform(j, (list[j] as Transform3D) * off)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "%s_%d" % [id, k]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_end_margin = vis_range * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		made.append(mmi)
	return made


## A single copy of one variant (for hero pieces: a fallen trunk across the
## path, a street lamp), with an optional simple box collider.
static func place(parent: Node3D, id: String, xf: Transform3D, variant := 0, collide := false) -> Node3D:
	var vs := variants(id)
	if vs.is_empty():
		return null
	var v: Dictionary = vs[variant % vs.size()]
	var mi := MeshInstance3D.new()
	mi.mesh = v.mesh
	mi.transform = xf * (v.offset as Transform3D)
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var box: AABB = v.mesh.get_aabb()
		bs.size = box.size
		cs.shape = bs
		cs.position = box.get_center()
		sb.add_child(cs)
		mi.add_child(sb)
	return mi
