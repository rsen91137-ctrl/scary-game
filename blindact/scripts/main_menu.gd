extends Node3D
## Main menu director. Night, rain, the stairwell of a rotting block of
## flats. A "blind" man climbs it with his cane, floor after floor; every tap
## clicks on a sensor bulb that leaves him in the dark again a few seconds
## later. Through dark glasses everything is dim. Lightning, doors, voices
## behind doors, lights that will not stay on. 开始游戏 / 设置 float over it.

const PREGAME_SCENE := "res://scenes/pregame.tscn"

var stairs: StairBuilder
var world: InteriorEnv
var walker: StairWalker
var body: BodySounds
var ui: MenuUI
var post_mat: ShaderMaterial
var whispers: WhisperPlayer
var ambience: AudioStreamPlayer
var step_player: AudioStreamPlayer3D
var cane_player: AudioStreamPlayer3D
var step_streams: Array[AudioStream] = []
var cane_streams: Array[AudioStream] = []

var fade := 1.0
var fade_target := 0.0
var fade_speed := 0.35
var flash := 0.0
var _floor_seeds: Array[int] = [1000, 1001, 1002]
var _floor_nums: Array[String] = ["3", "4", "5"]
var _number := 5
var _event_timer := 12.0
var _thunder_queue := -1.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _capture := false
var _starting := false


func _ready() -> void:
	_rng.randomize()
	_capture = OS.get_cmdline_user_args().has("--capture")
	stairs = StairBuilder.new()
	stairs.name = "Stairs"
	add_child(stairs)
	stairs.build()
	for k in 3:
		stairs.configure(k, _floor_seeds[k], _floor_nums[k])
	world = InteriorEnv.new()
	add_child(world)
	world.setup(self)

	walker = StairWalker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.tapped.connect(_on_tap)
	walker.stepped.connect(_on_step)
	walker.lap_done.connect(_on_lap)
	stairs.place_moon(0)

	body = BodySounds.new()
	body.walker = walker
	body.stress = 0.28
	add_child(body)
	whispers = WhisperPlayer.new()
	add_child(whispers)

	ambience = AudioStreamPlayer.new()
	ambience.bus = "Ambience"
	ambience.stream = _stream("res://assets/audio/amb_stair.ogg")
	ambience.volume_db = -4.0
	add_child(ambience)
	ambience.play()
	step_player = AudioStreamPlayer3D.new()
	step_player.bus = "SFX"
	step_player.unit_size = 3.0
	add_child(step_player)
	cane_player = AudioStreamPlayer3D.new()
	cane_player.bus = "SFX"
	cane_player.unit_size = 3.0
	add_child(cane_player)
	for i in range(1, 9):
		var s := _stream("res://assets/audio/step_%d.ogg" % i)
		if s:
			step_streams.append(s)
	for i in range(1, 5):
		var s2 := _stream("res://assets/audio/cane_tap_%d.ogg" % i)
		if s2:
			cane_streams.append(s2)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/screen_fx.gdshader")
	post_mat.set_shader_parameter("cold", 1.0)
	rect.material = post_mat
	layer.add_child(rect)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	ui = MenuUI.new()
	ui_layer.add_child(ui)
	ui.start_requested.connect(_on_start)
	ui.quit_requested.connect(func() -> void: get_tree().quit())
	Settings.changed.connect(_apply_settings)
	_apply_settings()

	fade = 0.0 if _capture else 1.0
	fade_target = 0.0
	fade_speed = 0.3
	ui.show_menu(0.0 if _capture else 2.4)
	if _capture:
		ui.snap_visible()
		_dev_flags()
		add_child(load("res://scripts/dev_capture.gd").new())


