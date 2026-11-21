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
var _man_moving := false
var _paused := false
var _flash := 0.0
var _next_lightning := 18.0
var _thunder_in := -1.0
var lightning: SpotLight3D
var _moon_k := 0
var _world_ready := false
var head: CharacterRig          # hers, for the piano
var _head_held := false
var _susp_stage := 0
var _man_watching := false
var scares: Scares
var entering := false           # walking in past her, on the way to the piano
var _gore_light: SpotLight3D
signal world_ready
var _fp_item: Node3D            # what he holds up in front of him (receiver, glasses)
var _cord: MeshInstance3D       # the phone cord while the receiver is lifted
var _cord_base := Vector3.ZERO
var _tapping := false


func _ready() -> void:
	_rng.randomize()
	_capture = OS.get_cmdline_user_args().has("--capture")
	world = InteriorEnv.new()
	add_child(world)
	world.setup(self)
	flat = FlatBuilder.new()
	flat.name = "Flat"
	add_child(flat)
	flat.build_home()
	stairs = StairBuilder.new()
	stairs.name = "Stairs"
	stairs.position = Vector3(0.0, 0.0, -40.0)
	add_child(stairs)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.collision_mask = 1      # people are soft: see Player.avoid
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
	man.visible = false
	woman = CharacterRig.new()
	woman.name = "Woman"
	add_child(woman)
	woman.visible = false
	player.avoid = man
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
	var start := "home"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--act="):
			start = a.substr(6)
	if _capture:
		add_child(load("res://scripts/dev_capture.gd").new())
		_dev_place()
	_build_world()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay"):
			add_child(load("res://scripts/dev_autoplay.gd").new())
	match start:
		"stairs":
			_act_stairs()
		"door":
			_dev_door()
		"flat", "piano":
			_act_flat()
		"bath":
			_dev_bath()
		"chase":
			_act_flat_quick_chase()
		"head", "face", "pop", "upside", "side", "lunge", "sub", "far", "blackout", "monster":
			_dev_scare(start)
		_:
			_act_home()


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
	piano_ui.missed.connect(func(_lane: int) -> void: state.piano_error("miss"))
	piano_ui.wrong.connect(func(_lane: int) -> void: state.piano_error("wrong"))
	state.suspicion_changed.connect(func(v: float) -> void: ui.suspicion(v / state.max_suspicion()))
	state.tell.connect(func(kind: String, amount: float) -> void: ui.tell(kind, amount))
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
	# his knife (a kitchen knife), carried in the right hand
	knife = Node3D.new()
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh()
	var bsh := ShaderMaterial.new()
	bsh.shader = load("res://shaders/blade.gdshader")
	blade.material_override = bsh
	blade.rotation.y = PI * 0.5          # the flat of the blade faces the palm
	blade.position = Vector3(0.021, 0.07, 0.0)
	knife.add_child(blade)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.6, 0.62, 0.64)
	steel.metallic = 1.0
	steel.roughness = 0.3
	var bolster := MeshInstance3D.new()
	bolster.mesh = MeshUtil.rounded_box(Vector3(0.03, 0.014, 0.012), 0.004)
	bolster.material_override = steel
	bolster.position = Vector3(0, 0.064, 0.0)
	knife.add_child(bolster)
	var handle := MeshInstance3D.new()
	handle.mesh = MeshUtil.rounded_box(Vector3(0.026, 0.115, 0.019), 0.008)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.035, 0.035, 0.038)
	hm.roughness = 0.45
	handle.material_override = hm
	knife.add_child(handle)
	for ry: float in [-0.035, 0.0, 0.035]:
		for sx: float in [-1.0, 1.0]:
			var rivet := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0028
			cm.bottom_radius = 0.0028
			cm.height = 0.002
			cm.radial_segments = 10
			rivet.mesh = cm
			rivet.material_override = steel
			rivet.rotation.x = PI * 0.5
			rivet.position = Vector3(0.0, ry, sx * 0.0095)
			knife.add_child(rivet)
	knife.visible = false
	if man.skel:
		var ba := man.attach("wrist.R", knife)
		ba.name = "KnifeHand"
		knife.position = Vector3(0, 0.08, 0.02)
	# the coil of piano wire he hands you: a few loose turns, one end sprung out
	wire = Node3D.new()
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.42, 0.42, 0.43)
	wm.metallic = 1.0
	wm.roughness = 0.28
	for k in 5:
		var loop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.046 + 0.002 * k
		tm.outer_radius = tm.inner_radius + 0.0016
		tm.rings = 48
		tm.ring_segments = 6
		loop.mesh = tm
		loop.material_override = wm
		loop.rotation = Vector3(0.05 * k - 0.1, 0.4 * k, 0.04 * (k % 2) - 0.02)
		loop.position = Vector3(0.0, 0.0015 * k, 0.002 * k)
		wire.add_child(loop)
	var tail := MeshInstance3D.new()
	tail.mesh = MeshUtil.tube(PackedVector3Array([Vector3(0.05, 0.0, 0.0), Vector3(0.09, 0.01, -0.03), Vector3(0.12, -0.02, -0.08)]),
			PackedFloat32Array([0.0009, 0.0009, 0.0007]), 5)
	tail.material_override = wm
	wire.add_child(tail)
	wire.visible = false
	add_child(wire)


## A chef's knife blade: y along it (tip at the top), z across (spine at 0,
## the edge below, with a belly up to the point), thin at the edge.
func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var length := 0.2
	var spine: Array[Vector3] = []
	var edge: Array[Vector3] = []
	for i in n + 1:
		var f := float(i) / float(n)
		var y := f * length
		var h := 0.042 * (1.0 - pow(f, 2.2)) * (1.0 - 0.15 * f)       # depth spine to edge
		var drop := -0.012 * pow(maxf(0.0, (f - 0.7) / 0.3), 1.6)     # the spine dips to the point
		var t := 0.0013 * (1.0 - f * 0.85)                              # half thickness
		spine.append(Vector3(t, y, drop))
		edge.append(Vector3(0.0, y, drop - h))
	for i in n:
		for sd: float in [1.0, -1.0]:
			var a := Vector3(spine[i].x * sd, spine[i].y, spine[i].z)
			var b := Vector3(spine[i + 1].x * sd, spine[i + 1].y, spine[i + 1].z)
			var tri := [[a, b, edge[i + 1]], [a, edge[i + 1], edge[i]]]
			for t3: Array in tri:
				var nrm: Vector3 = (t3[1] - t3[0]).cross(t3[2] - t3[0])
				if nrm.x * sd < 0.0:
					t3 = [t3[0], t3[2], t3[1]]
				for v: Vector3 in t3:
					st.add_vertex(v)
		# the flat of the spine
		var p0 := spine[i]
		var p1 := spine[i + 1]
		for t3: Array in [[p0, Vector3(-p0.x, p0.y, p0.z), Vector3(-p1.x, p1.y, p1.z)], [p0, Vector3(-p1.x, p1.y, p1.z), p1]]:
			var nrm: Vector3 = (t3[1] - t3[0]).cross(t3[2] - t3[0])
			if nrm.z < 0.0:
				t3 = [t3[0], t3[2], t3[1]]
			for v: Vector3 in t3:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


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
	man.talk(secs * 0.85)
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
		if _tapping:
			_tap_handset()
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
	# stop everything that is still going, then leave on a clean frame
	_gen += 1
	act = "end"
	_paused = false
	get_tree().paused = false
	for p: Node in [amb, chase_music, man_voice, phone_voice, ring_player, clock_player]:
		if p:
			p.stop()
	piano_ui.stop()
	ui.fade_now(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(MENU_SCENE)


## Everything but his room, built in the background (he is on the phone).
func _build_world() -> void:
	await get_tree().process_frame
	await flat.build_rest()
	stairs.build()
	await get_tree().process_frame
	stairs.add_colliders()
	stairs.place_moon(0)
	stairs.configure(0, 7, "2")
	stairs.configure(1, 8, "3")
	stairs.configure(2, 9, "4")
	stairs.her_floor = 2
	stairs.add_knock_target()
	await get_tree().process_frame
	man.setup("man")
	man.visible = false
	await get_tree().process_frame
	woman.setup("woman", "womanc")
	woman.visible = false
	woman.alive = false
	# the wire is still in her neck
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.046
	tm.outer_radius = 0.051
	tm.rings = 40
	tm.ring_segments = 8
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.3, 0.03, 0.03)
	rm.metallic = 0.8
	rm.roughness = 0.25
	ring.material_override = rm
	ring.position = Vector3(0.0, 0.035, 0.0)
	woman.attach("neck02", ring)
	scares = Scares.new()
	scares.name = "Scares"
	add_child(scares)
	scares.setup(self)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay"):
			scares.bot = true
		elif a.begins_with("--hold="):
			scares.dev_hold = float(a.substr(7))
	_gore_light = SpotLight3D.new()
	_gore_light.light_color = Color(1.0, 0.95, 0.88)
	_gore_light.light_energy = 0.0
	_gore_light.spot_range = 4.5
	_gore_light.spot_angle = 42.0
	_gore_light.shadow_enabled = true
	add_child(_gore_light)
	man.stepped.connect(_on_man_step)
	_make_props()
	await _bake_nav()
	_world_ready = true
	world_ready.emit()


