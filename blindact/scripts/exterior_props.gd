class_name ExteriorProps
extends RefCounted
## Meshes for the outdoor night, all generated: trees (pine, spruce, bare
## oak, birch, dead snag, young spruce) with tapered lumpy trunks, root
## flare, buttress roots, branches and needle / twig cards; undergrowth
## (ferns, bilberry mounds, thicket shrubs, grass); rocks, stumps, fallen
## logs and sticks; and the estate: 1980s blocks with their window grids,
## entrances, balconies, pipes and roof clutter, street lamps, a bike shed and
## bicycles, bins, cars, benches, a stone table, railings, a guard hut; and the
## forest landmarks (footbridge, hunter's stand, collapsed shed, root plate
## and hollow log, abandoned car, a fire-warning sign).
##
## Geometry goes into MBuf (packed arrays, far faster than SurfaceTool for
## thousands of triangles). Front faces wind clockwise (Godot's convention):
## MBuf.quad takes its corners counter-clockwise as seen from the front.
## Builders that need materials take the dictionary `m` made by
## ExteriorBuilder._materials().

## cells of assets/textures/forest/signs.png (4 x 4 cells of 256 x 128)
const SIGN_CELLS := {
	"unit_1": 0, "unit_2": 1, "unit_3": 2, "unit_4": 3,
	"block_1": 4, "block_2": 5, "block_3": 6, "block_4": 7, "block_5": 8,
	"fire": 9, "chai": 10, "danger": 11, "missing": 12, "notice": 13, "intercom": 14,
}


# ---------------------------------------------------------------------------
# MBuf: triangles into packed arrays
# ---------------------------------------------------------------------------
class MBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, t: Vector2, c: Color) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		col.append(c)
		return v.size() - 1

	func tri_idx(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	## Quad p0..p3, counter-clockwise as seen from where `nn` points.
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, c := Color(0, 0, 0, 1)) -> void:
		var i := v.size()
		add(p0, nn, u0, c)
		add(p1, nn, u1, c)
		add(p2, nn, u2, c)
		add(p3, nn, u3, c)
		tri_idx(i, i + 2, i + 1)
		tri_idx(i, i + 3, i + 2)

	## Axis box of `size` placed by `xf` (rigid), UVs in metres * uvs.
	func box(xf: Transform3D, size: Vector3, c := Color(0, 0, 0, 1), uvs := 1.0, skip_bottom := false) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
			[Vector3.LEFT, Vector3.BACK, Vector3.UP],
			[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
			[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
			[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
			[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
		]
		var b := xf.basis.orthonormalized()
		for f: Array in faces:
			var nn: Vector3 = f[0]
			if skip_bottom and nn == Vector3.DOWN:
				continue
			var r: Vector3 = f[1]
			var u: Vector3 = f[2]
			var c0 := nn * absf(h.dot(nn))
			var hr := absf(h.dot(r))
			var hu := absf(h.dot(u))
			var pts := [c0 - r * hr - u * hu, c0 + r * hr - u * hu, c0 + r * hr + u * hu, c0 - r * hr + u * hu]
			var uvq: Array[Vector2] = []
			for p: Vector3 in pts:
				uvq.append(Vector2(p.dot(r), -p.dot(u)) * uvs)
			quad(xf * pts[0], xf * pts[1], xf * pts[2], xf * pts[3], b * nn, uvq[0], uvq[1], uvq[2], uvq[3], c)

	## Tube along `pts` with per-point radii. UV: u round (0..uv_around), v metres.
	## lumps: bark bumps; buttress: lobes at the foot; colour g runs g0 -> g1 along
	## (branch weight for the wind), b = phase. cap: close the far end with an
	## end-grain disc (COLOR.r = 1).
	func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, uv_around := 1.0, lumps := 0.0, ph := 0.0,
			g0 := 0.0, g1 := 0.0, cb := 0.0, buttress := 0.0, cap := false, cap_start := false) -> void:
		var np := pts.size()
		if np < 2:
			return
		var tangents: Array[Vector3] = []
		for i in np:
			var t: Vector3
			if i == 0:
				t = pts[1] - pts[0]
			elif i == np - 1:
				t = pts[i] - pts[i - 1]
			else:
				t = pts[i + 1] - pts[i - 1]
			tangents.append(t.normalized())
		var nrm := tangents[0].cross(Vector3.UP)
		if nrm.length() < 0.1:
			nrm = tangents[0].cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var base := v.size()
		var dist := 0.0
		var total := 0.0
		for i in range(1, np):
			total += pts[i].distance_to(pts[i - 1])
		for i in np:
			if i > 0:
				var axis := tangents[i - 1].cross(tangents[i])
				if axis.length() > 1e-5:
					nrm = nrm.rotated(axis.normalized(), tangents[i - 1].angle_to(tangents[i]))
				dist += pts[i].distance_to(pts[i - 1])
			var bin := tangents[i].cross(nrm).normalized()
			var tk := dist / maxf(total, 1e-4)
			var c := Color(0.0, lerpf(g0, g1, tk), cb, 1.0)
			var bk := 0.0
			if buttress > 0.0 and dist < 1.0:
				bk = buttress * pow(1.0 - dist, 2.0)
			for s in sides + 1:
				var th := TAU * float(s) / float(sides)
				var dirv := (nrm * cos(th) + bin * sin(th))
				var r := radii[i]
				if lumps > 0.0:
					r *= 1.0 + lumps * (sin(th * 3.0 + ph + dist * 1.7) * 0.5 + sin(th * 7.0 - dist * 3.1 + ph * 2.0) * 0.25 + sin(th * 2.0 + dist * 0.6) * 0.25)
				if bk > 0.0:
					r *= 1.0 + bk * pow(maxf(0.0, sin(th * 5.0 + ph * 3.0)), 2.0)
				add(pts[i] + dirv * r, dirv, Vector2(float(s) / float(sides) * uv_around, dist), c)
		var ring := sides + 1
		for i in np - 1:
			for s in sides:
				var a := base + i * ring + s
				var b2 := a + 1
				var d := a + ring
				var c2 := d + 1
				tri_idx(a, d, c2)
				tri_idx(a, c2, b2)
		if cap:
			_cap(pts[np - 1], tangents[np - 1], base + (np - 1) * ring, sides, radii[np - 1], cb)
		if cap_start:
			_cap(pts[0], -tangents[0], base, sides, radii[0], cb, true)

	func _cap(center: Vector3, t: Vector3, ring0: int, sides: int, r: float, cb: float, flip := false) -> void:
		var c := Color(1.0, 0.0, cb, 1.0)
		var ci := add(center, t, Vector2(0.5, 0.5), c)
		var first := v.size()
		for s in sides + 1:
			var p := v[ring0 + s]
			var d := (p - center) / maxf(r, 1e-4)
			# disc UV: project onto two axes perpendicular to t
			var ax := t.cross(Vector3.UP)
			if ax.length() < 0.1:
				ax = t.cross(Vector3.RIGHT)
			ax = ax.normalized()
			var ay := t.cross(ax).normalized()
			add(p, t, Vector2(0.5 + d.dot(ax) * 0.5, 0.5 + d.dot(ay) * 0.5), c)
		for s in sides:
			if flip:
				tri_idx(ci, first + s + 1, first + s)
			else:
				tri_idx(ci, first + s, first + s + 1)

	## A foliage card: base at `p`, growing along `ax` for `length`, `side` across
	## (width), the tip sagging by `sag` (down). `ctr` is the crown axis point the
	## baked normal points away from. g0/g1 branch weight at base/tip, cb phase,
	## ao occlusion. hang = true: the texture's attachment is at its top.
	func card(p: Vector3, ax: Vector3, side: Vector3, length: float, width: float, sag: float, ctr: Vector3,
			g0: float, g1: float, cb: float, ao: float, hang := false, up_bias := 0.35, rows := 2) -> void:
		var base := v.size()
		var cn := ax.cross(side).normalized()
		for j in rows:
			var t := float(j) / float(rows - 1)
			var q := p + ax * length * t + Vector3.DOWN * sag * t * t
			for k in 2:
				var sx := -0.5 if k == 0 else 0.5
				var pos := q + side * width * sx
				var vn := (pos - ctr)
				vn.y = maxf(vn.y, 0.0) + up_bias * vn.length()
				vn = (vn.normalized() * 0.8 + cn * 0.2 * signf(cn.dot(pos - ctr) + 0.001)).normalized()
				var uvy := t if hang else 1.0 - t
				add(pos, vn, Vector2(float(k), uvy), Color(t, lerpf(g0, g1, t), cb, ao))
		for j in rows - 1:
			var a := base + j * 2
			tri_idx(a, a + 2, a + 1)
			tri_idx(a + 1, a + 2, a + 3)

	func commit(mesh: ArrayMesh, mat: Material, tangents := false) -> void:
		if v.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		if tangents:
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_tangents()
			arr = st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

	func to_mesh(mat: Material, tangents := false) -> ArrayMesh:
		var m := ArrayMesh.new()
		commit(m, mat, tangents)
		return m


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
static func rnd_dir_h(rng: RandomNumberGenerator) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a))


static func perp(d: Vector3) -> Vector3:
	var p := d.cross(Vector3.UP)
	if p.length() < 0.05:
		p = d.cross(Vector3.RIGHT)
	return p.normalized()


## A curving polyline: starts along `dir`, sags (droop) or lifts (lift) with
## distance, wobbles a little.
static func bend_line(rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, segs: int, droop: float, lift: float, wobble: float) -> PackedVector3Array:
	var out := PackedVector3Array([start])
	var d := dir.normalized()
	var p := start
	var step := length / float(segs)
	for i in segs:
		var t := float(i + 1) / float(segs)
		d = (d + Vector3(rng.randf_range(-wobble, wobble), -droop * step + lift * t * step * 2.0, rng.randf_range(-wobble, wobble))).normalized()
		p += d * step
		out.append(p)
	return out


