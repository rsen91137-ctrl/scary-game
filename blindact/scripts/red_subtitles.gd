class_name RedSubtitles
extends Control
## The whispers made visible: red words that seep onto the screen on the
## side the voice came from, letter by letter, trembling, then bleed away.

var _items: Array = []         # [Label, age, life, total_chars, ShaderMaterial]
var _rng := RandomNumberGenerator.new()
var _shader: Shader


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader = load("res://shaders/blood_text.gdshader")


func show_line(text_key: String, pan: float, duration: float) -> void:
	var l := Label.new()
	l.text = text_key
	l.add_theme_font_override("font", UIWidgets.font(true))
	var fs := int(size.y * _rng.randf_range(0.04, 0.058))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.85, 0.06, 0.04))
	l.add_theme_color_override("font_shadow_color", Color(0.25, 0.0, 0.0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible_ratio = 0.0
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("seed", _rng.randf() * 100.0)
	l.material = mat
	add_child(l)
	await get_tree().process_frame
	var sz := l.get_combined_minimum_size()
	var side := clampf(pan, -1.0, 1.0)
	var cx := size.x * (0.5 + side * _rng.randf_range(0.18, 0.3))
	var cy := size.y * _rng.randf_range(0.18, 0.78)
	l.position = Vector2(clampf(cx - sz.x * 0.5, 30.0, size.x - sz.x - 30.0), cy)
	l.rotation = _rng.randf_range(-0.06, 0.06)
	_items.append([l, 0.0, maxf(duration, 1.2) + 2.6, maxf(duration, 0.6), mat])


func _process(delta: float) -> void:
	var i := 0
	while i < _items.size():
		var it: Array = _items[i]
		var l: Label = it[0]
		it[1] = float(it[1]) + delta
		var age: float = it[1]
		var life: float = it[2]
		if age >= life:
			l.queue_free()
			_items.remove_at(i)
			continue
		l.visible_ratio = clampf(age / float(it[3]), 0.0, 1.0)
		var out := smoothstep(life - 1.6, life, age)
		(it[4] as ShaderMaterial).set_shader_parameter("dissolve", out)
		(it[4] as ShaderMaterial).set_shader_parameter("time_s", age)
		l.position.y -= delta * 6.0
		i += 1
