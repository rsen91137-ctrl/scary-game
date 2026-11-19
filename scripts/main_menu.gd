extends Node3D
## Main menu director.
## First person, an endless walk down the corridor from the photos. The
## corridor is a treadmill: stretches you pass are rebuilt ahead of you,
## sometimes as exact copies of what you just walked through (it repeats),
## sometimes as something new (it changes). Symptoms come and go at random —
## a violent heartbeat that shakes the screen, vertigo, tinnitus — over the
## score. The menu (开始游戏 / 设置) floats over it all.

const START_Z := 1.6
const PROLOGUE_SCENE := "res://scenes/prologue.tscn"

var corridor: CorridorBuilder
var world: WorldEnv
var walker: FPWalker
var body: BodySounds
var ui: MenuUI
var post_mat: ShaderMaterial
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var drone: AudioStreamPlayer
var stinger: AudioStreamPlayer
var ring: AudioStreamPlayer        # tinnitus
var vertigo: AudioStreamPlayer     # dizziness whoosh
var step_player: AudioStreamPlayer3D
var step_streams: Array[AudioStream] = []

var state := "walk"
var fade := 1.0
var fade_target := 0.0
var fade_speed := 0.35
var glitch := 0.0
var spike := 0.0                   # temporary stress from scares
var loop_t := 0.0

# symptom episodes ---------------------------------------------------------
var episode := ""                  # "" | heart | dizzy | tinnitus
var ep_t := 0.0
var ep_len := 0.0
var ep_attack := 2.0
var ep_release := 3.0
var next_episode := 6.0
var last_episode := ""
var heart_ep := 0.0                # 0..1 envelopes
var dizzy := 0.0
var tinnitus := 0.0
var _companion := ""               # a weaker second symptom riding along
var _companion_amt := 0.0

# repeating vs. changing corridor -----------------------------------------
var loop_phase := false            # every new stretch is the same stretch
var _loop_seed := 0
var _phase_left := 40.0
var _recent_seeds: Array[int] = []
var _event_timer := 14.0

var _amb_target := 1.0
var _music_target := 1.0
var _muffle_fx: Array = []         # [bus_idx, effect_idx]
var _rng := RandomNumberGenerator.new()
var _capture_mode := false