static func taper(n: int, r0: float, r1: float, power := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		out.append(lerpf(r0, r1, pow(t, power)))
	return out


static func mi(parent: Node3D, mesh: Mesh, pos := Vector3.ZERO, rot := Vector3.ZERO, shadow := true, mat: Material = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	if mat:
		m.material_override = mat
	if not shadow:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


static func rbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, r := 0.01, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	return mi(parent, MeshUtil.rounded_box(size, r, 2), pos, rot, shadow, mat)


static func node(parent: Node, pos := Vector3.ZERO, rot_y := 0.0, nm := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	if nm != "":
		n.name = nm
	parent.add_child(n)
	return n


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, seg := 12, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return mi(parent, cm, pos, rot, shadow, mat)


# ---------------------------------------------------------------------------
# trees
# ---------------------------------------------------------------------------
## kind: pine | spruce | oak | birch | snag | sapling. lod 0 near, 1 far.
## Returns {mesh, h (height), r1 (trunk radius at 1 m, unscaled), crown}.
static func tree(kind: String, seed: int, lod: int, m: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := MBuf.new()
	var leaf := MBuf.new()
	var twig := MBuf.new()
	var info := {}
	match kind:
		"pine":
			info = _pine(rng, lod, bark, leaf)
		"spruce":
			info = _spruce(rng, lod, bark, leaf, twig, false)
		"sapling":
			info = _spruce(rng, lod, bark, leaf, twig, true)
		"oak":
			info = _oak(rng, lod, bark, twig)
		"birch":
			info = _birch(rng, lod, bark, leaf)
		_:
			info = _snag(rng, lod, bark, twig)
	var mesh := ArrayMesh.new()
	var bark_mat: Material = m.get("bark_" + String(info.get("bark", kind)), m.get("bark_pine"))
	bark.commit(mesh, bark_mat, true)
	if not leaf.v.is_empty():
		leaf.commit(mesh, m.get("leaf_" + String(info.get("leaf", kind))))
	if not twig.v.is_empty():
		twig.commit(mesh, m.leaf_twigs)
	info["mesh"] = mesh
	return info


static func _trunk_line(rng: RandomNumberGenerator, h: float, segs: int, lean: float, curve: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var ld := rnd_dir_h(rng)
	var cd := rnd_dir_h(rng)
	var ph := rng.randf() * TAU
	for i in segs + 1:
		var t := float(i) / float(segs)
		var y := -0.35 + (h + 0.35) * t
		var off := ld * lean * t * t * h * 0.05 + cd * curve * sin(t * PI * 1.3 + ph) * 0.4
		pts.append(Vector3(off.x, y, off.z))
	return pts


static func _trunk_radii(pts: PackedVector3Array, r1: float, top_r: float, flare: float, h: float) -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	for p: Vector3 in pts:
		var t := clampf(p.y / h, 0.0, 1.0)
		var r := lerpf(r1 * 1.06, top_r, pow(t, 0.85))
		if p.y < 0.9:
			r *= 1.0 + flare * pow(clampf(1.0 - maxf(p.y, 0.0) / 0.9, 0.0, 1.0), 2.2)
		radii.append(r)
	return radii


## Point on the trunk polyline at height y (for hanging branches on it).
static func _on_trunk(pts: PackedVector3Array, y: float) -> Vector3:
	for i in pts.size() - 1:
		if pts[i + 1].y >= y:
			var t := (y - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 1e-4)
			return pts[i].lerp(pts[i + 1], t)
	return pts[pts.size() - 1]


static func _r_at(pts: PackedVector3Array, radii: PackedFloat32Array, y: float) -> float:
	for i in pts.size() - 1:
		if pts[i + 1].y >= y:
			var t := (y - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 1e-4)
			return lerpf(radii[i], radii[i + 1], t)
	return radii[radii.size() - 1]


## Buttress roots spreading from the foot into the ground.
static func _roots(rng: RandomNumberGenerator, bark: MBuf, r0: float, count: int, sides: int) -> void:
	var a0 := rng.randf() * TAU
	for k in count:
		var a := a0 + TAU * float(k) / float(count) + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0.0, sin(a))
		var ln := r0 * rng.randf_range(2.6, 4.2)
		var pts := PackedVector3Array()
		for i in 5:
			var t := float(i) / 4.0
			pts.append(d * (r0 * 0.55 + ln * t) + Vector3(0.0, lerpf(0.45, -0.18, pow(t, 0.7)) * r0 * 1.6, 0.0) + perp(d) * sin(t * 3.0 + a) * 0.05)
		bark.tube(pts, taper(5, r0 * 0.42, r0 * 0.08, 0.8), sides, 1.0, 0.12, a)


static func _pine(rng: RandomNumberGenerator, lod: int, bark: MBuf, leaf: MBuf) -> Dictionary:
	var h := rng.randf_range(16.0, 23.0)
	var r1 := rng.randf_range(0.2, 0.3)
	var segs := 16 if lod == 0 else 7
	var pts := _trunk_line(rng, h, segs, rng.randf_range(0.0, 0.6), rng.randf_range(0.1, 0.35))
	var radii := _trunk_radii(pts, r1, 0.035, 0.45, h)
	var sides := 12 if lod == 0 else 6
	bark.tube(pts, radii, sides, maxf(2.0, roundf(TAU * r1 / 0.5)), 0.05 if lod == 0 else 0.0, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.35 if lod == 0 else 0.0)
	if lod == 0:
		_roots(rng, bark, r1, 5, 6)
	var crown_r := rng.randf_range(1.9, 2.9)
	var y0 := h * rng.randf_range(0.6, 0.7)
	var y := y0
	# the crown: whorls of branches, low ones level and long, high ones short
	# and rising; needle clumps all along their outer parts
	while y < h - 0.4:
		var t := (y - y0) / (h - y0)
		var nb := rng.randi_range(4, 5) if lod == 0 else 3
		var a0 := rng.randf() * TAU
		for k in nb:
			var a := a0 + TAU * float(k) / float(nb) + rng.randf_range(-0.35, 0.35)
			var d := Vector3(cos(a), 0.0, sin(a))
			var elev := deg_to_rad(lerpf(-4.0, 48.0, t) + rng.randf_range(-8.0, 8.0))
			var dir := (d * cos(elev) + Vector3.UP * sin(elev)).normalized()
			var ln := crown_r * pow(1.0 - t * 0.8, 0.8) * rng.randf_range(0.7, 1.1) + 0.3
			var st := _on_trunk(pts, y)
			var br := _r_at(pts, radii, y) * 0.4
			var bl := bend_line(rng, st, dir, ln, 4 if lod == 0 else 2, 0.05, 0.2, 0.14)
			var cb := rng.randf()
			bark.tube(bl, taper(bl.size(), br, 0.015, 0.9), 5 if lod == 0 else 3, 1.0, 0.0, 0.0, 0.0, 1.0, cb)
			var stems: Array = [[bl, 0.0]]
			if lod == 0:
				for j in rng.randi_range(2, 4):
					var tj := rng.randf_range(0.3, 0.9)
					var ti := clampi(int(tj * (bl.size() - 1)), 1, bl.size() - 2)
					var bd := (bl[ti + 1] - bl[ti]).normalized()
					var sd := (bd + perp(bd).rotated(bd, rng.randf() * TAU) * rng.randf_range(0.8, 1.3) + Vector3.UP * 0.35).normalized()
					var sb := bend_line(rng, bl[ti], sd, ln * rng.randf_range(0.3, 0.5), 3, 0.05, 0.2, 0.2)
					bark.tube(sb, taper(sb.size(), br * 0.4, 0.01), 3, 1.0, 0.0, 0.0, tj, 1.0, cb)
					stems.append([sb, tj])
			var ctr := _on_trunk(pts, y + 0.5)
			for sm: Array in stems:
				var line: PackedVector3Array = sm[0]
				var g0: float = sm[1]
				var total := 0.0
				for i in range(1, line.size()):
					total += line[i].distance_to(line[i - 1])
				var stepc := 0.3 if lod == 0 else 0.5
				var dist := total * (0.3 if g0 == 0.0 else 0.15)
				while dist <= total:
					var f := dist / total
					var fi := f * float(line.size() - 1)
					var i0 := mini(int(fi), line.size() - 2)
					var p := line[i0].lerp(line[i0 + 1], fi - float(i0))
					var bd2 := (line[i0 + 1] - line[i0]).normalized()
					var cd := (bd2 + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.2, 1.0), rng.randf_range(-0.9, 0.9))).normalized()
					var cl := rng.randf_range(0.55, 0.8) * (1.0 if lod == 0 else 1.45)
					var ao := clampf(0.45 + 0.4 * t + 0.25 * f, 0.35, 1.0)
					leaf.card(p - cd * cl * 0.3, cd, perp(cd).rotated(cd, rng.randf() * PI), cl, cl, 0.03, ctr, lerpf(g0, 1.0, f), 1.0, cb, ao)
					dist += stepc * rng.randf_range(0.8, 1.2)
		y += rng.randf_range(0.55, 0.85) if lod == 0 else rng.randf_range(0.9, 1.3)
	# the leader at the top
	var top := pts[pts.size() - 1]
	for c in 4:
		var cd3 := (Vector3.UP + rnd_dir_h(rng) * 0.7).normalized()
		leaf.card(top - Vector3(0, 0.35, 0), cd3, perp(cd3), 0.7, 0.7, 0.0, top - Vector3(0, 1.0, 0), 0.5, 1.0, 0.0, 1.0)
	# dead stubs on the bare trunk below the crown
	if lod == 0:
		for k in rng.randi_range(6, 11):
			var yy := rng.randf_range(2.5, y0 - 0.5)
			var st2 := _on_trunk(pts, yy)
			var d2 := rnd_dir_h(rng)
			var sl := bend_line(rng, st2, (d2 + Vector3.DOWN * 0.15).normalized(), rng.randf_range(0.15, 0.55), 2, 0.1, 0.0, 0.1)
			bark.tube(sl, taper(sl.size(), rng.randf_range(0.025, 0.04), 0.012), 4, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true)
	return {"h": h, "r1": r1, "crown": crown_r, "bark": "pine", "leaf": "pine"}


static func _spruce(rng: RandomNumberGenerator, lod: int, bark: MBuf, leaf: MBuf, twig: MBuf, young: bool) -> Dictionary:
	var h := rng.randf_range(1.4, 3.2) if young else rng.randf_range(13.0, 21.0)
	var r1 := (0.03 + h * 0.012) if young else rng.randf_range(0.17, 0.28)
	var segs := (6 if young else 14) if lod == 0 else 6
	var pts := _trunk_line(rng, h, segs, rng.randf_range(0.0, 0.3), rng.randf_range(0.0, 0.12))
	var radii := _trunk_radii(pts, r1, 0.012, 0.0 if young else 0.4, h)
	var sides := (6 if young else 11) if lod == 0 else 5
	bark.tube(pts, radii, sides, maxf(1.0, roundf(TAU * r1 / 0.45)), 0.04 if lod == 0 else 0.0, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0 if young else (0.3 if lod == 0 else 0.0))
	if lod == 0 and not young:
		_roots(rng, bark, r1, 5, 5)
	var crown_r := (h * 0.32) if young else rng.randf_range(2.0, 3.1)
	var y0 := (0.12) if young else h * rng.randf_range(0.22, 0.4)
	var y := y0
	var step := (0.22 if young else 0.55) if lod == 0 else (0.4 if young else 0.85)
	while y < h - 0.25:
		var t := (y - y0) / maxf(h - y0, 0.1)
		var nb := (rng.randi_range(4, 6) if lod == 0 else 3)
		var a0 := rng.randf() * TAU
		for k in nb:
			var a := a0 + TAU * float(k) / float(nb) + rng.randf_range(-0.3, 0.3)
			var d := Vector3(cos(a), 0.0, sin(a))
			var elev := deg_to_rad(lerpf(-14.0, 22.0, t) + rng.randf_range(-6.0, 6.0))
			var dir := (d * cos(elev) + Vector3.UP * sin(elev)).normalized()
			var ln := crown_r * pow(1.0 - t, 0.95) * rng.randf_range(0.8, 1.1) + (0.12 if young else 0.25)
			var st := _on_trunk(pts, y)
			var br := maxf(_r_at(pts, radii, y) * 0.32, 0.006)
			var bl := bend_line(rng, st, dir, ln, 3 if lod == 0 else 2, 0.22, 0.18, 0.08)
			var cb := rng.randf()
			if lod == 0 and not young:
				bark.tube(bl, taper(bl.size(), br, 0.008, 0.9), 4 if y < h * 0.6 else 3, 1.0, 0.0, 0.0, 0.0, 1.0, cb)
			elif not young:
				bark.tube(PackedVector3Array([bl[0], bl[bl.size() - 1]]), taper(2, br, 0.01), 3, 1.0, 0.0, 0.0, 0.0, 1.0, cb)
			var ctr := _on_trunk(pts, y + 0.3)
			var n_cards := int(ceil(ln / (0.42 if lod == 0 else 0.7)))
			for c in n_cards:
				var tt := lerpf(0.12, 1.0, float(c) / float(maxi(n_cards - 1, 1))) if n_cards > 1 else 0.6
				var fi := tt * float(bl.size() - 1)
				var i0 := mini(int(fi), bl.size() - 2)
				var p := bl[i0].lerp(bl[i0 + 1], fi - float(i0))
				var bd := (bl[i0 + 1] - bl[i0]).normalized()
				var cl := clampf(ln * 0.5, 0.3, 0.85) * rng.randf_range(0.85, 1.1) * (1.0 if lod == 0 else 1.5)
				var ao := clampf(0.35 + 0.45 * tt + 0.3 * t, 0.3, 1.0)
				for layer in (2 if lod == 0 and t < 0.55 else 1):
					var tilt := deg_to_rad(rng.randf_range(15.0, 35.0)) * (1.0 if layer == 0 else -1.0)
					var cd := (bd + Vector3.DOWN * rng.randf_range(0.1, 0.45)).normalized()
					var cs := perp(cd).rotated(cd, tilt)
					leaf.card(p - cd * cl * 0.15, cd, cs, cl, cl * 0.5, cl * 0.18, ctr, tt, 1.0, cb, ao)
		y += step * rng.randf_range(0.85, 1.15)
	# the leader
	var top := pts[pts.size() - 1]
	var lc := (0.5 if young else 0.9)
	for c in 3:
		var cd2 := (Vector3.UP + rnd_dir_h(rng) * 0.35).normalized()
		leaf.card(top - Vector3(0, lc * 0.6, 0), cd2, perp(cd2).rotated(cd2, c * 1.05), lc, lc * 0.5, 0.0, top - Vector3(0, 1, 0), 0.4, 1.0, 0.0, 1.0)
	# dead grey branches on the shaded lower trunk
	if not young and lod == 0:
		var yy := 1.4
		while yy < y0 - 0.2:
			for k in rng.randi_range(2, 4):
				var d2 := rnd_dir_h(rng)
				var st2 := _on_trunk(pts, yy)
				var dl := bend_line(rng, st2, (d2 + Vector3.DOWN * rng.randf_range(0.1, 0.5)).normalized(), rng.randf_range(0.3, 0.95), 3, 0.35, 0.0, 0.25)
				bark.tube(dl, taper(dl.size(), 0.022, 0.006), 3, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true)
				if rng.randf() < 0.35:
					var e := dl[dl.size() - 1]
					var ed := (dl[dl.size() - 1] - dl[dl.size() - 2]).normalized()
					twig.card(e - ed * 0.4, (ed + Vector3.UP * 0.2).normalized(), perp(ed), 0.8, 0.8, 0.05, st2, 0.0, 0.3, 0.0, 0.5)
			yy += rng.randf_range(0.4, 0.7)
	return {"h": h, "r1": r1, "crown": crown_r, "bark": "spruce", "leaf": "spruce"}


static func _oak(rng: RandomNumberGenerator, lod: int, bark: MBuf, twig: MBuf) -> Dictionary:
	var h := rng.randf_range(11.0, 16.0)
	var r1 := rng.randf_range(0.24, 0.38)
	var yf := h * rng.randf_range(0.32, 0.45)
	var segs := 9 if lod == 0 else 4
	var pts := _trunk_line(rng, yf + 0.6, segs, rng.randf_range(0.0, 0.8), rng.randf_range(0.15, 0.4))
	var radii := _trunk_radii(pts, r1, r1 * 0.72, 0.6, h)
	var sides := 13 if lod == 0 else 6
	bark.tube(pts, radii, sides, maxf(2.0, roundf(TAU * r1 / 0.5)), 0.12 if lod == 0 else 0.0, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.5 if lod == 0 else 0.0)
	if lod == 0:
		_roots(rng, bark, r1, 6, 6)
	var fork := pts[pts.size() - 1]
	var nl := rng.randi_range(2, 4)
	var a0 := rng.randf() * TAU
	var crown := 0.0
	for k in nl:
		var a := a0 + TAU * float(k) / float(nl) + rng.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a), 0.0, sin(a))
		var elev := deg_to_rad(rng.randf_range(45.0, 68.0))
		var dir := (d * cos(elev) + Vector3.UP * sin(elev)).normalized()
		var ln := (h - yf) * rng.randf_range(0.75, 1.0)
		var cb := rng.randf()
		var limb := bend_line(rng, fork - Vector3(0, 0.5, 0), dir, ln, 6 if lod == 0 else 3, 0.03, 0.0, 0.14)
		var lr := r1 * 0.62
		bark.tube(limb, taper(limb.size(), lr, lr * 0.25, 0.9), 8 if lod == 0 else 4, 2.0, 0.08 if lod == 0 else 0.0, a, 0.0, 0.5, cb)
		crown = maxf(crown, Vector2(limb[limb.size() - 1].x, limb[limb.size() - 1].z).length())
		var nb := rng.randi_range(3, 5) if lod == 0 else 2
		for j in nb:
			var ti := rng.randi_range(2, limb.size() - 2)
			var bd0 := (limb[ti + 1] - limb[ti]).normalized()
			var sd := (bd0 + perp(bd0).rotated(bd0, rng.randf() * TAU) * rng.randf_range(0.7, 1.3)).normalized()
			sd = (sd + Vector3.UP * 0.25).normalized()
			var bln := ln * rng.randf_range(0.38, 0.6)
			var b := bend_line(rng, limb[ti], sd, bln, 4 if lod == 0 else 2, 0.08, 0.05, 0.2)
			var g0 := 0.5 * float(ti) / float(limb.size() - 1)
			bark.tube(b, taper(b.size(), lr * 0.4, 0.015), 5 if lod == 0 else 3, 1.0, 0.0, 0.0, g0, 1.0, cb)
			var tips: Array = [[b[b.size() - 1], (b[b.size() - 1] - b[b.size() - 2]).normalized()]]
			if lod == 0:
				for q in rng.randi_range(2, 3):
					var ti2 := rng.randi_range(1, b.size() - 2)
					var bd1 := (b[ti2 + 1] - b[ti2]).normalized()
					var td := (bd1 + perp(bd1).rotated(bd1, rng.randf() * TAU) * 0.9 + Vector3.UP * 0.3).normalized()
					var tb := bend_line(rng, b[ti2], td, bln * rng.randf_range(0.35, 0.5), 3, 0.05, 0.05, 0.25)
					bark.tube(tb, taper(tb.size(), lr * 0.14, 0.008), 3, 1.0, 0.0, 0.0, 0.7, 1.0, cb)
					tips.append([tb[tb.size() - 1], (tb[tb.size() - 1] - tb[tb.size() - 2]).normalized()])
			for tp: Array in tips:
				var p: Vector3 = tp[0]
				var td2: Vector3 = tp[1]
				for c in (2 if lod == 0 else 1):
					var cd := (td2 + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
					var cs := perp(cd).rotated(cd, rng.randf_range(-0.6, 0.6) + c * 1.57)
					var cl := rng.randf_range(1.3, 2.0) * (1.0 if lod == 0 else 1.35)
					twig.card(p - cd * cl * 0.35, cd, cs, cl, cl, 0.1, fork, 0.85, 1.0, cb, 0.85)
	return {"h": h, "r1": r1, "crown": crown + 1.0, "bark": "oak", "leaf": "twigs"}


static func _birch(rng: RandomNumberGenerator, lod: int, bark: MBuf, leaf: MBuf) -> Dictionary:
	var h := rng.randf_range(11.0, 16.0)
	var r1 := rng.randf_range(0.1, 0.16)
	var segs := 14 if lod == 0 else 6
	var pts := _trunk_line(rng, h, segs, rng.randf_range(0.5, 2.0), rng.randf_range(0.2, 0.5))
	var radii := _trunk_radii(pts, r1, 0.02, 0.35, h)
	bark.tube(pts, radii, 10 if lod == 0 else 5, 2.0, 0.03 if lod == 0 else 0.0, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.2 if lod == 0 else 0.0)
	var y := h * rng.randf_range(0.35, 0.45)
	var crown := 0.0
	while y < h - 0.6:
		var t := (y - h * 0.4) / (h * 0.6)
		var d := rnd_dir_h(rng)
		var dir := (d * 0.7 + Vector3.UP * rng.randf_range(0.6, 1.1)).normalized()
		var ln := rng.randf_range(1.5, 3.2) * (1.0 - 0.5 * t)
		var st := _on_trunk(pts, y)
		var cb := rng.randf()
		var bl := bend_line(rng, st, dir, ln, 4 if lod == 0 else 2, 0.3, 0.0, 0.1)
		bark.tube(bl, taper(bl.size(), _r_at(pts, radii, y) * 0.45, 0.01), 5 if lod == 0 else 3, 1.0, 0.0, 0.0, 0.0, 1.0, cb)
		crown = maxf(crown, Vector2(bl[bl.size() - 1].x, bl[bl.size() - 1].z).length())
		var ctr := _on_trunk(pts, y + 1.0)
		for i in range(1, bl.size()):
			if lod == 1 and i % 2 == 0:
				continue
			var p := bl[i]
			for c in (2 if lod == 0 else 1):
				var hd := (Vector3.DOWN + rnd_dir_h(rng) * 0.35 + d * 0.25).normalized()
				var cl := rng.randf_range(1.0, 1.6) * (1.0 if lod == 0 else 1.4)
				leaf.card(p, hd, perp(hd).rotated(hd, rng.randf() * PI), cl, cl * 0.5, 0.0, ctr, float(i) / bl.size(), 1.0, cb, 0.8, true, 0.2)
		y += rng.randf_range(0.35, 0.7) if lod == 0 else rng.randf_range(0.8, 1.2)
	return {"h": h, "r1": r1, "crown": crown + 0.8, "bark": "birch", "leaf": "birch"}


static func _snag(rng: RandomNumberGenerator, lod: int, bark: MBuf, twig: MBuf) -> Dictionary:
	var h := rng.randf_range(6.0, 11.0)
	var r1 := rng.randf_range(0.18, 0.3)
	var segs := 10 if lod == 0 else 5
	var pts := _trunk_line(rng, h, segs, rng.randf_range(0.5, 1.5), rng.randf_range(0.1, 0.3))
	var radii := _trunk_radii(pts, r1, r1 * 0.45, 0.4, h * 1.6)
	bark.tube(pts, radii, 11 if lod == 0 else 5, maxf(2.0, roundf(TAU * r1 / 0.5)), 0.1 if lod == 0 else 0.0, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.4 if lod == 0 else 0.0, true)
	if lod == 0:
		_roots(rng, bark, r1, 5, 5)
		for k in rng.randi_range(5, 9):
			var yy := rng.randf_range(2.0, h - 0.6)
			var st := _on_trunk(pts, yy)
			var d := rnd_dir_h(rng)
			var bl := bend_line(rng, st, (d + Vector3.UP * rng.randf_range(-0.2, 0.5)).normalized(), rng.randf_range(0.3, 1.8), 3, 0.05, 0.0, 0.15)
			bark.tube(bl, taper(bl.size(), _r_at(pts, radii, yy) * 0.3, 0.02), 4, 1.0, 0.0, 0.0, 0.0, 0.6, rng.randf(), 0.0, true)
			if rng.randf() < 0.3:
				var e := bl[bl.size() - 1]
				var ed := (bl[bl.size() - 1] - bl[bl.size() - 2]).normalized()
				twig.card(e - ed * 0.3, (ed + Vector3.UP * 0.3).normalized(), perp(ed), 1.0, 1.0, 0.05, st, 0.2, 0.6, 0.0, 0.6)
	return {"h": h, "r1": r1, "crown": 1.5, "bark": "dead", "leaf": "twigs"}


# ---------------------------------------------------------------------------
# undergrowth, rocks, deadwood
# ---------------------------------------------------------------------------
## A clump of arching fronds.
static func fern(seed: int, m: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var n := rng.randi_range(7, 11)
	var a0 := rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * float(k) / float(n) + rng.randf_range(-0.25, 0.25)
		var d := Vector3(cos(a), 0.0, sin(a))
		var elev := deg_to_rad(rng.randf_range(38.0, 68.0))
		var ax := (d * cos(elev) + Vector3.UP * sin(elev)).normalized()
		var ln := rng.randf_range(0.55, 0.95)
		var side := d.cross(Vector3.UP).normalized().rotated(ax, rng.randf_range(-0.35, 0.35))
		b.card(Vector3(0, 0.02, 0) + d * 0.03, ax, side, ln, ln * 0.5, ln * 0.45, Vector3(0, -0.4, 0), 0.0, 0.7, rng.randf(), 0.75, false, 0.6, 3)
	return b.to_mesh(m.leaf_fern)


## A low bilberry / bramble mound.
static func bush(seed: int, m: Dictionary, size := 0.7) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var n := rng.randi_range(9, 13)
	for k in n:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var tilt := rng.randf_range(0.0, 0.7)
		var ax := (Vector3.UP + d * tilt).normalized()
		var ln := size * rng.randf_range(0.7, 1.15)
		var off := d * rng.randf_range(0.0, size * 0.45)
		b.card(off - ax * 0.05, ax, d.cross(Vector3.UP).normalized(), ln, ln, 0.02, Vector3(0, -size * 0.5, 0), 0.0, 0.6, rng.randf(), 0.8, false, 0.5)
	return b.to_mesh(m.leaf_bush)


## A thicket shrub you can stand in (hazel / hornbeam), about 2 m: stems,
## leafy cards and dead twig fans. Two surfaces (leaves, twigs) + stems.
static func thicket(seed: int, m: Dictionary, size := 2.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stems := MBuf.new()
	var lv := MBuf.new()
	var tw := MBuf.new()
	for k in rng.randi_range(6, 9):
		var d := rnd_dir_h(rng)
		var dir := (Vector3.UP + d * rng.randf_range(0.25, 0.6)).normalized()
		var sl := bend_line(rng, d * rng.randf_range(0.0, 0.35), dir, size * rng.randf_range(0.7, 1.05), 4, 0.05, 0.0, 0.12)
		var cb := rng.randf()
		stems.tube(sl, taper(sl.size(), 0.025, 0.008), 4, 1.0, 0.0, 0.0, 0.0, 1.0, cb)
		for i in range(1, sl.size()):
			var p := sl[i]
			var cd := (dir + rnd_dir_h(rng) * 0.9 + Vector3.UP * 0.2).normalized()
			var cl := rng.randf_range(0.7, 1.1) * size * 0.5
			lv.card(p - cd * cl * 0.4, cd, perp(cd).rotated(cd, rng.randf() * PI), cl, cl, 0.05, Vector3(0, size * 0.4, 0), float(i) / sl.size(), 1.0, cb, 0.75)
			if rng.randf() < 0.5:
				tw.card(p - cd * cl * 0.3, cd, perp(cd).rotated(cd, rng.randf() * PI), cl * 1.2, cl * 1.2, 0.05, Vector3(0, size * 0.4, 0), float(i) / sl.size(), 1.0, cb, 0.75)
	var mesh := ArrayMesh.new()
	stems.commit(mesh, m.bark_oak, true)
	lv.commit(mesh, m.leaf_bush)
	tw.commit(mesh, m.leaf_twigs)
	return mesh


static func grass(seed: int, m: Dictionary, size := 0.45) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	for k in 4:
		var a := float(k) * PI / 4.0 + rng.randf_range(-0.3, 0.3)
		var side := Vector3(cos(a), 0.0, sin(a))
		var ax := (Vector3.UP + rnd_dir_h(rng) * 0.15).normalized()
		var ln := size * rng.randf_range(0.8, 1.2)
		b.card(rnd_dir_h(rng) * 0.05 - Vector3(0, 0.03, 0), ax, side, ln, ln * 1.2, 0.0, Vector3(0, -0.6, 0), 0.0, 0.5, rng.randf(), 0.85, false, 0.8)
	return b.to_mesh(m.leaf_grass)


## A boulder: an icosphere pushed about by noise, flattened underneath.
## UVs are not needed (the rock shader maps in object space).
static func rock(seed: int, m: Dictionary, detail := 3) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for lvl in detail:
		var cache := {}
		var nf: Array = []
		for f: Array in faces:
			var mids: Array[int] = []
			for e in 3:
				var a: int = f[e]
				var b2: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b2), maxi(a, b2))
				if not cache.has(key):
					verts.append(((verts[a] + verts[b2]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				mids.append(cache[key])
			nf.append([f[0], mids[0], mids[2]])
			nf.append([f[1], mids[1], mids[0]])
			nf.append([f[2], mids[2], mids[1]])
			nf.append([mids[0], mids[1], mids[2]])
		faces = nf
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var squash := Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.55, 0.85), rng.randf_range(0.75, 1.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos: Array[Vector3] = []
	for vv: Vector3 in verts:
		var d := 1.0 + noise.get_noise_3dv(vv * 1.3) * 0.32 + noise.get_noise_3dv(vv * 4.0 + Vector3(5, 5, 5)) * 0.07
		var p := vv * d * squash
		# facets: flatten towards a few random planes (split rock faces)
		if p.y < -0.15:
			p.y = -0.15 + (p.y + 0.15) * 0.25
		pos.append(p)
	for f: Array in faces:
		# icosphere faces wind counter-clockwise from outside: emit clockwise
		for k: int in [f[0], f[2], f[1]]:
			st.set_uv(Vector2(pos[k].x + pos[k].z, pos[k].y))
			st.add_vertex(pos[k])
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, m.rock)
	return mesh


## A cut or broken stump with roots.
static func stump(seed: int, m: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var r := rng.randf_range(0.22, 0.4)
	var hh := rng.randf_range(0.25, 0.7)
	var pts := PackedVector3Array([Vector3(0, -0.25, 0), Vector3(0, 0.05, 0), Vector3(0.01, hh * 0.5, 0), Vector3(0.02, hh, 0)])
	var radii := PackedFloat32Array([r * 1.35, r * 1.2, r * 1.02, r])
	b.tube(pts, radii, 12, maxf(2.0, roundf(TAU * r / 0.5)), 0.1, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.5, true)
	_roots(rng, b, r, 5, 5)
	return b.to_mesh(m.bark_oak, true)


## A fallen trunk along +x, centred, lying on y = 0 (sink it a little).
static func log_mesh(seed: int, m: Dictionary, length := 6.0, r := 0.3, bark := "bark_pine") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs := 10
	var cd := rng.randf_range(-0.25, 0.25)
	for i in segs + 1:
		var t := float(i) / float(segs)
		pts.append(Vector3((t - 0.5) * length, r + sin(t * PI) * 0.04, sin(t * PI) * cd))
		radii.append(r * lerpf(1.1, 0.8, t))
	b.tube(pts, radii, 11, maxf(2.0, roundf(TAU * r / 0.5)), 0.08, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true, true)
	for k in rng.randi_range(2, 5):
		var t := rng.randf_range(0.2, 0.9)
		var p := Vector3((t - 0.5) * length, r, 0)
		var d := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var sl := bend_line(rng, p, d, rng.randf_range(0.2, 0.9), 2, 0.1, 0.0, 0.1)
		b.tube(sl, taper(sl.size(), r * 0.25, 0.015), 4, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true)
	return b.to_mesh(m[bark], true)


## A fallen stick with a fork, lying on the ground.
static func stick(seed: int, m: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var d := rnd_dir_h(rng)
	var ln := rng.randf_range(0.5, 1.3)
	var pts := PackedVector3Array()
	for i in 4:
		var t := float(i) / 3.0
		pts.append(d * (t - 0.5) * ln + perp(d) * sin(t * 2.5) * 0.04 + Vector3(0, 0.02, 0))
	var r := rng.randf_range(0.012, 0.028)
	b.tube(pts, taper(4, r, r * 0.6), 4, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
	var fp := pts[1]
	var fd := (d + perp(d) * rng.randf_range(-1.0, 1.0)).normalized()
	var f := PackedVector3Array([fp, fp + fd * ln * 0.3 + Vector3(0, 0.01, 0)])
	b.tube(f, taper(2, r * 0.6, r * 0.3), 3, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true)
	return b.to_mesh(m.bark_oak, true)

# ---------------------------------------------------------------------------
# the blocks
# ---------------------------------------------------------------------------
const FH := 2.9          # storey height
const GF := 0.45         # ground floor above the street (the entrance steps)
const REVEAL := 0.24     # depth of the window reveals
const WIN := {           # width, height, sill above the floor
	"big": Vector3(1.5, 1.5, 0.9),
	"kitchen": Vector3(1.0, 1.3, 1.0),
	"stair": Vector3(1.2, 1.1, 0.0),
	"small": Vector3(0.6, 0.8, 1.4),
	"bal": Vector3(2.4, 2.35, 0.0),
}


## Quad with corners in any order around its rim; turned to face `nn`.
static func fquad(b: MBuf, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, c := Color(1, 1, 1, 1)) -> void:
	if (p1 - p0).cross(p2 - p0).dot(nn) >= 0.0:
		b.quad(p0, p1, p2, p3, nn, u0, u1, u2, u3, c)
	else:
		b.quad(p0, p3, p2, p1, nn, u0, u3, u2, u1, c)


## A facade plane: origin o (bottom-left seen from outside... u runs along r),
## outward normal n. Wall rectangles round rectangular holes (Rect2 in u, y),
## plus the reveals of each hole, `depth` deep. UVs in metres.
static func wall_with_holes(b: MBuf, o: Vector3, r: Vector3, n: Vector3, length: float, y0: float, y1: float, holes: Array, depth := REVEAL) -> void:
	var ys: Array[float] = [y0, y1]
	for h: Rect2 in holes:
		ys.append(clampf(h.position.y, y0, y1))
		ys.append(clampf(h.end.y, y0, y1))
	ys.sort()
	var uniq: Array[float] = []
	for y: float in ys:
		if uniq.is_empty() or y - uniq[uniq.size() - 1] > 0.001:
			uniq.append(y)
	for i in uniq.size() - 1:
		var ya := uniq[i]
		var yb := uniq[i + 1]
		var ym := (ya + yb) * 0.5
		var cuts: Array = []
		for h: Rect2 in holes:
			if h.position.y < ym and h.end.y > ym:
				cuts.append(Vector2(h.position.x, h.end.x))
		cuts.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
		var x := 0.0
		for cv: Vector2 in cuts:
			if cv.x > x + 0.001:
				_wrect(b, o, r, n, x, cv.x, ya, yb)
			x = maxf(x, cv.y)
		if x < length - 0.001:
			_wrect(b, o, r, n, x, length, ya, yb)
	for h: Rect2 in holes:
		var ua := h.position.x
		var ub := h.end.x
		var ya := h.position.y
		var yb := h.end.y
		var d := -n * depth
		var pa := o + r * ua + Vector3.UP * ya
		var pb := o + r * ub + Vector3.UP * ya
		var pc := o + r * ub + Vector3.UP * yb
		var pd := o + r * ua + Vector3.UP * yb
		fquad(b, pa, pd, pd + d, pa + d, r, Vector2(0, ya), Vector2(0, yb), Vector2(depth, yb), Vector2(depth, ya))
		fquad(b, pb, pc, pc + d, pb + d, -r, Vector2(0, ya), Vector2(0, yb), Vector2(depth, yb), Vector2(depth, ya))
		fquad(b, pa, pb, pb + d, pa + d, Vector3.UP, Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, depth), Vector2(ua, depth))
		fquad(b, pd, pc, pc + d, pd + d, Vector3.DOWN, Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, depth), Vector2(ua, depth))


static func _wrect(b: MBuf, o: Vector3, r: Vector3, n: Vector3, u0: float, u1: float, y0: float, y1: float) -> void:
	var p0 := o + r * u0 + Vector3.UP * y0
	var p1 := o + r * u1 + Vector3.UP * y0
	var p2 := o + r * u1 + Vector3.UP * y1
	var p3 := o + r * u0 + Vector3.UP * y1
	fquad(b, p0, p1, p2, p3, n, Vector2(u0, -y0), Vector2(u1, -y0), Vector2(u1, -y1), Vector2(u0, -y1))


## Transform of an opening: origin at the bottom centre of the hole on the wall
## face; +x to the right as seen from outside, +y up, +z out of the wall.
static func opening_xf(o: Vector3, r: Vector3, n: Vector3, u: float, y: float) -> Transform3D:
	return Transform3D(Basis(-r, Vector3.UP, n), o + r * u + Vector3.UP * y)


## Window frame meshes in opening space (x across, y up from the sill, z out).
static func window_frame(kind: String, m: Dictionary) -> ArrayMesh:
	var s: Vector3 = WIN[kind]
	var w := s.x
	var h := s.y
	var b := MBuf.new()
	var zc := -0.11
	var fw := 0.055
	var fd := 0.07
	var white := Color(1, 1, 1, 1)
	var bx := func(cx: float, cy: float, sx: float, sy: float, z := zc, sz := fd) -> void:
		b.box(Transform3D(Basis.IDENTITY, Vector3(cx, cy, z)), Vector3(sx, sy, sz), white, 1.0)
	bx.call(-w * 0.5 + fw * 0.5, h * 0.5, fw, h)
	bx.call(w * 0.5 - fw * 0.5, h * 0.5, fw, h)
	bx.call(0.0, fw * 0.5, w, fw)
	bx.call(0.0, h - fw * 0.5, w, fw)
	match kind:
		"big":
			var tr := h * 0.68
			bx.call(0.0, tr, w, fw * 0.8)
			bx.call(0.0, tr * 0.5, fw * 0.8, tr)
			for sx: float in [-1.0, 1.0]:
				# casement sashes, a touch proud of the frame
				var cx := sx * w * 0.25
				var sw := w * 0.5 - fw * 1.4
				bx.call(cx - sw * 0.5 + 0.02, tr * 0.5, 0.04, tr - fw * 1.6, zc + 0.025, 0.045)
				bx.call(cx + sw * 0.5 - 0.02, tr * 0.5, 0.04, tr - fw * 1.6, zc + 0.025, 0.045)
				bx.call(cx, fw + 0.02, sw, 0.04, zc + 0.025, 0.045)
				bx.call(cx, tr - fw - 0.02, sw, 0.04, zc + 0.025, 0.045)
				bx.call(cx + sx * -sw * 0.32, tr * 0.5, 0.018, 0.12, zc + 0.06, 0.03)
		"kitchen":
			var tr2 := h * 0.74
			bx.call(0.0, tr2, w, fw * 0.8)
			bx.call(0.0, tr2 * 0.5, fw * 0.8, tr2)
		"stair":
			bx.call(0.0, h * 0.5, fw * 0.8, h)
			bx.call(0.0, h * 0.5, w, fw * 0.8)
		"small":
			bx.call(0.0, h * 0.55, w, fw * 0.8)
		"bal":
			var dx := -w * 0.5 + 0.85
			bx.call(dx, h * 0.5, fw, h)
			bx.call((dx + w * 0.5) * 0.5, 0.9, w * 0.5 - 0.85 + w * 0.5, fw)
			# solid panels under the window and the lower half of the door
			b.box(Transform3D(Basis.IDENTITY, Vector3((dx + w * 0.5) * 0.5, 0.45, zc - 0.01)), Vector3(w * 0.5 - dx, 0.85, 0.03), white, 1.0)
			b.box(Transform3D(Basis.IDENTITY, Vector3((dx - w * 0.5) * 0.5, 0.5, zc - 0.01)), Vector3(dx + w * 0.5 - fw, 0.95, 0.03), white, 1.0)
			bx.call((dx - w * 0.5) * 0.5 + 0.25, 1.05, 0.03, 0.14, zc + 0.04, 0.03)
	return b.to_mesh(m.frame)


## A steel security cage in front of a window (opening space).
static func window_cage(kind: String, m: Dictionary) -> ArrayMesh:
	var s: Vector3 = WIN[kind]
	var w := s.x + 0.16
	var h := s.y + 0.12
	var d := 0.36
	var b := MBuf.new()
	var c := Color(1, 1, 1, 1)
	var bar := 0.014
	var x := -w * 0.5
	while x <= w * 0.5 + 0.001:
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5 - 0.06, d)), Vector3(bar, h, bar), c)
		x += 0.12
	for y: float in [-0.06, h * 0.45, h - 0.06]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(0, y, d)), Vector3(w, 0.025, 0.012), c)
		for sx: float in [-1.0, 1.0]:
			b.box(Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, y, d * 0.5)), Vector3(0.012, 0.025, d), c)
	for sx: float in [-1.0, 1.0]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, h * 0.5 - 0.06, d * 0.5)), Vector3(0.02, h, 0.02), c)
		b.box(Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, h * 0.5 - 0.06, d)), Vector3(0.025, h, 0.025), c)
	# a sloping rain sheet on top and a floor grid
	var top := Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0, h + 0.02, d * 0.5))
	b.box(top, Vector3(w + 0.06, 0.012, d + 0.08), c)
	x = -w * 0.5
	while x <= w * 0.5 + 0.001:
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, -0.06, d * 0.5)), Vector3(0.012, 0.012, d), c)
		x += 0.2
	return b.to_mesh(m.cage)


