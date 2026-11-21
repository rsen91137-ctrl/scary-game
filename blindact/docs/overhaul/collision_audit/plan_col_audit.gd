extends "res://scratch_test/plan_col_base.gd"
## PLANNING ONLY. Static audit: collider inventory, clearance map (largest
## capsule that stands in each 5 cm cell), widest-route clearance from the
## hall to every key spot, passage widths, pockets, scripted targets, and the
## same routes with the husband parked where the director parks him.

func _ready() -> void:
	await build_world(true)
	print("SERVER class=", Engine.get_singleton("PhysicsServer3D").get_class())
	inventory()
	lap("inventory")
	print("\n===== FLAT =====")
	make_clearance(-5.3, -0.2, 3.1, 9.9, 0.0)
	lap("clearance flat")
	flat_report()
	lap("flat report")
	interact_reach(flat.spots.hall_mid)
	lap("interact reach flat")
	print("\n===== HOME =====")
	make_clearance(37.9, -0.1, 41.7, 4.1, 0.0)
	lap("clearance home")
	home_report()
	interact_reach(flat.spots.home_start)
	get_tree().quit()


# ---------------------------------------------------------------------------
func inventory() -> void:
	var stack: Array[Node] = [self]
	var n_box := 0
	var n_tri := 0
	var n_cap := 0
	var rows: Array[String] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is StaticBody3D):
			continue
		for c in n.get_children():
			if not (c is CollisionShape3D):
				continue
			var cs := c as CollisionShape3D
			var bb := shape_aabb(cs)
			var flags := ""
			if cs.shape is ConcavePolygonShape3D:
				n_tri += 1
				flags += " CONCAVE"
			elif cs.shape is BoxShape3D:
				n_box += 1
			else:
				n_cap += 1
			var top := bb.position.y + bb.size.y
			var bot := bb.position.y
			# only what a standing capsule can meet
			var rel_bot := bot - floorf((bot + 0.3) / 2.9) * 0.0
			if minf(bb.size.x, bb.size.z) < 0.1 and bb.size.y > 0.3:
				flags += " THIN(%.3f)" % minf(bb.size.x, bb.size.z)
			if top > 0.02 and top < 0.3 and bot < 0.05 and bot > -0.2:
				flags += " LOW_LIP(top %.2f)" % top
			if bot > 0.04 and bot < 1.7 and bb.size.y < 2.0:
				flags += " OVERHANG(bottom %.2f)" % bot
			if absf(cs.global_basis.get_euler().x) > 0.01 or absf(cs.global_basis.get_euler().z) > 0.01:
				flags += " TILTED"
			rows.append("%s | aabb x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] layer=%d%s" % [cdesc(n), bb.position.x, bb.position.x + bb.size.x,
					bot, top, bb.position.z, bb.position.z + bb.size.z, (n as StaticBody3D).collision_layer, flags])
	rows.sort()
	print("COLLIDERS: %d boxes, %d concave trimeshes, %d capsules" % [n_box, n_tri, n_cap])
	for r in rows:
		print("  C ", r)


# ---------------------------------------------------------------------------
func bottleneck(spot: Vector3, res: Array, cmap: PackedFloat32Array) -> String:
	var best: PackedInt32Array = res[0]
	var parent: PackedInt32Array = res[1]
	var c := cell_of(spot)
	if best[c] < 0:
		return "UNREACHABLE (cell clearance %.2f)" % cmap[c]
	var mn := 9.0
	var mc := c
	var cur := c
	var steps := 0
	while cur >= 0 and steps < 100000:
		if cmap[cur] < mn:
			mn = cmap[cur]
			mc = cur
		cur = parent[cur]
		steps += 1
	var bp := cell_pos(mc)
	return "width %.2f m (slack %+.2f) pinch at %s between %s" % [mn * 2.0, mn * 2.0 - 2.0 * PR, v2(bp), str(hits(bp, mn + 0.04, 5, 0.03, 6))]


