extends "res://scratch_test/plan_col_base.gd"
## PLANNING ONLY. Dynamic flood fill with the real move_and_slide (gravity,
## floor snapping, depenetration): from a start, every reached position is
## expanded in 8 directions for 7 physics frames (12 cm at walking speed).
## Reports: cells reached, falls out of the world, one-way cells (reached but
## with no way back), what blocks most often, and what player.gd's unstick()
## would do from every reached position.

const Q := 0.1

var nodes := {}          # Vector3i -> Vector3
var parent := {}
var out_edges := {}      # Vector3i -> Array[Vector3i]
var order: Array[Vector3i] = []
var voids: Array = []
var drops: Array = []
var blockers := {}


func _ready() -> void:
	await build_world(true)
	var regions := [
		["FLAT", flat.spots.hall_mid, 1.05],
		["HOME", flat.spots.home_start, 1.05],
		["STAIRS", stairs.to_global(Vector3(-0.68, 0.05, 0.4)), 1.05],
	]
	for a: String in OS.get_cmdline_user_args():
		if a == "--fast":
			for r: Array in regions:
				r[2] = 2.1
	for r: Array in regions:
		print("\n===== %s (speed %.2f) from %s =====" % [r[0], r[2], v3(r[1])])
		explore(r[1], r[2])
		lap("explore")
		report(r[0], r[1])
		lap("report")
		unstick_audit(r[0])
		lap("unstick audit")
	get_tree().quit()


func key_of(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x / Q), roundi(p.y / 0.3), roundi(p.z / Q))


func step_direct(v: Vector2) -> void:
	walker.velocity.x = v.x
	walker.velocity.z = v.y
	if walker.is_on_floor():
		walker.velocity.y = -0.1
	else:
		walker.velocity.y -= 9.8 * DT
	walker.move_and_slide()


func explore(start: Vector3, speed: float) -> void:
	nodes.clear()
	parent.clear()
	out_edges.clear()
	order.clear()
	voids.clear()
	drops.clear()
	blockers.clear()
	place(start)
	for i in 30:
		step_direct(Vector2.ZERO)
	var s := walker.global_position
	var sk := key_of(s)
	nodes[sk] = s
	order.append(sk)
	var head := 0
	var dirs: Array[Vector2] = []
	for k in 8:
		dirs.append(Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0)))
	var frames := 7 if speed < 1.5 else 4
	while head < order.size() and order.size() < 60000:
		var k: Vector3i = order[head]
		head += 1
		var pos: Vector3 = nodes[k]
		var outs: Array[Vector3i] = []
		for d: Vector2 in dirs:
			place(pos)
			var f := 0
			while f < frames * 2:
				step_direct(d * speed)
				f += 1
				var cp := walker.global_position
				if f >= frames and Vector2(cp.x - pos.x, cp.z - pos.z).length() >= Q * 1.2:
					break
			var guard := 0
			while not walker.is_on_floor() and walker.global_position.y > pos.y - 30.0 and guard < 900:
				step_direct(Vector2.ZERO)
				guard += 1
			var np := walker.global_position
			if np.y < pos.y - 25.0 or guard >= 900:
				voids.append([pos, d])
				continue
			var moved := Vector2(np.x - pos.x, np.z - pos.z).length()
			if moved < 0.03 and absf(np.y - pos.y) < 0.05:
				for t: String in touching():
					blockers[t] = int(blockers.get(t, 0)) + 1
				continue
			if np.y < pos.y - 0.12:
				drops.append([pos, np])
			var k2 := key_of(np)
			if k2 == k:
				continue
			if not outs.has(k2):
				outs.append(k2)
			if not nodes.has(k2):
				nodes[k2] = np
				parent[k2] = k
				order.append(k2)
		out_edges[k] = outs


