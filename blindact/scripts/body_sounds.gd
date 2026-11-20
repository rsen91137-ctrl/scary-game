class_name BodySounds
extends Node
## The protagonist's body: a heartbeat that drives the screen shake and the
## post-process pulse, and breathing that turns into panting with stress.
## Everything plays on the dry "Body" bus so it feels inside your head.

signal beat(strength: float)

var walker: Node               # anything with heartbeat_kick(strength)
var stress := 0.0             # 0 calm .. 1 panic (set by the director)
var bpm := 68.0
var pulse := 0.0              # 0..1 envelope for the post shader
var breath_value := 0.0       # -1..1 chest position for the camera
var enabled := true
var breathing_enabled := true

var _beat_timer := 0.8
var _dub_timer := -1.0
var _lub_streams: Array[AudioStream] = []
var _dub_streams: Array[AudioStream] = []
var _hb_players: Array[AudioStreamPlayer] = []
var _hb_idx := 0
var _breath: Dictionary = {}  # set -> {"in": [...], "out": [...]}
var _br_player: AudioStreamPlayer
var _br_state := 2            # 0 inhale, 1 exhale, 2 pause
var _br_timer := 1.0
var _br_len := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Body"
		add_child(p)
		_hb_players.append(p)
	_br_player = AudioStreamPlayer.new()
	_br_player.bus = "Body"
	add_child(_br_player)
	for v in ["", "_hard"]:
		var l := _load("res://assets/audio/heart_lub%s.ogg" % v)
		var d := _load("res://assets/audio/heart_dub%s.ogg" % v)
		if l:
			_lub_streams.append(l)
		if d:
			_dub_streams.append(d)
	for set_name: String in ["calm", "heavy", "pant"]:
		var ins: Array[AudioStream] = []
		var outs: Array[AudioStream] = []
		for i in range(1, 5):
			var a := _load("res://assets/audio/breath_%s_in_%d.ogg" % [set_name, i])
			var b := _load("res://assets/audio/breath_%s_out_%d.ogg" % [set_name, i])
			if a:
				ins.append(a)
			if b:
				outs.append(b)
		_breath[set_name] = {"in": ins, "out": outs}


func _load(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func target_bpm() -> float:
	return lerpf(66.0, 152.0, pow(clampf(stress, 0.0, 1.0), 1.15))


func _process(delta: float) -> void:
	var tb := target_bpm()
	bpm = move_toward(bpm, tb, delta * (14.0 if tb > bpm else 4.0))
	pulse = maxf(0.0, pulse - delta * (3.2 + bpm / 60.0))
	if enabled:
		var interval := 60.0 / bpm
		_beat_timer -= delta
		if _beat_timer <= 0.0:
			_beat_timer += interval
			_lub()
			_dub_timer = clampf(interval * 0.34, 0.17, 0.3)
		if _dub_timer > 0.0:
			_dub_timer -= delta
			if _dub_timer <= 0.0:
				_dub()
	_update_breathing(delta)


func _strength() -> float:
	return 0.4 + 1.05 * pow(clampf(stress, 0.0, 1.0), 1.3)


func _play_hb(streams: Array[AudioStream], vol_db: float, pitch: float) -> void:
	if streams.is_empty():
		return
	var hard := stress > 0.55 and streams.size() > 1
	var p := _hb_players[_hb_idx]
	_hb_idx = (_hb_idx + 1) % _hb_players.size()
	p.stream = streams[1 if hard else 0]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func _lub() -> void:
	var s := _strength()
	_play_hb(_lub_streams, lerpf(-9.0, 1.5, clampf(stress, 0.0, 1.0)), _rng.randf_range(0.97, 1.03))
	pulse = clampf(pulse + 0.55 * s, 0.0, 1.0)
	if walker and walker.has_method("heartbeat_kick"):
		walker.call("heartbeat_kick", s)
	beat.emit(s)


func _dub() -> void:
	var s := _strength() * 0.55
	_play_hb(_dub_streams, lerpf(-12.0, -1.5, clampf(stress, 0.0, 1.0)), _rng.randf_range(0.97, 1.03))
	pulse = clampf(pulse + 0.35 * s, 0.0, 1.0)
	if walker and walker.has_method("heartbeat_kick"):
		walker.call("heartbeat_kick", s * 0.6)
	beat.emit(s)


func _breath_set() -> String:
	if stress < 0.3:
		return "calm"
	elif stress < 0.62:
		return "heavy"
	return "pant"


func _update_breathing(delta: float) -> void:
	_br_timer -= delta
	var k := clampf(1.0 - _br_timer / maxf(_br_len, 0.01), 0.0, 1.0)
	match _br_state:
		0:
			breath_value = sin(k * PI * 0.5)
		1:
			breath_value = cos(k * PI * 0.5) * 1.15 - 0.15
		_:
			breath_value = lerpf(breath_value, 0.0, 1.0 - exp(-delta * 3.0))
	if _br_timer > 0.0:
		return
	var set_name := _breath_set()
	var s: Dictionary = _breath.get(set_name, {})
	var vol := -13.0 if set_name == "calm" else (-8.0 if set_name == "heavy" else -4.5)
	match _br_state:
		0:
			_br_state = 1
			_br_len = _play_breath(s.get("out", []), vol)
			if _br_len <= 0.0:
				_br_len = lerpf(2.2, 0.55, stress)
		1:
			_br_state = 2
			_br_len = lerpf(1.1, 0.04, clampf(stress * 1.4, 0.0, 1.0)) * _rng.randf_range(0.7, 1.3)
		_:
			_br_state = 0
			_br_len = _play_breath(s.get("in", []), vol)
			if _br_len <= 0.0:
				_br_len = lerpf(1.6, 0.5, stress)
	_br_timer = _br_len


func _play_breath(streams: Array, vol_db: float) -> float:
	if not breathing_enabled or streams.is_empty():
		return -1.0
	var st: AudioStream = streams[_rng.randi() % streams.size()]
	_br_player.stream = st
	_br_player.volume_db = vol_db + _rng.randf_range(-1.5, 1.0)
	_br_player.pitch_scale = _rng.randf_range(0.96, 1.04)
	_br_player.play()
	return st.get_length() / _br_player.pitch_scale


func hold_breath() -> void:
	_br_player.stop()
	_br_state = 2
	_br_timer = 3.5
	_br_len = 3.5
