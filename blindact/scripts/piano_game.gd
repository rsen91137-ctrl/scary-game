class_name PianoGame
extends Control
## Playing for him. Four lanes (D F J K) at the bottom of the screen: the
## melody falls towards the line, the left hand plays itself. A blind
## pianist plays from memory, so the lanes are faint, like muscle memory.
## Misses leave holes in the music; wrong keys sound sour; stopping is noticed.
## Songs are public domain (Satie, Chopin), simplified.

signal hit(lane: int)
signal missed(lane: int)
signal stopped
signal finished

const KEYS := [KEY_D, KEY_F, KEY_J, KEY_K]
const KEY_NAMES := ["D", "F", "J", "K"]
const LEAD := 1.7

var piano: PianoPlayer
var active := false
var shake := 0.0                  # 0..1 trembling hands (from his heartbeat)
var t := 0.0
var notes: Array = []             # [time, lane, midi, state 0 pending / 1 hit / 2 miss]
var acc: Array = []               # [time, midi, done]
var length := 0.0
var _last_press := 0.0
var _stopped_flag := false
var _miss_streak := 0
var _flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


static func gymnopedie() -> Dictionary:
	var beat := 0.82
	var mel := [
		[4, 1, 78], [4, 2, 81], [5, 0, 79], [5, 1, 78], [5, 2, 73], [6, 0, 71], [6, 1, 73], [6, 2, 74],
		[7, 0, 69], [8, 0, 66],
		[10, 1, 78], [10, 2, 81], [11, 0, 79], [11, 1, 78], [11, 2, 73], [12, 0, 71], [12, 1, 73], [12, 2, 74],
		[13, 0, 69], [14, 0, 73], [15, 0, 78], [16, 0, 76],
		[18, 1, 78], [18, 2, 81], [19, 0, 79], [19, 1, 78], [19, 2, 73], [20, 0, 71], [20, 1, 73], [20, 2, 74],
		[21, 0, 69], [22, 0, 66], [23, 1, 69], [23, 2, 71], [24, 0, 73], [24, 2, 74], [25, 0, 71], [26, 0, 66],
	]
	var accs := []
	for bar in 28:
		var a := bar % 2 == 0
		accs.append([bar * 3 * beat, 43 if a else 38])
		for m: int in ([59, 62, 66] if a else [57, 61, 66]):
			accs.append([(bar * 3 + 1) * beat, m])
	var out := []
	for m: Array in mel:
		out.append([(int(m[0]) * 3 + int(m[1])) * beat, int(m[2])])
	return {"melody": out, "acc": accs, "length": 28 * 3 * beat}


static func prelude() -> Dictionary:
	var beat := 0.95
	var mel := [
		[0, 0, 71, 2], [0, 2, 72, 1], [0, 3, 71, 1], [1, 0, 71, 4], [2, 0, 71, 2], [2, 2, 72, 1], [2, 3, 71, 1],
		[3, 0, 71, 4], [4, 0, 71, 2], [4, 2, 72, 1], [4, 3, 71, 1], [5, 0, 70, 2], [5, 2, 71, 1], [5, 3, 70, 1],
		[6, 0, 69, 4], [7, 0, 69, 2], [7, 2, 71, 1], [7, 3, 69, 1], [8, 0, 67, 2], [8, 2, 66, 1], [8, 3, 67, 1],
		[9, 0, 69, 2], [9, 2, 72, 2], [10, 0, 71, 4], [11, 0, 64, 4],
	]
	var chords := [[55, 59, 64], [54, 57, 64], [54, 57, 63], [54, 57, 63], [53, 57, 62], [52, 55, 61],
		[52, 55, 60], [51, 54, 60], [52, 55, 59], [50, 54, 60], [47, 54, 59], [52, 55, 59]]
	var accs := []
	for bar in chords.size():
		for e in 8:
			var tt := (bar * 4 + e * 0.5) * beat
			for m: int in chords[bar]:
				accs.append([tt, m])
	var out := []
	for m: Array in mel:
		out.append([(int(m[0]) * 4 + int(m[1])) * beat, int(m[2])])
	return {"melody": out, "acc": accs, "length": chords.size() * 4 * beat}