func width_on(a: Vector3, b: Vector3) -> float:
	var n := int(a.distance_to(b) / 0.025) + 1
	var m := 0.0
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(n))
		m = maxf(m, clr[cell_of(p)])
	return m * 2.0


## Components of cells where the player's capsule stands; returns [labels, sizes].
func components(cmap: PackedFloat32Array, thr: float) -> Array:
	var n := cmap.size()
	var lab := PackedInt32Array()
	lab.resize(n)
	lab.fill(-1)
	var sizes: Array[int] = []
	for s in n:
		if lab[s] >= 0 or cmap[s] < thr:
			continue
		var id := sizes.size()
		var cnt := 0
		var q: Array[int] = [s]
		lab[s] = id
		while not q.is_empty():
			var c: int = q.pop_back()
			cnt += 1
			var ci := c % gnx
			var cj := c / gnx
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni < 0 or nj < 0 or ni >= gnx or nj >= gnz:
					continue
				var nc := nj * gnx + ni
				if lab[nc] < 0 and cmap[nc] >= thr:
					lab[nc] = id
					q.append(nc)
		sizes.append(cnt)
	return [lab, sizes]


func report_components(thr: float, ref: Vector3) -> void:
	var res := components(clr, thr)
	var lab: PackedInt32Array = res[0]
	var sizes: Array[int] = res[1]
	var main := lab[cell_of(ref)]
	print("COMPONENTS at r=%.2f: %d (main has %d cells = %.1f m2)" % [thr, sizes.size(), sizes[main] if main >= 0 else 0, (sizes[main] if main >= 0 else 0) * CELL * CELL])
	for id in sizes.size():
		if id == main:
			continue
		var mnx := INF
		var mxx := -INF
		var mnz := INF
		var mxz := -INF
		for c in lab.size():
			if lab[c] == id:
				var p := cell_pos(c)
				mnx = minf(mnx, p.x)
				mxx = maxf(mxx, p.x)
				mnz = minf(mnz, p.z)
				mxz = maxf(mxz, p.z)
		print("  POCKET #%d: %d cells (%.3f m2) centres x[%.2f,%.2f] z[%.2f,%.2f]" % [id, sizes[id], sizes[id] * CELL * CELL, mnx, mxx, mnz, mxz])


func ascii_map(cmap: PackedFloat32Array, step := 2) -> void:
	# one char per 10 cm: '#' no floor/solid, digits = slack class
	for j in range(gnz - 1, -1, -step):
		var line := ""
		for i in range(0, gnx, step):
			var c := cmap[j * gnx + i]
			if c < 0.0:
				line += " "
			elif c < 0.10:
				line += "#"
			elif c < PR:
				line += "x"
			elif c < 0.30:
				line += "!"
			elif c < 0.35:
				line += ":"
			elif c < 0.45:
				line += "."
			else:
				line += " " if false else "_"
		print("  |", line, "| z=%.1f" % (gz0 + j * CELL))


