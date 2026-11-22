extends Node3D
## Test scene for the outdoor night (scenes/outside_test.tscn): builds the
## exterior at (400, 0, 0) like game.gd will, switches an InteriorEnv
## WorldEnvironment to the outdoor night and puts a Player in walk mode at his
## door. Walk with WASD; footsteps change with the ground.
##
## User args (after --):
##   --capture                 dev capture hook (--shots=t1,t2 --out=DIR)
##   --pos=x,y,z  --yaw=deg  --pitch=deg     place the player (global coords)
##   --at=spot                 stand on a named spot (ExteriorBuilder.spots)
##   --tour=a;b;c              a viewpoint every --dwell s (default 0.6) from
##                             t = 2 s. Each viewpoint: "lx,lz,yaw,pitch[,h]"
##                             in the exterior's local metres (h: extra eye
##                             height) or "spot,yaw,pitch"
##   --lens                    the game's post effect with the dark glasses on
##   --walktest=walk|chase|both  drive the player along path() and report stalls
##   --pathbench               time path() calls
##   --quality=N               graphics preset (dev_capture)

var world: InteriorEnv
var ext: ExteriorBuilder
var player: Player
var post: ShaderMaterial
var _args := PackedStringArray()
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	world = InteriorEnv.new()
	add_child(world)
	world.setup(self)
	ext = ExteriorBuilder.new()
	ext.name = "Exterior"
	ext.position = Vector3(400.0, 0.0, 0.0)
	add_child(ext)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.position = Vector3(0, 100, 0)
	player.set_mode("locked")
	if _args.has("--capture"):
		add_child(load("res://scripts/dev_capture.gd").new())
	if _args.has("--lens"):
		_add_post()
	await ext.build()
	ext.enter(world.world_env)
	player.global_position = ext.spots.his_door
	player.yaw = ext.spot_yaw.his_door
	player.pitch = 0.0
	player.set_mode("walk", player.yaw)
	player.stepped.connect(_on_step)
	if not _args.has("--capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[outside] build %d ms, spots: %s" % [ext.build_ms, ", ".join(ext.spots.keys())])
	for a: String in _args:
		if a.begins_with("--pos="):
			var p := a.substr(6).split(",")
			player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			player.set_mode("locked")
		elif a.begins_with("--at="):
			var s := a.substr(5)
			if ext.spots.has(s):
				player.global_position = ext.spots[s]
				player.yaw = ext.spot_yaw.get(s, player.yaw)
		elif a.begins_with("--yaw="):
			player.yaw = deg_to_rad(float(a.substr(6)))
		elif a.begins_with("--pitch="):
			player.pitch = deg_to_rad(float(a.substr(8)))
		elif a.begins_with("--tour="):
			_tour(a.substr(7).split(";"))
		elif a.begins_with("--walktest"):
			_walk_test(a.substr(11) if a.length() > 11 else "both")
		elif a == "--pathbench":
			_path_bench()
		elif a == "--slopecheck":
			_slope_check()
		elif a == "--stats":
			_stats()
		elif a == "--spots":
			for k: String in ext.spots:
				var g: Vector3 = ext.spots[k]
				print("[spot] %-16s global (%.1f, %.2f, %.1f)  local (%.1f, %.2f, %.1f)%s" % [k, g.x, g.y, g.z, g.x - 400.0, g.y, g.z, ("  yaw %.0f deg" % rad_to_deg(ext.spot_yaw[k])) if ext.spot_yaw.has(k) else ""])
		elif a.begins_with("--probe="):
			var q := a.substr(8).split(",")
			_probe(Vector2(float(q[0]), float(q[1])))


func _add_post() -> void:
	var fx := CanvasLayer.new()
	add_child(fx)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/screen_fx.gdshader")
	post.set_shader_parameter("cold", 1.0)
	post.set_shader_parameter("sunglasses", 0.8)
	post.set_shader_parameter("vignette", 0.55)
	post.set_shader_parameter("grain", 0.04)
	rect.material = post
	fx.add_child(rect)