func _stream(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func _sfx3d(path: String, pos: Vector3, vol := 0.0, unit := 4.0) -> void:
	var s := _stream(path)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = s
	p.volume_db = vol
	p.unit_size = unit
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _sfx(path: String, vol := 0.0, bus := "SFX") -> void:
	var s := _stream(path)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = s
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _apply_settings() -> void:
	world.apply_settings()
	walker.shake_scale = Settings.shake
	post_mat.set_shader_parameter("grain", 0.055 if Settings.film_grain else 0.0)
	post_mat.set_shader_parameter("brightness", lerpf(1.0, Settings.brightness, 0.5))


func _dev_flags() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--settings"):
			get_tree().create_timer(0.3).timeout.connect(func() -> void: ui.call("_on_settings"))
		elif a.begins_with("--s="):
			walker.set("_s", float(a.substr(4)))
		elif a.begins_with("--lights"):
			for L: SensorLight in stairs.lights:
				L.trigger()
		elif a.begins_with("--noui"):
			ui.visible = false
		elif a.begins_with("--nopuddle"):
			for f: Node3D in stairs.floors:
				for c in f.get_children():
					if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh:
						(c as MeshInstance3D).visible = false
		elif a.begins_with("--lightning"):
			_lightning()


# ---------------------------------------------------------------------------
# the climb
# ---------------------------------------------------------------------------
func _light_near(pos: Vector3, radius := 3.6) -> void:
	for L: SensorLight in stairs.lights:
		if L.global_position.distance_to(pos) < radius:
			L.trigger()


func _on_tap(pos: Vector3) -> void:
	if not cane_streams.is_empty():
		cane_player.stream = cane_streams[_rng.randi() % cane_streams.size()]
		cane_player.pitch_scale = _rng.randf_range(0.93, 1.07)
		cane_player.volume_db = _rng.randf_range(-6.0, -3.0)
		cane_player.global_position = pos
		cane_player.play()
	_light_near(pos)


func _on_step(pos: Vector3) -> void:
	if not step_streams.is_empty():
		step_player.stream = step_streams[_rng.randi() % step_streams.size()]
		step_player.pitch_scale = _rng.randf_range(0.85, 0.95)
		step_player.volume_db = _rng.randf_range(-11.0, -8.0)
		step_player.global_position = pos
		step_player.play()
	_light_near(pos, 2.6)


func _on_lap() -> void:
	# moved down one floor: floor 0 becomes what floor 1 was, and so on
	for li in 4:
		var src: SensorLight = stairs.lights[li + 2]
		var dst: SensorLight = stairs.lights[li]
		dst.level = src.level
		dst.set("_target", src.get("_target"))
		dst.set("_timer", src.get("_timer"))
	_floor_seeds = [_floor_seeds[1], _floor_seeds[2], _rng.randi()]
	_number += 1
	var n := str(_number)
	if _rng.randf() < 0.22:
		n = _floor_nums[1]                       # the same floor again
	elif _rng.randf() < 0.08:
		n = "13"
	if _number > 9:
		_number = 3
		n = "3"
	_floor_nums = [_floor_nums[1], _floor_nums[2], n]
	for k in 3:
		stairs.configure(k, _floor_seeds[k], _floor_nums[k])
	stairs.place_moon(0)
	walker.position.y -= StairBuilder.H


# ---------------------------------------------------------------------------
# events
# ---------------------------------------------------------------------------
func _lightning() -> void:
	flash = 1.0
	_thunder_queue = _rng.randf_range(0.6, 2.8)


func _random_event() -> void:
	var roll := _rng.randi() % 6
	match roll:
		0, 1:
			_lightning()
		2:   # a door upstairs slams; the lights up there come on by themselves
			_sfx3d("res://assets/audio/door_slam.ogg", walker.global_position + Vector3(0, 4.5, 1.0), 2.0, 8.0)
			for L: SensorLight in stairs.lights:
				if L.global_position.y > walker.global_position.y + 1.5:
					L.trigger()
			walker.look_target = Vector2(0.0, 0.45)
			body.stress = 0.5
		3:   # a door on this floor creaks open onto blackness
			var f := stairs.floors[1] if walker.position.y > StairBuilder.H else stairs.floors[0]
			var dn: String = ["DoorL", "DoorR"][_rng.randi() % 2]
			var hinge: Node3D = f.get_node(dn).get_node("Hinge")
			var side := -1.0 if dn == "DoorL" else 1.0
			create_tween().tween_property(hinge, "rotation:y", side * _rng.randf_range(0.25, 0.5), 2.2).set_trans(Tween.TRANS_SINE)
			_sfx3d("res://assets/audio/door_creak.ogg", hinge.global_position + Vector3(0, 1.0, 0.4), -2.0)
		4:   # someone muttering behind a door
			whispers.murmur(-12.0)
		5:   # the light gives up on him
			for L: SensorLight in stairs.lights:
				if L.level > 0.5:
					L.dying = true
					L.kill()
	_event_timer = _rng.randf_range(9.0, 20.0)


func _on_start() -> void:
	if _starting:
		return
	_starting = true
	fade_target = 1.0
	fade_speed = 0.9
	walker.paused = true
	await get_tree().create_timer(1.3).timeout
	get_tree().change_scene_to_file(PREGAME_SCENE)


func _process(delta: float) -> void:
	_t += delta
	fade = move_toward(fade, fade_target, delta * fade_speed)
	walker.breath = body.breath_value
	body.stress = move_toward(body.stress, 0.28, delta * 0.03)
	_event_timer -= delta
	if _event_timer <= 0.0 and not _capture:
		_random_event()
	if _thunder_queue > 0.0:
		_thunder_queue -= delta
		if _thunder_queue <= 0.0:
			_sfx("res://assets/audio/thunder_%d.ogg" % _rng.randi_range(1, 2), -2.0, "Ambience")
			# thunder is a noise too: every sensor in the shaft clicks on
			for L: SensorLight in stairs.lights:
				if absf(L.global_position.y - walker.global_position.y) < 3.0:
					L.trigger()
	flash = maxf(0.0, flash - delta * 2.2)
	var fl := flash * (0.6 + 0.4 * sin(_t * 60.0)) if flash > 0.3 else flash
	stairs.window_mat.set_shader_parameter("flash", fl)
	stairs.window_mat.set_shader_parameter("time_s", _t)
	for pm: ShaderMaterial in stairs.puddles:
		pm.set_shader_parameter("time_s", _t)
	stairs.moon.light_energy = 2.2 + fl * 30.0
	# the menu reacts to the light: darker title when the bulbs are off
	var lit := 0.0
	for L: SensorLight in stairs.lights:
		lit = maxf(lit, L.level)
	ui.flicker = clampf(0.35 + lit * 0.65 + fl, 0.0, 1.0)
	ui.heart_pulse = body.pulse
	post_mat.set_shader_parameter("sunglasses", 0.62)
	post_mat.set_shader_parameter("vignette", 0.6)
	post_mat.set_shader_parameter("pulse", body.pulse * 0.4)
	post_mat.set_shader_parameter("fade", fade)
	post_mat.set_shader_parameter("time_s", _t)
