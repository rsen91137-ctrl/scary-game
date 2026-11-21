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
var scare_until := -1.0          # after a scare your hands give you away
var _err_in_window := 0
var listening := false           # he is near enough to hear you (set by the director)
var his_head := Vector3.INF      # where his eyes are (INF: he is not there)
var comp_until := -1.0           # a scare just hit: your composure is being judged
var mic_gate_until := -1.0       # the game's own stinger in your microphone is not you
var _comp_w := 1.0
var _fumble_w := 1.0            # how much a slip at the keys costs in this window
var _comp_t0 := 0.0
var _comp_flinched := false
var _comp_froze := false
var _comp_speed0 := 0.0
var _voice_t := 0.0
var _voice_hit := 0.0
var _loud_t := 0.0
var _eye_t := 0.0
var _phantoms: Array = []        # sounds only you can hear

var _tests: Array = []           # dicts
var _t := 0.0
var _hist_t := 0.0


func _ready() -> void:
	if mic:
		mic.sound_started.connect(_on_mic)


func max_suspicion() -> float:
	return float(Difficulty.get_value("suspicion_max"))


func visual(id: String, pos: Vector3, window := 2.5, weight := 1.0) -> void:
	scare_window(window + 1.0)
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


## For `secs` from now, playing out of order at the piano is a tell.
func scare_window(secs: float, w := 1.0) -> void:
	if _t > scare_until:
		_err_in_window = 0
		_fumble_w = w
	else:
		_fumble_w = maxf(_fumble_w, w)
	scare_until = maxf(scare_until, _t + secs)


## A wrong key or a missed note. Right after a scare a pianist's hands that
## suddenly lose their order mean he saw something; otherwise it costs little.
func piano_error(kind: String) -> void:
	if kind == "miss":
		piano_misses += 1
	if not playing_piano or exposed_flag:
		return
	if _t < scare_until:
		_err_in_window += 1
		add_suspicion((7.0 + 2.0 * minf(_err_in_window, 4.0)) * _fumble_w, "TELL_FUMBLE")
	else:
		# sloppy playing alone makes him wary, never certain
		var room := max_suspicion() * 0.45 - suspicion
		if room > 0.0:
			add_suspicion(minf(1.5, room / float(Difficulty.get_value("suspicion_gain"))), "TELL_SLIP")


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
	pass    # the voice is judged every frame now (_judge_voice), not only in tests


## A scare just hit. For `secs` he reads you: a sound, a jerk of the head,
## feet that stop dead, hands that lose the beat.
func composure(secs: float, weight := 1.0) -> void:
	comp_until = maxf(comp_until, _t + secs)
	_comp_w = weight
	_comp_t0 = _t
	_comp_flinched = false
	_comp_froze = false
	_comp_speed0 = Vector2(player.velocity.x, player.velocity.z).length()
	mic_gate_until = _t + 0.3
	if playing_piano:
		# the things in your head come often: a slip after one costs less
		scare_window(secs, 0.8 if weight > 0.7 else 0.4)


## A sound that is only in your head: he heard nothing, so turning to it tells.
func phantom(pos: Vector3, window := 2.8) -> void:
	var to := (pos - player.eye_pos()).normalized()
	_phantoms.append({"pos": pos, "t0": _t, "window": window, "ang0": player.aim_dir().angle_to(to)})


## He hears you all night, not only when he is testing you. A sound costs; a
## sound right after a scare costs dear; a scream ends it.
func _judge_voice(delta: float) -> void:
	if mic == null or exposed_flag or not Settings.mic_this_run or not listening or _t < mic_gate_until:
		_voice_t = 0.0
		_loud_t = 0.0
		return
	var thr := mic.threshold_db()
	var lvl := mic.level_db
	var scream := maxf(Settings.mic_voice_db + 7.0, thr + 9.0)
	if lvl > scream:
		_loud_t += delta
		if _loud_t > 0.22:
			_loud_t = 0.0
			if Settings.difficulty == 0:
				add_suspicion(60.0, "TELL_SCREAM")
			else:
				expose("TELL_SCREAM")
			return
	else:
		_loud_t = maxf(0.0, _loud_t - delta * 2.0)
	if lvl > thr:
		_voice_t += delta
		if _voice_t > float(Difficulty.get_value("mic_min_len")) and _t > _voice_hit:
			_voice_hit = _t + 1.0
			if _t < comp_until:
				add_suspicion(34.0 * _comp_w, "TELL_GASP")
			else:
				add_suspicion(14.0, "TELL_VOICE")
	else:
		_voice_t = 0.0


func _judge_composure() -> void:
	if _t > comp_until or exposed_flag or player.eyes_closed or not watched:
		return
	var age := _t - _comp_t0
	# a jerk of the view, a human reaction time after it appeared
	if not _comp_flinched and age > 0.12 and age < 1.6 and player.ang_speed > 2.6:
		_comp_flinched = true
		add_suspicion(15.0 * _comp_w, "TELL_FLINCH")
	# walking, then rooted to the spot
	if not _comp_froze and age > 0.25 and age < 1.3 and _comp_speed0 > 0.8 and Vector2(player.velocity.x, player.velocity.z).length() < 0.15:
		_comp_froze = true
		add_suspicion(9.0 * _comp_w, "TELL_FROZE")


## A blind man does not hold another man's eyes.
func _judge_eyes(delta: float) -> void:
	if not watched or his_head == Vector3.INF or exposed_flag or player.eyes_closed or player.view_forced() \
			or not (player.mode == "walk" or player.mode == "seated"):
		_eye_t = maxf(0.0, _eye_t - delta)
		return
	var to := his_head - player.eye_pos()
	if to.length() < 4.0 and player.aim_dir().angle_to(to.normalized()) < deg_to_rad(6.5):
		_eye_t += delta
		if _eye_t > 1.4:
			_eye_t = 0.9
			add_suspicion(7.0, "TELL_EYES")
	else:
		_eye_t = maxf(0.0, _eye_t - delta * 2.0)


func _judge_phantoms() -> void:
	var i := 0
	while i < _phantoms.size():
		var ph: Dictionary = _phantoms[i]
		var to: Vector3 = (Vector3(ph.pos) - player.eye_pos()).normalized()
		var ang := player.aim_dir().angle_to(to)
		if watched and ang < float(ph.ang0) - deg_to_rad(28.0):
			add_suspicion(20.0, "TELL_PHANTOM")
			_phantoms.remove_at(i)
		elif _t - float(ph.t0) > float(ph.window):
			_phantoms.remove_at(i)
		else:
			i += 1


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
	_judge_voice(delta)
	_judge_composure()
	_judge_eyes(delta)
	_judge_phantoms()
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
	# (playing out of order right after it is judged in piano_error)


func _judge_sound(t: Dictionary, age: float) -> void:
	if bool(t.ok):
		return
	var to: Vector3 = (Vector3(t.pos) - player.eye_pos()).normalized()
	var ang := player.look_dir().angle_to(to)
	if ang < float(t.angle0) - deg_to_rad(20.0) or ang < deg_to_rad(40.0) and age > 0.25:
		t.ok = true
		t.done = true