func _process(delta: float) -> void:
	_t += delta
	if post:
		post.set_shader_parameter("time_s", _t)


func _on_step(pos: Vector3) -> void:
	if ext == null or _args.has("--capture"):
		return
	var path := ext.step_sound(pos)
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.bus = "SFX"
	p.volume_db = -4.0 if player.speed > 1.5 else -8.0
	p.pitch_scale = _rng.randf_range(0.92, 1.08)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Viewpoints for stills.
func _tour(stops: PackedStringArray) -> void:
	var dwell := 0.6
	for a: String in _args:
		if a.begins_with("--dwell="):
			dwell = float(a.substr(8))
	while _t < 2.0:
		await get_tree().process_frame
	var times: Array[String] = []
	for k in stops.size():
		times.append("%.2f" % (2.0 + k * dwell + dwell * 0.85))
	print("[outside] tour shots at: ", ",".join(times))
	for si in stops.size():
		while _t < 2.0 + si * dwell:
			await get_tree().process_frame
		var v := stops[si].split(",")
		player.set_mode("locked")
		if v[0].is_valid_float():
			var lx := float(v[0])
			var lz := float(v[1])
			var h := float(v[4]) if v.size() > 4 and v[4].is_valid_float() else 0.0
			player.global_position = ext.to_global(Vector3(lx, ext.height_at(lx, lz) + h, lz))
			player.yaw = deg_to_rad(float(v[2]))
			player.pitch = deg_to_rad(float(v[3]))
		else:
			player.global_position = ext.spots.get(v[0], player.global_position)
			player.yaw = deg_to_rad(float(v[1])) if v.size() > 1 else ext.spot_yaw.get(v[0], 0.0)
			player.pitch = deg_to_rad(float(v[2])) if v.size() > 2 and v[2].is_valid_float() else 0.0
		# a trailing "L" shows this view through his dark glasses (the game's post effect)
		var lens := v[v.size() - 1] == "L"
		if lens and post == null:
			_add_post()
		ext.exposure_boost = 1.6 if lens or _args.has("--lens") else 1.0
		if post:
			(post as ShaderMaterial).set_shader_parameter("sunglasses", 0.8 if lens or _args.has("--lens") else 0.0)
			(post as ShaderMaterial).set_shader_parameter("cold", 1.0 if lens or _args.has("--lens") else 0.0)
			(post as ShaderMaterial).set_shader_parameter("vignette", 0.55 if lens or _args.has("--lens") else 0.0)
			(post as ShaderMaterial).set_shader_parameter("grain", 0.04 if lens or _args.has("--lens") else 0.0)
		player.snap_eye()


