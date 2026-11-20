class_name Props
extends RefCounted
## Furniture and fittings for the flat and his room, built from MeshUtil's
## rounded boxes, lathes, mouldings and draped cloth. Builders take a parent
## node and FlatBuilder's materials dictionary `m`, and return what they made.


static func add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func rb(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, r := 0.008, rot := Vector3.ZERO) -> MeshInstance3D:
	return add(parent, MeshUtil.rounded_box(size, r), mat, pos, rot)


static func collider(parent: Node3D, size: Vector3, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func node(parent: Node3D, pos: Vector3, rot_y := 0.0, nm := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	if nm != "":
		n.name = nm
	parent.add_child(n)
	return n


static func lathe(parent: Node3D, profile: Array, half: Vector2, pos: Vector3, mat: Material, e := 2.0, seg := 20) -> MeshInstance3D:
	return add(parent, MeshUtil.lathe(PackedVector2Array(profile), half, e, seg), mat, pos)


## A turned leg standing at `base`, `height` tall, widest radius `r`.
static func turned_leg(parent: Node3D, base: Vector3, height: float, r: float, mat: Material) -> MeshInstance3D:
	var prof := []
	for p: Vector2 in [Vector2(0.0, 0.0), Vector2(0.62, 0.0), Vector2(0.66, 0.02), Vector2(0.55, 0.05), Vector2(0.5, 0.2),
			Vector2(0.62, 0.38), Vector2(0.95, 0.55), Vector2(0.75, 0.7), Vector2(0.6, 0.76), Vector2(0.85, 0.82),
			Vector2(1.0, 0.88), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]:
		prof.append(Vector2(p.x, p.y * height))
	return lathe(parent, prof, Vector2(r, r), base, mat, 2.0, 14)


## A tube along points (MeshUtil.tube), for rails, handsets, cords.
static func tube(parent: Node3D, pts: Array, radii: Array, mat: Material, sides := 10) -> MeshInstance3D:
	return add(parent, MeshUtil.tube(PackedVector3Array(pts), PackedFloat32Array(radii), sides), mat)


# ---------------------------------------------------------------------------
# seating
# ---------------------------------------------------------------------------
## A wingback armchair in worn velvet: skirted seat, loose cushions, rolled
## arms, wings, turned front legs. Faces +z.
static func armchair(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var a := node(parent, pos, rot_y, "Armchair")
	var fab: Material = m.velvet
	var wd: Material = m.wood
	for sx: float in [-0.33, 0.33]:
		turned_leg(a, Vector3(sx, 0.0, 0.3), 0.15, 0.028, wd)
		rb(a, Vector3(0.045, 0.15, 0.045), Vector3(sx, 0.075, -0.3), wd, 0.01, Vector3(0.12, 0, 0))
	rb(a, Vector3(0.8, 0.26, 0.76), Vector3(0, 0.28, 0.0), fab, 0.04)
	rb(a, Vector3(0.58, 0.13, 0.6), Vector3(0, 0.46, 0.06), fab, 0.055)
	rb(a, Vector3(0.7, 0.82, 0.15), Vector3(0, 0.83, -0.3), fab, 0.06, Vector3(-0.14, 0, 0))
	rb(a, Vector3(0.54, 0.5, 0.08), Vector3(0, 0.76, -0.2), fab, 0.04, Vector3(-0.14, 0, 0))
	for sx: float in [-1.0, 1.0]:
		rb(a, Vector3(0.12, 0.22, 0.68), Vector3(sx * 0.35, 0.52, 0.02), fab, 0.055)
		rb(a, Vector3(0.15, 0.14, 0.08), Vector3(sx * 0.35, 0.6, 0.35), fab, 0.065)
		rb(a, Vector3(0.1, 0.54, 0.34), Vector3(sx * 0.36, 0.96, -0.17), fab, 0.045, Vector3(0, sx * 0.25, 0))
	collider(a, Vector3(0.8, 0.9, 0.78), Vector3(0, 0.45, 0))
	return a


## A sofa nobody uses any more, under a dust sheet. Faces +z.
static func sheeted_sofa(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float, seed := 7) -> Node3D:
	var s := node(parent, pos, rot_y, "Sofa")
	var top := func(x: float, z: float) -> float:
		var h := lerpf(0.46, 0.86, smoothstep(-0.16, -0.32, z))
		var arm := smoothstep(0.78, 0.92, absf(x))
		return maxf(h, 0.64 * arm)
	add(s, MeshUtil.drape(top, Vector2(1.05, 0.45), 0.95, Vector2i(72, 48), seed), m.linen)
	collider(s, Vector3(2.1, 0.85, 0.9), Vector3(0, 0.42, 0))
	return s


## A chair under a dust sheet, a shape you keep mistaking for someone sitting.
static func sheeted_chair(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float, seed := 3) -> Node3D:
	var s := node(parent, pos, rot_y, "SheetedChair")
	var top := func(x: float, z: float) -> float:
		var h := lerpf(0.48, 1.05, smoothstep(-0.12, -0.2, z))
		return h + 0.03 * smoothstep(0.2, 0.0, absf(x)) * smoothstep(-0.1, -0.2, z)
	add(s, MeshUtil.drape(top, Vector2(0.24, 0.24), 0.75, Vector2i(40, 40), seed), m.linen)
	collider(s, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.5, 0))
	return s


## A piano bench with a buttoned seat. Faces +z.
static func bench(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var b := node(parent, pos, rot_y, "Bench")
	rb(b, Vector3(0.85, 0.05, 0.38), Vector3(0, 0.47, 0), m.lacquer, 0.012)
	rb(b, Vector3(0.8, 0.05, 0.34), Vector3(0, 0.515, 0), m.velvet, 0.02)
	rb(b, Vector3(0.78, 0.07, 0.32), Vector3(0, 0.41, 0), m.lacquer, 0.006)
	for bx: float in [-0.37, 0.37]:
		for bz: float in [-0.15, 0.15]:
			turned_leg(b, Vector3(bx, 0.0, bz), 0.4, 0.024, m.lacquer)
	collider(b, Vector3(0.85, 0.52, 0.38), Vector3(0, 0.26, 0))
	return b


# ---------------------------------------------------------------------------
# tables and what is left on them
# ---------------------------------------------------------------------------
static func coffee_table(parent: Node3D, m: Dictionary, pos: Vector3) -> Node3D:
	var t := node(parent, pos, 0.0, "CoffeeTable")
	rb(t, Vector3(1.0, 0.035, 0.56), Vector3(0, 0.435, 0), m.wood, 0.012)
	rb(t, Vector3(0.92, 0.07, 0.48), Vector3(0, 0.385, 0), m.wood, 0.006)
	for tx: float in [-0.43, 0.43]:
		for tz: float in [-0.21, 0.21]:
			turned_leg(t, Vector3(tx, 0.0, tz), 0.35, 0.026, m.wood)
	rb(t, Vector3(0.86, 0.02, 0.42), Vector3(0, 0.1, 0), m.wood, 0.005)
	collider(t, Vector3(1.0, 0.45, 0.56), Vector3(0, 0.225, 0))
	bottle(t, m, Vector3(-0.28, 0.453, 0.06))
	wine_glass(t, m, Vector3(-0.1, 0.453, 0.13), false)
	wine_glass(t, m, Vector3(0.1, 0.453, -0.1), true)
	var spill := lathe(t, [Vector2(1.0, 0.0), Vector2(0.0, 0.0)], Vector2(0.09, 0.06), Vector3(0.2, 0.4535, -0.13), m.wine, 2.6, 18)
	spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ashtray(t, m, Vector3(0.32, 0.453, 0.12))
	for i in 3:
		rb(t, Vector3(0.3, 0.004, 0.22), Vector3(-0.05 + i * 0.012, 0.115 + i * 0.005, 0.04 - i * 0.01), m.paper, 0.001, Vector3(0, 0.1 * i, 0))
	return t


static func bottle(parent: Node3D, m: Dictionary, pos: Vector3) -> MeshInstance3D:
	return lathe(parent, [Vector2(0.0, 0.0), Vector2(0.95, 0.0), Vector2(1.0, 0.012), Vector2(1.0, 0.2), Vector2(0.92, 0.232),
			Vector2(0.5, 0.268), Vector2(0.34, 0.29), Vector2(0.33, 0.33), Vector2(0.39, 0.336), Vector2(0.38, 0.348),
			Vector2(0.0, 0.348)], Vector2(0.036, 0.036), pos, m.bottle, 2.0, 24)


static func wine_glass(parent: Node3D, m: Dictionary, pos: Vector3, fallen: bool) -> Node3D:
	var g := node(parent, pos)
	lathe(g, [Vector2(0.0, 0.0), Vector2(0.75, 0.0), Vector2(0.75, 0.004), Vector2(0.12, 0.012), Vector2(0.1, 0.09),
			Vector2(0.3, 0.1), Vector2(0.75, 0.12), Vector2(1.0, 0.16), Vector2(0.92, 0.205), Vector2(0.88, 0.2),
			Vector2(0.93, 0.16), Vector2(0.7, 0.125), Vector2(0.25, 0.108), Vector2(0.0, 0.106)], Vector2(0.038, 0.038), Vector3.ZERO, m.glass, 2.0, 20)
	if fallen:
		g.rotation = Vector3(0.0, 0.7, PI * 0.5)
		g.position += Vector3(0.0, 0.034, 0.0)
	else:
		# a dark crust of wine in the bottom
		lathe(g, [Vector2(0.7, 0.112), Vector2(0.0, 0.112)], Vector2(0.03, 0.03), Vector3.ZERO, m.wine, 2.0, 16)
	return g


static func ashtray(parent: Node3D, m: Dictionary, pos: Vector3) -> Node3D:
	var a := node(parent, pos)
	lathe(a, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.022), Vector2(0.86, 0.026), Vector2(0.8, 0.012),
			Vector2(0.0, 0.012)], Vector2(0.07, 0.07), Vector3.ZERO, m.glass, 2.0, 24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 4:
		var ang := rng.randf() * TAU
		var butt := rb(a, Vector3(0.032, 0.008, 0.008), Vector3(cos(ang) * 0.03, 0.017, sin(ang) * 0.03), m.paper, 0.003, Vector3(0, ang, 0.2))
		butt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return a


## A round pedestal side table.
static func pedestal_table(parent: Node3D, m: Dictionary, pos: Vector3) -> Node3D:
	var t := node(parent, pos, 0.0, "SideTable")
	lathe(t, [Vector2(0.0, 0.715), Vector2(0.96, 0.715), Vector2(1.0, 0.725), Vector2(1.0, 0.742), Vector2(0.97, 0.75),
			Vector2(0.0, 0.75)], Vector2(0.24, 0.24), Vector3.ZERO, m.wood, 2.0, 32)
	lathe(t, [Vector2(0.0, 0.08), Vector2(1.0, 0.08), Vector2(0.7, 0.16), Vector2(0.55, 0.3), Vector2(0.8, 0.42),
			Vector2(0.5, 0.55), Vector2(0.45, 0.66), Vector2(0.8, 0.7), Vector2(0.9, 0.715), Vector2(0.0, 0.715)],
			Vector2(0.05, 0.05), Vector3.ZERO, m.wood, 2.0, 16)
	for i in 3:
		var ang := TAU * float(i) / 3.0
		var foot := rb(t, Vector3(0.26, 0.05, 0.04), Vector3(cos(ang) * 0.12, 0.04, sin(ang) * 0.12), m.wood, 0.015)
		foot.rotation = Vector3(0, -ang, -0.15)
	collider(t, Vector3(0.45, 0.75, 0.45), Vector3(0, 0.375, 0))
	return t


## A black bakelite rotary telephone, the handset on its cradle, coiled cord.
static func rotary_phone(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var p := node(parent, pos, rot_y, "Phone")
	var bk: Material = m.bakelite
	rb(p, Vector3(0.2, 0.07, 0.21), Vector3(0, 0.035, 0), bk, 0.03)
	rb(p, Vector3(0.17, 0.06, 0.13), Vector3(0, 0.075, 0.02), bk, 0.028, Vector3(-0.32, 0, 0))
	var dial := node(p, Vector3(0, 0.1, 0.06))
	dial.rotation.x = -0.32
	lathe(dial, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.006), Vector2(0.92, 0.009), Vector2(0.0, 0.009)],
			Vector2(0.052, 0.052), Vector3.ZERO, m.nickel, 2.0, 28)
	for i in 10:
		var ang := deg_to_rad(60.0 + i * 25.0)
		var hole := lathe(dial, [Vector2(1.0, 0.0094), Vector2(0.0, 0.0094)], Vector2(0.0075, 0.0075),
				Vector3(cos(ang) * 0.036, 0.0, sin(ang) * 0.036), m.dark, 2.0, 10)
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lathe(dial, [Vector2(1.0, 0.0096), Vector2(0.0, 0.0096)], Vector2(0.018, 0.018), Vector3.ZERO, m.ivory, 2.0, 16)
	for sx: float in [-0.065, 0.065]:
		rb(p, Vector3(0.025, 0.04, 0.03), Vector3(sx, 0.11, -0.06), bk, 0.008)
	# the handset lying across the cradle: ear and mouth cups on a curved grip
	var hs := node(p, Vector3(0, 0.135, -0.06))
	tube(hs, [Vector3(-0.1, 0.0, 0.0), Vector3(-0.04, 0.012, 0.0), Vector3(0.04, 0.012, 0.0), Vector3(0.1, 0.0, 0.0)],
			[0.014, 0.012, 0.012, 0.014], bk, 12)
	for sx: float in [-1.0, 1.0]:
		var cup := lathe(hs, [Vector2(0.0, 0.0), Vector2(0.7, 0.0), Vector2(1.0, 0.012), Vector2(1.0, 0.03), Vector2(0.0, 0.03)],
				Vector2(0.026, 0.026), Vector3(sx * 0.11, -0.022, 0.0), bk, 2.0, 16)
		cup.rotation.z = -sx * 0.25
	# coiled cord from the body's side to the end of the handset
	var coil := []
	var radii := []
	for i in 140:
		var t := float(i) / 139.0
		var base := Vector3(0.1, 0.03, 0.02).lerp(Vector3(0.11, 0.115, -0.06), t)
		base += Vector3(0.05 * sin(t * PI), 0.0, 0.07 * sin(t * PI))
		var ang := t * TAU * 18.0
		coil.append(base + Vector3(0.0, cos(ang) * 0.006, sin(ang) * 0.006))
		radii.append(0.0022)
	tube(p, coil, radii, bk, 5)
	return p


# ---------------------------------------------------------------------------
# the long-case clock, stopped hands, a pendulum you can still hear
# ---------------------------------------------------------------------------
static func longcase_clock(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var c := node(parent, pos, rot_y, "Clock")
	var wd: Material = m.wood
	rb(c, Vector3(0.56, 0.04, 0.36), Vector3(0, 0.02, 0), wd, 0.008)
	rb(c, Vector3(0.52, 0.3, 0.32), Vector3(0, 0.19, 0), wd, 0.012)
	rb(c, Vector3(0.46, 0.05, 0.3), Vector3(0, 0.36, 0), wd, 0.01)
	rb(c, Vector3(0.4, 1.0, 0.24), Vector3(0, 0.86, 0), wd, 0.01)
	rb(c, Vector3(0.46, 0.05, 0.3), Vector3(0, 1.37, 0), wd, 0.01)
	rb(c, Vector3(0.3, 0.78, 0.02), Vector3(0, 0.86, 0.125), wd, 0.008)
	var glass := rb(c, Vector3(0.2, 0.5, 0.004), Vector3(0, 0.92, 0.137), m.glass_dark, 0.002)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb(c, Vector3(0.5, 0.5, 0.3), Vector3(0, 1.65, 0), wd, 0.012)
	rb(c, Vector3(0.54, 0.06, 0.34), Vector3(0, 1.93, 0), wd, 0.012)
	rb(c, Vector3(0.48, 0.12, 0.05), Vector3(0, 2.02, 0.13), wd, 0.012)
	for sx: float in [-0.22, 0.0, 0.22]:
		lathe(c, [Vector2(0.0, 0.0), Vector2(0.6, 0.0), Vector2(1.0, 0.03), Vector2(0.4, 0.06), Vector2(0.15, 0.09), Vector2(0.0, 0.1)],
				Vector2(0.03, 0.03), Vector3(sx, 1.96 + (0.08 if sx == 0.0 else 0.0), 0.0), m.nickel, 2.0, 12)
	# the dial: a face, a chapter ring, hands at five to midnight
	var d := node(c, Vector3(0, 1.66, 0.152))
	d.rotation.x = PI * 0.5
	lathe(d, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.004), Vector2(0.0, 0.004)], Vector2(0.17, 0.17), Vector3.ZERO, m.dial, 2.0, 36)
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var tick := rb(d, Vector3(0.006, 0.006, 0.03), Vector3(sin(ang) * 0.14, 0.005, -cos(ang) * 0.14), m.dark, 0.001, Vector3(0, -ang, 0))
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hand_h := rb(d, Vector3(0.008, 0.003, 0.085), Vector3(0, 0.008, -0.035), m.dark, 0.001)
	hand_h.position = Vector3(sin(deg_to_rad(-2.5)) * 0.04, 0.008, -cos(deg_to_rad(-2.5)) * 0.04)
	hand_h.rotation.y = deg_to_rad(2.5)
	var hand_m := rb(d, Vector3(0.005, 0.003, 0.125), Vector3(0, 0.01, 0), m.dark, 0.001)
	hand_m.position = Vector3(sin(deg_to_rad(-30.0)) * 0.06, 0.01, -cos(deg_to_rad(-30.0)) * 0.06)
	hand_m.rotation.y = deg_to_rad(30.0)
	# the pendulum, swinging behind the glass
	var pend := node(c, Vector3(0, 1.36, 0.06), 0.0, "Pendulum")
	rb(pend, Vector3(0.008, 0.62, 0.004), Vector3(0, -0.31, 0), m.nickel, 0.002)
	var bob := node(pend, Vector3(0, -0.64, 0))
	bob.rotation.x = PI * 0.5
	lathe(bob, [Vector2(0.0, -0.006), Vector2(1.0, -0.002), Vector2(1.0, 0.002), Vector2(0.0, 0.006)], Vector2(0.055, 0.055), Vector3.ZERO, m.nickel, 2.0, 24)
	c.set_meta("pendulum", pend)
	collider(c, Vector3(0.52, 2.1, 0.34), Vector3(0, 1.05, 0))
	return c


