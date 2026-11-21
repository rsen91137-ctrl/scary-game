extends "res://scratch_test/plan_col_base.gd"
## PLANNING ONLY. The stairwell: a scripted climb to her floor with the real
## walking code, the way back down, the floor profile along each flight, the
## hole on the ground floor, the top of the last flight.


func _ready() -> void:
	await build_world(true)
	var L := func(x: float, y: float, z: float) -> Vector3: return stairs.to_global(Vector3(x, y, z))
	var ZL := StairBuilder.ZL
	var ZH := StairBuilder.ZH
	var H := StairBuilder.H
	# floor profile along the middle of flight A and flight B of floor 0
	for side: float in [-0.68, 0.68]:
		var line := "PROFILE x=%.2f (floor height by z, rays from above): " % side
		var base := 0.0 if side < 0.0 else H * 0.5
		var z := ZL - 0.5
		while z <= ZH + 0.5:
			var top := base + H * 0.5 + 1.0 if side < 0.0 else base + H * 0.5 + 1.0
			var rq := PhysicsRayQueryParameters3D.create(L.call(side, top, z), L.call(side, -1.0, z))
			rq.collision_mask = 1
			var hit := space.intersect_ray(rq)
			line += "z%.2f:%s " % [z, ("%.2f" % (float(hit.position.y))) if hit else "VOID"]
			z += 0.1
		print(line)
	# 1) straight up flight A with the game's own stepping
	print("CLIMB flight A from the start, holding forward (+z):")
	place(L.call(-0.68, 0.05, 0.4))
	for i in 20:
		step(Vector2.ZERO)
	var last := walker.global_position
	for f in 600:
		step(Vector2(0, 1) * 1.05)
		if f % 30 == 29:
			var p := walker.global_position
			print("  t=%.1fs local %s on_floor=%s wall=%s moved=%.3f vel=%s touching=%s" % [(f + 1) / 60.0, v3(stairs.to_local(p)), walker.is_on_floor(), walker.is_on_wall(),
					p.distance_to(last), v3(walker.velocity), str(touching())])
			last = p
	# 2) the whole climb by waypoints
	print("CLIMB to her floor by waypoints:")
	place(L.call(-0.68, 0.05, 0.4))
	var wps: Array[Vector3] = []
	for k in 2:
		wps.append(L.call(-0.68, k * H, ZL - 0.1))
		wps.append(L.call(-0.68, k * H + H * 0.5, ZH + 0.5))
		wps.append(L.call(0.68, k * H + H * 0.5, ZH + 0.5))
		wps.append(L.call(0.68, (k + 1) * H, ZL - 0.5))
		wps.append(L.call(-0.68, (k + 1) * H, 0.4))
	wps.append(L.call(-0.9, 2 * H, -1.0))
	var t := 0
	var ok := true
	for wp: Vector3 in wps:
		var before := walker.global_position
		var got := false
		for f in 900:
			var p := walker.global_position
			var d := Vector2(wp.x - p.x, wp.z - p.z)
			if d.length() < 0.1:
				got = true
				break
			step(d.normalized() * 1.05)
			t += 1
		var p2 := walker.global_position
		print("  -> %s : %s at local %s (y %.2f, wanted %.2f) t=%.1fs" % [v3(stairs.to_local(wp)), "ok" if got else "STUCK", v3(stairs.to_local(p2)), p2.y, wp.y, t / 60.0])
		if not got:
			print("     touching ", touching())
			ok = false
			break
	print("CLIMB RESULT: ", "reached her door" if ok else "FAILED")
	# 3) back down from her floor
	print("DESCEND from her floor:")
	place(L.call(-0.68, 2 * H + 0.05, 0.4))
	for i in 20:
		step(Vector2.ZERO)
	var down: Array[Vector3] = [L.call(0.68, 2 * H, ZL - 0.5), L.call(0.68, 1.5 * H, ZH + 0.5), L.call(-0.68, 1.5 * H, ZH + 0.5), L.call(-0.68, H, ZL - 0.5)]
	for wp: Vector3 in down:
		var got := false
		for f in 900:
			var p := walker.global_position
			var d := Vector2(wp.x - p.x, wp.z - p.z)
			if d.length() < 0.1:
				got = true
				break
			step(d.normalized() * 1.05)
		var p2 := walker.global_position
		print("  -> %s : %s at local %s touching %s" % [v3(stairs.to_local(wp)), "ok" if got else "BLOCKED", v3(stairs.to_local(p2)), str(touching()) if not got else ""])
		if not got:
			break
	# 4) the ground-floor hole
	print("GROUND FLOOR, right-hand side, walking +z from the start landing:")
	place(L.call(0.68, 0.05, 0.4))
	for i in 20:
		step(Vector2.ZERO)
	for f in 400:
		step(Vector2(0, 1) * 1.05)
		if f % 40 == 39:
			print("  t=%.1fs local %s on_floor=%s" % [(f + 1) / 60.0, v3(stairs.to_local(walker.global_position)), walker.is_on_floor()])
	# 5) past her floor: the flights above the top landing
	print("ABOVE HER FLOOR (flight A and B of the top floor):")
	place(L.call(-0.68, 2 * H + 0.05, 0.4))
	for i in 20:
		step(Vector2.ZERO)
	var up: Array[Vector3] = [L.call(-0.68, 2 * H, ZL - 0.1), L.call(-0.68, 2.5 * H, ZH + 0.5), L.call(0.68, 2.5 * H, ZH + 0.5), L.call(0.68, 3 * H, ZL - 0.6), L.call(0.0, 3 * H, -1.0)]
	for wp: Vector3 in up:
		var got := false
		for f in 900:
			var p := walker.global_position
			var d := Vector2(wp.x - p.x, wp.z - p.z)
			if d.length() < 0.1:
				got = true
				break
			step(d.normalized() * 1.05)
		var p2 := walker.global_position
		print("  -> %s : %s at local %s on_floor=%s" % [v3(stairs.to_local(wp)), "ok" if got else "no", v3(stairs.to_local(p2)), walker.is_on_floor()])
	get_tree().quit()
