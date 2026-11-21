extends Node3D
## PLANNING ONLY (temporary, git-ignored): shared helpers for the collision lab.
## Builds the same world game.gd builds (flat + his room + stairwell with its
## colliders), a capsule the size of the player, and capsule proxies for the
## two people (r 0.22, h 1.6, layer 4, exactly as CharacterRig.setup makes).

const PR := 0.26
const PH := 1.7
const DT := 1.0 / 60.0

var flat: FlatBuilder
var stairs: StairBuilder
var man: Node3D
var woman: Node3D
var walker: CharacterBody3D
var space: PhysicsDirectSpaceState3D
var _q := PhysicsShapeQueryParameters3D.new()
var _caps := {}
var _t0 := 0


func person(nm: String) -> Node3D:
	var rig := Node3D.new()
	rig.name = nm
	add_child(rig)
	var sb := StaticBody3D.new()
	sb.name = nm + "Body"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.85
	sb.add_child(cs)
	sb.collision_layer = 4
	rig.add_child(sb)
	return rig


func build_world(with_stairs := true) -> void:
	_t0 = Time.get_ticks_msec()
	flat = FlatBuilder.new()
	flat.name = "Flat"
	add_child(flat)
	flat.build_home()
	await flat.build_rest()
	if with_stairs:
		stairs = StairBuilder.new()
		stairs.name = "Stairs"
		stairs.position = Vector3(0.0, 0.0, -40.0)
		add_child(stairs)
		stairs.build()
		await get_tree().process_frame
		stairs.add_colliders()
		stairs.her_floor = 2
	woman = person("Woman")
	woman.global_position = flat.spots.tub + Vector3(0.45, 0.0, 0.0)
	woman.rotation = Vector3(-deg_to_rad(70.0), deg_to_rad(90.0), 0.0)
	man = person("Man")
	man.global_position = Vector3(0.0, -100.0, 0.0)
	walker = CharacterBody3D.new()
	walker.name = "Walker"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = PR
	cap.height = PH
	cs.shape = cap
	cs.position.y = PH * 0.5
	walker.add_child(cs)
	walker.collision_layer = 1
	walker.collision_mask = 1 | 4
	add_child(walker)
	walker.global_position = Vector3(0.0, -60.0, 0.0)
	for i in 4:
		await get_tree().physics_frame
	space = get_world_3d().direct_space_state
	_q.exclude = [walker.get_rid()]
	_q.margin = 0.0
	print("WORLD built in %d ms; physics setting=%s" % [Time.get_ticks_msec() - _t0, str(ProjectSettings.get_setting("physics/3d/physics_engine"))])


func lap(label: String) -> void:
	print("  [%s: %d ms]" % [label, Time.get_ticks_msec() - _t0])
	_t0 = Time.get_ticks_msec()


func v3(p: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [p.x, p.y, p.z]


func v2(p: Vector3) -> String:
	return "(%.2f,%.2f)" % [p.x, p.z]


func cap_shape(r: float) -> CapsuleShape3D:
	var k := int(round(r * 1000.0))
	if not _caps.has(k):
		var c := CapsuleShape3D.new()
		c.radius = r
		c.height = maxf(PH, 2.0 * r + 0.02)
		_caps[k] = c
	return _caps[k]


## Does a capsule of radius r stand at p (feet at p.y, lifted off the floor)?
func fits(p: Vector3, r := PR, mask := 5, lift := 0.03) -> bool:
	var sh := cap_shape(r)
	_q.shape = sh
	_q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, sh.height * 0.5 + lift, 0.0))
	_q.collision_mask = mask
	return space.intersect_shape(_q, 1).is_empty()


func hits(p: Vector3, r := PR, mask := 5, lift := 0.03, n := 8) -> Array:
	var sh := cap_shape(r)
	_q.shape = sh
	_q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, sh.height * 0.5 + lift, 0.0))
	_q.collision_mask = mask
	var out := []
	for h: Dictionary in space.intersect_shape(_q, n):
		var d := cdesc(h.collider)
		if not out.has(d):
			out.append(d)
	return out


## Height of the floor under p (ray from p.y + up to p.y - down), or -INF.
func floor_y(p: Vector3, up := 0.5, down := 0.6) -> float:
	var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p - Vector3(0, down, 0))
	rq.collision_mask = 1
	rq.exclude = [walker.get_rid()]
	var hit := space.intersect_ray(rq)
	if hit.is_empty():
		return -INF
	return float(hit.position.y)


func ray_blocked(a: Vector3, b: Vector3, mask := 1) -> bool:
	var rq := PhysicsRayQueryParameters3D.create(a, b)
	rq.collision_mask = mask
	rq.exclude = [walker.get_rid()]
	return not space.intersect_ray(rq).is_empty()


const AUTO := ["StaticBody3D", "MeshInstance3D", "Node3D", "CollisionShape3D"]


