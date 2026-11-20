extends Node
## After 开始游戏: the red sketch eye on dark paper. It never keeps still —
## it stretches, blurs, trembles, blinks, bleeds ink, gets scratched over,
## stares — while a broken piano plays (every note appears on screen) and a
## man whispers (every word seeps up in red). Over it: difficulty ->
## microphone calibration. Then the eye swells, the
## picture shatters like glass and the night begins.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const STORY := ["STORY_1", "STORY_2", "STORY_3", "STORY_4", "STORY_5", "STORY_6", "STORY_7", "STORY_8", "STORY_9", "STORY_10"]
const EPISODES := ["stretch", "blur", "tremble", "bleed", "scribble", "dilate", "stare", "flutter", "glitch", "look"]

var eye: SketchEye
var paper_mat: ShaderMaterial
var post_mat: ShaderMaterial
var notes: FloatingNotes
var subs: RedSubtitles
var piano: PianoPlayer
var whispers: WhisperPlayer
var mic: MicMonitor
var body: BodySounds
var ui: PregameUI
var shatter: ShatterFX
var drone: AudioStreamPlayer
var sfx: AudioStreamPlayer
var eye_layer: CanvasLayer
var fx_layer: CanvasLayer

var state := "difficulty"
var fade := 1.0
var fade_target := 0.0
var episode := ""
var ep_t := 0.0
var ep_len := 0.0
var ep_amt := 0.0
var last_episode := ""
var next_episode := 3.5
var next_piano := 1.5
var next_whisper := 4.0
var next_blink := 2.5
var next_glance := 1.0
var zoom_t := 0.0
var _stretch_dir := Vector2(1.0, 0.0)
var _beat := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _capture := false
var _look_target: Control


func _ready() -> void:
	_rng.randomize()
	_capture = OS.get_cmdline_user_args().has("--capture")
	eye_layer = CanvasLayer.new()
	eye_layer.layer = 0
	add_child(eye_layer)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_mat = ShaderMaterial.new()
	paper_mat.shader = load("res://shaders/paper.gdshader")
	bg.material = paper_mat
	eye_layer.add_child(bg)
	eye = SketchEye.new()
	eye.center = Vector2(0.56, 0.33)
	eye.unit = 0.29
	eye_layer.add_child(eye)
	notes = FloatingNotes.new()
	eye_layer.add_child(notes)
	subs = RedSubtitles.new()
	eye_layer.add_child(subs)

	fx_layer = CanvasLayer.new()
	fx_layer.layer = 1
	add_child(fx_layer)
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/screen_fx.gdshader")
	post.material = post_mat
	fx_layer.add_child(post)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	ui = PregameUI.new()
	ui_layer.add_child(ui)
	var top := CanvasLayer.new()
	top.layer = 20
	add_child(top)
	shatter = ShatterFX.new()
	top.add_child(shatter)

	mic = MicMonitor.new()
	add_child(mic)
	ui.mic = mic
	piano = PianoPlayer.new()
	piano.volume_db = -4.0
	add_child(piano)
	piano.note_played.connect(notes.on_note)
	whispers = WhisperPlayer.new()
	add_child(whispers)
	whispers.whispered.connect(_on_whisper)
	body = BodySounds.new()
	body.stress = 0.3
	body.breathing_enabled = false
	add_child(body)
	body.beat.connect(func(s: float) -> void: _beat = clampf(_beat + s * 0.6, 0.0, 1.0))
	drone = _player("Music", "res://assets/audio/drone_eye.ogg", -8.0)
	drone.play()
	sfx = _player("SFX", "", 0.0)

	ui.difficulty_chosen.connect(_on_difficulty)
	ui.back_requested.connect(_on_back)
	ui.calibration_done.connect(_on_calibrated)
	ui.story_finished.connect(_start_zoom)
	ui.control_focused.connect(func(c: Control) -> void: _look_target = c)
	shatter.finished.connect(_on_shattered)
	Settings.changed.connect(_apply_settings)
	_apply_settings()

	fade = 1.0
	fade_target = 0.0
	ui.show_difficulty()
	if _capture:
		fade = 0.0
		_dev_flags()
		add_child(load("res://scripts/dev_capture.gd").new())


