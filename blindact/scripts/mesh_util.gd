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


## A worn concrete step, front (riser) facing -z, tread on top at y = height.
## The nosing is rounded, chipped here and there, and the tread is dished
## where people have walked for decades. UVs in metres.
static func worn_step(width: float, height: float, run: float, seed: int, wear := 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := 0.018
	# profile (y, z) with outward normals
	var prof: Array = []      # [Vector2(y, z), Vector2 normal(y, z)]
	prof.append([Vector2(0.0, 0.0), Vector2(0.0, -1.0)])
	prof.append([Vector2(height - r, 0.0), Vector2(0.0, -1.0)])
	for i in range(1, 6):
		var t := PI * 0.5 * float(i) / 5.0
		prof.append([Vector2(height - r + r * sin(t), r - r * cos(t)), Vector2(sin(t), -cos(t))])
	for k in range(1, 6):
		prof.append([Vector2(height, r + (run - r) * float(k) / 5.0), Vector2(1.0, 0.0)])
	var nx := 14
	var chips: Array = []
	for c in rng.randi_range(1, 4):
		chips.append([rng.randf_range(-width * 0.45, width * 0.45), rng.randf_range(0.02, 0.07), rng.randf_range(0.006, 0.018)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []   # grid of positions [ix][ip]
	var nrm := []
	for ix in nx + 1:
		var x := -width * 0.5 + width * float(ix) / nx
		var col_p: Array[Vector3] = []
		var col_n: Array[Vector3] = []
		for ip in prof.size():
			var yz: Vector2 = prof[ip][0]
			var nn: Vector2 = prof[ip][1]
			var y := yz.x
			var z := yz.y
			# dished tread in the middle of the walking line
			if nn.x > 0.5 and y >= height - 0.001:
				y -= wear * 0.009 * exp(-pow(x / (0.32 * width), 2.0)) * exp(-pow((z - 0.06) / 0.12, 2.0))
			# chips bitten out of the nosing
			if ip >= 1 and ip <= 6:
				for ch: Array in chips:
					var d := absf(x - float(ch[0])) / float(ch[1])
					if d < 1.0:
						var bite := float(ch[2]) * (1.0 - d * d)
						y -= bite * nn.x
						z += bite * -nn.y
			col_p.append(Vector3(x, y, z))
			col_n.append(Vector3(0.0, nn.x, nn.y).normalized())
		pts.append(col_p)
		nrm.append(col_n)
	var vlen: Array[float] = [0.0]
	for ip in range(1, prof.size()):
		vlen.append(vlen[ip - 1] + (prof[ip][0] as Vector2).distance_to(prof[ip - 1][0]))
	for ix in nx:
		for ip in prof.size() - 1:
			var a: Vector3 = pts[ix][ip]
			var b: Vector3 = pts[ix + 1][ip]
			var c: Vector3 = pts[ix + 1][ip + 1]
			var d: Vector3 = pts[ix][ip + 1]
			var na: Vector3 = nrm[ix][ip]
			var nb: Vector3 = nrm[ix + 1][ip]
			var nc: Vector3 = nrm[ix + 1][ip + 1]
			var nd: Vector3 = nrm[ix][ip + 1]
			var ua := Vector2(a.x, vlen[ip])
			var ub := Vector2(b.x, vlen[ip])
			var uc := Vector2(c.x, vlen[ip + 1])
			var ud := Vector2(d.x, vlen[ip + 1])
			for tri: Array in [[a, na, ua, b, nb, ub, c, nc, uc], [a, na, ua, c, nc, uc, d, nd, ud]]:
				for k in 3:
					st.set_normal(tri[k * 3 + 1])
					st.set_uv(tri[k * 3 + 2])
					st.add_vertex(tri[k * 3])
	# side caps and the back face
	for side: int in [0, nx]:
		var sgn := -1.0 if side == 0 else 1.0
		var col: Array = pts[side]
		var cen := Vector3(col[0].x, height * 0.5, run * 0.5)
		var ring: Array = col.duplicate()
		ring.append(Vector3(col[0].x, 0.0, run))
		for i in ring.size():
			var p0: Vector3 = ring[i]
			var p1: Vector3 = ring[(i + 1) % ring.size()]
			var tri := [cen, p0, p1] if sgn > 0.0 else [cen, p1, p0]
			for q: Vector3 in tri:
				st.set_normal(Vector3(sgn, 0.0, 0.0))
				st.set_uv(Vector2(q.z, q.y))
				st.add_vertex(q)
	var bl := Vector3(-width * 0.5, 0.0, run)
	var br := Vector3(width * 0.5, 0.0, run)
	var tr := Vector3(width * 0.5, height, run)
	var tl := Vector3(-width * 0.5, height, run)
	for q: Vector3 in [bl, tl, tr, bl, tr, br]:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(q.x, q.y))
		st.add_vertex(q)
	st.generate_tangents()
	return st.commit()