## Outdoor air-conditioning unit on its brackets (opening space, hung below a sill).
static func ac_unit(m: Dictionary) -> ArrayMesh:
	var b := MBuf.new()
	var c := Color(1, 1, 1, 1)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0.17)), Vector3(0.8, 0.54, 0.29), c)
	# grille: a dark disc behind rings and spokes
	var g := MBuf.new()
	for k in 5:
		var rr := 0.06 + k * 0.045
		for s in 24:
			var a0 := TAU * s / 24.0
			var a1 := TAU * (s + 1) / 24.0
			var p0 := Vector3(-0.12 + cos(a0) * rr, 0.28 + sin(a0) * rr, 0.318)
			var p1 := Vector3(-0.12 + cos(a1) * rr, 0.28 + sin(a1) * rr, 0.318)
			g.box(Transform3D(Basis.looking_at(p1 - p0, Vector3.BACK), (p0 + p1) * 0.5), Vector3(0.008, 0.008, p0.distance_to(p1)), c)
	for k in 6:
		var a := TAU * k / 6.0
		g.box(Transform3D(Basis(Vector3.BACK, a), Vector3(-0.12, 0.28, 0.32)), Vector3(0.44, 0.01, 0.01), c)
	for sx: float in [-0.3, 0.3]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(sx, 0.0, 0.2)), Vector3(0.04, 0.04, 0.42), c)
		b.box(Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(sx, 0.2, 0.18)), Vector3(0.035, 0.035, 0.52), c)
	var mesh := b.to_mesh(m.ac)
	g.commit(mesh, m.dark_metal)
	# the copper pipes into the wall
	var p := MBuf.new()
	p.tube(PackedVector3Array([Vector3(0.36, 0.3, 0.17), Vector3(0.46, 0.3, 0.17), Vector3(0.5, 0.5, 0.05), Vector3(0.5, 0.6, -0.05)]), taper(4, 0.012, 0.012), 5)
	p.commit(mesh, m.dark_metal)
	return mesh


