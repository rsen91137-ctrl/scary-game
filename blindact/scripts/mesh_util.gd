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


## A surface of revolution about +Y whose footprint is a rounded rectangle
## (superellipse with half-extents `half` and exponent `e`; e = 2 is an
## ellipse, larger is boxier). `profile` points are (scale, y): scale 1 lands
## on the footprint, 0 on the axis. Walk the profile up the outside and back
## down the inside to get a basin (tub, sink, bowl); normals point away from
## the material on both sides. Normals come from the surface itself, so there
## is no seam where the revolution closes.
static func lathe(profile: PackedVector2Array, half := Vector2.ONE, e := 2.0, segments := 40) -> ArrayMesh:
	var np := profile.size()
	var dirs: Array[Vector2] = []
	for j in segments:
		var t := TAU * float(j) / float(segments)
		var c := cos(t)
		var s := sin(t)
		dirs.append(Vector2(half.x * signf(c) * pow(absf(c), 2.0 / e), half.y * signf(s) * pow(absf(s), 2.0 / e)))
	var grid: Array = []
	for i in np:
		var row: Array[Vector3] = []
		for j in segments:
			row.append(Vector3(dirs[j].x * profile[i].x, profile[i].y, dirs[j].y * profile[i].x))
		grid.append(row)
	var arc := PackedFloat32Array([0.0])
	for i in range(1, np):
		arc.append(arc[i - 1] + profile[i].distance_to(profile[i - 1]))
	var normals: Array = []
	for i in np:
		var row: Array[Vector3] = []
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, np - 1)
		var tp := profile[i1] - profile[i0]          # profile tangent (scale, y)
		for j in segments:
			var n: Vector3
			if absf(profile[i].x) < 1e-4:
				n = Vector3(0.0, -signf(tp.x), 0.0)
			else:
				var dth: Vector3 = grid[i][(j + 1) % segments] - grid[i][(j - 1 + segments) % segments]
				var ds: Vector3 = grid[i1][j] - grid[i0][j]
				n = ds.cross(dth)
				if n.length() < 1e-9:
					n = Vector3(0.0, -signf(tp.x), 0.0)
			row.append(n.normalized())
		normals.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in np - 1:
		for j in segments:
			var j2 := (j + 1) % segments
			var u0 := float(j) / float(segments)
			var u1 := float(j + 1) / float(segments)
			var quad := [[i, j, u0], [i + 1, j, u0], [i + 1, j2, u1], [i, j2, u1]]
			for tri: Array in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
				var p0: Vector3 = grid[tri[0][0]][tri[0][1]]
				var p1: Vector3 = grid[tri[1][0]][tri[1][1]]
				var p2: Vector3 = grid[tri[2][0]][tri[2][1]]
				var nsum: Vector3 = normals[tri[0][0]][tri[0][1]] + normals[tri[1][0]][tri[1][1]] + normals[tri[2][0]][tri[2][1]]
				var order := [tri[0], tri[1], tri[2]]
				# Godot's front faces wind clockwise: the cross product points into the surface
				if (p1 - p0).cross(p2 - p0).dot(nsum) > 0.0:
					order = [tri[0], tri[2], tri[1]]
				for v: Array in order:
					st.set_normal(normals[v[0]][v[1]])
					st.set_uv(Vector2(v[2] * 3.0, arc[v[0]]))
					st.add_vertex(grid[v[0]][v[1]])
	st.generate_tangents()
	return st.commit()


static var _rb_cache := {}


## A box with rounded edges and corners (radius r): every face is a grid
## whose border rows are cut at equal angles round the rounding, so the
## bevels catch the light like real edges. UVs in metres, u along the face's
## longer side. Meshes are cached by size.
static func rounded_box(size: Vector3, r: float, seg := 3) -> ArrayMesh:
	var key := "%.4f,%.4f,%.4f,%.4f,%d" % [size.x, size.y, size.z, r, seg]
	if _rb_cache.has(key):
		return _rb_cache[key]
	var h := size * 0.5
	r = clampf(r, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.95)
	var inner := h - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var b := (axis + 1) % 3
			var c := (axis + 2) % 3
			var cb := _rb_coords(inner[b], r, seg)
			var cc := _rb_coords(inner[c], r, seg)
			var long_b := size[b] >= size[c]
			var pts: Array = []
			var nrm: Array = []
			var uvs: Array = []
			for i in cb.size():
				var prow: Array = []
				var nrow: Array = []
				var urow: Array = []
				for j in cc.size():
					var q := Vector3.ZERO
					q[axis] = sgn * h[axis]
					q[b] = cb[i]
					q[c] = cc[j]
					var cl := q.clamp(-inner, inner)
					var n := (q - cl).normalized()
					prow.append(cl + n * r)
					nrow.append(n)
					urow.append(Vector2(cb[i], -cc[j]) if long_b else Vector2(cc[j], -cb[i]))
				pts.append(prow)
				nrm.append(nrow)
				uvs.append(urow)
			for i in cb.size() - 1:
				for j in cc.size() - 1:
					var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
					for tri: Array in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
						var p0: Vector3 = pts[tri[0][0]][tri[0][1]]
						var p1: Vector3 = pts[tri[1][0]][tri[1][1]]
						var p2: Vector3 = pts[tri[2][0]][tri[2][1]]
						var fn: Vector3 = nrm[tri[0][0]][tri[0][1]] + nrm[tri[1][0]][tri[1][1]] + nrm[tri[2][0]][tri[2][1]]
						var order := tri
						if (p1 - p0).cross(p2 - p0).dot(fn) > 0.0:
							order = [tri[0], tri[2], tri[1]]
						for v: Array in order:
							st.set_normal(nrm[v[0]][v[1]])
							st.set_uv(uvs[v[0]][v[1]])
							st.add_vertex(pts[v[0]][v[1]])
	st.generate_tangents()
	var mesh := st.commit()
	_rb_cache[key] = mesh
	return mesh


