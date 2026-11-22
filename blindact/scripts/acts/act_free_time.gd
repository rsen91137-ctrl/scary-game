class_name ActFreeTime
extends Act
## He leaves you alone for a while: "excuse me" (the WC), "I'll take the
## rubbish down" (out of the flat), or the telephone. Find what proves what
## he did, or sit still and wait: both are allowed. When he comes back he
## wants you where he left you.

const LEAD := 14.0          # the warning before he is back (a flush, keys)


func run(kind: String, secs: float, items: Array) -> void:
	var st: NightState = g.state
	if st.suspicion >= st.max_suspicion() * 0.5 or st.exposed_flag:
		await g.man_say("MAN_STAY", 2.6)
		return
	var bench: Vector3 = g.flat.spots.piano_seat
	g._tr("free time " + kind)
	if g.player.global_position.distance_to(bench) > 1.4:
		# he takes you back to the piano first
		g.ui.fade_to(1.0, 0.5)
		await wait(0.6)
		g._sit_at_piano()
		g.man.stop()
		g.man.global_position = g.flat.spots.armchair + Vector3(0.4, 0.0, -0.3)
		g.man.set_pose("stand", 0.0)
		g.ui.fade_to(0.0, 0.6)
		await wait(0.6)
	match kind:
		"wc":
			await g.man_say("MAN_WC", 2.4)
			if not alive():
				return
			await g.man_walk(spot("wc_stand", Vector3(-1.6, 0.0, 5.4)))
			if not alive():
				return
			# the WC door shuts; he can hear you through it, not see you
			_wc_door(false)
			g.man.visible = false
			g.hearing_offstage = true
		"bags":
			await g.man_say("MAN_BAGS", 3.2)
			if not alive():
				return
			await g.man_walk(spot("front_inside", Vector3(0.0, 0.0, 0.7)))
			g._sfx3d("res://assets/audio/door_creak.ogg", Vector3(0.0, 1.2, 0.1), -6.0)
			await wait(0.8)
			g.man.visible = false
			g._sfx3d("res://assets/audio/door_slam.ogg", Vector3(0.0, 1.2, 0.1), -10.0)
			await wait(0.6)
			g._sfx3d("res://assets/audio/key_lock.ogg", Vector3(0.0, 1.0, 0.1), -2.0, 2.0)
			g.front_locked = true
		"night":
			pass
	if not alive():
		return
	# alone
	if g.player.mode == "seated":
		g._stand_up()
	g.free_time = true
	g.ui.objective("OBJ_FREE")
	g.hint_once("HINT_FREE_" + kind.to_upper(), 10.0)
	g.ui.hint("HINT_FREE", 9.0)
	var t := secs
	var warned := false
	var early: bool = kind == "wc" and g._rng.randf() < 0.25
	var early_at: float = secs * g._rng.randf_range(0.35, 0.55)
	var wc_noise := 4.0
	while alive() and t > 0.0:
		await wait(0.2)
		t -= 0.2
		g.show_evidence(items)
		g.ui.countdown(t)
		if kind == "wc":
			wc_noise -= 0.2
			if wc_noise <= 0.0:
				wc_noise = g._rng.randf_range(6.0, 12.0)
				var noises := ["newspaper", "cough_man", "zipper"]
				g._sfx3d("res://assets/audio/%s.ogg" % noises[g._rng.randi() % noises.size()], spot("wc_stand", Vector3(-1.6, 1.2, 5.4)) + Vector3(0, 1.2, 0), -4.0, 2.5)
			if early and t < secs - early_at:
				# he forgot something; the lock clicks and he is coming out
				early = false
				g._sfx3d("res://assets/audio/relay_click.ogg", spot("wc_door", Vector3(-0.5, 1.2, 5.35)), -4.0, 2.0)
				t = minf(t, 4.0)
				warned = true
				g.think("THINK_BACK_EARLY", 2.5)
		if not warned and t <= LEAD:
			warned = true
			if kind == "wc":
				g._sfx3d("res://assets/audio/toilet_flush.ogg", spot("wc_stand", Vector3(-1.6, 0.6, 5.4)) + Vector3(0, 0.6, 0), 0.0, 3.0)
			elif kind == "bags":
				g._sfx3d("res://assets/audio/stair_steps_up.ogg", Vector3(0.0, 1.0, -0.6), 0.0, 4.0)
			g.think("THINK_HE_COMES", 3.0)
	g.ui.countdown(-1.0)
	if not alive():
		return
	# back
	if kind == "bags":
		g._sfx3d("res://assets/audio/keys_jingle.ogg", Vector3(0.0, 1.0, 0.0), -2.0, 2.0)
		await wait(0.8)
		g._sfx3d("res://assets/audio/key_lock.ogg", Vector3(0.0, 1.0, 0.1), -2.0, 2.0)
		await wait(0.5)
		g._sfx3d("res://assets/audio/door_creak.ogg", Vector3(0.0, 1.2, 0.1), -6.0)
		g.man.visible = true
		g.man.global_position = spot("front_inside", Vector3(0.0, 0.0, 0.7))
		g.front_locked = true
	if kind == "wc":
		_wc_door(true)
		g.man.visible = true
		g.hearing_offstage = false
	g.free_time = false
	g.ui.evidence([])
	g.ui.objective("")
	await _his_return(bench)


