class_name GameUI
extends Control
## In-game overlay: spoken lines, the inner voice, gradual hints, the
## interaction prompt, eyes-closed darkness, a REC dot, bait prompts (they
## lie), chapter titles, the pause menu and the ending / death screens.

signal resume_requested
signal menu_requested
signal retry_requested

var _sub: Label
var _sub_t := 0.0
var _think: Label
var _think_t := 0.0
var _think_len := 0.0
var _hint: Label
var _hint_t := 0.0
var _prompt: Label
var _eyes: ColorRect
var _rec: Label
var _fake: Label
var _fake_t := 0.0
var _title: Label
var _fade: ColorRect
var _fade_target := 0.0
var _fade_speed := 1.0
var _pause: Control
var _end: Control
var _end_title: Label
var _end_body: Label
var _end_why: Label
var _graph: Control
var _graph_data: PackedFloat32Array = PackedFloat32Array()
var _graph_thr := -40.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eyes = ColorRect.new()
	_eyes.color = Color(0.015, 0.0, 0.0, 0.0)
	_eyes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_eyes)
	_sub = _mk_label(30, Color(0.92, 0.88, 0.84), 0.05, 0.95, 0.83, 0.93)
	_think = _mk_label(28, Color(0.68, 0.66, 0.64, 0.95), 0.12, 0.88, 0.7, 0.8)
	_hint = _mk_label(22, Color(0.85, 0.3, 0.25, 0.9), 0.2, 0.8, 0.05, 0.11)
	_prompt = _mk_label(22, Color(0.85, 0.82, 0.78, 0.85), 0.35, 0.65, 0.58, 0.63)
	_fake = _mk_label(56, Color(1.0, 0.15, 0.1), 0.2, 0.8, 0.62, 0.74)
	_fake.visible = false
	_title = _mk_label(64, Color(0.86, 0.82, 0.78), 0.1, 0.9, 0.4, 0.55)
	_title.modulate.a = 0.0
	_rec = _mk_label(22, Color(0.9, 0.12, 0.08), 0.84, 0.98, 0.03, 0.08)
	_rec.text = "● REC"
	_rec.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rec.visible = false
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_build_pause()
	_build_end()


func _mk_label(size: int, col: Color, l: float, r: float, t: float, b: float) -> Label:
	var lb := UIWidgets.label("", size, col)
	lb.anchor_left = l
	lb.anchor_right = r
	lb.anchor_top = t
	lb.anchor_bottom = b
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("shadow_offset_x", 2)
	lb.add_theme_constant_override("shadow_offset_y", 2)
	add_child(lb)
	return lb


# ---- lines --------------------------------------------------------------------
func say(speaker_key: String, line_key: String, secs := 3.5) -> void:
	if not Settings.subtitles:
		return
	var who := tr(speaker_key) + "：" if speaker_key != "" else ""
	_sub.text = who + tr(line_key)
	_sub.modulate.a = 1.0
	_sub_t = secs


func think(line_key: String, secs := 4.0) -> void:
	_think.text = tr(line_key)
	_think.visible_ratio = 0.0
	_think.modulate.a = 1.0
	_think_t = 0.0
	_think_len = secs


func hint(line_key: String, secs := 5.0) -> void:
	_hint.text = tr(line_key)
	_hint.modulate.a = 1.0
	_hint_t = secs


func prompt(text: String) -> void:
	_prompt.text = text


func rec(on: bool) -> void:
	_rec.visible = on


func fake_prompt(text_key: String, secs := 2.0) -> void:
	_fake.text = tr(text_key)
	_fake.visible = true
	_fake_t = secs


func chapter(key: String, secs := 3.0) -> void:
	_title.text = tr(key)
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.0)
	tw.tween_interval(secs)
	tw.tween_property(_title, "modulate:a", 0.0, 1.2)


func fade_to(a: float, secs := 1.0) -> void:
	_fade_target = a
	_fade_speed = 1.0 / maxf(secs, 0.01)


func fade_now(a: float) -> void:
	_fade.color.a = a
	_fade_target = a


func eyes(closed: bool, pulse := 0.0) -> void:
	_eyes.color.a = move_toward(_eyes.color.a, 0.985 if closed else 0.0, 0.25)
	_eyes.color.r = 0.015 + pulse * 0.05


func _process(delta: float) -> void:
	_t += delta
	_fade.color.a = move_toward(_fade.color.a, _fade_target, delta * _fade_speed)
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t <= 0.6:
			_sub.modulate.a = maxf(_sub_t / 0.6, 0.0)
	if _think_len > 0.0:
		_think_t += delta
		_think.visible_ratio = clampf(_think_t / maxf(_think.text.length() * 0.06, 0.01), 0.0, 1.0)
		if _think_t > _think_len:
			_think.modulate.a = maxf(0.0, 1.0 - (_think_t - _think_len) / 0.8)
	if _hint_t > 0.0:
		_hint_t -= delta
		_hint.modulate.a = clampf(_hint_t / 0.8, 0.0, 1.0)
	if _fake_t > 0.0:
		_fake_t -= delta
		_fake.modulate.a = 0.6 + 0.4 * sin(_t * 30.0)
		_fake.position.x = _rng.randf_range(-4.0, 4.0)
		if _fake_t <= 0.0:
			_fake.visible = false
	if _rec.visible:
		_rec.modulate.a = 0.6 + 0.4 * (1.0 if fmod(_t, 1.0) < 0.6 else 0.0)


