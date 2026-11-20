extends Node3D
## The night. Three acts in one scene:
##   home    his room: the landline rings; a woman's voice; two taps on the
##           receiver for "yes"; dark glasses, white cane, out of the door
##   stairs  the stairwell from the menu, climbed by the player; her door
##           on the fourth floor; a man opens it
##   flat    the piano, his tests (that are also frame-ups), the bathroom,
##           the evidence, the bait, the duet with the dead, midnight
## If he realises you can see: the chase (hide, don't make a sound, get out).
## Hints come only when something is first needed.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

var flat: FlatBuilder
var stairs: StairBuilder
var world: InteriorEnv
var player: Player
var ui: GameUI
var piano_ui: PianoGame
var piano: PianoPlayer
var body: BodySounds
var mic: MicMonitor
var state: NightState
var man: CharacterRig
var woman: CharacterRig
var knife: Node3D
var wire: Node3D
var post_mat: ShaderMaterial
var amb: AudioStreamPlayer
var chase_music: AudioStreamPlayer
var man_voice: AudioStreamPlayer3D
var phone_voice: AudioStreamPlayer
var ring_player: AudioStreamPlayer3D
var clock_player: AudioStreamPlayer3D

var act := ""
var sunglasses := 0.0
var sunglasses_target := 0.0
var adrenaline := 0.0
var red_flash := 0.0
var recording := false
var has_recorder := false
var recorder_spot := ""
var wire_taken := false
var blood_tapped := false
var in_blood := false
var hidden_in := ""
var chase_mode := ""
var man_speed := 1.0
var _gen := 0
var _hints := {}
var _t := 0.0
var _clicks := 0
var _last_noise := -99.0
var _clock_t := 0.0
var _rng := RandomNumberGenerator.new()
var _capture := false
var _man_path: Array[Vector3] = []
var _man_walk_phase := 0.0
var _man_moving := false
var _paused := false
var _flash := 0.0
var _next_lightning := 18.0
var _thunder_in := -1.0
var lightning: SpotLight3D
var _memory := 0.0             # 0..1 the image smears into a memory (flashback transitions)
var _flash_pos := Vector3.ZERO
var _flash_yaw := PI
var _moon_k := 0


func _ready() -> void:
	_rng.randomize()
	_capture = OS.get_cmdline_user_args().has("--capture")
	world = InteriorEnv.new()
	add_child(world)
	world.setup(self)
	flat = FlatBuilder.new()
	flat.name = "Flat"
	add_child(flat)
	flat.build()
	stairs = StairBuilder.new()
	stairs.name = "Stairs"
	stairs.position = Vector3(0.0, 0.0, -40.0)
	add_child(stairs)
	stairs.build()
	stairs.add_colliders()
	stairs.place_moon(0)
	stairs.configure(0, 7, "2")
	stairs.configure(1, 8, "3")
	stairs.configure(2, 9, "4")
	stairs.her_floor = 2
	stairs.add_knock_target()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.collision_mask = 1 | 4
	player.interacted.connect(_on_interact)
	player.tapped.connect(_on_tap)
	player.stepped.connect(_on_step)
	mic = MicMonitor.new()
	add_child(mic)
	mic.sound_started.connect(func(_db: float) -> void: _last_noise = _t)
	state = NightState.new()
	state.player = player
	state.mic = mic
	add_child(state)
	state.exposed.connect(_on_exposed)
	body = BodySounds.new()
	body.walker = player
	body.stress = 0.25
	add_child(body)
	piano = PianoPlayer.new()
	piano.volume_db = -3.0
	add_child(piano)

	man = CharacterRig.new()
	man.name = "Man"
	add_child(man)
	man.setup("man")
	man.visible = false
	woman = CharacterRig.new()
	woman.name = "Woman"
	add_child(woman)
	woman.setup("woman")
	_make_props()

	_setup_audio()
	_setup_ui()
	# lightning through the living room window
	lightning = SpotLight3D.new()
	lightning.light_color = Color(0.7, 0.78, 1.0)
	lightning.spot_range = 12.0
	lightning.spot_angle = 55.0
	lightning.light_energy = 0.0
	lightning.shadow_enabled = true
	lightning.position = Vector3(-3.2, 2.6, 6.0)
	add_child(lightning)
	lightning.look_at(Vector3(-3.4, 0.5, 1.5), Vector3.UP)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	if not _capture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var start := "climb"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--act="):
			start = a.substr(6)
	if _capture:
		add_child(load("res://scripts/dev_capture.gd").new())
		_dev_place()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay"):
			add_child(load("res://scripts/dev_autoplay.gd").new())
	match start:
		"home":
			_act_home()
		"return":
			_act_return()
		"door":
			_act_return(true)
		"flat", "piano":
			_act_flat()
		"bath":
			_dev_bath()
		"chase":
			_act_flat_quick_chase()
		_:
			_act_climb()


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
func _setup_audio() -> void:
	amb = AudioStreamPlayer.new()
	amb.bus = "Ambience"
	add_child(amb)
	chase_music = AudioStreamPlayer.new()
	chase_music.bus = "Music"
	chase_music.stream = _stream("res://assets/audio/chase_loop.ogg")
	chase_music.volume_db = -80.0
	add_child(chase_music)
	man_voice = AudioStreamPlayer3D.new()
	man_voice.bus = "Voice"
	man_voice.unit_size = 3.0
	add_child(man_voice)
	phone_voice = AudioStreamPlayer.new()
	phone_voice.bus = "Voice"
	add_child(phone_voice)
	ring_player = AudioStreamPlayer3D.new()
	ring_player.bus = "SFX"
	ring_player.unit_size = 4.0
	ring_player.stream = _stream("res://assets/audio/phone_ring.ogg")
	add_child(ring_player)
	clock_player = AudioStreamPlayer3D.new()
	clock_player.bus = "SFX"
	clock_player.unit_size = 2.0
	clock_player.stream = _stream("res://assets/audio/clock_tick.ogg")
	add_child(clock_player)