func _wc_door(open: bool) -> void:
	var h: Node3D = g.flat.doors.get("wc")
	if h == null:
		return
	if not h.has_meta("open_rot_v3"):
		h.set_meta("open_rot_v3", h.rotation.y)
	var shut: float = h.get_meta("base_rot", h.rotation.y)
	g.create_tween().tween_property(h, "rotation:y", float(h.get_meta("open_rot_v3")) if open else shut, 0.6)
	g._sfx3d("res://assets/audio/door_creak.ogg", h.global_position + Vector3(0, 1.0, 0), -8.0, 2.0)


## He walks back to where he left you. Where he finds you is what he learns.
func _his_return(bench: Vector3) -> void:
	var p: Player = g.player
	var at_bench := p.global_position.distance_to(bench) < 1.4
	if at_bench:
		if p.mode != "seated":
			g._sit_at_piano()
		await g.man_walk(g.flat.spots.armchair + Vector3(0.4, 0.0, -0.3), p.global_position)
		return
	# not where he left you. He comes looking.
	g.man.walk_path(g.nav_path(g.man.global_position, p.global_position), 1.5)
	await g.man_say("MAN_WHERE", 1.8)
	var t := 0.0
	while alive() and t < 25.0:
		await wait(0.2)
		t += 0.2
		var mp: Vector3 = g.man.global_position
		var pp := p.global_position
		if fmod(t, 1.0) < 0.2:
			g.man.walk_path(g.nav_path(mp, pp), 1.5)
		if mp.distance_to(pp) < 2.2 or (mp.distance_to(pp) < 5.0 and g._line_of_sight(g.man.bone_pos("head"), p.eye_pos())):
			break
	if not alive():
		return
	g.man.stop()
	var room: String = g.scares.room_at(p.global_position)
	if room == "passage" or (room == "attic" and g.found("diary")):
		g.state.expose("TELL_FOUND_HIDDEN")
		return
	if room == "study" or room == "attic" or room == "pantry":
		g.state.add_suspicion(32.0, "TELL_SNOOPING")
		await g.man_say("MAN_FOUND_SNOOP", 2.8)
	else:
		g.state.add_suspicion(10.0, "TELL_WANDERED")
		await g.man_say("MAN_FOUND_LOST", 2.6)
	if not alive():
		return
	# he takes you by the arm, back to the bench
	g.ui.fade_to(1.0, 0.6)
	await wait(0.7)
	g.man.stop()
	g._man_sit_now()
	g._sit_at_piano()
	g.ui.fade_to(0.0, 0.8)
	await wait(0.8)