func report(label: String, start: Vector3) -> void:
	var sk: Vector3i = order[0]
	print("REACHED %d cells of %.0f cm (%.1f m2)" % [nodes.size(), Q * 100.0, nodes.size() * Q * Q])
	# levels
	var by_y := {}
	for k: Vector3i in nodes:
		by_y[k.y] = int(by_y.get(k.y, 0)) + 1
	var ys := by_y.keys()
	ys.sort()
	var line := "  by height (0.3 m bands): "
	for y: int in ys:
		line += "%.1f:%d " % [y * 0.3, by_y[y]]
	print(line)
	print("FALLS OUT OF THE WORLD: %d moves" % voids.size())
	var shown := 0
	var seen := {}
	for v: Array in voids:
		var kk := Vector2i(roundi((v[0] as Vector3).x / 0.3), roundi((v[0] as Vector3).z / 0.3))
		if seen.has(kk):
			continue
		seen[kk] = true
		if shown < 12:
			print("  VOID from %s heading (%.1f,%.1f)" % [v3(v[0]), (v[1] as Vector2).x, (v[1] as Vector2).y])
		shown += 1
	print("  (%d distinct 30 cm areas you can fall from)" % seen.size())
	print("DROPS (>12 cm down in one move): %d" % drops.size())
	seen.clear()
	shown = 0
	for d: Array in drops:
		var kk := Vector3i(roundi((d[0] as Vector3).x / 0.4), roundi((d[0] as Vector3).y / 0.4), roundi((d[0] as Vector3).z / 0.4))
		if seen.has(kk):
			continue
		seen[kk] = true
		if shown < 14:
			print("  DROP %s -> %s (%.2f m)" % [v3(d[0]), v3(d[1]), (d[0] as Vector3).y - (d[1] as Vector3).y])
		shown += 1
	# who can get back to the start (on the recorded moves)?
	var rev := {}
	for k: Vector3i in out_edges:
		for k2: Vector3i in out_edges[k]:
			if not rev.has(k2):
				rev[k2] = []
			(rev[k2] as Array).append(k)
	var back := {sk: true}
	var q: Array[Vector3i] = [sk]
	while not q.is_empty():
		var k: Vector3i = q.pop_back()
		for k0: Vector3i in rev.get(k, []):
			if not back.has(k0):
				back[k0] = true
				q.append(k0)
	var traps: Array[Vector3i] = []
	for k: Vector3i in nodes:
		if not back.has(k):
			traps.append(k)
	print("ONE-WAY CELLS (reached, but no recorded way back to the start): %d" % traps.size())
	# confirm by really walking back along the parents
	var confirmed := 0
	var groups := {}
	for k: Vector3i in traps:
		var chain: Array[Vector3] = []
		var cur := k
		var guard := 0
		while parent.has(cur) and guard < 100000:
			cur = parent[cur]
			chain.append(nodes[cur])
			guard += 1
		place(nodes[k])
		var ok := true
		var fail_at := Vector3.ZERO
		var fail_to := Vector3.ZERO
		var idx := 0
		# skip ahead along the chain while still in the trapped set
		for wp: Vector3 in chain:
			idx += 1
			if not walk_to(wp, 1.05, 150, 0.09):
				ok = false
				fail_at = walker.global_position
				fail_to = wp
				break
			if back.has(key_of(wp)):
				break
		if not ok:
			confirmed += 1
			var gk := Vector3i(roundi(fail_at.x / 0.5), roundi(fail_at.y / 0.5), roundi(fail_at.z / 0.5))
			if not groups.has(gk):
				groups[gk] = [0, nodes[k], fail_at, fail_to, touching()]
			groups[gk][0] = int(groups[gk][0]) + 1
	print("  confirmed by walking the way back: %d" % confirmed)
	for gk: Vector3i in groups:
		var g: Array = groups[gk]
		print("  ONE-WAY x%d e.g. from %s: stops at %s heading for %s against %s" % [g[0], v3(g[1]), v3(g[2]), v3(g[3]), str(g[4])])
	var bl := blockers.keys()
	bl.sort_custom(func(a: String, b: String) -> bool: return int(blockers[a]) > int(blockers[b]))
	print("WHAT STOPS A MOVE DEAD (moved < 3 cm in 7 frames), top 12:")
	for i in mini(12, bl.size()):
		print("  B %5d  %s" % [blockers[bl[i]], bl[i]])


func unstick_audit(label: String) -> void:
	var n_touch := 0
	var n_ok := 0
	var cats := {}
	var examples := {}
	var jump_sum := 0.0
	for k: Vector3i in nodes:
		var p: Vector3 = nodes[k]
		var d := unstick_dest(p)
		if d == p:
			continue
		n_touch += 1
		var cat := ""
		if d == Vector3.INF:
			cat = "NO CANDIDATE (stays stuck)"
		else:
			jump_sum += p.distance_to(d)
			var near := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						var kk := key_of(d) + Vector3i(dx, dy, dz)
						if nodes.has(kk) and (nodes[kk] as Vector3).distance_to(d) < 0.25:
							near = true
			var fy := floor_y(d, 0.3, 30.0)
			var through := ray_blocked(p + Vector3(0, 0.9, 0), d + Vector3(0, 0.9, 0))
			if fy == -INF:
				cat = "NO FLOOR under the new spot (falls for ever)"
			elif fy < d.y - 0.5:
				cat = "DROP of %.1f m at the new spot" % snappedf(d.y - fy, 0.5)
			elif not near:
				cat = "OUTSIDE the walkable set" + (" (through a wall/prop)" if through else "")
			elif through:
				cat = "through a solid body to another walkable spot"
			else:
				cat = "ok"
				n_ok += 1
		if cat != "ok":
			cats[cat] = int(cats.get(cat, 0)) + 1
			if not examples.has(cat):
				examples[cat] = []
			if (examples[cat] as Array).size() < 5:
				(examples[cat] as Array).append("%s -> %s past %s" % [v3(p), v3(d) if d != Vector3.INF else "-", str(hits(p, 0.27, 5, 0.1, 3))])
	print("UNSTICK AUDIT: %d of %d reached positions touch something (so a 1.2 s push calls unstick); %d land on a normal walkable spot; mean jump %.2f m" % [n_touch, nodes.size(), n_ok, jump_sum / maxf(1.0, n_touch)])
	for c: String in cats:
		print("  U %5d  %s" % [cats[c], c])
		for e: String in examples[c]:
			print("        e.g. ", e)