## A balcony on the back wall (opening space of the balcony door: x across,
## y up from the floor, z out). enclosed: aluminium windows above the parapet.
static func balcony(m: Dictionary, enclosed: bool, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var mt := MBuf.new()
	var gl := MBuf.new()
	var c := Color(1, 1, 1, 1)
	var w := 3.0
	var d := 1.25
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.06, d * 0.5)), Vector3(w, 0.12, d), c)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.5, d - 0.05)), Vector3(w, 1.0, 0.1), c)
	for sx: float in [-1.0, 1.0]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.05), 0.5, d * 0.5)), Vector3(0.1, 1.0, d - 0.1), c)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.03, d - 0.05)), Vector3(w + 0.04, 0.06, 0.16), c)
	if enclosed:
		var top := FH - 0.12
		for sx: float in [-1.0, 1.0]:
			mt.box(Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.04), (1.06 + top) * 0.5, d * 0.5)), Vector3(0.05, top - 1.06, d - 0.1), c)
		var nseg := 4
		for k in nseg + 1:
			var x := -w * 0.5 + 0.04 + (w - 0.08) * float(k) / nseg
			mt.box(Transform3D(Basis.IDENTITY, Vector3(x, (1.06 + top) * 0.5, d - 0.06)), Vector3(0.045, top - 1.06, 0.06), c)
		mt.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.09, d - 0.06)), Vector3(w, 0.05, 0.08), c)
		mt.box(Transform3D(Basis.IDENTITY, Vector3(0, top - 0.03, d - 0.06)), Vector3(w, 0.06, 0.08), c)
		fquad(gl, Vector3(-w * 0.5, 1.1, d - 0.07), Vector3(w * 0.5, 1.1, d - 0.07), Vector3(w * 0.5, top - 0.05, d - 0.07), Vector3(-w * 0.5, top - 0.05, d - 0.07), Vector3.BACK,
				Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(rng.randf_range(0.0, 0.25), rng.randf(), rng.randf(), 0.0))
	else:
		# a rail on top of the parapet and laundry poles out over it
		mt.tube(PackedVector3Array([Vector3(-w * 0.5, 1.12, d - 0.05), Vector3(w * 0.5, 1.12, d - 0.05)]), taper(2, 0.02, 0.02), 6)
		for k in rng.randi_range(1, 2):
			var x := rng.randf_range(-1.1, 1.1)
			mt.tube(PackedVector3Array([Vector3(x, 2.3, 0.1), Vector3(x, 2.25, d + 0.5)]), taper(2, 0.012, 0.012), 4)
	var mesh := b.to_mesh(m.wall_bal, true)
	mt.commit(mesh, m.alu)
	gl.commit(mesh, m.glass_win)
	return mesh


## Laundry hanging from a pole or a line: a few cloth sheets (opening space of
## a balcony; the cloth shader sways them).
static func laundry(m: Dictionary, seed: int, width := 2.2) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MBuf.new()
	var x := -width * 0.5
	while x < width * 0.5 - 0.3:
		var w := rng.randf_range(0.3, 0.75)
		var h := rng.randf_range(0.45, 1.1)
		var col := Color(rng.randf(), rng.randf(), 0.0, 1.0)
		var segs := 4
		for j in segs:
			var t0 := float(j) / segs
			var t1 := float(j + 1) / segs
			var z0 := sin(t0 * 2.0) * 0.03
			var z1 := sin(t1 * 2.0) * 0.03
			var p0 := Vector3(x, -h * t0, z0)
			var p1 := Vector3(x + w, -h * t0, z0)
			var p2 := Vector3(x + w, -h * t1, z1)
			var p3 := Vector3(x, -h * t1, z1)
			fquad(b, p0, p1, p2, p3, Vector3.BACK, Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1), col)
		x += w + rng.randf_range(0.05, 0.25)
	return b.to_mesh(m.cloth)


## One whole block. spec: len, depth, floors, units, wall (Material), number,
## door (Material), seed, lit (fraction of lit windows), xf (Transform3D in the
## parent's space). Repeated parts are pushed into `parts` (kind -> Array of
## [Transform3D, Color custom]) for MultiMeshes. Returns {node, entrances:
## [{xf (opening transform of the entrance), unit}], collider size}.
static func block(parent: Node3D, m: Dictionary, spec: Dictionary, parts: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var L: float = spec.len
	var D: float = spec.depth
	var F: int = spec.floors
	var U: int = spec.units
	var xf: Transform3D = spec.xf
	var lit_p: float = spec.get("lit", 0.12)
	var root := Node3D.new()
	root.name = "Block%d" % int(spec.number)
	root.transform = xf
	parent.add_child(root)
	var walls := MBuf.new()
	var bands := MBuf.new()
	var plinth := MBuf.new()
	var roofb := MBuf.new()
	var pipes := MBuf.new()
	var metal := MBuf.new()
	var top := GF + F * FH
	var htop := top + 0.9
	var uw := L / U
	var entrances: Array = []
	# facade frames: o, r, n (r x up = -n), length
	var frames := {
		"front": [Vector3(0, 0, 0), Vector3.RIGHT, Vector3.FORWARD, L],
		"back": [Vector3(L, 0, D), Vector3.LEFT, Vector3.BACK, L],
		"left": [Vector3(0, 0, D), Vector3.FORWARD, Vector3.LEFT, D],
		"right": [Vector3(L, 0, 0), Vector3.BACK, Vector3.RIGHT, D],
	}
	for side: String in frames:
		var fr: Array = frames[side]
		var o: Vector3 = fr[0]
		var r: Vector3 = fr[1]
		var n: Vector3 = fr[2]
		var length: float = fr[3]
		var holes: Array = []
		var opens: Array = []        # [kind, u, y, floor, unit]
		if side == "front":
			for u in U:
				var xc := (u + 0.5) * uw
				holes.append(Rect2(xc - 0.8, GF, 1.6, 2.25))
				entrances.append({"u": xc, "unit": u + 1})
				for f in range(1, F):
					var s: Vector3 = WIN.stair
					var yc := GF + (f + 0.5) * FH
					opens.append(["stair", xc, yc - s.y * 0.5, f, u])
				var half := uw * 0.5 - 1.3
				for f in F:
					var yf := GF + f * FH
					for sd: float in [-1.0, 1.0]:
						var kx := xc + sd * (1.3 + 0.22 * half + 0.5)
						var bx := xc + sd * (1.3 + 0.7 * half + 0.75)
						opens.append(["kitchen", kx, yf + WIN.kitchen.z, f, u])
						opens.append(["big", bx, yf + WIN.big.z, f, u])
		elif side == "back":
			for u in U:
				var xc := (u + 0.5) * uw
				var half := uw * 0.5
				for f in F:
					var yf := GF + f * FH
					for sd: float in [-1.0, 1.0]:
						var px := xc + sd * minf(half * 0.55, 3.6)
						if f == 0:
							opens.append(["big", px, yf + WIN.big.z, f, u])
						else:
							opens.append(["bal", px, yf, f, u])
						opens.append(["small", xc + sd * 1.0, yf + WIN.small.z, f, u])
		else:
			for f in F:
				var yf := GF + f * FH
				opens.append(["small", 2.2, yf + WIN.small.z, f, 0])
				opens.append(["small", length - 2.2, yf + WIN.small.z, f, 0])
		for op: Array in opens:
			var s2: Vector3 = WIN[op[0]]
			holes.append(Rect2(float(op[1]) - s2.x * 0.5, float(op[2]), s2.x, s2.y))
		wall_with_holes(walls, o, r, n, length, -0.3, htop, holes)
		# windows and what hangs on them
		for op: Array in opens:
			var kind: String = op[0]
			var s3: Vector3 = WIN[kind]
			var oxf := xf * opening_xf(o, r, n, float(op[1]), float(op[2]))
			_push(parts, "frame_" + kind, oxf, Color(1, 1, 1, 1))
			var lit := 0.0
			var tv := 0.0
			var temp := rng.randf()
			if kind == "stair":
				lit = 1.0 if rng.randf() < lit_p * 0.9 else 0.0
				temp = rng.randf_range(0.6, 1.0)
			elif kind != "bal" or rng.randf() < 0.5:
				lit = 1.0 if rng.randf() < lit_p else 0.0
				tv = 1.0 if lit > 0.5 and rng.randf() < 0.18 else 0.0
			var gxf := oxf * Transform3D(Basis.from_scale(Vector3(s3.x - 0.04, s3.y - 0.04, 1.0)), Vector3(0, 0.02, -0.12))
			var sp: Vector2i = spec.get("someone", Vector2i(-1, -1))
			if kind == "kitchen" and side == "front" and int(op[4]) == sp.x and int(op[3]) == sp.y and not spec.has("_someone_done"):
				# her kitchen: lit, curtains drawn, someone standing behind them
				spec["_someone_done"] = true
				lit = 1.0
				temp = 0.08
				tv = 2.0
			_push(parts, "glass", gxf, Color(lit * rng.randf_range(0.6, 1.0) if tv < 1.5 else 0.95, temp, rng.randf(), tv))
			if kind == "kitchen" and side == "front" and rng.randf() < 0.45:
				# soot from the kitchen extractor, rising up the wall
				_push(parts, "streak", oxf * Transform3D(Basis(Vector3.BACK, PI) * Basis.from_scale(Vector3(s3.x + 0.1, rng.randf_range(0.5, 1.1), 1.0)), Vector3(0, s3.y + 0.05, 0.006)), Color(float(rng.randi_range(0, 3)) / 4.0, rng.randf_range(0.6, 0.95), 0, 0))
			if kind != "bal" and kind != "stair":
				_push(parts, "sill", oxf * Transform3D(Basis.from_scale(Vector3(s3.x + 0.12, 0.05, 0.32)), Vector3(0, -0.025, -0.1)), Color(1, 1, 1, 1))
			if kind == "stair":
				_push(parts, "sill", oxf * Transform3D(Basis.from_scale(Vector3(s3.x + 0.08, 0.04, 0.28)), Vector3(0, -0.02, -0.1)), Color(1, 1, 1, 1))
			var fl: int = op[3]
			if (kind == "big" or kind == "kitchen" or kind == "small") and side != "left" and side != "right":
				var cage_p := 0.75 if fl <= 1 else 0.12
				if rng.randf() < cage_p:
					_push(parts, "cage_" + kind, oxf, Color(1, 1, 1, 1))
				elif kind == "big" and fl > 0 and rng.randf() < 0.35:
					var ax := rng.randf_range(-0.3, 0.3)
					_push(parts, "ac", oxf * Transform3D(Basis.IDENTITY, Vector3(ax, -0.82, 0.0)), Color(1, 1, 1, 1))
					_push(parts, "streak", oxf * Transform3D(Basis.from_scale(Vector3(0.9, rng.randf_range(0.4, 0.62), 1.0)), Vector3(ax, -0.85, 0.006)), Color(float(rng.randi_range(0, 3)) / 4.0, rng.randf_range(0.45, 0.85), 0, 0))
			if kind == "bal":
				var enc := rng.randf() < 0.55
				_push(parts, "bal_closed" if enc else "bal_open", oxf, Color(1, 1, 1, 1))
				if not enc and rng.randf() < 0.6:
					_push(parts, "laundry", oxf * Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.3, 0.3), 2.24, 0.95)), Color(1, 1, 1, 1))
			elif rng.randf() < 0.7:
				_push(parts, "streak", oxf * Transform3D(Basis.from_scale(Vector3(s3.x + 0.2, rng.randf_range(0.4, 1.3), 1.0)), Vector3(0, -0.06, 0.006)), Color(float(rng.randi_range(0, 3)) / 4.0, rng.randf_range(0.35, 0.75), 0, 0))
		# long runs from the roof edge
		var end_wall := side == "left" or side == "right"
		var nruns := int(length / (2.5 if end_wall else 4.0))
		for k in nruns:
			var u2 := rng.randf_range(0.3, length - 0.3)
			if end_wall and absf(u2 - 2.2) < 0.6 or end_wall and absf(u2 - (length - 2.2)) < 0.6:
				continue
			var hh := rng.randf_range(3.0, 12.0) if end_wall else rng.randf_range(0.4, 1.0)
			var sxf := xf * opening_xf(o, r, n, u2, htop - 0.15)
			_push(parts, "streak", sxf * Transform3D(Basis.from_scale(Vector3(rng.randf_range(0.6, 1.8), hh, 1.0)), Vector3(0, 0, 0.007)), Color(float(rng.randi_range(0, 3)) / 4.0, rng.randf_range(0.3, 0.6), 0, 0))
		# floor bands and the plinth
		if side == "front" or side == "back":
			for f in range(1, F + 1):
				var yb := GF + f * FH - 0.06
				_band(bands, o, r, n, length, yb, 0.18, 0.05)
		_band(plinth, o, r, n, length, -0.3, GF + 0.6, 0.04)
		_band(bands, o, r, n, length + 0.0, htop, 0.08, 0.06)
	# roof slab, parapet inside faces, stair housings, tanks, heaters, aerials
	fquad(roofb, Vector3(0, top + 0.05, 0), Vector3(L, top + 0.05, 0), Vector3(L, top + 0.05, D), Vector3(0, top + 0.05, D), Vector3.UP,
			Vector2(0, 0), Vector2(L, 0), Vector2(L, D), Vector2(0, D))
	for pr: Array in [[Vector3(0.2, top, 0.2), Vector3(L - 0.2, top, 0.2), Vector3.BACK], [Vector3(L - 0.2, top, D - 0.2), Vector3(0.2, top, D - 0.2), Vector3.FORWARD],
			[Vector3(0.2, top, D - 0.2), Vector3(0.2, top, 0.2), Vector3.RIGHT], [Vector3(L - 0.2, top, 0.2), Vector3(L - 0.2, top, D - 0.2), Vector3.LEFT]]:
		var a: Vector3 = pr[0]
		var c: Vector3 = pr[1]
		fquad(walls, a, c, c + Vector3(0, 0.9, 0), a + Vector3(0, 0.9, 0), pr[2], Vector2(0, 0), Vector2(a.distance_to(c), 0), Vector2(a.distance_to(c), -0.9), Vector2(0, -0.9))
	for u in U:
		var xc := (u + 0.5) * uw
		walls.box(Transform3D(Basis.IDENTITY, Vector3(xc, top + 1.25, 2.2)), Vector3(2.8, 2.5, 3.2), Color(1, 1, 1, 1), 1.0, true)
		roofb.box(Transform3D(Basis.IDENTITY, Vector3(xc, top + 2.55, 2.2)), Vector3(3.0, 0.1, 3.4))
		metal.box(Transform3D(Basis.IDENTITY, Vector3(xc + 0.5, top + 1.0, 3.81)), Vector3(0.9, 1.9, 0.04))
		if rng.randf() < 0.7:
			# solar water heater: a tilted rack of glass tubes and a tank
			var hx := xc + rng.randf_range(-uw * 0.35, uw * 0.35)
			var hz := rng.randf_range(5.5, D - 1.5)
			var tilt := Basis(Vector3.RIGHT, -0.75)
			for t in 14:
				var tx := hx - 0.9 + t * 0.13
				metal.tube(PackedVector3Array([Vector3(tx, top + 0.25, hz + 0.6), Vector3(tx, top + 1.5, hz - 0.5)]), taper(2, 0.045, 0.045), 6)
			metal.tube(PackedVector3Array([Vector3(hx - 1.0, top + 1.62, hz - 0.62), Vector3(hx + 1.0, top + 1.62, hz - 0.62)]), taper(2, 0.17, 0.17), 10, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
			for sx: float in [-0.95, 0.95]:
				metal.box(Transform3D(tilt, Vector3(hx + sx, top + 0.8, hz)), Vector3(0.04, 0.04, 1.7))
				metal.box(Transform3D(Basis.IDENTITY, Vector3(hx + sx, top + 0.8, hz - 0.6)), Vector3(0.04, 1.6, 0.04))
		if rng.randf() < 0.5:
			var ax2 := xc + rng.randf_range(-3.0, 3.0)
			metal.tube(PackedVector3Array([Vector3(ax2, top, D - 1.0), Vector3(ax2, top + 3.2, D - 1.0)]), taper(2, 0.025, 0.02), 5)
			for k in 4:
				var yy := top + 2.0 + k * 0.32
				var hw := 0.7 - k * 0.12
				metal.tube(PackedVector3Array([Vector3(ax2 - hw, yy, D - 1.0), Vector3(ax2 + hw, yy, D - 1.0)]), taper(2, 0.008, 0.008), 4)
	if rng.randf() < 0.8:
		var tx2 := rng.randf_range(4.0, L - 4.0)
		metal.tube(PackedVector3Array([Vector3(tx2 - 1.3, top + 1.4, D * 0.6), Vector3(tx2 + 1.3, top + 1.4, D * 0.6)]), taper(2, 0.65, 0.65), 14, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-0.4, 0.4]:
				metal.box(Transform3D(Basis.IDENTITY, Vector3(tx2 + sx, top + 0.4, D * 0.6 + sz)), Vector3(0.06, 0.8, 0.06))
	# drainpipes on the long faces at the unit joints and the ends
	for side2: String in ["front", "back"]:
		var fr2: Array = frames[side2]
		var o2: Vector3 = fr2[0]
		var r2: Vector3 = fr2[1]
		var n2: Vector3 = fr2[2]
		for u in U + 1:
			var px := clampf(u * uw, 0.35, L - 0.35)
			if side2 == "front" and u > 0 and u < U:
				px += 1.4
			var base := o2 + r2 * px + n2 * 0.11
			var pts := PackedVector3Array([base + Vector3(0, -0.05, 0) + n2 * 0.12, base + Vector3(0, 0.25, 0) + n2 * 0.1, base + Vector3(0, 0.55, 0),
					base + Vector3(0, htop - 0.6, 0), base + Vector3(0, htop - 0.35, 0) - n2 * 0.02])
			pipes.tube(pts, taper(5, 0.055, 0.055), 8)
			pipes.box(Transform3D(Basis.IDENTITY, base + Vector3(0, htop - 0.2, 0.0) + n2 * 0.02), Vector3(0.24, 0.24, 0.24) + Vector3(absf(r2.x), 0, absf(r2.z)) * 0.08)
			var yy2 := 1.5
			while yy2 < htop - 1.0:
				pipes.box(Transform3D(Basis.IDENTITY, base + Vector3(0, yy2, 0) - n2 * 0.06), Vector3(0.14, 0.04, 0.14))
				yy2 += 2.2
	var mesh := ArrayMesh.new()
	walls.commit(mesh, spec.wall, true)
	bands.commit(mesh, m.band, true)
	plinth.commit(mesh, m.plinth, true)
	roofb.commit(mesh, m.roof, true)
	pipes.commit(mesh, m.pipe, true)
	metal.commit(mesh, m.galv, true)
	var bm := MeshInstance3D.new()
	bm.name = "Shell"
	bm.mesh = mesh
	root.add_child(bm)
	# painted block number high on both end walls
	for fr3: Array in [frames["left"], frames["right"]]:
		var o3: Vector3 = fr3[0]
		var r3: Vector3 = fr3[1]
		var n3: Vector3 = fr3[2]
		var sxf := opening_xf(o3, r3, n3, D * 0.5, top - 1.6)
		sign_quad(root, m, "block_%d" % int(spec.number), sxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.012)), 2.4)
	return {"node": root, "entrances": entrances, "top": htop}