func _ready() -> void:
	_rng.randomize()
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	corridor = CorridorBuilder.new()
	corridor.name = "Corridor"
	corridor.seed_policy = _seed_for
	add_child(corridor)
	corridor.build(START_Z)

	world = WorldEnv.new()
	world.name = "World"
	add_child(world)
	world.setup()

	walker = FPWalker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.reset_to(START_Z)
	walker.footstep.connect(_on_footstep)

	body = BodySounds.new()
	body.name = "Body"
	body.walker = walker
	add_child(body)
	body.stress = 0.36
	body.bpm = 88.0

	for lamp: Node3D in corridor.lamps:
		lamp.connect("dropped", _on_lamp_dropped.bind(lamp))

	_setup_audio()
	_setup_post()
	_setup_ui()
	Settings.changed.connect(_apply_settings)
	_apply_settings()

	fade = 0.0 if _capture_mode else 1.0
	fade_target = 0.0
	fade_speed = 0.28
	ui.show_menu(0.0 if _capture_mode else 2.6)
	if _capture_mode:
		ui.snap_visible()
		add_child(load("res://scripts/dev_capture.gd").new())


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
func _stream(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func _player(bus: String, path: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = _stream(path)
	p.volume_db = vol
	add_child(p)
	return p


func _setup_audio() -> void:
	music = _player("Music", "res://assets/audio/bgm_corridor.ogg", -80.0)
	ambience = _player("Ambience", "res://assets/audio/amb_night.ogg", -80.0)
	drone = _player("Music", "res://assets/audio/riser.ogg", -6.0)
	stinger = _player("SFX", "res://assets/audio/stinger.ogg", 0.0)
	ring = _player("Body", "res://assets/audio/tinnitus.ogg", -80.0)
	vertigo = _player("Body", "res://assets/audio/dizzy.ogg", -80.0)
	step_player = AudioStreamPlayer3D.new()
	step_player.bus = "SFX"
	step_player.unit_size = 4.0
	walker.add_child(step_player)
	for i in range(1, 9):
		var s := _stream("res://assets/audio/step_%d.ogg" % i)
		if s:
			step_streams.append(s)
	for p: AudioStreamPlayer in [music, ambience, ring, vertigo]:
		if p.stream:
			p.play()
	# low-pass filters (added by Settings) used to muffle the world
	for bus_name: String in ["Music", "Ambience", "SFX"]:
		var bi := AudioServer.get_bus_index(bus_name)
		for k in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, k) is AudioEffectLowPassFilter:
				_muffle_fx.append([bi, k])


func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.visible = not OS.get_cmdline_user_args().has("--nopost")
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	rect.material = post_mat
	layer.add_child(rect)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = MenuUI.new()
	layer.add_child(ui)
	ui.start_requested.connect(_on_start_game)
	ui.quit_requested.connect(func() -> void: get_tree().quit())


func _apply_settings() -> void:
	walker.shake_scale = Settings.shake
	post_mat.set_shader_parameter("shake_amount", Settings.shake)
	post_mat.set_shader_parameter("grain", 0.05 if Settings.film_grain else 0.0)
	post_mat.set_shader_parameter("brightness", lerpf(1.0, Settings.brightness, 0.5))


# ---------------------------------------------------------------------------
# the corridor repeats itself / changes
# ---------------------------------------------------------------------------
func _seed_for(_seg: CorridorSegment) -> int:
	if loop_phase:
		return _loop_seed
	if not _recent_seeds.is_empty() and _rng.randf() < 0.2:
		return _recent_seeds[_rng.randi() % _recent_seeds.size()]   # déjà vu
	var s := _rng.randi()
	_recent_seeds.append(s)
	if _recent_seeds.size() > 6:
		_recent_seeds.pop_front()
	return s


func _update_phase(delta: float) -> void:
	_phase_left -= delta
	if _phase_left > 0.0:
		return
	loop_phase = not loop_phase
	if loop_phase:
		# lock onto the stretch just walked through: it will keep coming back,
		# and the night goes quiet while it does
		_loop_seed = _recent_seeds.back() if not _recent_seeds.is_empty() else _rng.randi()
		_phase_left = _rng.randf_range(25.0, 45.0)
		_amb_target = 0.25
		if stinger.stream:
			stinger.volume_db = -20.0
			stinger.pitch_scale = 0.5
			stinger.play()
	else:
		_phase_left = _rng.randf_range(35.0, 70.0)
		_amb_target = 1.0


# ---------------------------------------------------------------------------
# symptoms: heartbeat / vertigo / tinnitus, alternating at random
# ---------------------------------------------------------------------------
func _update_episodes(delta: float) -> void:
	if episode == "":
		next_episode -= delta
		if next_episode <= 0.0:
			_start_episode()
	else:
		ep_t += delta
		if ep_t >= ep_len:
			last_episode = episode
			episode = ""
			_companion = ""
			next_episode = _rng.randf_range(3.0, 9.0)
	var e := 0.0
	if episode != "":
		e = smoothstep(0.0, ep_attack, ep_t) * (1.0 - smoothstep(ep_len - ep_release, ep_len, ep_t))
	var targets := {"heart": 0.0, "dizzy": 0.0, "tinnitus": 0.0}
	if episode != "":
		targets[episode] = e
	if _companion != "":
		targets[_companion] = maxf(targets[_companion], e * _companion_amt)
	var k := 1.0 - exp(-delta * 4.0)
	heart_ep = lerpf(heart_ep, targets["heart"], k)
	dizzy = lerpf(dizzy, targets["dizzy"], k)
	tinnitus = lerpf(tinnitus, targets["tinnitus"], k)


func _start_episode(forced := "") -> void:
	# never the same symptom twice in a row; the heartbeat is a bit more likely
	var choices := ["heart", "dizzy", "tinnitus"]
	choices.erase(last_episode)
	if forced != "":
		episode = forced
	elif choices.has("heart") and _rng.randf() < 0.55:
		episode = "heart"
	else:
		choices.erase("heart")
		episode = choices[_rng.randi() % choices.size()]
	ep_t = 0.0
	match episode:
		"heart":
			ep_len = _rng.randf_range(8.0, 14.0)
			ep_attack = 1.5
			ep_release = 3.5
		"dizzy":
			ep_len = _rng.randf_range(9.0, 15.0)
			ep_attack = 3.0
			ep_release = 4.0
		_:
			ep_len = _rng.randf_range(6.0, 10.0)
			ep_attack = 1.2
			ep_release = 3.0
	# sometimes two symptoms overlap
	_companion = ""
	if _rng.randf() < 0.35:
		var others := ["heart", "dizzy", "tinnitus"]
		others.erase(episode)
		_companion = others[_rng.randi() % others.size()]
		_companion_amt = _rng.randf_range(0.35, 0.65)
	if forced != "":
		_companion = ""
		ep_len = 1000.0
		ep_attack = 0.3
	if _capture_mode:
		print("EPISODE ", episode, " +", _companion, " len=", snappedf(ep_len, 0.1))


# ---------------------------------------------------------------------------
# frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	loop_t += delta
	spike = maxf(0.0, spike - delta * 0.06)
	glitch = maxf(0.0, glitch - delta * 2.5)
	corridor.update_stream(walker.position.z)
	world.follow(walker.position.z)

	if state == "walk":
		_update_phase(delta)
		_update_episodes(delta)
		_random_events(delta)
		body.stress = clampf(0.36 + 0.6 * heart_ep + 0.18 * dizzy + 0.12 * tinnitus + spike, 0.0, 1.0)
	elif state == "starting":
		body.stress = move_toward(body.stress, 1.0, delta * 0.35)

	walker.tension = clampf(body.stress, 0.0, 1.0)
	walker.breath = body.breath_value
	walker.dizzy = dizzy

	# audio: tinnitus rings and muffles the world; vertigo hums and smears it
	var muffle := clampf(maxf(tinnitus * 0.95, dizzy * 0.55), 0.0, 1.0)
	for fx: Array in _muffle_fx:
		var lp := AudioServer.get_bus_effect(fx[0], fx[1]) as AudioEffectLowPassFilter
		lp.cutoff_hz = lerpf(20000.0, 420.0, pow(muffle, 0.7))
	if ring.stream:
		ring.volume_db = linear_to_db(maxf(tinnitus * 0.55, 0.0001))
	if vertigo.stream:
		vertigo.volume_db = linear_to_db(maxf(dizzy * 0.8, 0.0001))
		vertigo.pitch_scale = 0.92 + 0.08 * sin(loop_t * 0.37)
	fade = move_toward(fade, fade_target, delta * fade_speed)
	_mix(ambience, _amb_target * (1.0 - 0.6 * muffle), delta, -7.0)
	_mix(music, _music_target * (1.0 - 0.35 * muffle), delta, -3.0)

	post_mat.set_shader_parameter("pulse", body.pulse)
	post_mat.set_shader_parameter("tension", body.stress)
	post_mat.set_shader_parameter("dizzy", dizzy)
	post_mat.set_shader_parameter("tinnitus", tinnitus)
	post_mat.set_shader_parameter("fade", smoothstep(0.0, 1.0, fade))
	post_mat.set_shader_parameter("glitch", glitch)
	post_mat.set_shader_parameter("time_s", loop_t)
	ui.flicker = _nearest_lamp_level()
	ui.heart_pulse = body.pulse
	ui.external_glitch = glitch


func _mix(p: AudioStreamPlayer, target: float, delta: float, base_db: float) -> void:
	if p == null or p.stream == null:
		return
	var cur := db_to_linear(p.volume_db - base_db)
	cur = move_toward(cur, target, delta * 0.3)
	p.volume_db = linear_to_db(maxf(cur, 0.0001)) + base_db


func _nearest_lamp_level() -> float:
	var best := 1e9
	var lvl := 1.0
	for lamp: Node3D in corridor.lamps:
		if not lamp.visible:
			continue
		var d := lamp.global_position.distance_to(walker.global_position)
		if lamp.global_position.z < walker.global_position.z + 2.0 and d < best:
			best = d
			lvl = lamp.get("level")
	return lerpf(1.0, lvl, clampf(1.0 - best / 25.0, 0.0, 1.0))


## Small scares between the symptoms: the insects fall silent, a lamp ahead
## dies, a power dip runs down the corridor, the far light stutters.
func _random_events(delta: float) -> void:
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = _rng.randf_range(12.0, 26.0)
	match _rng.randi() % 4:
		0:
			_amb_target = 0.06
			spike += 0.12
			get_tree().create_timer(_rng.randf_range(6.0, 10.0)).timeout.connect(func() -> void: _amb_target = 1.0)
		1:
			var ahead := _lamp_ahead(4.0)
			if ahead:
				ahead.call("force", 0.0, _rng.randf_range(3.0, 7.0))
				spike += 0.1
		2:
			spike += 0.18
			var i := 0
			for lamp: Node3D in corridor.lamps:
				get_tree().create_timer(0.07 * i).timeout.connect(lamp.call.bind("force", 0.05, 0.5))
				i += 1
			if stinger.stream:
				stinger.volume_db = -15.0
				stinger.pitch_scale = 0.6
				stinger.play()
		_:
			walker.glance_at(corridor.end_lamp, 3.5)
			corridor.end_lamp.call("force", 0.12, 0.8)
			spike += 0.1


func _lamp_ahead(min_dist: float) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for lamp: Node3D in corridor.lamps:
		if not lamp.visible or lamp == corridor.end_lamp:
			continue
		var dz := walker.global_position.z - lamp.global_position.z
		if dz > min_dist and dz < bd:
			bd = dz
			best = lamp
	return best


# ---------------------------------------------------------------------------
# 开始游戏: everything fails, then the (placeholder) game
# ---------------------------------------------------------------------------
func _on_start_game() -> void:
	if state == "starting":
		return
	state = "starting"
	walker.walking = true
	spike = 0.4
	_amb_target = 0.0
	if drone.stream:
		drone.volume_db = -4.0
		drone.play()
	for k in 5:
		get_tree().create_timer(0.45 * k).timeout.connect(func() -> void:
			for lamp: Node3D in corridor.lamps:
				lamp.call("force", _rng.randf_range(0.0, 0.4), _rng.randf_range(0.05, 0.2)))
	get_tree().create_timer(2.8).timeout.connect(_blackout)


func _blackout() -> void:
	for lamp: Node3D in corridor.lamps:
		lamp.call("force", 0.0, 999.0)
	glitch = 1.0
	_music_target = 0.0
	if stinger.stream:
		stinger.volume_db = -2.0
		stinger.pitch_scale = 1.0
		stinger.play()
	body.hold_breath()
	fade_speed = 2.5
	fade_target = 0.94
	await get_tree().create_timer(2.6).timeout
	body.enabled = false
	fade_speed = 0.8
	fade_target = 1.0
	await get_tree().create_timer(1.6).timeout
	Settings.save_settings()
	get_tree().change_scene_to_file(PROLOGUE_SCENE)


# ---------------------------------------------------------------------------
# reactions
# ---------------------------------------------------------------------------
func _on_footstep(foot: int) -> void:
	if step_streams.is_empty() or walker.walk_factor < 0.2:
		return
	step_player.stream = step_streams[_rng.randi() % step_streams.size()]
	step_player.position = Vector3(-0.12 if foot == 0 else 0.12, 0.05, -0.2)
	step_player.volume_db = -9.0 + _rng.randf_range(-2.0, 1.0)
	step_player.pitch_scale = _rng.randf_range(0.92, 1.05) * (1.0 - 0.08 * dizzy)
	step_player.play()


func _on_lamp_dropped(strength: float, lamp: Node3D) -> void:
	if state != "walk":
		return
	var d := lamp.global_position.distance_to(walker.global_position)
	if d < 14.0:
		spike = minf(spike + 0.06 * strength * (1.0 - d / 14.0), 0.35)
		glitch = maxf(glitch, 0.12 * (1.0 - d / 14.0))