# ---------------------------------------------------------------------------
# bedroom
# ---------------------------------------------------------------------------
## A double bed (headboard at -z), its blanket thrown back, two pillows.
static func bed(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var b := node(parent, pos, rot_y, "Bed")
	var wd: Material = m.wood
	for sx: float in [-0.78, 0.78]:
		turned_leg(b, Vector3(sx, 0.0, -1.02), 1.15, 0.04, wd)
		turned_leg(b, Vector3(sx, 0.0, 1.02), 0.7, 0.035, wd)
		rb(b, Vector3(0.05, 0.18, 2.0), Vector3(sx, 0.32, 0.0), wd, 0.012)
	rb(b, Vector3(1.5, 0.62, 0.05), Vector3(0, 0.78, -1.02), wd, 0.015)
	for sx: float in [-0.48, 0.0, 0.48]:
		rb(b, Vector3(0.36, 0.42, 0.02), Vector3(sx, 0.8, -0.995), wd, 0.01)
	rb(b, Vector3(1.5, 0.32, 0.05), Vector3(0, 0.5, 1.02), wd, 0.015)
	rb(b, Vector3(1.5, 0.22, 1.96), Vector3(0, 0.52, 0.0), m.linen, 0.07)
	for sx: float in [-0.36, 0.36]:
		rb(b, Vector3(0.6, 0.13, 0.36), Vector3(sx, 0.7, -0.75), m.linen, 0.065, Vector3(0.15, sx * 0.1, 0))
	var top := func(_x: float, z: float) -> float:
		return 0.63 + 0.05 * smoothstep(-0.2, 0.1, z) * (0.5 + 0.5 * sin(z * 9.0))
	var blanket := add(b, MeshUtil.drape(top, Vector2(0.74, 0.62), 0.42, Vector2i(48, 40), 11), m.blanket, Vector3(0, 0, 0.36))
	blanket.name = "Blanket"
	collider(b, Vector3(1.6, 0.65, 2.1), Vector3(0, 0.33, 0))
	return b


## A bedside table with a drawer and a dead lamp.
static func nightstand(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var n := node(parent, pos, rot_y, "Nightstand")
	rb(n, Vector3(0.45, 0.04, 0.4), Vector3(0, 0.6, 0), m.wood, 0.01)
	rb(n, Vector3(0.42, 0.42, 0.37), Vector3(0, 0.37, 0), m.wood, 0.012)
	rb(n, Vector3(0.38, 0.13, 0.02), Vector3(0, 0.49, 0.19), m.wood, 0.006)
	lathe(n, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.012), Vector2(0.0, 0.016)], Vector2(0.012, 0.012), Vector3(0, 0.49, 0.2), m.nickel, 2.0, 10).rotation.x = PI * 0.5
	for sx: float in [-0.19, 0.19]:
		for sz: float in [-0.16, 0.16]:
			rb(n, Vector3(0.035, 0.16, 0.035), Vector3(sx, 0.08, sz), m.wood, 0.008)
	collider(n, Vector3(0.45, 0.62, 0.4), Vector3(0, 0.31, 0))
	return n