## Drive the player with a held W along path() and report where it stalls.
func _walk_test(which: String) -> void:
	var routes: Array = []
	if which == "walk" or which == "both" or which == "all":
		routes.append(["his_door", "her_unit_door", 1.05])
	if which == "chase" or which == "both" or which == "all":
		routes.append(["chase_start", "forest_exit", 3.2])
	if which == "estate":
		var est2 := PackedVector3Array([ext.spots.his_door])
		for q: Vector2 in [Vector2(-17, -27), Vector2(32, -27), Vector2(32, 28.5), Vector2(39, 28.6)]:
			est2.append(ext.to_global(Vector3(q.x, ext.height_at(q.x, q.y), q.y)))
		est2.append(ext.spots.her_unit_door)
		routes.append(["estate paths", est2, 1.05])
	if which == "trails" or which == "all":
		# the paved way across the estate, then every trail end to end and back
		var est := PackedVector3Array([ext.spots.his_door])
		for q: Vector2 in [Vector2(-17, -27), Vector2(32, -27), Vector2(32, 28.5), Vector2(39, 28.6)]:
			est.append(ext.to_global(Vector3(q.x, ext.height_at(q.x, q.y), q.y)))
		est.append(ext.spots.her_unit_door)
		routes.append(["estate paths", est, 1.05])
		for k in ext._trails.size():
			var tp: PackedVector2Array = ext._trails[k].pts
			var fwd := PackedVector3Array()
			for q2: Vector2 in tp:
				fwd.append(ext.to_global(Vector3(q2.x, ext.height_at(q2.x, q2.y), q2.y)))
			routes.append(["trail %d" % k, fwd, 3.2])
			var back := fwd.duplicate()
			back.reverse()
			routes.append(["trail %d back" % k, back, 3.2])
	var speed_arg := -1.0
	for a: String in _args:
		if a.begins_with("--speed="):
			speed_arg = float(a.substr(8))
	var all_ok := true
	for r: Array in routes:
		var pts: PackedVector3Array
		var ms := 0.0
		if r[1] is PackedVector3Array:
			pts = r[1]
		else:
			var tu := Time.get_ticks_usec()
			pts = ext.path(ext.spots[r[0]], ext.spots[r[1]])
			ms = (Time.get_ticks_usec() - tu) / 1000.0
		var a: Vector3 = pts[0] if not pts.is_empty() else Vector3.ZERO
		var b: Vector3 = pts[pts.size() - 1] if not pts.is_empty() else Vector3.ZERO
		var plen := 0.0
		for i in range(1, pts.size()):
			plen += pts[i].distance_to(pts[i - 1])
		print("[walktest] %s -> %s: path %d points, %.1f m, %.2f ms" % [r[0], str(r[1]) if r[1] is String else "end", pts.size(), plen, ms])
		if _args.has("--dumppath"):
			for i in pts.size():
				if i % 4 == 0 or i < 20:
					print("[walktest]   p%d %s" % [i, str(ext.to_local(pts[i]))])
		if pts.is_empty():
			print("[walktest] NO PATH")
			all_ok = false
			continue
		player.global_position = a + Vector3(0, 0.05, 0)
		player.velocity = Vector3.ZERO
		player.set_mode("walk", player.yaw)
		player.speed = speed_arg if speed_arg > 0.0 else float(r[2])
		_key(KEY_W, true)
		var idx := 1
		var t := 0.0
		var stalls: Array = []
		var jumps := 0
		var check_t := 0.0
		var check_pos := player.global_position
		var prev := player.global_position
		var max_t := plen / player.speed * 2.5 + 20.0
		var min_y := INF
		while idx < pts.size() and t < max_t:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			var here := player.global_position
			if here.distance_to(prev) > 1.0:
				jumps += 1
				print("[walktest]   teleported (unstick) at %s" % str(ext.to_local(prev)))
			prev = here
			min_y = minf(min_y, here.y - (ext.to_global(Vector3(0, ext.height_at(ext.to_local(here).x, ext.to_local(here).z), 0)).y))
			# progress = the closest point on the next few segments; steer at a
			# carrot 1.5 m further along the polyline
			var h2 := Vector2(here.x, here.z)
			var best_d := INF
			var best_seg := maxi(idx - 1, 0)
			var best_p := h2
			for sgi in range(maxi(idx - 1, 0), mini(idx + 4, pts.size() - 1)):
				var sa := Vector2(pts[sgi].x, pts[sgi].z)
				var sb := Vector2(pts[sgi + 1].x, pts[sgi + 1].z)
				var sv := sb - sa
				var tt := clampf((h2 - sa).dot(sv) / maxf(sv.length_squared(), 1e-6), 0.0, 1.0)
				var cp := sa + sv * tt
				var dd := cp.distance_to(h2)
				if dd < best_d - 0.01:
					best_d = dd
					best_seg = sgi
					best_p = cp
			idx = maxi(idx, best_seg + 1)
			var rem := 1.5
			var cur := best_p
			var si := best_seg
			while si < pts.size() - 1:
				var nxt := Vector2(pts[si + 1].x, pts[si + 1].z)
				var dl := cur.distance_to(nxt)
				if dl >= rem:
					cur = cur + (nxt - cur).normalized() * rem
					break
				rem -= dl
				cur = nxt
				si += 1
			var to := Vector2(cur.x - h2.x, cur.y - h2.y)
			if to.length() > 0.05:
				player.yaw = lerp_angle(player.yaw, atan2(-to.x, -to.y), 0.5)
			if idx >= pts.size() - 1 and h2.distance_to(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)) < 0.8:
				idx = pts.size()
			if _args.has("--tracewalk") and int(t * 60.0) % 15 == 0:
				print("[walktest]     t=%.2f pos %s vel %.2f floor %s yaw %.0f idx %d" % [t, str(ext.to_local(here)), Vector2(player.velocity.x, player.velocity.z).length(), player.is_on_floor(), rad_to_deg(player.yaw), idx])
			check_t += 1.0 / 60.0
			if check_t > 1.5:
				var moved := Vector2(here.x - check_pos.x, here.z - check_pos.z).length()
				if moved < 0.35 * player.speed:
					stalls.append(ext.to_local(here))
					print("[walktest]   STALL at local %s (moved %.2f m in 1.5 s, next point %d/%d)" % [str(ext.to_local(here)), moved, idx, pts.size()])
					# nudge on so the rest of the route is still tested
					player.global_position = pts[mini(idx + 1, pts.size() - 1)] + Vector3(0, 0.1, 0)
					idx = mini(idx + 2, pts.size() - 1)
				check_t = 0.0
				check_pos = player.global_position
		_key(KEY_W, false)
		var reached := player.global_position.distance_to(b) < 2.0
		print("[walktest] %s: %s in %.1f s, %d stalls, %d unstick jumps, lowest foot %.2f m vs ground" % [r[0], "REACHED" if reached else "NOT REACHED", t, stalls.size(), jumps, min_y])
		all_ok = all_ok and reached and stalls.is_empty() and jumps == 0
	print("[walktest] RESULT ", "OK" if all_ok else "PROBLEMS")
	if _args.has("--quit-when-done"):
		get_tree().quit()


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _path_bench() -> void:
	await get_tree().process_frame
	var pairs := [["his_door", "her_unit_door"], ["chase_start", "forest_exit"], ["chase_start", "hide_4"], ["forest_gate", "hide_5"], ["bridge", "his_door"]]
	for pr: Array in pairs:
		var tot := 0.0
		var n := 10
		var pts := PackedVector3Array()
		for k in n:
			var tu := Time.get_ticks_usec()
			pts = ext.path(ext.spots[pr[0]], ext.spots[pr[1]])
			tot += (Time.get_ticks_usec() - tu) / 1000.0
		var plen := 0.0
		for i in range(1, pts.size()):
			plen += pts[i].distance_to(pts[i - 1])
		print("[pathbench] %s -> %s: %.2f ms avg, %d points, %.1f m" % [pr[0], pr[1], tot / n, pts.size(), plen])
	# random pairs over the walkable area
	var worst := 0.0
	var tot2 := 0.0
	var fails := 0
	for k in 40:
		var a := ext.to_global(Vector3(_rng.randf_range(-80, 185), 0, _rng.randf_range(-70, 112)))
		var b := ext.to_global(Vector3(_rng.randf_range(-80, 185), 0, _rng.randf_range(-70, 112)))
		var tu := Time.get_ticks_usec()
		var pts2 := ext.path(a, b)
		var ms := (Time.get_ticks_usec() - tu) / 1000.0
		var ta := Time.get_ticks_usec()
		var raw := ext._astar.get_id_path(ext._free_near(ext._cell(ext.to_local(a))), ext._free_near(ext._cell(ext.to_local(b))), true)
		var ams := (Time.get_ticks_usec() - ta) / 1000.0
		if ms > 15.0:
			print("[pathbench]   slow pair %s -> %s: %.1f ms total, %.1f ms A*, %d jump points, %d out" % [str(ext.to_local(a)), str(ext.to_local(b)), ms, ams, raw.size(), pts2.size()])
		tot2 += ms
		worst = maxf(worst, ms)
		if pts2.is_empty():
			fails += 1
	print("[pathbench] 40 random pairs: %.2f ms avg, %.2f ms worst, %d without a route" % [tot2 / 40.0, worst, fails])
	# the chase: a pursuer 5-40 m behind someone on the trails
	var tot3 := 0.0
	var worst3 := 0.0
	var main: PackedVector2Array = ext._trails[0].pts
	for k in 60:
		var i := _rng.randi_range(0, main.size() - 1)
		var j := clampi(i - _rng.randi_range(10, 80), 0, main.size() - 1)
		var a3 := ext.to_global(Vector3(main[j].x, 0, main[j].y) + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)))
		var b3 := ext.to_global(Vector3(main[i].x, 0, main[i].y))
		var tu3 := Time.get_ticks_usec()
		ext.path(a3, b3)
		var ms3 := (Time.get_ticks_usec() - tu3) / 1000.0
		tot3 += ms3
		worst3 = maxf(worst3, ms3)
	print("[pathbench] 60 chase-range queries (pursuer 5-40 m behind): %.2f ms avg, %.2f ms worst" % [tot3 / 60.0, worst3])