func _setup_ui() -> void:
	var fx := CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/screen_fx.gdshader")
	post_mat.set_shader_parameter("cold", 1.0)
	rect.material = post_mat
	fx.add_child(rect)
	var l := CanvasLayer.new()
	l.layer = 10
	add_child(l)
	piano_ui = PianoGame.new()
	piano_ui.piano = piano
	l.add_child(piano_ui)
	piano_ui.missed.connect(func(_lane: int) -> void: state.piano_misses += 1)
	piano_ui.stopped.connect(func() -> void: if act == "flat" and man.visible: state.add_suspicion(14.0, "TELL_STOPPED"))
	ui = GameUI.new()
	l.add_child(ui)
	ui.resume_requested.connect(func() -> void: _set_paused(false))
	ui.menu_requested.connect(_to_menu)
	ui.retry_requested.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(GAME_SCENE))
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.fade_now(1.0)


func _stream(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func _sfx3d(path: String, pos: Vector3, vol := 0.0, unit := 3.0) -> void:
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


func _sfx(path: String, vol := 0.0) -> void:
	var s := _stream(path)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = s
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _apply_settings() -> void:
	world.apply_settings()
	player.shake_scale = Settings.shake
	post_mat.set_shader_parameter("grain", 0.05 if Settings.film_grain else 0.0)
	post_mat.set_shader_parameter("brightness", lerpf(1.0, Settings.brightness, 0.5))


func _make_props() -> void:
	# his knife (kitchen knife), carried in the right hand
	knife = Node3D.new()
	var blade := MeshInstance3D.new()
	blade.mesh = MeshUtil.box(Vector3(0.03, 0.2, 0.004))
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.7, 0.7, 0.72)
	bm.metallic = 1.0
	bm.roughness = 0.15
	blade.material_override = bm
	blade.position = Vector3(0, 0.16, 0)
	knife.add_child(blade)
	var handle := MeshInstance3D.new()
	handle.mesh = MeshUtil.box(Vector3(0.025, 0.11, 0.02))
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.05, 0.04, 0.03)
	handle.material_override = hm
	knife.add_child(handle)
	knife.visible = false
	if man.skel:
		var ba := man.attach("wrist.R", knife)
		ba.name = "KnifeHand"
		knife.position = Vector3(0, 0.08, 0.02)
	# the coil of piano wire he hands you
	wire = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.052
	(wire as MeshInstance3D).mesh = tm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.4, 0.38, 0.35)
	wm.metallic = 1.0
	wm.roughness = 0.3
	(wire as MeshInstance3D).material_override = wm
	wire.visible = false
	add_child(wire)


# ---------------------------------------------------------------------------
# little async helpers (every sequence carries a generation number; when the
# night changes course — he knows — older sequences stop at the next await)
# ---------------------------------------------------------------------------
func _tr(msg: String) -> void:
	if OS.get_cmdline_user_args().has("--trace") or OS.get_cmdline_user_args().has("--autoplay"):
		print("[night] t=%.1f %s  susp=%.0f frame=%.0f  %s" % [_t, msg, state.suspicion, state.frame, state.log_lines])


func _alive(g: int) -> bool:
	return g == _gen and is_inside_tree()


func wait(secs: float) -> void:
	await get_tree().create_timer(secs, false).timeout


func think(key: String, secs := 3.5) -> void:
	ui.think(key, secs)


func hint_once(key: String, secs := 5.0) -> void:
	if _hints.has(key):
		return
	_hints[key] = true
	ui.hint(key, secs)


func man_say(key: String, secs := 3.0) -> void:
	man_voice.stream = _stream("res://assets/audio/voice/man_talk_%d.ogg" % _rng.randi_range(1, 8))
	man_voice.global_position = man.bone_pos("head")
	man_voice.pitch_scale = _rng.randf_range(0.92, 1.0)
	man_voice.play()
	ui.say("SPK_MAN", key, secs)
	await wait(secs)
	man_voice.stop()


func phone_say(key: String, secs := 3.5) -> void:
	phone_voice.stream = _stream("res://assets/audio/voice/phone_woman_%d.ogg" % _rng.randi_range(1, 6))
	phone_voice.play()
	ui.say("SPK_WOMAN", key, secs)
	await wait(secs)
	phone_voice.stop()


func wait_interact(id: String) -> void:
	while true:
		var got: String = await player.interacted
		if got == id:
			return


## Returns "nod", "shake" or "" on timeout.
func wait_gesture(timeout: float) -> String:
	player.expect_gesture = true
	var result := [""]
	var cb := func(k: String) -> void: result[0] = k
	player.gesture.connect(cb)
	var t := 0.0
	while t < timeout and result[0] == "":
		await get_tree().process_frame
		t += get_process_delta_time()
	player.gesture.disconnect(cb)
	player.expect_gesture = false
	return result[0]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and act != "end":
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()
		return
	if _paused:
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_clicks += 1
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and act != "end":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_R and has_recorder:
			recording = not recording
			ui.rec(recording)
			_sfx("res://assets/audio/rec_click.ogg", -6.0)
		if k == KEY_E and ui.get("_fake").visible:
			# the prompt was a lie
			state.expose("TELL_BAIT")