func _player(bus: String, path: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = vol
	if path != "" and ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _sfx(path: String, vol := 0.0, pitch := 1.0) -> void:
	if ResourceLoader.exists(path):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = load(path)
		p.volume_db = vol
		p.pitch_scale = pitch
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


func _apply_settings() -> void:
	post_mat.set_shader_parameter("grain", 0.06 if Settings.film_grain else 0.0)
	post_mat.set_shader_parameter("brightness", lerpf(1.0, Settings.brightness, 0.5))


func _dev_flags() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--state="):
			var st := a.substr(8)
			if st == "calibrate":
				ui.diff_panel.visible = false
				ui.show_calibration()
				state = "calibrate"
			elif st == "story":
				ui.diff_panel.visible = false
				state = "story"
				ui.show_story(STORY)
			elif st == "zoom":
				ui.diff_panel.visible = false
				_start_zoom()
		elif a.begins_with("--episode="):
			_start_episode(a.substr(10))
		elif a.begins_with("--bleed="):
			eye.bleed = float(a.substr(8))


# ---------------------------------------------------------------------------
# flow
# ---------------------------------------------------------------------------
func _on_difficulty(i: int) -> void:
	Settings.difficulty = i
	Settings.save_settings()
	if Settings.mic_enabled:
		state = "calibrate"
		ui.show_calibration()
	else:
		_on_calibrated(false)


func _on_calibrated(use_mic: bool) -> void:
	# the backstory is told inside the game now (the phone call); straight in
	Settings.mic_this_run = use_mic
	_start_zoom()


func _on_back() -> void:
	state = "leaving"
	fade_target = 1.0
	await get_tree().create_timer(0.9).timeout
	get_tree().change_scene_to_file(MENU_SCENE)


func _start_zoom() -> void:
	state = "zoom"
	zoom_t = 0.0
	episode = ""
	piano.stop_all(0.6)
	whispers.whisper(12, 0.0, -2.0)
	body.stress = 0.7
	_sfx("res://assets/audio/whoosh.ogg", -6.0, 0.6)


func _do_shatter() -> void:
	state = "shatter"
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	eye_layer.visible = false
	fx_layer.visible = false
	var pupil_px := eye.pupil_screen_pos()
	shatter.shatter(tex, pupil_px / get_viewport().get_visible_rect().size)
	_sfx("res://assets/audio/glass_shatter.ogg", 0.0)
	drone.stop()
	body.enabled = false


func _on_shattered() -> void:
	await get_tree().create_timer(0.8).timeout
	if ResourceLoader.exists(GAME_SCENE):
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _on_whisper(line: int, pan: float, dur: float) -> void:
	if Settings.subtitles or true:
		subs.show_line("WHISPER_%d" % line, pan, dur)
	eye.gaze_target = Vector2(clampf(pan, -1.0, 1.0) * 0.35, 0.0)


# ---------------------------------------------------------------------------
# the eye's moods
# ---------------------------------------------------------------------------
func _start_episode(name: String) -> void:
	episode = name
	last_episode = name
	ep_t = 0.0
	ep_len = _rng.randf_range(3.0, 6.5)
	match name:
		"stretch":
			_stretch_dir = Vector2(1.0, 0.0) if _rng.randf() < 0.6 else Vector2(0.0, 1.0)
			_sfx("res://assets/audio/whoosh.ogg", -10.0, _rng.randf_range(0.5, 0.8))
		"blur":
			_sfx("res://assets/audio/ring.ogg", -18.0)
		"bleed":
			ep_len = _rng.randf_range(6.0, 9.0)
		"stare":
			ep_len = 4.0
			_sfx("res://assets/audio/stinger.ogg", -6.0)
			whispers.whisper([1, 2, 11][_rng.randi() % 3], 0.0, -1.0)
		"flutter":
			ep_len = 1.6
		"look":
			ep_len = _rng.randf_range(2.5, 4.0)


func _update_episodes(delta: float) -> void:
	if state == "zoom" or state == "shatter":
		return
	if episode == "":
		next_episode -= delta
		if next_episode <= 0.0:
			var pool: Array = EPISODES.duplicate()
			pool.erase(last_episode)
			_start_episode(pool[_rng.randi() % pool.size()])
		return
	ep_t += delta
	var att := minf(1.4, ep_len * 0.3)
	var rel := minf(2.0, ep_len * 0.4)
	ep_amt = smoothstep(0.0, att, ep_t) * (1.0 - smoothstep(ep_len - rel, ep_len, ep_t))
	match episode:
		"flutter":
			if not eye.is_blinking() and _rng.randf() < delta * 6.0:
				eye.do_blink(0.14)
		"dilate":
			eye.pupil_target = lerpf(0.42, 1.0, ep_amt)
		"stare":
			eye.gaze_target = Vector2.ZERO
			eye.wide = ep_amt
			eye.pupil_target = lerpf(0.42, 0.0, ep_amt)
		"bleed":
			eye.bleed = maxf(eye.bleed, smoothstep(0.0, ep_len * 0.7, ep_t))
		"look":
			var mp := get_viewport().get_mouse_position()
			eye.gaze_target = _gaze_towards(mp) * ep_amt
	if ep_t >= ep_len:
		episode = ""
		ep_amt = 0.0
		eye.wide = 0.0
		eye.pupil_target = 0.42
		next_episode = _rng.randf_range(2.0, 6.0)


func _gaze_towards(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var c := Vector2(eye.center.x * vp.x, eye.center.y * vp.y)
	var d := (screen_pos - c) / (vp.y * eye.unit)
	d.y = -d.y
	return Vector2(clampf(d.x * 0.15, -0.55, 0.55), clampf(d.y * 0.12, -0.18, 0.1))


func pupil_frac() -> Vector2:
	return eye.pupil_screen_pos() / get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	_t += delta
	fade = move_toward(fade, fade_target, delta * 0.8)
	_beat = maxf(0.0, _beat - delta * 3.0)
	_update_episodes(delta)

	# idle life: blinks, little glances (often at the option you are on)
	next_blink -= delta
	if next_blink <= 0.0 and state != "shatter":
		eye.do_blink(_rng.randf_range(0.18, 0.3), 0.0 if _rng.randf() < 0.8 else _rng.randf_range(0.2, 0.8))
		next_blink = _rng.randf_range(2.0, 6.5)
	next_glance -= delta
	if next_glance <= 0.0 and episode == "" and state != "zoom":
		if _look_target and _look_target.is_visible_in_tree() and _rng.randf() < 0.6:
			eye.gaze_target = _gaze_towards(_look_target.get_global_rect().get_center())
		else:
			eye.gaze_target = Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.1, 0.06))
		next_glance = _rng.randf_range(0.8, 3.0)
	if eye.bleed > 0.0 and episode != "bleed":
		eye.bleed = maxf(0.0, eye.bleed - delta * 0.12)

	# sound
	if state != "zoom" and state != "shatter":
		next_piano -= delta
		if next_piano <= 0.0:
			next_piano = piano.play_fragment() + _rng.randf_range(1.5, 5.0)
		next_whisper -= delta
		if next_whisper <= 0.0 and not whispers.is_playing():
			if _rng.randf() < 0.75:
				whispers.whisper()
			else:
				whispers.murmur()
			next_whisper = _rng.randf_range(6.0, 13.0)

	# map the episode onto the drawing and the screen
	var stretch := Vector2.ZERO
	var blur := 0.0
	var trem := 0.0
	var ghost := 0.0
	var glitch := 0.0
	var melt := 0.0
	match episode:
		"stretch":
			stretch = _stretch_dir * 0.35 * ep_amt
			melt = ep_amt * 0.8
		"blur":
			blur = ep_amt * 0.9
			ghost = ep_amt * 0.6
		"tremble":
			trem = ep_amt
		"glitch":
			glitch = ep_amt
			trem = ep_amt * 0.3
		"scribble":
			trem = ep_amt * 0.3
	eye.tremble = trem
	eye.scribble = ep_amt if episode == "scribble" else 0.0
	var zoom := 0.0
	if state == "zoom":
		zoom_t += delta
		var k := clampf(zoom_t / 2.6, 0.0, 1.0)
		zoom = pow(k, 2.2) * 6.0
		trem = k * 0.8
		eye.pupil_target = lerpf(0.5, 1.0, k)
		eye.tremble = k
		if zoom_t >= 2.6:
			_do_shatter()
	post_mat.set_shader_parameter("stretch", stretch)
	post_mat.set_shader_parameter("stretch_center", pupil_frac())
	post_mat.set_shader_parameter("melt", melt)
	post_mat.set_shader_parameter("blur", blur)
	post_mat.set_shader_parameter("ghost", ghost)
	post_mat.set_shader_parameter("tremble", trem)
	post_mat.set_shader_parameter("glitch", glitch)
	post_mat.set_shader_parameter("zoom", zoom)
	post_mat.set_shader_parameter("zoom_center", pupil_frac())
	post_mat.set_shader_parameter("glow", 0.55 + 0.25 * _beat)
	post_mat.set_shader_parameter("pulse", _beat * 0.6)
	post_mat.set_shader_parameter("vignette", 0.62)
	post_mat.set_shader_parameter("fade", fade)
	post_mat.set_shader_parameter("time_s", _t)
	paper_mat.set_shader_parameter("glow_center", pupil_frac())
	paper_mat.set_shader_parameter("time_s", _t)
	eye.veins = 0.5 + 0.4 * _beat