func start(song: Dictionary) -> void:
	notes.clear()
	acc.clear()
	var lo := 999
	var hi := -999
	for m: Array in song.melody:
		lo = mini(lo, int(m[1]))
		hi = maxi(hi, int(m[1]))
	for m: Array in song.melody:
		var lane := clampi(int(floor(float(int(m[1]) - lo) / float(hi - lo + 1) * 4.0)), 0, 3)
		notes.append([float(m[0]) + LEAD, lane, int(m[1]), 0])
	for a: Array in song.acc:
		acc.append([float(a[0]) + LEAD, int(a[1]), false])
	length = float(song.length) + LEAD
	t = 0.0
	_last_press = 0.0
	_stopped_flag = false
	_miss_streak = 0
	active = true
	visible = true


func stop() -> void:
	active = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	var lane := KEYS.find(k)
	if lane < 0:
		return
	_last_press = t
	_stopped_flag = false
	_flash[lane] = 1.0
	var best := -1
	var bd := 0.2
	for i in notes.size():
		var n: Array = notes[i]
		if int(n[3]) != 0 or int(n[1]) != lane:
			continue
		var d := absf(float(n[0]) - t)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		var n: Array = notes[best]
		n[3] = 1
		_miss_streak = 0
		_stopped_flag = false
		piano.play(int(n[2]), 0.62 + _rng.randf_range(-0.08, 0.08), "", _rng.randf_range(-6.0, 6.0) * shake)
		hit.emit(lane)
	else:
		# a wrong note: something sour and quiet
		piano.play(60 + lane * 3 + _rng.randi_range(-1, 1), 0.3, "sour" if _rng.randf() < 0.5 else "")
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for i in 4:
		_flash[i] = maxf(0.0, _flash[i] - delta * 4.0)
	if not active:
		return
	t += delta
	for a: Array in acc:
		if not bool(a[2]) and t >= float(a[0]):
			a[2] = true
			piano.play(int(a[1]), 0.36 + _rng.randf_range(-0.05, 0.05))
	for n: Array in notes:
		if int(n[3]) == 0 and t > float(n[0]) + 0.2:
			n[3] = 2
			missed.emit(int(n[1]))
			_miss_streak += 1
			# he notices when the melody stops: three notes in a row missing
			if _miss_streak >= 3 and not _stopped_flag:
				_stopped_flag = true
				stopped.emit()
	if t > length + 1.0:
		active = false
		visible = false
		finished.emit()
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var lw := 70.0
	var x0 := w * 0.5 - lw * 2.0
	var y_hit := h * 0.92
	var y_top := h * 0.62
	for i in 4:
		var x := x0 + lw * i
		draw_rect(Rect2(x + 4, y_top, lw - 8, y_hit - y_top), Color(1, 1, 1, 0.025 + _flash[i] * 0.06))
		draw_string(UIWidgets.font(), Vector2(x + lw * 0.5 - 7, y_hit + 32), KEY_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.76, 0.72, 0.5))
	draw_line(Vector2(x0, y_hit), Vector2(x0 + lw * 4, y_hit), Color(0.8, 0.15, 0.1, 0.55), 2.0)
	for n: Array in notes:
		if int(n[3]) != 0:
			continue
		var dt := float(n[0]) - t
		if dt > LEAD or dt < -0.25:
			continue
		var k := 1.0 - dt / LEAD
		var y := lerpf(y_top, y_hit, k)
		var jx := sin(t * 31.0 + float(n[0])) * 6.0 * shake
		var x := x0 + lw * int(n[1]) + 10 + jx
		var a := clampf(k * 1.4, 0.0, 0.55)
		draw_rect(Rect2(x, y - 6, lw - 20, 12), Color(0.9, 0.86, 0.8, a))
