class_name ActDinner
extends Act
## Dinner by candlelight. He has been cooking since you sat down to play.
## Her head is on the cake stand at your left, combed, eyes shut, as if she
## were listening. Eat. A blind guest does not know what is on his plate.

const NEED := 5              # bites before he is satisfied

var bites := 0
var _fork: Node3D
var _morsel: MeshInstance3D
var _ring_bite := 3
var _held := 0.0
var _chewing := false
var _idle := 0.0
var _seat_yaw := 0.0


func run() -> void:
	if not has_spot("dinner_seat"):
		return
	var seat := spot("dinner_seat", Vector3(-7.0, 0.0, 2.95))
	var look := spot("dinner_look", seat + Vector3(0.0, 0.9, -1.2))
	var his := spot("his_seat", Vector3(-9.05, 0.0, 2.0))
	var stand := spot("head_stand", seat + Vector3(-0.45, 0.95, -0.55))
	var p: Player = g.player
	g._tr("dinner")
	g.scares.busy += 1
	g.ui.objective("OBJ_DINNER")
	g.ui.hint("HINT_DINNER", 7.0)
	var t := 0.0
	while alive() and not near(seat, 1.0) and t < 60.0:
		await wait(0.2)
		t += 0.2
	if not alive():
		g.scares.busy -= 1
		return
	# he pulls the chair out for you
	g.ui.fade_to(1.0, 0.5)
	await wait(0.6)
	p.global_position = seat
	var d := look - seat
	_seat_yaw = atan2(-d.x, -d.z)
	p.set_mode("seated", _seat_yaw)
	p.snap_eye()
	g.dinner_mood(true)
	g.place_head_on_stand(stand, p.eye_pos())
	g.serve_dinner(spot("plate", seat + Vector3(0.0, 0.79, -0.42)))
	g.man.stop()
	g.man.visible = true
	g.man.global_position = his
	g.man.look_at(Vector3(seat.x, his.y, seat.z), Vector3.UP, true)
	g.man.set_pose("sit", 0.0)
	g.man.look_node = p.head
	g.ui.objective("")
	g.ui.fade_to(0.0, 0.8)
	await wait(1.0)
	if not alive():
		_out()
		return
	g.state.visual("head_stand", stand, 5.0, 0.9)
	g.think("THINK_DINNER_HEAD", 4.0)
	await g.man_say("MAN_D_1", 3.4)
	await g.man_say("MAN_D_2", 3.0)
	if not alive():
		_out()
		return
	g.ui.hint("HINT_EAT", 9.0)
	_make_fork()
	# what happens while you eat, in a different order each night
	var events := ["eyes", "ankle", "wine", "story", "dessert"]
	events.shuffle()
	events.erase("dessert")
	events.append("dessert")
	_ring_bite = g._rng.randi_range(2, 4)
	var next_event := 9.0
	var clock := 0.0
	while alive() and (bites < NEED or not events.is_empty()) and clock < 220.0:
		await g.get_tree().process_frame
		var dt: float = g.get_process_delta_time()
		clock += dt
		_eat(dt)
		_idle += dt
		if _idle > 15.0 and bites < NEED:
			_idle = 0.0
			g.state.add_suspicion(7.0, "TELL_REFUSE")
			await g.man_say("MAN_D_EAT", 1.8)
		if not events.is_empty() and clock > next_event and not _chewing:
			var e: String = events.pop_front()
			if e == "dessert" and bites < NEED - 1:
				events.push_front(e)
				next_event = clock + 4.0
				continue
			await _event(e, stand, look)
			next_event = clock + g._rng.randf_range(10.0, 16.0)
	if not alive():
		_out()
		return
	_drop_fork()
	await g.man_say("MAN_D_GOOD", 2.4)
	g.ui.hint_hold("HINT_NOD")
	var ans: String = await g.wait_gesture(8.0)
	g.ui.hint_clear()
	if ans == "shake":
		await g.man_say("MAN_D_GOOD_SHAKE", 3.0)
		g.state.add_suspicion(5.0, "TELL_REFUSE")
	else:
		await g.man_say("MAN_D_GOOD_NOD", 2.6)
	g.state.evidence["ate"] = true
	_out()


func _out() -> void:
	_drop_fork()
	g.scares.busy = maxi(0, g.scares.busy - 1)


# ---- eating: hold the left button to lift the fork, let go to swallow ----
func _eat(dt: float) -> void:
	if _fork == null:
		return
	var down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or bool(g.get_meta("bot_eat", false))
	if down:
		_held += dt
		_idle = 0.0
		if _held > 0.45 and not _chewing:
			_chewing = true
			g._sfx("res://assets/audio/chew_%d.ogg" % g._rng.randi_range(1, 3), -4.0)
			if bites + 1 == _ring_bite:
				_ring()
	elif _held > 0.0:
		if _chewing and _held > 0.9:
			bites += 1
			g._sfx("res://assets/audio/swallow.ogg", -6.0)
			g.player.heartbeat_kick(0.15)
		_held = 0.0
		_chewing = false
		if is_instance_valid(_morsel):
			_morsel.visible = true
	var k := clampf(_held / 0.45, 0.0, 1.0)
	_fork.position = Vector3(0.05, -0.36, -0.5).lerp(Vector3(0.0, -0.08, -0.2), k * k * (3.0 - 2.0 * k))
	_fork.rotation.x = lerpf(-0.2, 0.9, k)
	if _chewing and is_instance_valid(_morsel):
		_morsel.visible = false