## Dev: list the colliders a player capsule would touch at local (x, z).
func _probe(p: Vector2) -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var y := ext.height_at(p.x, p.y)
	q.transform = Transform3D(Basis.IDENTITY, ext.to_global(Vector3(p.x, y + 0.9, p.y)))
	var hits := space.intersect_shape(q, 16)
	print("[probe] local (%.2f, %.2f) ground %.2f: %d hits" % [p.x, p.y, y, hits.size()])
	for h: Dictionary in hits:
		var body: CollisionObject3D = h.collider
		var sid: int = h.shape
		var owner_id := body.shape_find_owner(sid)
		var xf := body.shape_owner_get_transform(owner_id)
		var sh := body.shape_owner_get_shape(owner_id, 0)
		print("[probe]   %s %s at %s size %s" % [body.name, sh.get_class(), str(xf.origin), str(sh.get("size") if sh is BoxShape3D else sh.get("radius"))])


## Dev: the steepest ground inside the walkable area (terrain grid, 1 m).
func _slope_check() -> void:
	var w := ExteriorBuilder.WALK
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var over30 := 0
	var total := 0
	var x := w.position.x
	while x < w.end.x:
		var z := w.position.y
		while z < w.end.y:
			var h := ext._hraw(x, z)
			var gx := (ext._hraw(x + 0.5, z) - ext._hraw(x - 0.5, z))
			var gz := (ext._hraw(x, z + 0.5) - ext._hraw(x, z - 0.5))
			var ang := rad_to_deg(atan(Vector2(gx, gz).length()))
			total += 1
			if ang > 30.0:
				over30 += 1
			if ang > worst:
				worst = ang
				worst_at = Vector2(x, z)
			z += 1.0
		x += 1.0
	print("[slope] walkable ground: steepest %.1f deg at %s, %d of %d samples over 30 deg" % [worst, str(worst_at), over30, total])


## Dev: what the exterior is made of (for the performance budget).
func _stats() -> void:
	var mmis := 0
	var inst := 0
	var lights := 0
	var shadow_lights := 0
	var meshes := 0
	var stack: Array[Node] = [ext]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D:
			mmis += 1
			inst += (n as MultiMeshInstance3D).multimesh.instance_count
		elif n is MeshInstance3D:
			meshes += 1
		elif n is Light3D:
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadow_lights += 1
	print("[stats] %d MultiMeshInstance3D (%d instances), %d MeshInstance3D, %d lights (%d with shadows), %d collision shapes" % [mmis, inst, meshes, lights, shadow_lights, ext._body.get_shape_owners().size()])
	for k: String in ext._tree:
		var info: Dictionary = ext._tree[k]
		print("[stats]   %s: near %d tris, far %d tris, height %.1f m" % [k, _tris(info.near), _tris(info.far), info.h])


func _tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