# ---------------------------------------------------------------------------
func flat_report() -> void:
	var seat: Vector3 = flat.spots.piano_seat
	var spots := {
		"front_inside (exit trigger)": flat.spots.front_inside,
		"living door, room side": Vector3(-1.0, 0, 1.8),
		"piano pocket (after standing up)": Vector3(-3.3, 0, 2.6),
		"behind the armchair": Vector3(-1.9, 0, 4.2),
		"sofa/table corridor": Vector3(-3.2, 0, 1.3),
		"left of coffee table": Vector3(-4.1, 0, 1.35),
		"bath, inside the door": Vector3(1.1, 0, 4.4),
		"sink_stand (wash spot)": flat.spots.sink_stand,
		"bath, by the tub": Vector3(2.3, 0, 4.7),
		"bedroom, inside the door": Vector3(0.1, 0, 7.0),
		"wardrobe_front": flat.spots.wardrobe_front,
		"wardrobe_in (hide teleport)": flat.spots.wardrobe_in,
		"escape (window)": flat.spots.escape,
		"chest/bed slot": Vector3(-1.8, 0, 7.3),
		"bed foot, left": Vector3(-1.0, 0, 7.25),
		"nightstand/window corner": Vector3(0.25, 0, 9.4),
	}
	var ref: Vector3 = flat.spots.hall_mid
	var res := maximin(ref, clr)
	print("WIDEST ROUTE from hall_mid %s (player needs 0.52):" % v2(ref))
	for k: String in spots:
		print("  R %-34s %s -> %s" % [k, v2(spots[k]), bottleneck(spots[k], res, clr)])
	report_components(PR, ref)
	print("PASSAGE WIDTHS (2 x largest capsule radius on the cross-line):")
	var lines := [
		["living doorway x=-0.65 z1.2..2.4", Vector3(-0.65, 0, 1.2), Vector3(-0.65, 0, 2.4)],
		["bath doorway x=0.65 z3.7..4.5", Vector3(0.65, 0, 3.7), Vector3(0.65, 0, 4.5)],
		["bath door, 25 cm inside (leaf)", Vector3(0.95, 0, 3.5), Vector3(0.95, 0, 4.9)],
		["bedroom doorway z=6.4", Vector3(-0.45, 0, 6.4), Vector3(0.45, 0, 6.4)],
		["bedroom door, 30 cm inside (leaf)", Vector3(-0.6, 0, 6.75), Vector3(0.8, 0, 6.75)],
		["hall z=3.0", Vector3(-0.65, 0, 3.0), Vector3(0.65, 0, 3.0)],
		["hall at coat stand z=0.8", Vector3(-0.65, 0, 0.8), Vector3(0.65, 0, 0.8)],
		["coffee table corner - armchair corner", Vector3(-2.7, 0, 2.18), Vector3(-2.34, 0, 2.76)],
		["sofa - coffee table", Vector3(-3.2, 0, 0.97), Vector3(-3.2, 0, 1.62)],
		["armchair - window wall", Vector3(-2.06, 0, 3.84), Vector3(-2.06, 0, 4.52)],
		["armchair - pedestal table", Vector3(-1.66, 0, 3.15), Vector3(-1.225, 0, 3.355)],
		["bench - coffee table", Vector3(-3.86, 0, 2.0), Vector3(-3.7, 0, 2.0)],
		["bench - piano keys", Vector3(-4.57, 0, 2.2), Vector3(-4.24, 0, 2.2)],
		["sofa - piano", Vector3(-4.7, 0, 0.97), Vector3(-4.7, 0, 1.5)],
		["toilet - sink pocket", Vector3(1.94, 0, 3.85), Vector3(2.55, 0, 3.85)],
		["toilet - tub", Vector3(1.75, 0, 4.07), Vector3(1.75, 0, 5.07)],
		["sink - tub", Vector3(2.7, 0, 4.28), Vector3(2.7, 0, 5.07)],
		["bed - wardrobe", Vector3(-0.6, 0, 8.0), Vector3(1.74, 0, 8.0)],
		["chest - bed slot", Vector3(-1.8, 0, 7.07), Vector3(-1.8, 0, 7.55)],
		["bed - nightstand/window wall", Vector3(-0.6, 0, 9.0), Vector3(2.32, 0, 9.0)],
	]
	for l: Array in lines:
		var w := width_on(l[1], l[2])
		print("  W %-40s %.2f m  slack %+.2f%s" % [l[0], w, w - 2.0 * PR, "  << BLOCKED" if w < 2.0 * PR else ("  << TIGHT" if w < 0.70 else "")])
	print("MAP (10 cm cells; x: -5.3 .. 3.1 left to right; '#' solid, 'x' capsule does not fit, '!' slack<8cm, ':' <18cm, '.' <38cm, '_' roomy):")
	ascii_map(clr)
	# scripted player targets
	print("SCRIPTED PLAYER TARGETS (capsule r 0.26 at the target):")
	var targets := {
		"_sit_at_piano (piano_seat)": seat,
		"_stand_up tween target (seat + 0.62 x)": seat + Vector3(0.62, 0.0, 0.0),
		"wash tween target (sink_stand)": flat.spots.sink_stand,
		"wardrobe_in (hide)": flat.spots.wardrobe_in,
		"wardrobe_front (leave hide)": flat.spots.wardrobe_front,
		"autoplay piano return (seat + 0.5 x)": seat + Vector3(0.5, 0, 0),
		"front_inside": flat.spots.front_inside,
		"escape": flat.spots.escape,
	}
	for k: String in targets:
		var p: Vector3 = targets[k]
		var free := fits(p, PR)
		var ud := unstick_dest(p)
		print("  T %-40s %s clearance %.2f %s%s%s" % [k, v2(p), clr[cell_of(p)], "FREE" if free else "INSIDE " + str(hits(p, PR)),
				"" if ud == p else ("  unstick-> " + (v2(ud) if ud != Vector3.INF else "NONE") + (" clearance %.2f" % clr[cell_of(ud)] if ud != Vector3.INF else "")),
				""])
	# the husband parked where the director parks him
	print("HUSBAND PARKED (capsule r 0.22): widest route for the player (needs 0.52)")
	var man_spots := {
		"armchair (sitting)": flat.spots.armchair,
		"just up from the chair": Vector3(-1.836, 0, 3.51),
		"MAN_WATCH (while you go to wash)": Vector3(-1.25, 0, 0.95),
		"hall, by her photograph": Vector3(-0.32, 0, 4.85),
		"hall (0,2.6) after the wire": Vector3(0.0, 0, 2.6),
		"FACE_SPOT": seat + Vector3(-0.33, 0, -0.66),
		"WATCH_SPOT (suspicious)": seat + Vector3(0.75, 0, 0.5),
		"knife test": Vector3(seat.x + 0.3, 0, seat.z + 0.75),
		"wire offer (seat+0.6,0.7)": seat + Vector3(0.6, 0, 0.7),
		"head scene end (seat+1.4,0.4)": seat + Vector3(1.4, 0, 0.4),
		"fake charge start (sink-1.4,+0.3)": flat.spots.sink_stand + Vector3(-1.4, 0, 0.3),
		"fake charge end (sink-0.5,+0.32)": flat.spots.sink_stand + Vector3(-0.5, 0, 0.32),
		"chase ROUTE (0,4.1)": Vector3(0, 0, 4.1),
		"chase ROUTE (1.3,7.5) wardrobe check": Vector3(1.3, 0, 7.5),
		"bedroom doorway (0,6.4)": Vector3(0, 0, 6.4),
		"living doorway (-0.65,1.8)": Vector3(-0.65, 0, 1.8),
		"bath doorway (0.65,4.1)": Vector3(0.65, 0, 4.1),
		"front door (0,0.5)": Vector3(0, 0, 0.5),
	}
	var pairs := [
		["piano pocket", Vector3(-3.3, 0, 2.6), "front_inside", flat.spots.front_inside],
		["sink_stand", flat.spots.sink_stand, "living door", Vector3(-1.0, 0, 1.8)],
		["hall_mid", flat.spots.hall_mid, "escape window", flat.spots.escape],
		["hall_mid", flat.spots.hall_mid, "front_inside", flat.spots.front_inside],
	]
	for mk: String in man_spots:
		var mp: Vector3 = man_spots[mk]
		var cm := PackedFloat32Array(clr)
		for c in cm.size():
			if cm[c] > 0.0:
				var p := cell_pos(c)
				var d := Vector2(p.x - mp.x, p.z - mp.z).length() - 0.22
				if d < cm[c]:
					cm[c] = maxf(d, 0.0)
		var man_c := clr[cell_of(mp)]
		var line := "  M %-36s %s (his own clearance %.2f)" % [mk, v2(mp), man_c]
		for pr: Array in pairs:
			var r2 := maximin(pr[1], cm)
			var b: PackedInt32Array = r2[0]
			var v := b[cell_of(pr[3])]
			var src_ok := cm[cell_of(pr[1])] >= PR
			line += " | %s>%s: %s" % [pr[0], pr[2], ("src-overlap" if not src_ok else ("BLOCKED" if v < 26 else "%.2f" % (v * 0.02)))]
		print(line)