func _set_paused(on: bool) -> void:
	_paused = on
	get_tree().paused = on
	ui.show_pause(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


# ---------------------------------------------------------------------------
# ACT 1: the stairs. He climbs with his cane and his dark glasses; on the
# third floor a phone rings behind a neighbour's door and he remembers the
# call that brought him here (ACT 1b, a flashback: home, three hours
# earlier). Then the last flight, and her door.
# ---------------------------------------------------------------------------
func _enter_stairs() -> void:
	sunglasses_target = 0.8
	sunglasses = 0.8
	player.cane_enabled = true
	player.can_close_eyes = true
	amb.stream = _stream("res://assets/audio/amb_stair.ogg")
	amb.volume_db = -4.0
	amb.play()


## Wait until the player has climbed `floors_up` storeys of the stairwell.
func _climb_to(floors_up: float) -> void:
	var g := _gen
	while _alive(g) and player.global_position.y < stairs.global_position.y + StairBuilder.H * floors_up - 0.3:
		await wait(0.25)


func _act_climb() -> void:
	_gen += 1
	var g := _gen
	act = "climb"
	_enter_stairs()
	ui.fade_now(1.0)
	var start := stairs.to_global(Vector3(-0.68, 0.05, 0.4))
	player.global_position = start
	player.set_mode("walk", PI)
	player.yaw = PI
	await wait(0.8)
	ui.fade_to(0.0, 3.0)
	ui.chapter("CH_1", 2.5)
	await wait(3.2)
	if not _alive(g):
		return
	think("THINK_CLIMB_1", 3.5)
	get_tree().create_timer(6.0, false).timeout.connect(func() -> void:
		if act == "climb" and player.global_position.distance_to(start) < 0.6:
			hint_once("HINT_MOVE", 5.0))
	get_tree().create_timer(10.0, false).timeout.connect(func() -> void:
		if act == "climb":
			think("THINK_STAIRS_1", 3.5)
			hint_once("HINT_CANE", 5.0))
	await _climb_to(0.5)
	if not _alive(g):
		return
	think("THINK_CLIMB_2", 4.5)
	await _climb_to(1.0)
	if not _alive(g):
		return
	# a phone rings behind a neighbour's door; nobody answers it
	ring_player.global_position = stairs.neighbour_door(1)
	ring_player.play()
	await wait(1.6)
	think("THINK_CLIMB_3", 3.2)
	await wait(3.6)
	if not _alive(g):
		return
	think("THINK_CLIMB_4", 3.4)
	_flash_pos = player.global_position
	_flash_yaw = player.yaw
	player.set_mode("locked")
	player.face_point(stairs.neighbour_door(1), 0.4)
	# the memory takes over: the image smears, doubles, drains
	create_tween().tween_method(func(v: float) -> void: _memory = v, 0.0, 1.0, 2.8)
	await wait(2.6)
	ui.fade_to(1.0, 0.9)
	await wait(1.1)
	ring_player.stop()
	if not _alive(g):
		return
	_memory = 0.0
	_act_home()


func _act_home() -> void:
	_gen += 1
	var g := _gen
	act = "home"
	amb.stream = _stream("res://assets/audio/amb_flat.ogg")
	amb.volume_db = -8.0
	amb.play()
	player.global_position = flat.spots.home_start
	player.set_mode("walk", deg_to_rad(-140.0))
	player.cane_enabled = false
	player.set_mode("walk")
	player.can_close_eyes = false
	sunglasses_target = 0.0
	ring_player.global_position = flat.spots.home_phone
	ui.fade_now(1.0)
	await wait(0.6)
	ring_player.play()
	ui.fade_to(0.0, 2.5)
	ui.chapter("FLASH_PAST", 2.5)
	await wait(2.4)
	if not _alive(g):
		return
	think("THINK_PHONE_1", 3.0)
	var ringing := true
	_ring_loop(g)
	get_tree().create_timer(7.0, false).timeout.connect(func() -> void:
		if act == "home" and not _hints.has("picked"):
			hint_once("HINT_MOVE", 5.0))
	await wait_interact("home_phone")
	if not _alive(g):
		return
	_hints["picked"] = true
	ring_player.stop()
	_sfx("res://assets/audio/phone_click.ogg", -4.0)
	player.set_mode("locked")
	player.face_point(flat.spots.home_phone + Vector3(0, -0.2, 0), 1.0)
	await wait(1.2)
	await phone_say("CALL_1", 3.5)
	think("THINK_CALL_1", 3.2)
	await wait(3.0)
	await phone_say("CALL_2", 4.5)
	await phone_say("CALL_3", 3.5)
	hint_once("HINT_KNOCK", 6.0)
	_clicks = 0
	var tries := 0
	while _clicks < 2:
		await wait(0.3)
		tries += 1
		if tries == 40:
			await phone_say("CALL_1", 2.5)
			tries = 0
		if not _alive(g):
			return
	_sfx3d("res://assets/audio/knock.ogg", flat.spots.home_phone, -14.0, 1.0)
	await wait(1.0)
	await phone_say("CALL_4", 4.5)
	think("THINK_CALL_2", 3.0)
	await wait(3.2)
	await phone_say("CALL_5", 3.8)
	think("THINK_CALL_3", 2.6)
	await wait(2.8)
	await phone_say("CALL_6", 4.0)
	_sfx("res://assets/audio/phone_click.ogg", -4.0)
	await wait(0.6)
	_sfx("res://assets/audio/phone_dead.ogg", -14.0)
	think("THINK_CALL_4", 2.5)
	await wait(2.8)
	think("THINK_CALL_5", 3.0)
	await wait(3.3)
	think("THINK_CALL_6", 3.8)
	await wait(3.0)
	player.set_mode("walk")
	# glasses and cane, in any order
	var got := {}
	while got.size() < 2:
		var id: String = await player.interacted
		if not _alive(g):
			return
		if id == "glasses" and not got.has("glasses"):
			got["glasses"] = true
			flat.get_node("Home/Glasses").visible = false
			sunglasses_target = 0.8
		elif id == "cane" and not got.has("cane"):
			got["cane"] = true
			flat.get_node("Home/HomeCane").visible = false
			player.cane_enabled = true
			player.set_mode("walk")
	think("THINK_GLASSES", 3.5)
	player.can_close_eyes = true
	await wait_interact("home_door")
	if not _alive(g):
		return
	_sfx3d("res://assets/audio/door_creak.ogg", flat.spots.home_out, -6.0)
	ui.fade_to(1.0, 1.2)
	await wait(1.6)
	_act_return()


func _ring_loop(g: int) -> void:
	while _alive(g) and act == "home" and not _hints.has("picked"):
		if not ring_player.playing:
			ring_player.play()
		await wait(0.5)


# ---------------------------------------------------------------------------
# ACT 2: back on the stairs (now), the last flight and the door
# ---------------------------------------------------------------------------
func _act_return(at_door := false) -> void:
	_gen += 1
	var g := _gen
	act = "stairs"
	_enter_stairs()
	if at_door:
		_flash_pos = stairs.to_global(Vector3(-0.6, StairBuilder.H * stairs.her_floor + 0.05, -0.2))
		_flash_yaw = PI * 0.5
	elif _flash_pos == Vector3.ZERO:
		_flash_pos = stairs.to_global(Vector3(-0.6, StairBuilder.H + 0.05, -0.4))
	ui.fade_now(1.0)
	player.global_position = _flash_pos
	player.set_mode("walk", _flash_yaw)
	player.yaw = _flash_yaw
	player.pitch = 0.0
	_memory = 0.7
	create_tween().tween_method(func(v: float) -> void: _memory = v, 0.7, 0.0, 2.6)
	ui.fade_to(0.0, 1.8)
	if not at_door:
		ui.chapter("FLASH_NOW", 2.0)
		await wait(2.8)
		if not _alive(g):
			return
		think("THINK_CLIMB_5", 3.8)
		await _climb_to(1.5)
		if not _alive(g):
			return
		think("THINK_CLIMB_6", 3.5)
		await _climb_to(float(stairs.her_floor))
		if not _alive(g):
			return
	else:
		await wait(1.0)
	think("THINK_DOOR_0", 2.5)
	await wait_interact("her_door")
	if not _alive(g):
		return
	_sfx3d("res://assets/audio/knock.ogg", stairs.knock_pos(), -2.0)
	player.set_mode("locked")
	await wait(2.4)
	# the door opens; he is there, in the dark
	var hinge := stairs.her_hinge()
	_sfx3d("res://assets/audio/door_creak.ogg", stairs.knock_pos(), -4.0)
	create_tween().tween_property(hinge, "rotation:y", -1.25, 1.6).set_trans(Tween.TRANS_SINE)
	man.visible = true
	man.global_position = stairs.to_global(Vector3(-StairBuilder.W - 0.35, StairBuilder.H * stairs.her_floor, -1.0))
	man.look_at(Vector3(player.global_position.x, man.global_position.y, player.global_position.z), Vector3.UP, true)
	man.set_pose("stand", 0.0)
	await wait(1.8)
	# he leans in, his face at yours, staring into your eyes
	player.face_point(man.bone_pos("head"), 1.0)
	man.set_pose("lean_in", 1.2)
	create_tween().tween_property(man, "global_position", man.global_position + (player.global_position - man.global_position).normalized() * 0.45 * Vector3(1, 0, 1), 1.2)
	await wait(0.6)
	state.watched = true
	state.visual("door_face", man.bone_pos("head"), 4.0, 0.4)
	player.set_mode("seated", player.yaw)
	await wait(4.2)
	if not _alive(g):
		return
	think("THINK_DOOR_1", 3.5)
	hint_once("HINT_RULE_SEE", 6.0)
	await wait(3.0)
	man.set_pose("stand", 0.8)
	await man_say("MAN_1", 2.6)
	hint_once("HINT_NOD", 6.0)
	var gsture := await wait_gesture(8.0)
	if not _alive(g):
		return
	if gsture == "shake":
		await man_say("MAN_1", 2.0)
	await man_say("MAN_2", 3.0)
	ui.fade_to(1.0, 1.2)
	await wait(1.5)
	_act_flat()


# ---------------------------------------------------------------------------
# ACT 3: the flat
# ---------------------------------------------------------------------------
func _act_flat() -> void:
	_gen += 1
	var g := _gen
	act = "flat"
	sunglasses_target = 0.8
	sunglasses = 0.8
	amb.stream = _stream("res://assets/audio/amb_flat.ogg")
	amb.volume_db = -8.0
	amb.play()
	clock_player.global_position = flat.spots.clock
	recorder_spot = ["cabinet", "towels", "coat", "drawer"][_rng.randi() % 4]
	# her, in the bath
	woman.visible = true
	woman.set_pose("lie", 0.0)
	woman.global_position = flat.spots.tub + Vector3(0.45, 0.0, 0.0)
	woman.rotation = Vector3(-deg_to_rad(70.0), deg_to_rad(90.0), 0.0)
	# him, in the armchair behind you
	man.visible = true
	man.set_pose("sit", 0.0)
	man.global_position = flat.spots.armchair + Vector3(0, -0.42, 0)
	man.rotation = Vector3(0, deg_to_rad(-120.0) + PI, 0)
	_sit_at_piano()
	ui.fade_to(0.0, 1.5)
	await wait(2.0)
	if not _alive(g):
		return
	await man_say("MAN_3", 2.6)
	hint_once("HINT_PIANO", 6.0)
	_tr("piece 1")
	piano_ui.start(PianoGame.gymnopedie())
	state.playing_piano = true
	_piano_tests(g, piano_ui.length)
	await piano_ui.finished
	if not _alive(g):
		return
	state.playing_piano = false
	# the bathroom
	_tr("to the bathroom")
	await man_say("MAN_5", 3.4)
	player.set_mode("walk", player.yaw)
	man_stand_at(flat.spots.front_inside + Vector3(-0.2, 0.0, 1.0), Vector3(0, 0, 3.0))
	_blood_test(g)
	await _bathroom_sequence(g)
	if not _alive(g):
		return
	_tr("back to the piano")
	await man_say("MAN_8", 2.5)
	await _walk_back_to_piano(g)
	if not _alive(g):
		return
	# second piece: the string, the duet
	_sit_at_piano()
	_tr("piece 2")
	piano_ui.start(PianoGame.prelude())
	state.playing_piano = true
	_second_piece(g)
	await piano_ui.finished
	if not _alive(g):
		return
	state.playing_piano = false
	# midnight
	_sfx3d("res://assets/audio/clock_chime.ogg", flat.spots.clock, 0.0, 4.0)
	await wait(2.5)
	_tr("midnight")
	await man_say("MAN_13", 3.2)
	_stand_up()
	if woman.current == "slump":
		woman.visible = false
	await _leaving(g)


func _sit_at_piano() -> void:
	player.global_position = flat.spots.piano_seat + Vector3(0.0, 0.0, 0.0)
	player.global_position.y = 0.0
	player.set_mode("seated", deg_to_rad(90.0))
	player.head.position.y = 1.2
	player.cane_enabled = false
	player.set_mode("seated", deg_to_rad(90.0))


func _stand_up() -> void:
	player.global_position = flat.spots.piano_seat + Vector3(0.62, 0.02, 0.0)
	player.set_mode("walk", player.yaw)
	player.cane_enabled = true
	player.set_mode("walk", player.yaw)


func man_stand_at(pos: Vector3, face: Vector3) -> void:
	man.set_pose("stand", 0.6)
	man.global_position = pos
	man.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP, true)


