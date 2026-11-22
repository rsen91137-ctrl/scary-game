class_name ActKitchen
extends Act
## While you finish the piece he is in the kitchen: the cleaver, again and
## again. Then he calls you to make yourself useful: plates, cutlery, two
## places at the table. The kitchen is a butcher's shop and he watches you
## walk through it.

var _boil: AudioStreamPlayer3D


func run() -> void:
	if not has_spot("stove") or not g.flat.interactables.has("plates"):
		return
	var stove := spot("stove", Vector3(-7.6, 0.0, 8.6))
	g._tr("kitchen")
	await g.man_say("MAN_K_CALL", 3.0)
	if not alive():
		return
	g._stand_up()
	g.ui.objective("OBJ_KITCHEN")
	g.ui.hint("HINT_KITCHEN", 8.0)
	_loop("boil_loop", stove + Vector3(0.0, 1.0, 0.0), -6.0)
	# he is at the stove when you come in, his back to you, stirring
	g.man.stop()
	g.man.visible = true
	g.man.set_pose("stand", 0.0)
	g.man.global_position = stove
	g.man.look_at(Vector3(stove.x, 0.0, stove.z) + Vector3(-1.0, 0.0, 0.0), Vector3.UP, true)
	g.man.look_node = null
	# the cleaver, while you find your way
	var chop_t := 0.0
	while alive() and g.scares.room_at(g.player.global_position) != "kitchen":
		await wait(0.2)
		chop_t -= 0.2
		if chop_t <= 0.0:
			chop_t = g._rng.randf_range(0.6, 1.6)
			g._sfx3d("res://assets/audio/chop_%d.ogg" % g._rng.randi_range(1, 4), spot("chop_block", stove) + Vector3(0, 0.9, 0), 2.0, 4.0)
	if not alive():
		return
	g.man.look_node = g.player.head
	g.state.visual("block", spot("chop_block", stove) + Vector3(0, 0.95, 0), 4.0, 0.7)
	g.think("THINK_KITCHEN", 3.5)
	await g.man_say("MAN_K_PLATES", 3.2)
	if not alive():
		return
	# the fridge, on your way past it
	_fridge_scare()
	for what: String in ["plates", "cutlery"]:
		g.ui.objective("OBJ_" + what.to_upper())
		await _carry(what)
		if not alive():
			return
	_stop_loop()
	g.ui.objective("")
	await g.man_say("MAN_K_SIT", 2.4)


## Pick it up in the kitchen, lay it at the two places in the dining room.
func _carry(what: String) -> void:
	await g.wait_interact(what)
	if not alive():
		return
	g._sfx("res://assets/audio/plate_set.ogg" if what == "plates" else "res://assets/audio/cutlery_1.ogg", -6.0)
	hold(_held_mesh(what))
	var table := spot("plate", Vector3(-7.0, 0.78, 2.4))
	var a := _area("lay_" + what, "ACT_PUT", table, Vector3(1.6, 0.4, 1.2))
	await g.wait_interact("lay_" + what)
	if is_instance_valid(a):
		a.queue_free()
	drop_held()
	g._sfx3d("res://assets/audio/plate_set.ogg" if what == "plates" else "res://assets/audio/cutlery_2.ogg", table, -4.0)
	g.lay_table(what)


func _fridge_scare() -> void:
	var fridge := spot("fridge", Vector3(-9.4, 0.0, 5.3))
	var t := 0.0
	while alive() and t < 40.0:
		await wait(0.2)
		t += 0.2
		if near(fridge, 1.6):
			g._sfx3d("res://assets/audio/fridge_open.ogg", fridge + Vector3(0, 1.0, 0), 0.0, 2.5)
			await wait(0.5)
			if g.scares.busy == 0:
				await g.scares.pop("stare", false)
			return


func _area(id: String, prompt: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 2
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.set_meta("interact", prompt)
	a.set_meta("id", id)
	g.add_child(a)
	a.global_position = pos
	return a


func _held_mesh(what: String) -> Node3D:
	var n := Node3D.new()
	var china := StandardMaterial3D.new()
	china.albedo_color = Color(0.86, 0.88, 0.86)
	china.roughness = 0.2
	if what == "plates":
		for i in 3:
			var m := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.13
			cm.bottom_radius = 0.1
			cm.height = 0.018
			m.mesh = cm
			m.material_override = china
			m.position = Vector3(0, 0.02 * i, 0)
			n.add_child(m)
	else:
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.7, 0.72, 0.74)
		steel.metallic = 1.0
		steel.roughness = 0.25
		for i in 4:
			var m := MeshInstance3D.new()
			m.mesh = MeshUtil.rounded_box(Vector3(0.016, 0.004, 0.2), 0.002)
			m.material_override = steel
			m.position = Vector3(-0.03 + 0.02 * i, 0.0, 0.0)
			m.rotation.y = 0.05 * i
			n.add_child(m)
	n.rotation.x = 0.35
	return n


func _loop(name: String, pos: Vector3, vol: float) -> void:
	var path := "res://assets/audio/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	_boil = AudioStreamPlayer3D.new()
	_boil.stream = load(path)
	_boil.bus = "SFX"
	_boil.volume_db = vol
	_boil.unit_size = 3.0
	g.add_child(_boil)
	_boil.global_position = pos
	_boil.play()
	_boil.finished.connect(_boil.play)


func _stop_loop() -> void:
	if is_instance_valid(_boil):
		_boil.queue_free()