## A readable name for a collider: named ancestors + its shape and where it is.
func cdesc(o: Object) -> String:
	var n := o as Node
	if n == null:
		return "?"
	var names: Array[String] = []
	var cur: Node = n
	while cur and cur != self:
		var s := String(cur.name)
		if not s.begins_with("@") and not AUTO.has(s) and not s.begins_with("_"):
			names.push_front(s)
		cur = cur.get_parent()
	var tag := "/".join(names)
	for c in n.get_children():
		if c is CollisionShape3D:
			var sh := (c as CollisionShape3D).shape
			var gp := (c as CollisionShape3D).global_position
			if sh is BoxShape3D:
				var sz := (sh as BoxShape3D).size
				tag += " box %.2fx%.2fx%.2f@%s" % [sz.x, sz.y, sz.z, v3(gp)]
			elif sh is ConcavePolygonShape3D:
				tag += " TRIMESH %dtri@%s" % [(sh as ConcavePolygonShape3D).get_faces().size() / 3, v3(gp)]
			elif sh is CapsuleShape3D:
				tag += " capsule r%.2f@%s" % [(sh as CapsuleShape3D).radius, v3(gp)]
			else:
				tag += " %s@%s" % [sh.get_class(), v3(gp)]
			break
	return tag


## World AABB of a collision shape.
func shape_aabb(cs: CollisionShape3D) -> AABB:
	var sh := cs.shape
	var xf := cs.global_transform
	if sh is BoxShape3D:
		var sz := (sh as BoxShape3D).size
		return xf * AABB(-sz * 0.5, sz)
	if sh is CapsuleShape3D:
		var c := sh as CapsuleShape3D
		return xf * AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if sh is ConcavePolygonShape3D:
		var f := (sh as ConcavePolygonShape3D).get_faces()
		var bb := AABB(xf * f[0], Vector3.ZERO)
		for p: Vector3 in f:
			bb = bb.expand(xf * p)
		return bb
	return AABB(xf.origin, Vector3.ZERO)