func _man_head() -> Vector3:
	return man.bone_pos("head")


func _piano_tests(g: int, length: float) -> void:
	var pool := ["knife", "glass", "face", "money"]
	pool.shuffle()
	var times := [length * 0.28, length * 0.62]
	for i in 2:
		await wait(times[i] - (times[i - 1] if i > 0 else 0.0))
		if not _alive(g) or not piano_ui.active:
			return
		await _test(pool[i], g)


func _test(kind: String, g: int) -> void:
	match kind:
		"knife":
			# he stands beside you and slowly passes a blade in front of your eyes
			man.set_pose("stand", 0.3)
			var side := player.eye_pos() + Vector3(0.0, -1.2, 0.75)
			man.global_position = Vector3(side.x + 0.3, 0.0, side.z)
			man.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
			man.set_pose("offer", 0.6)
			knife.visible = true
			await wait(0.8)
			state.watched = true
			state.visual("knife", player.eye_pos() - player.look_dir() * -0.4, 3.5, 1.0)
			_sfx("res://assets/audio/knife_swish.ogg", -14.0)
			var tw := create_tween()
			var base := player.eye_pos() + player.look_dir() * 0.35
			var right := player.look_dir().cross(Vector3.UP).normalized()
			knife.top_level = true
			for k in 3:
				tw.tween_property(knife, "global_position", base + right * 0.18, 0.6)
				tw.tween_property(knife, "global_position", base - right * 0.18, 0.6)
			await tw.finished
			knife.top_level = false
			knife.position = Vector3(0, 0.08, 0.02)
			knife.visible = false
			if _alive(g) and not _hints.has("eyes"):
				_hints["eyes"] = true
				ui.hint("HINT_EYES", 5.0)
			man.set_pose("stand", 0.5)
			await wait(0.8)
			_man_back_to_chair()
		"glass":
			# a glass smashes behind you; a blind man would turn
			var p := man.bone_pos("head") + Vector3(0, -0.6, 0)
			_sfx3d("res://assets/audio/glass_drop.ogg", p, 2.0, 5.0)
			state.watched = true
			state.sound("glass", p, 2.4, 1.0)
			await wait(2.6)
			if _alive(g):
				hint_once("HINT_RULE_HEAR", 6.0)
		"face":
			man.set_pose("stand", 0.3)
			var fp := player.eye_pos() + player.look_dir() * 0.75
			man.global_position = Vector3(fp.x, 0.0, fp.z)
			man.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
			man.set_pose("lean_in", 1.0)
			await wait(1.0)
			state.watched = true
			state.visual("face", man.bone_pos("head"), 5.0, 1.0)
			think("THINK_FACE", 3.0)
			await wait(5.0)
			man.set_pose("stand", 0.6)
			await wait(0.6)
			_man_back_to_chair()
		"money":
			# money left by your hand without a word: a blind man can't know it's there
			var m := MeshInstance3D.new()
			m.mesh = MeshUtil.box(Vector3(0.16, 0.012, 0.07))
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.45, 0.5, 0.38)
			m.material_override = mm
			add_child(m)
			m.global_position = flat.spots.piano_seat + Vector3(-0.55, 0.8, 0.3)
			_sfx3d("res://assets/audio/money.ogg", m.global_position, -10.0)
			var a := Area3D.new()
			a.collision_layer = 2
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.3, 0.2, 0.3)
			cs.shape = bs
			a.add_child(cs)
			a.set_meta("interact", "ACT_TAKE")
			a.set_meta("id", "money")
			m.add_child(a)
			state.visual("money", m.global_position, 6.0, 0.5)
			await wait(8.0)
			m.queue_free()