## A chest of drawers: three drawers with knobs, a plinth and a moulded top.
static func chest(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var c := node(parent, pos, rot_y, "Chest")
	var wd: Material = m.wood
	rb(c, Vector3(0.95, 0.035, 0.48), Vector3(0, 0.82, 0), wd, 0.012)
	rb(c, Vector3(0.9, 0.72, 0.44), Vector3(0, 0.44, 0), wd, 0.012)
	rb(c, Vector3(0.92, 0.07, 0.46), Vector3(0, 0.05, 0), wd, 0.01)
	for i in 3:
		var y := 0.2 + i * 0.22
		rb(c, Vector3(0.84, 0.19, 0.02), Vector3(0, y, 0.225), wd, 0.008)
		for sx: float in [-0.25, 0.25]:
			var k := lathe(c, [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.45, 0.012), Vector2(1.0, 0.02), Vector2(0.0, 0.026)],
					Vector2(0.016, 0.016), Vector3(sx, y, 0.236), m.nickel, 2.0, 10)
			k.rotation.x = PI * 0.5
	collider(c, Vector3(0.95, 0.85, 0.48), Vector3(0, 0.42, 0))
	return c


# ---------------------------------------------------------------------------
# fittings
# ---------------------------------------------------------------------------
## A cast-iron column radiator under a window, its paint flaking.
static func radiator(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float, sections := 12) -> Node3D:
	var r := node(parent, pos, rot_y, "Radiator")
	var w := sections * 0.062
	for i in sections:
		var x := -w * 0.5 + 0.031 + i * 0.062
		rb(r, Vector3(0.05, 0.56, 0.16), Vector3(x, 0.4, 0), m.iron, 0.022)
	rb(r, Vector3(w, 0.05, 0.06), Vector3(0, 0.66, 0), m.iron, 0.02)
	rb(r, Vector3(w, 0.05, 0.06), Vector3(0, 0.14, 0), m.iron, 0.02)
	for sx: float in [-w * 0.42, w * 0.42]:
		rb(r, Vector3(0.06, 0.12, 0.14), Vector3(sx, 0.06, 0), m.iron, 0.02)
	tube(r, [Vector3(w * 0.5 + 0.03, 0.0, 0.02), Vector3(w * 0.5 + 0.03, 0.14, 0.02), Vector3(w * 0.5 - 0.02, 0.14, 0.02)], [0.016, 0.016, 0.016], m.iron)
	collider(r, Vector3(w, 0.7, 0.16), Vector3(0, 0.35, 0))
	return r


