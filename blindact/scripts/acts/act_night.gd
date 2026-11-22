class_name ActNight
extends Act
## It is late, the last bus has gone, and he will not hear of you leaving.
## The guest room is the attic. Lie still. Keep your eyes shut if you like.
## Whatever comes up the stairs, a blind man is asleep.
## (Getting up is allowed. Not being in bed when he looks in is not.)

var in_bed := false
var _bed: Vector3
var _hour := 0


func run() -> void:
	var p: Player = g.player
	g._tr("night")
	g.scares.busy += 1
	g.storm(true)
	await g.man_say("MAN_NIGHT_1", 3.4)
	await g.man_say("MAN_NIGHT_2", 2.6)
	if not alive():
		_done()
		return
	if p.mode == "seated":
		g._stand_up()
	g.ui.objective("OBJ_ATTIC")
	g.ui.hint("HINT_ATTIC", 8.0)
	var stair_top := spot("stair_top", Vector3(-2.9, 2.95, 6.2))
	var arrive := spot("attic_arrive", stair_top)
	_bed = spot("attic_bed", Vector3(-4.3, 2.95, 7.4))
	g.man.follow_height = true
	g.man_walk(arrive + Vector3(-0.6, 0.0, -0.3))
	var t := 0.0
	while alive() and g.scares.room_at(p.global_position) != "attic" and t < 90.0:
		await wait(0.25)
		t += 0.25
	if not alive():
		_done()
		return
	if g.scares.room_at(p.global_position) != "attic":
		g.ui.fade_to(1.0, 0.5)
		await wait(0.6)
		p.global_position = arrive + Vector3(0, 0.05, 0)
		g.ui.fade_to(0.0, 0.6)
	# rain on the roof, a hand's breadth over your head
	var rain := "res://assets/audio/roof_rain_loop.ogg"
	if ResourceLoader.exists(rain):
		g.amb.stream = load(rain)
		g.amb.volume_db = -6.0
		g.amb.play()
	await g.man_say("MAN_NIGHT_BED", 2.6)
	g.ui.objective("OBJ_BED")
	g.ui.hint("HINT_BED", 7.0)
	t = 0.0
	while alive() and not in_bed and t < 60.0:
		await wait(0.2)
		t += 0.2
		if t > 45.0:
			lie_down()
	if not alive():
		_done()
		return
	g.ui.objective("")
	await g.man_say("MAN_NIGHT_GOOD", 2.4)
	g.lamp_off("garret_lamp")
	g.man.walk_path(g.nav_path(g.man.global_position, spot("stair_bottom", Vector3(-2.9, 0.0, 10.2))), 1.0)
	await wait(4.0)
	g.man.visible = false
	g.man.stop()
	g.man.global_position = spot("stair_bottom", Vector3(-2.9, 0.0, 10.2))
	g.ui.hint("HINT_NIGHT", 9.0)
	# the hours
	var evs := ["door", "under", "foot", "knife", "pillow", "roof"]
	evs.shuffle()
	evs.erase("knife")
	evs.insert(3, "knife")
	var gap := 22.0
	for e: String in evs:
		await wait(g._rng.randf_range(gap * 0.7, gap * 1.2))
		if not alive():
			_done()
			return
		_chime()
		await _event(e)
		if not alive():
			_done()
			return
	await wait(6.0)
	# three o'clock: the telephone downstairs, then his steps on the stair
	g._sfx3d("res://assets/audio/phone_ring.ogg", Vector3(-1.0, 0.85, 3.58), -6.0, 4.0)
	await wait(3.0)
	await _he_looks_in("MAN_NIGHT_UP", false)
	_done()


func lie_down() -> void:
	if in_bed:
		return
	var p: Player = g.player
	in_bed = true
	var head := spot("attic_bed_head", _bed + Vector3(-0.7, 0.0, 0.0))
	var foot_dir := (_bed - head)
	foot_dir.y = 0.0
	var yaw := atan2(-foot_dir.x, -foot_dir.z) if foot_dir.length() > 0.05 else 0.0
	p.global_position = Vector3(head.x, _bed.y, head.z)
	p.set_mode("bed", yaw)
	p.pitch = 0.85
	p.snap_eye()
	g._sfx("res://assets/audio/bed_creak.ogg", -6.0)


func get_up() -> void:
	if not in_bed:
		return
	in_bed = false
	var p: Player = g.player
	p.global_position = _bed + Vector3(0.0, 0.05, -0.75)
	p.set_mode("walk", p.yaw)
	p.unstick()
	g._sfx("res://assets/audio/bed_creak.ogg", -8.0)


func _chime() -> void:
	_hour += 1
	for i in mini(_hour, 3):
		g.get_tree().create_timer(1.6 * i).timeout.connect(func() -> void:
			g._sfx3d("res://assets/audio/clock_chime.ogg", g.flat.spots.clock, -12.0, 6.0))