## Acts that need the flat, the stairs or the people wait for them.
func _need_world() -> void:
	if not _world_ready:
		await world_ready


# ---------------------------------------------------------------------------
# ACT 1: his room. The landline rings; a woman's voice; two taps on the
# receiver for yes. His dark glasses, his white cane, out of the door.
# ---------------------------------------------------------------------------
func _act_home() -> void:
	_gen += 1
	var g := _gen
	act = "home"
	amb.stream = _stream("res://assets/audio/amb_flat.ogg")
	amb.volume_db = -8.0
	amb.play()
	player.global_position = flat.spots.home_start
	player.set_mode("walk", deg_to_rad(-140.0))
	player.yaw = deg_to_rad(-140.0)
	player.pitch = 0.0
	player.cane_enabled = false
	player.set_mode("walk")
	player.can_close_eyes = false
	sunglasses_target = 0.0
	sunglasses = 0.0
	ring_player.global_position = flat.spots.home_phone
	ui.fade_now(1.0)
	await wait(0.4)
	_ring_loop(g)
	ui.fade_to(0.0, 2.0)
	ui.chapter("CH_1", 2.5)
	await wait(2.0)
	if not _alive(g):
		return
	think("THINK_PHONE_1", 3.0)
	ui.objective("OBJ_PHONE")
	ui.hint_hold("HINT_START")
	await wait_interact("home_phone")
	if not _alive(g):
		return
	ui.hint_clear()
	_hints["picked"] = true
	ring_player.stop()
	# he lifts the receiver off the cradle to his ear
	player.set_mode("locked")
	await _turn_to(flat.spots.home_phone + Vector3(0, -0.2, 0), 0.5)
	await _lift_handset()
	_sfx("res://assets/audio/phone_click.ogg", -4.0)
	ui.objective("OBJ_LISTEN")
	await wait(0.8)
	await phone_say("CALL_1", 3.5)
	think("THINK_CALL_1", 3.2)
	await wait(3.0)
	await phone_say("CALL_2", 4.5)
	await phone_say("CALL_3", 3.5)
	# yes = two taps on the receiver
	ui.objective("OBJ_TAP")
	ui.hint_hold("HINT_KNOCK")
	_clicks = 0
	_tapping = true
	var tries := 0
	while _clicks < 2:
		await wait(0.3)
		tries += 1
		if tries == 40:
			await phone_say("CALL_1", 2.5)
			tries = 0
		if not _alive(g):
			return
	_tapping = false
	ui.hint_clear()
	ui.objective("OBJ_LISTEN")
	await wait(0.6)
	await phone_say("CALL_4", 4.5)
	think("THINK_CALL_2", 3.0)
	await wait(3.2)
	await phone_say("CALL_5", 3.8)
	think("THINK_CALL_3", 2.6)
	await wait(2.8)
	await phone_say("CALL_6", 4.0)
	_sfx("res://assets/audio/phone_click.ogg", -4.0)
	await wait(0.5)
	_sfx("res://assets/audio/phone_dead.ogg", -14.0)
	await wait(0.8)
	await _hang_up()
	if not _alive(g):
		return
	think("THINK_CALL_4", 2.5)
	await wait(2.8)
	think("THINK_CALL_5", 3.0)
	await wait(3.3)
	think("THINK_CALL_6", 3.8)
	await wait(2.0)
	player.set_mode("walk", player.yaw)
	# glasses and cane, in any order
	ui.objective("OBJ_GEAR")
	ui.hint_hold("HINT_GEAR")
	var got := {}
	while got.size() < 2:
		var id: String = await player.interacted
		if not _alive(g):
			return
		if id == "glasses" and not got.has("glasses"):
			got["glasses"] = true
			await _put_on_glasses()
		elif id == "cane" and not got.has("cane"):
			got["cane"] = true
			await _take_cane()
		elif id == "home_door":
			think("THINK_NOT_YET", 2.6)
	ui.hint_clear()
	think("THINK_GLASSES", 3.5)
	player.can_close_eyes = true
	ui.objective("OBJ_LEAVE")
	ui.hint_hold("HINT_DOOR")
	await wait_interact("home_door")
	if not _alive(g):
		return
	ui.hint_clear()
	await _leave_home()
	if not _alive(g):
		return
	_act_stairs()


func _ring_loop(g: int) -> void:
	while _alive(g) and act == "home" and not _hints.has("picked"):
		if not ring_player.playing:
			ring_player.play()
		await wait(0.5)


## Turn the head to look at a point over `secs`.
func _turn_to(p: Vector3, secs: float) -> void:
	player.look_toward(p, secs)
	await wait(secs)


func _home_phone() -> Node3D:
	return flat.get_node_or_null("Home/Phone")