static func _rb_coords(inner: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(seg, 0, -1):
		out.append(-inner - r * tan(PI * 0.25 * float(k) / float(seg)))
	out.append(-inner)
	out.append(inner)
	for k in range(1, seg + 1):
		out.append(inner + r * tan(PI * 0.25 * float(k) / float(seg)))
	return out


## A moulding: the 2D profile (x = out from the wall, y = up), walked with
## the material on its left, swept along X for `length` (centred). Shading is
## smooth across shallow profile corners and crisp across sharp ones.
static func extrude(profile: PackedVector2Array, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var segn: Array[Vector2] = []
	for i in n - 1:
		var t := profile[i + 1] - profile[i]
		segn.append(Vector2(t.y, -t.x).normalized())
	var hx := length * 0.5
	var arc := 0.0
	for i in n - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var na := segn[i]
		var nb := segn[i]
		if i > 0 and segn[i - 1].dot(segn[i]) > 0.7:
			na = (segn[i - 1] + segn[i]).normalized()
		if i < n - 2 and segn[i + 1].dot(segn[i]) > 0.7:
			nb = (segn[i + 1] + segn[i]).normalized()
		var sl := a.distance_to(b)
		var v := [
			[Vector3(-hx, a.y, a.x), Vector3(0.0, na.y, na.x), Vector2(-hx, arc)],
			[Vector3(hx, a.y, a.x), Vector3(0.0, na.y, na.x), Vector2(hx, arc)],
			[Vector3(hx, b.y, b.x), Vector3(0.0, nb.y, nb.x), Vector2(hx, arc + sl)],
			[Vector3(-hx, b.y, b.x), Vector3(0.0, nb.y, nb.x), Vector2(-hx, arc + sl)]]
		for tri: Array in [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]:
			var order := tri
			var fn: Vector3 = tri[0][1] + tri[1][1] + tri[2][1]
			if (tri[1][0] - tri[0][0]).cross(tri[2][0] - tri[0][0]).dot(fn) > 0.0:
				order = [tri[0], tri[2], tri[1]]
			for vv: Array in order:
				st.set_normal(vv[1])
				st.set_uv(vv[2])
				st.add_vertex(vv[0])
		arc += sl
	st.generate_tangents()
	return st.commit()


## A dust sheet thrown over something. `top` is a Callable (x, z) -> height
## of what is under the sheet inside the footprint |x| <= half.x, |z| <= half.y.
## The cloth lies on it, falls down the sides in folds and spreads a little
## on the floor; `overhang` is how much cloth lies beyond the footprint.
static func drape(top: Callable, half: Vector2, overhang: float, res := Vector2i(56, 40), seed := 1) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ph := rng.randf() * 10.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := res.x
	var nz := res.y
	for i in nx + 1:
		for j in nz + 1:
			var u := lerpf(-half.x - overhang, half.x + overhang, float(i) / nx)
			var v := lerpf(-half.y - overhang, half.y + overhang, float(j) / nz)
			var ex := maxf(absf(u) - half.x, 0.0)
			var ez := maxf(absf(v) - half.y, 0.0)
			var cu := clampf(u, -half.x, half.x)
			var cv := clampf(v, -half.y, half.y)
			var o := sqrt(ex * ex + ez * ez)
			var p: Vector3
			if o <= 0.0:
				var bump := 0.006 * sin(u * 23.0 + ph) * sin(v * 19.0 - ph)
				p = Vector3(u, float(top.call(u, v)) + 0.012 + bump, v)
			else:
				var he := float(top.call(cu, cv))
				var dir := Vector2(signf(u) * ex, signf(v) * ez) / o
				var drop := minf(o, he - 0.006)
				var spread := maxf(o - (he - 0.006), 0.0)
				var k := drop / maxf(he, 0.01)
				var along := cv if absf(dir.x) > absf(dir.y) else cu
				var fold := (sin(along * 26.0 + ph) * 0.6 + sin(along * 57.0 - ph * 2.0) * 0.4) * 0.016 * k
				var out := Vector2(cu, cv) + dir * (0.015 + 0.03 * k + spread + fold)
				p = Vector3(out.x, he + 0.012 - drop, out.y)
			st.set_uv(Vector2(u, v))
			st.add_vertex(p)
	for i in nx:
		for j in nz:
			var a := i * (nz + 1) + j
			var b := (i + 1) * (nz + 1) + j
			st.add_index(a)
			st.add_index(b)
			st.add_index(b + 1)
			st.add_index(a)
			st.add_index(b + 1)
			st.add_index(a + 1)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## A hanging curtain in the local XY plane (top edge at y = 0, hanging down
## to -height), pleated along Z: `folds` pleats, deeper towards the hem.
static func curtain(width: float, height: float, folds := 7, depth := 0.05, seed := 1) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ph := rng.randf() * TAU
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := folds * 8
	var ny := 18
	for i in nx + 1:
		for j in ny + 1:
			var fx := float(i) / nx
			var fy := float(j) / ny
			var x := (fx - 0.5) * width
			var y := -fy * height - (0.02 * sin(fx * 9.0 + ph) * fy * fy)
			var z := sin(fx * folds * TAU + ph) * depth * (0.55 + 0.45 * fy) + sin(fx * 31.0 + ph) * 0.006 * fy
			st.set_uv(Vector2(x, -y))
			st.add_vertex(Vector3(x, y, z))
	for i in nx:
		for j in ny:
			var a := i * (ny + 1) + j
			var b := (i + 1) * (ny + 1) + j
			st.add_index(a)
			st.add_index(b + 1)
			st.add_index(b)
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b + 1)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()