## A framed picture behind glass (texture from assets/textures/decals).
static func picture(parent: Node3D, m: Dictionary, tex: String, size: Vector2, pos: Vector3, rot_y: float) -> Node3D:
	var f := node(parent, pos, rot_y, "Picture")
	var bw := 0.035
	rb(f, Vector3(size.x + 2 * bw, bw, 0.025), Vector3(0, size.y * 0.5 + bw * 0.5, 0.012), m.frame, 0.006)
	rb(f, Vector3(size.x + 2 * bw, bw, 0.025), Vector3(0, -size.y * 0.5 - bw * 0.5, 0.012), m.frame, 0.006)
	rb(f, Vector3(bw, size.y, 0.025), Vector3(size.x * 0.5 + bw * 0.5, 0, 0.012), m.frame, 0.006)
	rb(f, Vector3(bw, size.y, 0.025), Vector3(-size.x * 0.5 - bw * 0.5, 0, 0.012), m.frame, 0.006)
	var q := QuadMesh.new()
	q.size = size
	var pm := StandardMaterial3D.new()
	var p := "res://assets/textures/decals/%s.png" % tex
	if ResourceLoader.exists(p):
		pm.albedo_texture = load(p)
	pm.roughness = 0.6
	add(f, q, pm, Vector3(0, 0, 0.006))
	var g := QuadMesh.new()
	g.size = size
	add(f, g, m.glass, Vector3(0, 0, 0.012), Vector3.ZERO, false)
	return f


