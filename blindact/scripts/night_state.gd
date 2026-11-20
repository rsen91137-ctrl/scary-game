class_name NightState
extends Node
## What he thinks of you, and what is left of you at the scene.
##   suspicion  0..max  how sure he is that you can see (max -> he knows)
##   frame      0..100  how much of you is on her (prints, footprints...)
## Tells are judged here. The director opens "tests":
##   visual(id, pos)  something you must NOT react to. Tells: your view jerks
##                    (flinch), your gaze rests on it while he watches
##                    (fixation), the microphone hears you (a mute who makes
##                    a sound has seen something), your playing breaks off.
##   sound(id, pos)   a noise a blind man WOULD turn his head to. No turn = a tell.

signal exposed(reason: String)
signal suspicion_changed(v: float)
signal tell(kind: String, amount: float)

var player: Player
var mic: MicMonitor
var suspicion := 0.0
var frame := 0.0
var exposed_flag := false
var watched := false             # set by the director (his eyes on you)
var evidence := {}               # recorder, recording, camera, photos
var log_lines: Array[String] = []
var last_reason := ""
var mic_history := PackedFloat32Array()
var playing_piano := false
var piano_misses := 0            # misses since the last test began

var _tests: Array = []           # dicts
var _t := 0.0
var _hist_t := 0.0


func _ready() -> void:
	if mic:
		mic.sound_started.connect(_on_mic)


func max_suspicion() -> float:
	return float(Difficulty.get_value("suspicion_max"))


func visual(id: String, pos: Vector3, window := 2.5, weight := 1.0) -> void:
	var to := (pos - player.eye_pos()).normalized()
	_tests.append({"kind": "visual", "id": id, "pos": pos, "t0": _t, "window": window, "w": weight,
		"fix": 0.0, "flinched": false, "ang0": player.look_dir().angle_to(to), "misses0": piano_misses,
		"track": 0.0, "prev_ang": player.look_dir().angle_to(to)})


func sound(id: String, pos: Vector3, window := 2.4, weight := 1.0) -> void:
	var to := (pos - player.eye_pos()).normalized()
	_tests.append({"kind": "sound", "id": id, "pos": pos, "t0": _t, "window": window, "w": weight,
		"angle0": player.look_dir().angle_to(to), "ok": false})


func end_tests() -> void:
	_tests.clear()


func add_suspicion(amount: float, reason: String) -> void:
	if exposed_flag:
		return
	var a := amount * float(Difficulty.get_value("suspicion_gain"))
	suspicion = clampf(suspicion + a, 0.0, max_suspicion())
	if a > 0.0:
		last_reason = reason
		log_lines.append(reason)
		tell.emit(reason, a)
	suspicion_changed.emit(suspicion)
	if suspicion >= max_suspicion():
		expose(reason)


func expose(reason: String) -> void:
	if exposed_flag:
		return
	exposed_flag = true
	last_reason = reason
	exposed.emit(reason)


func add_frame(amount: float, reason: String) -> void:
	frame = clampf(frame + amount * float(Difficulty.get_value("frame_gain")), 0.0, 100.0)
	log_lines.append(reason)


func _on_mic(_db: float) -> void:
	if exposed_flag or not Settings.mic_this_run:
		return
	for t: Dictionary in _tests:
		if t.kind == "visual" and _t - float(t.t0) < float(t.window):
			# a mute who makes a sound has seen something
			if Settings.difficulty == 0:
				add_suspicion(55.0, "TELL_VOICE")
			else:
				expose("TELL_VOICE")
			return


func _process(delta: float) -> void:
	_t += delta
	if mic:
		_hist_t += delta
		if _hist_t > 0.05:
			_hist_t = 0.0
			mic_history.append(mic.level_db)
			if mic_history.size() > 160:
				mic_history = mic_history.slice(mic_history.size() - 160)
	if not exposed_flag and suspicion > 0.0:
		suspicion = maxf(0.0, suspicion - delta * float(Difficulty.get_value("suspicion_decay")) * (0.4 if watched else 1.0))
	var i := 0
	while i < _tests.size():
		var t: Dictionary = _tests[i]
		var age := _t - float(t.t0)
		if t.kind == "visual":
			_judge_visual(t, age, delta)
		else:
			_judge_sound(t, age)
		if age > float(t.window) or bool(t.get("done", false)):
			if t.kind == "sound" and not bool(t.ok):
				add_suspicion(18.0 * float(t.w), "TELL_NO_REACTION")
			_tests.remove_at(i)
		else:
			i += 1


func _judge_visual(t: Dictionary, age: float, delta: float) -> void:
	if player.eyes_closed:
		return
	var to: Vector3 = (Vector3(t.pos) - player.eye_pos()).normalized()
	var ang := player.look_dir().angle_to(to)
	# flinch: a jerk of the head right after it appeared, while it was in view
	if not bool(t.flinched) and age < 0.9 and player.ang_speed > 4.0 and ang < deg_to_rad(60.0):
		t.flinched = true
		add_suspicion(32.0 * float(t.w), "TELL_FLINCH")
	# fixation: you moved your gaze onto it and kept it there. Something put
	# in front of your face is not a tell; turning your eyes to it is.
	var moved_onto := float(t.ang0) > deg_to_rad(16.0)
	if ang < deg_to_rad(9.0) and moved_onto:
		t.fix = float(t.fix) + delta
		if float(t.fix) > float(Difficulty.get_value("fixate_time")):
			t.fix = -99.0
			add_suspicion(26.0 * float(t.w), "TELL_STARE")
	# tracking: your view keeps closing in on a thing that is moving
	if player.ang_speed > 0.6 and ang < float(t.prev_ang) - 0.002 and ang < deg_to_rad(25.0):
		t.track = float(t.track) + delta
		if float(t.track) > 0.8:
			t.track = -99.0
			add_suspicion(24.0 * float(t.w), "TELL_STARE")
	t.prev_ang = ang
	# the music broke off
	if playing_piano and piano_misses - int(t.misses0) >= 3 and age < 2.0:
		t.misses0 = 999
		add_suspicion(16.0 * float(t.w), "TELL_FUMBLE")


func _judge_sound(t: Dictionary, age: float) -> void:
	if bool(t.ok):
		return
	var to: Vector3 = (Vector3(t.pos) - player.eye_pos()).normalized()
	var ang := player.look_dir().angle_to(to)
	if ang < float(t.angle0) - deg_to_rad(20.0) or ang < deg_to_rad(40.0) and age > 0.25:
		t.ok = true
		t.done = true
