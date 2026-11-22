class_name ActPhoto
extends Act
## "One photograph before bed. For the papers." He fetches her from the bath
## and sits her on the bench beside you, puts the lights out and fires the
## flash. A blind man does not blink at a flash. Between the flashes it is
## black, and every flash she is somewhere else.

var _cam_node: Node3D
var _flash: OmniLight3D


func run() -> void:
	var p: Player = g.player
	g._tr("photograph")
	g.scares.busy += 1
	await g.man_say("MAN_P_1", 3.4)
	if not alive():
		_done()
		return
	g.ui.fade_to(1.0, 0.6)
	await wait(0.7)
	g._sit_at_piano()
	var bench: Vector3 = g.flat.spots.piano_seat
	var fwd := Vector3(g.flat.spots.piano_view).normalized()
	var left := Vector3.UP.cross(fwd).normalized()
	# her, beside you on the bench, slumped against your shoulder
	var w: CharacterRig = g.woman
	w.visible = true
	w.undead = false
	w.look_node = null
	w.set_pose("sit", 0.0)
	w.rotation = Vector3.ZERO
	w.global_position = bench + left * 0.48 + Vector3(0.0, 0.0, 0.0)
	w.look_at(w.global_position + fwd, Vector3.UP, true)
	w.jaw_open = 0.3
	_make_camera(bench - fwd * 2.2 + left * 0.4)
	g.man.stop()
	g.man.global_position = bench - fwd * 2.6 + left * 0.1
	g.man.look_at(Vector3(bench.x, 0.0, bench.z), Vector3.UP, true)
	g.man.set_pose("stand", 0.0)
	g.man.look_node = p.head
	g.ui.fade_to(0.0, 0.6)
	await wait(0.8)
	g.state.visual("photo_her", w.bone_pos("head"), 4.0, 0.8)
	await g.man_say("MAN_P_2", 3.0)
	if not alive():
		_done()
		return
	g.scares.lights(false)
	await g.man_say("MAN_P_COUNT", 2.6)
	# four flashes
	for i in 4:
		if not alive():
			break
		match i:
			1:
				w.undead = true
				w.look_node = p.head
				w.jaw_open = 1.0
				w.lid_wide = 1.0
			2:
				w.visible = false
		_fire()
		g.state.composure(1.6, 0.6)
		g.state.watched = true
		if i == 3:
			await g.scares.pop("pop", false)
		await wait(g._rng.randf_range(1.8, 2.8))
		g._sfx3d("res://assets/audio/camera_wind.ogg", _cam_node.global_position, -6.0, 2.0)
	g.scares.lights(true)
	w.visible = true
	w.undead = false
	w.look_node = null
	w.jaw_open = 0.3
	w.lid_wide = 0.6
	g.state.add_frame(20.0, "FRAME_PHOTO")
	await g.man_say("MAN_P_3", 3.0)
	# her back to the bath
	g.ui.fade_to(1.0, 0.6)
	await wait(0.7)
	g._corpse_to_tub()
	w.set_pose("lie", 0.0)
	if is_instance_valid(_cam_node):
		_cam_node.queue_free()
	g.ui.fade_to(0.0, 0.6)
	_done()


func _fire() -> void:
	g._sfx3d("res://assets/audio/camera_flash.ogg", _cam_node.global_position, 0.0, 3.0)
	_flash.light_energy = 9.0
	g.scares.flash_frame(0.7)
	var tw: Tween = g.create_tween()
	tw.tween_property(_flash, "light_energy", 0.0, 0.18)


func _make_camera(at: Vector3) -> void:
	_cam_node = Node3D.new()
	g.add_child(_cam_node)
	_cam_node.global_position = at
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.045)
	dark.roughness = 0.5
	for k in 3:
		var leg := MeshInstance3D.new()
		leg.mesh = MeshUtil.tube(PackedVector3Array([Vector3.ZERO, Vector3(cos(k * 2.09) * 0.32, -1.4, sin(k * 2.09) * 0.32)]), PackedFloat32Array([0.012, 0.009]), 6)
		leg.material_override = dark
		leg.position = Vector3(0, 1.4, 0)
		_cam_node.add_child(leg)
	var body := MeshInstance3D.new()
	body.mesh = MeshUtil.rounded_box(Vector3(0.16, 0.11, 0.09), 0.01)
	body.material_override = dark
	body.position = Vector3(0, 1.48, 0)
	_cam_node.add_child(body)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.95, 0.97, 1.0)
	_flash.light_energy = 0.0
	_flash.omni_range = 6.0
	_flash.shadow_enabled = true
	_flash.position = Vector3(0, 1.62, 0)
	_cam_node.add_child(_flash)


func _done() -> void:
	g.scares.busy = maxi(0, g.scares.busy - 1)
	g.scares.lights(true)