func _man_back_to_chair() -> void:
	man.set_pose("sit", 0.6)
	man.global_position = flat.spots.armchair + Vector3(0, -0.42, 0)
	man.rotation = Vector3(0, deg_to_rad(-120.0) + PI, 0)


func _blood_test(g: int) -> void:
	# a pool of "water" across the hallway
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.1, 0.7)
	pool.mesh = pm
	pool.material_override = flat.get("_m").blood
	pool.position = flat.spots.blood_pool + Vector3(0, 0.006, 0)
	pool.name = "BloodPool"
	flat.add_child(pool)
	await wait(1.2)
	if not _alive(g):
		return
	await man_say("MAN_6", 2.2)
	blood_tapped = false
	var judged := false
	while _alive(g) and not judged:
		await wait(0.1)
		var p := player.global_position
		var bp: Vector3 = flat.spots.blood_pool
		var inside := absf(p.x - bp.x) < 0.55 and absf(p.z - bp.z) < 0.35
		if inside:
			judged = true
			state.add_frame(25.0, "FRAME_FOOTPRINTS")
			think("THINK_BLOOD", 2.5)
		elif p.z > bp.z + 0.5:
			judged = true
			if not blood_tapped:
				state.add_suspicion(22.0, "TELL_AVOID")


func _bathroom_sequence(g: int) -> void:
	# wait until he reaches the bathroom
	while _alive(g) and not (player.global_position.x > 0.7 and player.global_position.z > 3.4 and player.global_position.z < 5.8):
		await wait(0.2)
	if not _alive(g):
		return
	state.visual("tub", woman.bone_pos("head"), 3.0, 0.6)
	await wait(1.5)
	_tr("in the bathroom")
	think("THINK_BATH_1", 3.0)
	await wait(3.2)
	think("THINK_BATH_2", 3.0)
	# now he follows, silently, to the bathroom door
	man.visible = true
	man_stand_at(Vector3(0.0, 0.0, 4.1), player.global_position)
	var washed := false
	var t := 0.0
	while _alive(g) and t < 40.0 and not washed:
		var id: String = await player.interacted
		if id == "sink":
			washed = true
		elif id in ["cabinet", "towels", "coat", "drawer"]:
			_search(id)
		t += 1.0
	if not _alive(g):
		return
	_tr("washing")
	player.set_mode("locked")
	player.global_position = flat.spots.sink_stand
	player.face_point(Vector3(3.0, 1.55, 4.0), 1.0)
	_sfx3d("res://assets/audio/drip.ogg", Vector3(2.75, 0.9, 4.0), -4.0)
	await wait(2.0)
	if _rng.randf() < 0.65:
		await _fake_charge(g)
	if not _alive(g):
		return
	player.set_mode("walk", player.yaw)
	# a last chance to search on the way out
	var t2 := 0.0
	while _alive(g) and t2 < 6.0:
		await wait(0.25)
		t2 += 0.25
		if player.global_position.x < 0.7:
			break