## The receiver comes off the cradle up to his ear; the coiled cord follows.
func _lift_handset() -> void:
	var phone := _home_phone()
	if phone == null:
		return
	var hs: Node3D = phone.get_node("Handset")
	var fp := hs.duplicate() as Node3D
	player.cam.add_child(fp)
	fp.global_transform = hs.global_transform
	hs.visible = false
	var cord_static := phone.get_node_or_null("Cord")
	if cord_static:
		cord_static.visible = false
	_fp_item = fp
	_cord_base = phone.to_global(Vector3(0.1, 0.03, 0.02))
	_cord = MeshInstance3D.new()
	_cord.top_level = true
	_cord.material_override = flat._m.bakelite
	add_child(_cord)
	# at the ear: the grip runs from the mouth (lower right of the view) up past the cheek
	var ear := Transform3D(Basis(Vector3(0.37, 0.56, 0.74), Vector3(0.929, -0.223, -0.295), Vector3(0.0, 0.796, -0.603)), Vector3(0.1, -0.06, -0.155))
	var tw := create_tween()
	tw.tween_property(fp, "transform", ear, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## A tap of a finger on the receiver (the only "yes" he can give).
func _tap_handset() -> void:
	if _fp_item == null:
		return
	var base := _fp_item.position
	var tw := create_tween()
	tw.tween_property(_fp_item, "position", base + Vector3(-0.012, 0.01, -0.025), 0.05)
	tw.tween_property(_fp_item, "position", base, 0.12)
	_sfx("res://assets/audio/knock.ogg", -15.0)


## Back on the cradle.
func _hang_up() -> void:
	var phone := _home_phone()
	if phone == null or _fp_item == null:
		return
	var hs: Node3D = phone.get_node("Handset")
	var target := player.cam.global_transform.affine_inverse() * hs.global_transform
	var tw := create_tween()
	tw.tween_property(_fp_item, "transform", target, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_sfx3d("res://assets/audio/phone_click.ogg", phone.global_position, -4.0, 1.5)
	_fp_item.queue_free()
	_fp_item = null
	hs.visible = true
	if _cord:
		_cord.queue_free()
		_cord = null
	var cord_static := phone.get_node_or_null("Cord")
	if cord_static:
		cord_static.visible = true


## The coiled cord between the phone and the receiver in his hand.
func _update_cord() -> void:
	if _cord == null or _fp_item == null:
		return
	var a := _cord_base
	var b := _fp_item.to_global(Vector3(-0.1, -0.012, 0.0))
	var d := a.distance_to(b)
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var up2 := side.cross(axis)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 64
	for i in n:
		var t := float(i) / float(n - 1)
		var p := a.lerp(b, t) + Vector3(0.0, -sin(t * PI) * 0.14 * d, 0.0)
		var ang := t * TAU * 24.0
		p += (side * cos(ang) + up2 * sin(ang)) * 0.0065 * sin(t * PI) ** 0.3
		pts.append(p)
		radii.append(0.0022)
	_cord.mesh = MeshUtil.tube(pts, radii, 4)


## The dark glasses: up off the table, unfolded in front of his face, on.
func _put_on_glasses() -> void:
	var gl: Node3D = flat.get_node("Home/Glasses")
	player.set_mode("locked")
	await _turn_to(gl.global_position, 0.35)
	var fp := gl.duplicate() as Node3D
	player.cam.add_child(fp)
	fp.global_transform = gl.global_transform
	gl.visible = false
	var front := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -0.03, -0.2))
	var on := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -0.004, -0.028))
	var tw := create_tween()
	tw.tween_property(fp, "transform", front, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.2)
	tw.tween_property(fp, "transform", on, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	fp.queue_free()
	sunglasses = 0.6
	sunglasses_target = 0.8
	_sfx("res://assets/audio/rec_click.ogg", -16.0)
	player.set_mode("walk", player.yaw)


## The white cane: off its nail by the door and into his hand.
func _take_cane() -> void:
	var cane: Node3D = flat.get_node("Home/HomeCane")
	player.set_mode("locked")
	await _turn_to(cane.global_position, 0.35)
	var fwd := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var right := Vector3(cos(player.yaw), 0.0, -sin(player.yaw))
	var hand := player.global_position + Vector3(0, Player.EYE - 0.8, 0) + right * 0.24 + fwd * 0.28
	var tip := player.global_position + fwd * 0.95 + Vector3(0, 0.02, 0)
	var dir := tip - hand
	var up := dir.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var xax := up.cross(ref).normalized()
	var zax := xax.cross(up).normalized()
	var target := Transform3D(Basis(xax, up * (dir.length() / 1.2), zax), hand + dir * 0.5)
	var tw := create_tween()
	tw.tween_property(cane, "global_transform", target, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	cane.visible = false
	player.cane_enabled = true
	player.set_mode("walk", player.yaw)
	_sfx3d("res://assets/audio/cane_tap_1.ogg", tip, -6.0, 2.0)


## Out: the door swings open onto the dark, he steps through.
func _leave_home() -> void:
	player.set_mode("locked")
	var hinge: Node3D = flat.doors["home_door"]
	var door_mid := hinge.global_position + Vector3(0.45, 1.1, 0.0)
	await _turn_to(door_mid, 0.4)
	_sfx3d("res://assets/audio/door_creak.ogg", door_mid, -4.0)
	var base: float = hinge.get_meta("base_rot", hinge.rotation.y)
	create_tween().tween_property(hinge, "rotation:y", base + 1.45, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await wait(0.9)
	var out := Vector3(hinge.global_position.x + 0.45, player.global_position.y, hinge.global_position.z - 0.9)
	create_tween().tween_property(player, "global_position", out, 1.8).set_trans(Tween.TRANS_SINE)
	await wait(0.9)
	ui.fade_to(1.0, 0.8)
	await wait(1.1)
	hinge.rotation.y = base


# ---------------------------------------------------------------------------
# ACT 2: the stairs. Two floors up through the dark (the lights only wake to
# a sound); a phone rings behind a neighbour's door; her door.
# ---------------------------------------------------------------------------
func _enter_stairs() -> void:
	sunglasses_target = 0.8
	sunglasses = 0.8
	player.cane_enabled = true
	player.can_close_eyes = true
	amb.stream = _stream("res://assets/audio/amb_stair.ogg")
	amb.volume_db = -4.0
	amb.play()


## His footsteps on the landing wake the nearest sensor lights.
func _wake_stair_lights(p: Vector3) -> void:
	for L: SensorLight in stairs.lights:
		if L.global_position.distance_to(p) < 4.0:
			L.trigger()


## Wait until the player has climbed `floors_up` storeys of the stairwell.
func _climb_to(floors_up: float) -> void:
	var g := _gen
	while _alive(g) and player.global_position.y < stairs.global_position.y + StairBuilder.H * floors_up - 0.3:
		await wait(0.25)


func _act_stairs() -> void:
	await _need_world()
	_gen += 1
	var g := _gen
	act = "stairs"
	_enter_stairs()
	ui.fade_now(1.0)
	var start := stairs.to_global(Vector3(-0.68, 0.05, 0.4))
	player.global_position = start
	player.set_mode("walk", PI)
	player.yaw = PI
	player.pitch = 0.0
	await wait(0.3)
	_wake_stair_lights(start)
	ui.fade_to(0.0, 1.6)
	await wait(1.4)
	if not _alive(g):
		return
	think("THINK_CLIMB_1", 3.5)
	ui.objective("OBJ_CLIMB")
	ui.hint_hold("HINT_CLIMB")
	await _climb_to(0.45)
	if not _alive(g):
		return
	ui.hint_clear()
	think("THINK_STAIRS_1", 3.5)
	await wait(4.0)
	hint_once("HINT_EYES", 5.0)
	await _climb_to(1.0)
	if not _alive(g):
		return
	think("THINK_CLIMB_2", 4.5)
	# a phone rings behind a neighbour's door; nobody answers it
	_ring_times(stairs.neighbour_door(1), 4, g)
	await wait(5.0)
	if not _alive(g):
		return
	think("THINK_CLIMB_3", 3.2)
	await wait(3.6)
	think("THINK_CLIMB_4", 3.4)
	await _climb_to(1.5)
	if not _alive(g):
		return
	think("THINK_CLIMB_5", 3.5)
	await _climb_to(float(stairs.her_floor))
	if not _alive(g):
		return
	_door_scene(g)


func _ring_times(pos: Vector3, n: int, g: int) -> void:
	ring_player.global_position = pos
	for i in n:
		if not _alive(g):
			return
		ring_player.play()
		await wait(2.6)
	ring_player.stop()


## Her door: knock, the door opens, he looks into your eyes.
func _door_scene(g: int) -> void:
	think("THINK_DOOR_0", 2.5)
	ui.objective("OBJ_KNOCK")
	ui.hint_hold("HINT_KNOCK_DOOR")
	await wait_interact("her_door")
	if not _alive(g):
		return
	ui.hint_clear()
	ui.objective("")
	player.set_mode("locked")
	await _turn_to(stairs.knock_pos(), 0.4)
	for i in 3:
		_sfx3d("res://assets/audio/knock.ogg", stairs.knock_pos(), -4.0 + i, 1.5)
		player.heartbeat_kick(0.3)
		await wait(0.42)
	await wait(2.2)
	if not _alive(g):
		return
	# the door opens; he is there, in the dark of the hallway
	var hinge := stairs.her_hinge()
	_sfx3d("res://assets/audio/door_creak.ogg", stairs.knock_pos(), -4.0)
	create_tween().tween_property(hinge, "rotation:y", -1.25, 1.6).set_trans(Tween.TRANS_SINE)
	man.visible = true
	man.global_position = stairs.to_global(Vector3(-StairBuilder.W - 0.4, StairBuilder.H * stairs.her_floor, -1.0))
	man.look_at(Vector3(player.global_position.x, man.global_position.y, player.global_position.z), Vector3.UP, true)
	man.set_pose("stand", 0.0)
	man.look_node = player.head
	ui.show_meter(true)
	await wait(1.6)
	if not _alive(g):
		return
	# he leans in close, his face a hand's breadth from yours, and studies your eyes
	ui.hint_hold("HINT_RULE_SEE")
	player.set_mode("still", player.yaw)
	player.look_toward(man.bone_pos("head"), 0.7)
	man.set_pose("lean_in", 1.2)
	var to_player := (player.global_position - man.global_position) * Vector3(1, 0, 1)
	var step := clampf(to_player.length() - 0.9, 0.0, 0.4)
	if step > 0.05:
		man.walk_path(PackedVector3Array([man.global_position + to_player.normalized() * step]), 0.4)
	await wait(0.6)
	state.watched = true
	state.visual("door_face", man.bone_pos("head"), 4.0, 0.4)
	await wait(4.2)
	if not _alive(g):
		return
	ui.hint_clear()
	think("THINK_DOOR_1", 3.5)
	await wait(3.0)
	man.set_pose("stand", 0.8)
	await man_say("MAN_1", 2.6)
	if not _alive(g):
		return
	ui.hint_hold("HINT_NOD")
	var gsture := await wait_gesture(10.0)
	ui.hint_clear()
	if not _alive(g):
		return
	if gsture == "shake":
		await man_say("MAN_1", 2.0)
	await man_say("MAN_2", 3.0)
	ui.fade_to(1.0, 1.2)
	await wait(1.5)
	if not _alive(g):
		return
	_act_flat()


## Found out on the landing: he pulls you inside. The night ends at the door.
func _door_grab(reason: String) -> void:
	_gen += 1
	act = "end"
	ui.hint_clear()
	ui.objective("")
	player.set_mode("locked")
	man.visible = true
	man.stop()
	man.set_pose("lunge", 0.25)
	var to_p := (player.global_position - man.global_position) * Vector3(1, 0, 1)
	create_tween().tween_property(man, "global_position", player.global_position - to_p.normalized() * 0.6, 0.35)
	player.look_toward(man.bone_pos("head"), 0.3)
	_sfx("res://assets/audio/stinger.ogg", 0.0)
	adrenaline = 1.0
	red_flash = 1.0
	await wait(0.6)
	_sfx3d("res://assets/audio/door_slam.ogg", stairs.knock_pos(), 0.0)
	ui.fade_now(1.0)
	await wait(1.6)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var why := tr("WHY") + "\n" + tr(state.last_reason if state.last_reason != "" else reason)
	ui.show_end("END_DEAD", "END_DOOR_D", why, state.mic_history, mic.threshold_db())


func _dev_door() -> void:
	await _need_world()
	_gen += 1
	act = "stairs"
	_enter_stairs()
	player.global_position = stairs.to_global(Vector3(-0.3, StairBuilder.H * stairs.her_floor + 0.05, -1.0))
	player.set_mode("walk", PI * 0.5)
	player.yaw = PI * 0.5
	_wake_stair_lights(player.global_position)
	ui.fade_to(0.0, 0.5)
	_door_scene(_gen)


# ---------------------------------------------------------------------------
# ACT 3: the flat
# ---------------------------------------------------------------------------
func _act_flat() -> void:
	await _need_world()
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
	woman.visible = true
	woman.set_pose("lie", 0.0)
	man.visible = true
	man.look_node = player.head
	ui.show_meter(true)
	if OS.get_cmdline_user_args().has("--act=piano"):
		# (dev) straight to the bench: she is already in the bath
		_corpse_to_tub()
		man.set_pose("sit", 0.0)
		_man_sit_now()
		_sit_at_piano()
		await scares.prewarm()
		ui.fade_to(0.0, 1.5)
		await wait(2.0)
	else:
		await _enter_flat(g)
	if not _alive(g):
		return
	await man_say("MAN_3", 2.6)
	hint_once("HINT_PIANO", 7.0)
	get_tree().create_timer(7.5).timeout.connect(func() -> void:
		if _alive(g):
			hint_once("HINT_METER", 7.0))
	_tr("piece 1")
	piano_ui.start(PianoGame.gymnopedie())
	state.playing_piano = true
	scares.run(g)
	_piano_tests(g, piano_ui.length)
	await piano_ui.finished
	if not _alive(g):
		return
	state.playing_piano = false
	# the bathroom
	_tr("to the bathroom")
	await man_say("MAN_5", 3.4)
	_stand_up()
	ui.objective("OBJ_BATH")
	ui.hint("HINT_BATH", 7.0)
	man_walk(MAN_WATCH, Vector3(0.0, 0.0, 3.2))
	_blood_test(g)
	await _bathroom_sequence(g)
	if not _alive(g):
		return
	_tr("back to the piano")
	await man_say("MAN_8", 2.5)
	ui.objective("OBJ_BACK")
	ui.hint("HINT_BACK", 6.0)
	await _walk_back_to_piano(g)
	if not _alive(g):
		return
	# second piece: the string, the duet
	ui.objective("")
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
	ui.objective("OBJ_EXIT")
	ui.hint("HINT_EXIT", 7.0)
	await _leaving(g)


## The door shuts behind you and the hall bulb is on. She is lying on the
## floor in front of you, the wire still in her neck, and he is standing over
## her watching you walk past. Then her head turns.
func _enter_flat(g: int) -> void:
	entering = true
	_corpse_in_hall()
	man.set_pose("stand", 0.0)
	man.global_position = Vector3(0.28, 0.0, 4.75)
	man.look_at(Vector3(0.0, 0.0, 0.7), Vector3.UP, true)
	player.global_position = flat.spots.front_inside + Vector3(0.0, 0.03, 0.1)
	player.velocity = Vector3.ZERO
	player.set_mode("walk")
	player.yaw = PI
	player.pitch = -0.12
	player.snap_eye()
	await scares.prewarm()
	ui.fade_to(0.0, 1.4)
	scares._play("dread_swell", -3.0)
	await wait(1.8)
	if not _alive(g):
		return
	state.visual("corpse", woman.bone_pos("head"), 6.0, 0.6)
	think("THINK_CORPSE", 4.5)
	ui.objective("OBJ_PIANO")
	ui.hint("HINT_ENTER", 9.0)
	var snapped := false
	var t := 0.0
	while _alive(g) and player.global_position.distance_to(flat.spots.piano_seat) > 1.25:
		await wait(0.1)
		t += 0.1
		if not snapped and (player.global_position.z > 1.4 or player.global_position.x < -0.8 or t > 10.0):
			snapped = true
			scares.corpse_snap(1.0)
			get_tree().create_timer(4.5).timeout.connect(func() -> void:
				if _alive(g):
					think("THINK_NOT_REAL", 4.0)
					ui.hint("HINT_UNREAL", 9.0))
	if not _alive(g):
		return
	entering = false
	ui.objective("")
	_sit_at_piano()
	_drag_to_bath(g)


func _corpse_in_hall() -> void:
	# on her back, feet towards the bathroom he was dragging her to
	woman.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	woman.global_position = Vector3(0.1, 0.13, 4.1)
	woman.undead = false
	woman.jaw_open = 0.25
	woman.lid_wide = 0.6
	_gore_light.global_position = Vector3(0.0, 2.3, 2.9)
	_gore_light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_gore_light.light_energy = 3.2
	flat.blood_decal(flat, "blood_pool", Vector3(0.05, 0.0, 2.65), Vector3(1.05, 0.3, 0.95), Vector3.UP, 0.7)
	flat.blood_decal(flat, "blood_splat2", Vector3(-0.2, 0.0, 3.3), Vector3(0.9, 0.3, 0.9), Vector3.UP, 2.1)
	flat.blood_decal(flat, "blood_hand", Vector3(-0.63, 0.75, 2.5), Vector3(0.4, 0.3, 0.5), Vector3.RIGHT, 0.0)
	flat.blood_decal(flat, "blood_drip", Vector3(0.63, 1.1, 3.0), Vector3(0.7, 0.3, 0.9), Vector3.LEFT, 0.0)


func _corpse_to_tub() -> void:
	woman.global_position = flat.spots.tub + Vector3(0.45, 0.0, 0.0)
	woman.rotation = Vector3(-deg_to_rad(70.0), deg_to_rad(90.0), 0.0)
	scares.corpse_rest()
	_gore_light.global_position = flat.spots.tub + Vector3(-0.2, 1.9, -0.5)
	_gore_light.look_at(flat.spots.tub + Vector3(0.3, 0.4, 0.0), Vector3.UP)
	_gore_light.light_energy = 2.6


## While you play, behind you, he drags her the rest of the way to the bath.
func _drag_to_bath(g: int) -> void:
	await wait(2.0)
	if not _alive(g):
		return
	_sfx3d("res://assets/audio/drag.ogg", Vector3(0.0, 0.2, 3.4), 3.0, 5.0)
	await wait(5.0)
	if not _alive(g):
		return
	_corpse_to_tub()
	flat.blood_decal(flat, "blood_drag", Vector3(0.0, 0.0, 3.35), Vector3(1.7, 0.3, 0.6), Vector3.UP, PI * 0.5)
	flat.blood_decal(flat, "blood_drag", Vector3(0.85, 0.0, 4.15), Vector3(1.4, 0.3, 0.55), Vector3.UP, 0.25)
	flat.blood_decal(flat, "blood_hand", Vector3(0.68, 0.9, 3.25), Vector3(0.4, 0.3, 0.5), Vector3.RIGHT, 0.0)
	_sfx3d("res://assets/audio/wet_thud.ogg", flat.spots.tub, 0.0, 4.0)
	man_sit_chair()


func _sit_at_piano() -> void:
	player.global_position = flat.spots.piano_seat + Vector3(0.0, 0.0, 0.0)
	player.global_position.y = 0.0
	player.cane_enabled = false
	player.set_mode("seated", deg_to_rad(90.0))
	player.snap_eye()


## Up from the bench: you rise and step out beside it (clear of the coffee
## table), then walk.
func _stand_up() -> void:
	player.cane_enabled = true
	player.set_mode("locked")
	player.eye_h = Player.EYE
	var to: Vector3 = flat.spots.piano_seat + Vector3(0.62, 0.02, 0.0)
	var tw := create_tween()
	tw.tween_property(player, "global_position", to, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		player.set_mode("walk", player.yaw)
		player.unstick())


# ---------------------------------------------------------------------------
# moving him about: he walks round the furniture and through the doors,
# turns, sits down and gets up again. Nothing snaps.
# ---------------------------------------------------------------------------
## Where he waits while you go to wash: inside the living-room door, out of
## your way, with the hall in view.
const MAN_WATCH := Vector3(-1.25, 0.0, 0.95)
## Where he creeps up to for the face at the piano (from the seat).
const FACE_SPOT := Vector3(-0.33, 0.0, -0.66)
## His armchair faces the back of the piano bench.
const CHAIR_YAW := PI / 3.0
## Where he stands to watch your hands when he grows suspicious (from the seat).
const WATCH_SPOT := Vector3(0.75, 0.0, 0.5)

var _nav_region: NavigationRegion3D
var _nav_ready := false


## The walkable floor of the flat, from its colliders, for nav_path().
func _nav_probe() -> void:
	var pairs := [[flat.spots.armchair + Vector3(0.36, 0, 0.21), MAN_WATCH], [MAN_WATCH, Vector3(-0.32, 0, 4.85)],
		[Vector3(-0.32, 0, 4.85), Vector3(0.85, 0, 4.3)], [Vector3(0.85, 0, 4.3), flat.spots.armchair],
		[flat.spots.piano_seat + Vector3(0.6, 0, 0.7), Vector3(0.0, 0.0, 2.6)], [Vector3(0, 0, 2.0), Vector3(1.3, 0, 7.5)]]
	for pr: Array in pairs:
		var path := nav_path(pr[0], pr[1])
		var length := 0.0
		var prev: Vector3 = pr[0]
		for q: Vector3 in path:
			length += prev.distance_to(q)
			prev = q
		print("NAV %s -> %s : %d pts, %.2f m (straight %.2f)" % [pr[0], pr[1], path.size(), length, (pr[0] as Vector3).distance_to(pr[1])])


func _bake_nav() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.05)
	NavigationServer3D.map_set_cell_height(map, 0.05)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.05
	nm.cell_height = 0.05
	nm.agent_radius = 0.25
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_flat"
	flat.add_to_group(&"nav_flat")
	_nav_region = NavigationRegion3D.new()
	_nav_region.navigation_mesh = nm
	add_child(_nav_region)
	_nav_region.bake_navigation_mesh(true)
	await _nav_region.bake_finished
	# the server folds the new mesh into the map in the background: wait for it
	var probe: Vector3 = flat.spots.hall_mid
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.4:
			break
	_nav_ready = true
	if OS.get_cmdline_user_args().has("--navprobe"):
		print("NAVMESH polys=%d verts=%d map_active=%s regions=%d closest=%s" % [nm.get_polygon_count(), nm.get_vertices().size(),
			NavigationServer3D.map_is_active(map), NavigationServer3D.map_get_regions(map).size(),
			NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 2))])
		_nav_probe()


