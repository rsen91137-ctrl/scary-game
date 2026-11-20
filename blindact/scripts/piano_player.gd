class_name PianoPlayer
extends Node
## Plays the synthesised old upright (assets/audio/piano). Notes are taken
## from the nearest sample and pitch-shifted. Also composes "broken"
## fragments for the menus: half-remembered phrases that stumble, keys that
## stick, dead keys, sour unisons, reversed swells.
## Emits note_played for every note so the screen can show it.

signal note_played(midi: int, velocity: float, broken: String)

var bus := "Piano"
var volume_db := -6.0
var _samples := {}            # midi -> AudioStream
var _broken := {"thud": [], "buzz": [], "sour": []}
var _reversed: Array[AudioStream] = []
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _rng := RandomNumberGenerator.new()
var _queue: Array = []        # [time_left, midi, vel, broken]


func _ready() -> void:
	_rng.randomize()
	for m in range(33, 97, 3):
		var p := "res://assets/audio/piano/pn_%d.ogg" % m
		if ResourceLoader.exists(p):
			_samples[m] = load(p)
	for kind: String in ["thud", "buzz", "sour"]:
		for i in 6:
			var p := "res://assets/audio/piano/pnb_%s_%d.ogg" % [kind, i]
			if ResourceLoader.exists(p):
				(_broken[kind] as Array).append(load(p))
	for m: int in [36, 45, 51, 57, 63]:
		var p := "res://assets/audio/piano/pnr_%d.ogg" % m
		if ResourceLoader.exists(p):
			_reversed.append(load(p))
	for i in 14:
		var ap := AudioStreamPlayer.new()
		ap.bus = bus
		add_child(ap)
		_pool.append(ap)


func _next_player() -> AudioStreamPlayer:
	var ap := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	return ap


## Plays one note now. broken: "" | "thud" | "buzz" | "sour"
func play(midi: int, vel := 0.8, broken := "", detune := 0.0) -> AudioStreamPlayer:
	var ap := _next_player()
	if broken != "" and not (_broken[broken] as Array).is_empty():
		var arr: Array = _broken[broken]
		ap.stream = arr[_rng.randi() % arr.size()]
		ap.pitch_scale = pow(2.0, float(midi - 55) / 12.0 * 0.35) * _rng.randf_range(0.97, 1.03)
	else:
		var best := 57
		var bd := 999
		for m: int in _samples:
			if absi(m - midi) < bd:
				bd = absi(m - midi)
				best = m
		if not _samples.has(best):
			return ap
		ap.stream = _samples[best]
		ap.pitch_scale = pow(2.0, (float(midi - best) + detune / 100.0) / 12.0)
	ap.volume_db = volume_db + linear_to_db(clampf(vel, 0.05, 1.2))
	ap.play()
	note_played.emit(midi, vel, broken)
	return ap


func play_reversed(vel := 0.8) -> void:
	if _reversed.is_empty():
		return
	var ap := _next_player()
	ap.stream = _reversed[_rng.randi() % _reversed.size()]
	ap.pitch_scale = _rng.randf_range(0.85, 1.1)
	ap.volume_db = volume_db + linear_to_db(vel) - 2.0
	ap.play()


func schedule(delay: float, midi: int, vel := 0.8, broken := "") -> void:
	_queue.append([delay, midi, vel, broken])


func clear_queue() -> void:
	_queue.clear()


func stop_all(fade := 0.3) -> void:
	_queue.clear()
	for ap: AudioStreamPlayer in _pool:
		if ap.playing:
			var tw := create_tween()
			tw.tween_property(ap, "volume_db", -60.0, fade)
			tw.tween_callback(ap.stop)


func _process(delta: float) -> void:
	var i := 0
	while i < _queue.size():
		var q: Array = _queue[i]
		q[0] = float(q[0]) - delta
		if float(q[0]) <= 0.0:
			play(int(q[1]), float(q[2]), String(q[3]))
			_queue.remove_at(i)
		else:
			i += 1


# ---------------------------------------------------------------------------
# broken fragments for the menus
# ---------------------------------------------------------------------------
## Queues one random fragment and returns its length in seconds.
func play_fragment() -> float:
	var kind := _rng.randi() % 7
	var t := 0.0
	# A minor / harmonic minor material, an octave chosen at random
	var root := [45, 50, 52, 57][_rng.randi() % 4]
	var scale := [0, 2, 3, 5, 7, 8, 11, 12]
	match kind:
		0:  # a half-remembered lullaby phrase that stops in the wrong place
			var motif := [7, 5, 3, 2, 3, 0, -1, 0]
			var n := _rng.randi_range(3, motif.size())
			for i in n:
				t += _rng.randf_range(0.32, 0.7)
				var br := "sour" if _rng.randf() < 0.12 else ""
				schedule(t, root + 12 + motif[i], _rng.randf_range(0.4, 0.75), br)
			if _rng.randf() < 0.5:
				t += 0.5
				schedule(t, root + 12 + motif[n - 1] + 1, 0.9, "thud")
		1:  # a key that sticks: the same note, slower and slower
			var m: int = root + 12 + scale[_rng.randi() % scale.size()]
			var gap := 0.18
			for i in _rng.randi_range(4, 8):
				t += gap
				gap *= 1.35
				schedule(t, m, 0.75 - i * 0.05, "")
		2:  # a dissonant cluster stab, then the bass dropping
			for d: int in [0, 1, 6]:
				schedule(0.0, root + 12 + d, 0.9, "")
			t = 1.6
			schedule(t, root - 12, 1.0, "")
		3:  # dead keys
			for i in _rng.randi_range(2, 4):
				t += _rng.randf_range(0.4, 1.0)
				schedule(t, root + _rng.randi_range(-5, 12), 1.0, "thud")
		4:  # a loose string buzzing under a falling third
			schedule(0.0, root + 15, 0.7, "")
			t = 0.6
			schedule(t, root + 12, 0.75, "buzz")
		5:  # reversed swell into a soft low note
			play_reversed(0.8)
			t = 3.6
			schedule(t, root - 5, 0.6, "")
		_:  # a broken arpeggio, sour on top
			var chord := [0, 3, 7, 11, 14]
			for i in chord.size():
				t += _rng.randf_range(0.14, 0.3)
				schedule(t, root + chord[i], 0.6, "sour" if i == chord.size() - 1 else "")
	return t + 1.5