func _search(id: String) -> void:
	if id == recorder_spot and not has_recorder:
		has_recorder = true
		think("THINK_RECORDER", 3.0)
		hint_once("HINT_REC", 6.0)
	else:
		think("THINK_NOTHING", 1.5)


func _fake_charge(g: int) -> void:
	# lights stutter; in the mirror, behind you, he raises the knife
	var lamp: OmniLight3D = flat.lamps.bath
	var base := lamp.light_energy
	for i in 6:
		lamp.light_energy = base * (0.1 if i % 2 == 0 else 1.0)
		await wait(0.08)
	man.visible = true
	man.global_position = player.global_position + Vector3(-1.4, 0.0, 0.0)
	man.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
	man.set_pose("knife_high", 0.3)
	knife.visible = true
	await wait(0.6)
	# everything screams RUN
	adrenaline = 1.0
	chase_music.volume_db = 0.0
	chase_music.play()
	_sfx("res://assets/audio/stinger.ogg", 0.0)
	body.stress = 1.0
	ui.fake_prompt("BAIT_GRAB" if _rng.randf() < 0.6 else "BAIT_RUN", 2.4)
	state.watched = true
	state.visual("charge", man.bone_pos("head"), 4.0, 1.4)
	var start_pos := player.global_position
	player.set_mode("walk", player.yaw)
	var tw := create_tween()
	tw.tween_property(man, "global_position", player.global_position + Vector3(-0.45, 0.0, 0.0), 1.3)
	man.set_pose("lunge", 1.0)
	var t := 0.0
	while t < 2.6 and _alive(g):
		await wait(0.1)
		t += 0.1
		if player.global_position.distance_to(start_pos) > 0.6:
			state.expose("TELL_RAN")
			return
	chase_music.stop()
	adrenaline = 0.0
	knife.visible = false
	man.set_pose("stand", 0.6)
	await wait(0.6)
	await man_say("MAN_7", 2.4)
	man.visible = true
	man_stand_at(Vector3(-1.6, 0.0, 2.0), Vector3(-3.0, 0.0, 2.0))


func _walk_back_to_piano(g: int) -> void:
	var t := 0.0
	while _alive(g) and t < 45.0:
		await wait(0.25)
		t += 0.25
		if player.global_position.distance_to(flat.spots.piano_seat) < 1.3:
			break
	ui.fade_to(1.0, 0.6)
	await wait(0.7)
	ui.fade_to(0.0, 0.8)


func _second_piece(g: int) -> void:
	var len := piano_ui.length
	await wait(len * 0.22)
	if not _alive(g) or not piano_ui.active:
		return
	# a string snaps
	_sfx3d("res://assets/audio/wire_twang.ogg", flat.spots.piano_seat + Vector3(-0.8, 1.0, 0), 0.0)
	await wait(1.2)
	man.visible = true
	man_stand_at(flat.spots.piano_seat + Vector3(0.6, 0.0, 0.7), player.global_position)
	await man_say("MAN_9", 3.0)
	man.set_pose("offer", 0.5)
	wire.visible = true
	wire.global_position = player.eye_pos() + player.look_dir() * 0.4 + Vector3(0, -0.25, 0)
	hint_once("HINT_TAKE", 6.0)
	var gs := await wait_gesture(7.0)
	wire.visible = false
	if not _alive(g):
		return
	if gs == "nod":
		wire_taken = true
		state.add_frame(40.0, "FRAME_WIRE")
		think("THINK_WIRE", 2.5)
	else:
		state.add_suspicion(8.0, "TELL_STOPPED")
	man.set_pose("stand", 0.4)
	await wait(len * 0.15)
	if not _alive(g) or not piano_ui.active:
		return
	# the duet: he brings her
	_tr("duet")
	await man_say("MAN_10", 3.0)
	man.visible = false
	_sfx3d("res://assets/audio/drag.ogg", Vector3(-0.6, 0.5, 3.5), -2.0, 4.0)
	await wait(3.5)
	woman.visible = true
	woman.rotation = Vector3(0, -PI * 0.5, 0)
	woman.global_position = flat.spots.piano_seat + Vector3(0.05, -0.44, -0.55)
	woman.set_pose("slump", 1.5)
	man.visible = true
	man_stand_at(flat.spots.piano_seat + Vector3(1.4, 0.0, 0.4), player.global_position)
	think("THINK_DUET", 3.0)
	state.watched = true
	state.visual("duet", woman.bone_pos("head"), 14.0, 1.0)
	await wait(4.0)
	if not _alive(g):
		return
	var rec_before := recording
	await man_say("MAN_11", 3.2)
	await wait(1.0)
	await man_say("MAN_12", 3.6)
	if recording or rec_before:
		state.evidence["confession"] = true


func _leaving(g: int) -> void:
	var t := 0.0
	var baited := false
	while _alive(g):
		await wait(0.2)
		t += 0.2
		var p := player.global_position
		if not baited and p.x > -0.7 and p.z < 1.0 and _rng.randf() < 0.5:
			baited = true
			await _final_bait(g)
		if p.distance_to(flat.spots.front_inside) < 0.7:
			break
	if not _alive(g):
		return
	_tr("leaving")
	await man_say("MAN_14", 2.2)
	_ending_exit()


func _final_bait(g: int) -> void:
	man.visible = true
	man.global_position = player.global_position + Vector3(0.0, 0.0, 2.8)
	man.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
	man.set_pose("lunge", 0.4)
	knife.visible = true
	adrenaline = 1.0
	chase_music.volume_db = -2.0
	chase_music.play()
	_sfx("res://assets/audio/stinger.ogg", -2.0)
	state.watched = true
	state.visual("door_charge", man.bone_pos("head"), 3.0, 1.2)
	create_tween().tween_property(man, "global_position", player.global_position + Vector3(0.0, 0.0, 0.6), 1.4)
	await wait(2.6)
	chase_music.stop()
	adrenaline = 0.0
	knife.visible = false
	man.set_pose("stand", 0.5)


