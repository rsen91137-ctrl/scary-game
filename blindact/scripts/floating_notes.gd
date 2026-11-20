class_name FloatingNotes
extends Control
## Inked musical notes that appear with the broken piano: they bloom in,
## drift up and sideways with a slight sway, and fade. Broken notes appear
## cracked, shiver and drop instead of rising.

const NAMES := ["quarter", "eighth", "sixteenth", "beam", "half"]
var spawn_area := Rect2(0.12, 0.12, 0.8, 0.62)   # in screen fractions
var tint := Color(0.78, 0.07, 0.05)
var _tex := {}
var _items: Array = []       # [TextureRect, vel, life, age, spin, broken]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n: String in NAMES + ["broken", "drip"]:
		var p := "res://assets/ui/notes/note_%s.png" % n
		if ResourceLoader.exists(p):
			_tex[n] = load(p)


func on_note(midi: int, vel: float, broken: String) -> void:
	if _tex.is_empty():
		return
	var name: String = NAMES[_rng.randi() % NAMES.size()]
	if broken != "":
		name = "broken" if broken != "sour" else "drip"
	if not _tex.has(name):
		return
	var tr := TextureRect.new()
	tr.texture = _tex[name]
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := size.y * _rng.randf_range(0.05, 0.09) * (0.8 + 0.4 * vel)
	tr.size = Vector2(s, s)
	tr.pivot_offset = tr.size * 0.5
	# higher notes appear further right and higher up
	var fx := clampf(remap(float(midi), 33.0, 90.0, 0.0, 1.0) + _rng.randf_range(-0.25, 0.25), 0.0, 1.0)
	var fy := _rng.randf()
	tr.position = Vector2((spawn_area.position.x + spawn_area.size.x * fx) * size.x,
		(spawn_area.position.y + spawn_area.size.y * fy) * size.y) - tr.size * 0.5
	tr.rotation = _rng.randf_range(-0.35, 0.35)
	var c := tint
	c.a = 0.0
	tr.modulate = c
	tr.scale = Vector2(0.6, 0.6)
	add_child(tr)
	var vel_v := Vector2(_rng.randf_range(-18.0, 18.0), -_rng.randf_range(18.0, 40.0))
	if broken != "":
		vel_v = Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(30.0, 60.0))
	_items.append([tr, vel_v, _rng.randf_range(2.4, 4.2), 0.0, _rng.randf_range(-0.25, 0.25), broken != ""])


func _process(delta: float) -> void:
	var i := 0
	while i < _items.size():
		var it: Array = _items[i]
		var tr: TextureRect = it[0]
		it[3] = float(it[3]) + delta
		var age: float = it[3]
		var life: float = it[2]
		var k := age / life
		if k >= 1.0:
			tr.queue_free()
			_items.remove_at(i)
			continue
		var v: Vector2 = it[1]
		tr.position += v * delta + Vector2(sin(age * 2.3 + float(i)) * 12.0 * delta, 0.0)
		tr.rotation += float(it[4]) * delta
		var a := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.55, 1.0, k))
		var c := tint
		if bool(it[5]):
			tr.position += Vector2(_rng.randf_range(-2.0, 2.0), 0.0)
			c = c.darkened(0.25)
		c.a = a * 0.9
		tr.modulate = c
		var sc := lerpf(0.6, 1.0, smoothstep(0.0, 0.18, k))
		tr.scale = Vector2(sc, sc)
		i += 1