## player.gd's unstick(), copied: where it would put the body (p if p is free).
func unstick_dest(p: Vector3) -> Vector3:
	var shape := cap_shape(0.27)
	var q := PhysicsShapeQueryParameters3D.new()
	var s2 := CapsuleShape3D.new()
	s2.radius = 0.27
	s2.height = 1.6
	q.shape = s2
	q.collision_mask = 1 | 4
	q.exclude = [walker.get_rid()]
	for r: float in [0.0, 0.3, 0.5, 0.75, 1.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var c := p + Vector3(cos(a) * r, 0.0, sin(a) * r)
			q.transform = Transform3D(Basis.IDENTITY, c + Vector3(0, 0.9, 0))
			if space.intersect_shape(q, 1).is_empty():
				return c
	return Vector3.INF


## Put the walker at p and refresh its floor state.
func place(p: Vector3) -> void:
	walker.global_position = p
	walker.velocity = Vector3(0.0, -0.1, 0.0)
	walker.move_and_slide()
	walker.velocity = Vector3.ZERO


## One physics step of player.gd's walking (dir: wanted horizontal velocity).
func step(want: Vector2) -> void:
	var cur := Vector2(walker.velocity.x, walker.velocity.z)
	cur = cur.move_toward(want, (7.0 if want.length() > cur.length() else 10.0) * DT)
	walker.velocity.x = cur.x
	walker.velocity.z = cur.y
	if not walker.is_on_floor():
		walker.velocity.y -= 9.8 * DT
	else:
		walker.velocity.y = -0.1
	walker.move_and_slide()


## Walk straight at `tgt` for up to `frames`; true if it gets within `tol`.
func walk_to(tgt: Vector3, speed := 1.05, frames := 240, tol := 0.08) -> bool:
	for f in frames:
		var p := walker.global_position
		var d := Vector2(tgt.x - p.x, tgt.z - p.z)
		if d.length() < tol:
			return true
		step(d.normalized() * speed)
	return false


func touching() -> Array:
	var out := []
	for c in walker.get_slide_collision_count():
		var col := walker.get_slide_collision(c)
		var d := cdesc(col.get_collider())
		if not out.has(d):
			out.append(d)
	return out


# ---------------------------------------------------------------------------
# clearance grid
# ---------------------------------------------------------------------------
const CELL := 0.05

var gx0 := 0.0
var gz0 := 0.0
var gnx := 0
var gnz := 0
var gy := 0.0
var clr := PackedFloat32Array()


func make_clearance(x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	gx0 = x0
	gz0 = z0
	gy = y
	gnx = int(round((x1 - x0) / CELL)) + 1
	gnz = int(round((z1 - z0) / CELL)) + 1
	clr = PackedFloat32Array()
	clr.resize(gnx * gnz)
	for j in gnz:
		for i in gnx:
			var p := Vector3(gx0 + i * CELL, y, gz0 + j * CELL)
			var c := -1.0
			var fy := floor_y(p)
			if fy > y - 0.3 and fy < y + 0.3:
				p.y = fy
				if not fits(p, 0.10):
					c = 0.0
				elif fits(p, 0.70):
					c = 0.70
				else:
					var lo := 0.10
					var hi := 0.70
					if fits(p, PR):
						lo = PR
					else:
						hi = PR
					for it in 6:
						var mid := (lo + hi) * 0.5
						if fits(p, mid):
							lo = mid
						else:
							hi = mid
					c = lo
			clr[j * gnx + i] = c


func cell_of(p: Vector3) -> int:
	var i := clampi(int(round((p.x - gx0) / CELL)), 0, gnx - 1)
	var j := clampi(int(round((p.z - gz0) / CELL)), 0, gnz - 1)
	return j * gnx + i


func cell_pos(c: int) -> Vector3:
	return Vector3(gx0 + (c % gnx) * CELL, gy, gz0 + (c / gnx) * CELL)


func lvl(c: float) -> int:
	return clampi(int(floor(c * 100.0 + 1e-4)), 0, 70)


## Widest route from `ref`: best[cell] = the bottleneck clearance (cm) of the
## best path; parent[] to walk it back.
func maximin(ref: Vector3, cmap: PackedFloat32Array) -> Array:
	var n := cmap.size()
	var best := PackedInt32Array()
	best.resize(n)
	best.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var qs: Array = []
	var ps: Array = []
	for l in 71:
		qs.append([])
		ps.append([])
	var r0 := cell_of(ref)
	var l0 := lvl(cmap[r0])
	if l0 < 1:
		return [best, parent]
	(qs[l0] as Array).append(r0)
	(ps[l0] as Array).append(-1)
	for l in range(70, 0, -1):
		var q: Array = qs[l]
		var pq: Array = ps[l]
		var idx := 0
		while idx < q.size():
			var c: int = q[idx]
			var par: int = pq[idx]
			idx += 1
			if best[c] >= 0:
				continue
			best[c] = l
			parent[c] = par
			var ci := c % gnx
			var cj := c / gnx
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni < 0 or nj < 0 or ni >= gnx or nj >= gnz:
					continue
				var nc := nj * gnx + ni
				if best[nc] >= 0:
					continue
				var nl := mini(l, lvl(cmap[nc]))
				if nl >= 1:
					(qs[nl] as Array).append(nc)
					(ps[nl] as Array).append(c)
	return [best, parent]



## A way over the grid from a to b through cells where a capsule of radius
## `thr` stands (8-neighbour BFS, no corner cutting). Empty if none.
func plan_path(a: Vector3, b: Vector3, cmap: PackedFloat32Array, thr: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var s := cell_of(a)
	var g := cell_of(b)
	var par := PackedInt32Array()
	par.resize(cmap.size())
	par.fill(-2)
	var q: Array[int] = [s]
	par[s] = -1
	var head := 0
	while head < q.size():
		var c: int = q[head]
		head += 1
		if c == g:
			break
		var ci := c % gnx
		var cj := c / gnx
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var ni := ci + d.x
			var nj := cj + d.y
			if ni < 0 or nj < 0 or ni >= gnx or nj >= gnz:
				continue
			var nc := nj * gnx + ni
			if par[nc] != -2 or cmap[nc] < thr:
				continue
			if d.x != 0 and d.y != 0 and (cmap[cj * gnx + ni] < thr or cmap[nj * gnx + ci] < thr):
				continue
			par[nc] = c
			q.append(nc)
	if par[g] == -2:
		return out
	var cur := g
	while cur >= 0:
		out.push_front(cell_pos(cur))
		cur = par[cur]
	return out


## The clearance map with the husband's capsule standing at mp.
func with_man(cmap: PackedFloat32Array, mp: Vector3) -> PackedFloat32Array:
	var cm := PackedFloat32Array(cmap)
	for c in cm.size():
		if cm[c] > 0.0:
			var p := cell_pos(c)
			var d := Vector2(p.x - mp.x, p.z - mp.z).length() - 0.22
			if d < cm[c]:
				cm[c] = maxf(d, 0.0)
	return cm


## player.gd's stuck timer + unstick around one walking step. Returns true
## when unstick() fired on this step.
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var unstick_log: Array = []


func game_step(dir: Vector2, speed: float) -> bool:
	step(dir * speed)
	var fired := false
	if dir.length() > 0.1:
		if walker.global_position.distance_to(last_pos) < 0.004:
			stuck_t += DT
			if stuck_t > 1.2:
				stuck_t = 0.0
				var from := walker.global_position
				var d := unstick_dest(from)
				if d != Vector3.INF:
					walker.global_position = d
				unstick_log.append([from, d])
				fired = true
		else:
			stuck_t = 0.0
	else:
		stuck_t = 0.0
	last_pos = walker.global_position
	return fired