func _ending_exit() -> void:
	act = "end"
	_gen += 1
	ui.fade_to(1.0, 1.5)
	await wait(1.8)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if state.evidence.get("confession", false):
		ui.show_end("END_TRUTH", "END_TRUTH_D")
	elif state.frame >= 40.0:
		ui.show_end("END_SCAPEGOAT", "END_SCAPEGOAT_D", _frame_lines())
	else:
		ui.show_end("END_SILENCE", "END_SILENCE_D")


func _frame_lines() -> String:
	var out := ""
	for l: String in state.log_lines:
		if l.begins_with("FRAME_"):
			out += "· " + tr(l) + "\n"
	return out


# ---------------------------------------------------------------------------
# he knows: the chase
# ---------------------------------------------------------------------------
func _on_exposed(reason: String) -> void:
	if act == "end" or act == "chase":
		return
	_gen += 1
	var g := _gen
	act = "chase"
	piano_ui.stop()
	state.playing_piano = false
	state.end_tests()
	ui.fake_prompt("", 0.01)
	man.visible = true
	man.set_pose("stand", 0.3)
	knife.visible = true
	player.set_mode("walk", player.yaw)
	player.cane_enabled = false
	player.speed = 2.1
	adrenaline = 0.6
	await man_say("MAN_EXPOSED", 2.0)
	if not _alive(g):
		return
	chase_music.volume_db = -3.0
	chase_music.play()
	hint_once("HINT_CHASE", 5.0)
	if man.global_position.distance_to(player.global_position) < 1.6:
		# he is right there: a moment to break away
		man.global_position = player.global_position + (man.global_position - player.global_position).normalized() * 1.8
	chase_mode = "hunt"
	_chase_loop(g)


func _act_flat_quick_chase() -> void:
	_act_flat()
	await wait(3.0)
	state.expose("TELL_FLINCH")


const ROUTE := [Vector3(-2.8, 0, 2.2), Vector3(-1.2, 0, 1.8), Vector3(0, 0, 2.0), Vector3(0, 0, 4.1), Vector3(1.6, 0, 4.4),
	Vector3(0, 0, 4.1), Vector3(0, 0, 6.0), Vector3(0, 0, 7.4), Vector3(1.3, 0, 7.5), Vector3(-0.8, 0, 8.4), Vector3(0, 0, 6.0), Vector3(0, 0, 2.0)]


func _chase_loop(g: int) -> void:
	var idx := 0
	var hunt_t := 0.0
	while _alive(g) and act == "chase":
		await get_tree().process_frame
		var dt := get_process_delta_time()
		var mp := man.global_position
		var pp := player.global_position
		var sees := hidden_in == "" and _line_of_sight(man.bone_pos("head"), player.eye_pos()) and mp.distance_to(pp) < 9.0
		var heard := _t - _last_noise < 0.6 and mp.distance_to(pp) < float(Difficulty.get_value("hearing_m"))
		var target: Vector3 = ROUTE[idx]
		var spd := 1.2 * float(Difficulty.get_value("chase_speed"))
		if sees or heard:
			target = pp
			spd = 2.4 * float(Difficulty.get_value("chase_speed"))
			hunt_t = 4.0
		elif hunt_t > 0.0:
			hunt_t -= dt
			target = pp if hidden_in == "" else target
		var d := target - mp
		d.y = 0.0
		if d.length() < 0.35 and target == ROUTE[idx]:
			idx = (idx + 1) % ROUTE.size()
			# checking a hiding place
			if hidden_in != "" and _near_hide(mp):
				var found := (_t - _last_noise < 6.0) or _rng.randf() < 0.25
				if found:
					_caught(g, "TELL_FOUND")
					return
		elif d.length() > 0.01:
			var step := d.normalized() * spd * dt
			man.global_position = mp + step
			man.look_at(man.global_position + Vector3(step.x, 0, step.z), Vector3.UP, true)
			_man_walk_phase += dt * spd * 3.0
			man.set_pose("lunge" if spd > 2.0 and sin(_man_walk_phase) > 0.0 else "stand", 0.15)
		if hidden_in == "" and mp.distance_to(pp) < 0.9:
			_caught(g, "TELL_HEARD" if heard else state.last_reason)
			return


func _he_sees_you() -> bool:
	var head := man.bone_pos("head")
	var to_p := player.eye_pos() - head
	if to_p.length() > 9.0:
		return false
	var fwd := man.global_basis.z     # the rig faces +Z
	if fwd.dot(to_p.normalized()) < 0.2:
		return false
	return _line_of_sight(head, player.eye_pos())


func _near_hide(mp: Vector3) -> bool:
	if hidden_in == "wardrobe":
		return mp.distance_to(flat.spots.wardrobe_front) < 1.0
	if hidden_in == "curtain":
		return mp.distance_to(Vector3(1.6, 0, 4.4)) < 1.0
	return false


func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