## He comes up the stairs and stands in the door with the lamp.
func _he_looks_in(line: String, quiet := true) -> void:
	var door := spot("garret_mid", _bed + Vector3(1.6, 0.0, -0.4))
	var m: CharacterRig = g.man
	m.visible = true
	m.stop()
	m.global_position = spot("stair_top", Vector3(-2.9, 2.95, 6.2))
	m.quiet = quiet
	if not quiet:
		g._sfx3d("res://assets/audio/stair_steps_up.ogg", m.global_position, -2.0, 4.0)
	m.walk_path(g.nav_path(m.global_position, door), 0.9, g.player.global_position)
	var t := 0.0
	while t < 6.0 and m.moving:
		await wait(0.2)
		t += 0.2
	m.quiet = false
	m.look_node = g.player.head
	g.state.watched = true
	if not in_bed:
		g.state.add_suspicion(38.0, "TELL_NOT_IN_BED")
	await g.man_say(line, 2.8)


func _event(e: String) -> void:
	g._tr("night " + e)
	var p: Player = g.player
	match e:
		"door":
			await _he_looks_in("MAN_NIGHT_WATCH")
			await wait(6.0)
			g.man.walk_path(g.nav_path(g.man.global_position, spot("stair_bottom", Vector3(-2.9, 0.0, 10.2))), 1.0)
			await wait(4.0)
			g.man.visible = false
		"under":
			# scratching under the bed; something breathing
			g._sfx3d("res://assets/audio/scratch.ogg", _bed + Vector3(0, 0.2, 0), 0.0, 1.5)
			await wait(2.0)
			g._sfx3d("res://assets/audio/breath_near.ogg", _bed + Vector3(0, 0.3, 0), 0.0, 1.0)
			game_phantom(_bed + Vector3(0, 0.2, 0))
			await wait(2.5)
			if g._rng.randf() < 0.6:
				await g.scares.pop("side", false)
		"foot":
			# only in the lightning: someone standing at the foot of the bed
			var foot := _bed + (_bed - spot("attic_bed_head", _bed + Vector3(-0.7, 0, 0))) * 1.4
			g.scares.ghost = g.scares.ghost_w
			for i in 3:
				g.set("_flash", 1.0)
				var at: Vector3 = foot.lerp(p.eye_pos(), 0.3 * i) + Vector3(0, 1.45 - 0.25 * i, 0)
				g.scares._show(at, p.eye_pos(), false, 0.4 + 0.2 * i)
				g.state.composure(1.4, 0.5)
				await wait(0.18)
				g.scares._hide()
				await wait(g._rng.randf_range(1.6, 2.6))
			g.set("_thunder_in", 0.4)
			await g.scares.pop("upside", false)
		"knife":
			# he comes in without a sound, and stands over you with the knife
			await _he_looks_in("MAN_NIGHT_KNIFE", true)
			var m: CharacterRig = g.man
			m.walk_path(PackedVector3Array([_bed + Vector3(0.0, 0.0, 0.55)]), 0.5, p.global_position)
			await wait(1.6)
			m.set_pose("knife_high", 0.8)
			g.knife.visible = true
			g.state.visual("knife_bed", m.bone_pos("wrist.R"), 8.0, 1.2)
			g.state.composure(8.0, 1.0)
			g.body.stress = 1.0
			await wait(8.0)
			g.knife.visible = false
			m.set_pose("stand", 0.6)
			await wait(0.6)
			m.walk_path(g.nav_path(m.global_position, spot("stair_bottom", Vector3(-2.9, 0.0, 10.2))), 1.0)
			await wait(4.0)
			m.visible = false
		"pillow":
			# turn your head: she is lying next to you
			var side := (p.aim_dir().cross(Vector3.UP)).normalized()
			var at := p.eye_pos() + side * 0.32 + Vector3(0, -0.02, 0)
			g.scares.ghost = g.scares.ghost_w
			g.scares.ghost.jaw_open = 0.2
			g.scares._show(at, p.eye_pos(), false, 0.3)
			g._sfx3d("res://assets/audio/breath_near.ogg", at, -2.0, 1.0)
			var t := 0.0
			while t < 8.0:
				await wait(0.1)
				t += 0.1
				if p.aim_dir().angle_to((at - p.eye_pos()).normalized()) < deg_to_rad(30.0):
					g.scares.ghost.jaw_open = 1.0
					g.scares.hit(1.0)
					await wait(0.7)
					break
			g.scares._hide()
		"roof":
			# footsteps across the roof, and a face at the skylight
			var sky := spot("skylight", _bed + Vector3(0.6, 2.0, -1.2))
			for i in 6:
				g._sfx3d("res://assets/audio/step_%d.ogg" % g._rng.randi_range(1, 8), sky + Vector3(-1.5 + 0.5 * i, 0.4, 0), 0.0, 3.0)
				await wait(0.6)
			g.set("_flash", 1.0)
			g.scares.ghost = g.scares.ghost_w
			g.scares._show(sky + Vector3(0, 0.25, 0), p.eye_pos(), true, 0.6)
			g.scares.hit(0.85)
			await wait(0.35)
			g.scares._hide()


func game_phantom(pos: Vector3) -> void:
	g.state.phantom(pos, 2.5)
	g.state.composure(2.5, 0.5)


func _done() -> void:
	g.scares.busy = maxi(0, g.scares.busy - 1)
	g.scares._hide()
	g.amb.stream = load("res://assets/audio/amb_flat.ogg")
	g.amb.volume_db = -8.0
	g.amb.play()