func _ring() -> void:
	# something hard between the teeth: her wedding ring
	g.think("THINK_RING", 3.5)
	g.state.composure(4.0, 0.8)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.008
	tm.outer_radius = 0.0105
	ring.mesh = tm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.72, 0.36)
	gold.metallic = 1.0
	gold.roughness = 0.2
	ring.material_override = gold
	ring.position = Vector3(0.0, 0.012, -0.11)
	ring.rotation.x = PI * 0.5
	_fork.add_child(ring)
	g.state.evidence["ring"] = true
	g.get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if alive():
			g.man_say("MAN_D_RING", 2.8))


func _make_fork() -> void:
	_fork = Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.73, 0.75)
	steel.metallic = 1.0
	steel.roughness = 0.22
	var shaft := MeshInstance3D.new()
	shaft.mesh = MeshUtil.rounded_box(Vector3(0.012, 0.004, 0.17), 0.0018)
	shaft.material_override = steel
	shaft.position = Vector3(0.0, 0.0, 0.03)
	_fork.add_child(shaft)
	for i in 4:
		var tine := MeshInstance3D.new()
		tine.mesh = MeshUtil.rounded_box(Vector3(0.0022, 0.0022, 0.045), 0.0009)
		tine.material_override = steel
		tine.position = Vector3(-0.0075 + 0.005 * i, 0.0, -0.075)
		_fork.add_child(tine)
	_morsel = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.026
	_morsel.mesh = sm
	_morsel.material_override = g.meat_material()
	_morsel.position = Vector3(0.0, 0.012, -0.09)
	_fork.add_child(_morsel)
	hold(_fork, Vector3(0.05, -0.36, -0.5))


func _drop_fork() -> void:
	if _fork != null:
		drop_held()
		_fork = null


# ---- what happens at the table ----
func _event(e: String, stand: Vector3, look: Vector3) -> void:
	g._tr("dinner " + e)
	match e:
		"story":
			await g.man_say("MAN_D_STORY_1", 3.6)
			await g.man_say("MAN_D_STORY_2", 3.6)
			await g.man_say("MAN_D_STORY_3", 3.2)
		"eyes":
			# her eyes are open. Her mouth moves. Only you see it.
			g.head.retexture("womang")
			g._sfx3d("res://assets/audio/voice/whisper_en_%d.ogg" % g._rng.randi_range(1, 10), stand, 0.0, 1.0)
			g.ui.say("SPK_HER", "HER_DONT_EAT", 3.0)
			g.scares.hit(0.7, true, "quiet")
			await wait(3.2)
			g.head.retexture("womanc")
		"ankle":
			# a cold hand round your ankle under the cloth
			g._sfx("res://assets/audio/breath_near.ogg", -2.0)
			g.player.heartbeat_kick(0.7)
			await wait(0.5)
			g.player.look_toward(g.player.eye_pos() + g.player.aim_dir() * 0.6 + Vector3(0.0, -0.9, 0.0), 0.25)
			await wait(0.9)
			g.player.look_toward(look, 0.4)
			await wait(0.5)
			await g.scares.pop("under", false)
		"wine":
			g._sfx3d("res://assets/audio/wine_pour.ogg", spot("wine_glass", look), -2.0, 2.0)
			await g.man_say("MAN_D_WINE", 2.4)
			g.ui.hint("HINT_DRINK", 5.0)
			var held := 0.0
			var tt := 0.0
			while alive() and tt < 9.0 and held < 1.0:
				await g.get_tree().process_frame
				var dt: float = g.get_process_delta_time()
				tt += dt
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or g.get_meta("bot_eat", false):
					held += dt
			if held >= 1.0:
				g._sfx("res://assets/audio/swallow.ogg", -4.0)
				g.think("THINK_WINE", 3.0)
				g.state.composure(3.0, 0.5)
			else:
				g.state.add_suspicion(6.0, "TELL_REFUSE")
		"dessert":
			await g.man_say("MAN_D_DESSERT", 2.2)
			g.man.set_pose("stand", 0.5)
			await wait(0.6)
			g.man_walk(spot("stove", Vector3(-7.6, 0.0, 8.6)))
			# alone with her. The candles lean. Her head turns to you.
			var t := 0.0
			var y0: float = g.head.global_rotation.y
			while alive() and t < 16.0:
				await wait(0.1)
				t += 0.1
				g.head.global_rotation.y = lerp_angle(y0, y0 + 0.35, smoothstep(4.0, 12.0, t))
				if t > 8.0 and t < 8.15:
					g.dinner_candles_gutter()
			await g.man_walk(spot("his_seat", Vector3(-9.05, 0.0, 2.0)) + Vector3(0.6, 0.0, 0.4), g.player.global_position)
			g.serve_dessert(spot("plate", look))
			await g.man_say("MAN_D_EYES", 3.2)
			g.state.visual("dessert", spot("plate", look), 4.0, 1.0)
			g.state.composure(4.0, 0.8)
			await wait(1.5)
			g.man.global_position = spot("his_seat", Vector3(-9.05, 0.0, 2.0))
			g.man.set_pose("sit", 0.6)