static func _push(parts: Dictionary, kind: String, xf: Transform3D, c: Color) -> void:
	if not parts.has(kind):
		parts[kind] = []
	parts[kind].append([xf, c])


## A horizontal band proud of a facade (floor bands, plinth, coping).
static func _band(b: MBuf, o: Vector3, r: Vector3, n: Vector3, length: float, y: float, h: float, out: float) -> void:
	var c := o + r * (length * 0.5) + n * (out * 0.5) + Vector3.UP * (y + h * 0.5)
	var basis := Basis(r, Vector3.UP, r.cross(Vector3.UP))
	b.box(Transform3D(basis, c), Vector3(length + out * 2.0, h, out), Color(1, 1, 1, 1))


## A painted sign / notice from the signs atlas, `width` wide, on a wall
## (xf: x across, y up, facing +z).
static func sign_quad(parent: Node3D, m: Dictionary, cell: String, xf: Transform3D, width: float) -> MeshInstance3D:
	var idx: int = SIGN_CELLS.get(cell, 0)
	var cu := float(idx % 4) * 0.25
	var cv := float(idx / 4) * 0.25
	var h := width * 0.5
	var b := MBuf.new()
	fquad(b, Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(width * 0.5, h, 0), Vector3(-width * 0.5, h, 0), Vector3.BACK,
			Vector2(cu, cv + 0.25), Vector2(cu + 0.25, cv + 0.25), Vector2(cu + 0.25, cv), Vector2(cu, cv))
	var node := mi(parent, b.to_mesh(m.sign), Vector3.ZERO, Vector3.ZERO, false)
	node.transform = xf
	return node


## The entrance of one unit (in the block's opening space: x right seen from
## outside, y up from the street, z out from the wall). Steps, landing,
## canopy on brackets, a double steel door, a caged bulkhead lamp, the
## painted unit number, an intercom and notices. Returns the lamp light and
## bulb material and the collider boxes [size, Transform3D].
static func entrance(parent: Node3D, m: Dictionary, xf: Transform3D, unit: int, door_mat: Material, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var e := Node3D.new()
	e.name = "Entrance%d" % unit
	e.transform = xf
	parent.add_child(e)
	var conc := MBuf.new()
	var steel := MBuf.new()
	# landing and two worn steps (risers facing out)
	conc.box(Transform3D(Basis.IDENTITY, Vector3(0, GF * 0.5 - 0.1, 0.65)), Vector3(2.6, GF + 0.2, 1.3))
	var st0 := mi(e, MeshUtil.worn_step(2.2, 0.15, 0.32, seed, 1.2), Vector3(0, 0, 1.92), Vector3(0, PI, 0), true, m.step)
	st0.name = "Step0"
	mi(e, MeshUtil.worn_step(2.3, 0.3, 0.32, seed + 1, 0.8), Vector3(0, 0, 1.6), Vector3(0, PI, 0), true, m.step)
	# canopy slab with a lip, on two brackets
	var cy := GF + 2.55
	conc.box(Transform3D(Basis.IDENTITY, Vector3(0, cy, 0.75)), Vector3(2.7, 0.1, 1.5))
	conc.box(Transform3D(Basis.IDENTITY, Vector3(0, cy + 0.06, 1.47)), Vector3(2.7, 0.22, 0.06))
	for sx: float in [-1.15, 1.15]:
		conc.box(Transform3D(Basis(Vector3.RIGHT, 0.62), Vector3(sx, cy - 0.42, 0.42)), Vector3(0.1, 0.12, 1.05))
	# door frame and the two leaves (one a little open on its own: never, they're shut)
	var dz := -0.14
	for sx: float in [-0.8, 0.8]:
		steel.box(Transform3D(Basis.IDENTITY, Vector3(sx, GF + 1.125, dz)), Vector3(0.06, 2.25, 0.08))
	steel.box(Transform3D(Basis.IDENTITY, Vector3(0, GF + 2.22, dz)), Vector3(1.66, 0.06, 0.08))
	var mesh := conc.to_mesh(m.concrete, true)
	steel.commit(mesh, m.dark_metal, true)
	mi(e, mesh)
	for k in 2:
		var leaf := Node3D.new()
		leaf.position = Vector3(-0.78 if k == 0 else 0.78, GF + 0.02, dz)
		e.add_child(leaf)
		var sgn := 1.0 if k == 0 else -1.0
		rbox(leaf, Vector3(0.76, 2.16, 0.05), Vector3(sgn * 0.38, 1.08, 0), door_mat, 0.008)
		# a raised panel, a kick plate, a pull handle; wired glass in one leaf
		rbox(leaf, Vector3(0.6, 0.85, 0.012), Vector3(sgn * 0.38, 0.62, 0.028), door_mat, 0.004)
		rbox(leaf, Vector3(0.72, 0.18, 0.008), Vector3(sgn * 0.38, 0.1, 0.03), m.dark_metal, 0.003)
		rbox(leaf, Vector3(0.025, 0.32, 0.03), Vector3(sgn * 0.68, 1.05, 0.05), m.dark_metal, 0.006)
		if k == 1:
			rbox(leaf, Vector3(0.34, 0.42, 0.012), Vector3(sgn * 0.38, 1.55, 0.026), m.glass_door, 0.004)
		else:
			rbox(leaf, Vector3(0.6, 0.55, 0.012), Vector3(sgn * 0.38, 1.6, 0.028), door_mat, 0.004)
	# the bulkhead lamp under the canopy: a round cage over a glass dome
	var lamp := Node3D.new()
	lamp.position = Vector3(0, GF + 2.36, 0.02)
	e.add_child(lamp)
	cyl(lamp, 0.11, 0.11, 0.05, Vector3(0, 0, 0.025), m.dark_metal, 16, Vector3(PI * 0.5, 0, 0))
	var bulb_mat := (m.bulb as StandardMaterial3D).duplicate() as StandardMaterial3D
	var dome := SphereMesh.new()
	dome.radius = 0.085
	dome.height = 0.12
	dome.is_hemisphere = true
	mi(lamp, dome, Vector3(0, 0, 0.05), Vector3(PI * 0.5, 0, 0), false, bulb_mat)
	for k in 4:
		var a := k * PI * 0.25
		var cage := MBuf.new()
		var pts := PackedVector3Array()
		for i in 7:
			var t := PI * float(i) / 6.0
			pts.append(Vector3(cos(t) * 0.1 * cos(a), cos(t) * 0.1 * sin(a), 0.05 + sin(t) * 0.09))
		cage.tube(pts, taper(7, 0.005, 0.005), 4)
		mi(lamp, cage.to_mesh(m.dark_metal), Vector3.ZERO, Vector3.ZERO, false)
	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.05, 0.3)
	light.omni_range = 7.0
	light.omni_attenuation = 1.3
	light.light_energy = 1.4
	light.light_color = Color(0.74, 0.86, 1.0)
	light.light_volumetric_fog_energy = 1.2
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 10.0
	lamp.add_child(light)
	# unit number painted beside the door, an intercom, a notice or two
	sign_quad(e, m, "unit_%d" % clampi(unit, 1, 4), Transform3D(Basis.IDENTITY, Vector3(-1.45, GF + 1.35, 0.012)), 0.95)
	sign_quad(e, m, "intercom", Transform3D(Basis.IDENTITY, Vector3(1.12, GF + 1.15, 0.015)), 0.42)
	if rng.randf() < 0.8:
		sign_quad(e, m, "notice" if rng.randf() < 0.6 else "missing", Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.06, 0.06)), Vector3(1.3, GF + 1.55, 0.014)), 0.5)
	var cols := [
		[Vector3(2.6, GF, 1.3), Transform3D(Basis.IDENTITY, Vector3(0, GF * 0.5, 0.65))],
		[Vector3(2.4, 0.1, 1.25), Transform3D(Basis(Vector3.RIGHT, atan2(GF, 1.15)), Vector3(0, GF * 0.5 - 0.06, 1.85))],
	]
	return {"node": e, "light": light, "bulb": bulb_mat, "colliders": cols}

# ---------------------------------------------------------------------------
# street furniture. Builders take `cols` and append [size, local Transform3D]
# collider boxes in the returned node's space.
# ---------------------------------------------------------------------------
static func _col(cols: Array, size: Vector3, pos: Vector3, basis := Basis.IDENTITY) -> void:
	cols.append([size, Transform3D(basis, pos)])


## A street lamp: concrete footing, tapered steel pole, a curved arm reaching
## out along +x and a cobra-head luminaire with a glass bowl. kind "mercury"
## (cold blue-green) or "sodium" (orange). Returns {node, light, glass, halo}.
static func street_lamp(parent: Node3D, m: Dictionary, xf: Transform3D, kind: String, height: float, cols: Array) -> Dictionary:
	var n := Node3D.new()
	n.name = "Lamp"
	n.transform = xf
	parent.add_child(n)
	var pole := MBuf.new()
	var conc := MBuf.new()
	conc.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), Vector3(0.44, 0.3, 0.44))
	pole.tube(PackedVector3Array([Vector3(0, 0.14, 0), Vector3(0, 0.6, 0), Vector3(0, height * 0.5, 0), Vector3(0, height, 0)]),
			PackedFloat32Array([0.1, 0.085, 0.07, 0.05]), 8, 1.0)
	pole.tube(PackedVector3Array([Vector3(0, 0.14, 0), Vector3(0, 0.34, 0)]), taper(2, 0.13, 0.12), 8)
	pole.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.075)), Vector3(0.12, 0.3, 0.04))
	var arm := PackedVector3Array()
	for i in 9:
		var t := float(i) / 8.0
		var a := t * PI * 0.5
		arm.append(Vector3(sin(a) * 0.55 + t * t * 1.0, height + (1.0 - cos(a)) * 0.0 + sin(a) * 0.45 - t * t * 0.12, 0))
	pole.tube(arm, taper(9, 0.045, 0.032), 6)
	var tip := arm[8]
	var mesh := pole.to_mesh(m.lamp_pole, true)
	conc.commit(mesh, m.concrete, true)
	mi(n, mesh)
	var head := Node3D.new()
	head.position = tip + Vector3(0.32, -0.04, 0)
	head.rotation.z = -0.07
	n.add_child(head)
	rbox(head, Vector3(0.78, 0.15, 0.34), Vector3(0, 0.04, 0), m.lamp_head, 0.05)
	rbox(head, Vector3(0.5, 0.06, 0.24), Vector3(-0.12, 0.13, 0), m.lamp_head, 0.025)
	var glass := (m.lamp_glass as StandardMaterial3D).duplicate() as StandardMaterial3D
	var col := Color(0.56, 0.92, 0.86) if kind == "mercury" else Color(1.0, 0.56, 0.22)
	glass.emission = col
	var bowl := SphereMesh.new()
	bowl.radius = 0.3
	bowl.height = 0.18
	bowl.is_hemisphere = true
	var bm := mi(head, bowl, Vector3(0.04, -0.03, 0), Vector3(PI, 0, 0), false, glass)
	bm.scale = Vector3(1.15, 0.55, 0.62)
	var light := SpotLight3D.new()
	light.position = Vector3(0.04, -0.09, 0)
	light.rotation = Vector3(-PI * 0.5, 0, 0)
	light.light_color = col
	light.light_energy = 7.5 if kind == "mercury" else 6.5
	light.spot_range = 17.0
	light.spot_angle = 62.0
	light.spot_attenuation = 0.85
	light.spot_angle_attenuation = 1.4
	light.light_volumetric_fog_energy = 2.2
	light.shadow_enabled = false
	light.shadow_bias = 0.06
	light.shadow_normal_bias = 1.5
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_shadow = 30.0
	light.distance_fade_length = 12.0
	head.add_child(light)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	halo.mesh = q
	var hm := (m.halo as ShaderMaterial).duplicate() as ShaderMaterial
	hm.set_shader_parameter("color", col)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0.04, -0.1, 0)
	halo.extra_cull_margin = 2.0
	head.add_child(halo)
	_col(cols, Vector3(0.22, height, 0.22), Vector3(0, height * 0.5, 0))
	return {"node": n, "light": light, "glass": glass, "halo": hm, "color": col}


static func _ring(b: MBuf, center: Vector3, axis_x: Vector3, axis_y: Vector3, r: float, tr: float, segs := 24, sides := 5) -> void:
	var pts := PackedVector3Array()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		pts.append(center + axis_x * cos(a) * r + axis_y * sin(a) * r)
	b.tube(pts, taper(segs + 1, tr, tr), sides)


