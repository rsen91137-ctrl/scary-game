class_name ActNeighbour
extends Act
## A knock at the front door, past eleven. The old woman from downstairs:
## something is coming through her ceiling, and it is red. He takes you to
## the door with him - "stand here, and smile" - and she asks you, the blind
## piano man, whether everything is all right.

func run() -> void:
	var door := Vector3(0.0, 1.2, 0.1)
	g._tr("neighbour")
	g.scares.busy += 1
	g._sfx3d("res://assets/audio/bang_1.ogg", door, 2.0, 5.0)
	g.player.heartbeat_kick(0.6)
	await wait(1.4)
	if not alive():
		_done()
		return
	await g.man_say("MAN_N_1", 2.4)
	if not alive():
		_done()
		return
	g._sfx3d("res://assets/audio/bang_2.ogg", door, 3.0, 5.0)
	# he takes you by the arm into the hall
	g.ui.fade_to(1.0, 0.5)
	await wait(0.6)
	g.player.global_position = Vector3(0.15, 0.03, 1.9)
	g.player.set_mode("still", 0.0)
	g.player.yaw = 0.0
	g.player.pitch = -0.05
	g.player.snap_eye()
	g.man.stop()
	g.man.set_pose("stand", 0.0)
	g.man.global_position = Vector3(-0.15, 0.0, 0.75)
	g.man.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP, true)
	g.man.look_node = null
	g.ui.fade_to(0.0, 0.6)
	await wait(0.7)
	# the chain stays on; the stairwell light through the gap
	var hinge: Node3D = g.flat.doors.get("front")
	var shut := hinge.rotation.y if hinge else 0.0
	if hinge:
		g.create_tween().tween_property(hinge, "rotation:y", shut + 0.32, 0.6)
	g._sfx3d("res://assets/audio/door_creak.ogg", door, -6.0)
	var gap := OmniLight3D.new()
	gap.light_color = Color(0.85, 0.9, 1.0)
	gap.light_energy = 1.2
	gap.omni_range = 2.5
	g.add_child(gap)
	gap.global_position = Vector3(0.3, 1.6, -0.4)
	await wait(0.8)
	await _her("NB_1", 4.0)
	await g.man_say("MAN_N_2", 3.4)
	await _her("NB_2", 4.2)
	if not alive():
		gap.queue_free()
		_done()
		return
	# she is asking you
	g.ui.hint_hold("HINT_NEIGHBOUR")
	var ans: String = await g.wait_gesture(9.0)
	g.ui.hint_clear()
	if ans == "shake":
		await _her("NB_3B", 3.6)
		g.police_called = true
		g.neighbour_knows = true
	else:
		if ans == "":
			await g.man_say("MAN_N_SHY", 2.4)
		await _her("NB_3A", 2.6)
	if hinge:
		g.create_tween().tween_property(hinge, "rotation:y", shut, 0.4)
	g._sfx3d("res://assets/audio/door_slam.ogg", door, -8.0)
	g._sfx3d("res://assets/audio/key_lock.ogg", door, -4.0, 2.0)
	gap.queue_free()
	await wait(0.8)
	if ans == "shake" and alive():
		# he turns round, slowly
		g.man.look_node = g.player.head
		g.man.turn_to(g.player.global_position)
		await wait(1.0)
		g.state.add_suspicion(26.0, "TELL_BETRAY")
		await g.man_say("MAN_N_WHY", 3.0)
	_done()


func _her(key: String, secs: float) -> void:
	var v := AudioStreamPlayer3D.new()
	v.bus = "Voice"
	v.stream = load("res://assets/audio/voice/murmur_%d.ogg" % g._rng.randi_range(1, 4))
	v.pitch_scale = 1.25
	v.unit_size = 3.0
	g.add_child(v)
	v.global_position = Vector3(0.25, 1.5, -0.5)
	v.play()
	g.ui.say("SPK_NEIGHBOUR", key, secs)
	await wait(secs)
	v.queue_free()


func _done() -> void:
	g.scares.busy = maxi(0, g.scares.busy - 1)
	if g.player.mode == "still":
		g.player.set_mode("walk", g.player.yaw)