## A mirror on the wall, covered with black cloth (somebody died here).
static func covered_mirror(parent: Node3D, m: Dictionary, pos: Vector3, rot_y: float) -> Node3D:
	var c := node(parent, pos, rot_y, "CoveredMirror")
	rb(c, Vector3(0.6, 0.85, 0.035), Vector3(0, 0, 0.017), m.frame, 0.01)
	var cloth := add(c, MeshUtil.curtain(0.66, 0.95, 4, 0.025, 4), m.mourning, Vector3(0, 0.44, 0.05))
	cloth.name = "Cloth"
	return c


## A coat stand with two dark coats hanging on it.
static func coat_stand(parent: Node3D, m: Dictionary, pos: Vector3) -> Node3D:
	var s := node(parent, pos, 0.0, "CoatStand")
	lathe(s, [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.9, 0.04), Vector2(0.3, 0.07), Vector2(0.25, 1.7),
			Vector2(0.5, 1.74), Vector2(0.2, 1.8), Vector2(0.0, 1.82)], Vector2(0.11, 0.11), Vector3.ZERO, m.wood, 2.0, 16)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + 0.4
		tube(s, [Vector3(0, 1.62, 0), Vector3(cos(ang) * 0.09, 1.66, sin(ang) * 0.09), Vector3(cos(ang) * 0.12, 1.72, sin(ang) * 0.12)],
				[0.008, 0.007, 0.006], m.nickel, 6)
	for i in 2:
		var ang := 0.4 + PI * i
		var coat := node(s, Vector3(cos(ang) * 0.12, 1.66, sin(ang) * 0.12), ang)
		rb(coat, Vector3(0.12, 0.18, 0.4), Vector3(0.0, -0.1, 0.0), m.coat, 0.05)
		rb(coat, Vector3(0.14, 0.8, 0.46), Vector3(0.03, -0.55, 0.0), m.coat, 0.06, Vector3(0, 0, 0.05))
	collider(s, Vector3(0.3, 1.8, 0.3), Vector3(0, 0.9, 0))
	return s