# ---- pause ------------------------------------------------------------------------
func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_theme_constant_override("separation", 16)
	_pause.add_child(v)
	var b1 := HorrorButton.new("PAUSE_RESUME", 38)
	var b2 := HorrorButton.new("PAUSE_MENU", 32)
	b1.pressed.connect(func() -> void: resume_requested.emit())
	b2.pressed.connect(func() -> void: menu_requested.emit())
	v.add_child(b1)
	v.add_child(b2)
	_pause.set_meta("first", b1)


func show_pause(on: bool) -> void:
	_pause.visible = on
	if on:
		(_pause.get_meta("first") as Control).grab_focus.call_deferred()


func paused() -> bool:
	return _pause.visible


# ---- endings --------------------------------------------------------------------
func _build_end() -> void:
	_end = Control.new()
	_end.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end.visible = false
	add_child(_end)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end.add_child(bg)
	_end_title = UIWidgets.label("", 60, Color(0.85, 0.12, 0.08), true, 8)
	_end_title.anchor_left = 0.1
	_end_title.anchor_right = 0.9
	_end_title.anchor_top = 0.12
	_end_title.anchor_bottom = 0.24
	_end.add_child(_end_title)
	_end_body = UIWidgets.label("", 28, Color(0.86, 0.82, 0.78))
	_end_body.anchor_left = 0.15
	_end_body.anchor_right = 0.85
	_end_body.anchor_top = 0.26
	_end_body.anchor_bottom = 0.46
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end.add_child(_end_body)
	_end_why = UIWidgets.label("", 22, Color(0.7, 0.66, 0.62))
	_end_why.anchor_left = 0.15
	_end_why.anchor_right = 0.85
	_end_why.anchor_top = 0.47
	_end_why.anchor_bottom = 0.6
	_end_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_why.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_end.add_child(_end_why)
	_graph = Control.new()
	_graph.anchor_left = 0.25
	_graph.anchor_right = 0.75
	_graph.anchor_top = 0.61
	_graph.anchor_bottom = 0.74
	_graph.draw.connect(_draw_graph)
	_end.add_child(_graph)
	var h := HBoxContainer.new()
	h.anchor_left = 0.2
	h.anchor_right = 0.8
	h.anchor_top = 0.8
	h.anchor_bottom = 0.9
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 60)
	_end.add_child(h)
	var b1 := HorrorButton.new("END_RETRY", 32)
	var b2 := HorrorButton.new("PAUSE_MENU", 32)
	b1.pressed.connect(func() -> void: retry_requested.emit())
	b2.pressed.connect(func() -> void: menu_requested.emit())
	h.add_child(b1)
	h.add_child(b2)
	_end.set_meta("first", b1)


## why: plain text lines (already translated); graph: mic dB history.
func show_end(title_key: String, body_key: String, why := "", graph := PackedFloat32Array(), thr := -40.0) -> void:
	_end_title.text = tr(title_key)
	_end_body.text = tr(body_key)
	_end_why.text = why
	_graph_data = graph
	_graph_thr = thr
	_graph.visible = graph.size() > 2
	_end.visible = true
	_end.modulate.a = 0.0
	create_tween().tween_property(_end, "modulate:a", 1.0, 1.5)
	(_end.get_meta("first") as Control).grab_focus.call_deferred()


func _draw_graph() -> void:
	if _graph_data.size() < 2:
		return
	var w := _graph.size.x
	var h := _graph.size.y
	_graph.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.05))
	var pts := PackedVector2Array()
	for i in _graph_data.size():
		var k := clampf(remap(_graph_data[i], -75.0, -10.0, 0.0, 1.0), 0.0, 1.0)
		pts.append(Vector2(w * float(i) / float(_graph_data.size() - 1), h * (1.0 - k)))
	_graph.draw_polyline(pts, Color(0.9, 0.85, 0.8, 0.9), 2.0, true)
	var ty := h * (1.0 - clampf(remap(_graph_thr, -75.0, -10.0, 0.0, 1.0), 0.0, 1.0))
	_graph.draw_line(Vector2(0, ty), Vector2(w, ty), Color(0.9, 0.12, 0.08, 0.8), 1.5)
	_graph.draw_string(UIWidgets.font(), Vector2(4, ty - 6), tr("END_MIC_LINE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.2, 0.15))