func home_report() -> void:
	var ox := 38.0
	var ref: Vector3 = flat.spots.home_start
	var res := maximin(ref, clr)
	var spots := {
		"phone table front": Vector3(ox + 2.7, 0, 3.0),
		"home_out (door)": flat.spots.home_out,
		"cane corner": Vector3(ox + 3.2, 0, 0.5),
		"keyboard front": Vector3(ox + 0.95, 0, 0.9),
		"bed side": Vector3(ox + 1.3, 0, 2.9),
		"bed foot / keyboard": Vector3(ox + 0.5, 0, 1.3),
	}
	print("WIDEST ROUTE from home_start %s:" % v2(ref))
	for k: String in spots:
		print("  R %-34s %s -> %s" % [k, v2(spots[k]), bottleneck(spots[k], res, clr)])
	report_components(PR, ref)
	ascii_map(clr)


## From how much reachable floor can each interactable be focused, by the
## rule in player.gd _update_focus (1.7 m ray from the eye; areas behind a
## body are still picked on the second pass)?
func interact_reach(ref: Vector3) -> void:
	var res := maximin(ref, clr)
	var best: PackedInt32Array = res[0]
	print("INTERACTABLE REACH (floor area from which the prompt can appear; needs the crosshair on the box):")
	for id: String in flat.interactables:
		var a: Area3D = flat.interactables[id]
		var gp := a.global_position
		if gp.x < gx0 or gp.x > gx0 + gnx * CELL or gp.z < gz0 or gp.z > gz0 + gnz * CELL:
			continue
		var bs := (a.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var samples: Array[Vector3] = []
		for sx: float in [-0.42, 0.0, 0.42]:
			for sy: float in [-0.42, 0.0, 0.42]:
				for sz: float in [-0.42, 0.0, 0.42]:
					samples.append(a.global_transform * Vector3(sx * bs.size.x, sy * bs.size.y, sz * bs.size.z))
		var n_ok := 0
		var n_wall := 0
		var mnx := INF
		var mxx := -INF
		var mnz := INF
		var mxz := -INF
		for c in clr.size():
			if best[c] < 26:
				continue
			var cp := cell_pos(c)
			if Vector2(cp.x - gp.x, cp.z - gp.z).length() > 1.7 + bs.size.length() * 0.5:
				continue
			var eye := cp + Vector3(0, 1.62, 0)
			var ok := false
			var through := false
			for s: Vector3 in samples:
				var d := s - eye
				if d.length() > 1.7:
					continue
				var pitch := atan2(d.y, Vector2(d.x, d.z).length())
				if pitch < -1.25 or pitch > 1.2:
					continue
				var rq := PhysicsRayQueryParameters3D.create(eye, eye + d.normalized() * 1.7)
				rq.collide_with_areas = true
				rq.collide_with_bodies = true
				rq.collision_mask = 3
				rq.exclude = [walker.get_rid()]
				var hit := space.intersect_ray(rq)
				if hit and hit.collider == a:
					ok = true
					break
				if hit.is_empty() or not (hit.collider is Area3D):
					rq.collide_with_bodies = false
					var hit2 := space.intersect_ray(rq)
					if hit2 and hit2.collider == a:
						ok = true
						through = not hit.is_empty()
						break
			if ok:
				n_ok += 1
				if through:
					n_wall += 1
				mnx = minf(mnx, cp.x)
				mxx = maxf(mxx, cp.x)
				mnz = minf(mnz, cp.z)
				mxz = maxf(mxz, cp.z)
		print("  I %-14s at %s size %s : %.2f m2 of floor (%.2f m2 only THROUGH a solid body)%s" % [id, v3(gp), v3(bs.size), n_ok * CELL * CELL, n_wall * CELL * CELL,
				("  cells x[%.2f,%.2f] z[%.2f,%.2f]" % [mnx, mxx, mnz, mxz]) if n_ok > 0 else "  << UNREACHABLE"])