## A way across the floor from `from` to `to` (corners only, `to` last).
func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _nav_ready:
		var p := NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
		for i in range(1, p.size()):
			out.append(Vector3(p[i].x, to.y, p[i].z))
	if out.is_empty():
		out.append(to)
	else:
		var gap := Vector2(out[out.size() - 1].x - to.x, out[out.size() - 1].z - to.z).length()
		if gap > 0.03 and gap < 0.7:
			out.append(to)
	return out


## He walks to `to` (getting up first if he is sitting) and turns to face
## `face`. Await it to wait until he is there.
func man_walk(to: Vector3, face := Vector3.INF, speed := -1.0) -> void:
	man.visible = true
	if man.target_pose() == "sit":
		await man_stand_up()
	elif man.target_pose() not in CharacterRig.STANDING:
		man.set_pose("stand", 0.5)
	man.walk_path(nav_path(man.global_position, to), speed, face)
	await man.arrived


func man_stand_up() -> void:
	man.stop()
	var f := man.global_basis.z
	f = Vector3(f.x, 0.0, f.z).normalized()
	var to := Vector3(man.global_position.x, 0.0, man.global_position.z) + f * 0.42
	man.set_pose("stand", 1.0)
	var tw := create_tween()
	tw.tween_property(man, "global_position", to, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## Back to his armchair: he walks round to the front of it, turns his back
## to it and lowers himself in.
func man_sit_chair() -> void:
	var fwd := Vector3(sin(CHAIR_YAW), 0.0, cos(CHAIR_YAW))
	var seat: Vector3 = flat.spots.armchair + Vector3(0, -0.42, 0)
	var front := Vector3(seat.x, 0.0, seat.z) + fwd * 0.42
	await man_walk(front, front + fwd)
	if man.global_position.distance_to(front) > 0.2:
		return
	man.set_pose("sit", 1.0)
	var tw := create_tween()
	tw.tween_property(man, "global_position", seat, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	man.rotation.y = CHAIR_YAW


func _man_sit_now() -> void:
	man.visible = true
	man.set_pose("sit", 0.0)
	man.global_position = flat.spots.armchair + Vector3(0, -0.42, 0)
	man.rotation = Vector3(0, CHAIR_YAW, 0)


func _on_man_step(pos: Vector3, loud: float) -> void:
	if not man.visible or act == "end":
		return
	_sfx3d("res://assets/audio/step_%d.ogg" % _rng.randi_range(1, 8), pos + Vector3(0, 0.05, 0), -13.0 + 7.0 * loud, 2.5)


func _man_head() -> Vector3:
	return man.bone_pos("head")


func _piano_tests(g: int, length: float) -> void:
	var pool := ["knife", "glass", "face", "money"]
	pool.shuffle()
	var times := [length * 0.38, length * 0.72]
	for i in 2:
		await wait(times[i] - (times[i - 1] if i > 0 else 0.0))
		if not _alive(g) or not piano_ui.active:
			return
		scares.busy += 1
		await _test(pool[i], g)
		scares.busy = maxi(0, scares.busy - 1)


func _test(kind: String, g: int) -> void:
	match kind:
		"knife":
			# he comes and stands beside you and slowly passes a blade in front of your eyes
			var side := player.eye_pos() + Vector3(0.0, -1.2, 0.75)
			await man_walk(Vector3(side.x + 0.3, 0.0, side.z), player.global_position)
			if not _alive(g):
				return
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
			# he creeps up on your right, no footsteps; then his face, all at
			# once, right beside yours
			man.quiet = true
			# he stands at the bass end of the keyboard, side on to you
			await man_walk(flat.spots.piano_seat + FACE_SPOT, flat.spots.piano_seat + FACE_SPOT + Vector3(0, 0, 1), 0.7)
			man.quiet = false
			if not _alive(g):
				return
			await wait(_rng.randf_range(0.3, 1.6))
			# all at once: one frame he is not there, the next he fills your sight
			man.set_pose("peer", 0.0)
			_face_light(4.0)
			await get_tree().process_frame
			await get_tree().process_frame
			if OS.get_cmdline_user_args().has("--probe"):
				await wait(0.3)
				var hp := man.bone_pos("head")
				var to := (hp - player.eye_pos())
				print("PROBE head=", hp, " dist=", to.length(), " angle=", rad_to_deg(player.look_dir().angle_to(to.normalized())))
			scares.hit(1.0)
			_sfx3d("res://assets/audio/whoosh.ogg", man.bone_pos("head"), -6.0, 2.0)
			state.watched = true
			state.visual("face", man.bone_pos("head"), 4.0, 1.2)
			think("THINK_FACE", 3.0)
			await wait(3.6)
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
	man_sit_chair()


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
	if _rng.randf() < 0.65:
		scares.corpse_snap(0.85)
	else:
		state.visual("tub", woman.bone_pos("head"), 3.0, 0.6)
	await wait(1.5)
	_tr("in the bathroom")
	ui.hint_hold("HINT_WASH")
	think("THINK_BATH_1", 3.0)
	await wait(3.2)
	think("THINK_BATH_2", 3.0)
	# now he follows down the hall and waits by her photograph
	man_walk(Vector3(-0.32, 0.0, 4.85), Vector3(0.6, 0.0, 4.2))
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
	ui.hint_clear()
	ui.objective("")
	_tr("washing")
	player.set_mode("locked")
	create_tween().tween_property(player, "global_position", flat.spots.sink_stand, 0.6).set_trans(Tween.TRANS_SINE)
	player.look_toward(Vector3(3.0, 1.55, 4.0), 0.8)
	_sfx3d("res://assets/audio/drip.ogg", Vector3(2.75, 0.9, 4.0), -4.0)
	await wait(2.0)
	var charged := _rng.randf() < 0.55
	if charged:
		await _fake_charge(g)
	if not _alive(g):
		return
	player.set_mode("walk", player.yaw)
	if not charged or _rng.randf() < 0.4:
		scares.turn_pop(10.0)
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
	# he creeps in behind you while the water runs
	man.quiet = true
	await man_walk(player.global_position + Vector3(-1.4, 0.0, 0.3), player.global_position, 0.8)
	man.quiet = false
	if not _alive(g):
		return
	# lights stutter; in the mirror, behind you, he raises the knife
	var lamp: OmniLight3D = flat.lamps.bath
	var base := lamp.light_energy
	for i in 6:
		lamp.light_energy = base * (0.1 if i % 2 == 0 else 1.0)
		await wait(0.08)
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
	man.walk_path(PackedVector3Array([player.global_position + Vector3(-0.5, 0.0, 0.32)]), 0.75)
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
	man_sit_chair()


func _walk_back_to_piano(g: int) -> void:
	var t := 0.0
	while _alive(g) and t < 45.0:
		await wait(0.25)
		t += 0.25
		if player.global_position.distance_to(flat.spots.piano_seat) < 1.3:
			break
	ui.fade_to(1.0, 0.6)
	await wait(0.7)
	if man.target_pose() != "sit":
		man.stop()
		_man_sit_now()
	ui.fade_to(0.0, 0.8)


func _second_piece(g: int) -> void:
	var len := piano_ui.length
	await wait(len * 0.22)
	if not _alive(g) or not piano_ui.active:
		return
	# a string snaps
	scares.busy += 1
	_sfx3d("res://assets/audio/wire_twang.ogg", flat.spots.piano_seat + Vector3(-0.8, 1.0, 0), 0.0)
	await wait(0.6)
	await man_walk(flat.spots.piano_seat + Vector3(0.6, 0.0, 0.7), player.global_position)
	if not _alive(g):
		return
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
	man_walk(Vector3(0.0, 0.0, 2.6))
	scares.busy = maxi(0, scares.busy - 1)
	await wait(len * 0.15)
	if not _alive(g) or not piano_ui.active:
		return
	scares.busy += 1
	await _head_scene(g)
	scares.busy = maxi(0, scares.busy - 1)
	if not _alive(g):
		return
	var rec_before := recording
	await man_say("MAN_11", 3.2)
	await wait(1.0)
	await man_say("MAN_12", 3.6)
	if recording or rec_before:
		state.evidence["confession"] = true


## "She wants to play with you": he comes up on your left, her head hanging
## from his hand by the hair, and throws it down onto the keys in front of you.
func _head_scene(g: int) -> void:
	_tr("head")
	if head == null:
		head = CharacterRig.new()
		head.name = "Head"
		add_child(head)
		head.setup("woman_head", "womang", false)
		head.jaw_open = 1.0
		head.lid_wide = 1.0
	head.visible = true
	_head_held = true
	woman.hide_head()
	_sfx3d("res://assets/audio/drip.ogg", man.global_position + Vector3(0, 0.5, 0), -8.0, 2.0)
	await man_walk(flat.spots.piano_seat + Vector3(0.3, 0.0, 0.85), player.global_position)
	if not _alive(g):
		return
	await wait(0.6)
	if not _alive(g):
		return
	await man_say("MAN_10", 2.8)
	if not _alive(g):
		return
	await _throw_head()
	if not _alive(g):
		return
	# he leans in over your shoulder and watches your hands
	man.set_pose("lean_in", 0.9)
	man.walk_path(PackedVector3Array([flat.spots.piano_seat + Vector3(0.3, 0.0, 0.62)]), 0.35)
	await wait(1.4)
	if not _alive(g):
		return
	think("THINK_HEAD", 3.0)
	await man_say("MAN_HEAD", 3.4)
	await wait(1.6)
	man.set_pose("stand", 0.8)
	await wait(0.6)
	await man_walk(flat.spots.piano_seat + Vector3(1.4, 0.0, 0.4), player.global_position)


## A faint cold light from where you sit, so a face pushed into yours shows.
func _face_light(secs: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.72, 0.83, 1.0)
	l.light_energy = 0.0
	l.omni_range = 1.3
	l.shadow_enabled = false
	add_child(l)
	l.global_position = player.eye_pos() + player.look_dir() * 0.05 + Vector3(0, 0.08, 0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 1.3, 0.02)
	tw.tween_interval(maxf(0.1, secs - 1.6))
	tw.tween_property(l, "light_energy", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


## Her head, thrown past your ear: it crashes down on the keys and comes to
## rest on the music desk, against the score, looking at you. The low strings
## crash, blood spatters the music, and if your hands lose the beat now he knows.
func _throw_head() -> void:
	_head_held = false
	head.visible = true
	var from := head.global_position
	var rest: Vector3 = flat.spots.piano_seat + Vector3(-0.62, 1.06, 0.0)
	var rot0 := head.rotation
	var rot1 := Vector3(-0.2, PI * 0.5, 0.2)
	_sfx3d("res://assets/audio/whoosh.ogg", player.eye_pos() + Vector3(0, 0, 0.4), -2.0, 2.0)
	var dur := 0.45
	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k := clampf(t / dur, 0.0, 1.0)
		head.global_position = from.lerp(rest, k) + Vector3(0.0, sin(k * PI) * 0.35, 0.0)
		# it tumbles once in the air
		head.rotation = Vector3(lerpf(rot0.x, rot1.x + TAU, k), lerp_angle(rot0.y, rot1.y, k), lerpf(rot0.z, rot1.z, k))
		await get_tree().process_frame
	head.global_position = rest
	head.rotation = rot1
	_sfx3d("res://assets/audio/stab.ogg", rest, 4.0, 3.0)
	_sfx3d("res://assets/audio/wet_thud.ogg", rest, 3.0, 3.0)
	scares.hit(1.15)
	_face_light(5.0)
	for n: int in [36, 37, 39, 41, 42, 44, 45, 48, 49]:
		piano.play(n, 1.0)
	red_flash = 1.0
	adrenaline = 1.0
	body.stress = 1.0
	player.heartbeat_kick(1.3)
	flat.blood_decal(flat, "blood_splat1", rest + Vector3(-0.08, 0.05, 0.0), Vector3(0.95, 0.3, 0.95), Vector3.RIGHT, 1.2)
	flat.blood_decal(flat, "blood_drip", rest + Vector3(-0.06, -0.22, 0.1), Vector3(0.55, 0.3, 0.6), Vector3.RIGHT, 0.0)
	flat.blood_decal(flat, "blood_splat2", Vector3(rest.x + 0.12, 0.78, rest.z), Vector3(0.8, 0.25, 1.0), Vector3.UP, 0.4)
	state.watched = true
	state.visual("head", rest, 4.0, 1.3)
	state.scare_window(5.0)
	# it rocks against the score and settles, its clouded eyes on you
	var tw := create_tween()
	tw.tween_property(head, "rotation:z", 0.45, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "rotation:z", 0.08, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(head, "rotation:z", 0.2, 0.35).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(head, "global_position", rest + Vector3(0.01, -0.012, 0.0), 0.35)
	await tw.finished


## As he grows sure, it shows: at half he watches your hands, at four
## fifths he has made up his mind but for one more slip.
func _update_suspicion_stage() -> void:
	var f := state.suspicion / state.max_suspicion()
	var stage := 2 if f >= 0.8 else (1 if f >= 0.5 else (0 if f < 0.3 else mini(_susp_stage, 1)))
	if stage > _susp_stage and (act == "flat" or act == "stairs"):
		think("THINK_SUSPECT_%d" % stage, 3.0)
		body.stress = maxf(body.stress, 0.55 + 0.25 * stage)
		player.heartbeat_kick(0.4 * stage)
		# while you play he gets out of his chair and comes to watch your hands
		if act == "flat" and state.playing_piano and man.target_pose() == "sit" and not man.moving:
			_man_watching = true
			man_walk(flat.spots.piano_seat + WATCH_SPOT, player.eye_pos(), 0.85)
	elif stage == 0 and _man_watching and not man.moving and act == "flat":
		# satisfied, for now
		_man_watching = false
		if man.global_position.distance_to(flat.spots.piano_seat + WATCH_SPOT) < 0.4:
			man_sit_chair()
	_susp_stage = stage


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
	if man.target_pose() == "sit" or man.global_position.distance_to(player.global_position) > 4.5:
		man.stop()
		man.set_pose("stand", 0.0)
		man.global_position = player.global_position + Vector3(0.0, 0.0, 2.8)
	man.set_pose("knife_low", 0.3)
	knife.visible = true
	adrenaline = 1.0
	chase_music.volume_db = -2.0
	chase_music.play()
	_sfx("res://assets/audio/stinger.ogg", -2.0)
	state.watched = true
	state.visual("door_charge", man.bone_pos("head"), 3.0, 1.2)
	var to_p := (player.global_position - man.global_position) * Vector3(1, 0, 1)
	man.walk_path(nav_path(man.global_position, player.global_position - to_p.normalized() * 0.6), 2.6)
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
	if act == "stairs" or act == "home":
		_door_grab(reason)
		return
	_gen += 1
	var g := _gen
	act = "chase"
	piano_ui.stop()
	state.playing_piano = false
	state.end_tests()
	scares.stop()
	entering = false
	ui.fake_prompt("", 0.01)
	man.visible = true
	man.stop()
	# what your fear makes of him now
	man.retexture("manm")
	man.jaw_open = 0.85
	man.lid_wide = 1.0
	scares.hit(1.0)
	man.set_pose("knife_low", 0.3)
	man.look_while_walking = true
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
	ui.objective("OBJ_HIDE")
	ui.hint("HINT_CHASE", 8.0)
	chase_mode = "hunt"
	_chase_loop(g)


func _act_flat_quick_chase() -> void:
	await _need_world()
	_act_flat()
	await wait(3.0)
	state.expose("TELL_FLINCH")


const ROUTE := [Vector3(-2.8, 0, 2.2), Vector3(-1.2, 0, 1.8), Vector3(0, 0, 2.0), Vector3(0, 0, 4.1), Vector3(1.6, 0, 4.4),
	Vector3(0, 0, 4.1), Vector3(0, 0, 6.0), Vector3(0, 0, 7.4), Vector3(1.3, 0, 7.5), Vector3(-0.8, 0, 8.4), Vector3(0, 0, 6.0), Vector3(0, 0, 2.0)]


func _chase_loop(g: int) -> void:
	var idx := 0
	var hunt_t := 0.0
	var repath := 0.0
	# a moment to break away
	await wait(0.8)
	while _alive(g) and act == "chase":
		await get_tree().process_frame
		var dt := get_process_delta_time()
		var mp := man.global_position
		var pp := player.global_position
		var sees := hidden_in == "" and _line_of_sight(man.bone_pos("head"), player.eye_pos()) and mp.distance_to(pp) < 9.0
		var heard := _t - _last_noise < 0.6 and mp.distance_to(pp) < float(Difficulty.get_value("hearing_m"))
		var target: Vector3 = ROUTE[idx]
		var spd := 1.15 * float(Difficulty.get_value("chase_speed"))
		if sees or heard:
			target = pp
			spd = 2.4 * float(Difficulty.get_value("chase_speed"))
			hunt_t = 4.0
		elif hunt_t > 0.0:
			hunt_t -= dt
			if hidden_in == "":
				target = pp
				spd = 1.8 * float(Difficulty.get_value("chase_speed"))
		if target == ROUTE[idx] and Vector2(target.x - mp.x, target.z - mp.z).length() < 0.5:
			idx = (idx + 1) % ROUTE.size()
			repath = 0.0
			# checking a hiding place
			if hidden_in != "" and _near_hide(mp):
				var found := (_t - _last_noise < 6.0) or _rng.randf() < 0.25
				if found:
					_caught(g, "TELL_FOUND")
					return
		repath -= dt
		if repath <= 0.0:
			repath = 0.3
			man.walk_path(nav_path(mp, target), spd)
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
	man.stop()
	var away := (man.global_position - player.global_position) * Vector3(1, 0, 1)
	if away.length() < 0.05:
		away = Vector3.FORWARD
	man.global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z) + away.normalized() * 0.52
	man.look_at(Vector3(player.global_position.x, man.global_position.y, player.global_position.z), Vector3.UP, true)
	man.set_pose("knife_high", 0.0)
	man.jaw_open = 1.0
	player.look_toward(man.bone_pos("head") + Vector3(0, 0.08, 0), 0.12)
	_face_light(2.0)
	scares.hit(1.3)
	await wait(0.7)
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
	if act == "stairs":
		for L: SensorLight in stairs.lights:
			if L.global_position.distance_to(pos) < 3.6:
				L.trigger()
	if act == "flat" and flat.spots.has("blood_pool"):
		var bp: Vector3 = flat.spots.blood_pool
		if Vector2(pos.x - bp.x, pos.z - bp.z).length() < 0.8:
			blood_tapped = true


func _on_step(pos: Vector3) -> void:
	var path := "res://assets/audio/step_%d.ogg" % _rng.randi_range(1, 8)
	var vol := -2.5 if player.on_stairs else -6.0
	if act == "chase":
		vol = -1.0
	_sfx3d(path, pos, vol, 3.0)
	if act == "stairs":
		for L: SensorLight in stairs.lights:
			if L.global_position.distance_to(pos) < 2.8:
				L.trigger()


func _dev_place() -> void:
	await _need_world()
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
		elif a.begins_with("--tour="):
			# x,y,z,yaw,pitch;... : a new viewpoint every 3 s (for screenshots)
			_dev_tour(a.substr(7).split(";"))


func _dev_tour(stops: PackedStringArray) -> void:
	for stop: String in stops:
		var v := stop.split(",")
		player.set_mode("locked")
		player.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		player.yaw = deg_to_rad(float(v[3]))
		player.pitch = deg_to_rad(float(v[4]))
		ui.fade_now(0.0)
		await wait(3.0)


## Dev: straight to a piano scare to look at it (--act=head / --act=face).
func _dev_scare(kind: String) -> void:
	await _need_world()
	_gen += 1
	var g := _gen
	act = "flat"
	sunglasses_target = 0.8
	sunglasses = 0.8
	_man_sit_now()
	man.look_node = player.head
	_sit_at_piano()
	ui.fade_now(0.0)
	ui.show_meter(true)
	piano_ui.start(PianoGame.prelude())
	state.playing_piano = true
	await wait(0.5)
	_corpse_to_tub()
	await scares.prewarm()
	scares._running = true
	match kind:
		"face":
			await _test("face", g)
		"head":
			await _head_scene(g)
		"sub":
			await scares.subliminal()
		"blackout":
			await scares.blackout()
		"far":
			_stand_up()
			await wait(1.5)
			player.yaw = -PI * 0.5
			await wait(0.3)
			print("far shown: ", await scares.far())
		"monster":
			state.expose("TELL_SCREAM")
		_:
			await scares.pop(kind, false)


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
	state.listening = man.visible and (act == "flat" or act == "stairs")
	state.his_head = man.bone_pos("head") if man.visible and _world_ready else Vector3.INF
	if act == "chase" and mic.active:
		_last_noise = _t
	ui.mic(mic.level_db, mic.threshold_db(), Settings.mic_this_run and mic.has_input())
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
	if stairs.window_mat:
		stairs.window_mat.set_shader_parameter("time_s", _t)
	_update_cord()
	_update_suspicion_stage()
	if _head_held and head:
		head.global_position = man.bone_pos("wrist.R") + Vector3(0.0, -0.16, 0.0)
		head.global_rotation = Vector3(0.12 * sin(_t * 1.7), man.global_rotation.y, 0.08 * sin(_t * 1.3))
	if act == "stairs":
		var k := clampi(int((player.global_position.y - stairs.global_position.y) / StairBuilder.H + 0.25), 0, 2)
		if k != _moon_k:
			_moon_k = k
			stairs.place_moon(k)
	post_mat.set_shader_parameter("sunglasses", sunglasses * (1.0 - 0.8 * (scares.open if scares else 0.0)))
	post_mat.set_shader_parameter("tremble", adrenaline * 0.6)
	post_mat.set_shader_parameter("pulse", body.pulse * (0.5 + adrenaline))
	post_mat.set_shader_parameter("red_flash", red_flash + adrenaline * 0.15)
	post_mat.set_shader_parameter("zoom", adrenaline * 0.05)
	post_mat.set_shader_parameter("vignette", 0.55 + adrenaline * 0.3)
	post_mat.set_shader_parameter("time_s", _t)
	if recording and act == "flat":
		pass