## An old upright bicycle (the black Flying-Pigeon kind), along +x, wheels on y = 0.
static func bicycle(m: Dictionary, paint: Material) -> ArrayMesh:
	var fr := MBuf.new()
	var ch := MBuf.new()
	var rb := MBuf.new()
	var wr := 0.34
	var rear := Vector3(-0.53, wr, 0)
	var front := Vector3(0.55, wr, 0)
	var bb := Vector3(0.0, 0.3, 0)
	var seat := Vector3(-0.13, 0.86, 0)
	var head_t := Vector3(0.44, 0.92, 0)
	var head_b := Vector3(0.48, 0.74, 0)
	for w: Vector3 in [rear, front]:
		_ring(rb, w, Vector3.RIGHT, Vector3.UP, wr - 0.018, 0.019, 28, 6)
		_ring(ch, w, Vector3.RIGHT, Vector3.UP, wr - 0.045, 0.008, 28, 4)
		for s in 18:
			var a := TAU * s / 18.0
			var e := w + Vector3(cos(a), sin(a), 0) * (wr - 0.05)
			ch.tube(PackedVector3Array([w + Vector3(0, 0, 0.03 if s % 2 == 0 else -0.03), e]), taper(2, 0.0018, 0.0018), 3)
		ch.tube(PackedVector3Array([w + Vector3(0, 0, -0.05), w + Vector3(0, 0, 0.05)]), taper(2, 0.022, 0.022), 8)
		# mudguard
		var mg := PackedVector3Array()
		for i in 10:
			var a2 := lerpf(0.15, PI * 0.95, float(i) / 9.0) + (0.0 if w == rear else 0.2)
			mg.append(w + Vector3(cos(a2) * (wr + 0.035) * (-1.0 if w == rear else 1.0), sin(a2) * (wr + 0.035), 0))
		fr.tube(mg, taper(10, 0.022, 0.022), 4)
	var tubes := [[bb, head_b, 0.016], [seat, head_t, 0.015], [bb, seat + Vector3(0.01, 0.04, 0), 0.016],
		[head_b, head_t, 0.019]]
	for z: float in [-0.045, 0.045]:
		tubes.append([bb + Vector3(0, 0, z * 0.5), rear + Vector3(0, 0, z), 0.01])
		tubes.append([seat + Vector3(0, -0.05, z * 0.4), rear + Vector3(0, 0, z), 0.009])
		tubes.append([head_b + Vector3(0, 0, z * 0.5), front + Vector3(0.02, 0, z), 0.011])
	for t: Array in tubes:
		fr.tube(PackedVector3Array([t[0], t[1]]), taper(2, t[2], t[2]), 6)
	# rear rack over the back wheel
	for z: float in [-0.08, 0.08]:
		fr.tube(PackedVector3Array([rear + Vector3(0, 0, z), rear + Vector3(-0.05, 0.42, z)]), taper(2, 0.007, 0.007), 4)
		fr.tube(PackedVector3Array([seat + Vector3(-0.05, -0.04, z * 0.5), rear + Vector3(-0.3, 0.42, z)]), taper(2, 0.007, 0.007), 4)
	for k in 5:
		var x := -0.12 - k * 0.07
		ch.tube(PackedVector3Array([Vector3(x - 0.3, wr + 0.42, -0.09), Vector3(x - 0.3, wr + 0.42, 0.09)]), taper(2, 0.006, 0.006), 4)
	# handlebar, stem, grips, saddle, cranks, pedals, chainring, stand
	ch.tube(PackedVector3Array([head_t, head_t + Vector3(-0.02, 0.12, 0)]), taper(2, 0.012, 0.012), 6)
	var hb := head_t + Vector3(-0.02, 0.12, 0)
	ch.tube(PackedVector3Array([hb + Vector3(-0.12, 0.02, -0.28), hb + Vector3(0.02, 0, -0.18), hb + Vector3(0.04, 0, 0), hb + Vector3(0.02, 0, 0.18), hb + Vector3(-0.12, 0.02, 0.28)]), taper(5, 0.011, 0.011), 6)
	for z: float in [-0.28, 0.28]:
		rb.tube(PackedVector3Array([hb + Vector3(-0.1, 0.02, z * 0.85), hb + Vector3(-0.2, 0.03, z * 1.08)]), taper(2, 0.017, 0.017), 6, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
	rb.box(Transform3D(Basis.IDENTITY, seat + Vector3(-0.02, 0.07, 0)), Vector3(0.26, 0.06, 0.15))
	ch.tube(PackedVector3Array([seat + Vector3(0, 0.02, 0), seat + Vector3(-0.01, 0.06, 0)]), taper(2, 0.012, 0.012), 6)
	_ring(ch, bb + Vector3(0, 0, 0.06), Vector3.RIGHT, Vector3.UP, 0.09, 0.012, 20, 4)
	for z: float in [-0.08, 0.08]:
		var cp := bb + Vector3(0.0, -0.12 if z > 0 else 0.12, z)
		ch.tube(PackedVector3Array([bb + Vector3(0, 0, z), cp]), taper(2, 0.01, 0.01), 4)
		rb.box(Transform3D(Basis.IDENTITY, cp + Vector3(0, 0, z * 0.5)), Vector3(0.1, 0.02, 0.07))
	ch.tube(PackedVector3Array([rear + Vector3(0.1, 0, 0.05), rear + Vector3(0.14, -0.33, 0.12)]), taper(2, 0.008, 0.008), 4)
	var mesh := fr.to_mesh(paint)
	ch.commit(mesh, m.chrome)
	rb.commit(mesh, m.rubber)
	return mesh


## The bike shed: steel posts, a sloping corrugated roof and back wall, a rail,
## bicycles under it and a fluorescent tube. Open along +z. 4 m deep along z?
## No: size.x along the shed, depth 3.2 along z, back wall at z = 0.
static func bike_shed(parent: Node3D, m: Dictionary, xf: Transform3D, length: float, bikes: Array, cols: Array, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "BikeShed"
	n.transform = xf
	parent.add_child(n)
	var steel := MBuf.new()
	var sheet := MBuf.new()
	var d := 3.2
	var h0 := 2.35
	var h1 := 2.75
	var x := 0.0
	while x <= length + 0.01:
		steel.box(Transform3D(Basis.IDENTITY, Vector3(x, h1 * 0.5, 0.1)), Vector3(0.08, h1, 0.08))
		steel.box(Transform3D(Basis.IDENTITY, Vector3(x, h0 * 0.5, d)), Vector3(0.08, h0, 0.08))
		steel.box(Transform3D(Basis(Vector3.RIGHT, atan2(h1 - h0, d)), Vector3(x, (h0 + h1) * 0.5 + 0.03, d * 0.5)), Vector3(0.06, 0.1, d + 0.4))
		x += length / ceilf(length / 2.6)
	# corrugated roof and back wall (sine profile)
	var roof_pts := 64
	for i in roof_pts:
		var u0 := float(i) / roof_pts * length
		var u1 := float(i + 1) / roof_pts * length
		var y0o := sin(float(i) * PI * 0.5) * 0.02
		var y1o := sin(float(i + 1) * PI * 0.5) * 0.02
		var a0 := Vector3(u0, h1 + 0.1 + y0o, -0.15)
		var b0 := Vector3(u1, h1 + 0.1 + y1o, -0.15)
		var a1 := Vector3(u0, h0 + 0.1 + y0o, d + 0.25)
		var b1 := Vector3(u1, h0 + 0.1 + y1o, d + 0.25)
		var nn := Vector3(-(y1o - y0o) / (u1 - u0) * 0.5, 1.0, 0.12).normalized()
		fquad(sheet, a0, b0, b1, a1, nn, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, d), Vector2(u0, d))
		fquad(sheet, a0, b0, b1, a1, -nn, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, d), Vector2(u0, d))
		var w0 := Vector3(u0, 0.05, 0.05 + y0o)
		var w1 := Vector3(u1, 0.05, 0.05 + y1o)
		var nw := Vector3(-(y1o - y0o) / (u1 - u0) * 0.5, 0.0, 1.0).normalized()
		fquad(sheet, w0, w1, w1 + Vector3(0, h1, 0), w0 + Vector3(0, h1, 0), nw, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, -h1), Vector2(u0, -h1))
		fquad(sheet, w0, w1, w1 + Vector3(0, h1, 0), w0 + Vector3(0, h1, 0), -nw, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, -h1), Vector2(u0, -h1))
	steel.tube(PackedVector3Array([Vector3(0, 0.35, 0.7), Vector3(length, 0.35, 0.7)]), taper(2, 0.02, 0.02), 6)
	var mesh := sheet.to_mesh(m.corrugated, true)
	steel.commit(mesh, m.galv, true)
	mi(n, mesh)
	# bicycles parked nose-in against the rail
	var bx := 0.6
	var k := 0
	while bx < length - 0.4:
		if rng.randf() < 0.82:
			var bike: Mesh = bikes[k % bikes.size()]
			var lean := rng.randf_range(-0.06, 0.06)
			mi(n, bike, Vector3(bx, 0, 0.75), Vector3(lean, -PI * 0.5 + rng.randf_range(-0.12, 0.12), 0))
			k += 1
		bx += rng.randf_range(0.55, 0.8)
	# the tube light under the roof (the builder animates it)
	var tube_mat := (m.bulb as StandardMaterial3D).duplicate() as StandardMaterial3D
	tube_mat.emission = Color(0.7, 0.95, 0.85)
	var tl := cyl(n, 0.018, 0.018, 1.2, Vector3(length * 0.5, h0 + 0.12, d * 0.6), tube_mat, 8, Vector3(0, 0, PI * 0.5), false)
	tl.name = "Tube"
	rbox(n, Vector3(1.3, 0.05, 0.08), Vector3(length * 0.5, h0 + 0.16, d * 0.6), m.galv, 0.01)
	var light := OmniLight3D.new()
	light.position = Vector3(length * 0.5, h0 - 0.1, d * 0.6)
	light.light_color = Color(0.72, 0.96, 0.86)
	light.light_energy = 1.1
	light.omni_range = 6.0
	light.light_volumetric_fog_energy = 0.8
	n.add_child(light)
	_col(cols, Vector3(length, h1, 0.2), Vector3(length * 0.5, h1 * 0.5, 0.05))
	x = 0.0
	while x <= length + 0.01:
		_col(cols, Vector3(0.12, h0, 0.12), Vector3(x, h0 * 0.5, d))
		x += length / ceilf(length / 2.6)
	_col(cols, Vector3(length, 1.0, 1.1), Vector3(length * 0.5, 0.5, 0.75))
	return {"node": n, "light": light, "tube": tube_mat}


## A 240 l wheelie bin (front +z), lid shut or thrown back.
static func wheelie_bin(parent: Node3D, m: Dictionary, xf: Transform3D, mat: Material, open_lid: bool, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	var b := MBuf.new()
	var w0 := Vector2(0.5, 0.58)
	var w1 := Vector2(0.58, 0.72)
	var h := 0.95
	var corners := [Vector3(-w0.x, 0.06, -w0.y), Vector3(w0.x, 0.06, -w0.y), Vector3(w0.x, 0.06, w0.y), Vector3(-w0.x, 0.06, w0.y),
		Vector3(-w1.x, h, -w1.y), Vector3(w1.x, h, -w1.y), Vector3(w1.x, h, w1.y), Vector3(-w1.x, h, w1.y)]
	for i in 4:
		corners[i] = corners[i] * Vector3(0.5, 1, 0.5)
		corners[i + 4] = corners[i + 4] * Vector3(0.5, 1, 0.5)
	for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var p0: Vector3 = corners[f[0]]
		var p1: Vector3 = corners[f[1]]
		var p2: Vector3 = corners[f[2]]
		var p3: Vector3 = corners[f[3]]
		var nn := (p1 - p0).cross(p3 - p0).normalized()
		if nn.dot((p0 + p2) * 0.5 - Vector3(0, 0.5, 0)) < 0.0:
			nn = -nn
		fquad(b, p0, p1, p2, p3, nn, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	fquad(b, corners[0], corners[1], corners[2], corners[3], Vector3.DOWN, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, h - 0.04, -w1.y * 0.5 - 0.04)), Vector3(w1.x + 0.06, 0.08, 0.08))
	var mesh := b.to_mesh(mat)
	mi(n, mesh)
	var lid := Node3D.new()
	lid.position = Vector3(0, h + 0.02, -w1.y * 0.5 - 0.04)
	n.add_child(lid)
	rbox(lid, Vector3(w1.x + 0.06, 0.05, w1.y + 0.06), Vector3(0, 0, w1.y * 0.5 + 0.04), mat, 0.02)
	if open_lid:
		lid.rotation.x = -1.9
	for sx: float in [-1.0, 1.0]:
		cyl(n, 0.1, 0.1, 0.06, Vector3(sx * 0.27, 0.1, -w0.y * 0.5 + 0.02), m.rubber, 14, Vector3(0, 0, PI * 0.5))
	cyl(n, 0.015, 0.015, w1.x + 0.1, Vector3(0, h - 0.12, -w1.y * 0.5 - 0.1), m.dark_metal, 6, Vector3(0, 0, PI * 0.5))
	_col(cols, Vector3(0.62, 1.0, 0.78), Vector3(0, 0.5, 0))
	return n


## Rubbish bags: lumpy black / blue plastic blobs.
static func rubbish_bag(parent: Node3D, m: Dictionary, pos: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.5
	sm.radial_segments = 12
	sm.rings = 8
	var bag := mi(parent, sm, pos + Vector3(0, 0.2, 0), Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)), true,
			m.bag_black if rng.randf() < 0.7 else m.bag_blue)
	bag.scale = Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.2))
	var knot := cyl(bag, 0.02, 0.06, 0.12, Vector3(0, 0.27, 0), bag.material_override, 8)
	knot.rotation.z = rng.randf_range(-0.4, 0.4)


## A boxy 1990s saloon along +x (front at +x). wreck: rusted, sunk on flat
## tyres, glass gone, moss.
static func car(parent: Node3D, m: Dictionary, xf: Transform3D, paint: Material, wreck: bool, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "Car"
	n.transform = xf
	parent.add_child(n)
	var body := Node3D.new()
	body.position.y = -0.14 if wreck else 0.0
	body.rotation = Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.04, 0.04) if wreck else 0.0)
	n.add_child(body)
	var prof := PackedVector2Array([Vector2(-2.27, 0.33), Vector2(2.24, 0.33), Vector2(2.3, 0.5), Vector2(2.27, 0.8), Vector2(1.2, 0.88),
		Vector2(0.56, 1.36), Vector2(-0.82, 1.38), Vector2(-1.62, 0.94), Vector2(-2.24, 0.9), Vector2(-2.31, 0.62)])
	var b := MBuf.new()
	var hw := 0.84
	var tri := Geometry2D.triangulate_polygon(prof)
	for sgn: float in [-1.0, 1.0]:
		var zz := sgn * hw
		for i in range(0, tri.size(), 3):
			var pa := prof[tri[i]]
			var pb := prof[tri[i + 1]]
			var pc := prof[tri[i + 2]]
			var za := zz * _car_inset(pa.y)
			var zb := zz * _car_inset(pb.y)
			var zc := zz * _car_inset(pc.y)
			var a := Vector3(pa.x, pa.y, za)
			var bb := Vector3(pb.x, pb.y, zb)
			var c := Vector3(pc.x, pc.y, zc)
			var nn := Vector3(0, 0, sgn)
			var i0 := b.add(a, nn, Vector2(pa.x, -pa.y), Color(1, 1, 1, 1))
			var i1 := b.add(bb, nn, Vector2(pb.x, -pb.y), Color(1, 1, 1, 1))
			var i2 := b.add(c, nn, Vector2(pc.x, -pc.y), Color(1, 1, 1, 1))
			if (bb - a).cross(c - a).dot(nn) > 0.0:
				b.tri_idx(i0, i2, i1)
			else:
				b.tri_idx(i0, i1, i2)
	for i in prof.size():
		var p0 := prof[i]
		var p1 := prof[(i + 1) % prof.size()]
		var a0 := Vector3(p0.x, p0.y, -hw * _car_inset(p0.y))
		var a1 := Vector3(p1.x, p1.y, -hw * _car_inset(p1.y))
		var c0 := Vector3(p0.x, p0.y, hw * _car_inset(p0.y))
		var c1 := Vector3(p1.x, p1.y, hw * _car_inset(p1.y))
		var e := p1 - p0
		var nn2 := Vector3(e.y, -e.x, 0).normalized()
		fquad(b, a0, a1, c1, c0, nn2, Vector2(0, 0), Vector2(e.length(), 0), Vector2(e.length(), 1.7), Vector2(0, 1.7))
	var shell := b.to_mesh(m.rust if wreck else paint, true)
	mi(body, shell)
	# glass: windscreen, rear window, side windows (dark, a little proud)
	var g := MBuf.new()
	var gc := Color(1, 1, 1, 1)
	var ws := [Vector2(1.16, 0.9), Vector2(0.6, 1.33)]
	var rs := [Vector2(-0.84, 1.35), Vector2(-1.58, 0.96)]
	for pair: Array in [ws, rs]:
		var q0: Vector2 = pair[0]
		var q1: Vector2 = pair[1]
		var e2 := (q1 - q0)
		var nn3 := Vector3(e2.y, -e2.x, 0).normalized()
		if nn3.y < 0.0:
			nn3 = -nn3
		var off := nn3 * 0.008
		fquad(g, Vector3(q0.x, q0.y, -0.7 * _car_inset(q0.y)) + off, Vector3(q1.x, q1.y, -0.62) + off, Vector3(q1.x, q1.y, 0.62) + off, Vector3(q0.x, q0.y, 0.7 * _car_inset(q0.y)) + off, nn3,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), gc)
	for sgn2: float in [-1.0, 1.0]:
		var poly := [Vector2(1.08, 0.92), Vector2(0.56, 1.3), Vector2(-0.78, 1.32), Vector2(-1.5, 0.95)]
		var pts3: Array[Vector3] = []
		for pp: Vector2 in poly:
			pts3.append(Vector3(pp.x, pp.y, sgn2 * (hw * _car_inset(pp.y) + 0.006)))
		fquad(g, pts3[0], pts3[1], pts3[2], pts3[3], Vector3(0, 0, sgn2), Vector2(0, 1), Vector2(0.3, 0), Vector2(0.8, 0), Vector2(1, 1), gc)
	if not wreck:
		g.commit(shell, m.car_glass)
	else:
		var shards := MBuf.new()
		for k in 3:
			var p := Vector3(rng.randf_range(-0.6, 0.9), rng.randf_range(0.95, 1.2), rng.randf_range(-0.7, 0.7))
			fquad(shards, p, p + Vector3(0.12, 0.05, 0), p + Vector3(0.05, 0.18, 0.02), p + Vector3(-0.04, 0.1, 0), Vector3(0, 0, 1),
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		shards.commit(shell, m.car_glass)
	# window frames / pillars, door seams, bumpers, lights, plates, mirrors, wheels
	var trim := MBuf.new()
	for sgn3: float in [-1.0, 1.0]:
		var z := sgn3 * (hw + 0.004)
		for sx: float in [0.95, -0.25]:
			trim.box(Transform3D(Basis.IDENTITY, Vector3(sx, 0.6, z)), Vector3(0.006, 0.5, 0.004))
		trim.box(Transform3D(Basis.IDENTITY, Vector3(-0.12, 0.84, z * 1.0)), Vector3(2.4, 0.03, 0.01))
		trim.box(Transform3D(Basis.IDENTITY, Vector3(0.6, 0.7, z * 1.006)), Vector3(0.14, 0.02, 0.02))
		trim.box(Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.7, z * 1.006)), Vector3(0.14, 0.02, 0.02))
	for sx2: float in [-1.0, 1.0]:
		trim.box(Transform3D(Basis.IDENTITY, Vector3(sx2 * 2.3, 0.42, 0)), Vector3(0.12, 0.15, 1.72))
	var tmesh := trim.to_mesh(m.rubber)
	mi(body, tmesh)
	for sz: float in [-0.56, 0.56]:
		rbox(body, Vector3(0.04, 0.12, 0.3), Vector3(2.29, 0.66, sz), m.car_light, 0.01)
		rbox(body, Vector3(0.04, 0.12, 0.26), Vector3(-2.31, 0.7, sz * 1.05), m.tail_light, 0.01)
	for sx3: float in [-1.0, 1.0]:
		rbox(body, Vector3(0.02, 0.13, 0.42), Vector3(sx3 * 2.37, 0.45, 0), m.plate, 0.005)
	for sz2: float in [-1.0, 1.0]:
		rbox(body, Vector3(0.08, 0.09, 0.12), Vector3(1.05, 0.95, sz2 * 0.88), m.rubber, 0.02)
	for wx: float in [-1.33, 1.32]:
		for wz: float in [-0.73, 0.73]:
			var wheel := Node3D.new()
			wheel.position = Vector3(wx, 0.31 if not wreck else 0.24, wz)
			body.add_child(wheel)
			var tyre := cyl(wheel, 0.31, 0.31, 0.19, Vector3.ZERO, m.rubber, 20, Vector3(PI * 0.5, 0, 0))
			if wreck:
				tyre.scale = Vector3(1.0, 1.0, 0.82)
			cyl(wheel, 0.18, 0.18, 0.2, Vector3.ZERO, m.rust if wreck else m.chrome, 16, Vector3(PI * 0.5, 0, 0))
	if not wreck:
		# a drift of dead leaves on the bonnet and roof
		var lv := MBuf.new()
		for k in 18:
			var p := Vector3(rng.randf_range(-0.7, 2.0), 0.0, rng.randf_range(-0.6, 0.6))
			p.y = 1.39 if p.x < 0.5 and p.x > -0.75 else (0.89 if p.x > 1.2 else -1.0)
			if p.y < 0.0:
				continue
			var s := rng.randf_range(0.08, 0.16)
			var a := rng.randf() * TAU
			var dx := Vector3(cos(a), 0, sin(a)) * s
			var dz := Vector3(-sin(a), 0, cos(a)) * s
			fquad(lv, p - dx - dz + Vector3(0, 0.01, 0), p + dx - dz + Vector3(0, 0.01, 0), p + dx + dz + Vector3(0, 0.01, 0), p - dx + dz + Vector3(0, 0.01, 0), Vector3.UP,
					Vector2(0.4, 0.6), Vector2(0.6, 0.6), Vector2(0.6, 0.4), Vector2(0.4, 0.4), Color(0, 0, 0, 1))
		if not lv.v.is_empty():
			mi(body, lv.to_mesh(m.leaf_twigs), Vector3.ZERO, Vector3.ZERO, false)
	_col(cols, Vector3(4.62, 1.4, 1.76), Vector3(0, 0.75, 0))
	return n