func _caught(g: int, reason: String) -> void:
	if not _alive(g):
		return
	_gen += 1
	act = "end"
	chase_mode = ""
	player.set_mode("locked")
	man.visible = true
	man.global_position = player.global_position + (man.global_position - player.global_position).normalized() * 0.7
	man.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
	man.set_pose("knife_high", 0.2)
	player.face_point(man.bone_pos("head"), 1.0)
	_sfx("res://assets/audio/stinger.ogg", 0.0)
	await wait(0.5)
	_sfx("res://assets/audio/stab.ogg", 2.0)
	red_flash = 1.0
	ui.fade_now(1.0)
	chase_music.stop()
	await wait(1.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var why := tr("WHY") + "\n" + tr(state.last_reason if state.last_reason != "" else reason)
	if reason != state.last_reason:
		why += "\n" + tr(reason)
	ui.show_end("END_DEAD", "END_DEAD_D", why, state.mic_history, mic.threshold_db())


# ---------------------------------------------------------------------------
# interaction, noises
# ---------------------------------------------------------------------------
func _on_interact(id: String) -> void:
	match id:
		"money":
			state.expose("TELL_GREED")
		"wardrobe":
			if act == "chase":
				if hidden_in == "":
					hidden_in = "wardrobe"
					player.global_position = flat.spots.wardrobe_in
					player.set_mode("hidden", deg_to_rad(90.0))
					ui.hint("ACT_LEAVE_HIDE", 3.0)
				else:
					hidden_in = ""
					player.global_position = flat.spots.wardrobe_front
					player.set_mode("walk", player.yaw)
		"window_escape":
			if act == "chase":
				_gen += 1
				act = "end"
				chase_music.stop()
				ui.fade_to(1.0, 1.0)
				await wait(1.2)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_end("END_ESCAPE", "END_ESCAPE_D")
		"front_door":
			if act == "chase":
				think("THINK_LOCKED", 1.5)
		"cabinet", "towels", "coat", "drawer":
			if act == "flat" or act == "chase":
				_search(id)
	if id == "cabinet" and act == "chase" and hidden_in == "":
		pass


func _on_tap(pos: Vector3) -> void:
	_sfx3d("res://assets/audio/cane_tap_%d.ogg" % _rng.randi_range(1, 4), pos, -6.0, 2.0)
	if act == "stairs" or act == "climb":
		for L: SensorLight in stairs.lights:
			if L.global_position.distance_to(pos) < 3.6:
				L.trigger()
	if act == "flat" and flat.spots.has("blood_pool"):
		var bp: Vector3 = flat.spots.blood_pool
		if Vector2(pos.x - bp.x, pos.z - bp.z).length() < 0.8:
			blood_tapped = true


func _on_step(pos: Vector3) -> void:
	var path := "res://assets/audio/step_%d.ogg" % _rng.randi_range(1, 8)
	_sfx3d(path, pos, -12.0 if act != "chase" else -6.0, 2.0)
	if act == "stairs" or act == "climb":
		for L: SensorLight in stairs.lights:
			if L.global_position.distance_to(pos) < 2.8:
				L.trigger()


func _dev_place() -> void:
	await wait(0.4)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pos="):
			var p := a.substr(6).split(",")
			player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			player.set_mode("locked")
		elif a.begins_with("--yaw="):
			player.yaw = deg_to_rad(float(a.substr(6)))
		elif a.begins_with("--pitch="):
			player.pitch = deg_to_rad(float(a.substr(8)))
		elif a.begins_with("--glasses="):
			sunglasses_target = float(a.substr(10))
			sunglasses = sunglasses_target
		elif a.begins_with("--man="):
			var q := a.substr(6).split(",")
			man.visible = true
			man.global_position = Vector3(float(q[0]), float(q[1]), float(q[2]))
			man.set_pose(q[3] if q.size() > 3 else "stand", 0.0)
			man.look_at(Vector3(player.global_position.x, man.global_position.y, player.global_position.z), Vector3.UP, true)
		elif a.begins_with("--fadeoff"):
			ui.fade_now(0.0)


func _dev_bath() -> void:
	_act_flat()
	await wait(1.0)
	piano_ui.stop()
	piano_ui.finished.emit()


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	body.stress = move_toward(body.stress, clampf(0.25 + state.suspicion / 140.0 + adrenaline * 0.6, 0.0, 1.0), delta * 0.3)
	player.breath = body.breath_value
	piano_ui.shake = clampf(body.stress - 0.3, 0.0, 1.0)
	adrenaline = maxf(0.0, adrenaline - delta * 0.2)
	red_flash = maxf(0.0, red_flash - delta * 1.5)
	sunglasses = move_toward(sunglasses, sunglasses_target, delta * 0.6)
	ui.eyes(player.eyes_closed, body.pulse)
	var f := player.focus
	ui.prompt(tr(String(f.get_meta("interact"))) if f and act != "end" else "")
	if act == "flat" or act == "stairs":
		state.watched = man.visible and _he_sees_you()
	# the clock
	if act == "flat":
		_clock_t += delta
		if _clock_t > 1.0:
			_clock_t = 0.0
			clock_player.play()
		if flat.clock_pendulum:
			flat.clock_pendulum.rotation.z = sin(_t * PI) * 0.12
	if act == "flat" or act == "chase" or act == "home":
		_next_lightning -= delta
		if _next_lightning <= 0.0:
			_next_lightning = _rng.randf_range(16.0, 38.0)
			_flash = 1.0
			_thunder_in = _rng.randf_range(0.8, 3.0)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0:
			_sfx("res://assets/audio/thunder_%d.ogg" % _rng.randi_range(1, 2), -6.0)
	_flash = maxf(0.0, _flash - delta * 2.4)
	var fl := _flash * (0.55 + 0.45 * sin(_t * 70.0)) if _flash > 0.35 else _flash
	lightning.light_energy = fl * 14.0
	flat.window_mat.set_shader_parameter("flash", fl)
	flat.window_mat.set_shader_parameter("time_s", _t)
	stairs.window_mat.set_shader_parameter("time_s", _t)
	var memory_look := 0.3 if act == "home" else 0.0
	post_mat.set_shader_parameter("ghost", _memory * 0.7 + memory_look * 0.4)
	post_mat.set_shader_parameter("blur", _memory * 0.9)
	post_mat.set_shader_parameter("desaturate", clampf(_memory * 0.6 + memory_look, 0.0, 1.0))
	if act == "climb" or act == "stairs":
		var k := clampi(int((player.global_position.y - stairs.global_position.y) / StairBuilder.H + 0.25), 0, 2)
		if k != _moon_k:
			_moon_k = k
			stairs.place_moon(k)
	post_mat.set_shader_parameter("sunglasses", sunglasses)
	post_mat.set_shader_parameter("tremble", adrenaline * 0.6)
	post_mat.set_shader_parameter("pulse", body.pulse * (0.5 + adrenaline))
	post_mat.set_shader_parameter("red_flash", red_flash + adrenaline * 0.15)
	post_mat.set_shader_parameter("zoom", adrenaline * 0.05)
	post_mat.set_shader_parameter("vignette", 0.55 + adrenaline * 0.3)
	post_mat.set_shader_parameter("time_s", _t)
	if recording and act == "flat":
		pass
