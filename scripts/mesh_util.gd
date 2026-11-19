class_name MeshUtil
extends RefCounted
## Small procedural mesh helpers used by the corridor builder.
## Godot uses clockwise winding for front faces.


## Axis-aligned box.
## unit_uv = true  -> every face gets 0..1 UVs (u right, v down, as seen from outside)
## unit_uv = false -> UVs in metres; u follows the box's longest axis when it lies in the face
static func box(size: Vector3, unit_uv: bool = false, uv_offset := Vector2.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var long_axis := 0
	if size.y >= size.x and size.y >= size.z:
		long_axis = 1
	elif size.z >= size.x and size.z >= size.y:
		long_axis = 2
	var la := Vector3.ZERO
	la[long_axis] = 1.0
	for n: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var r: Vector3
		var d: Vector3
		if absf(n.y) > 0.5:
			r = Vector3.RIGHT
			d = Vector3.BACK if n.y > 0.0 else Vector3.FORWARD
		else:
			r = Vector3.UP.cross(n)
			d = Vector3.DOWN
		var hu := absf(h.dot(r))
		var hv := absf(h.dot(d))
		var c := h * n
		var corners := [c - r * hu - d * hv, c + r * hu - d * hv, c + r * hu + d * hv, c - r * hu + d * hv]
		# uv axes
		var ua := r
		var va := d
		if not unit_uv and absf(d.dot(la)) > 0.5:
			ua = la
			va = r
		var uvs: Array[Vector2] = []
		for p: Vector3 in corners:
			if unit_uv:
				uvs.append(Vector2(p.dot(r) / (2.0 * hu) + 0.5, p.dot(d) / (2.0 * hv) + 0.5))
			else:
				uvs.append(Vector2(p.dot(ua), p.dot(va)) + uv_offset)
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	st.generate_tangents()
	return st.commit()


## Rectangle swept along a polyline lying in a plane whose normal is `side`.
## Used for the curved goose-neck slats of the benches. UV: u along length (m), v across.
static func swept_rect(points: PackedVector3Array, width: float, thick: float, side := Vector3.BACK) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_pts := points.size()
	var frames: Array = []
	var dist := 0.0
	for i in n_pts:
		var t: Vector3
		if i == 0:
			t = (points[1] - points[0]).normalized()
		elif i == n_pts - 1:
			t = (points[i] - points[i - 1]).normalized()
		else:
			t = (points[i + 1] - points[i - 1]).normalized()
		var nrm := side.cross(t).normalized()
		if i > 0:
			dist += points[i].distance_to(points[i - 1])
		frames.append([points[i], nrm, dist])
	var b := side.normalized()
	# 4 faces: +nrm, -nrm, +b, -b
	var offs := [
		[Vector2(1, -1), Vector2(1, 1), 0],
		[Vector2(-1, 1), Vector2(-1, -1), 1],
		[Vector2(1, 1), Vector2(-1, 1), 2],
		[Vector2(-1, -1), Vector2(1, -1), 3],
	]
	for face in offs:
		var a0: Vector2 = face[0]
		var a1: Vector2 = face[1]
		var fid: int = face[2]
		for i in n_pts - 1:
			var f0: Array = frames[i]
			var f1: Array = frames[i + 1]
			var quad: Array[Vector3] = []
			var nrms: Array[Vector3] = []
			var uvq: Array[Vector2] = []
			for k in 4:
				var fr: Array = f0 if k < 2 else f1
				var a: Vector2 = a0 if (k == 0 or k == 3) else a1
				var p: Vector3 = fr[0]
				var nn: Vector3 = fr[1]
				quad.append(p + nn * a.x * thick * 0.5 + b * a.y * width * 0.5)
				var fn: Vector3
				match fid:
					0: fn = nn
					1: fn = -nn
					2: fn = b
					_: fn = -b
				nrms.append(fn)
				uvq.append(Vector2(fr[2], (a.y * 0.5 + 0.5) * width + a.x * 0.01))
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrms[idx])
				st.set_uv(uvq[idx])
				st.add_vertex(quad[idx])
	st.generate_tangents()
	return st.commit()


## Tube along a polyline with per-point radius. UV: u around (0..uv_around), v along (metres).
## Optional per-point jitter makes bark lumpy.
static func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int = 10, uv_around := 1.0, lumpy := 0.0, seed := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n_pts := points.size()
	# parallel transport frames
	var tangents: Array[Vector3] = []
	for i in n_pts:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n_pts - 1:
			t = points[i] - points[i - 1]
		else:
			t = points[i + 1] - points[i - 1]
		tangents.append(t.normalized())
	var nrm := tangents[0].cross(Vector3.UP)
	if nrm.length() < 0.1:
		nrm = tangents[0].cross(Vector3.RIGHT)
	nrm = nrm.normalized()
	var rings: Array = []
	var dist := 0.0
	var lump_phase := rng.randf() * 10.0
	for i in n_pts:
		if i > 0:
			var axis := tangents[i - 1].cross(tangents[i])
			if axis.length() > 1e-5:
				var ang := tangents[i - 1].angle_to(tangents[i])
				nrm = nrm.rotated(axis.normalized(), ang)
			dist += points[i].distance_to(points[i - 1])
		var bin := tangents[i].cross(nrm).normalized()
		var ring: Array = []
		for s in sides + 1:
			var th := TAU * float(s) / float(sides)
			var dirv := (nrm * cos(th) + bin * sin(th)).normalized()
			var r := radii[i]
			if lumpy > 0.0:
				r *= 1.0 + lumpy * (sin(th * 3.0 + lump_phase + dist * 1.7) * 0.5 + sin(th * 7.0 - dist * 3.1) * 0.25)
			ring.append([points[i] + dirv * r, dirv, Vector2(float(s) / float(sides) * uv_around, dist)])
		rings.append(ring)
	for i in n_pts - 1:
		for s in sides:
			var a: Array = rings[i][s]
			var b2: Array = rings[i][s + 1]
			var c: Array = rings[i + 1][s + 1]
			var d: Array = rings[i + 1][s]
			for v: Array in [a, d, c, a, c, b2]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	st.generate_tangents()
	return st.commit()


## A camera-facing-ish leaf card: a quad centred on the origin.
static func quad(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-w * 0.5, h * 0.5, 0), Vector3(w * 0.5, h * 0.5, 0), Vector3(w * 0.5, -h * 0.5, 0), Vector3(-w * 0.5, -h * 0.5, 0)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uvs[idx])
		st.add_vertex(pts[idx])
	st.generate_tangents()
	return st.commit()


## Thin hanging strand: 3-sided prism from y=0 down to y=-1 with a slight kink.
static func strand(segments: int = 5, radius: float = 0.0025) -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segments + 1:
		var t := float(i) / float(segments)
		pts.append(Vector3(sin(t * 2.3) * 0.03 * t, -t, cos(t * 1.7) * 0.02 * t))
		radii.append(radius * (1.0 - 0.6 * t))
	return tube(pts, radii, 3, 1.0)