static func _car_inset(y: float) -> float:
	return lerpf(1.0, 0.84, clampf((y - 0.86) / 0.5, 0.0, 1.0))


## A park bench: concrete ends, wooden slats, facing +z.
static func bench(parent: Node3D, m: Dictionary, xf: Transform3D, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	for sx: float in [-0.85, 0.85]:
		rbox(n, Vector3(0.09, 0.44, 0.5), Vector3(sx, 0.22, 0.0), m.concrete, 0.015)
		rbox(n, Vector3(0.07, 0.5, 0.07), Vector3(sx, 0.7, -0.24), m.dark_metal, 0.01, Vector3(-0.15, 0, 0))
	for k in 3:
		rbox(n, Vector3(1.9, 0.035, 0.11), Vector3(0, 0.455, -0.16 + k * 0.13), m.wood_slat, 0.008)
	for k in 2:
		rbox(n, Vector3(1.9, 0.1, 0.03), Vector3(0, 0.66 + k * 0.17, -0.26 - k * 0.03), m.wood_slat, 0.008, Vector3(-0.15, 0, 0))
	_col(cols, Vector3(1.95, 0.9, 0.6), Vector3(0, 0.45, -0.05))
	return n


## The stone table and four drum stools of a Chinese courtyard.
static func stone_table(parent: Node3D, m: Dictionary, pos: Vector3, cols: Array) -> Node3D:
	var n := node(parent, pos, 0.0, "StoneTable")
	var ped := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.06), Vector2(0.62, 0.12), Vector2(0.5, 0.4), Vector2(0.55, 0.62), Vector2(0.75, 0.68), Vector2(0.0, 0.68)]
	mi(n, MeshUtil.lathe(PackedVector2Array(ped), Vector2(0.24, 0.24), 2.0, 24), Vector3.ZERO, Vector3.ZERO, true, m.granite)
	var top := [Vector2(0.0, 0.68), Vector2(0.97, 0.68), Vector2(1.0, 0.7), Vector2(1.0, 0.75), Vector2(0.97, 0.77), Vector2(0.0, 0.77)]
	mi(n, MeshUtil.lathe(PackedVector2Array(top), Vector2(0.48, 0.48), 2.0, 32), Vector3.ZERO, Vector3.ZERO, true, m.granite)
	_col(cols, Vector3(0.96, 0.78, 0.96), Vector3(0, 0.39, 0))
	for k in 4:
		var a := k * PI * 0.5 + 0.4
		var p := Vector3(cos(a) * 0.82, 0, sin(a) * 0.82)
		var drum := [Vector2(0.0, 0.0), Vector2(0.8, 0.0), Vector2(0.95, 0.05), Vector2(1.0, 0.2), Vector2(0.95, 0.38), Vector2(0.85, 0.42), Vector2(0.0, 0.42)]
		mi(n, MeshUtil.lathe(PackedVector2Array(drum), Vector2(0.18, 0.18), 2.0, 18), p, Vector3.ZERO, true, m.granite)
		_col(cols, Vector3(0.36, 0.42, 0.36), p + Vector3(0, 0.21, 0))
	return n


## Iron railings on a low concrete plinth from a to c (ground y of each end
## given in a.y / c.y). A gap (metres along) leaves the bars bent apart and the
## plinth broken so you can step through. Appends colliders (parent space).
static func railing(bars: MBuf, conc: MBuf, a: Vector3, c: Vector3, rng: RandomNumberGenerator, cols: Array, gap := Vector2(-1, -1)) -> void:
	var d := c - a
	var length := Vector2(d.x, d.z).length()
	var dir := Vector3(d.x, 0, d.z) / maxf(length, 0.001)
	var side := Vector3(-dir.z, 0, dir.x)
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var wc := Color(1, 1, 1, 1)
	var segs: Array = []
	if gap.x >= 0.0:
		segs = [Vector2(0.0, gap.x), Vector2(gap.y, length)]
	else:
		segs = [Vector2(0.0, length)]
	for sg: Vector2 in segs:
		if sg.y - sg.x < 0.05:
			continue
		var mid := a + dir * (sg.x + sg.y) * 0.5
		mid.y = lerpf(a.y, c.y, (sg.x + sg.y) * 0.5 / length)
		conc.box(Transform3D(basis, mid + Vector3(0, 0.05, 0)), Vector3(sg.y - sg.x, 0.42, 0.22), wc)
		for ry: float in [0.42, 1.72]:
			bars.box(Transform3D(basis, mid + Vector3(0, ry, 0)), Vector3(sg.y - sg.x, 0.04, 0.016), wc)
		var cm := mid + Vector3(0, 1.0, 0)
		cols.append([Vector3(sg.y - sg.x, 2.0, 0.26), Transform3D(basis, cm)])
		var t := sg.x + 0.06
		while t < sg.y - 0.03:
			var p := a + dir * t
			p.y = lerpf(a.y, c.y, t / length)
			bars.box(Transform3D(basis, p + Vector3(0, 1.08, 0)), Vector3(0.018, 1.56, 0.018), wc)
			bars.box(Transform3D(basis * Basis(Vector3.BACK, PI * 0.25), p + Vector3(0, 1.9, 0)), Vector3(0.035, 0.035, 0.012), wc)
			t += 0.13
		var pt := sg.x
		while pt <= sg.y + 0.01:
			var pp := a + dir * pt
			pp.y = lerpf(a.y, c.y, pt / length)
			bars.box(Transform3D(basis, pp + Vector3(0, 1.0, 0)), Vector3(0.06, 1.9, 0.06), wc)
			bars.box(Transform3D(basis, pp + Vector3(0, 1.98, 0)), Vector3(0.09, 0.05, 0.09), wc)
			pt += minf(2.4, maxf(sg.y - sg.x, 0.1))
	if gap.x >= 0.0:
		# bars wrenched apart at both sides of the gap, one lying in the grass
		for e in 2:
			var tt := gap.x if e == 0 else gap.y
			var outw := -1.0 if e == 0 else 1.0
			for k in 3:
				var p0 := a + dir * (tt + outw * (0.1 + k * 0.13))
				p0.y = lerpf(a.y, c.y, tt / length)
				var pts := PackedVector3Array()
				for i in 6:
					var f := float(i) / 5.0
					var bend := sin(f * PI) * (0.35 - k * 0.1) * (1.0 if rng.randf() < 0.8 else -0.5)
					pts.append(p0 + Vector3(0, 0.3 + f * 1.55, 0) + dir * outw * bend + side * bend * 0.4)
				bars.tube(pts, taper(6, 0.01, 0.01), 4)
		var fall := a + dir * (gap.x + gap.y) * 0.5 + side * 0.6
		fall.y = lerpf(a.y, c.y, (gap.x + gap.y) * 0.5 / length) + 0.02
		bars.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5), fall + Vector3(0, 0.0, 0)), Vector3(0.018, 1.5, 0.018), wc)


## The guard hut and the accordion gate at the estate's main entrance (gate
## along +x from x = 0 to `gate_len`, hut beyond its end).
static func gatehouse(parent: Node3D, m: Dictionary, xf: Transform3D, gate_len: float, cols: Array) -> Dictionary:
	var n := Node3D.new()
	n.name = "Gate"
	n.transform = xf
	parent.add_child(n)
	var g := MBuf.new()
	var wc := Color(1, 1, 1, 1)
	var sec := 0.42
	var cnt := int(gate_len / sec)
	for k in cnt:
		var x0 := k * sec
		g.box(Transform3D(Basis.IDENTITY, Vector3(x0, 0.85, 0)), Vector3(0.03, 1.5, 0.05), wc)
		for sgn: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(Vector3.BACK, sgn * 1.2), Vector3(x0 + sec * 0.5, 0.85, sgn * 0.012)), Vector3(0.025, 1.65, 0.012), wc)
		var wheel := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x0, 0.06, 0))
		g.box(wheel, Vector3(0.1, 0.03, 0.1), wc)
	g.box(Transform3D(Basis.IDENTITY, Vector3(gate_len * 0.5, 1.62, 0)), Vector3(gate_len, 0.04, 0.06), wc)
	mi(n, g.to_mesh(m.alu, true))
	# the motor head at the free end with its little sign
	rbox(n, Vector3(0.5, 1.75, 0.35), Vector3(-0.3, 0.88, 0), m.lamp_head, 0.03)
	rbox(n, Vector3(0.62, 0.06, 0.46), Vector3(-0.3, 1.78, 0), m.dark_metal, 0.02)
	_col(cols, Vector3(gate_len + 0.6, 1.8, 0.3), Vector3(gate_len * 0.5 - 0.3, 0.9, 0))
	# hut
	var hut := node(n, Vector3(gate_len + 2.2, 0, -0.6))
	var walls := MBuf.new()
	var hw := 1.5
	var hd := 1.3
	var hh := 2.7
	var o := Vector3(-hw, 0, hd)
	wall_with_holes(walls, Vector3(-hw, 0, hd), Vector3.RIGHT, Vector3.BACK, hw * 2.0, 0.0, hh, [Rect2(0.5, 0.95, 1.5, 1.05)], 0.12)
	wall_with_holes(walls, Vector3(hw, 0, -hd), Vector3.LEFT, Vector3.FORWARD, hw * 2.0, 0.0, hh, [Rect2(0.4, 0.0, 0.9, 2.05)], 0.12)
	wall_with_holes(walls, Vector3(-hw, 0, -hd), Vector3.BACK, Vector3.LEFT, hd * 2.0, 0.0, hh, [Rect2(0.7, 0.95, 1.2, 1.0)], 0.12)
	wall_with_holes(walls, Vector3(hw, 0, hd), Vector3.FORWARD, Vector3.RIGHT, hd * 2.0, 0.0, hh, [], 0.12)
	var hmesh := walls.to_mesh(m.hut_wall, true)
	mi(hut, hmesh)
	rbox(hut, Vector3(hw * 2.0 + 0.5, 0.14, hd * 2.0 + 0.5), Vector3(0, hh + 0.07, 0), m.concrete, 0.02)
	var glass := MBuf.new()
	fquad(glass, o + Vector3(0.5, 0.95, -0.1), o + Vector3(2.0, 0.95, -0.1), o + Vector3(2.0, 2.0, -0.1), o + Vector3(0.5, 2.0, -0.1), Vector3.BACK,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.55, 0.15, 0.4, 0.0))
	fquad(glass, Vector3(-hw + 0.1, 0.95, -hd + 0.7), Vector3(-hw + 0.1, 0.95, -hd + 1.9), Vector3(-hw + 0.1, 1.95, -hd + 1.9), Vector3(-hw + 0.1, 1.95, -hd + 0.7), Vector3.LEFT,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.0, 0.2, 0.8, 0.0))
	mi(hut, glass.to_mesh(m.glass_hut), Vector3.ZERO, Vector3.ZERO, false)
	rbox(hut, Vector3(0.9, 2.02, 0.05), Vector3(hw - 0.4 - 0.45, 1.02, -hd + 0.06), m.door_blue, 0.01)
	sign_quad(hut, m, "notice", Transform3D(Basis.IDENTITY, Vector3(-hw + 0.3, 1.3, hd + 0.01)), 0.45)
	_col(cols, Vector3(hw * 2.0, hh, hd * 2.0), Vector3(0, hh * 0.5, 0) + hut.position)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0)
	light.light_color = Color(1.0, 0.7, 0.42)
	light.light_energy = 0.6
	light.omni_range = 4.5
	light.light_volumetric_fog_energy = 0.4
	hut.add_child(light)
	return {"node": n, "light": light}


## A T-post washing line with laundry between two posts (along +x).
static func clothes_line(parent: Node3D, m: Dictionary, xf: Transform3D, length: float, seed: int, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	var b := MBuf.new()
	for x: float in [0.0, length]:
		b.tube(PackedVector3Array([Vector3(x, -0.1, 0), Vector3(x, 2.0, 0)]), taper(2, 0.035, 0.03), 8)
		b.tube(PackedVector3Array([Vector3(x, 1.9, -0.55), Vector3(x, 1.9, 0.55)]), taper(2, 0.025, 0.025), 6)
		_col(cols, Vector3(0.12, 2.0, 0.12), Vector3(x, 1.0, 0))
	for z: float in [-0.45, 0.0, 0.45]:
		var pts := PackedVector3Array()
		for i in 9:
			var t := float(i) / 8.0
			pts.append(Vector3(t * length, 1.9 - sin(t * PI) * 0.12, z))
		b.tube(pts, taper(9, 0.004, 0.004), 3)
	mi(n, b.to_mesh(m.galv))
	mi(n, laundry(m, seed, length - 0.6), Vector3(length * 0.5, 1.84, 0.0), Vector3.ZERO, true)
	mi(n, laundry(m, seed + 7, length - 1.0), Vector3(length * 0.5, 1.84, 0.45), Vector3.ZERO, true)
	return n


## An arched climbing frame of painted steel pipe (along +x).
static func climbing_frame(parent: Node3D, m: Dictionary, xf: Transform3D, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	var b := MBuf.new()
	var r := 1.3
	for z: float in [-0.65, 0.65]:
		var pts := PackedVector3Array()
		for i in 17:
			var a := PI * float(i) / 16.0
			pts.append(Vector3(cos(a) * r, sin(a) * r * 1.3 - 0.05, z))
		b.tube(pts, taper(17, 0.03, 0.03), 8)
	for i in range(1, 12):
		var a := PI * float(i) / 12.0
		var p := Vector3(cos(a) * r, sin(a) * r * 1.3 - 0.05, 0)
		b.tube(PackedVector3Array([p + Vector3(0, 0, -0.65), p + Vector3(0, 0, 0.65)]), taper(2, 0.018, 0.018), 6)
	mi(n, b.to_mesh(m.play_paint, true))
	_col(cols, Vector3(2.8, 1.8, 1.5), Vector3(0, 0.9, 0))
	return n


## The estate notice board on two posts, glass over pinned papers.
static func notice_board(parent: Node3D, m: Dictionary, xf: Transform3D, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	for sx: float in [-0.95, 0.95]:
		rbox(n, Vector3(0.08, 2.2, 0.08), Vector3(sx, 1.1, 0), m.lamp_pole, 0.01)
	rbox(n, Vector3(2.0, 1.1, 0.08), Vector3(0, 1.5, 0), m.dark_metal, 0.01)
	rbox(n, Vector3(1.86, 0.98, 0.01), Vector3(0, 1.5, 0.042), m.cork, 0.003)
	sign_quad(n, m, "missing", Transform3D(Basis(Vector3.BACK, 0.03), Vector3(-0.5, 1.2, 0.05)), 0.9)
	sign_quad(n, m, "notice", Transform3D(Basis(Vector3.BACK, -0.04), Vector3(0.35, 1.18, 0.05)), 0.9)
	rbox(n, Vector3(1.9, 1.0, 0.01), Vector3(0, 1.5, 0.065), m.glass_door, 0.003)
	rbox(n, Vector3(2.3, 0.05, 0.4), Vector3(0, 2.2, 0.05), m.dark_metal, 0.01, Vector3(0.15, 0, 0))
	_col(cols, Vector3(2.1, 2.2, 0.3), Vector3(0, 1.1, 0))
	return n


# ---------------------------------------------------------------------------
# forest landmarks
# ---------------------------------------------------------------------------
## A plank footbridge on two log beams with log railings. Along +x, centred,
## deck top at y = 0. Colliders: the deck and both railings.
static func footbridge(parent: Node3D, m: Dictionary, xf: Transform3D, length: float, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "Footbridge"
	n.transform = xf
	parent.add_child(n)
	var logs := MBuf.new()
	var planks := MBuf.new()
	var hl := length * 0.5
	for z: float in [-0.62, 0.62]:
		var pts := PackedVector3Array()
		for i in 7:
			var t := float(i) / 6.0
			pts.append(Vector3(lerpf(-hl - 0.8, hl + 0.8, t), -0.22 + sin(t * PI) * 0.03, z + sin(t * 4.0) * 0.03))
		logs.tube(pts, taper(7, 0.17, 0.15), 9, 2.0, 0.07, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true, true)
	var x := -hl
	while x < hl:
		var w := rng.randf_range(0.17, 0.24)
		var basis := Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)) * Basis(Vector3.RIGHT, rng.randf_range(-0.02, 0.02))
		planks.box(Transform3D(basis, Vector3(x + w * 0.5, -0.03 + rng.randf_range(-0.008, 0.008), rng.randf_range(-0.04, 0.04))), Vector3(w - 0.025, 0.05, rng.randf_range(1.55, 1.75)))
		x += w
	for z2: float in [-0.82, 0.82]:
		var px := -hl
		while px <= hl + 0.01:
			logs.tube(PackedVector3Array([Vector3(px, -0.35, z2), Vector3(px + rng.randf_range(-0.03, 0.03), 1.0, z2)]), taper(2, 0.06, 0.055), 7, 1.0, 0.05, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true)
			px += length / ceilf(length / 1.7)
		logs.tube(PackedVector3Array([Vector3(-hl - 0.1, 0.98, z2), Vector3(0, 1.0, z2 + 0.01), Vector3(hl + 0.1, 0.97, z2)]), taper(3, 0.05, 0.045), 7, 1.0, 0.06, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true, true)
		logs.tube(PackedVector3Array([Vector3(-hl, 0.48, z2), Vector3(hl, 0.5, z2)]), taper(2, 0.035, 0.035), 6, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
		cols.append([Vector3(length + 0.3, 1.3, 0.14), Transform3D(Basis.IDENTITY, Vector3(0, 0.55, z2))])
	var mesh := planks.to_mesh(m.planks, true)
	logs.commit(mesh, m.bark_oak, true)
	mi(n, mesh)
	cols.append([Vector3(length + 1.6, 0.2, 1.62), Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0))])
	return n


## A hunter's high seat: four splayed log legs, a plank platform with a
## half-walled box and a tin roof, a ladder up the front (+z).
static func hunters_stand(parent: Node3D, m: Dictionary, xf: Transform3D, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "HuntersStand"
	n.transform = xf
	parent.add_child(n)
	var logs := MBuf.new()
	var planks := MBuf.new()
	var top := 3.4
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p0 := Vector3(sx * 1.05, -0.3, sz * 1.05)
			var p1 := Vector3(sx * 0.7, top + 1.6, sz * 0.7)
			logs.tube(PackedVector3Array([p0, p0.lerp(p1, 0.5) + Vector3(rng.randf_range(-0.03, 0.03), 0, 0), p1]), taper(3, 0.09, 0.07), 8, 1.0, 0.06, rng.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true)
			cols.append([Vector3(0.24, top, 0.24), Transform3D(Basis.IDENTITY, Vector3(sx * 0.95, top * 0.5, sz * 0.95))])
	for sx2: float in [-1.0, 1.0]:
		logs.tube(PackedVector3Array([Vector3(sx2 * 1.0, 0.4, -1.0), Vector3(sx2 * 0.78, top - 0.2, 1.0)]), taper(2, 0.045, 0.045), 6, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
		logs.tube(PackedVector3Array([Vector3(-1.0, 0.6, sx2 * 1.0), Vector3(1.0, top - 0.4, sx2 * 0.8)]), taper(2, 0.045, 0.045), 6, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
	planks.box(Transform3D(Basis.IDENTITY, Vector3(0, top, 0)), Vector3(1.75, 0.06, 1.75))
	for side: Array in [[Vector3(0, top + 0.5, -0.85), Vector3(1.7, 1.0, 0.04)], [Vector3(-0.85, top + 0.5, 0), Vector3(0.04, 1.0, 1.7)], [Vector3(0.85, top + 0.5, 0), Vector3(0.04, 1.0, 1.7)],
			[Vector3(0, top + 0.3, 0.85), Vector3(1.7, 0.6, 0.04)]]:
		planks.box(Transform3D(Basis.IDENTITY, side[0]), side[1])
	var roof := Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, top + 1.75, 0))
	var mesh := planks.to_mesh(m.planks, true)
	logs.commit(mesh, m.bark_pine, true)
	mi(n, mesh)
	rbox(n, Vector3(2.0, 0.03, 2.1), roof.origin, m.corrugated, 0.01, Vector3(-0.22, 0, 0))
	# the ladder
	var lad := MBuf.new()
	for sx3: float in [-0.25, 0.25]:
		lad.tube(PackedVector3Array([Vector3(sx3, -0.1, 2.2), Vector3(sx3, top + 0.1, 0.9)]), taper(2, 0.04, 0.035), 6, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true)
	for k in 11:
		var t := (float(k) + 0.6) / 11.5
		var p := Vector3(0, -0.1, 2.2).lerp(Vector3(0, top + 0.1, 0.9), t)
		lad.tube(PackedVector3Array([p + Vector3(-0.27, 0, 0), p + Vector3(0.27, 0, 0)]), taper(2, 0.025, 0.025), 5)
	mi(n, lad.to_mesh(m.bark_pine, true))
	cols.append([Vector3(0.7, 0.6, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 2.05))])
	return n


## A collapsed wooden shed: the back wall (-z) still stands, one side leans,
## the other lies flat, the tin roof slid down to the ground at the front.
static func collapsed_shed(parent: Node3D, m: Dictionary, xf: Transform3D, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "CollapsedShed"
	n.transform = xf
	parent.add_child(n)
	var pl := MBuf.new()
	var w := 3.2
	var d := 2.4
	var h := 2.2
	var wall := func(xfw: Transform3D, ww: float, hh: float, broken: float) -> void:
		var x := -ww * 0.5
		while x < ww * 0.5 - 0.05:
			var bw := rng.randf_range(0.14, 0.22)
			var bh := hh * (1.0 - broken * rng.randf())
			pl.box(xfw * Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.02, 0.02)), Vector3(x + bw * 0.5, bh * 0.5, 0)), Vector3(bw - 0.012, bh, 0.025))
			x += bw
		pl.box(xfw * Transform3D(Basis.IDENTITY, Vector3(0, hh * 0.25, -0.03)), Vector3(ww, 0.1, 0.05))
		pl.box(xfw * Transform3D(Basis.IDENTITY, Vector3(0, hh * 0.8, -0.03)), Vector3(ww, 0.1, 0.05))
	wall.call(Transform3D(Basis.IDENTITY, Vector3(0, 0, -d * 0.5)), w, h, 0.05)
	cols.append([Vector3(w, h, 0.2), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, -d * 0.5))])
	var lean := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, 0.0) * Basis(Vector3.RIGHT, -0.22), Vector3(-w * 0.5, 0, 0))
	wall.call(lean, d, h * 0.9, 0.2)
	cols.append([Vector3(0.3, h, d), Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 - 0.15, h * 0.5, 0))])
	var flat := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.06), Vector3(w * 0.5 + 0.1, 0.05, 0))
	wall.call(flat, d, h * 0.8, 0.4)
	# the roof: corrugated sheets slid down from the back wall to the ground
	var roof_basis := Basis(Vector3.RIGHT, atan2(h - 0.1, d + 0.4))
	for k in 3:
		var sx := -w * 0.35 + k * w * 0.35 + rng.randf_range(-0.1, 0.1)
		rbox(n, Vector3(1.05, 0.02, sqrt(pow(h, 2.0) + pow(d + 0.4, 2.0))), Vector3(sx, h * 0.5, 0.15), m.corrugated, 0.005, Vector3(atan2(h - 0.1, d + 0.4) + rng.randf_range(-0.05, 0.05), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05)))
	cols.append([Vector3(w, 0.3, sqrt(pow(h, 2.0) + pow(d + 0.4, 2.0))), Transform3D(roof_basis, Vector3(0, h * 0.5, 0.15))])
	# the door hanging off one hinge, loose planks, a barrel
	var door := Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.BACK, 0.25), Vector3(1.0, 0.0, d * 0.5 + 0.4))
	wall.call(door, 0.8, 1.8, 0.0)
	for k in 6:
		pl.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)), Vector3(rng.randf_range(-2.0, 2.0), 0.03, rng.randf_range(0.5, 2.5))), Vector3(rng.randf_range(0.8, 1.8), 0.025, 0.16))
	mi(n, pl.to_mesh(m.planks, true))
	barrel(n, m, Vector3(-w * 0.5 + 0.6, 0, -d * 0.5 + 0.5), seed, cols)
	return n


static func barrel(parent: Node3D, m: Dictionary, pos: Vector3, seed: int, cols: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := node(parent, pos, rng.randf() * TAU)
	var prof := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.03), Vector2(0.97, 0.05), Vector2(1.0, 0.3), Vector2(0.97, 0.32), Vector2(1.0, 0.58),
		Vector2(0.97, 0.6), Vector2(1.0, 0.86), Vector2(0.98, 0.88), Vector2(0.0, 0.88)]
	mi(b, MeshUtil.lathe(PackedVector2Array(prof), Vector2(0.29, 0.29), 2.0, 20), Vector3.ZERO, Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05)), true, m.rust)
	cols.append([Vector3(0.6, 0.9, 0.6), Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.45, 0))])


## An uprooted spruce: the trunk lying along +x and its root plate standing
## on edge (a wall of soil and roots taller than a man).
static func root_plate(parent: Node3D, m: Dictionary, xf: Transform3D, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "RootPlate"
	n.transform = xf
	parent.add_child(n)
	var soil := MBuf.new()
	var roots := MBuf.new()
	var segs := 28
	var rad := PackedFloat32Array()
	for i in segs:
		rad.append(rng.randf_range(1.25, 1.65))
	var ctr := Vector3(0, 1.0, 0)
	for face in 2:
		var x := 0.28 if face == 0 else -0.25
		var nn := Vector3.RIGHT if face == 0 else Vector3.LEFT
		var ci := soil.add(ctr + Vector3(x, 0, 0), nn, Vector2(0.5, 0.5), Color(1, 1, 1, 1))
		var first := soil.v.size()
		for i in segs + 1:
			var a := TAU * float(i % segs) / float(segs)
			var r := rad[i % segs]
			var p := ctr + Vector3(x + rng.randf_range(-0.08, 0.08), sin(a) * r, cos(a) * r)
			soil.add(p, (nn + Vector3(0, sin(a), cos(a)) * 0.3).normalized(), Vector2(0.5 + cos(a) * r * 0.5, 0.5 + sin(a) * r * 0.5), Color(1, 1, 1, 1))
		for i in segs:
			var a0 := first + i
			var p0 := soil.v[ci]
			var p1 := soil.v[a0]
			var p2 := soil.v[a0 + 1]
			if (p1 - p0).cross(p2 - p0).dot(nn) > 0.0:
				soil.tri_idx(ci, a0 + 1, a0)
			else:
				soil.tri_idx(ci, a0, a0 + 1)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var pa := ctr + Vector3(0.28, sin(a0) * rad[i], cos(a0) * rad[i])
		var pb := ctr + Vector3(0.28, sin(a1) * rad[(i + 1) % segs], cos(a1) * rad[(i + 1) % segs])
		var pc := pb + Vector3(-0.53, 0, 0)
		var pd := pa + Vector3(-0.53, 0, 0)
		var nn2 := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		fquad(soil, pa, pb, pc, pd, nn2, Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 0.5), Vector2(0, 0.5))
	for k in 22:
		var a := rng.randf() * TAU
		var r0 := rng.randf_range(0.1, 0.8)
		var r1 := rng.randf_range(1.3, 2.3)
		var pts := PackedVector3Array()
		for i in 5:
			var t := float(i) / 4.0
			var rr := lerpf(r0, r1, t)
			pts.append(ctr + Vector3(0.3 + sin(t * 3.0 + a) * 0.1 + t * 0.15, sin(a) * rr, cos(a) * rr))
		roots.tube(pts, taper(5, rng.randf_range(0.04, 0.12), 0.012), 5, 1.0, 0.1, a, 0.0, 0.0, 0.0, 0.0, true)
	var mesh := soil.to_mesh(m.soil, true)
	roots.commit(mesh, m.bark_spruce, true)
	mi(n, mesh)
	mi(n, log_mesh(seed + 1, m, 9.0, 0.36, "bark_spruce"), Vector3(-4.6, -0.12, 0.1), Vector3(0, 0.05, 0))
	cols.append([Vector3(0.7, 2.6, 3.0), Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0))])
	cols.append([Vector3(9.0, 0.7, 0.8), Transform3D(Basis(Vector3.UP, 0.05), Vector3(-4.6, 0.3, 0.1))])
	return n


## A great fallen trunk gone hollow, open at both ends (along +x, centred,
## resting on the ground). Big enough to crawl into.
static func hollow_log(parent: Node3D, m: Dictionary, xf: Transform3D, seed: int, cols: Array) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := Node3D.new()
	n.name = "HollowLog"
	n.transform = xf
	parent.add_child(n)
	var b := MBuf.new()
	var inner := MBuf.new()
	var length := 5.4
	var ro := 0.98
	var ri := 0.8
	var pts := PackedVector3Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector3((t - 0.5) * length, ro - 0.12 + sin(t * PI) * 0.04, 0))
	b.tube(pts, taper(9, ro, ro * 0.92), 16, 6.0, 0.07, rng.randf() * TAU)
	inner.tube(pts, taper(9, ri, ri * 0.9), 14, 4.0, 0.05, rng.randf() * TAU)
	# turn the inner tube inside out
	var nidx := PackedInt32Array()
	for i in range(0, inner.idx.size(), 3):
		nidx.append(inner.idx[i])
		nidx.append(inner.idx[i + 2])
		nidx.append(inner.idx[i + 1])
	inner.idx = nidx
	for i in inner.n.size():
		inner.n[i] = -inner.n[i]
	# end rings (end grain)
	for e in 2:
		var x := pts[0].x if e == 0 else pts[8].x
		var cy := pts[0].y if e == 0 else pts[8].y
		var ro2 := ro if e == 0 else ro * 0.92
		var ri2 := ri if e == 0 else ri * 0.9
		var nn := Vector3.LEFT if e == 0 else Vector3.RIGHT
		for s in 16:
			var a0 := TAU * s / 16.0
			var a1 := TAU * (s + 1) / 16.0
			var p0 := Vector3(x, cy + sin(a0) * ri2, cos(a0) * ri2)
			var p1 := Vector3(x, cy + sin(a1) * ri2, cos(a1) * ri2)
			var p2 := Vector3(x, cy + sin(a1) * ro2, cos(a1) * ro2)
			var p3 := Vector3(x, cy + sin(a0) * ro2, cos(a0) * ro2)
			var u := func(p: Vector3) -> Vector2: return Vector2(0.5 + (p.z) / ro2 * 0.5, 0.5 + (p.y - cy) / ro2 * 0.5)
			fquad(b, p0, p1, p2, p3, nn, u.call(p0), u.call(p1), u.call(p2), u.call(p3), Color(1, 0, 0, 1))
	var mesh := b.to_mesh(m.bark_oak, true)
	inner.commit(mesh, m.rotten_wood, true)
	mi(n, mesh)
	cols.append([Vector3(length, 0.3, 2.0), Transform3D(Basis.IDENTITY, Vector3(0, ro * 2.0 - 0.25, 0))])
	for sz: float in [-1.0, 1.0]:
		cols.append([Vector3(length, 1.9, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 0.85, sz * 0.86))])
	return n


## A forest-fire warning board on a post (facing +z).
static func fire_sign(parent: Node3D, m: Dictionary, xf: Transform3D, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	rbox(n, Vector3(0.1, 2.0, 0.1), Vector3(0, 1.0, -0.05), m.lamp_pole, 0.01)
	rbox(n, Vector3(1.0, 0.52, 0.03), Vector3(0, 1.75, 0.0), m.dark_metal, 0.01)
	sign_quad(n, m, "fire", Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0.017)), 1.0)
	_col(cols, Vector3(0.14, 2.0, 0.14), Vector3(0, 1.0, -0.05))
	return n


## A steel W-beam crash barrier on posts, along +x from 0 to length.
static func crash_barrier(parent: Node3D, m: Dictionary, xf: Transform3D, length: float, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.05), Vector2(0.02, 0.1), Vector2(0.02, 0.16), Vector2(0.06, 0.21), Vector2(0.0, 0.26)])
	var beam := MeshUtil.extrude(prof, length)
	mi(n, beam, Vector3(length * 0.5, 0.48, 0.05), Vector3.ZERO, true, m.galv)
	var x := 0.0
	var posts := MBuf.new()
	while x <= length + 0.01:
		posts.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.38, 0.0)), Vector3(0.06, 0.9, 0.1))
		x += 2.0
	mi(n, posts.to_mesh(m.galv))
	_col(cols, Vector3(length, 0.8, 0.2), Vector3(length * 0.5, 0.4, 0.03))
	return n


## A bus stop pole with its round sign and timetable board.
static func bus_stop(parent: Node3D, m: Dictionary, xf: Transform3D, cols: Array) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	cyl(n, 0.04, 0.04, 2.8, Vector3(0, 1.4, 0), m.galv, 10)
	var disc := cyl(n, 0.28, 0.28, 0.03, Vector3(0, 2.6, 0.05), m.bus_sign, 24, Vector3(PI * 0.5, 0, 0))
	disc.name = "Disc"
	rbox(n, Vector3(0.5, 0.7, 0.03), Vector3(0, 1.7, 0.06), m.bus_sign, 0.01)
	_col(cols, Vector3(0.12, 2.8, 0.12), Vector3(0, 1.4, 0))
	return n
